import AppKit
import Foundation
import VisaCore

/// What the recorder needs from `AppModel` to tag an event (design §5.12).
struct PerfRecorderContext {
    var mode: Mode
    var isPlaytest: Bool
}

/// Parent-facing summary of one recent play session (this launch only, memory).
struct PerfSessionSummary: Equatable, Identifiable {
    let id: String
    var start: Date
    var end: Date
    var rounds: Int
    var plays: Int
    var actors: Set<PerfActor>
}

/// D10 performance recorder (v0.20.0, ADR 0008). @MainActor glue between `AppModel` hooks
/// and the append-only `PerfEventStore`. File I/O runs on one private serial queue.
///
/// Hard rules: never touches `Session`, `update(_:)`, `storageFailed` or `message`; never
/// throws into the child flow; a write error only raises `onWriteFailed` (parent banner).
@MainActor
final class PerformanceRecorder {
    nonisolated let store: PerfEventStore
    private let queue = DispatchQueue(label: "family.visagames.perf-store", qos: .utility)
    private let launchID = UUID().uuidString
    private let appVersion: String
    private var seq = 0
    private var sessionClock = PerfSessionClock()
    private(set) var uat = PerfUATSwitch()
    private var lastWall: Date?
    private var lastContinuousSeconds: Double?

    var contextProvider: (() -> PerfRecorderContext)?
    var onWriteFailed: (() -> Void)?
    private var writeFailureReported = false

    private var round: (tracker: PerfRoundTracker, actor: PerfActor, session: String)?
    private var playtest: (tracker: PerfRoundTracker, actor: PerfActor, session: String)?
    private var play: (tracker: PerfPlayTracker, actor: PerfActor, session: String)?
    private var lastProgressMono: Double?
    private var visa: (id: String, source: PerfVisaSource, startedAt: Date)?
    private var knownVisits: [String] = []
    private var shownPage: (visit: String, page: Int, mono: Double)?
    private var pendingPick: [String: PerfValue]?
    private var lastResumeOffer: (video: String, position: Int, surface: String)?
    private(set) var recentSessions: [PerfSessionSummary] = []
    private(set) var excludedSessions: Set<String> = []

    static let visaMarkerKey = "VisaGames.perfVisaMarker.v1"
    static let progressEverySeconds: Double = 60

    nonisolated init(store: PerfEventStore = PerfEventStore(directory: PerfEventStore.defaultDirectory())) {
        self.store = store
        self.appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    // MARK: Envelope + write

    private static func monoNow() -> Double { ProcessInfo.processInfo.systemUptime }

    /// Continuous clock (includes sleep) — only used to flag wall-clock changes.
    private static func continuousNow() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }

    private var context: PerfRecorderContext {
        contextProvider?() ?? PerfRecorderContext(mode: .lock, isPlaytest: false)
    }

    func currentActor(isVideoEvent: Bool, now: Date = Date()) -> PerfActor {
        let ctx = context
        return PerfActorRule.resolve(
            mode: ctx.mode,
            isPlaytest: ctx.isPlaytest,
            isVideoEvent: isVideoEvent,
            uatOn: uat.isOn(at: now),
            visaSource: visa?.source
        )
    }

    /// Builds, tags and queues one event. `unit` pins actor + session for events that belong
    /// to an already-started round or play.
    @discardableResult
    private func emit(_ type: PerfEventType, _ fields: [String: PerfValue] = [:],
                      unit: (actor: PerfActor, session: String)? = nil,
                      actorOverride: PerfActor? = nil,
                      synchronize: Bool = false) -> (actor: PerfActor, session: String) {
        let now = Date()
        let mono = Self.monoNow()
        let ctx = context
        noteClockJump(now: now)
        let actor = unit?.actor ?? actorOverride ?? PerfActorRule.resolve(
            mode: ctx.mode,
            isPlaytest: ctx.isPlaytest,
            isVideoEvent: type.isVideoEvent,
            uatOn: uat.isOn(at: now),
            visaSource: visa?.source
        )
        let session: String
        if let unit {
            session = unit.session
        } else {
            let resolved = sessionClock.session(isParentMode: ctx.mode == .parent, now: now) { UUID().uuidString }
            session = resolved.id
            if let started = resolved.started {
                write(.sessionStart, ["reason": .string(started.rawValue)], actor: actor, session: session,
                      mode: ctx.mode, now: now, mono: mono, synchronize: false)
            }
        }
        write(type, fields, actor: actor, session: session, mode: ctx.mode, now: now, mono: mono,
              synchronize: synchronize)
        noteSessionActivity(type: type, actor: actor, session: session, now: now)
        return (actor, session)
    }

    private func write(_ type: PerfEventType, _ fields: [String: PerfValue], actor: PerfActor, session: String,
                       mode: Mode, now: Date, mono: Double, synchronize: Bool) {
        seq += 1
        let event = PerfEvent(
            type: type,
            timestamp: now,
            tz: PerfCodec.offsetString(TimeZone.current, at: now),
            mono: mono,
            launch: launchID,
            seq: seq,
            app: appVersion,
            actor: actor,
            mode: PerfActorRule.modeName(mode),
            session: session,
            fields: fields
        )
        let store = self.store
        queue.async { [weak self] in
            do {
                try store.append([event], synchronize: synchronize)
            } catch {
                VisaGamesLog.append("perf write FAILED — 表現紀錄未能儲存 \(error.localizedDescription)")
                Task { @MainActor in self?.reportWriteFailure() }
            }
        }
    }

    private func reportWriteFailure() {
        guard !writeFailureReported else { return }
        writeFailureReported = true
        onWriteFailed?()
    }

    private func noteClockJump(now: Date) {
        let continuous = Self.continuousNow()
        defer {
            lastWall = now
            lastContinuousSeconds = continuous
        }
        guard let lastWall, let lastContinuousSeconds else { return }
        let delta = now.timeIntervalSince(lastWall) - (continuous - lastContinuousSeconds)
        guard abs(delta) > 120 else { return }
        seq += 1
        let mono = Self.monoNow()
        let event = PerfEvent(
            type: .clockJump, timestamp: now, tz: PerfCodec.offsetString(TimeZone.current, at: now),
            mono: mono, launch: launchID, seq: seq, app: appVersion, actor: .system,
            mode: PerfActorRule.modeName(context.mode), session: sessionClock.current ?? "",
            fields: ["delta_s": .seconds(delta)]
        )
        let store = self.store
        queue.async { try? store.append([event]) }
    }

    private func noteSessionActivity(type: PerfEventType, actor: PerfActor, session: String, now: Date) {
        switch actor {
        case .child, .parentUAT, .parentTestVisa: break
        default: return
        }
        if let index = recentSessions.firstIndex(where: { $0.id == session }) {
            recentSessions[index].end = now
            recentSessions[index].actors.insert(actor)
            if type == .gameDealt { recentSessions[index].rounds += 1 }
            if type == .videoStart { recentSessions[index].plays += 1 }
        } else {
            recentSessions.insert(PerfSessionSummary(
                id: session, start: now, end: now,
                rounds: type == .gameDealt ? 1 : 0,
                plays: type == .videoStart ? 1 : 0,
                actors: [actor]
            ), at: 0)
            if recentSessions.count > 5 { recentSessions.removeLast(recentSessions.count - 5) }
        }
    }

    // MARK: Lifecycle

    func launch(recoveredPlay: Bool, visaEndsAt: Date?, allowlistIDs: [String],
                assignment: MissionGameAssignment) {
        if let visaEndsAt { recoverVisa(endsAt: visaEndsAt) } else { clearVisaMarker() }
        var assignmentFields: [String: PerfValue] = [:]
        for kind in ActivityCatalog.playableKinds {
            let stars = ChildDifficulty.allCases.filter { assignment.isEnabled(kind, star: $0) }
            assignmentFields[kind.rawValue] = .array(stars.map { .int($0.rawValue) })
        }
        emit(.appLaunch, [
            "recovered_play": .bool(recoveredPlay),
            "allowlist_ids": .strings(allowlistIDs),
            "assignment": .object(assignmentFields),
            "deal_mode": .string("off"),
            "visa_source": .optionalString(visa?.source.rawValue)
        ], actorOverride: .system)
        let store = self.store
        queue.async {
            do {
                let outcome = try PerfRetention.prune(store: store, now: Date())
                if !outcome.deleted.isEmpty {
                    VisaGamesLog.append("perf prune — 表現紀錄整理 folded=\(outcome.folded.count) deleted=\(outcome.deleted.count)")
                }
            } catch {
                VisaGamesLog.append("perf prune FAILED — \(error.localizedDescription)")
            }
        }
    }

    func terminate(reason: String) {
        if play != nil { endPlay(reason: .appTerminate, resumeSaved: false) }
        abandonRound(reason: "terminate")
        abandonPlaytest(reason: "terminate")
        emit(.appTerminate, ["reason": .string(reason)], actorOverride: .system, synchronize: true)
        queue.sync {}
    }

    func tick(now: Date) {
        if uat.expireIfNeeded(now: now) {
            emit(.uatMode, ["on": .bool(false), "reason": .string("auto_off")], actorOverride: .parent)
            VisaGamesLog.append("perf uat auto-off — 家長測試中自動關")
        }
        guard let open = play, open.actor != .parentPreview else { return }
        let mono = Self.monoNow()
        if mono - (lastProgressMono ?? open.tracker.startMono) >= Self.progressEverySeconds {
            lastProgressMono = mono
            emit(.videoProgress, open.tracker.progressFields(mono: mono), unit: (open.actor, open.session))
        }
    }

    // MARK: Parent mode + tools

    func parentEntered(fromMode: Mode) {
        let mono = Self.monoNow()
        round?.tracker.parentStarted(mono: mono)
        emit(.parentEnter, ["from_mode": .string(PerfActorRule.modeName(fromMode))], actorOverride: .parent)
    }

    func parentLeft(reason: String, toMode: Mode) {
        emit(.parentLeave, [
            "reason": .string(reason), "to_mode": .string(PerfActorRule.modeName(toMode))
        ], actorOverride: .parent)
        round?.tracker.parentEnded(mono: Self.monoNow())
    }

    func setUAT(on: Bool) {
        let now = Date()
        if on { uat.turnOn(now: now) } else { uat.turnOff() }
        emit(.uatMode, [
            "on": .bool(on),
            "until": .optionalString(uat.until.map(PerfCodec.formatTimestamp)),
            "reason": .string("parent")
        ], actorOverride: .parent)
    }

    func setSessionExcluded(_ session: String, excluded: Bool) {
        if excluded { excludedSessions.insert(session) } else { excludedSessions.remove(session) }
        emit(excluded ? .statsExclude : .statsInclude, ["target_session": .string(session)],
             actorOverride: .parent, synchronize: true)
    }

    func marker(_ what: String) {
        emit(.statsMarker, ["what": .string(what)], actorOverride: .parent, synchronize: true)
    }

    func allowlistChanged(op: String, video: String) {
        emit(.allowlistChange, ["op": .string(op), "video": .string(video)], actorOverride: .parent)
    }

    func assignmentChanged(kind: ActivityKind, star: Int, on: Bool) {
        emit(.configChange, [
            "what": .string("assignment"), "kind": .string(kind.rawValue),
            "star": .int(star), "value": .bool(on)
        ], actorOverride: .parent)
    }

    /// v0.21 表現: builds the report on the recorder queue (after any queued writes, so a
    /// just-tapped 唔計呢段 is already on disk), then hands it to main. Never on the main thread.
    func buildReport(window: PerfReportWindow, videoIDs: [String], titles: [String: String],
                     completion: @escaping @MainActor @Sendable (PerfReport) -> Void) {
        let store = self.store
        queue.async {
            let started = Date()
            let read = store.read()
            let report = PerfReportBuilder.build(
                events: read.events, rollup: store.loadRollup(),
                videos: videoIDs.map { (id: $0, title: titles[$0] ?? $0) },
                now: Date(), window: window, timeZone: store.timeZone
            )
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            VisaGamesLog.append("parent review — built \(window.rawValue) from \(read.events.count) events in \(ms) ms")
            Task { @MainActor in completion(report) }
        }
    }

    /// Writes the CSV export folder off the main thread, then reports the folder on main.
    func export(titles: [String: String], order: [String] = [],
                completion: @escaping @MainActor @Sendable (Result<URL, Error>) -> Void) {
        let store = self.store
        let stamp: String = {
            let now = Date()
            let day = PerfClock.dayStamp(now, timeZone: store.timeZone).replacingOccurrences(of: "-", with: "")
            let time = PerfClock.timeStamp(now, timeZone: store.timeZone).replacingOccurrences(of: ":", with: "")
            return "performance-\(day)-\(time)"
        }()
        queue.async {
            let result: Result<URL, Error>
            do {
                let read = store.read()
                let files = PerfCSVExport.files(events: read.events, rollup: store.loadRollup(), titles: titles,
                                                order: order, now: Date(), timeZone: store.timeZone)
                let folder = store.exportsDirectory.appendingPathComponent(stamp, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for (name, contents) in files {
                    try Data(contents.utf8).write(to: folder.appendingPathComponent(name), options: .atomic)
                }
                result = .success(folder)
            } catch {
                result = .failure(error)
            }
            Task { @MainActor in completion(result) }
        }
    }

    /// 「清除表現紀錄」: stats folder only, then a fresh `stats_marker{cleared}`.
    func clearAll(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        let store = self.store
        recentSessions = []
        excludedSessions = []
        queue.async {
            let ok = (try? store.clear()) != nil
            Task { @MainActor in completion(ok) }
        }
        marker("cleared")
    }

    // MARK: Visa

    private struct VisaMarker: Codable {
        var visa: String
        var source: PerfVisaSource
        var endsAt: Date
    }

    func visaStarted(id: String, source: PerfVisaSource, seconds: TimeInterval, endsAt: Date?, stars: Int?) {
        visa = (id, source, Date())
        if let endsAt, let data = try? JSONEncoder().encode(VisaMarker(visa: id, source: source, endsAt: endsAt)) {
            UserDefaults.standard.set(data, forKey: Self.visaMarkerKey)
        }
        emit(.visaStart, [
            "visa": .string(id),
            "source": .string(source.rawValue),
            "seconds": .seconds(seconds),
            "ends_at": .optionalString(endsAt.map(PerfCodec.formatTimestamp)),
            "stars": .optionalInt(stars)
        ])
    }

    func visaEnded(reason: String) {
        guard let current = visa else { return }
        emit(.visaEnd, [
            "visa": .string(current.id),
            "source": .string(current.source.rawValue),
            "reason": .string(reason),
            "used_s": .seconds(Date().timeIntervalSince(current.startedAt))
        ])
        visa = nil
        clearVisaMarker()
    }

    private func recoverVisa(endsAt: Date) {
        guard let data = UserDefaults.standard.data(forKey: Self.visaMarkerKey),
              let marker = try? JSONDecoder().decode(VisaMarker.self, from: data),
              abs(marker.endsAt.timeIntervalSince(endsAt)) < 2 else {
            visa = ("recovered-\(UUID().uuidString)", .unknown, Date())
            return
        }
        visa = (marker.visa, marker.source, Date())
    }

    private func clearVisaMarker() {
        UserDefaults.standard.removeObject(forKey: Self.visaMarkerKey)
    }

    var visaSource: PerfVisaSource? { visa?.source }

    // MARK: Rounds (child / UAT)

    func roundDealt(round id: String, kind: ActivityKind, stars: Int, pendingStart: Int, pool: [ActivityKind]) {
        abandonRound(reason: "superseded")
        let slots = PerfChoiceCatalog.slots(kind: kind, seed: id)
        let item = PerfChoiceCatalog.item(for: kind)
        let unit = emit(.gameDealt, [
            "round": .string(id),
            "kind": .string(kind.rawValue),
            "item": .string(item),
            "stars": .int(stars),
            "pending_start": .int(pendingStart),
            "pool": .strings(pool.map(\.rawValue)),
            "deal_mode": .string("off"),
            "slots": .strings(slots)
        ])
        round = (PerfRoundTracker(round: id, kind: kind, item: item, stars: stars, pendingStart: pendingStart,
                                  slots: slots, mono: Self.monoNow()), unit.actor, unit.session)
    }

    /// One evaluated child tap. `sequence` carries the convoy step context.
    func roundAnswer(choice: String, correct: Bool, pendingBefore: Int, pendingAfter: Int, hintOn: Bool,
                     sequence: (step: Int, expected: String?, tappedSoFar: [String])? = nil) {
        guard var open = round else { return }
        let fields = answerFields(&open.tracker, choice: choice, correct: correct, pendingBefore: pendingBefore,
                                  pendingAfter: pendingAfter, hintOn: hintOn, sequence: sequence)
        round = open
        emit(.answerAttempt, fields, unit: (open.actor, open.session))
    }

    func roundPauseStarted() { round?.tracker.pauseStarted(mono: Self.monoNow()) }
    func roundPauseEnded() { round?.tracker.pauseEnded(mono: Self.monoNow()) }
    func roundMashTap() { round?.tracker.noteMashTap() }

    func roundHint(afterMisses: Int) {
        guard var open = round else { return }
        open.tracker.noteHint()
        round = open
        emit(.hintShown, ["round": .string(open.tracker.round), "after_misses": .int(afterMisses),
                          "auto": .bool(true)], unit: (open.actor, open.session))
    }

    func roundFinished(outcome: PerfRoundTracker.Outcome, earnedMinutes: Int, assisted: Bool) {
        guard var open = round else { return }
        round = nil
        let fields = open.tracker.result(outcome: outcome, earnedMinutes: earnedMinutes, assisted: assisted,
                                         reason: nil, mono: Self.monoNow())
        emit(.roundResult, fields, unit: (open.actor, open.session), synchronize: true)
    }

    func abandonRound(reason: String) {
        guard var open = round else { return }
        round = nil
        let fields = open.tracker.result(outcome: .abandoned, earnedMinutes: 0, assisted: false,
                                         reason: reason, mono: Self.monoNow())
        emit(.roundResult, fields, unit: (open.actor, open.session), synchronize: true)
    }

    private func answerFields(_ tracker: inout PerfRoundTracker, choice: String, correct: Bool,
                              pendingBefore: Int, pendingAfter: Int, hintOn: Bool,
                              sequence: (step: Int, expected: String?, tappedSoFar: [String])?) -> [String: PerfValue] {
        let facts = tracker.answer(choice: choice, correct: correct, mono: Self.monoNow())
        let kind = tracker.kind
        var tags: [String] = []
        if !correct {
            if kind == .sequenceShortToLong, let sequence {
                tags = PerfChoiceCatalog.sequenceTags(tapped: choice, expected: sequence.expected,
                                                      tappedSoFar: sequence.tappedSoFar, presented: tracker.slots)
            } else {
                tags = PerfChoiceCatalog.tags(kind: kind, choice: choice)
            }
        }
        var fields: [String: PerfValue] = [
            "round": .string(tracker.round),
            "kind": .string(kind.rawValue),
            "item": .string(tracker.item),
            "n": .int(facts.n),
            "choice": .string(choice),
            "asset": .optionalString(PerfChoiceCatalog.asset(kind: kind, choice: choice)),
            "slot": .optionalInt(facts.slot),
            "correct": .bool(correct),
            "pending_before": .int(pendingBefore),
            "pending_after": .int(pendingAfter),
            "hint_on": .bool(hintOn),
            "ms_since_deal": .int(facts.msSinceDeal),
            "ms_since_unlock": .int(facts.msSinceUnlock),
            "tags": .strings(tags),
            "repeat_wrong": .bool(facts.repeatWrong),
            "fast": .bool(facts.fast)
        ]
        if let sequence {
            fields["step"] = .int(sequence.step)
            fields["expected"] = .optionalString(sequence.expected)
        }
        return fields
    }

    // MARK: Playtest (parent cover; never counted)

    func playtestStarted(round id: String, kind: ActivityKind, pendingStart: Int) {
        abandonPlaytest(reason: "superseded")
        let slots = PerfChoiceCatalog.slots(kind: kind, seed: id)
        let item = PerfChoiceCatalog.item(for: kind)
        let unit = emit(.gameDealt, [
            "round": .string(id),
            "kind": .string(kind.rawValue),
            "item": .string(item),
            "stars": .int(0),
            "pending_start": .int(pendingStart),
            "deal_mode": .string("playtest"),
            "slots": .strings(slots)
        ], actorOverride: .parentPlaytest)
        playtest = (PerfRoundTracker(round: id, kind: kind, item: item, stars: 0, pendingStart: pendingStart,
                                     slots: slots, mono: Self.monoNow()), unit.actor, unit.session)
    }

    func playtestAnswer(choice: String, correct: Bool, pendingBefore: Int, pendingAfter: Int, hintOn: Bool,
                        sequence: (step: Int, expected: String?, tappedSoFar: [String])? = nil) {
        guard var open = playtest else { return }
        let fields = answerFields(&open.tracker, choice: choice, correct: correct, pendingBefore: pendingBefore,
                                  pendingAfter: pendingAfter, hintOn: hintOn, sequence: sequence)
        if !correct { open.tracker.pauseStarted(mono: Self.monoNow()) }
        playtest = open
        emit(.answerAttempt, fields, unit: (open.actor, open.session))
    }

    func playtestPauseEnded() { playtest?.tracker.pauseEnded(mono: Self.monoNow()) }

    func playtestHint(afterMisses: Int) {
        guard var open = playtest else { return }
        open.tracker.noteHint()
        playtest = open
        emit(.hintShown, ["round": .string(open.tracker.round), "after_misses": .int(afterMisses),
                          "auto": .bool(true)], unit: (open.actor, open.session))
    }

    func playtestSolved(earnedMinutes: Int, assisted: Bool) {
        guard var open = playtest else { return }
        playtest = nil
        let fields = open.tracker.result(outcome: .solved, earnedMinutes: earnedMinutes, assisted: assisted,
                                         reason: nil, mono: Self.monoNow())
        emit(.roundResult, fields, unit: (open.actor, open.session))
    }

    func abandonPlaytest(reason: String) {
        guard var open = playtest else { return }
        playtest = nil
        let fields = open.tracker.result(outcome: .abandoned, earnedMinutes: 0, assisted: false,
                                         reason: reason, mono: Self.monoNow())
        emit(.roundResult, fields, unit: (open.actor, open.session))
    }

    // MARK: Picker

    func pickerVisit(visit: String, entry: String, deck: [String], visaLeft: Int, budgetLeft: TimeInterval) {
        guard !visit.isEmpty else { return }
        rememberVisit(visit)
        shownPage = nil
        emit(.pickerVisit, [
            "visit": .string(visit),
            "entry": .string(entry),
            "deck": .strings(deck),
            "page_count": .int(VideoPickerDeck.pageCount(itemCount: deck.count)),
            "visa": .optionalString(visa?.id),
            "visa_source": .optionalString(visa?.source.rawValue),
            "visa_left_s": .int(visaLeft),
            "budget_left_s": .seconds(budgetLeft)
        ])
    }

    private func rememberVisit(_ visit: String) {
        knownVisits.append(visit)
        if knownVisits.count > 20 { knownVisits.removeFirst(knownVisits.count - 20) }
    }

    func pageShown(visit: String, deck: [String], page: Int, via: String, visaLeft: Int, budgetLeft: TimeInterval) {
        if !knownVisits.contains(visit) {
            pickerVisit(visit: visit, entry: "implicit", deck: deck, visaLeft: visaLeft, budgetLeft: budgetLeft)
        }
        // `onAppear` can fire again for the same page (e.g. back from parent): one line per showing.
        if via == "open", let shown = shownPage, shown.visit == visit, shown.page == page { return }
        shownPage = (visit, page, Self.monoNow())
        emit(.videoImpressions, [
            "visit": .string(visit),
            "page": .int(page),
            "ids": .strings(PerfPickerPlacement.ids(deck: deck, page: page)),
            "via": .string(via)
        ])
    }

    /// Child tapped a card. The pick line is written with the start (accepted) or now (refused).
    func pickTapped(visit: String, video: String, deck: [String]) {
        let index = deck.firstIndex(of: video)
        let placement = index.flatMap { PerfPickerPlacement.placement(deckIndex: $0) }
        let msOnPage: Int? = {
            guard let shown = shownPage, shown.visit == visit else { return nil }
            return Int(((Self.monoNow() - shown.mono) * 1000).rounded())
        }()
        pendingPick = [
            "visit": .string(visit),
            "video": .string(video),
            "page": .optionalInt(placement?.page),
            "slot": .optionalInt(placement?.slot),
            "deck_index": .optionalInt(index),
            "deck_size": .int(deck.count),
            "ms_on_page": .optionalInt(msOnPage)
        ]
    }

    func pickRefused(reason: String?) {
        guard var fields = pendingPick else { return }
        pendingPick = nil
        fields["accepted"] = .bool(false)
        fields["refuse_reason"] = .optionalString(reason)
        emit(.videoPick, fields)
    }

    // MARK: Resume

    func resumeOffered(video: String, position: TimeInterval, surface: String) {
        if let last = lastResumeOffer, last.video == video, last.position == Int(position),
           last.surface == surface { return }
        lastResumeOffer = (video, Int(position), surface)
        emit(.resumeOffered, ["video": .string(video), "position_s": .seconds(position), "surface": .string(surface)])
    }

    func resumeUsed(video: String, position: TimeInterval, choice: String) {
        let surface = lastResumeOffer?.surface ?? "unknown"
        lastResumeOffer = nil
        emit(.resumeUsed, [
            "video": .string(video), "position_s": .seconds(position),
            "choice": .string(choice), "surface": .string(surface)
        ])
    }

    /// The saved 繼續睇 position was dropped (design §5.5). Lets the reader settle
    /// `resumed_later` = no instead of pending.
    func resumeCleared(video: String, position: TimeInterval?, reason: String) {
        var fields: [String: PerfValue] = ["video": .string(video), "reason": .string(reason)]
        if let position { fields["position_s"] = .seconds(position) }
        emit(.resumeCleared, fields)
    }

    // MARK: Plays

    var hasOpenPlay: Bool { play != nil }

    func videoStarted(video: String, source: String, startSeconds: TimeInterval?, durationSeconds: TimeInterval?,
                      visaLeft: Int, budgetLeft: TimeInterval) {
        if play != nil { endPlay(reason: .superseded, resumeSaved: false) }
        var pick = pendingPick
        pendingPick = nil
        if var accepted = pick, accepted["video"]?.stringValue == video, source == "pick" {
            accepted["accepted"] = .bool(true)
            accepted["refuse_reason"] = .null
            emit(.videoPick, accepted)
        } else {
            pick = nil
        }
        let id = UUID().uuidString
        var fields: [String: PerfValue] = [
            "play": .string(id),
            "video": .string(video),
            "source": .string(source),
            "start_s": .seconds(startSeconds ?? 0),
            "duration_s": .seconds(durationSeconds),
            "visa": .optionalString(visa?.id),
            "visa_source": .optionalString(visa?.source.rawValue),
            "visa_left_s": .int(visaLeft),
            "budget_left_s": .seconds(budgetLeft)
        ]
        if let pick {
            for key in ["visit", "page", "slot", "deck_size", "ms_on_page"] { fields[key] = pick[key] ?? .null }
        }
        let unit = emit(.videoStart, fields)
        play = (PerfPlayTracker(play: id, video: video, source: source, startSeconds: startSeconds,
                                durationSeconds: durationSeconds, mono: Self.monoNow()), unit.actor, unit.session)
        lastProgressMono = nil
    }

    func playSample(video: String, seconds: TimeInterval) {
        guard var open = play, open.tracker.video == video else { return }
        open.tracker.sample(position: seconds)
        play = open
    }

    func playDuration(video: String, seconds: TimeInterval) {
        guard var open = play, open.tracker.video == video else { return }
        open.tracker.noteDuration(seconds)
        play = open
    }

    func endPlay(reason: PerfVideoStopReason, resumeSaved: Bool) {
        guard let open = play else { return }
        play = nil
        lastProgressMono = nil
        emit(.videoEnd, open.tracker.endFields(reason: reason, resumeSaved: resumeSaved, mono: Self.monoNow()),
             unit: (open.actor, open.session), synchronize: true)
    }

    var openPlayVideoID: String? { play?.tracker.video }
}
