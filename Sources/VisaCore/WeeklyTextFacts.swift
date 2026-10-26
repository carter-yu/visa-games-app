import Foundation

// Weekly report W3: the few facts the text needs that W1 and W2 do not keep — off-path per shape or road,
// wrong starts, guide_clean, the 連一連 wrong lines per category, this week's setting values, the
// most-watched videos (D8 B) and the numerals learned. Read from the same index and counted rounds as
// W1 / W2; ADR 0023 lists the definitions. Pure value code.

/// A game row of one window: (kind, type), as in W1.
struct WeeklyRowKey: Hashable {
    let kind: String
    let type: WeeklyRoundType

    init(kind: String, type: WeeklyRoundType) {
        self.kind = kind
        self.type = type
    }

    init(_ game: WeeklyGame) {
        self.init(kind: game.kind, type: game.type)
    }

    /// "countVehicles/quiz", the key the text JSON paths use.
    var text: String { kind + "/" + type.rawValue }
}

/// What the text reads off one row's counted rounds in one window.
public struct WeeklyRowFacts: Sendable, Equatable {
    /// Σ `off_path_count` and Σ `shapes_total` (lines, shapes) or `roads_total` (roads) over solved rounds
    /// that wrote both.
    public var offPath = 0
    public var offPathUnits = 0
    /// Solved rounds with `wrong_start` > 0, and solved rounds that wrote it.
    public var wrongStart = 0
    public var wrongStartKnown = 0
    /// Solved rounds with `guide_clean`, and solved rounds that wrote it.
    public var guideClean = 0
    public var guideCleanKnown = 0
    /// 連一連 · 自己配 (quiz): wrong lines (`answer_attempt.wrong_lines`) per `game_dealt.category`, and in all.
    public var wrongLines: [String: Int] = [:]
    public var wrongLinesTotal = 0

    public init() {}
}

/// This week's setting values: the last value in the countable deals (or their results), in record order.
public struct WeeklySettingsSeen: Sendable, Equatable {
    public var range: Int?
    public var countVoice: Bool?
    public var traceScaffold: String?
    public var guideLevel: String?
    public var lineTolerance: String?
    public var categoryMix: String?
    public var directionHint: Bool?
    public var slantLines: Bool?

    public init() {}
}

/// D8 B: one of the most-watched videos this week.
public struct WeeklyVideoTime: Sendable, Equatable {
    public var video: String
    public var watchedMs: Int
    /// The parent's label for the video, else its id.
    public var title: String
}

struct WeeklyTextFacts {
    /// D8 B: at most 3 videos, each with at least one (rounded) minute.
    static let videoCount = 3

    var rows: [WeeklyRowKey: WeeklyRowFacts] = [:]
    var previousRows: [WeeklyRowKey: WeeklyRowFacts] = [:]
    var settings = WeeklySettingsSeen()
    var videos: [WeeklyVideoTime] = []
    /// Numerals with a counted round that started `guide_learned_before == 1`, before or during the week.
    var numeralsLearned: [Int] = []
    /// Days that started before the cut-off and end after the first record (W1 `coveredDays`).
    var coveredDays: [Int] = []

    init(index: WeeklyMetricsBuilder.Index, model: WeeklyModel, rollup: PerfRollup, videoTitles: [String: String]) {
        let window = model.window
        var dealtByRound: [String: PerfEvent] = [:]
        for entry in index.dealt where entry.countable && !entry.round.isEmpty && dealtByRound[entry.round] == nil {
            dealtByRound[entry.round] = entry.event
        }
        rows = Self.rowFacts(index, model.current, dealtByRound)
        previousRows = Self.rowFacts(index, model.previous, dealtByRound)
        settings = Self.settingsSeen(index, window)
        videos = Self.videoTimes(index, window, videoTitles)
        let wins = WeeklyWinFacts(index: index, rollup: rollup, window: window)
        numeralsLearned = wins.learnedBefore.union(wins.learnedThisWeek).sorted()
        if let first = index.firstEvent {
            coveredDays = (0..<WeeklyWindow.dayCount).filter {
                window.dayStarts[$0] < window.cutoff && window.dayStarts[$0 + 1] > first
            }
        }
    }

    static func rowFacts(_ index: WeeklyMetricsBuilder.Index, _ metrics: WeeklyWindowMetrics,
                         _ dealtByRound: [String: PerfEvent]) -> [WeeklyRowKey: WeeklyRowFacts] {
        let cutoff = metrics.window.cutoff
        var out: [WeeklyRowKey: WeeklyRowFacts] = [:]
        for round in metrics.rounds {
            let key = WeeklyRowKey(kind: round.kind, type: round.type)
            var facts = out[key] ?? WeeklyRowFacts()
            if round.type == .practice, round.outcome == .solved,
               let result = index.result(for: round.round, cutoff: cutoff) {
                let family = WeeklyPracticeFamily.of(kind: round.kind)
                if family == .lines || family == .shapes || family == .roads,
                   let off = result.int("off_path_count"),
                   let units = result.int(family == .roads ? "roads_total" : "shapes_total") {
                    facts.offPath += off
                    facts.offPathUnits += units
                }
                if let start = result.int("wrong_start") {
                    facts.wrongStartKnown += 1
                    if start > 0 { facts.wrongStart += 1 }
                }
                if let clean = WeeklyField.flag(result["guide_clean"]) {
                    facts.guideCleanKnown += 1
                    if clean { facts.guideClean += 1 }
                }
            }
            if round.type == .quiz, round.kind == ActivityKind.lineMatch.rawValue, !round.round.isEmpty {
                let category = dealtByRound[round.round]?.string("category")
                for attempt in index.wrongAttempts[round.round] ?? [] where attempt.timestamp <= cutoff {
                    let count = attempt["wrong_lines"]?.stringArray.count ?? 0
                    facts.wrongLinesTotal += count
                    if let category, count > 0 { facts.wrongLines[category, default: 0] += count }
                }
            }
            out[key] = facts
        }
        return out
    }

    static func settingsSeen(_ index: WeeklyMetricsBuilder.Index, _ window: WeeklyWindow) -> WeeklySettingsSeen {
        var seen = WeeklySettingsSeen()
        for entry in index.dealt where entry.countable && window.contains(entry.event.timestamp) {
            guard let kind = ActivityKind(rawValue: entry.kind) else { continue }
            let dealt = entry.event
            if kind.isTapCountFamily {
                if let range = dealt.int("range") { seen.range = range }
                if let voice = dealt.bool("count_voice") { seen.countVoice = voice }
                if let scaffold = dealt.string("trace_scaffold") { seen.traceScaffold = scaffold }
                if let result = index.result(for: entry.round, cutoff: window.cutoff),
                   let level = result.string("guide_level") {
                    seen.guideLevel = level
                }
            }
            if kind.isLineMatchFamily {
                if let tolerance = dealt.string("tolerance") { seen.lineTolerance = tolerance }
                if let mix = dealt.string("category_mix") { seen.categoryMix = mix }
            }
            if kind.isShapeTraceFamily {
                if let hint = dealt.bool("direction_coaching") { seen.directionHint = hint }
                if let slant = dealt.bool("slant_enabled") { seen.slantLines = slant }
            }
        }
        return seen
    }

    /// Watched milliseconds per video, counted as W1 counts video minutes: `video_end` in the week, and
    /// the last `video_progress` of a play without an end. Most watched first, then by id.
    static func videoTimes(_ index: WeeklyMetricsBuilder.Index, _ window: WeeklyWindow,
                           _ titles: [String: String]) -> [WeeklyVideoTime] {
        var playVideo: [String: String] = [:]
        for start in index.videoStarts {
            guard let play = start.string("play"), !play.isEmpty, let video = start.string("video"),
                  playVideo[play] == nil else { continue }
            playVideo[play] = video
        }
        var totals: [String: Int] = [:]
        for start in index.videoStarts where window.contains(start.timestamp) {
            guard window.dayIndex(start.timestamp) != nil, let play = start.string("play"), !play.isEmpty,
                  !(index.endedPlays[play] ?? []).contains(where: { $0 <= window.cutoff }) else { continue }
            let last = (index.progress[play] ?? []).last { $0.timestamp <= window.cutoff }
            if let video = start.string("video") {
                totals[video, default: 0] += WeeklyMetricsBuilder.watchedMs(last?.double("watched_s"))
            }
        }
        for end in index.videoEnds where window.contains(end.timestamp) {
            guard window.dayIndex(end.timestamp) != nil else { continue }
            let video = end.string("video") ?? playVideo[end.string("play") ?? ""]
            if let video {
                totals[video, default: 0] += WeeklyMetricsBuilder.watchedMs(end.double("watched_s"))
            }
        }
        let ranked = totals.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key.utf8.lexicographicallyPrecedes(rhs.key.utf8)
        }
        var out: [WeeklyVideoTime] = []
        for (video, ms) in ranked where WeeklyFormat.minutes(ms: ms) >= 1 && out.count < videoCount {
            out.append(WeeklyVideoTime(video: video, watchedMs: ms, title: titles[video] ?? video))
        }
        return out
    }
}
