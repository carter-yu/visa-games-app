import Foundation

// Hanzi H1 pure core (0.38.0 / 82): design hanzi-tap v2 (LOCKED D1–D12) and the six-target addendum
// (2026-11-06). Settings, recognition progress, the week scheduler, 2 × 5 Find & flip deals, cue decks, the
// round index and writing progress for 中文字 · 翻字卡 (`tapHanziAll`) and 搵完寫 (`tapHanziWrite`). The H2 find
// board (`HanziFind.swift`) deals through it. Every value lives in its own `VisaGames.tapHanzi*` store under `hanzi:<glyph>` keys; no
// letter store, key or value is read or written. Only pack targets are dealt, retried, reviewed or written;
// find-only glyphs (入 八 本 未) are board distractors only (D2).

// MARK: - Settings

/// Parent intent, `VisaGames.tapHanziSettings.v1`. Missing, unreadable, another schema version or an
/// out-of-range value loads `defaults`: audio and jyutping OFF (D4). The games are OFF elsewhere: both kinds are
/// in `ActivityCatalog.defaultOffKinds` (no star before a playtest, D6) and are not playable before H2–H4.
public struct HanziTapSettings: Codable, Equatable, Sendable {
    public static let currentSchema = 1

    public var schemaVersion: Int
    /// 今星期 in the parent's order. Empty, or fewer than three pack targets, means the pack's week.
    public var week: [String]
    /// 溫習「每 4 輪 1 輪」: 4, or 0 for none.
    public var reviewEvery: Int
    /// 易混字護欄.
    public var confusableGuard: Bool
    /// 廣東話語音 (D4: OFF).
    public var audioEnabled: Bool
    /// 粵拼 (D4: OFF).
    public var jyutpingEnabled: Bool

    public init(week: [String] = [], reviewEvery: Int = 4, confusableGuard: Bool = true,
                audioEnabled: Bool = false, jyutpingEnabled: Bool = false) {
        schemaVersion = Self.currentSchema
        self.week = week
        self.reviewEvery = reviewEvery
        self.confusableGuard = confusableGuard
        self.audioEnabled = audioEnabled
        self.jyutpingEnabled = jyutpingEnabled
    }

    public static let defaults = Self()

    /// Pack targets in the parent's order, each once; never a find-only or unknown glyph. Fewer than three
    /// (`HanziScheduler.minimumWeek`) → the pack's week: in a two-target week a missed target could not wait out
    /// two other rounds without an immediate repeat.
    public func validWeek(in pack: HanziPack) -> [String] {
        var unique: [String] = []
        for glyph in week where pack.isTarget(glyph) && !unique.contains(glyph) { unique.append(glyph) }
        return unique.count >= HanziScheduler.minimumWeek ? unique : pack.defaults.week
    }
}

public struct HanziTapSettingsStore {
    public static let key = "VisaGames.tapHanziSettings.v1"
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> HanziTapSettings {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(HanziTapSettings.self, from: data),
              value.schemaVersion == HanziTapSettings.currentSchema,
              value.reviewEvery == 0 || value.reviewEvery == 4 else { return .defaults }
        return value
    }
    public func save(_ value: HanziTapSettings) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

// MARK: - Recognition progress

/// One week target's finding state: the letter family's three boxes and rules (design run 1), stored under a
/// `hanzi:` key in the Hanzi store. No Latin state is shared or carried over.
public struct HanziGlyphState: Codable, Equatable, Sendable {
    public var box: LetterBox = .learning
    public var lastSeen: Date?
    public var cleanRounds = 0
    public var firstCleanDay: Date?
    public var hasTargetRound = false
    /// A clean find round ever: lifts the confusable guard for good (design: "before first clean target round"),
    /// so a later miss, which resets `cleanRounds`, does not re-arm it.
    public var hasCleanRound = false
    public init() {}

    enum CodingKeys: String, CodingKey { case box, lastSeen, cleanRounds, firstCleanDay, hasTargetRound, hasCleanRound }

    /// State saved before `hasCleanRound` existed derives it from `cleanRounds` (a streak a miss already reset
    /// reads false); every other field decodes as before.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        box = try values.decode(LetterBox.self, forKey: .box)
        lastSeen = try values.decodeIfPresent(Date.self, forKey: .lastSeen)
        cleanRounds = try values.decode(Int.self, forKey: .cleanRounds)
        firstCleanDay = try values.decodeIfPresent(Date.self, forKey: .firstCleanDay)
        hasTargetRound = try values.decode(Bool.self, forKey: .hasTargetRound)
        hasCleanRound = try values.decodeIfPresent(Bool.self, forKey: .hasCleanRound) ?? (cleanRounds > 0)
    }
}

public struct HanziRetry: Codable, Equatable, Sendable {
    public let glyph: String
    public let dueRound: Int
    public init(glyph: String, dueRound: Int) { self.glyph = glyph; self.dueRound = dueRound }
}

/// `VisaGames.tapHanziProgress.v1`, shared by both Hanzi kinds (as `LetterProgress` is by both letter kinds).
public struct HanziProgress: Codable, Equatable, Sendable {
    public static let keyPrefix = "hanzi:"

    /// `hanzi:<glyph>` → finding state.
    public var glyphs: [String: HanziGlyphState] = [:]
    public var retryQueue: [HanziRetry] = []
    public var lastTarget: String?
    /// The week the current cycle deals from, its number (0 = the week's own order) and the week targets it
    /// has dealt (week rounds and retries).
    public var cycleWeek: [String] = []
    public var cycle = 0
    public var cycleDealt: [String] = []
    public init() {}

    public static func key(_ glyph: String) -> String { keyPrefix + glyph }
    public func state(for glyph: String) -> HanziGlyphState { glyphs[Self.key(glyph)] ?? HanziGlyphState() }

    /// A finished round of `choice`; `clean` = found first try with no hint. Box rules as
    /// `LetterProgress.record`; a miss is retried after two intervening rounds.
    public mutating func record(_ choice: HanziChoice, clean: Bool, round: Int, at date: Date) {
        let target = choice.target
        var state = state(for: target)
        state.hasTargetRound = true
        state.lastSeen = date
        if clean {
            state.cleanRounds += 1
            state.hasCleanRound = true
            if state.firstCleanDay == nil { state.firstCleanDay = date }
            if state.cleanRounds >= 3, let first = state.firstCleanDay,
               !Calendar(identifier: .gregorian).isDate(first, inSameDayAs: date) { state.box = .known }
            else if state.cleanRounds >= 2 { state.box = .practising }
        } else {
            state.cleanRounds = 0
            state.firstCleanDay = nil
            state.box = .learning
            retryQueue.append(HanziRetry(glyph: target, dueRound: round + HanziScheduler.retryAfterInterveningRounds + 1))
        }
        glyphs[Self.key(target)] = state
        lastTarget = target
        retryQueue.removeAll { $0.glyph == target && $0.dueRound <= round }
        // A week target dealt as a week round or a retry is this cycle's visit, so the cycle never hands
        // back the target just played.
        guard choice.lane != .review, choice.week.contains(target) else { return }
        if cycleWeek != choice.week || cycle != choice.cycle {
            cycleWeek = choice.week
            cycle = choice.cycle
            cycleDealt = []
        }
        if !cycleDealt.contains(target) { cycleDealt.append(target) }
    }
}

/// Versioned by its key, as the letter stores: the blob has no version field, so a well-formed one under `.v1`
/// decodes as v1 (extra fields ignored), and an incompatible format must take a new key (`.v2`) that this store
/// never reads. Missing or unreadable → empty. Only the settings store checks a `schemaVersion`.
public struct HanziProgressStore {
    public static let key = "VisaGames.tapHanziProgress.v1"
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> HanziProgress {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(HanziProgress.self, from: data) else { return HanziProgress() }
        return value
    }
    public func save(_ value: HanziProgress) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

// MARK: - Scheduler

public struct HanziChoice: Equatable, Sendable {
    public let target: String
    public let lane: LetterLane
    /// The week and cycle the target was drawn from; `HanziProgress.record` keeps them.
    public let week: [String]
    public let cycle: Int
}

/// The run-1 scheduler kept by design v2 and the addendum: each week target once per cycle (the first cycle in
/// the week's order, later cycles reshuffled), never the same target twice in a row (also across a cycle
/// boundary), a missed target dealt by no lane until two other rounds intervene and then retried, and every
/// fourth round an older target that is due. A pure function of its inputs: the same seed and state give the
/// same choice.
public enum HanziScheduler {
    public static let retryAfterInterveningRounds = 2
    /// The fewest week targets that let a miss wait out its intervening rounds with no immediate repeat.
    public static let minimumWeek = retryAfterInterveningRounds + 1

    /// `n` is the 1-based child round number (completed Hanzi rounds + 1).
    public static func next(seed: String, n: Int, settings: HanziTapSettings, progress: HanziProgress,
                            pack: HanziPack, now: Date) -> HanziChoice {
        let week = settings.validWeek(in: pack)
        let last = progress.lastTarget
        // Every lane skips the last target and a missed target whose retry is not due yet, so a miss is dealt again
        // only after two intervening rounds, whichever lane would deal it.
        let cooling = Set(progress.retryQueue.filter { $0.dueRound > n }.map(\.glyph))
        func ready(_ glyph: String) -> Bool { glyph != last && !cooling.contains(glyph) }
        let sameWeek = progress.cycleWeek == week
        var cycle = sameWeek ? progress.cycle : 0
        var dealt = sameWeek ? progress.cycleDealt : []
        if week.allSatisfy(dealt.contains) {
            cycle += 1
            dealt = []
        }
        func choice(_ target: String, _ lane: LetterLane) -> HanziChoice {
            HanziChoice(target: target, lane: lane, week: week, cycle: cycle)
        }
        // Review: an older target (played before, outside this week) whose box spacing has passed (as letters).
        // It goes before a due retry, which stays queued for the next round.
        if settings.reviewEvery > 0 && n % settings.reviewEvery == 0 {
            let order = pack.board.targetWeek
            let due = progress.glyphs.compactMap { key, state -> (glyph: String, state: HanziGlyphState)? in
                guard key.hasPrefix(HanziProgress.keyPrefix) else { return nil }
                let glyph = String(key.dropFirst(HanziProgress.keyPrefix.count))
                guard pack.isTarget(glyph), !week.contains(glyph), ready(glyph), state.hasTargetRound else { return nil }
                let days: Double = state.box == .known ? 7 : state.box == .practising ? 2 : 0
                return now.timeIntervalSince(state.lastSeen ?? now) >= days * 86_400 ? (glyph, state) : nil
            }
            if let pick = due.min(by: { lhs, rhs in
                if lhs.state.box != rhs.state.box { return lhs.state.box < rhs.state.box }
                if lhs.state.lastSeen != rhs.state.lastSeen {
                    return (lhs.state.lastSeen ?? .distantPast) < (rhs.state.lastSeen ?? .distantPast)
                }
                return (order.firstIndex(of: lhs.glyph) ?? .max) < (order.firstIndex(of: rhs.glyph) ?? .max)
            }) {
                return choice(pick.glyph, .review)
            }
        }
        if let retry = progress.retryQueue.filter({ $0.dueRound <= n && ready($0.glyph) && pack.isTarget($0.glyph) })
            .min(by: { ($0.dueRound, $0.glyph) < ($1.dueRound, $1.glyph) }) {
            return choice(retry.glyph, .retry)
        }
        var rng = QuestionRNG(seed: seed, salt: "hanzi-week-\(cycle)")
        let order = cycle == 0 ? week : rng.shuffled(week)
        let open = order.filter { !dealt.contains($0) }
        // Only the last two rounds' targets can be not ready, and the cycle has dealt both unless it began within
        // them, so a week of `minimumWeek` targets always leaves a ready one. The fallbacks only serve a store
        // whose round index fell behind its retries.
        return choice(open.first(where: ready) ?? open.first { $0 != last } ?? open.first ?? week[0], .week)
    }
}

// MARK: - Board

/// One 2 × 5 Find & flip deal: both rows permute the same five distinct glyphs, so each shows twice, and the
/// target is once in each row, in different columns.
public struct HanziBoard: Equatable, Sendable {
    public let target: String
    /// The five-glyph display set, target first. A week glyph outside it is not shown this deal (addendum §2).
    public let glyphs: [String]
    public let rows: [[String]]
    /// Paired confusables the guard keeps off this board (the target has no clean find round yet).
    public let guarded: [String]
    /// Guarded week neighbour → the validated find-only glyph shown in its place (addendum §3).
    public let replacements: [String: String]

    /// Row-major card indices of the two targets.
    public var targetCards: [Int] {
        rows.enumerated().compactMap { row, cells in cells.firstIndex(of: target).map { row * cells.count + $0 } }
    }
    public var cards: [String] { rows.flatMap { $0 } }
}

public enum HanziBoardBuilder {
    /// Nil (no deal) rather than a weaker board: a glyph that is not a pack target, a guarded week neighbour
    /// with no validated find-only glyph to stand in (guardMode: refuse), or fewer than five distinct glyphs.
    public static func make(seed: String, target: String, week: [String], confusableGuard: Bool,
                            progress: HanziProgress, pack: HanziPack) -> HanziBoard? {
        guard pack.isTarget(target), pack.board.rows == 2, pack.board.symbolsPerRow == 5 else { return nil }
        let findOnly = pack.dealableFindOnly
        let shown = Set(pack.board.targetWeek + findOnly)
        let partners = pack.board.confusablePairs.filter { $0.contains(target) }.flatMap { $0 }.filter { $0 != target }
        // Until the target's first clean find round its partners stay off the board. Unlike letters' mirror guard,
        // a later miss does not bring it back (design: "before first clean target round").
        let isGuarded = confusableGuard && !progress.state(for: target).hasCleanRound
        let blocked = isGuarded ? partners : []
        var glyphs = [target]
        func add(_ values: [String]) {
            for value in values where glyphs.count < 5 && shown.contains(value) && !glyphs.contains(value)
                && !blocked.contains(value) { glyphs.append(value) }
        }
        var pick = QuestionRNG(seed: seed, salt: "hanzi-board-set-\(target)")
        var replacements: [String: String] = [:]
        if isGuarded {
            // Each guarded week neighbour gives its place to a validated find-only glyph; none left → no deal.
            var spare = pick.shuffled(findOnly.filter { !blocked.contains($0) })
            for neighbour in blocked where week.contains(neighbour) {
                guard !spare.isEmpty else { return nil }
                let standIn = spare.removeFirst()
                replacements[neighbour] = standIn
                add([standIn])
            }
        } else {
            // After a clean find round, or with the guard off, the pairs are dealt on purpose (run 1).
            add(partners.filter { week.contains($0) || findOnly.contains($0) })
        }
        add(pick.shuffled(week))
        add(pick.shuffled(findOnly))
        // A two-target week with 人 or 木 guarded reaches four: the pack's other targets fill the row (addendum §2).
        // Only a direct call meets it: `validWeek` hands the scheduler three or more targets.
        add(pick.shuffled(pack.board.targetWeek))
        guard glyphs.count == 5 else { return nil }

        // Never a row in build order or pack order, or either reversed (letters' abcde / edcba rule).
        let packOrder = pack.board.targetWeek + pack.board.approvedFindOnlyPool
        let ordered = glyphs.sorted { (packOrder.firstIndex(of: $0) ?? .max) < (packOrder.firstIndex(of: $1) ?? .max) }
        let plain = [glyphs, Array(glyphs.reversed()), ordered, Array(ordered.reversed())]
        func valid(_ rows: [[String]]) -> Bool {
            rows[0] != rows[1] && rows[0].firstIndex(of: target) != rows[1].firstIndex(of: target)
                && !rows.contains(where: plain.contains)
        }
        func board(_ rows: [[String]]) -> HanziBoard {
            HanziBoard(target: target, glyphs: glyphs, rows: rows, guarded: blocked, replacements: replacements)
        }
        var shuffle = QuestionRNG(seed: seed, salt: "hanzi-board-\(target)")
        for _ in 0..<50 {
            let rows = [shuffle.shuffled(glyphs), shuffle.shuffled(glyphs)]
            if valid(rows) { return board(rows) }
        }
        // As letters: a fixed scramble and a rotation of it (a rotation moves every column).
        for first in [[glyphs[2], glyphs[4], glyphs[0], glyphs[3], glyphs[1]],
                      [glyphs[3], glyphs[0], glyphs[4], glyphs[1], glyphs[2]]] {
            for shift in 1..<5 {
                let rows = [first, Array(first.suffix(shift)) + Array(first.prefix(5 - shift))]
                if valid(rows) { return board(rows) }
            }
        }
        return nil
    }
}

// MARK: - Cue decks

/// `VisaGames.tapHanziCueDecks.v1`: which of a target's two cue pictures the first flip shows. A deal shows
/// both (never one twice) and leads with the other picture than last time.
public struct HanziCueDecks: Codable, Equatable, Sendable {
    /// `hanzi:<glyph>` → the picture the last deal led with.
    public var leads: [String: String] = [:]
    public init() {}

    /// The target's two pictures in flip order; empty for a find-only or unknown glyph (it never flips).
    public mutating func deal(_ glyph: String, pack: HanziPack) -> [String] {
        guard let pictures = pack.characters[glyph]?.cuePictures, pictures.count >= 2 else { return [] }
        let key = HanziProgress.key(glyph)
        let lead = pictures.first { $0 != leads[key] } ?? pictures[0]
        leads[key] = lead
        return [lead, pictures.first { $0 != lead } ?? pictures[1]]
    }
}

/// Versioned by its `.v1` key, as `HanziProgressStore`; missing or unreadable → empty.
public struct HanziCueDecksStore {
    public static let key = "VisaGames.tapHanziCueDecks.v1"
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> HanziCueDecks {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(HanziCueDecks.self, from: data) else { return HanziCueDecks() }
        return value
    }
    public func save(_ value: HanziCueDecks) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// Completed Hanzi child rounds (both kinds, every lane), as `LetterRoundIndexStore`; versioned by its `.v1` key.
public struct HanziRoundIndexStore {
    public static let key = "VisaGames.tapHanziRoundIndex.v1"
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> Int { max(0, defaults.integer(forKey: Self.key)) }
    public func save(_ value: Int) { defaults.set(max(0, value), forKey: Self.key) }
}

// MARK: - Writing progress

/// `VisaGames.tapHanziWriteProgress.v1`: a week target is learned after two clean writes in a row, and a
/// non-clean write resets its streak (the `LetterWriteProgress` rule). Its own store and `hanzi:` keys, so no
/// Latin streak is read or written; a find-only glyph is never written and never gets a streak.
public struct HanziWriteProgress: Codable, Equatable, Sendable {
    public private(set) var streaks: [String: Int] = [:]
    public init() {}

    public func streak(_ glyph: String) -> Int { streaks[HanziProgress.key(glyph)] ?? 0 }
    public func isLearned(_ glyph: String) -> Bool { streak(glyph) >= 2 }

    /// False, with nothing recorded, for a glyph that is not a week target of `pack`.
    @discardableResult public mutating func record(_ glyph: String, clean: Bool, pack: HanziPack) -> Bool {
        guard pack.isTarget(glyph) else { return false }
        streaks[HanziProgress.key(glyph)] = clean ? min(99, streak(glyph) + 1) : 0
        return true
    }

    /// The letter completion rule (`finishTapLetterRound`): no coach help noted (stall, ghost, re-demo), no
    /// wrong start, no reversal and no off-path event. Writing help is practice, never a finding miss.
    public static func isClean(guide: TapCountGuideRun?, trace: ShapeTraceBoard) -> Bool {
        (guide?.clean ?? true) && trace.wrongStarts == 0 && trace.reverseDirections == 0 && trace.offPathCount == 0
    }
}

/// Versioned by its `.v1` key, as `HanziProgressStore`; missing or unreadable → empty.
public struct HanziWriteProgressStore {
    public static let key = "VisaGames.tapHanziWriteProgress.v1"
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> HanziWriteProgress {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(HanziWriteProgress.self, from: data) else { return .init() }
        return value
    }
    public func save(_ value: HanziWriteProgress) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

// MARK: - Deal

public struct HanziDeal: Equatable, Sendable {
    public let kind: ActivityKind
    public let choice: HanziChoice
    public let board: HanziBoard
    /// The target's two cue pictures in flip order.
    public let cues: [String]
    /// Cue decks after this deal, saved with the finished round.
    public let decks: HanziCueDecks
}

public enum HanziNoDealReason: Equatable, Sendable {
    /// The pack is missing, unreadable or another schema: the Hanzi games stay off.
    case packUnavailable
    case notHanziKind
    /// Fewer than five glyphs, or a guarded neighbour with no validated find-only glyph to stand in.
    case insufficientBoardGlyphs
}

public enum HanziDealResult: Equatable, Sendable {
    case deal(HanziDeal)
    case unavailable(HanziNoDealReason)
    public var deal: HanziDeal? {
        if case .deal(let value) = self { return value }
        return nil
    }
}

public enum TapHanziGenerator {
    /// `pack` is nil when `HanziPack.load` failed; nothing is dealt then.
    public static func make(seed: String, kind: ActivityKind, n: Int, settings: HanziTapSettings,
                            progress: HanziProgress, decks: HanziCueDecks, pack: HanziPack?,
                            now: Date) -> HanziDealResult {
        guard kind.isTapHanziFamily else { return .unavailable(.notHanziKind) }
        guard let pack else { return .unavailable(.packUnavailable) }
        let choice = HanziScheduler.next(seed: seed, n: n, settings: settings, progress: progress, pack: pack, now: now)
        guard let board = HanziBoardBuilder.make(seed: seed, target: choice.target, week: choice.week,
                                                 confusableGuard: settings.confusableGuard,
                                                 progress: progress, pack: pack) else {
            return .unavailable(.insufficientBoardGlyphs)
        }
        var next = decks
        let cues = next.deal(choice.target, pack: pack)
        return .deal(HanziDeal(kind: kind, choice: choice, board: board, cues: cues, decks: next))
    }
}
