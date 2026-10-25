import Foundation
import VisaCore

/// Weekly report W1 (weekly-report design §4.1–4.9, §9.6, §12 W1): the round index and the
/// weekly metrics. The golden fixture is `Fixtures/weekly-2026-10-19/` (see its README.md).
final class WeeklyMetricsTests {
    private var seq = 0

    private func ev(_ type: PerfEventType, _ fields: [String: PerfValue], at date: Date, actor: PerfActor = .child,
                    session: String = "s1", launch: String = "L1") -> PerfEvent {
        seq += 1
        return PerfEvent(type: type, timestamp: date, tz: "+08:00", mono: Double(seq), launch: launch, seq: seq,
                         app: "0.34.0", actor: actor, mode: "lock", session: session, fields: fields)
    }

    /// `game_dealt`, then a solved, first-try `round_result` `seconds` later (fields overridable).
    private func round(_ kind: String, at date: Date, stars: Int = 1, dealt: [String: PerfValue] = [:],
                       result: [String: PerfValue] = [:], seconds: Double = 30, actor: PerfActor = .child,
                       session: String = "s1", launch: String = "L1") -> [PerfEvent] {
        seq += 1
        let id = "w\(seq)"
        var dealtFields: [String: PerfValue] = ["round": .string(id), "kind": .string(kind), "stars": .int(stars)]
        dealtFields.merge(dealt) { _, new in new }
        var resultFields: [String: PerfValue] = [
            "round": .string(id), "kind": .string(kind), "outcome": .string("solved"), "answers": .int(1),
            "first_try": .bool(true), "misses": .int(0), "hint_used": .bool(false), "assisted": .bool(false),
            "total_ms": .int(Int(seconds * 1000)), "active_ms": .int(4000), "earned_min": .int(stars * 5)
        ]
        resultFields.merge(result) { _, new in new }
        return [ev(.gameDealt, dealtFields, at: date, actor: actor, session: session, launch: launch),
                ev(.roundResult, resultFields, at: date.addingTimeInterval(seconds), actor: actor, session: session,
                   launch: launch)]
    }

    private func build(_ events: [PerfEvent], rollup: PerfRollup = PerfRollup(), at date: Date) -> WeeklyWindowMetrics {
        WeeklyMetricsBuilder.build(events: events, rollup: rollup, window: WeeklyWindow(containing: date)).current
    }

    /// The fixture sits beside this file; `#filePath` finds it from any working directory.
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

    // MARK: §4.3 / §4.4 quiz vs practice

    func testPracticeNeverInFirstTry() {
        let monday = PerfCodec.parseTimestamp("2026-10-19T10:00:00.000Z")!  // 18:00 HKT
        // Practice result lines that claim answers and a first try anyway.
        let claims: [String: PerfValue] = ["answers": .int(3), "first_try": .bool(true)]
        let shape: [String: PerfValue] = ["shapes_done": .int(2), "shapes_total": .int(2), "wrong_start": .int(0),
                                          "reverse_direction": .int(0), "off_path_count": .int(0)]
        let road: [String: PerfValue] = ["roads": .int(2), "roads_total": .int(2), "wrong_start": .int(0),
                                         "off_path_count": .int(0)]
        func at(_ minute: Double) -> Date { monday.addingTimeInterval(minute * 60) }
        var events: [PerfEvent] = []
        events += round("tapCountAll", at: at(0), result: claims.merging(["recount_attempts": .int(0)]) { _, new in new })
        events += round("traceLines", at: at(2), dealt: ["match_mode": .string("guided")],
                        result: claims.merging(shape) { _, new in new })
        events += round("lineMatch", at: at(4), dealt: ["match_mode": .string("guided"), "pairs": .int(2)],
                        result: claims.merging(road) { _, new in new })
        events += round("tapCountTraceEnglish", at: at(6),
                        result: claims.merging(["recount_attempts": .int(0), "guide_clean": .int(1)]) { _, new in new })
        events += round("mysteryTrace", at: at(8), dealt: ["match_mode": .string("guided")], result: claims)
        events += round("shadowMatch", at: at(10))
        events += round("halfMatch", at: at(12), result: ["first_try": .bool(false), "misses": .int(1), "answers": .int(2)])
        events += round("lineMatch", at: at(14), dealt: ["match_mode": .string("free"), "pairs": .int(3)])
        let week = build(events, at: monday)

        expectEqual(week.totals.quizRounds, 3)
        expectEqual(week.totals.practiceRounds, 5)
        expectEqual(week.totals.answered, 3)
        expectEqual(week.totals.firstTry, 2)
        expectEqual(week.days[0].counts.answered, 3)
        expectEqual(week.days[0].counts.firstTry, 2)
        expectEqual(week.days[0].counts.finished, 5)
        for row in week.kinds where row.type == .practice {
            expectEqual(row.answered, 0, row.kind)
            expectEqual(row.firstTry, 0, row.kind)
            expectNil(row.expected)
            expectNil(row.chanceMean)
            expectNil(row.adjusted)
        }
        for item in week.rounds where item.type == .practice {
            expectFalse(item.answered, item.kind)
            expectFalse(item.firstTry, item.kind)
            expectNil(item.chance)
            if case .object(let fields) = item.json {
                expectEqual(fields["first_try"], PerfValue.null, item.kind)
                expectEqual(fields["answered"], PerfValue.null, item.kind)
            } else {
                expectTrue(false, "round json is an object")
            }
        }
        // Guided roads dealt as lineMatch (before v0.24.1) are a practice row beside the quiz row.
        let lineRows = week.kinds.filter { $0.kind == "lineMatch" }
        expectEqual(lineRows.map(\.type), [WeeklyRoundType.quiz, .practice])
        expectEqual(lineRows.last?.family, WeeklyPracticeFamily.roads)
        // Practice is judged by "done smoothly" only; mysteryTrace has no rule, so it is undefined.
        expectEqual(week.totals.smoothDefined, 4)
        expectEqual(week.totals.smooth, 4)
        expectEqual(week.families[.roads]?.smooth, 1)
        expectTrue(week.kinds.contains { $0.kind == "mysteryTrace" && $0.type == .practice && $0.family == nil },
                   "an unknown guided kind is practice with no family")
        // The quiz prior pools quiz rows only.
        expectEqual(week.pooledQuiz, 0.5)
    }

    // MARK: §4.3 per-round chance

    func testPerRoundChance() {
        let tuesday = PerfCodec.parseTimestamp("2026-10-20T10:00:00.000Z")!
        func chance(_ kind: String, _ fields: [String: PerfValue] = [:]) -> Double? {
            var all = fields
            all["kind"] = .string(kind)
            return WeeklyChance.chance(dealt: ev(.gameDealt, all, at: tuesday))
        }
        let four = PerfValue.strings(["count-3", "count-4", "count-5", "count-6"])
        expectEqual(chance("lineMatch", ["pairs": .int(2)]), 0.5)
        expectEqual(chance("lineMatch", ["pairs": .int(3)]), 1.0 / 6.0)
        expectEqual(chance("lineMatch", ["pairs": .int(4)]), 1.0 / 24.0)
        expectEqual(chance("lineMatch"), PerfChoiceCatalog.chance(for: .lineMatch))
        expectEqual(chance("tapCountPick", ["cars": .int(5)]), 0.2)
        expectEqual(chance("tapCountPickEnglish", ["cars": .int(8)]), 0.125)
        expectEqual(chance("countVehicles", ["gen": .string("variants_v1"), "slots": four]), 0.25)
        expectEqual(chance("countVehicles", ["slots": four]), 1.0 / 3.0)  // fixed item: catalog value
        expectEqual(chance("findTheSame", ["gen": .string("variants_v1"), "slots": .strings(["a", "b", "c"])]), 1.0 / 3.0)
        expectEqual(chance("tapLetterAll"), 1.0 / 45.0)
        expectEqual(chance("capacityCompare"), 0.5)
        expectEqual(chance("sequenceShortToLong"), 1.0 / 24.0)
        // A written `game_dealt.chance` wins; out-of-range or non-numbers fall back.
        expectEqual(chance("halfMatch", ["chance": .double(0.125)]), 0.125)
        expectEqual(chance("halfMatch", ["chance": .double(0)]), 1.0 / 3.0)
        expectEqual(chance("halfMatch", ["chance": .double(1.5)]), 1.0 / 3.0)
        expectEqual(chance("halfMatch", ["chance": .string("x")]), 1.0 / 3.0)
        expectNil(chance("mysteryQuiz"))
        expectEqual(chance("mysteryQuiz", ["chance": .double(0.2)]), 0.2)

        var events: [PerfEvent] = []
        for (offset, pairs) in [2, 3, 4].enumerated() {
            events += round("lineMatch", at: tuesday.addingTimeInterval(Double(offset) * 120),
                            dealt: ["pairs": .int(pairs), "match_mode": .string("free")])
        }
        events += round("tapCountPick", at: tuesday.addingTimeInterval(600), stars: 3,
                        dealt: ["cars": .int(5), "match_mode": .string("free")])
        events += round("mysteryQuiz", at: tuesday.addingTimeInterval(720))
        events += round("halfMatch", at: tuesday.addingTimeInterval(840),
                        result: ["answers": .int(0), "first_try": .null, "outcome": .string("abandoned")])
        let week = build(events, at: tuesday)
        let lineE = 0.5 + 1.0 / 6.0 + 1.0 / 24.0
        let line = week.kinds.first { $0.kind == "lineMatch" }
        expectEqual(week.rounds.filter { $0.kind == "lineMatch" }.map(\.chance), [0.5, 1.0 / 6.0, 1.0 / 24.0])
        expectEqual(line?.expected ?? -1, lineE, accuracy: 1e-12)
        expectEqual(line?.chanceMean ?? -1, lineE / 3, accuracy: 1e-12)
        expectEqual(line?.adjusted, 1.0)
        expectEqual(line?.estimate?.chance ?? -1, lineE / 3, accuracy: 1e-12)
        let mystery = week.kinds.first { $0.kind == "mysteryQuiz" }
        expectEqual(mystery?.chanceKnown, false)
        expectEqual(mystery?.rate, 1.0)
        expectEqual(mystery?.area, WeeklyArea.other)
        expectNil(mystery?.expected)
        expectNil(mystery?.estimate)
        // An unanswered round adds no chance.
        let half = week.kinds.first { $0.kind == "halfMatch" }
        expectEqual(half?.answered, 0)
        expectEqual(half?.expected, 0)
        expectNil(half?.chanceMean)
        // The tile's lucky-guess share (§4.8) leaves the kind without a chance out.
        expectEqual(week.totals.answered, 5)
        expectEqual(week.totals.expectedAnswered, 4)
        expectEqual(week.totals.expected, lineE + 0.2, accuracy: 1e-12)
        expectEqual(week.totals.chanceMean ?? -1, (lineE + 0.2) / 4, accuracy: 1e-12)
    }

    // MARK: §4.6 game minutes

    func testGameMinutesCap() {
        let wednesday = PerfCodec.parseTimestamp("2026-10-21T09:00:00.000Z")!  // 17:00 HKT
        var events: [PerfEvent] = []
        events += round("countVehicles", at: wednesday, seconds: 900)  // walked away for 15 minutes
        events += round("shadowMatch", at: wednesday.addingTimeInterval(1_000), seconds: 120)
        events += round("tapCountAll", at: wednesday.addingTimeInterval(1_200),
                        result: ["recount_attempts": .int(0), "answers": .int(0), "first_try": .null], seconds: 30)
        events += round("emptyBay", at: wednesday.addingTimeInterval(1_300), seconds: 600)  // exactly the cap
        // Dealt, then the app died without a result: unfinished, no game time.
        events.append(ev(.gameDealt, ["round": .string("lost"), "kind": .string("moreFewer"), "stars": .int(1)],
                         at: wednesday.addingTimeInterval(2_000)))
        events.append(ev(.appLaunch, [:], at: wednesday.addingTimeInterval(2_400), actor: .system, launch: "L2"))
        // Dealt 23:59 HKT, solved 00:04 the next day: it all counts on the day it was dealt.
        events += round("halfMatch", at: PerfCodec.parseTimestamp("2026-10-21T15:59:00.000Z")!, seconds: 300,
                        launch: "L2")
        let week = build(events, at: wednesday)

        expectEqual(WeeklyMetricsBuilder.gameMsCap, 600_000)
        expectEqual(week.rounds.map(\.gameMs), [600_000, 120_000, 30_000, 600_000, 0, 300_000])
        expectEqual(week.rounds.map(\.day), [2, 2, 2, 2, 2, 2])
        expectEqual(week.rounds[4].outcome, WeeklyRound.Outcome.noResult)
        expectEqual(week.days[2].quizMs, 1_620_000)
        expectEqual(week.days[2].practiceMs, 30_000)
        expectEqual(week.days[3].gameMs, 0)
        expectEqual(week.quizMs + week.practiceMs, 1_650_000)
        if case .object(let fields) = week.days[2].json {
            expectEqual(fields["game_min"], PerfValue.double(27.5))
            expectEqual(fields["quiz_min"], PerfValue.double(27))
            expectEqual(fields["practice_min"], PerfValue.double(0.5))
        } else {
            expectTrue(false, "day json is an object")
        }
        expectEqual(WeeklyJSON.number(27.5), "27.500000")
        expectEqual(WeeklyJSON.number(-0.0000001), "0.000000")
    }

    // MARK: §4.9 new games

    func testNewGameUsesRollup() {
        let tuesday = PerfCodec.parseTimestamp("2026-10-20T10:00:00.000Z")!  // 18:00 HKT, week of 2026-10-19
        let lastWeek = tuesday.addingTimeInterval(-7 * 86_400)
        var events: [PerfEvent] = []
        events += round("shadowMatch", at: lastWeek)  // raw history
        events += round("emptyBay", at: lastWeek.addingTimeInterval(600), actor: .parentPlaytest)  // not countable
        events += round("halfMatch", at: tuesday)  // its first raw round
        events += round("shadowMatch", at: tuesday.addingTimeInterval(120))
        events += round("lineMatch", at: tuesday.addingTimeInterval(240),
                        dealt: ["pairs": .int(2), "match_mode": .string("free")])
        events += round("emptyBay", at: tuesday.addingTimeInterval(360))
        events += round("countVehicles", at: tuesday.addingTimeInterval(86_400))  // Wednesday
        let window = WeeklyWindow(containing: tuesday)
        func newKinds(_ rollup: PerfRollup, _ extra: [PerfEvent] = []) -> [String] {
            WeeklyMetricsBuilder.build(events: events + extra, rollup: rollup, window: window).current.newKinds
        }
        expectEqual(newKinds(PerfRollup()), ["countVehicles", "halfMatch", "emptyBay", "lineMatch"])

        var played = PerfGameDayStats()
        played.deals = 3
        played.answered = 3
        var rollup = PerfRollup(foldedDays: ["2026-06-30"], days: ["2026-06-30": PerfDaySummary(games: ["halfMatch|1": played])])
        expectEqual(newKinds(rollup), ["countVehicles", "emptyBay", "lineMatch"])
        // A day summary without deals is no history.
        rollup.days["2026-07-01"] = PerfDaySummary(games: ["countVehicles|2|variants_v1": PerfGameDayStats()])
        expectEqual(newKinds(rollup), ["countVehicles", "emptyBay", "lineMatch"])
        // Guided practice folded under the kind still means it was played.
        var guided = PerfGameDayStats()
        guided.deals = 1
        rollup.days["2026-07-02"] = PerfDaySummary(games: ["lineMatch|1|variants_v1|guided": guided])
        expectEqual(newKinds(rollup), ["countVehicles", "emptyBay"])
        // 「清除表現紀錄」 resets "ever": the rollup days and last week's round are older than it.
        let cleared = ev(.statsMarker, ["what": .string("cleared")], at: lastWeek.addingTimeInterval(3_600),
                         actor: .parent, session: "p")
        expectEqual(newKinds(rollup, [cleared]), ["countVehicles", "halfMatch", "shadowMatch", "emptyBay", "lineMatch"])
        // A clear after the cut-off is not seen.
        let laterClear = ev(.statsMarker, ["what": .string("cleared")], at: window.end.addingTimeInterval(60),
                            actor: .parent, session: "p")
        expectEqual(newKinds(rollup, [laterClear]), ["countVehicles", "emptyBay"])

        let week = WeeklyMetricsBuilder.build(events: events, rollup: rollup, window: window).current
        expectEqual(week.days[1].newKinds, ["emptyBay"])  // Tuesday
        expectEqual(week.days[2].newKinds, ["countVehicles"])  // Wednesday
        expectEqual(week.kinds.first { $0.kind == "halfMatch" }?.isNew, false)
        expectEqual(week.kinds.first { $0.kind == "countVehicles" }?.isNew, true)
    }

    // MARK: Golden fixture (§9.6)

    func testWeeklyGoldenFixtureByteForByte() throws {
        let folder = Self.fixtureFolder("weekly-2026-10-19")
        let expectedURL = folder.appendingPathComponent("expected-metrics.json")
        guard FileManager.default.fileExists(atPath: expectedURL.path) else {
            preconditionFailure("weekly fixture not found at \(folder.path)")
        }
        let store = PerfEventStore(directory: folder)
        let read = store.read()
        expectEqual(read.skipped, 1, "the line torn by the power cut")
        expectEqual(read.events.count, 274)
        expectEqual(store.loadRollup().foldedDays, ["2026-06-30", "2026-07-02"])

        // D1: Monday 00:00 to Sunday 24:00 HKT. The report is made on Sunday at 21:00.
        let madeAt = PerfCodec.parseTimestamp("2026-10-25T13:00:00.000Z")!
        guard let window = WeeklyWindow(weekStart: "2026-10-19", dataUntil: madeAt) else {
            preconditionFailure("week stamp did not parse")
        }
        expectEqual(window.dayStamps, ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23",
                                       "2026-10-24", "2026-10-25"])
        expectEqual(PerfCodec.formatTimestamp(window.start), "2026-10-18T16:00:00.000Z")
        expectEqual(PerfCodec.formatTimestamp(window.end), "2026-10-25T16:00:00.000Z")
        expectEqual(window.cutoff, madeAt)
        expectTrue(window.contains(madeAt))
        expectFalse(window.contains(madeAt.addingTimeInterval(0.001)))
        let sundayNight = PerfCodec.parseTimestamp("2026-10-18T15:59:59.000Z")!  // Sunday 23:59:59 HKT
        let mondayMidnight = PerfCodec.parseTimestamp("2026-10-18T16:00:00.000Z")!  // Monday 00:00 HKT
        expectNil(window.dayIndex(sundayNight))
        expectEqual(window.dayIndex(mondayMidnight), 0)
        expectEqual(window.shifted(weeks: -1).dayIndex(sundayNight), 6)
        expectEqual(WeeklyWindow(containing: sundayNight).weekStartStamp, "2026-10-12")
        expectEqual(WeeklyWindow(containing: mondayMidnight).weekStartStamp, "2026-10-19")
        expectEqual(WeeklyWindow(weekStart: "2026-10-25")?.weekStartStamp, "2026-10-19")
        expectEqual(window.shifted(weeks: -1).cutoff, window.start)

        let rollup = store.loadRollup()
        let model = WeeklyMetricsBuilder.build(events: read.events, rollup: rollup, window: window)
        let actual = model.canonicalJSON()
        let expected = try String(contentsOf: expectedURL, encoding: .utf8)
        if actual != expected {
            let got = actual.components(separatedBy: "\n")
            let want = expected.components(separatedBy: "\n")
            var line = min(got.count, want.count)
            for index in 0..<min(got.count, want.count) where got[index] != want[index] {
                line = index
                break
            }
            let out = FileManager.default.temporaryDirectory.appendingPathComponent("weekly-2026-10-19-actual.json")
            try? Data(actual.utf8).write(to: out)
            let wantLine = line < want.count ? want[line] : "<end>"
            let gotLine = line < got.count ? got[line] : "<end>"
            preconditionFailure("weekly golden mismatch at line \(line + 1): expected [\(wantLine)] got [\(gotLine)]; "
                                + "actual written to \(out.path)")
        }
        print("  weekly golden: \(expected.utf8.count) bytes match")

        // Same records in any file order, same bytes (readers never assume file order).
        let shuffled = WeeklyMetricsBuilder.build(events: Array(read.events.reversed()), rollup: rollup, window: window)
        expectEqual(shuffled.canonicalJSON(), actual)
        // Spot checks that the fixture exercises what it claims (README.md).
        expectEqual(model.current.openAtCutoff, 1)
        expectEqual(model.current.excludedRounds, ["parent_uat": 2, "parent_playtest": 1, "excluded_session": 2])
        expectEqual(model.current.days[1].rounds, 0, "Tuesday: parent test mode only")
        expectTrue(model.current.days[4].videoEstimated, "Friday's play has no video_end")
        expectEqual(model.weeks.map(\.weekStart), ["2026-10-05", "2026-10-12", "2026-10-19"])
        expectTrue(model.weeks[0].partial)

        // Never the host's zone, calendar or locale; Traditional Chinese only.
        let root = Self.repoRoot()
        for name in ["WeeklyWindow.swift", "WeeklyMetrics.swift", "WeeklyJSON.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent("Sources/VisaCore/\(name)"), encoding: .utf8)
            for banned in ["TimeZone.current", "autoupdatingCurrent", "Locale.current", "Calendar.current", "NSTimeZone"] {
                expectFalse(text.contains(banned), "\(name) must not use \(banned)")
            }
            expectTrue(isTraditionalChineseOnly(text) && perfTraditionalOnly(text), "\(name) is Traditional only")
        }
    }

    // MARK: Budget

    func testWeeklyModel35kEventsUnderBudget() {
        let sunday = PerfCodec.parseTimestamp("2026-10-25T02:00:00.000Z")!  // 10:00 HKT
        let kinds = ActivityCatalog.playableKinds
        let practice: [String: PerfValue] = [
            "shapes_done": .int(2), "shapes_total": .int(2), "wrong_start": .int(0), "reverse_direction": .int(0),
            "off_path_count": .int(1), "ink_outside_ratio": .double(0.1), "erasers": .int(0), "roads": .int(2),
            "roads_total": .int(2), "recount_attempts": .int(0), "guide_clean": .int(1), "guide_helps": .int(1)
        ]
        var events: [PerfEvent] = []
        events.reserveCapacity(35_200)
        for back in stride(from: 89, through: 0, by: -1) {
            let morning = sunday.addingTimeInterval(-Double(back) * 86_400)
            let launch = "L\(back / 7)"
            let session = "s\(back)"
            for index in 0..<95 {
                let kind = kinds[(back + index) % kinds.count]
                let dealtAt = morning.addingTimeInterval(Double(index) * 90)
                let id = "r\(back)-\(index)"
                var dealt: [String: PerfValue] = ["round": .string(id), "kind": .string(kind.rawValue),
                                                  "stars": .int(1 + index % 3)]
                if kind.tapCountBase == .tapCountPick { dealt["cars"] = .int(6) }
                if kind == .lineMatch { dealt["pairs"] = .int(3) }
                let wrong = index % 3 == 0
                events.append(ev(.gameDealt, dealt, at: dealtAt, session: session, launch: launch))
                events.append(ev(.answerAttempt, ["round": .string(id), "correct": .bool(!wrong), "fast": .bool(wrong),
                                                  "tags": .strings(wrong ? ["over_by_1"] : [])],
                                 at: dealtAt.addingTimeInterval(20), session: session, launch: launch))
                // Every result also carries the practice extras, so practice rounds test their rules.
                var result: [String: PerfValue] = [
                    "round": .string(id), "outcome": .string("solved"), "answers": .int(wrong ? 2 : 1),
                    "first_try": .bool(!wrong), "misses": .int(wrong ? 1 : 0), "total_ms": .int(40_000),
                    "active_ms": .int(9_000), "earned_min": .int(5)
                ]
                result.merge(practice) { current, _ in current }
                events.append(ev(.roundResult, result, at: dealtAt.addingTimeInterval(40), session: session,
                                 launch: launch))
            }
            for play in 0..<35 {
                let start = morning.addingTimeInterval(9_000 + Double(play) * 400)
                let id = "p\(back)-\(play)"
                events.append(ev(.videoStart, ["play": .string(id), "video": .string("vid\(play % 8)"),
                                               "source": .string("pick")], at: start, session: session, launch: launch))
                events.append(ev(.videoProgress, ["play": .string(id), "watched_s": .double(59.5)],
                                 at: start.addingTimeInterval(60), session: session, launch: launch))
                events.append(ev(.videoEnd, ["play": .string(id), "watched_s": .double(300.5),
                                             "stop_reason": .string("ended")],
                                 at: start.addingTimeInterval(302), session: session, launch: launch))
            }
        }
        var rollup = PerfRollup()
        for back in 91..<456 {
            var stats = PerfGameDayStats()
            stats.deals = 20
            stats.answered = 20
            stats.firstTry = 12
            let stamp = PerfClock.dayStamp(sunday.addingTimeInterval(-Double(back) * 86_400), timeZone: PerfClock.hongKong)
            rollup.days[stamp] = PerfDaySummary(games: ["countVehicles|1": stats])
        }
        expectTrue(events.count >= 35_000, "fixture size \(events.count)")
        let window = WeeklyWindow(containing: sunday)
        let started = Date()
        let model = WeeklyMetricsBuilder.build(events: events, rollup: rollup, window: window)
        let elapsed = Date().timeIntervalSince(started)
        print("  35k weekly model: \(events.count) events in \(Int((elapsed * 1000).rounded())) ms")
        expectTrue(elapsed < 0.3, "weekly model took \(elapsed) s (budget 0.3 s)")
        expectEqual(model.current.totals.rounds, 7 * 95)
        expectEqual(model.previous.totals.rounds, 7 * 95)
        expectEqual(model.weeks.count, WeeklyMetricsBuilder.trendWeeks + 1)
        expectEqual(model.current.newKinds, [])
    }
}
