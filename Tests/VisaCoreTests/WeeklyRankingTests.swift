import Foundation
import VisaCore

/// Weekly report W2 (weekly-report design §4.10, §5, §6.5, §12 W2): ranking, week over week, the ⚙
/// marker, wins and the "what changed" data. Golden fixtures: `Fixtures/weekly-ranking-5.6/` (the §5.6
/// worked example) and `Fixtures/weekly-2026-10-19/expected-analysis.json` (see the READMEs).
final class WeeklyRankingTests {
    private var seq = 0

    private func ev(_ type: PerfEventType, _ fields: [String: PerfValue], at date: Date, actor: PerfActor = .child,
                    session: String = "s1", launch: String = "L1") -> PerfEvent {
        seq += 1
        return PerfEvent(type: type, timestamp: date, tz: "+08:00", mono: Double(seq), launch: launch, seq: seq,
                         app: "0.34.0", actor: actor, mode: "lock", session: session, fields: fields)
    }

    /// `game_dealt`, then a solved, first-try `round_result` `seconds` later (fields overridable).
    private func round(_ kind: String, at date: Date, stars: Int = 1, dealt: [String: PerfValue] = [:],
                       result: [String: PerfValue] = [:], seconds: Double = 30, launch: String = "L1") -> [PerfEvent] {
        seq += 1
        let id = "r\(seq)"
        var dealtFields: [String: PerfValue] = ["round": .string(id), "kind": .string(kind), "stars": .int(stars)]
        dealtFields.merge(dealt) { _, new in new }
        var resultFields: [String: PerfValue] = [
            "round": .string(id), "kind": .string(kind), "outcome": .string("solved"), "answers": .int(1),
            "first_try": .bool(true), "misses": .int(0), "hint_used": .bool(false), "assisted": .bool(false),
            "total_ms": .int(Int(seconds * 1000)), "active_ms": .int(4000), "earned_min": .int(stars * 5)
        ]
        resultFields.merge(result) { _, new in new }
        return [ev(.gameDealt, dealtFields, at: date, launch: launch),
                ev(.roundResult, resultFields, at: date.addingTimeInterval(seconds), launch: launch)]
    }

    private func parentEvent(_ type: PerfEventType, _ fields: [String: PerfValue], at date: Date,
                             launch: String = "L1") -> PerfEvent {
        ev(type, fields, at: date, actor: .parent, session: "p", launch: launch)
    }

    /// Answered, not right first time.
    private static let missed: [String: PerfValue] = ["first_try": .bool(false), "misses": .int(1), "answers": .int(2)]

    private func analyse(_ events: [PerfEvent], rollup: PerfRollup = PerfRollup(), at date: Date) -> WeeklyAnalysis {
        WeeklyAnalysisBuilder.build(events: events, rollup: rollup, window: WeeklyWindow(containing: date))
    }

    private func score(_ kind: String, _ type: WeeklyRoundType, n: Int = 8, k: Int = 6, days: Int = 3,
                       tier: WeeklyTier, low: Double = 0.5, high: Double = 0.8) -> WeeklyScore {
        WeeklyScore(kind: kind, type: type, n: n, k: k, daysPlayed: days, tier: tier, low: low, high: high)
    }

    private static func threeDP(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// The fixtures sit beside this file; `#filePath` finds them from any working directory.
    private static func fixtureFolder(_ name: String) -> URL {
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: beside.path) { return beside }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/VisaCoreTests/Fixtures/\(name)", isDirectory: true)
    }

    private static func repoRoot() -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) { return root }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    /// Both fixtures are made on Sunday 2026-10-25 at 21:00 HKT for the week of 2026-10-19.
    private static func fixtureAnalysis(_ name: String) -> (analysis: WeeklyAnalysis, events: [PerfEvent], rollup: PerfRollup) {
        let store = PerfEventStore(directory: fixtureFolder(name))
        let read = store.read()
        let rollup = store.loadRollup()
        let madeAt = PerfCodec.parseTimestamp("2026-10-25T13:00:00.000Z")!
        guard let window = WeeklyWindow(weekStart: "2026-10-19", dataUntil: madeAt), !read.events.isEmpty else {
            preconditionFailure("weekly fixture \(name) not found or week stamp did not parse")
        }
        return (WeeklyAnalysisBuilder.build(events: read.events, rollup: rollup, window: window), read.events, rollup)
    }

    /// Every score is in exactly one place, and each place admits only its tiers (§5.3).
    private func expectPlacements(_ scores: [WeeklyScore], _ ranking: WeeklyRanking) {
        let lists = [ranking.top, ranking.stillLearning, ranking.alsoWell, ranking.alsoLearning]
        for score in scores {
            let listed = lists.filter { $0.contains(kind: score.kind, type: score.type) }.count
            let entries = ranking.insufficient.filter { $0.kind == score.kind && $0.type == score.type }
            expectEqual(listed + entries.count, 1, "\(score.kind) is listed exactly once")
            switch ranking.placement(kind: score.kind, type: score.type) {
            case .top:
                expectTrue(score.tier == .goingWell || score.tier == .learning, "\(score.kind) top tier")
            case .stillLearning:
                expectTrue(score.tier == .learning || score.tier == .needsPractice, "\(score.kind) still-learning tier")
                expectTrue(score.daysPlayed >= WeeklyRanking.minimumDays, "\(score.kind) still learning on 2+ days")
            case .alsoWell:
                expectEqual(score.tier, WeeklyTier.goingWell, score.kind)
            case .alsoLearning:
                expectTrue(score.tier == .learning || score.tier == .needsPractice, "\(score.kind) also learning")
                expectTrue(score.daysPlayed >= WeeklyRanking.minimumDays, "\(score.kind) also learning on 2+ days")
            case .insufficient:
                let reason = entries.first?.reason
                switch score.tier {
                case .insufficient: expectEqual(reason, WeeklyInsufficientReason.tooFew, score.kind)
                case .noMethod: expectEqual(reason, WeeklyInsufficientReason.noMethod, score.kind)
                case .learning, .needsPractice:
                    expectEqual(reason, WeeklyInsufficientReason.oneDay, score.kind)
                    expectTrue(score.daysPlayed < WeeklyRanking.minimumDays, "\(score.kind) one day")
                case .goingWell: expectTrue(false, "\(score.kind): going well is never on the 數據唔夠 list")
                }
            }
        }
        let qualified = scores.filter { $0.tier.isQualified }
        let topCandidates = qualified.filter { $0.tier != .needsPractice }.count
        expectEqual(ranking.topSize, WeeklyRanking.topSize(qualified: qualified.count))
        expectEqual(ranking.top.count, min(ranking.topSize, topCandidates))
        expectEqual(ranking.stillLearning.count, ranking.stillLearningSize)
        expectTrue(ranking.topSize <= WeeklyRanking.listSize && ranking.stillLearningSize <= WeeklyRanking.listSize)
        expectEqual(ranking.ranked, qualified.count >= WeeklyRanking.minimumQualified)
    }

    // MARK: §5.3 lists

    func testNoGameInBothLists() {
        var state: UInt64 = 0x5EED_2026
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let tiers = WeeklyTier.allCases
        let kinds = ActivityCatalog.playableKinds.map(\.rawValue) + ["mysteryQuiz"]
        for _ in 0..<600 {
            var scores: [WeeklyScore] = []
            for kind in kinds where next(3) > 0 {
                let tier = tiers[next(tiers.count)]
                let n = tier.isQualified ? WeeklyRanking.minimumRounds + next(12) : next(WeeklyRanking.minimumRounds)
                let low = Double(next(900)) / 1000
                let type: WeeklyRoundType = next(2) == 0 ? .quiz : .practice
                scores.append(score(kind, type, n: n, k: next(n + 1), days: 1 + next(7), tier: tier, low: low,
                                    high: min(1, low + Double(next(400)) / 1000)))
            }
            let ranking = WeeklyRanking.rank(scores)
            expectPlacements(scores, ranking)
            let top = Set(ranking.top.quiz.map { "q:" + $0 } + ranking.top.practice.map { "p:" + $0 })
            let bottom = Set(ranking.stillLearning.quiz.map { "q:" + $0 } + ranking.stillLearning.practice.map { "p:" + $0 })
            expectTrue(top.isDisjoint(with: bottom), "no game is in both lists")
        }

        // The §5.6 week: the games and the page-4 places agree.
        let analysis = Self.fixtureAnalysis("weekly-ranking-5.6").analysis
        for game in analysis.games {
            expectEqual(game.placement, analysis.ranking.placement(kind: game.kind, type: game.type), game.kind)
            if game.placement == .top { expectTrue(game.tier != .needsPractice, "\(game.kind) top") }
            if game.placement == .stillLearning { expectTrue(game.tier != .goingWell, "\(game.kind) still learning") }
        }
        expectTrue(Set(analysis.ranking.top.all).isDisjoint(with: Set(analysis.ranking.stillLearning.all)))
    }

    func testInsufficientNeverRanked() {
        let scores = [
            score("shadowMatch", .quiz, tier: .goingWell, low: 0.8), score("halfMatch", .quiz, tier: .learning),
            score("traceLines", .practice, tier: .goingWell, low: 0.7),
            score("emptyBay", .quiz, n: 4, k: 4, tier: .insufficient), score("shapeCousin", .quiz, n: 0, k: 0, tier: .insufficient),
            score("mysteryQuiz", .quiz, n: 9, k: 9, tier: .noMethod),
            score("tapCountTraceEnglish", .practice, n: 3, k: 1, days: 1, tier: .insufficient)
        ]
        let ranking = WeeklyRanking.rank(scores)
        expectPlacements(scores, ranking)
        expectEqual(ranking.insufficient.map(\.kind), ["emptyBay", "shapeCousin", "mysteryQuiz", "tapCountTraceEnglish"])
        expectEqual(ranking.insufficient.map(\.more), [1, 5, 0, 2])
        expectEqual(ranking.qualifiedQuiz + ranking.qualifiedPractice, 3)
        for entry in ranking.insufficient {
            expectEqual(ranking.placement(kind: entry.kind, type: entry.type), WeeklyPlacement.insufficient, entry.kind)
        }

        // From records: 4 answered rounds, a round never answered, an unknown kind without a chance and an
        // unknown guided kind are listed, never ranked.
        let monday = PerfCodec.parseTimestamp("2026-10-19T09:00:00.000Z")!  // 17:00 HKT
        func at(_ day: Int, _ minute: Int) -> Date { monday.addingTimeInterval(Double(day) * 86_400 + Double(minute) * 60) }
        var events: [PerfEvent] = []
        for index in 0..<4 { events += round("halfMatch", at: at(0, index)) }
        events += round("shapeCousin", at: at(0, 10), result: ["answers": .int(0), "first_try": .null,
                                                                "outcome": .string("abandoned")])
        for index in 0..<6 {
            events += round("mysteryQuiz", at: at(index % 2, 20 + index))
            events += round("mysteryTrace", at: at(index % 2, 30 + index), dealt: ["match_mode": .string("guided")],
                            result: ["answers": .int(0), "first_try": .null])
            events += round("shadowMatch", at: at(index % 2, 40 + index))
            events += round("emptyBay", at: at(index % 2, 50 + index))
        }
        let analysis = analyse(events, at: monday)
        let expected: [(String, WeeklyTier, WeeklyInsufficientReason, Int)] = [
            ("halfMatch", .insufficient, .tooFew, 1), ("shapeCousin", .insufficient, .tooFew, 5),
            ("mysteryQuiz", .noMethod, .noMethod, 0), ("mysteryTrace", .noMethod, .noMethod, 0)
        ]
        for (kind, tier, reason, more) in expected {
            let game = analysis.games.first { $0.kind == kind }
            expectEqual(game?.tier, tier, kind)
            expectEqual(game?.placement, WeeklyPlacement.insufficient, kind)
            let entry = analysis.ranking.insufficient.first { $0.kind == kind }
            expectEqual(entry?.reason, reason, kind)
            expectEqual(entry?.more, more, kind)
            expectFalse(analysis.ranking.top.all.contains(kind) || analysis.ranking.stillLearning.all.contains(kind)
                        || analysis.ranking.alsoWell.all.contains(kind) || analysis.ranking.alsoLearning.all.contains(kind),
                        "\(kind) is never ranked")
        }
        expectEqual(analysis.ranking.top.quiz, ["shadowMatch"])
        expectTrue(analysis.ranking.ranked)
    }

    func testStillLearningNeedsTwoDays() {
        let monday = PerfCodec.parseTimestamp("2026-10-19T09:00:00.000Z")!  // 17:00 HKT
        func week(countVehiclesDays: [Int]) -> WeeklyAnalysis {
            seq = 0
            var events: [PerfEvent] = []
            for index in 0..<6 {
                let day = Double(index % 2) * 86_400
                events += round("shadowMatch", at: monday.addingTimeInterval(day + Double(index) * 60))
                events += round("moreFewer", at: monday.addingTimeInterval(day + Double(10 + index) * 60),
                                result: index == 0 ? [:] : Self.missed)
                let countDay = Double(countVehiclesDays[index]) * 86_400
                events += round("countVehicles", at: monday.addingTimeInterval(countDay + Double(20 + index) * 60),
                                result: index == 0 ? [:] : Self.missed)
            }
            return analyse(events, at: monday)
        }

        // countVehicles: 6 rounds, all on Monday. Qualified and needs practice, but one day is not a pattern.
        let oneDay = week(countVehiclesDays: [0, 0, 0, 0, 0, 0])
        let count = oneDay.games.first { $0.kind == "countVehicles" }
        expectEqual(count?.tier, WeeklyTier.needsPractice)
        expectEqual(count?.daysPlayed, 1)
        expectEqual(count?.placement, WeeklyPlacement.insufficient)
        expectEqual(oneDay.ranking.insufficient.first { $0.kind == "countVehicles" }?.reason, WeeklyInsufficientReason.oneDay)
        expectEqual(oneDay.ranking.stillLearning.quiz, ["moreFewer"])
        expectEqual(oneDay.ranking.alsoLearning.quiz, [])
        expectEqual(oneDay.ranking.top.quiz, ["shadowMatch"])
        expectEqual(oneDay.ranking.stillLearningCandidates, 1)

        // One round on Tuesday: two days, so it is still learning (upper bound first).
        let twoDays = week(countVehiclesDays: [0, 0, 0, 0, 0, 1])
        expectEqual(twoDays.games.first { $0.kind == "countVehicles" }?.placement, WeeklyPlacement.stillLearning)
        expectEqual(Set(twoDays.ranking.stillLearning.quiz), ["countVehicles", "moreFewer"])
        expectTrue(twoDays.ranking.insufficient.isEmpty)
    }

    func testProportionalSplitAndSpill() {
        expectEqual(WeeklyRanking.largestRemainder(total: 5, weights: [9, 8]), [3, 2])  // design §5.6
        expectEqual(WeeklyRanking.largestRemainder(total: 5, weights: [8, 9]), [2, 3])
        expectEqual(WeeklyRanking.largestRemainder(total: 5, weights: [5, 5]), [3, 2])  // equal remainders: quiz
        expectEqual(WeeklyRanking.largestRemainder(total: 3, weights: [1, 1]), [2, 1])
        expectEqual(WeeklyRanking.largestRemainder(total: 4, weights: [1, 2]), [1, 3])
        expectEqual(WeeklyRanking.largestRemainder(total: 5, weights: [0, 4]), [0, 5])
        expectEqual(WeeklyRanking.largestRemainder(total: 0, weights: [3, 3]), [0, 0])
        expectEqual(WeeklyRanking.largestRemainder(total: 2, weights: [0, 0]), [0, 0])
        expectEqual([0, 1, 2, 3, 4, 9, 10, 17].map { WeeklyRanking.topSize(qualified: $0) }, [0, 1, 1, 2, 2, 5, 5, 5])

        // 4 quiz (3 need practice) and 4 practice games qualify: T = 4, slots 2 + 2. Only one quiz game
        // can be "going well", so its spare slot goes to practice.
        var scores = [score("shadowMatch", .quiz, tier: .goingWell, low: 0.8, high: 0.95)]
        for kind in ["countVehicles", "moreFewer", "emptyBay"] {
            scores.append(score(kind, .quiz, tier: .needsPractice, low: 0.1, high: 0.4))
        }
        for (offset, kind) in ["traceLines", "traceShapesDotted", "tapCountAll", "lineMatchGuidedStraight"].enumerated() {
            scores.append(score(kind, .practice, tier: .goingWell, low: 0.9 - Double(offset) / 10, high: 0.97))
        }
        var ranking = WeeklyRanking.rank(scores)
        expectPlacements(scores, ranking)
        expectEqual(ranking.topSize, 4)
        expectEqual(ranking.topSlots, [2, 2])
        expectEqual(ranking.top.quiz, ["shadowMatch"])
        expectEqual(ranking.top.practice, ["traceLines", "traceShapesDotted", "tapCountAll"])
        // Still learning: 3 quiz candidates, none in practice: B = 3, slots 2 + 1 (4 : 4), the spare one to quiz.
        expectEqual(ranking.stillLearningSize, 3)
        expectEqual(ranking.stillLearningSlots, [2, 1])
        expectEqual(ranking.stillLearning.quiz, ["countVehicles", "moreFewer", "emptyBay"])
        expectEqual(ranking.stillLearning.practice, [])
        expectEqual(ranking.alsoWell.practice, ["lineMatchGuidedStraight"])

        // Going well: lower bound, then more rounds, then the higher raw rate, then catalog order.
        scores = [score("shadowMatch", .quiz, tier: .goingWell, low: 0.8),
                  score("traceLines", .practice, n: 6, k: 6, tier: .goingWell, low: 0.75),
                  score("traceShapesArrows", .practice, n: 9, k: 7, tier: .goingWell, low: 0.7),
                  score("lineMatchGuidedStraight", .practice, n: 6, k: 6, tier: .goingWell, low: 0.7),
                  score("tapCountAllEnglish", .practice, n: 6, k: 5, tier: .goingWell, low: 0.7),
                  score("tapCountAll", .practice, n: 6, k: 5, tier: .goingWell, low: 0.7)]
        ranking = WeeklyRanking.rank(scores)
        expectEqual(ranking.topSlots, [1, 2])
        expectEqual(ranking.top.practice + ranking.alsoWell.practice,
                    ["traceLines", "traceShapesArrows", "lineMatchGuidedStraight", "tapCountAll", "tapCountAllEnglish"])

        // Still learning: upper bound, then more rounds, then the lower raw rate, then catalog order.
        scores = [score("halfMatch", .quiz, n: 8, k: 3, tier: .needsPractice, high: 0.4),
                  score("emptyBay", .quiz, n: 8, k: 2, tier: .needsPractice, high: 0.4),
                  score("moreFewer", .quiz, n: 10, k: 4, tier: .needsPractice, high: 0.4),
                  score("findTheSame", .quiz, n: 8, k: 3, tier: .needsPractice, high: 0.4),
                  score("countVehicles", .quiz, n: 8, k: 2, tier: .needsPractice, high: 0.3)]
        ranking = WeeklyRanking.rank(scores)
        expectEqual(ranking.top.count, 0)
        expectEqual(ranking.stillLearning.quiz, ["countVehicles", "moreFewer", "emptyBay", "findTheSame", "halfMatch"])
    }

    // MARK: §4.10 week over week

    func testMeaningfulChangeTable() {
        let rates: [(Int, Int, Int, Int, WeeklyChange?)] = [
            (4, 4, 5, 5, nil), (5, 5, 4, 4, nil), (0, 0, 0, 0, nil),           // fewer than 5 rounds in a week
            (5, 5, 3, 5, .up), (4, 5, 2, 5, .up), (5, 5, 4, 5, .up),           // 5 vs 5
            (4, 5, 3, 5, .unsure), (3, 5, 2, 5, .unsure),                      // Δ = 0.20 but within the noise
            (8, 10, 6, 10, .unsure), (9, 10, 7, 10, .up), (7, 10, 9, 10, .down),  // 10 vs 10
            (6, 10, 5, 10, .same), (5, 10, 5, 10, .same), (0, 5, 0, 5, .same), (5, 5, 5, 5, .same),
            (5, 8, 3, 8, .up), (3, 8, 5, 8, .down),                            // |Δ| = SE exactly
            (72, 97, 59, 86, .same), (42, 57, 29, 44, .same),                  // design §5.6 totals
            (7, 8, 6, 9, .up), (7, 9, 3, 6, .up), (6, 14, 7, 16, .same), (3, 7, 2, 6, .same)
        ]
        for (k1, n1, k0, n0, want) in rates {
            expectEqual(WeeklyComparison.rateChange(k1: k1, n1: n1, k0: k0, n0: n0), want, "\(k1)/\(n1) vs \(k0)/\(n0)")
            expectEqual(WeeklyRateComparison(k1: k1, n1: n1, k0: k0, n0: n0).change, want, "\(k1)/\(n1) vs \(k0)/\(n0)")
        }
        let counts: [(Int, Int, Int, Int, WeeklyChange?)] = [
            (130, 100, 5, 5, .up), (125, 100, 4, 4, .up), (124, 100, 7, 7, nil), (75, 100, 5, 5, .down),
            (76, 100, 5, 5, nil), (130, 100, 3, 5, nil), (130, 100, 5, 3, nil), (5, 0, 4, 4, .up), (0, 0, 7, 7, nil),
            (100, 100, 7, 7, nil), (154, 130, 6, 7, nil)
        ]
        for (current, previous, days1, days0, want) in counts {
            expectEqual(WeeklyComparison.countChange(current: current, previous: previous, daysCurrent: days1,
                                                     daysPrevious: days0), want, "\(current) vs \(previous)")
        }
    }

    func testSettingsMarker() {
        let lastMonday = PerfCodec.parseTimestamp("2026-10-12T09:00:00.000Z")!  // 17:00 HKT
        let monday = PerfCodec.parseTimestamp("2026-10-19T09:00:00.000Z")!
        func at(_ base: Date, _ day: Int, _ minute: Int) -> Date {
            base.addingTimeInterval(Double(day) * 86_400 + Double(minute) * 60)
        }
        let guided: [String: PerfValue] = ["match_mode": .string("guided"), "gen": .string("variants_v1"), "level": .int(2),
                                           "tolerance": .string("standard"), "shape_trace_level": .string("L2")]
        let shape: [String: PerfValue] = ["shapes_done": .int(3), "shapes_total": .int(3), "wrong_start": .int(0),
                                          "reverse_direction": .int(0), "off_path_count": .int(0)]
        let rough = shape.merging(["wrong_start": .int(1)]) { _, new in new }
        let trace: [String: PerfValue] = ["gen": .string("variants_v1"), "level": .int(2), "match_mode": .string("guided"),
                                          "trace_scaffold": .string("dots")]
        func traced(_ level: String) -> [String: PerfValue] {
            ["recount_attempts": .int(0), "guide_clean": .int(1), "guide_level": .string(level), "answers": .int(0),
             "first_try": .null]
        }
        func lineMatch(_ tolerance: String) -> [String: PerfValue] {
            ["match_mode": .string("free"), "gen": .string("variants_v1"), "level": .int(1), "pairs": .int(2),
             "tolerance": .string(tolerance)]
        }
        var events = [parentEvent(.configChange, ["what": .string("lineMatch_tolerance"), "kind": .string("lineMatch"),
                                                  "value": .string("standard")],
                                  at: PerfCodec.parseTimestamp("2026-10-01T09:00:00.000Z")!, launch: "L0")]
        for index in 0..<6 {
            let day = index / 2
            events += round("lineMatch", at: at(lastMonday, day, index), dealt: lineMatch("standard"),
                            result: index == 0 ? [:] : Self.missed, launch: "L0")
            events += round("traceShapesArrows", at: at(lastMonday, day, 10 + index), dealt: guided,
                            result: index < 2 ? shape : rough, launch: "L0")
            events += round("tapCountTrace", at: at(lastMonday, day, 20 + index), dealt: trace, result: traced("standard"),
                            launch: "L0")
            events += round("findTheSame", at: at(lastMonday, day, 30 + index),
                            dealt: ["gen": .string("variants_v1"), "level": .int(1)], launch: "L0")
            events += round("countVehicles", at: at(lastMonday, day, 40 + index), launch: "L0")
            events += round("shadowMatch", at: at(lastMonday, day, 50 + index), launch: "L0")
        }
        events.append(parentEvent(.configChange, ["what": .string("lineMatch_tolerance"), "kind": .string("lineMatch"),
                                                  "value": .string("wide")], at: at(monday, 1, -60)))
        events.append(parentEvent(.configChange, ["what": .string("assignment"), "kind": .string("shadowMatch"),
                                                  "star": .int(3), "value": .bool(true)], at: at(monday, 2, -60)))
        for index in 0..<6 {
            let day = 1 + index / 2
            let stars = index < 3 ? 1 : 3
            events += round("lineMatch", at: at(monday, day, index), dealt: lineMatch("wide"))
            events += round("traceShapesArrows", at: at(monday, day, 10 + index), dealt: guided, result: shape)
            events += round("tapCountTrace", at: at(monday, day, 20 + index), dealt: trace, result: traced("more"))
            events += round("findTheSame", at: at(monday, day, 30 + index), stars: stars,
                            dealt: ["gen": .string("variants_v1"), "level": .int(stars)])
            events += round("countVehicles", at: at(monday, day, 40 + index),
                            dealt: ["gen": .string("variants_v1"), "level": .int(1)])
            events += round("shadowMatch", at: at(monday, day, 50 + index))
        }
        let analysis = analyse(events, at: monday)
        func settings(_ kind: String) -> [WeeklySettingChange] {
            analysis.games.first { $0.kind == kind }?.settings ?? []
        }
        expectEqual(settings("lineMatch"), [.config(what: "lineMatch_tolerance", value: "wide", star: nil, date: "2026-10-20"),
                                            .signature(field: "tolerance", old: "standard", new: "wide")])
        expectEqual(settings("traceShapesArrows"), [], "a 連一連 setting is not a shape-trace setting")
        expectEqual(settings("tapCountTrace"), [.signature(field: "guide_level", old: "standard", new: "more")])
        // The level follows the star (generated kinds): the ★★★ rule speaks for it, not the signature.
        expectEqual(settings("findTheSame"), [.stars(previous: 0, previousRounds: 6, current: 3, currentRounds: 6)])
        expectEqual(settings("countVehicles"), [.signature(field: "gen", old: "fixed_v0", new: "variants_v1")])
        expectEqual(settings("shadowMatch"), [.config(what: "assignment", value: "true", star: 3, date: "2026-10-21")])

        // A ⚙ cell keeps its numbers but never feeds a clear change or a win.
        let line = analysis.games.first { $0.kind == "lineMatch" }
        expectEqual(line?.wow.change, WeeklyChange.up)
        expectEqual(analysis.comparison.clearChanges, [WeeklyClearChange(kind: "traceShapesArrows", type: .practice, change: .up)])
        expectEqual(analysis.winCandidates.filter { $0.id == "win.rise" },
                    [.rise(kind: "traceShapesArrows", type: .practice, k0: 2, n0: 6, k1: 6, n1: 6)])

        // The same changes on the page-5 panel.
        expectEqual(analysis.changes.settings.map(\.what), ["lineMatch_tolerance"])
        expectEqual(analysis.changes.settings.first?.old, "standard")
        expectEqual(analysis.changes.settings.first?.new, "wide")
        expectEqual(analysis.changes.settings.first?.kinds, ["lineMatchGuidedStraight", "lineMatchGuidedBridge", "lineMatch"])
        expectEqual(analysis.changes.assignments.map(\.kind), ["shadowMatch"])
        expectEqual(analysis.changes.assignments.first?.on, true)
        expectEqual(analysis.changes.generations.map(\.kind), ["countVehicles"])
        expectEqual(analysis.games.first { $0.kind == "shadowMatch" }?.fixedQuestion, true)
        expectEqual(analysis.games.first { $0.kind == "countVehicles" }?.fixedQuestion, false)
        expectEqual(WeeklyComparison.kinds(forConfig: "tapCount_guidance", kind: "tapCountAll"),
                    ["tapCountAll", "tapCountTrace", "tapCountPick", "tapCountAllEnglish", "tapCountTraceEnglish",
                     "tapCountPickEnglish"])
        expectEqual(WeeklyComparison.kinds(forConfig: "letters_mode", kind: "tapLetterAll"), [])
    }

    // MARK: §6.5 wins

    func testWinsCatalogue() {
        let lastMonday = PerfCodec.parseTimestamp("2026-10-12T09:00:00.000Z")!  // 17:00 HKT
        let monday = PerfCodec.parseTimestamp("2026-10-19T09:00:00.000Z")!
        func at(_ base: Date, _ day: Int, _ minute: Int) -> Date {
            base.addingTimeInterval(Double(day) * 86_400 + Double(minute) * 60)
        }
        let tapped: [String: PerfValue] = ["recount_attempts": .int(0), "answers": .int(0), "first_try": .null]
        let recounted = tapped.merging(["recount_attempts": .int(1)]) { _, new in new }
        func numeral(_ value: Int) -> [String: PerfValue] {
            ["recount_attempts": .int(0), "guide_clean": .int(1), "guide_learned_before": .int(1), "numeral": .int(value),
             "answers": .int(0), "first_try": .null]
        }
        var history: [PerfEvent] = []
        for index in 0..<4 { history += round("halfMatch", at: at(lastMonday, 0, index), result: Self.missed, launch: "L0") }
        history += round("capacityCompare", at: at(lastMonday, 0, 10), result: Self.missed, launch: "L0")
        for index in 0..<3 { history += round("tapCountAll", at: at(lastMonday, 1, index), result: recounted, launch: "L0") }
        for index in 0..<2 {
            history += round("tapCountTrace", at: at(lastMonday, 1, 10 + index), result: numeral(4), launch: "L0")
        }
        for index in 0..<6 {
            history += round("shadowMatch", at: at(lastMonday, 2, index), result: index < 2 ? [:] : Self.missed, launch: "L0")
        }

        var week: [PerfEvent] = []
        for index in 0..<12 {
            let day = [0, 4, 5][index / 4]
            week += round("emptyBay", at: at(monday, day, index), result: index % 3 == 2 ? Self.missed : [:])
        }
        for index in 0..<6 { week += round("shadowMatch", at: at(monday, 2, index)) }
        week += round("halfMatch", at: at(monday, 3, 0), result: Self.missed)
        week += round("halfMatch", at: at(monday, 3, 1))
        week += round("capacityCompare", at: at(monday, 3, 2))
        for index in 0..<2 { week += round("tapCountAll", at: at(monday, 3, 10 + index), result: tapped) }
        week += round("tapCountTrace", at: at(monday, 4, 20), result: numeral(4))
        week += round("tapCountTrace", at: at(monday, 4, 21), result: numeral(7))

        let analysis = analyse(history + week, at: monday)
        let expected: [WeeklyWin] = [
            .newGame(kind: "emptyBay"), .numeral(numerals: [7]), .streak(kind: "shadowMatch", run: 6),
            .rise(kind: "shadowMatch", type: .quiz, k0: 2, n0: 6, k1: 6, n1: 6), .firstSmooth(kind: "tapCountAll", day: 3),
            .firstTry(kind: "halfMatch", earlier: 5, day: 3), .cleanDay(day: 2, rounds: 6), .noFuelOut(rounds: 21)
        ]
        expectEqual(analysis.winCandidates, expected)
        expectEqual(analysis.wins, Array(expected.prefix(3)))
        expectEqual(analysis.wins.map(\.id), ["win.newGame", "win.numeral", "win.streak"])
        expectEqual(WeeklyWin.maximum, 3)

        // 「清除表現紀錄」 before this week resets "ever": 4 is learned again and every kind is new.
        let cleared = parentEvent(.statsMarker, ["what": .string("cleared")], at: at(lastMonday, 6, 300), launch: "L0")
        let afterClear = analyse(history + [cleared] + week, at: monday)
        expectTrue(afterClear.winCandidates.contains(.numeral(numerals: [4, 7])), "numerals after a clear")
        expectFalse(afterClear.winCandidates.contains { $0.id == "win.firstTry" }, "no earlier rounds after a clear")
    }

    // MARK: Design §5.6 worked example

    func testWorkedExample56ReproducedExactly() {
        let analysis = Self.fixtureAnalysis("weekly-ranking-5.6").analysis
        expectEqual(Self.threeDP(analysis.model.current.pooledQuiz), "0.598")
        expectEqual(Self.threeDP(analysis.model.current.pooledPractice), "0.737")
        expectEqual(analysis.model.current.totals.answered, 97)
        expectEqual(analysis.model.current.totals.smoothDefined, 57)

        let table: [(String, Int, Int, String, String, String, String, WeeklyTier)] = [
            ("shadowMatch", 9, 9, "0.333", "0.876", "0.784", "0.969", .goingWell),
            ("halfMatch", 11, 10, "0.333", "0.793", "0.684", "0.902", .goingWell),
            ("sequenceShortToLong", 8, 7, "0.042", "0.779", "0.680", "0.879", .goingWell),
            ("capacityCompare", 12, 11, "0.500", "0.775", "0.646", "0.904", .goingWell),
            ("findTheSame", 10, 7, "0.333", "0.564", "0.416", "0.712", .learning),
            ("emptyBay", 9, 6, "0.333", "0.530", "0.374", "0.687", .learning),
            ("lineMatch", 8, 4, "0.260", "0.415", "0.259", "0.572", .learning),
            ("moreFewer", 10, 6, "0.500", "0.314", "0.108", "0.520", .needsPractice),
            ("countVehicles", 14, 6, "0.333", "0.244", "0.099", "0.389", .needsPractice),
            ("traceLines", 6, 6, "-", "0.895", "0.817", "0.973", .goingWell),
            ("traceShapesDotted", 8, 7, "-", "0.829", "0.741", "0.917", .goingWell),
            ("tapCountAllEnglish", 7, 6, "-", "0.813", "0.719", "0.908", .goingWell),
            ("tapCountAll", 6, 5, "-", "0.795", "0.692", "0.897", .goingWell),
            ("lineMatchGuidedStraight", 6, 5, "-", "0.795", "0.692", "0.897", .goingWell),
            ("traceShapesArrows", 9, 7, "-", "0.765", "0.670", "0.861", .goingWell),
            ("lineMatchGuidedBridge", 5, 2, "-", "0.550", "0.417", "0.682", .learning),
            ("tapCountTrace", 7, 3, "-", "0.541", "0.420", "0.662", .learning)
        ]
        for (kind, n, k, chance, m, lo, hi, tier) in table {
            guard let game = analysis.games.first(where: { $0.kind == kind }) else {
                preconditionFailure("§5.6 row \(kind) missing")
            }
            expectEqual(game.n, n, kind)
            expectEqual(game.k, k, kind)
            expectEqual(Self.threeDP(game.chance), chance, kind)
            expectEqual(Self.threeDP(game.estimate?.mastery), m, kind)
            expectEqual(Self.threeDP(game.estimate?.masteryLow), lo, kind)
            expectEqual(Self.threeDP(game.estimate?.masteryHigh), hi, kind)
            expectEqual(game.tier, tier, kind)
        }

        let ranking = analysis.ranking
        expectEqual(ranking.qualifiedQuiz, 9)
        expectEqual(ranking.qualifiedPractice, 8)
        expectEqual(ranking.topSize, 5)
        expectEqual(ranking.topSlots, [3, 2])
        expectEqual(ranking.top.quiz, ["shadowMatch", "halfMatch", "sequenceShortToLong"])
        expectEqual(ranking.top.practice, ["traceLines", "traceShapesDotted"])
        expectEqual(ranking.stillLearningCandidates, 7)
        expectEqual(ranking.stillLearningSize, 5)
        expectEqual(ranking.stillLearningSlots, [3, 2])
        expectEqual(ranking.stillLearning.quiz, ["countVehicles", "moreFewer", "lineMatch"])
        expectEqual(ranking.stillLearning.practice, ["tapCountTrace", "lineMatchGuidedBridge"])
        expectEqual(ranking.alsoWell.quiz, ["capacityCompare"])
        expectEqual(Set(ranking.alsoWell.practice), ["traceShapesArrows", "tapCountAll", "tapCountAllEnglish",
                                                     "lineMatchGuidedStraight"])
        expectEqual(ranking.alsoWell.practice, ["tapCountAllEnglish", "lineMatchGuidedStraight", "tapCountAll",
                                                "traceShapesArrows"])
        expectEqual(ranking.alsoLearning.quiz, ["emptyBay", "findTheSame"])
        expectEqual(ranking.alsoLearning.practice, [])
        expectEqual(ranking.insufficient.map(\.kind), ["shapeCousin", "twoPictureChoose", "tapCountTraceEnglish"])
        expectEqual(ranking.insufficient.map(\.n), [4, 2, 3])
        expectEqual(ranking.insufficient.map(\.k), [4, 2, 1])
        expectEqual(ranking.insufficient.map(\.more), [1, 3, 2])

        // The sample report's wins and clear changes come from the same records.
        expectEqual(analysis.wins, [.newGame(kind: "tapCountTraceEnglish"), .numeral(numerals: [3, 5]),
                                    .streak(kind: "shadowMatch", run: 9)])
        expectEqual(analysis.comparison.clearChanges.map(\.kind), ["traceShapesDotted", "traceShapesArrows"])
        expectEqual(analysis.comparison.quiz.change, WeeklyChange.same)
        expectEqual(analysis.games.filter(\.memorised).map(\.kind), ["halfMatch", "capacityCompare"])
        expectEqual(analysis.games.filter { !$0.settings.isEmpty }.map(\.kind),
                    ["lineMatchGuidedStraight", "lineMatchGuidedBridge", "lineMatch", "tapCountTraceEnglish"])
    }

    // MARK: Golden fixtures

    func testWeeklyAnalysisGoldenFixtures() throws {
        for name in ["weekly-ranking-5.6", "weekly-2026-10-19"] {
            let expectedURL = Self.fixtureFolder(name).appendingPathComponent("expected-analysis.json")
            guard FileManager.default.fileExists(atPath: expectedURL.path) else {
                preconditionFailure("weekly analysis fixture not found at \(expectedURL.path)")
            }
            let built = Self.fixtureAnalysis(name)
            let actual = built.analysis.canonicalJSON()
            let expected = try String(contentsOf: expectedURL, encoding: .utf8)
            if actual != expected {
                let got = actual.components(separatedBy: "\n")
                let want = expected.components(separatedBy: "\n")
                var line = min(got.count, want.count)
                for index in 0..<min(got.count, want.count) where got[index] != want[index] {
                    line = index
                    break
                }
                let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-analysis-actual.json")
                try? Data(actual.utf8).write(to: out)
                let wantLine = line < want.count ? want[line] : "<end>"
                let gotLine = line < got.count ? got[line] : "<end>"
                preconditionFailure("\(name) analysis golden mismatch at line \(line + 1): expected [\(wantLine)] "
                                    + "got [\(gotLine)]; actual written to \(out.path)")
            }
            print("  weekly analysis golden \(name): \(expected.utf8.count) bytes match")
            // Same records in any file order, same bytes.
            let window = built.analysis.model.window
            let shuffled = WeeklyAnalysisBuilder.build(events: Array(built.events.reversed()), rollup: built.rollup,
                                                       window: window)
            expectEqual(shuffled.canonicalJSON(), actual, name)
        }

        // Never the host's zone, calendar or locale; Traditional Chinese only.
        let root = Self.repoRoot()
        for name in ["WeeklyRanking.swift", "WeeklyComparison.swift", "WeeklyWins.swift", "WeeklyAnalysis.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent("Sources/VisaCore/\(name)"), encoding: .utf8)
            for banned in ["TimeZone.current", "autoupdatingCurrent", "Locale.current", "Calendar.current", "NSTimeZone"] {
                expectFalse(text.contains(banned), "\(name) must not use \(banned)")
            }
            expectTrue(isTraditionalChineseOnly(text) && perfTraditionalOnly(text), "\(name) is Traditional only")
        }
    }
}
