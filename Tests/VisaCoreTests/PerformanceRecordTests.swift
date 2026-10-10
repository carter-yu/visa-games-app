import Foundation
import VisaCore

/// D10 performance records (v0.20.0, ADR 0008): event schema, tagging / exclusion,
/// trackers, retention and CSV export. Pure VisaCore — no AppKit, no real stats folder.
final class PerformanceRecordTests {
    private let base = PerfCodec.parseTimestamp("2026-10-09T10:00:00.000Z")!  // 18:00 HKT

    private func event(
        _ type: PerfEventType,
        _ fields: [String: PerfValue] = [:],
        at offset: TimeInterval = 0,
        seq: Int,
        actor: PerfActor = .child,
        session: String = "s1",
        launch: String = "L1",
        mode: String = "lock",
        v: Int = PerfEvent.schemaVersion
    ) -> PerfEvent {
        PerfEvent(v: v, type: type, timestamp: base.addingTimeInterval(offset), tz: "+08:00",
                  mono: 100.5 + offset, launch: launch, seq: seq, app: "0.20.0", actor: actor,
                  mode: mode, session: session, fields: fields)
    }

    private func tempStore() -> (PerfEventStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("perf-\(UUID().uuidString)")
        return (PerfEventStore(directory: root.appendingPathComponent("stats", isDirectory: true)), root)
    }

    // MARK: Schema

    func testEnvelopeRoundTripsEveryEventType() throws {
        for (index, type) in PerfEventType.known.enumerated() {
            let original = event(type, [
                "n": .int(index),
                "text": .string("a,\"b\"\n中文"),
                "list": .strings(["x", "y"]),
                "secs": .seconds(1.25),
                "none": .null,
                "flag": .bool(true),
                "seq": .int(999)  // envelope key: dropped from fields
            ], seq: index + 1)
            expectNil(original.fields["seq"])
            let line = try PerfCodec.encodeLine(original)
            expectFalse(line.contains("\n"))
            expectTrue(line.hasPrefix("{\"actor\":\"child\""))  // sorted keys
            guard case .event(let decoded) = PerfCodec.decodeLine(Substring(line)) else {
                preconditionFailure("line did not decode: \(line)")
            }
            expectEqual(decoded, original)
            expectEqual(decoded.type.rawValue, type.rawValue)
            expectEqual(PerfEventType(rawValue: type.rawValue), type)
        }
        // Raw names are unique snake_case.
        let names = PerfEventType.known.map(\.rawValue)
        expectEqual(Set(names).count, names.count)
        expectTrue(names.allSatisfy { $0 == $0.lowercased() && !$0.contains(" ") })
        // Video events are the ones a parent-mode actor turns into parent_preview.
        expectTrue(PerfEventType.videoEnd.isVideoEvent)
        expectTrue(PerfEventType.videoImpressions.isVideoEvent)
        expectFalse(PerfEventType.answerAttempt.isVideoEvent)
    }

    func testTolerantDecoderSkipsTornAndNewerLinesAndKeepsUnknownTypes() throws {
        let good = try PerfCodec.encodeLine(event(.gameDealt, ["round": .string("r1")], seq: 1))
        let unknown = try PerfCodec.encodeLine(event(.unknown("future_thing"), ["x": .int(1)], seq: 2))
        let newer = try PerfCodec.encodeLine(event(.gameDealt, seq: 3, v: 2))
        let torn = String(good.prefix(good.count / 2))
        let text = [good, torn, "", "not json", newer, unknown].joined(separator: "\n") + "\n"
        let decoded = PerfCodec.decodeLines(text)
        expectEqual(decoded.events.count, 2)
        expectEqual(decoded.skipped, 3)
        expectEqual(decoded.events[1].type, .unknown("future_thing"))
        expectEqual(decoded.events[1].type.rawValue, "future_thing")
    }

    func testStoreWritesOneFilePerHongKongDayAndReadsInLaunchOrder() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        // 15:59:59Z = 23:59:59 HKT (9 Oct); 16:00:00Z = 00:00 HKT (10 Oct).
        let lateNight = event(.gameDealt, ["round": .string("a")], at: 5 * 3600 + 59 * 60 + 59, seq: 1)
        let midnight = event(.roundResult, ["round": .string("a")], at: 6 * 3600, seq: 2)
        // A second launch whose events were written earlier in the file must still sort after L1.
        let laterLaunch = event(.appLaunch, at: 7 * 3600, seq: 1, launch: "L2")
        try store.append([laterLaunch])
        try store.append([lateNight, midnight], synchronize: true)
        expectEqual(store.eventDays(), ["2026-10-09", "2026-10-10"])
        expectTrue(FileManager.default.fileExists(atPath: store.fileURL(day: "2026-10-09").path))
        let read = store.read()
        expectEqual(read.skipped, 0)
        expectEqual(read.events.map(\.launch), ["L1", "L1", "L2"])
        expectEqual(read.events.map(\.seq), [1, 2, 1])
        // Appends never rewrite: a torn tail is skipped, earlier lines survive.
        let handle = try FileHandle(forWritingTo: store.fileURL(day: "2026-10-10"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"v\":1,\"t\":\"game_de".utf8))
        try handle.close()
        let again = store.read()
        expectEqual(again.events.count, 3)
        expectEqual(again.skipped, 1)
        expectEqual(PerfClock.dayStamp(lateNight.timestamp, timeZone: PerfClock.hongKong), "2026-10-09")
        expectEqual(PerfClock.timeStamp(lateNight.timestamp, timeZone: PerfClock.hongKong), "23:59:59")
    }

    func testClearPerformanceRecordsIsSeparateFromVisaReset() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        // state.json lives next to stats/ (same Application Support folder).
        let snapshots = SnapshotStore(url: root.appendingPathComponent("state.json"))
        try snapshots.save(Snapshot(configured: true))
        try store.append([event(.gameDealt, seq: 1)])
        try store.saveRollup(PerfRollup(foldedDays: ["2026-01-01"], days: ["2026-01-01": PerfDaySummary()]))
        // 清除簽證及重設儲存 writes a fresh snapshot only: stats survive (Carter decision 3A).
        try snapshots.save(Snapshot(configured: true))
        expectEqual(store.read().events.count, 1)
        expectEqual(store.loadRollup().foldedDays, ["2026-01-01"])
        // 清除表現紀錄 empties stats/ only: state.json untouched.
        try store.clear()
        expectEqual(store.read().events.count, 0)
        expectEqual(store.loadRollup(), PerfRollup())
        expectEqual(try snapshots.load(), Snapshot(configured: true))
        // Writing again after a clear recreates the folder.
        try store.append([event(.statsMarker, ["what": .string("cleared")], seq: 2, actor: .parent)])
        expectEqual(store.read().events.count, 1)
        // Default location: Application Support/VisaGames/stats (never the repo logs/ mirror).
        expectTrue(PerfEventStore.defaultDirectory().path.hasSuffix("VisaGames/stats"))
        #if os(macOS)
        expectTrue(PerfEventStore.defaultDirectory().path.hasSuffix("Library/Application Support/VisaGames/stats"))
        #endif
    }

    // MARK: Trackers

    func testRoundTrackerFirstTryMissesAndActiveTimeWithoutPauses() {
        var solved = PerfRoundTracker(round: "r1", kind: .findTheSame, item: "find-1", stars: 2, pendingStart: 10,
                                      slots: ["find-nytaxi", "find-hktaxi", "find-fire"], mono: 0)
        let facts = solved.answer(choice: "find-hktaxi", correct: true, mono: 4)
        expectEqual(facts.n, 1)
        expectEqual(facts.slot, 1)
        expectEqual(facts.msSinceDeal, 4000)
        let result = solved.result(outcome: .solved, earnedMinutes: 10, assisted: false, reason: nil, mono: 4)
        expectEqual(result["first_try"], .bool(true))
        expectEqual(result["misses"], .int(0))
        expectEqual(result["active_ms"], .int(4000))
        expectEqual(result["first_tap_ms"], .int(4000))

        var missed = PerfRoundTracker(round: "r2", kind: .findTheSame, item: "find-1", stars: 2, pendingStart: 10,
                                      slots: ["find-nytaxi", "find-hktaxi", "find-fire"], mono: 0)
        let wrong = missed.answer(choice: "find-nytaxi", correct: false, mono: 1)
        expectTrue(wrong.fast)  // 1 s after the board unlocked
        missed.pauseStarted(mono: 1)
        missed.noteMashTap()
        missed.noteMashTap()
        missed.pauseEnded(mono: 11)  // 10 s Think Pause not counted
        let repeatWrong = missed.answer(choice: "find-nytaxi", correct: false, mono: 14)
        expectTrue(repeatWrong.repeatWrong)
        expectFalse(repeatWrong.fast)
        expectEqual(repeatWrong.msSinceUnlock, 3000)
        missed.pauseStarted(mono: 14)
        missed.pauseEnded(mono: 24)
        missed.noteHint()
        _ = missed.answer(choice: "find-hktaxi", correct: true, mono: 26)
        let missedResult = missed.result(outcome: .solved, earnedMinutes: 3, assisted: true, reason: nil, mono: 26)
        expectEqual(missedResult["first_try"], .bool(false))
        expectEqual(missedResult["misses"], .int(2))
        expectEqual(missedResult["answers"], .int(3))
        expectEqual(missedResult["active_ms"], .int(1000 + 3000 + 2000))
        expectEqual(missedResult["total_ms"], .int(26000))
        expectEqual(missedResult["mash_taps"], .int(2))
        expectEqual(missedResult["hint_used"], .bool(true))
        expectEqual(missedResult["wrong_choices"], .strings(["find-nytaxi", "find-nytaxi"]))
        expectEqual(missedResult["earned_min"], .int(3))
    }

    func testRoundTrackerFuelOutParentIntervalIdleCapAndAbandon() {
        var zeroed = PerfRoundTracker(round: "r3", kind: .countVehicles, item: "count-1", stars: 1, pendingStart: 5,
                                      slots: ["count-2", "count-3", "count-4"], mono: 0)
        // Parent opens controls mid-round for 60 s: excluded from active and total time.
        zeroed.parentStarted(mono: 2)
        zeroed.parentEnded(mono: 62)
        _ = zeroed.answer(choice: "count-2", correct: false, mono: 63)
        zeroed.pauseStarted(mono: 63)
        zeroed.pauseEnded(mono: 73)
        _ = zeroed.answer(choice: "count-4", correct: false, mono: 74)
        let result = zeroed.result(outcome: .zeroed, earnedMinutes: 99, assisted: false, reason: nil, mono: 84)
        expectEqual(result["outcome"], .string("zeroed"))
        expectEqual(result["earned_min"], .int(0))
        expectEqual(result["parent_ms"], .int(60000))
        expectEqual(result["active_ms"], .int(2000 + 1000 + 1000))
        expectEqual(result["total_ms"], .int(24000))
        expectEqual(result["first_try"], .bool(false))

        var idle = PerfRoundTracker(round: "r4", kind: .moreFewer, item: "mf-1", stars: 1, pendingStart: 5,
                                    slots: ["lot-left", "lot-right"], mono: 0)
        let abandoned = idle.result(outcome: .abandoned, earnedMinutes: 0, assisted: false, reason: "terminate",
                                    mono: 600)
        expectEqual(abandoned["active_ms"], .int(Int(PerfRoundTracker.idleCapSeconds * 1000)))
        expectEqual(abandoned["first_try"], .null)  // never answered
        expectEqual(abandoned["reason"], .string("terminate"))
        expectEqual(abandoned["answers"], .int(0))
    }

    func testSequenceStepsBeforeFirstMissAndRankTags() {
        let order = ActivityCatalog.sequenceQuestion().orderedAssetIDs
        precondition(order.count >= 3)
        let presented = PerfChoiceCatalog.slots(kind: .sequenceShortToLong, seed: "seq-seed")
        var tracker = PerfRoundTracker(round: "r5", kind: .sequenceShortToLong, item: "seq-1", stars: 3,
                                       pendingStart: 15, slots: presented, mono: 0)
        _ = tracker.answer(choice: order[0], correct: true, mono: 1)
        _ = tracker.answer(choice: order[2], correct: false, mono: 2)
        let fields = tracker.result(outcome: .zeroed, earnedMinutes: 0, assisted: false, reason: nil, mono: 3)
        expectEqual(fields["steps_before_first_miss"], .int(1))

        let tags = PerfChoiceCatalog.sequenceTags(tapped: order[2], expected: order[1], tappedSoFar: [order[0]],
                                                  presented: presented)
        expectEqual(tags.first, "rank_error:1")
        let longestFirst = PerfChoiceCatalog.sequenceTags(tapped: order[order.count - 1], expected: order[0],
                                                          tappedSoFar: [], presented: presented)
        expectTrue(longestFirst.contains("longest_first"))
        expectEqual(longestFirst.first, "rank_error:\(order.count - 1)")
        // The leftmost untapped card, tapped wrongly, is flagged screen_order.
        if let leftmost = presented.first, leftmost != order[0] {
            expectTrue(PerfChoiceCatalog.sequenceTags(tapped: leftmost, expected: order[0], tappedSoFar: [],
                                                      presented: presented).contains("screen_order"))
        }
        expectEqual(PerfChoiceCatalog.sequenceTags(tapped: order[0], expected: order[0], tappedSoFar: [],
                                                   presented: presented), [])
    }

    func testRecordedSlotsMatchWhatTheChildSawForEveryKind() {
        for kind in ActivityKind.allCases {
            let all = PerfChoiceCatalog.allChoices(for: kind)
            expectFalse(all.isEmpty)
            for index in 0..<50 {
                let seed = "seed-\(index)"
                let slots = PerfChoiceCatalog.slots(kind: kind, seed: seed)
                expectEqual(slots, PerfChoiceCatalog.slots(kind: kind, seed: seed))  // deterministic
                expectEqual(slots.count, all.count)
                expectEqual(Set(slots), Set(all))
            }
            expectTrue(PerfChoiceCatalog.chance(for: kind) > 0 && PerfChoiceCatalog.chance(for: kind) <= 0.5)
            expectFalse(PerfChoiceCatalog.item(for: kind).isEmpty)
        }
        // Same presented order as the views (CanvasActivityHost uses presentedOptions(seed:)).
        expectEqual(PerfChoiceCatalog.slots(kind: .findTheSame, seed: "abc"),
                    ActivityCatalog.findSameQuestion().presentedOptions(seed: "abc").map(\.id))
    }

    func testEveryWrongOptionHasConfusionTagsAndTheRightOneHasNone() {
        for kind in ActivityKind.allCases where kind != .sequenceShortToLong {
            guard let correct = PerfChoiceCatalog.correctChoice(for: kind) else {
                preconditionFailure("no correct choice for \(kind)")
            }
            expectTrue(PerfChoiceCatalog.allChoices(for: kind).contains(correct))
            expectEqual(PerfChoiceCatalog.tags(kind: kind, choice: correct), [])
            for choice in PerfChoiceCatalog.allChoices(for: kind) where choice != correct {
                precondition(!PerfChoiceCatalog.tags(kind: kind, choice: choice).isEmpty,
                             "missing tags for \(kind.rawValue) \(choice)")
            }
        }
        expectEqual(PerfChoiceCatalog.asset(kind: .countVehicles, choice: "count-2"), nil)
        expectEqual(PerfChoiceCatalog.correctChoice(for: .sequenceShortToLong), nil)
    }

    func testActorRuleCountableAndParentExclusion() {
        typealias Rule = PerfActorRule
        expectEqual(Rule.resolve(mode: .lock, isPlaytest: false, isVideoEvent: false, uatOn: false, visaSource: nil), .child)
        expectEqual(Rule.resolve(mode: .play, isPlaytest: false, isVideoEvent: true, uatOn: false, visaSource: .earned), .child)
        expectEqual(Rule.resolve(mode: .play, isPlaytest: false, isVideoEvent: true, uatOn: false, visaSource: .parentTest),
                    .parentTestVisa)
        expectEqual(Rule.resolve(mode: .play, isPlaytest: false, isVideoEvent: true, uatOn: true, visaSource: .earned),
                    .parentUAT)
        expectEqual(Rule.resolve(mode: .lock, isPlaytest: false, isVideoEvent: false, uatOn: true, visaSource: nil),
                    .parentUAT)
        expectEqual(Rule.resolve(mode: .parent, isPlaytest: true, isVideoEvent: false, uatOn: true, visaSource: nil),
                    .parentPlaytest)
        expectEqual(Rule.resolve(mode: .parent, isPlaytest: false, isVideoEvent: true, uatOn: false, visaSource: nil),
                    .parentPreview)
        expectEqual(Rule.resolve(mode: .parent, isPlaytest: false, isVideoEvent: false, uatOn: false, visaSource: nil),
                    .parent)
        expectEqual(Rule.resolve(mode: .setup, isPlaytest: false, isVideoEvent: false, uatOn: false, visaSource: nil),
                    .system)

        let childRound = event(.gameDealt, seq: 1, session: "s1")
        expectTrue(PerfFilter.countable(childRound, excludedSessions: []))
        for actor in PerfActor.allCases where actor != .child {
            expectFalse(PerfFilter.countable(event(.gameDealt, seq: 2, actor: actor), excludedSessions: []))
        }
        expectFalse(PerfFilter.countable(event(.gameDealt, seq: 3, v: 2), excludedSessions: []))

        // 「唔計呢段」 / 「計返」: last write wins per target session.
        let marks = [
            event(.statsExclude, ["target_session": .string("s1")], at: 10, seq: 4, actor: .parent, session: "p"),
            event(.statsExclude, ["target_session": .string("s2")], at: 11, seq: 5, actor: .parent, session: "p"),
            event(.statsInclude, ["target_session": .string("s2")], at: 12, seq: 6, actor: .parent, session: "p")
        ]
        let excluded = PerfFilter.excludedSessions(in: marks.reversed())
        expectEqual(excluded, ["s1"])
        expectFalse(PerfFilter.countable(childRound, excludedSessions: excluded))
    }

    func testUATSwitchAutoOffAfterSixtyMinutesAndSessionClock() {
        var uat = PerfUATSwitch()
        expectFalse(uat.isOn(at: base))
        uat.turnOn(now: base)
        expectTrue(uat.isOn(at: base.addingTimeInterval(59 * 60)))
        expectEqual(uat.minutesLeft(at: base), 60)
        expectEqual(uat.minutesLeft(at: base.addingTimeInterval(59 * 60 + 1)), 1)
        expectFalse(uat.expireIfNeeded(now: base.addingTimeInterval(59 * 60)))
        expectTrue(uat.expireIfNeeded(now: base.addingTimeInterval(3600)))
        expectFalse(uat.expireIfNeeded(now: base.addingTimeInterval(3601)))  // once only
        expectFalse(uat.isOn(at: base.addingTimeInterval(3601)))

        var clock = PerfSessionClock()
        var counter = 0
        let mint = { () -> String in counter += 1; return "s\(counter)" }
        let first = clock.session(isParentMode: false, now: base, mint: mint)
        expectEqual(first.id, "s1")
        expectEqual(first.started, .launch)
        expectNil(clock.session(isParentMode: false, now: base.addingTimeInterval(60), mint: mint).started)
        // Parent mode stays in the current session; the next child event starts a new one.
        expectEqual(clock.session(isParentMode: true, now: base.addingTimeInterval(120), mint: mint).id, "s1")
        let afterParent = clock.session(isParentMode: false, now: base.addingTimeInterval(180), mint: mint)
        expectEqual(afterParent.id, "s2")
        expectEqual(afterParent.started, .afterParent)
        let afterGap = clock.session(isParentMode: false, now: base.addingTimeInterval(180 + 30 * 60), mint: mint)
        expectEqual(afterGap.id, "s3")
        expectEqual(afterGap.started, .idleGap)
    }

    func testPlayTrackerWatchedSecondsSeeksStopReasonsAndWallOnly() {
        var play = PerfPlayTracker(play: "p1", video: "vid", source: "continue", startSeconds: 30,
                                   durationSeconds: 120, mono: 0)
        for second in 31...60 { play.sample(position: Double(second)) }
        play.sample(position: 100)  // seek forward: not watched
        play.sample(position: 101)
        play.sample(position: 90)   // seek back: not watched
        let cut = play.endFields(reason: .visaExpired, resumeSaved: true, mono: 40)
        expectEqual(cut["watched_s"], .double(31))
        expectEqual(cut["max_pos_s"], .double(101))
        expectEqual(cut["last_pos_s"], .double(90))
        expectEqual(cut["completed"], .bool(false))
        expectEqual(cut["resume_saved"], .bool(true))
        expectEqual(cut["stop_reason"], .string("visa_expired"))
        expectEqual(cut["telemetry"], .string("full"))
        expectEqual(cut["completion"]?.doubleValue, 0.842)

        let ended = play.endFields(reason: .ended, resumeSaved: false, mono: 100)
        expectEqual(ended["completed"], .bool(true))
        expectEqual(ended["completion"], .double(1))

        let silent = PerfPlayTracker(play: "p2", video: "vid", source: "pick", startSeconds: nil,
                                     durationSeconds: nil, mono: 10)
        let silentEnd = silent.endFields(reason: .unknown, resumeSaved: false, mono: 25.5)
        expectEqual(silentEnd["telemetry"], .string("none"))
        expectEqual(silentEnd["watched_s"], .double(0))
        expectEqual(silentEnd["completion"], .null)

        // Stop reasons: unique snake_case raw values; only `ended` means completed.
        let raws = PerfVideoStopReason.allCases.map(\.rawValue)
        expectEqual(Set(raws).count, raws.count)
        expectTrue(raws.contains("nav_guard") && raws.contains("budget_exhausted") && raws.contains("parent_unlock"))
        for reason in PerfVideoStopReason.allCases {
            let fields = silent.endFields(reason: reason, resumeSaved: false, mono: 11)
            expectEqual(fields["completed"], .bool(reason == .ended))
        }
    }

    func testPickerPlacementPagesAndImpressions() {
        let deck = (0..<19).map { "v\($0)" }
        expectEqual(PerfPickerPlacement.placement(deckIndex: 0)?.page, 0)
        expectEqual(PerfPickerPlacement.placement(deckIndex: 7)?.slot, 7)
        expectEqual(PerfPickerPlacement.placement(deckIndex: 8)?.page, 1)
        expectEqual(PerfPickerPlacement.placement(deckIndex: 8)?.slot, 0)
        expectEqual(PerfPickerPlacement.placement(deckIndex: 18)?.page, 2)
        expectEqual(PerfPickerPlacement.placement(deckIndex: 18)?.slot, 2)
        expectNil(PerfPickerPlacement.placement(deckIndex: -1))
        expectEqual(PerfPickerPlacement.ids(deck: deck, page: 0), Array(deck[0..<8]))
        expectEqual(PerfPickerPlacement.ids(deck: deck, page: 2), ["v16", "v17", "v18"])
        expectEqual(PerfPickerPlacement.ids(deck: deck, page: 3), [])
    }

    // MARK: Export

    func testCSVHasBOMHeadersEscapingAndHongKongTime() {
        expectEqual(PerfCSVExport.escape("plain"), "plain")
        expectEqual(PerfCSVExport.escape("a,b"), "\"a,b\"")
        expectEqual(PerfCSVExport.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
        expectEqual(PerfCSVExport.escape("two\nlines"), "\"two\nlines\"")
        let doc = PerfCSVExport.document(header: ["a", "b"], rows: [["1", "x,y"]])
        expectEqual(doc, "\u{FEFF}a,b\r\n1,\"x,y\"\r\n")

        let events = [
            event(.gameDealt, ["round": .string("r1"), "kind": .string("findTheSame"), "stars": .int(2),
                               "item": .string("find-1"), "deal_mode": .string("off"), "pending_start": .int(10)],
                  seq: 1),
            event(.answerAttempt, ["round": .string("r1"), "choice": .string("find-nytaxi"), "correct": .bool(false),
                                   "slot": .int(0), "tags": .strings(["same_shape", "diff_color"]),
                                   "repeat_wrong": .bool(false), "fast": .bool(true)], at: 3, seq: 2),
            event(.roundResult, ["round": .string("r1"), "outcome": .string("solved"), "first_try": .bool(false),
                                 "misses": .int(1), "answers": .int(2), "hint_used": .bool(false),
                                 "assisted": .bool(false), "earned_min": .int(5), "active_ms": .int(6500),
                                 "total_ms": .int(16500), "first_tap_ms": .int(3000), "mash_taps": .int(4),
                                 "reason": .null], at: 16, seq: 3),
            event(.gameDealt, ["round": .string("r2"), "kind": .string("countVehicles"), "stars": .int(1)],
                  at: 30, seq: 4, actor: .parentPlaytest, mode: "parent")
        ]
        let files = PerfCSVExport.files(events: events, rollup: PerfRollup(), titles: [:])
        expectEqual(Set(files.keys), ["rounds.csv", "videos.csv", "video_impressions.csv", "daily_games.csv",
                                      "daily_videos.csv", "games_summary.csv", "videos_summary.csv", "README.txt"])
        let rounds = files["rounds.csv"] ?? ""
        expectTrue(rounds.hasPrefix("\u{FEFF}" + PerfCSVExport.roundsHeader.joined(separator: ",") + "\r\n"))
        let rows = PerfCSVExport.roundRows(events, excluded: [], timeZone: PerfClock.hongKong)
        expectEqual(rows.count, 2)
        let header = PerfCSVExport.roundsHeader
        func column(_ row: [String], _ name: String) -> String { row[header.firstIndex(of: name)!] }
        expectEqual(rows[0].count, header.count)
        expectEqual(column(rows[0], "date_hkt"), "2026-10-09")
        expectEqual(column(rows[0], "time_hkt"), "18:00:00")
        expectEqual(column(rows[0], "ts_utc"), "2026-10-09T10:00:00.000Z")
        expectEqual(column(rows[0], "counted"), "yes")
        expectEqual(column(rows[0], "kind_zh"), ActivityKind.findTheSame.parentCardTitle)
        expectEqual(column(rows[0], "first_try"), "no")
        expectEqual(column(rows[0], "active_s"), "6.5")
        expectEqual(column(rows[0], "wrong_tags"), "same_shape+diff_color")
        expectEqual(column(rows[0], "fast_wrong"), "1")
        expectEqual(column(rows[1], "counted"), "no")
        expectEqual(column(rows[1], "outcome"), "abandoned")
        expectEqual(column(rows[1], "abandon_reason"), "no_result_recorded")
        expectTrue(isTraditionalChineseOnly(PerfCSVExport.readme))
        expectTrue(perfTraditionalOnly(PerfCSVExport.readme))
        expectTrue(PerfCSVExport.readme.contains("請勿上載"))
    }

    func testVideoCSVStopReasonResumeLaterImpressionsAndMissingEnd() {
        let events = [
            event(.videoImpressions, ["visit": .string("v1"), "page": .int(0), "ids": .strings(["a", "b"]),
                                      "via": .string("open")], seq: 1, mode: "play"),
            event(.videoPick, ["visit": .string("v1"), "video": .string("b"), "page": .int(0), "slot": .int(1),
                               "accepted": .bool(true)], at: 2, seq: 2, mode: "play"),
            event(.videoStart, ["play": .string("p1"), "video": .string("b"), "source": .string("pick"),
                                "visit": .string("v1"), "page": .int(0), "slot": .int(1), "start_s": .double(0)],
                  at: 2, seq: 3, mode: "play"),
            event(.videoEnd, ["play": .string("p1"), "video": .string("b"), "stop_reason": .string("visa_expired"),
                              "completed": .bool(false), "resume_saved": .bool(true), "watched_s": .double(55),
                              "telemetry": .string("full")], at: 60, seq: 4, mode: "play"),
            event(.videoStart, ["play": .string("pp"), "video": .string("b"), "source": .string("parent_preview")],
                  at: 70, seq: 5, actor: .parentPreview, mode: "parent"),
            event(.videoStart, ["play": .string("p2"), "video": .string("b"), "source": .string("continue"),
                                "start_s": .double(57)], at: 900, seq: 6, mode: "play")
        ]
        let rows = PerfCSVExport.videoRows(events, excluded: [], titles: ["b": "Bus, \"big\""], timeZone: PerfClock.hongKong)
        let header = PerfCSVExport.videosHeader
        func column(_ row: [String], _ name: String) -> String { row[header.firstIndex(of: name)!] }
        expectEqual(rows.count, 3)
        expectEqual(column(rows[0], "stop_reason"), "visa_expired")
        expectEqual(column(rows[0], "completed"), "no")
        expectEqual(column(rows[0], "resume_saved"), "yes")
        expectEqual(column(rows[0], "resumed_later"), "yes")  // preview in between is skipped
        expectEqual(column(rows[0], "title"), "Bus, \"big\"")
        expectEqual(column(rows[0], "slot"), "1")
        expectEqual(column(rows[1], "counted"), "no")
        expectEqual(column(rows[2], "stop_reason"), "interrupted")
        expectEqual(column(rows[0], "time_up_stop"), "yes")
        expectEqual(column(rows[2], "resumed_later"), "")
        expectEqual(column(rows[2], "source"), "continue")

        let impressions = PerfCSVExport.impressionRows(events, excluded: [], titles: [:], timeZone: PerfClock.hongKong)
        expectEqual(impressions.count, 2)
        let iHeader = PerfCSVExport.impressionsHeader
        expectEqual(impressions[0][iHeader.firstIndex(of: "picked")!], "no")
        expectEqual(impressions[1][iHeader.firstIndex(of: "picked")!], "yes")
        expectEqual(impressions[1][iHeader.firstIndex(of: "slot")!], "1")
    }

    func testResumeLinkYesNoPendingAndNotApplicable() {
        func end(_ play: String, _ video: String, _ reason: String, saved: Bool, _ seq: Int) -> PerfEvent {
            event(.videoEnd, ["play": .string(play), "video": .string(video), "stop_reason": .string(reason),
                              "completed": .bool(reason == "ended"), "resume_saved": .bool(saved)],
                  at: TimeInterval(seq * 10), seq: seq, mode: "play")
        }
        let events = PerfCodec.ordered([
            end("p1", "a", "visa_expired", saved: true, 1),
            event(.resumeCleared, ["video": .string("a"), "reason": .string("pick_other")], at: 20, seq: 2, mode: "play"),
            event(.videoStart, ["play": .string("p2"), "video": .string("a"), "source": .string("pick")],
                  at: 30, seq: 3, mode: "play"),
            end("p2", "a", "budget_exhausted", saved: true, 4),
            event(.videoStart, ["play": .string("p3"), "video": .string("a"), "source": .string("continue")],
                  at: 50, seq: 5, mode: "play"),
            end("p3", "a", "ended", saved: false, 6),
            end("p4", "b", "visa_expired", saved: true, 7)
        ])
        let index = { (play: String) in events.firstIndex { $0.type == .videoEnd && $0.string("play") == play }! }
        expectEqual(PerfResumeLink.resolve(events, endIndex: index("p1")), .no)
        expectEqual(PerfResumeLink.resolve(events, endIndex: index("p2")), .yes)
        expectEqual(PerfResumeLink.resolve(events, endIndex: index("p3")), .notApplicable)
        expectEqual(PerfResumeLink.resolve(events, endIndex: index("p4")), .pending)
        expectEqual(PerfResumeLink.notApplicable.rawValue, "n/a")

        // after_parent reloads continue the same play: not a new play in the daily summary.
        let reload = [
            event(.videoStart, ["play": .string("q1"), "video": .string("c"), "source": .string("pick")],
                  at: 100, seq: 10, mode: "play"),
            event(.videoStart, ["play": .string("q2"), "video": .string("c"), "source": .string("after_parent")],
                  at: 200, seq: 11, mode: "play")
        ]
        let reloadDays = Set(reload.map { PerfClock.dayStamp($0.timestamp, timeZone: PerfClock.hongKong) })
        let reloadDay = PerfSummaries.daySummaries(events: reload, days: reloadDays, excluded: [],
                                                   timeZone: PerfClock.hongKong).values.first
        expectEqual(reloadDay?.videos["c"]?.plays, 1)
        expectTrue(PerfVideoStopReason.visaExpired.isTimeUp && PerfVideoStopReason.budgetExhausted.isTimeUp)
        expectFalse(PerfVideoStopReason.navGuard.isTimeUp)
        expectEqual(PerfVideoStopReason.navGuard.rawValue, "nav_guard")
        expectEqual(PerfVideoStopReason.storageReset.rawValue, "storage_reset")
        expectEqual(PerfVideoStopReason.appTerminate.rawValue, "app_terminate")
        expectEqual(PerfEventType.resumeCleared.rawValue, "resume_cleared")
    }

    /// v0.20.1 UAT: 「進階」 was a macOS DisclosureGroup (only the chevron toggles). Source guard:
    /// the Advanced header is a plain button, and the footer label matches Info.plist.
    func testParentAdvancedIsAButtonAndVersionMatchesInfoPlist() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let view = try String(contentsOf: root.appendingPathComponent("Sources/VisaGames/ParentSettingsView.swift"),
                              encoding: .utf8)
        let plist = try String(contentsOf: root.appendingPathComponent("Resources/Info.plist"), encoding: .utf8)
        func plistValue(_ key: String) -> String? {
            guard let keyRange = plist.range(of: "<key>\(key)</key><string>"),
                  let end = plist.range(of: "</string>", range: keyRange.upperBound..<plist.endIndex) else { return nil }
            return String(plist[keyRange.upperBound..<end.lowerBound])
        }
        let version = plistValue("CFBundleShortVersionString") ?? "?"
        expectTrue(view.contains("static let versionLabel = \"Visa Games v\(version)\""))
        expectEqual(version, "0.21.2")
        expectEqual(plistValue("CFBundleVersion"), "46")
        guard let start = view.range(of: "private func advancedSection("),
              let end = view.range(of: "private var advancedContent", range: start.upperBound..<view.endIndex) else {
            expectTrue(false)
            return
        }
        let header = view[start.upperBound..<end.lowerBound]
        expectFalse(header.contains("DisclosureGroup"))
        expectTrue(header.contains("Button(action: { toggleAdvanced(proxy: proxy) })"))
        expectTrue(header.contains(".contentShape(Rectangle())"))
        expectTrue(header.contains("scrollTo(Self.advancedAnchor"))
    }

    // MARK: Retention

    func testRetentionKeepsNinetyHongKongDaysIncludingToday() {
        let tz = PerfClock.hongKong
        let days = ["2026-07-10", "2026-07-11", "2026-07-12", "2026-10-09"]
        expectEqual(PerfRetention.expiredDays(days, today: "2026-10-09", timeZone: tz), ["2026-07-10", "2026-07-11"])
        expectEqual(PerfClock.dayStamp("2026-10-09", minusDays: 89, timeZone: tz), "2026-07-12")
        expectEqual(PerfClock.dayStamp("2026-03-01", minusDays: 1, timeZone: tz), "2026-02-28")
        expectEqual(PerfRetention.rawDays, 90)
    }

    func testPruneFoldsDailySummariesThenDeletesAndIsIdempotent() throws {
        let (store, root) = tempStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = PerfCodec.parseTimestamp("2026-06-01T04:00:00.000Z")!  // 12:00 HKT 1 Jun
        func oldEvent(_ type: PerfEventType, _ fields: [String: PerfValue], _ offset: TimeInterval, _ seq: Int,
                      actor: PerfActor = .child, session: String = "s1") -> PerfEvent {
            PerfEvent(type: type, timestamp: old.addingTimeInterval(offset), tz: "+08:00", mono: offset,
                      launch: "L0", seq: seq, app: "0.20.0", actor: actor, mode: "lock", session: session,
                      fields: fields)
        }
        try store.append([
            oldEvent(.gameDealt, ["round": .string("r1"), "kind": .string("findTheSame"), "stars": .int(2)], 0, 1),
            oldEvent(.roundResult, ["round": .string("r1"), "outcome": .string("solved"), "first_try": .bool(true),
                                    "misses": .int(0), "answers": .int(1), "active_ms": .int(4000)], 5, 2),
            oldEvent(.gameDealt, ["round": .string("r2"), "kind": .string("findTheSame"), "stars": .int(2)], 10, 3,
                     actor: .parentUAT),
            oldEvent(.gameDealt, ["round": .string("r3"), "kind": .string("findTheSame"), "stars": .int(2)], 20, 4,
                     session: "s9"),
            oldEvent(.statsExclude, ["target_session": .string("s9")], 30, 5, actor: .parent, session: "p"),
            oldEvent(.videoImpressions, ["visit": .string("v"), "page": .int(0), "ids": .strings(["a", "b"])], 40, 6),
            oldEvent(.videoPick, ["visit": .string("v"), "video": .string("a"), "accepted": .bool(true)], 41, 7),
            oldEvent(.videoStart, ["play": .string("p"), "video": .string("a"), "source": .string("pick")], 41, 8),
            oldEvent(.videoEnd, ["play": .string("p"), "video": .string("a"), "stop_reason": .string("budget_exhausted"),
                                 "watched_s": .double(90)], 140, 9)
        ])
        try store.append([event(.appLaunch, seq: 1, actor: .system)])  // today, kept
        let now = base
        let outcome = try PerfRetention.prune(store: store, now: now)
        expectEqual(outcome.folded, ["2026-06-01"])
        expectEqual(outcome.deleted, ["2026-06-01"])
        expectEqual(store.eventDays(), ["2026-10-09"])
        let rollup = store.loadRollup()
        let day = rollup.days["2026-06-01"]
        let games = day?.games["findTheSame|2"]
        expectEqual(games?.deals, 1)          // r2 is UAT, r3 is in an excluded session
        expectEqual(games?.firstTry, 1)
        expectEqual(games?.activeMs, 4000)
        expectEqual(day?.uncountedRounds, 2)
        expectEqual(day?.videos["a"]?.impressions, 1)
        expectEqual(day?.videos["a"]?.picks, 1)
        expectEqual(day?.videos["a"]?.plays, 1)
        expectEqual(day?.videos["a"]?.timeUpCuts, 1)
        expectEqual(day?.videos["a"]?.watchedSeconds, 90)
        expectEqual(day?.videos["b"]?.picks, 0)

        // Second run: nothing to do.
        expectEqual(try PerfRetention.prune(store: store, now: now), PerfRetention.Outcome(folded: [], deleted: []))
        // Crash between the rollup write and the delete: the raw file is back but already folded.
        try store.append([oldEvent(.gameDealt, ["round": .string("r1"), "kind": .string("findTheSame"),
                                                "stars": .int(2)], 0, 1)])
        let retry = try PerfRetention.prune(store: store, now: now)
        expectEqual(retry.folded, [])
        expectEqual(retry.deleted, ["2026-06-01"])
        expectEqual(store.loadRollup(), rollup)  // not counted twice
        let export = PerfCSVExport.files(events: store.read().events, rollup: rollup, titles: ["a": "Apple"])
        expectTrue((export["daily_games.csv"] ?? "").contains("2026-06-01,findTheSame,"))
        expectTrue((export["daily_videos.csv"] ?? "").contains("2026-06-01,a,Apple,1,1,1,0,1,0,0,0,0,1.5"))
    }

    // MARK: Language lock

    func testPerformanceStringsAreTraditionalChineseOnly() throws {
        // Parent-facing strings live in the app target; scan the sources (tests run from the repo root).
        let files = [
            "Sources/VisaGames/ParentSettingsView.swift",
            "Sources/VisaGames/PerformanceRecorder.swift",
            "Sources/VisaGames/AppDelegate.swift",
            "Sources/VisaCore/PerformanceCSV.swift",
            "Sources/VisaCore/PerformanceEvent.swift",
            "Sources/VisaCore/PerformanceTrackers.swift",
            "Sources/VisaCore/PerformanceEventStore.swift",
            "Sources/VisaCore/PerformanceCatalog.swift",
            "Sources/VisaGames/ParentReviewView.swift",
            "Sources/VisaCore/PerformanceReport.swift",
            "Sources/VisaCore/MasteryEstimator.swift",
            "Sources/VisaCore/VideoAppeal.swift"
        ]
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for path in files {
            let url = cwd.appendingPathComponent(path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            precondition(isTraditionalChineseOnly(text) && perfTraditionalOnly(text),
                         "Simplified Chinese character in \(path)")
        }
        expectFalse(perfTraditionalOnly("表现记录"))
        expectTrue(perfTraditionalOnly("表現紀錄 · 唔計呢段 · 家長測試中"))
    }
}

/// Stricter list for the D10 strings (only characters that never appear in HK Traditional text).
func perfTraditionalOnly(_ text: String) -> Bool {
    let simplified: Set<Character> = [
        "录", "纪", "记", "计", "测", "试", "导", "汇", "储", "设", "机", "会", "传", "时", "钟", "间",
        "频", "视", "观", "简", "动", "开", "关", "让", "应", "该", "断", "电", "画", "页", "选",
        "择", "难", "题", "错", "对", "远", "这", "们", "个", "车", "长", "发", "说", "还", "听", "务",
        "现", "数", "统", "启", "仅", "条", "过", "钮", "签", "证", "删", "隐"
    ]
    return !text.contains(where: { simplified.contains($0) })
}
