import Foundation
import VisaCore

/// v0.21.0 Review (design §3.4–3.9, §7.3–7.4, §11): mastery, labels, video appeal and the
/// report aggregator. The §3.9 worked examples are the fixtures.
final class PerformanceReviewTests {
    private let now = PerfCodec.parseTimestamp("2026-10-09T10:00:00.000Z")!  // 18:00 HKT
    private var seq = 0

    private func near(_ actual: Double, _ expected: Double, _ tolerance: Double = 1e-3,
                      _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        expectTrue(abs(actual - expected) <= tolerance, "\(message) expected \(expected), got \(actual)",
                   file: file, line: line)
    }

    private func evidence(_ rounds: [(age: Int, right: Bool)]) -> PerfMastery.Evidence {
        var e = PerfMastery.Evidence()
        for r in rounds { e.add(ageDays: Double(r.age), firstTry: r.right) }
        return e
    }

    // MARK: Event fixtures

    private func ev(_ type: PerfEventType, _ fields: [String: PerfValue], daysAgo: Int = 0, minute: Int = 0,
                    actor: PerfActor = .child, session: String = "s1") -> PerfEvent {
        seq += 1
        let at = now.addingTimeInterval(-Double(daysAgo) * 86_400 - 3600 + Double(minute) * 60 + Double(seq) * 0.001)
        return PerfEvent(v: PerfEvent.schemaVersion, type: type, timestamp: at, tz: "+08:00", mono: Double(seq),
                         launch: "L1", seq: seq, app: "0.21.0", actor: actor, mode: "lock",
                         session: session, fields: fields)
    }

    /// One dealt + resolved round.
    private func round(_ kind: ActivityKind, daysAgo: Int, outcome: String = "solved", firstTry: Bool,
                       stars: Int = 1, answers: Int = 1, actor: PerfActor = .child,
                       session: String = "s1") -> [PerfEvent] {
        seq += 1
        let id = "r\(seq)"
        return [
            ev(.gameDealt, ["round": .string(id), "kind": .string(kind.rawValue), "stars": .int(stars)],
               daysAgo: daysAgo, actor: actor, session: session),
            ev(.roundResult, ["round": .string(id), "outcome": .string(outcome), "first_try": .bool(firstTry),
                              "answers": .int(answers), "active_ms": .int(4000), "first_tap_ms": .int(1500)],
               daysAgo: daysAgo, minute: 1, actor: actor, session: session)
        ]
    }

    private func report(_ events: [PerfEvent], rollup: PerfRollup = PerfRollup(), videos: [String] = [],
                        window: PerfReportWindow = .days30) -> PerfReport {
        PerfReportBuilder.build(events: events, rollup: rollup, videos: videos.map { (id: $0, title: $0.uppercased()) },
                                now: now, window: window)
    }

    private func row(_ report: PerfReport, _ kind: ActivityKind) -> PerfGameRow {
        report.games.first { $0.kind == kind }!
    }

    // MARK: Worked examples (§3.9, m̄ = 0.55, H = 7)

    func testWorkedExampleA_ShadowConfident() {
        let e = evidence([0, 1, 2, 4, 6, 8, 10, 13].map { ($0, $0 != 10) })
        near(e.weight, 5.051, 2e-3, "Σw")
        near(e.success, 4.680, 2e-3, "s")
        let est = PerfMastery.estimate(chance: PerfChoiceCatalog.chance(for: .shadowMatch), pooled: 0.55, evidence: e)
        near(est.alpha, 7.480, 2e-3, "α")
        near(est.beta, 1.571, 2e-3, "β")
        near(est.mean, 0.826, 2e-3, "p̂")
        near(est.sd, 0.119, 2e-3, "sd")
        near(est.mastery, 0.740, 2e-3, "m̂")
        near(est.masteryLow, 0.589, 2e-3, "m20")
        expectEqual(PerfMastery.label(evidence: e, estimate: est, fuelOutsInLastFive: 0), .confident)
    }

    func testWorkedExampleB_HalfPractiseWithFuelFlag() {
        let ages = [9, 7, 5, 3, 1, 0]  // oldest first
        let e = evidence(ages.map { ($0, $0 == 9) })
        near(e.weight, 4.168, 2e-3, "Σw")
        let est = PerfMastery.estimate(chance: PerfChoiceCatalog.chance(for: .halfMatch), pooled: 0.55, evidence: e)
        near(est.alpha, 3.210, 2e-3, "α")
        near(est.beta, 4.958, 2e-3, "β")
        near(est.mastery, 0.089, 2e-3, "m̂")
        near(est.masteryHigh, 0.293, 2e-3, "m80")
        let dots: [PerfRoundDot] = ages.map { $0 == 9 ? .firstTry : ($0 == 0 || $0 == 3 ? .fuelOut : .retried) }
        expectEqual(PerfMastery.fuelOutFlag(lastOutcomes: dots), 2)
        expectEqual(PerfMastery.label(evidence: e, estimate: est, fuelOutsInLastFive: 2), .practise)
        // Through the report: same label, 最近油用晒 2 次.
        var events: [PerfEvent] = []
        for age in ages {
            events += round(.halfMatch, daysAgo: age, outcome: age == 0 || age == 3 ? "zeroed" : "solved",
                            firstTry: age == 9, answers: 2)
        }
        let r = row(report(events), .halfMatch)
        expectEqual(r.label, .practise)
        expectEqual(r.fuelOutFlag, 2)
        expectEqual(r.dots.count, 6)
    }

    func testWorkedExampleC_InsufficientBelowFive() {
        let e = evidence([(4, true), (2, true), (0, true)])
        near(e.weight, 2.493, 2e-3, "Σw")
        let est = PerfMastery.estimate(chance: PerfChoiceCatalog.chance(for: .countVehicles), pooled: 0.55, evidence: e)
        expectEqual(PerfMastery.label(evidence: e, estimate: est, fuelOutsInLastFive: 0), .insufficient)
        expectEqual(PerfMastery.roundsMissing(e), 2)
        // Five old rounds still too light (Σw < 3).
        let old = evidence((0..<5).map { (20 + $0, true) })
        let oldEst = PerfMastery.estimate(chance: 1.0 / 3.0, pooled: 0.55, evidence: old)
        expectEqual(PerfMastery.label(evidence: old, estimate: oldEst, fuelOutsInLastFive: 0), .insufficient)
    }

    func testWorkedExampleD_TwoChoiceChanceCorrection() {
        let e = evidence([0, 2, 3, 5, 8, 11, 12].map { ($0, $0 != 3 && $0 != 11) })
        near(e.weight, 4.267, 2e-3, "Σw")
        let est = PerfMastery.estimate(chance: PerfChoiceCatalog.chance(for: .capacityCompare), pooled: 0.55, evidence: e)
        near(est.prior, 0.775, 1e-6, "p0")
        near(est.alpha, 6.287, 2e-3, "α")
        near(est.beta, 1.979, 2e-3, "β")
        near(est.mean, 0.761, 2e-3, "p̂")
        near(est.sd, 0.140, 2e-3, "sd")
        near(est.mastery, 0.521, 2e-3, "m̂")
        near(est.masteryLow, 0.285, 2e-3, "m20")
        near(est.masteryHigh, 0.757, 2e-3, "m80")
        expectEqual(PerfMastery.label(evidence: e, estimate: est, fuelOutsInLastFive: 0), .learning)
    }

    func testFreshDataLabelTable() {
        func label(_ k: Int, of n: Int, chance: Double) -> PerfMastery.Label {
            let e = PerfMastery.Evidence(rounds: n, success: 0.9 * Double(k), failure: 0.9 * Double(n - k))
            let est = PerfMastery.estimate(chance: chance, pooled: 0.5, evidence: e)
            return PerfMastery.label(evidence: e, estimate: est, fuelOutsInLastFive: 0)
        }
        let chances = [0.5, 1.0 / 3.0, 1.0 / 24.0]
        let table: [(Int, [PerfMastery.Label])] = [
            (5, [.confident, .confident, .confident]),
            (4, [.learning, .learning, .learning]),
            (3, [.learning, .learning, .learning]),
            (2, [.practise, .practise, .learning]),
            (1, [.practise, .practise, .practise])
        ]
        for (k, expected) in table {
            for (index, chance) in chances.enumerated() {
                expectEqual(label(k, of: 5, chance: chance), expected[index], "\(k)/5 chance \(chance)")
            }
        }
        for chance in chances { expectEqual(label(9, of: 10, chance: chance), .confident, "9/10 \(chance)") }
        expectEqual(label(8, of: 10, chance: 0.5), .learning)
        expectEqual(label(8, of: 10, chance: 1.0 / 3.0), .learning)
        expectEqual(label(8, of: 10, chance: 1.0 / 24.0), .confident)
        // 要多練 starts at ≤ 6/10 (2-choice), ≤ 5/10 (3-choice), ≤ 3/10 (convoy).
        expectEqual(label(6, of: 10, chance: 0.5), .practise)
        expectTrue(label(7, of: 10, chance: 0.5) != .practise)
        expectEqual(label(5, of: 10, chance: 1.0 / 3.0), .practise)
        expectTrue(label(6, of: 10, chance: 1.0 / 3.0) != .practise)
        expectEqual(label(3, of: 10, chance: 1.0 / 24.0), .practise)
        expectTrue(label(4, of: 10, chance: 1.0 / 24.0) != .practise)
        expectEqual(label(4, of: 4, chance: 0.5), .insufficient)
    }

    func testHalfLifeSevenDays() {
        near(PerfMastery.weight(ageDays: 0), 1, 1e-12)
        near(PerfMastery.weight(ageDays: 7), 0.5, 1e-12)
        near(PerfMastery.weight(ageDays: 14), 0.25, 1e-12)
        near(PerfMastery.weight(ageDays: 90), 0.000135, 2e-6)
    }

    func testPooledPriorFallbackAndClamp() {
        let small = PerfMastery.Evidence(rounds: 10, success: 9, failure: 1)
        near(PerfMastery.pooledPrior([(0.5, small)]), 0.5, 1e-12, "fallback below Σw 20")
        let perfect = PerfMastery.Evidence(rounds: 30, success: 30, failure: 0)
        near(PerfMastery.pooledPrior([(1.0 / 3.0, perfect)]), 0.8, 1e-12, "clamped high")
        let wrong = PerfMastery.Evidence(rounds: 30, success: 0, failure: 30)
        near(PerfMastery.pooledPrior([(1.0 / 3.0, wrong)]), 0.2, 1e-12, "clamped low")
        // Weighted mix: 2-choice at 75% (m 0.5) Σw 20 + 3-choice at 2/3 (m 0.5) Σw 10 → 0.5.
        let mixA = PerfMastery.Evidence(rounds: 20, success: 15, failure: 5)
        let mixB = PerfMastery.Evidence(rounds: 10, success: 20.0 / 3.0, failure: 10.0 / 3.0)
        near(PerfMastery.pooledPrior([(0.5, mixA), (1.0 / 3.0, mixB)]), 0.5, 1e-9, "weighted")
    }

    func testPerStarCountsPooledLabel() {
        var events: [PerfEvent] = []
        for stars in 1...3 {
            events += round(.moreFewer, daysAgo: 0, firstTry: true, stars: stars)
            events += round(.moreFewer, daysAgo: 1, outcome: stars == 3 ? "zeroed" : "solved",
                            firstTry: stars != 3, stars: stars, answers: 2)
        }
        let r = row(report(events), .moreFewer)
        expectEqual(r.stars.map(\.rounds), [2, 2, 2])
        expectEqual(r.stars.map(\.firstTry), [2, 2, 1])
        expectEqual(r.stars.map(\.fuelOuts), [0, 0, 1])
        // 6 pooled rounds → labelled even though every star has fewer than 5.
        expectEqual(r.evidence.rounds, 6)
        expectTrue(r.label != .insufficient)
        expectEqual(r.firstTry, 5)
    }

    func testTrendNeedsThreeRoundsPerWeek() {
        let recent: [(ageDays: Int, firstTry: Bool)] = [(0, true), (1, true), (2, true)]
        expectEqual(PerfMastery.trend(recent + [(8, false), (9, false)]), nil)
        expectEqual(PerfMastery.trend(recent + [(8, false), (9, false), (10, true)]), .up)
        expectEqual(PerfMastery.trend([(0, false), (1, false), (2, true), (8, true), (9, true), (10, true)]), .down)
        expectEqual(PerfMastery.trend([(0, true), (1, true), (2, false), (8, true), (9, true), (10, false)]), .flat)
        expectEqual(PerfMastery.trend(recent + [(15, false), (16, false), (17, false)]), nil)
    }

    func testExcludedSessionDropsOut() {
        var events: [PerfEvent] = []
        for i in 0..<5 { events += round(.findTheSame, daysAgo: i, firstTry: true, session: "s1") }
        for i in 0..<3 { events += round(.findTheSame, daysAgo: 0, firstTry: false, session: "s2") }
        events += round(.findTheSame, daysAgo: 0, firstTry: true, actor: .parentUAT, session: "s3")
        let before = report(events)
        expectEqual(row(before, .findTheSame).answered, 8)
        expectEqual(before.sessions.first(where: { $0.id == "s3" })?.tested, true)
        let excluded = events + [ev(.statsExclude, ["target_session": .string("s2")], actor: .parent, session: "p")]
        let after = report(excluded)
        expectEqual(row(after, .findTheSame).answered, 5)
        expectEqual(after.sessions.first(where: { $0.id == "s2" })?.excluded, true)
        let restored = report(excluded + [ev(.statsInclude, ["target_session": .string("s2")], minute: 5,
                                             actor: .parent, session: "p")])
        expectEqual(row(restored, .findTheSame).answered, 8)
        expectEqual(restored.sessions.first(where: { $0.id == "s2" })?.excluded, false)
    }

    // MARK: Videos

    private func visit(_ id: String, deck: [String], pages: [Int], pick: (video: String, page: Int, slot: Int)?,
                       daysAgo: Int = 0) -> [PerfEvent] {
        var events = [ev(.pickerVisit, ["visit": .string(id), "deck": .strings(deck),
                                        "page_count": .int(VideoPickerDeck.pageCount(itemCount: deck.count))],
                         daysAgo: daysAgo)]
        for page in pages {
            events.append(ev(.videoImpressions, ["visit": .string(id), "page": .int(page),
                                                 "ids": .strings(PerfPickerPlacement.ids(deck: deck, page: page))],
                             daysAgo: daysAgo))
        }
        if let pick {
            events.append(ev(.videoPick, ["visit": .string(id), "video": .string(pick.video), "page": .int(pick.page),
                                          "slot": .int(pick.slot), "accepted": .bool(true)], daysAgo: daysAgo))
        }
        return events
    }

    func testVideoLabels_NotShownVsSeenNeverPicked() {
        expectEqual(PerfVideoAppeal.label(impressions: 0, observed: 0, expected: 0), .notShown)
        expectEqual(PerfVideoAppeal.label(impressions: 30, observed: 0, expected: 2.5), .seenNever)
        expectEqual(PerfVideoAppeal.label(impressions: 10, observed: 0, expected: 1.2), .insufficient)
        expectEqual(PerfVideoAppeal.label(impressions: 40, observed: 0, expected: 4), .seenNever)
        expectEqual(PerfVideoAppeal.label(impressions: 40, observed: 1, expected: 4), .rare)
        expectEqual(PerfVideoAppeal.label(impressions: 40, observed: 8, expected: 3), .favourite)
        expectEqual(PerfVideoAppeal.label(impressions: 40, observed: 3, expected: 1), .insufficient)
        expectEqual(PerfVideoAppeal.label(impressions: 40, observed: 3, expected: 3), .sometimes)
        // Through the report: a short deck where 'a' is always picked.
        let deck = ["a", "b", "c"]
        var events: [PerfEvent] = []
        for i in 0..<9 { events += visit("v\(i)", deck: deck, pages: [0], pick: ("a", 0, 0)) }
        let r = report(events, videos: ["a", "b", "c", "z"])
        let label = Dictionary(uniqueKeysWithValues: r.videos.map { ($0.id, $0.label) })
        expectEqual(label["z"], .notShown)
        expectEqual(label["b"], .seenNever)  // E = 9 / 3 = 3
        expectEqual(label["a"], .favourite)
        expectEqual(r.videos.map(\.id).last, "z", "未出過 sorts last")
        expectEqual(r.videos.count, 4, "every allowlisted video has a row")
    }

    func testAppealUsesImpressionsNotDeckPosition() {
        let deck = (0..<12).map { "v\($0)" }
        // Only page 1 drawn: v8…v11 (page 2) are in the deck but never shown.
        let events = visit("x", deck: deck, pages: [0], pick: ("v0", 0, 0))
        let r = report(events, videos: deck)
        let byId = Dictionary(uniqueKeysWithValues: r.videos.map { ($0.id, $0) })
        near(byId["v0"]!.expected, 1.0 / 8.0, 1e-9)
        near(byId["v7"]!.expected, 1.0 / 8.0, 1e-9)
        near(byId["v9"]!.expected, 0, 1e-12)
        expectEqual(byId["v9"]!.label, .notShown)
        near(r.videos.reduce(0) { $0 + $1.expected }, 1, 1e-9, "E sums to the picks")
        // Slot model kicks in at 30 picks; below it π = 1.
        let model = PerfVideoAppeal.SlotModel(picks: [PerfVideoAppeal.Cell(page: 0, slot: 0): 29],
                                              impressions: [PerfVideoAppeal.Cell(page: 0, slot: 0): 40])
        near(model.weight(PerfVideoAppeal.Cell(page: 0, slot: 0)), 1, 1e-12)
    }

    func testPagingRate() {
        let deck = (0..<12).map { "v\($0)" }
        var events = visit("p1", deck: deck, pages: [0, 1], pick: ("v8", 1, 0))
        events += visit("p2", deck: deck, pages: [0], pick: ("v1", 0, 1))
        events += visit("p3", deck: Array(deck.prefix(6)), pages: [0], pick: ("v2", 0, 2))
        let r = report(events, videos: deck)
        expectEqual(r.multiPageVisits, 2)
        expectEqual(r.pagedVisits, 1)
        near(r.pagingRate ?? -1, 0.5, 1e-12)
        near(r.slotShares?.reduce(0, +) ?? 0, 1, 1e-12, "slot map sums to 100%")
        expectEqual(r.slotPicks, [1, 1, 1, 0, 0, 0, 0, 0])
    }

    func testWatchOutcomesNeverChangeVideoLabel() {
        let deck = ["a", "b", "c"]
        var base: [PerfEvent] = []
        for i in 0..<9 { base += visit("w\(i)", deck: deck, pages: [0], pick: (i % 3 == 0 ? "b" : "a", 0, 0)) }
        var watchedToEnd = base
        var cutByTime = base
        for i in 0..<9 {
            let video = i % 3 == 0 ? "b" : "a"
            watchedToEnd.append(ev(.videoStart, ["play": .string("e\(i)"), "video": .string(video), "source": .string("pick")]))
            watchedToEnd.append(ev(.videoEnd, ["play": .string("e\(i)"), "video": .string(video), "stop_reason": .string("ended"),
                                               "watched_s": .seconds(300), "telemetry": .string("full")]))
            cutByTime.append(ev(.videoStart, ["play": .string("t\(i)"), "video": .string(video), "source": .string("pick")]))
            cutByTime.append(ev(.videoEnd, ["play": .string("t\(i)"), "video": .string(video),
                                            "stop_reason": .string("visa_expired"), "resume_saved": .bool(true),
                                            "watched_s": .seconds(20), "telemetry": .string("none")]))
        }
        let a = report(watchedToEnd, videos: deck)
        let b = report(cutByTime, videos: deck)
        expectEqual(a.videos.map(\.label), b.videos.map(\.label))
        expectEqual(a.videos.map(\.appeal), b.videos.map(\.appeal))
        let cutA = b.videos.first { $0.id == "a" }!
        expectEqual(cutA.timeUpStops, 6)
        expectEqual(cutA.noTelemetryPlays, 6)
        expectEqual(a.videos.first { $0.id == "a" }!.completions, 6)
        // 'continue' later links the time-up stop; after_parent is not a new play.
        let resumed = cutByTime + [
            ev(.videoStart, ["play": .string("c1"), "video": .string("a"), "source": .string("after_parent")], minute: 30),
            ev(.videoStart, ["play": .string("c2"), "video": .string("a"), "source": .string("continue")], minute: 31)
        ]
        let rr = report(resumed, videos: deck).videos.first { $0.id == "a" }!
        expectEqual(rr.timeUpResumedLater, 1)
        expectEqual(rr.plays, 7)
        expectEqual(rr.continues, 1)
    }

    func testReportMergesRollupAndRaw() {
        var rollup = PerfRollup()
        var stats = PerfGameDayStats()
        stats.deals = 4
        stats.answered = 4
        stats.firstTry = 3
        stats.solved = 4
        var video = PerfVideoDayStats()
        video.impressions = 6
        video.picks = 2
        video.expectedPicks = 1.5
        video.picksBySlot = [2, 0, 0, 0, 0, 0, 0, 0]
        var day = PerfDaySummary(games: ["emptyBay|2": stats], videos: ["a": video])
        day.multiPageVisits = 2
        day.pagedVisits = 1
        let oldStamp = PerfClock.dayStamp(now.addingTimeInterval(-100 * 86_400), timeZone: PerfClock.hongKong)
        let todayStamp = PerfClock.dayStamp(now, timeZone: PerfClock.hongKong)
        rollup.days[oldStamp] = day
        rollup.days[todayStamp] = day  // raw file exists for today → ignored
        var events: [PerfEvent] = []
        for i in 0..<2 { events += round(.emptyBay, daysAgo: i, firstTry: true, stars: 2) }
        events += visit("m", deck: ["a", "b"], pages: [0], pick: ("a", 0, 0))
        let all = report(events, rollup: rollup, videos: ["a", "b"], window: .all)
        let game = row(all, .emptyBay)
        expectEqual(game.deals, 6)
        expectEqual(game.answered, 6)
        expectEqual(game.firstTry, 5)
        expectEqual(game.stars[1].rounds, 6)
        expectEqual(game.evidence.rounds, 6)
        let a = all.videos.first { $0.id == "a" }!
        expectEqual(a.impressions, 7)
        expectEqual(a.picks, 3)
        near(a.expected, 2.0, 1e-9)
        expectEqual(all.slotPicks[0], 3)
        expectEqual(all.multiPageVisits, 2)
        let recent = report(events, rollup: rollup, videos: ["a", "b"], window: .days30)
        expectEqual(row(recent, .emptyBay).deals, 2)
        expectEqual(row(recent, .emptyBay).evidence.rounds, 6, "labels still use all retained data")
        expectEqual(recent.videos.first { $0.id == "a" }!.picks, 1)
    }

    func testRollupSchemaTwoLoadsV1AndFoldsNewCounters() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("perf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PerfEventStore(directory: root.appendingPathComponent("stats", isDirectory: true))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        let v1 = """
        {"rollup_schema":1,"folded_days":["2026-06-01"],"days":{"2026-06-01":{"games":{"findTheSame|1":{"deals":2,"answered":2,"first_try":1,\
        "misses":1,"solved":2,"zeroed":0,"abandoned":0,"hinted":0,"active_ms":9000}},\
        "videos":{"a":{"impressions":3,"picks":1}},"uncounted_rounds":0,"uncounted_plays":0}}}
        """
        try Data(v1.utf8).write(to: store.rollupURL)
        let loaded = store.loadRollup()
        expectEqual(loaded.rollupSchema, PerfRollup.currentSchema)
        expectEqual(loaded.days["2026-06-01"]?.games["findTheSame|1"]?.firstTry, 1)
        expectEqual(loaded.days["2026-06-01"]?.games["findTheSame|1"]?.activeHistogram, [0, 0, 0, 0, 0, 0])
        expectEqual(loaded.days["2026-06-01"]?.videos["a"]?.picksBySlot.count, 8)

        // Fold of raw events fills the schema-2 counters.
        let deck = (0..<10).map { "v\($0)" }
        var events = round(.findTheSame, daysAgo: 0, firstTry: true)
        events += visit("f", deck: deck, pages: [0, 1], pick: ("v9", 1, 1))
        let stamp = PerfClock.dayStamp(now, timeZone: PerfClock.hongKong)
        let summary = PerfSummaries.daySummaries(events: events, days: [stamp], excluded: [],
                                                 timeZone: PerfClock.hongKong)[stamp]!
        expectEqual(summary.games["findTheSame|1"]?.activeHistogram, [1, 0, 0, 0, 0, 0])
        expectEqual(summary.videos["v9"]?.picksBySlot[1], 1)
        expectEqual(summary.videos["v9"]?.impressionsByPage, [0, 1, 0, 0])
        expectEqual(summary.videos["v0"]?.impressionsByPage, [1, 0, 0, 0])
        near(summary.videos.values.reduce(0) { $0 + $1.expectedPicks }, 1, 1e-9)
        expectEqual(summary.multiPageVisits, 1)
        expectEqual(summary.pagedVisits, 1)
    }

    func testEmptyReportAndSummaryCSVs() {
        let empty = report([], videos: ["a"])
        expectTrue(empty.isEmpty)
        expectEqual(empty.games.count, ActivityCatalog.playableKinds.count)
        expectTrue(empty.games.allSatisfy { $0.label == .insufficient && $0.roundsMissing == 5 })
        expectEqual(empty.videos.first?.label, .notShown)
        expectEqual(empty.pagingRate, nil)
        expectEqual(empty.slotShares, nil)
        var events: [PerfEvent] = []
        for i in 0..<5 { events += round(.shadowMatch, daysAgo: i, firstTry: true) }
        let files = PerfCSVExport.files(events: events, rollup: PerfRollup(), titles: ["a": "Apple"], order: ["a"], now: now)
        let games = files["games_summary.csv"] ?? ""
        expectTrue(games.hasPrefix(PerfCSVExport.bom + PerfCSVExport.gamesSummaryHeader.joined(separator: ",")))
        expectTrue(games.contains("shadowMatch,"))
        let videos = files["videos_summary.csv"] ?? ""
        expectTrue(videos.contains("a,Apple,notShown,未出過"))
    }

    func testReportBuilds35kEventsUnderBudget() {
        var events: [PerfEvent] = []
        events.reserveCapacity(36_000)
        let deck = (0..<24).map { "vid\($0)" }
        let kinds = ActivityCatalog.playableKinds
        var n = 0
        for day in 0..<90 {
            for i in 0..<75 {
                let dealt = round(kinds[(day + i) % kinds.count], daysAgo: day, firstTry: i % 3 != 0)
                events += dealt
                events.append(ev(.answerAttempt, ["round": dealt[0]["round"] ?? .null, "correct": .bool(i % 3 != 0),
                                                  "tags": .strings(i % 3 != 0 ? [] : ["same_shape+diff_color"])],
                                 daysAgo: day))
                n += 1
            }
            for i in 0..<30 {
                events += visit("d\(day)v\(i)", deck: deck, pages: i % 2 == 0 ? [0, 1] : [0],
                                pick: (deck[(i * 7 + day) % 8], 0, (i * 7 + day) % 8), daysAgo: day)
                events.append(ev(.videoStart, ["video": .string(deck[i % 8]), "source": .string("pick")], daysAgo: day))
                events.append(ev(.videoEnd, ["video": .string(deck[i % 8]), "stop_reason": .string("ended"),
                                             "watched_s": .seconds(200), "telemetry": .string("full")], daysAgo: day))
            }
        }
        expectTrue(events.count >= 35_000, "fixture size \(events.count)")
        var rollup = PerfRollup()
        for d in 91..<456 {
            let stamp = PerfClock.dayStamp(now.addingTimeInterval(-Double(d) * 86_400), timeZone: PerfClock.hongKong)
            var stats = PerfGameDayStats()
            stats.deals = 20
            stats.answered = 20
            stats.firstTry = 12
            rollup.days[stamp] = PerfDaySummary(games: ["countVehicles|1": stats])
        }
        let start = Date()
        let built = PerfReportBuilder.build(events: events, rollup: rollup, videos: deck.map { ($0, $0) },
                                            now: now, window: .days30)
        let elapsed = Date().timeIntervalSince(start)
        print("  35k report: \(events.count) events in \(String(format: "%.2f", elapsed)) s")
        // AC is < 2 s in release on the Mac mini; debug builds on CI get headroom.
        expectTrue(elapsed < 15, "report took \(elapsed) s")
        expectFalse(built.isEmpty)
        expectEqual(built.videos.count, 24)
        _ = n
    }

    /// Layout-safety source guard for the 表現 view (parent SIGBUS history + the 進階 lesson):
    /// no lazy stacks / grids / GeometryReader / DisclosureGroup / animations, full-row buttons,
    /// `.equatable()` at the call site, and the report is only built from the segment button.
    func testReviewViewLayoutSafetySourceGuard() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let review = try String(contentsOf: root.appendingPathComponent("Sources/VisaGames/ParentReviewView.swift"),
                                encoding: .utf8)
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/VisaGames/ParentSettingsView.swift"),
                                  encoding: .utf8)
        for banned in ["LazyVGrid", "LazyVStack", "LazyHStack", "GeometryReader", "DisclosureGroup", "withAnimation",
                       ".animation(", "onAppear", ".task", "FileManager", "PerfReportBuilder"] {
            expectFalse(review.contains(banned), "ParentReviewView must not use \(banned)")
        }
        expectTrue(review.contains("struct ParentReviewView: View, Equatable"))
        expectTrue(review.contains(".contentShape(Rectangle())"))
        expectTrue(settings.contains(".equatable()"))
        expectTrue(settings.contains("if next == .review { model.perfRefreshReview() }"))
        for string in ["表現", "遊戲表現", "影片表現", "一眼睇", "未有紀錄", "計緊…", "更新", "最近玩過", "唔計呢段", "計返",
                       "播放結果只供參考，唔影響標籤。", "只計小朋友自己玩。家長試玩、測試簽證、測試模式都唔計。",
                       "紀錄只存喺呢部 Mac，唔會上網。", "● 一次答啱　◐ 試多次先啱　○ 油用晒　· 未完成",
                       "測試模式開緊：而家玩嘅唔會計。", "撳邊個位多", "已扣除估中機會（兩揀一 50%，三揀一 33%）"] {
            expectTrue(review.contains(string) || settings.contains(string), "missing UI string \(string)")
        }
    }
}
