import Foundation

// Hanzi H4 report (0.40.0 / 88): design hanzi-tap v2 § Engineering reuse (reporting) and § Parent settings ("Reports
// must use real recorded counts"). Built from recorded events only, per card and per `hanzi:<glyph>` target, with the
// 表現 review's countable filter and window. Finding (first-try recognition, wrong cards, confusion pairs, all from the
// find's own `answer_attempt`s) and writing help (the H3 write round's `round_result` fields) are separate tallies: a
// writing help event is never a finding miss, and a write left unfinished never undoes a find. Find-only glyphs (入 八
// 本 未) only ever appear as a wrong card: they get no row and no writing. Raw events are kept `PerfRetention.rawDays`
// days; older rounds are only the rollup's daily counts, so they get no detail line, only a count.

/// One week target's finding record on one card.
public struct HanziFindingRow: Equatable, Sendable {
    public let glyph: String
    /// Rounds of this target with at least one card tapped (a recorded `answer_attempt`).
    public var rounds = 0
    /// Both target cards flipped (the pack's `board.targetCards` distinct correct `choice`s) with no wrong card, from
    /// the round's own taps. Not `round_result.first_try`: that needs the whole round solved, so a 搵完寫 write left
    /// unfinished would undo the find.
    public var firstTry = 0
    /// Wrong cards (`answer_attempt` with `correct` false: the first tap on each wrong card, the board's penalty rule).
    public var wrongCards = 0
    /// Wrong cards that are the target's pack confusable partner (上↔下, 左↔右, 人↔入／八, 木↔本／未) → count.
    public var confusions: [String: Int] = [:]

    public init(glyph: String) { self.glyph = glyph }
}

/// One week target's writing help on 搵完寫 (the H3 write fields; practice, no score).
public struct HanziWritingRow: Equatable, Sendable {
    public let glyph: String
    /// Rounds whose write was recorded (`write_clean` present).
    public var writes = 0
    /// trace_clean: no coach help, wrong start, reversal or off-path event (`write_clean` true).
    public var clean = 0
    /// trace_assisted: every other recorded write.
    public var assisted = 0
    public var wrongStarts = 0
    public var reverses = 0
    public var offPath = 0
    /// The 2 s stall help (`guide_stalls`), the 8 s ghost to the stroke's end (`guide_ghost_to_end`) and the 20 s
    /// re-demo (`guide_redemos`).
    public var stalls = 0
    public var ghosts = 0
    public var redemos = 0

    public init(glyph: String) { self.glyph = glyph }
}

/// One Hanzi card's report: rows in the pack's week order, only for targets with a recorded event.
public struct HanziKindReport: Equatable, Sendable {
    public var finding: [HanziFindingRow] = []
    public var writing: [HanziWritingRow] = []
    /// Rounds in the window left only as the rollup's daily counts (their raw events are gone): in the 表現 row's
    /// counts, but with no taps or write fields, so in no line above.
    public var rolledUpRounds = 0

    public init(finding: [HanziFindingRow] = [], writing: [HanziWritingRow] = [], rolledUpRounds: Int = 0) {
        self.finding = finding
        self.writing = writing
        self.rolledUpRounds = rolledUpRounds
    }

    /// No line from retained events (rolled-up rounds may still exist).
    public var isEmpty: Bool { finding.isEmpty && writing.isEmpty }
}

public enum HanziReportBuilder {
    /// Each Hanzi card with a counted deal in `window`, or rolled-up rounds there (`rollup`, the 表現 rows' rule: a
    /// rollup day counts only when that day has no raw event); a card with neither has no entry. No pack → no report.
    public static func build(events: [PerfEvent], pack: HanziPack?, now: Date, window: PerfReportWindow,
                             timeZone: TimeZone = PerfClock.hongKong,
                             rollup: PerfRollup = PerfRollup()) -> [ActivityKind: HanziKindReport] {
        guard let pack else { return [:] }
        let ordered = PerfCodec.ordered(events)
        let excluded = PerfFilter.excludedSessions(in: ordered)
        let clock = PerfReportBuilder.DayClock(timeZone: timeZone, now: now)
        // Counted Hanzi deals in the window: round → card and target.
        var rounds: [String: (kind: ActivityKind, target: String)] = [:]
        for event in ordered where event.type == .gameDealt {
            guard PerfFilter.countable(event, excludedSessions: excluded),
                  let kind = event.string("kind").flatMap(ActivityKind.init(rawValue:)), kind.isTapHanziFamily,
                  window.contains(ageDays: clock.age(event.timestamp)),
                  let round = event.string("round"), let target = event.string("target"), pack.isTarget(target)
            else { continue }
            rounds[round] = (kind, target)
        }
        var finding: [ActivityKind: [String: HanziFindingRow]] = [:]
        var writing: [ActivityKind: [String: HanziWritingRow]] = [:]
        func partners(_ target: String, _ tapped: String) -> Bool {
            pack.board.confusablePairs.contains { Set($0) == [target, tapped] }
        }
        // Each round's find from its own taps: the board records a correct attempt for the first flip of each target
        // card and a wrong one for the first tap on each wrong card.
        var finds: [String: (flipped: Set<String>, wrong: Int)] = [:]
        for event in ordered {
            guard event.type == .answerAttempt || event.type == .roundResult,
                  let round = event.string("round"), let deal = rounds[round],
                  PerfFilter.countable(event, excludedSessions: excluded) else { continue }
            if event.type == .answerAttempt {
                guard let correct = event.bool("correct") else { continue }
                var taps = finds[round] ?? (flipped: [], wrong: 0)
                if correct {
                    if let card = event.string("choice") { taps.flipped.insert(card) }
                } else {
                    taps.wrong += 1
                    var find = finding[deal.kind]?[deal.target] ?? HanziFindingRow(glyph: deal.target)
                    find.wrongCards += 1
                    if let tapped = event.string("glyph"), partners(deal.target, tapped) {
                        find.confusions[tapped, default: 0] += 1
                    }
                    finding[deal.kind, default: [:]][deal.target] = find
                }
                finds[round] = taps
                continue
            }
            // Writing help only from 搵完寫's own write fields; never from the find.
            guard deal.kind == .tapHanziWrite, let clean = event.bool("write_clean") else { continue }
            var write = writing[deal.kind]?[deal.target] ?? HanziWritingRow(glyph: deal.target)
            write.writes += 1
            if clean { write.clean += 1 } else { write.assisted += 1 }
            write.wrongStarts += event.int("wrong_start") ?? 0
            write.reverses += event.int("reverse") ?? 0
            write.offPath += event.int("off_path") ?? 0
            write.stalls += event.int("guide_stalls") ?? 0
            write.ghosts += event.int("guide_ghost_to_end") ?? 0
            write.redemos += event.int("guide_redemos") ?? 0
            writing[deal.kind, default: [:]][deal.target] = write
        }
        for (round, taps) in finds {
            guard let deal = rounds[round] else { continue }
            var find = finding[deal.kind]?[deal.target] ?? HanziFindingRow(glyph: deal.target)
            find.rounds += 1
            if taps.wrong == 0 && taps.flipped.count >= pack.board.targetCards { find.firstTry += 1 }
            finding[deal.kind, default: [:]][deal.target] = find
        }
        // Days with no raw event left: the rollup's per-card daily deals (counts only).
        var rawDays: Set<Int> = []
        for event in ordered { rawDays.insert(clock.day(event.timestamp)) }
        var rolledUp: [ActivityKind: Int] = [:]
        for (stamp, summary) in rollup.days {
            guard let day = clock.day(stamp: stamp), !rawDays.contains(day),
                  window.contains(ageDays: max(0, clock.today - day)) else { continue }
            for (key, stats) in summary.games where stats.deals > 0 {
                guard let name = key.split(separator: "|").first, let kind = ActivityKind(rawValue: String(name)),
                      kind.isTapHanziFamily else { continue }
                rolledUp[kind, default: 0] += stats.deals
            }
        }
        var reports: [ActivityKind: HanziKindReport] = [:]
        for kind in Set(rounds.values.map(\.kind)).union(rolledUp.keys) {
            let week = pack.board.targetWeek
            reports[kind] = HanziKindReport(finding: week.compactMap { finding[kind]?[$0] },
                                            writing: week.compactMap { writing[kind]?[$0] },
                                            rolledUpRounds: rolledUp[kind] ?? 0)
        }
        return reports
    }
}

/// The 表現 detail lines for one Hanzi card: finding, then (搵完寫) writing help, never mixed. Every number is a
/// recorded count, each count line Cantonese then English; no records → one empty line, never an example. Rolled-up
/// rounds are named as such: history without detail is not 「未有中文字紀錄」.
public enum HanziReportText {
    public static func lines(_ report: HanziKindReport?, kind: ActivityKind) -> [String] {
        guard kind.isTapHanziFamily else { return [] }
        guard let report, !report.isEmpty || report.rolledUpRounds > 0 else { return [HanziParentCopy.reportEmpty] }
        guard !report.isEmpty else { return [HanziParentCopy.reportDetailNotKept(report.rolledUpRounds)] }
        var lines = [HanziParentCopy.reportTitle]
        if report.rolledUpRounds > 0 { lines.append(HanziParentCopy.reportRolledUp(report.rolledUpRounds)) }
        lines.append(HanziParentCopy.reportFinding)
        for row in report.finding {
            var line = "\(row.glyph)：\(row.rounds) 局 · 第一次就搵啱 \(row.firstTry) 局 · 搵錯 \(row.wrongCards) 張"
            var english = "\(row.glyph): rounds \(row.rounds) · found first time \(row.firstTry) · wrong cards \(row.wrongCards)"
            let pairs = row.confusions.sorted { $0.key < $1.key }
            if !pairs.isEmpty {
                line += "（易混：" + pairs.map { "\($0.key) \($0.value) 張" }.joined(separator: "、") + "）"
                english += " (look-alikes: " + pairs.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + ")"
            }
            lines.append(line + "\n" + english)
        }
        guard kind == .tapHanziWrite else { return lines }
        lines.append(HanziParentCopy.reportWriting)
        if report.writing.isEmpty { lines.append(HanziParentCopy.reportNoWrites) }
        for row in report.writing {
            lines.append("\(row.glyph)：寫咗 \(row.writes) 次 · 冇提示寫完 \(row.clean) · 有提示 \(row.assisted) · "
                         + "起點錯 \(row.wrongStarts) · 倒轉 \(row.reverses) · 出線 \(row.offPath) · 停咗 \(row.stalls) · "
                         + "影子車 \(row.ghosts) · 再示範 \(row.redemos)\n"
                         + "\(row.glyph): writes \(row.writes) · without help \(row.clean) · with help \(row.assisted) · "
                         + "wrong starts \(row.wrongStarts) · reversed \(row.reverses) · off path \(row.offPath) · "
                         + "stalls \(row.stalls) · ghost car \(row.ghosts) · re-demos \(row.redemos)")
        }
        lines.append(HanziParentCopy.reportStrokeSkip)
        return lines
    }
}
