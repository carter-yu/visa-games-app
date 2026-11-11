import Foundation
import VisaCore

/// Clock + elapsed chip C1 (0.39.0 / 86): the child glance chip layer's pure decisions (clock-playtime design §1.3,
/// §2.1–2.3, §2.7, §6, §9 C1, D-C0b and D-C0c; chip-rows/compare.md FINAL v1 §5) and source guards on the app wiring
/// (`ShellView`, `AppModel.launchUptime`, `StatusClockLayer`), which this box cannot compile. Since C5 (0.39.0 / 87)
/// Watch has the strip slot; its own checks are `StatusWatchStripTests`. Expected values are written out here, never
/// recomputed with the code under test.
final class StatusChipLayerTests {
    private static func utc(_ stamp: String) -> Date { PerfCodec.parseTimestamp(stamp)! }

    /// S, S_pick and the Watch strip slot (design §2.3; compare.md §4–§5).
    private static let s = LineMatchRect(x: 1190, y: 6, width: 84, height: 40)
    private static let sPick = LineMatchRect(x: 1042, y: 6, width: 84, height: 40)
    private static let watchStrip = LineMatchRect(x: 1196, y: 0, width: 84, height: 40)

    /// The header families of design §2.3 rows 2–4 (10 + 4 + 13 kinds).
    private static let boardTwo: [ActivityKind] = [.twoPictureChoose, .findTheSame, .countVehicles, .sequenceShortToLong,
                                                   .halfMatch, .shapeCousin, .capacityCompare, .moreFewer, .shadowMatch,
                                                   .emptyBay]
    private static let hanziLetter: [ActivityKind] = [.tapLetterAll, .tapLetterWrite, .tapHanziAll, .tapHanziWrite]
    private static let lineMatchFamily: [ActivityKind] = [.lineMatch, .lineMatchGuidedStraight, .lineMatchGuidedBridge,
                                                          .traceLines, .traceShapesDotted, .traceShapesArrows,
                                                          .traceShapesFree, .tapCountAll, .tapCountTrace, .tapCountPick,
                                                          .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish]

    /// `StatusRoute(mode:…)` with nothing else switched on by default.
    private static func shown(_ mode: Mode, providerBlocked: Bool = false, timesUp: Bool = false,
                              taskRoundOpen: Bool = false, unavailable: Bool = false, kind: ActivityKind? = nil,
                              play: PlayStageRoute = .videoPicker) -> StatusRoute? {
        StatusRoute(mode: mode, providerBlocked: providerBlocked, timesUp: timesUp, taskRoundOpen: taskRoundOpen,
                    letterTicketUnavailable: unavailable, boardKind: kind, playRoute: play)
    }

    private static func plan(_ route: StatusRoute?, _ kind: ActivityKind? = nil, pause: Int = 0) -> StatusChipPlan? {
        StatusChipPlan(route: route, activeKind: kind, thinkPauseRemaining: pause)
    }

    // MARK: Screen → route

    /// ShellView's screens in `childOrLegacy`'s branch order: parent controls (no child chip), provider blocked,
    /// Time's up, the lock screens, the play stage, then the setup shell.
    func testShellScreensMapToTheirChipRoutes() {
        let stages: [PlayStageRoute] = [.stamp, .emptyAllowlist, .resumeChoice, .videoPicker, .watch]
        // Parent controls win over every other flag: no child chip (C2 puts it in the parent bars, and a parent's 試玩
        // board is a parent screen).
        var parentCases = 0
        for blocked in [false, true] {
            for timesUp in [false, true] {
                for open in [false, true] {
                    for stage in stages {
                        expectNil(Self.shown(.parent, providerBlocked: blocked, timesUp: timesUp, taskRoundOpen: open,
                                             unavailable: !open, kind: .findTheSame, play: stage))
                        parentCases += 1
                    }
                }
            }
        }
        expectEqual(parentCases, 40)
        // Then provider blocked, then Time's up, in lock, play and setup alike.
        for mode in [Mode.lock, .play, .setup] {
            expectEqual(Self.shown(mode, providerBlocked: true, timesUp: true, taskRoundOpen: true, kind: .findTheSame,
                                   play: .watch), .providerBlocked, "\(mode)")
            expectEqual(Self.shown(mode, timesUp: true, taskRoundOpen: true, unavailable: true, kind: .findTheSame,
                                   play: .watch), .timesUp, "\(mode)")
        }
        // Lock without an open round: the letter-ticket screen, else the depot. The play stage is not read.
        expectEqual(Self.shown(.lock, unavailable: true, play: .watch), .letterUnavailable)
        expectEqual(Self.shown(.lock, play: .watch), .depot)
        expectEqual(Self.shown(.lock, kind: .tapLetterAll, play: .stamp), .depot)
        // Lock with an open round: the board's header family, even with the letter-ticket flag; nothing for a round
        // without a kind (the host draws an empty view).
        expectEqual(Self.shown(.lock, taskRoundOpen: true, unavailable: true, kind: .tapLetterAll), .hanziLetter)
        expectNil(Self.shown(.lock, taskRoundOpen: true))
        expectEqual(Self.boardTwo.count + Self.hanziLetter.count + Self.lineMatchFamily.count, ActivityKind.allCases.count)
        expectEqual(Set(Self.boardTwo + Self.hanziLetter + Self.lineMatchFamily), Set(ActivityKind.allCases))
        for (kinds, route) in [(Self.boardTwo, StatusRoute.boardTwo), (Self.hanziLetter, .hanziLetter),
                               (Self.lineMatchFamily, .lineMatchFamily)] {
            for kind in kinds {
                expectEqual(Self.shown(.lock, taskRoundOpen: true, kind: kind, play: .watch), route, "\(kind)")
            }
        }
        // Play: the play stage's own screen, whatever the round flags say.
        let play: [(PlayStageRoute, StatusRoute)] = [(.stamp, .stamp), (.emptyAllowlist, .emptyAllowlist),
                                                     (.resumeChoice, .resumeChoice), (.videoPicker, .videoPicker),
                                                     (.watch, .watch)]
        expectEqual(play.count, stages.count)
        for (stage, route) in play {
            expectEqual(Self.shown(.play, play: stage), route, "\(stage)")
            expectEqual(Self.shown(.play, taskRoundOpen: true, unavailable: true, kind: .lineMatch, play: stage), route,
                        "\(stage)")
        }
        // Setup: the legacy shell (D-C0c), whatever else is set.
        expectEqual(Self.shown(.setup), .setup)
        expectEqual(Self.shown(.setup, taskRoundOpen: true, unavailable: true, kind: .lineMatch, play: .watch), .setup)
    }

    // MARK: Slot and the hidden rule

    /// Where the chip goes (design §2.3, §9 C1, D-C0c, §9 C5): S on rows 1–3, 5–7, 9–11 and Setup, S_pick on the
    /// picker, the strip slot on Watch (C5), nothing on the LM family until C4, and nothing under parent controls.
    func testChipSitsAtItsSlotAndHidesOnLineMatch() {
        let expected: [(StatusRoute, LineMatchRect?)] = [
            (.depot, Self.s), (.boardTwo, Self.s), (.hanziLetter, Self.s), (.lineMatchFamily, nil), (.stamp, Self.s),
            (.timesUp, Self.s), (.resumeChoice, Self.s), (.videoPicker, Self.sPick), (.emptyAllowlist, Self.s),
            (.letterUnavailable, Self.s), (.providerBlocked, Self.s), (.watch, Self.watchStrip), (.setup, Self.s)
        ]
        expectEqual(expected.count, 13)
        expectEqual(Set(expected.map { $0.0 }), Set(StatusRoute.allCases))
        for (route, slot) in expected {
            let plan = Self.plan(route)
            let shownRoute: StatusRoute? = slot == nil ? nil : route
            expectEqual(plan?.slot, slot, "\(route)")
            expectEqual(plan?.route, shownRoute, "\(route)")
        }
        expectNil(Self.plan(nil, .findTheSame))
        // The hidden rule names exactly the routes without a slot, so C4 has to change both together (C5 took Watch
        // out of both).
        expectEqual(StatusChipPlan.hiddenRoutes, [.lineMatchFamily])
        for route in StatusRoute.allCases {
            expectEqual(StatusChipPlan.hiddenRoutes.contains(route), StatusSlot.rect(for: route) == nil, "\(route)")
        }
        // Through the shell: the 13 LM-family boards show no chip, every other board shows it at S.
        var hiddenBoards = 0
        for kind in ActivityKind.allCases {
            let lineMatch = Self.lineMatchFamily.contains(kind)
            expectEqual(Self.plan(Self.shown(.lock, taskRoundOpen: true, kind: kind), kind)?.slot,
                        lineMatch ? nil : Self.s, "\(kind)")
            if lineMatch { hiddenBoards += 1 }
        }
        expectEqual(hiddenBoards, 13)
        // Watch shows it in the strip above the player (C5), the picker moves it to S_pick, Time's up over a playing
        // video puts it at S, Setup shows it at S, and parent controls (with or without a 試玩 board) never show the
        // child chip.
        expectEqual(Self.plan(Self.shown(.play, play: .watch), .findTheSame)?.slot, Self.watchStrip)
        expectEqual(Self.plan(Self.shown(.play, play: .videoPicker))?.slot, Self.sPick)
        expectEqual(Self.plan(Self.shown(.play, timesUp: true, play: .watch))?.slot, Self.s)
        expectEqual(Self.plan(Self.shown(.setup))?.slot, Self.s)
        expectNil(Self.plan(Self.shown(.parent, taskRoundOpen: true, kind: .findTheSame), .findTheSame))
    }

    // MARK: Tone, language, Think Pause

    /// Night on the dusk boards only, the bottom row in the board's language (Q3), and the Think Pause dim (§2.7).
    func testToneLanguageAndThinkPauseDim() {
        let night: Set<StatusRoute> = [.timesUp, .resumeChoice, .watch]
        var nights = 0
        for route in StatusRoute.allCases {
            let tone = StatusChipTone(route: route)
            expectEqual(tone, night.contains(route) ? .night : .day, "\(route)")
            if tone == .night { nights += 1 }
        }
        expectEqual(nights, 3)
        expectEqual([Self.plan(.timesUp)?.tone, Self.plan(.resumeChoice)?.tone, Self.plan(.watch)?.tone,
                     Self.plan(.setup)?.tone, Self.plan(.depot)?.tone], [.night, .night, .night, .day, .day])
        // English: the Letters boards, the stamp after a Letters round and the English tap-count twins.
        let english: [(StatusRoute, ActivityKind)] = [
            (.hanziLetter, .tapLetterAll), (.hanziLetter, .tapLetterWrite), (.stamp, .tapLetterAll),
            (.stamp, .tapLetterWrite), (.lineMatchFamily, .tapCountAllEnglish), (.lineMatchFamily, .tapCountTraceEnglish),
            (.lineMatchFamily, .tapCountPickEnglish)
        ]
        for (route, kind) in english {
            expectEqual(StatusChipLanguage(route: route, activeKind: kind), .english, "\(route) \(kind)")
        }
        // Cantonese: the Hanzi boards, every other stamp (an English tap-count stamp is drawn in Cantonese by
        // `StampSuccessView`), the Cantonese LM boards, and every other screen whatever kind ran last.
        let cantonese: [(StatusRoute, ActivityKind?)] = [
            (.hanziLetter, .tapHanziAll), (.hanziLetter, .tapHanziWrite), (.hanziLetter, nil),
            (.stamp, .tapCountAllEnglish), (.stamp, .findTheSame), (.stamp, nil), (.lineMatchFamily, .tapCountAll),
            (.lineMatchFamily, .lineMatch), (.lineMatchFamily, nil)
        ]
        for (route, kind) in cantonese {
            expectEqual(StatusChipLanguage(route: route, activeKind: kind), .cantonese, "\(route) \(String(describing: kind))")
        }
        let otherScreens: [StatusRoute] = [.depot, .boardTwo, .timesUp, .resumeChoice, .videoPicker, .emptyAllowlist,
                                           .letterUnavailable, .providerBlocked, .watch, .setup]
        expectEqual(otherScreens.count + 3, StatusRoute.allCases.count)
        for route in otherScreens {
            for kind in [nil, ActivityKind.tapLetterAll, .tapLetterWrite, .tapCountPickEnglish, .findTheSame] {
                expectEqual(StatusChipLanguage(route: route, activeKind: kind), .cantonese, "\(route)")
            }
        }
        expectEqual(Self.plan(.hanziLetter, .tapLetterWrite)?.language, .english)
        expectEqual(Self.plan(.hanziLetter, .tapHanziWrite)?.language, .cantonese)
        let fiftyTwo = StatusChipText(zh: "52 分鐘", en: "52 min")
        expectEqual([fiftyTwo.text(in: .cantonese), fiftyTwo.text(in: .english)], ["52 分鐘", "52 min"])
        expectEqual([fiftyTwo.spoken(in: .cantonese), fiftyTwo.spoken(in: .english)], ["52 分鐘 / 52 min", "52 min"])
        // Think Pause: dimmed while seconds remain, to 45 %, faded over 0.2 s (no fade with Reduce Motion).
        for (seconds, dimmed) in [(0, false), (1, true), (5, true), (-1, false)] {
            expectEqual(Self.plan(.boardTwo, .findTheSame, pause: seconds)?.dimmed, dimmed, "\(seconds) s")
        }
        expectEqual([StatusChipStyle.thinkPauseOpacity, StatusChipStyle.thinkPauseFadeSeconds], [0.45, 0.2])
        // A plan changes only with something drawn (slot, tone, language, dim): a new question of the same family and
        // the pause's countdown seconds leave the layer alone.
        expectEqual(Self.plan(.boardTwo, .findTheSame), Self.plan(.boardTwo, .countVehicles))
        expectEqual(Self.plan(.boardTwo, .findTheSame, pause: 5), Self.plan(.boardTwo, .findTheSame, pause: 2))
        expectFalse(Self.plan(.boardTwo, .findTheSame) == Self.plan(.boardTwo, .findTheSame, pause: 3))
        expectFalse(Self.plan(.hanziLetter, .tapHanziAll) == Self.plan(.hanziLetter, .tapLetterAll))
    }

    /// Design §1.3 / §6: day and night tones, Increase Contrast and Reduce Transparency, with the WCAG contrast of the
    /// text and glyph against the chip's own fill.
    func testStyleForEachToneAndAccessibilitySetting() {
        let paper: UInt32 = 0xFFF6DF
        let ink: UInt32 = 0x3A2718
        let inkSoft: UInt32 = 0x5A4636
        expectEqual([DesignTokens.Palette.paper, DesignTokens.Palette.ink, DesignTokens.Palette.inkSoft],
                    [paper, ink, inkSoft])
        struct Row {
            let tone: StatusChipTone, contrast: Bool, transparency: Bool
            let colours: [UInt32]                  // fill, outline, text, glyph
            let numbers: [Double]                  // fill opacity, outline opacity, outline width (u)
        }
        let rows = [
            Row(tone: .day, contrast: false, transparency: false, colours: [paper, inkSoft, ink, inkSoft], numbers: [0.92, 1, 2]),
            Row(tone: .day, contrast: false, transparency: true, colours: [paper, inkSoft, ink, inkSoft], numbers: [1, 1, 2]),
            Row(tone: .day, contrast: true, transparency: false, colours: [paper, ink, ink, ink], numbers: [1, 1, 3]),
            Row(tone: .day, contrast: true, transparency: true, colours: [paper, ink, ink, ink], numbers: [1, 1, 3]),
            Row(tone: .night, contrast: false, transparency: false, colours: [ink, paper, paper, paper], numbers: [0.8, 0.35, 2]),
            Row(tone: .night, contrast: false, transparency: true, colours: [ink, paper, paper, paper], numbers: [1, 0.35, 2]),
            Row(tone: .night, contrast: true, transparency: false, colours: [ink, paper, paper, paper], numbers: [1, 1, 3]),
            Row(tone: .night, contrast: true, transparency: true, colours: [ink, paper, paper, paper], numbers: [1, 1, 3])
        ]
        for row in rows {
            let style = StatusChipStyle(tone: row.tone, increaseContrast: row.contrast, reduceTransparency: row.transparency)
            let label = "\(row.tone) contrast=\(row.contrast) transparency=\(row.transparency)"
            expectEqual([style.fill, style.outline, style.text, style.glyph], row.colours, label)
            expectEqual([style.fillOpacity, style.outlineOpacity, style.outlineWidth], row.numbers, label)
            // Text 13.1 : 1 in both tones, glyph ≥ 8 : 1; never the 5 u outline of pressable things.
            expectEqual(Self.contrast(style.text, style.fill), 13.1, accuracy: 0.05)
            expectTrue(Self.contrast(style.glyph, style.fill) >= 8, label)
            expectTrue(style.outlineWidth < DesignTokens.outlineWidth, label)
        }
        // §1.3's table: Ink on Paper 13.1 : 1, inkSoft on Paper 8.3 : 1 (8.25 by the WCAG 2 formula), Paper on Ink 13.1.
        expectEqual(Self.contrast(ink, paper), 13.15, accuracy: 0.01)
        expectEqual(Self.contrast(inkSoft, paper), 8.25, accuracy: 0.01)
        expectEqual(Self.contrast(paper, ink), 13.15, accuracy: 0.01)
    }

    // MARK: Words

    /// The chip's words: `h:mm` from the date, the elapsed row in the board's language from the uptimes only, and one
    /// accessibility label (Appendix A clock.a11y + chip.a11y, D-C0b), Traditional only.
    func testContentWordsAndAccessibilityLabel() throws {
        let at1545 = Self.utc("2026-11-10T07:45:00Z")
        let launch = 10_000.5
        func content(_ date: Date, _ seconds: Double, _ language: StatusChipLanguage) -> StatusChipContent {
            StatusChipContent(date: date, launchUptime: launch, nowUptime: launch + seconds, language: language)
        }
        // (seconds since launch, Cantonese row, English row)
        let rows: [(Double, String, String)] = [
            (0, "0 分鐘", "0 min"), (3_179, "52 分鐘", "52 min"), (3_900, "1 小時 5 分", "1 h 5 min"),
            (359_999, "99 小時 59 分", "99 h 59 min"), (360_000, "99+ 小時", "99+ h")
        ]
        for (seconds, zh, en) in rows {
            let cantonese = content(at1545, seconds, .cantonese)
            let english = content(at1545, seconds, .english)
            expectEqual([cantonese.clock, cantonese.elapsed, english.clock, english.elapsed], ["3:45", zh, "3:45", en])
            expectEqual(cantonese.accessibilityLabel,
                        "而家時間：下午3時45分。由開App計：\(zh) / Time now: 3:45 PM. Since app start: \(en)")
            expectEqual(english.accessibilityLabel, "Time now: 3:45 PM. Since app start: \(en)")
        }
        // Verbatim, as a screen reader gets it.
        expectEqual(content(at1545, 3_120, .cantonese).accessibilityLabel,
                    "而家時間：下午3時45分。由開App計：52 分鐘 / Time now: 3:45 PM. Since app start: 52 min")
        expectEqual(content(Self.utc("2026-11-09T16:05:00Z"), 3_900, .english).accessibilityLabel,
                    "Time now: 12:05 AM. Since app start: 1 h 5 min")
        expectEqual(StatusChipCopy.chipAccessibility(clock: StatusChipText(zh: "而家時間：下午3時45分", en: "Time now: 3:45 PM"),
                                                     elapsed: StatusChipText(zh: "由開App計：52 分鐘",
                                                                             en: "Since app start: 52 min")),
                    StatusChipText(zh: "而家時間：下午3時45分。由開App計：52 分鐘", en: "Time now: 3:45 PM. Since app start: 52 min"))
        // The top row reads only the date and the bottom row only the uptimes: any wall clock leaves 52 min at 52 min,
        // and any uptimes leave 3:45 at 3:45.
        for date in [at1545, Date(timeIntervalSince1970: 0), at1545.addingTimeInterval(-86_400 * 365), Date.distantFuture] {
            expectEqual(content(date, 3_120, .cantonese).elapsed, "52 分鐘")
            expectEqual(content(date, 3_120, .english).elapsed, "52 min")
        }
        let uptimePairs: [(Double, Double)] = [(0, 5), (1_000, 999), (5, 1e9), (.nan, 1)]
        for (launchUptime, nowUptime) in uptimePairs {
            expectEqual(StatusChipContent(date: at1545, launchUptime: launchUptime, nowUptime: nowUptime,
                                          language: .english).clock, "3:45")
        }
        // Every bottom-row minute to past 100 h and every clock minute of a day, both board languages: Traditional
        // only (the OpenCC fixture and both lists), English boards ASCII, no unfilled placeholder.
        let simplified = try Self.simplifiedOnly()
        expectTrue(Array("开计钟时间").allSatisfy { simplified.contains($0) })
        var cantoneseTexts: [String] = []
        var englishTexts: [String] = []
        for minute in 0...6_001 {
            let zh = content(at1545, Double(minute) * 60, .cantonese)
            let en = content(at1545, Double(minute) * 60, .english)
            cantoneseTexts += [zh.elapsed, zh.accessibilityLabel]
            englishTexts += [en.elapsed, en.accessibilityLabel]
        }
        let midnight = Self.utc("2026-11-09T16:00:00Z")
        for minute in 0..<1_440 {
            let date = midnight.addingTimeInterval(Double(minute * 60))
            let zh = content(date, 3_120, .cantonese)
            let en = content(date, 3_120, .english)
            cantoneseTexts += [zh.clock, zh.accessibilityLabel]
            englishTexts += [en.clock, en.accessibilityLabel]
        }
        for text in cantoneseTexts + englishTexts {
            expectFalse(text.contains { simplified.contains($0) }, "Simplified character in \(text)")
            expectTrue(isTraditionalChineseOnly(text) && perfTraditionalOnly(text), text)
            expectFalse(text.contains("{") || text.contains("}"), "unfilled placeholder in \(text)")
        }
        for text in englishTexts { expectTrue(text.allSatisfy(\.isASCII), "English board: \(text)") }
        expectEqual(cantoneseTexts.count + englishTexts.count, 4 * (6_002 + 1_440))
        for name in ["Sources/VisaCore/StatusChip.swift", "Sources/VisaGames/StatusClockLayer.swift"] {
            let source = try Self.text(name)
            expectFalse(source.contains { simplified.contains($0) }, "\(name) has a Simplified character")
            expectTrue(isTraditionalChineseOnly(source) && perfTraditionalOnly(source), name)
        }
    }

    // MARK: Refresh

    /// The coarse tick: the start, then each wall minute and 1 s after each minute since launch; at most two redraws
    /// in a wall minute; the top row never stale and the bottom row at most 1 s stale when drawn the way a timeline
    /// draws (the latest entry at or before the instant). Nothing scheduled past `99+` or from broken uptimes.
    func testRefreshLandsOnEachRowsNextMinute() {
        let launch = 50_000.0
        func entries(_ start: String, sinceLaunch: Double, count: Int) -> [Date] {
            var refresh = StatusChipRefresh(start: Self.utc("2026-11-10T\(start)Z"), uptimeAtStart: launch + sinceLaunch,
                                            launchUptime: launch)
            return (0..<count).compactMap { _ in refresh.next() }
        }
        func times(_ list: [String]) -> [Date] { list.map { Self.utc("2026-11-10T\($0)Z") } }
        expectEqual(StatusChipRefresh.elapsedGrace, 1)
        // 52 min 5 s since launch at 15:45:20 HKT: wall minutes at :00, the bottom row at :15 + 1 s.
        expectEqual(entries("07:45:20", sinceLaunch: 3_125, count: 7),
                    times(["07:45:20", "07:46:00", "07:46:16", "07:47:00", "07:47:16", "07:48:00", "07:48:16"]))
        // Both rows due at the same instant: one redraw.
        expectEqual(entries("07:45:20", sinceLaunch: 3_141, count: 4), times(["07:45:20", "07:46:00", "07:47:00", "07:48:00"]))
        // Starting on both boundaries: the next ones, never the start again.
        expectEqual(entries("07:45:00", sinceLaunch: 3_120, count: 4), times(["07:45:00", "07:46:00", "07:46:01", "07:47:00"]))
        // The bottom row's last change is `99+` at 100 h; the wall minutes go on.
        expectEqual(entries("07:45:20", sinceLaunch: 359_970, count: 5),
                    times(["07:45:20", "07:45:51", "07:46:00", "07:47:00", "07:48:00"]))
        expectEqual(entries("07:45:20", sinceLaunch: 360_000, count: 3), times(["07:45:20", "07:46:00", "07:47:00"]))
        // Unusable uptimes (backwards, not finite): wall minutes only.
        let brokenUptimes: [Double] = [-30, .nan, .infinity, -.infinity]
        for broken in brokenUptimes {
            expectEqual(entries("07:45:20", sinceLaunch: broken, count: 3), times(["07:45:20", "07:46:00", "07:47:00"]))
        }
        // A start that is not a real instant: the start, then the end (a timeline never spins on it).
        var odd = StatusChipRefresh(start: Date(timeIntervalSinceReferenceDate: .infinity), uptimeAtStart: launch,
                                    launchUptime: launch)
        expectEqual(odd.next(), Date(timeIntervalSinceReferenceDate: .infinity))
        expectNil(odd.next())
        // A valid start never ends.
        var long = StatusChipRefresh(start: Self.utc("2026-11-10T07:45:20Z"), uptimeAtStart: launch, launchUptime: launch)
        expectEqual((0..<20_000).compactMap { _ in long.next() }.count, 20_000)
        // An hour drawn as a timeline draws it (the latest entry at or before the instant), every 0.25 s, from three
        // starts: mid-minute, across Hong Kong midnight just before the first minute since launch, and on both
        // boundaries at launch.
        for (start, sinceLaunch) in [("2026-11-10T07:45:20Z", 3_125.0), ("2026-11-10T15:59:59.600Z", 59.7),
                                     ("2026-11-10T03:00:00Z", 0)] {
            let begin = Self.utc(start)
            let uptimeAtStart = launch + sinceLaunch
            var refresh = StatusChipRefresh(start: begin, uptimeAtStart: uptimeAtStart, launchUptime: launch)
            var list: [Date] = []
            while let next = refresh.next(), next.timeIntervalSince(begin) <= 3_600 { list.append(next) }
            expectEqual(list.first, begin)
            var perMinute: [Int: Int] = [:]
            for (a, b) in zip(list, list.dropFirst()) {
                expectTrue(b > a && b.timeIntervalSince(a) <= 60, "\(start): \(a) → \(b)")
                perMinute[Int((b.timeIntervalSinceReferenceDate / 60).rounded(.down)), default: 0] += 1
            }
            expectTrue(perMinute.values.allSatisfy { $0 <= 2 }, "\(start): at most two redraws a wall minute")
            expectTrue(list.count >= 61 && list.count <= 2 * 61, "\(start): \(list.count) entries")
            // What the layer draws at an entry, against the truth at any instant (C0's clock and elapsed types).
            func drawn(_ entry: Date) -> StatusChipContent {
                StatusChipContent(date: entry, launchUptime: launch,
                                  nowUptime: uptimeAtStart + entry.timeIntervalSince(begin), language: .cantonese)
            }
            func elapsedTruth(_ instant: Date) -> String {
                ElapsedSinceLaunch(launchUptime: launch, nowUptime: uptimeAtStart + instant.timeIntervalSince(begin)).text.zh
            }
            var index = 0
            var shown = drawn(list[0])
            var stale = 0
            for step in 0...(3_600 * 4) {
                let instant = begin.addingTimeInterval(Double(step) / 4)
                while index + 1 < list.count, list[index + 1] <= instant {
                    index += 1
                    shown = drawn(list[index])
                }
                if shown.clock != StatusClockText.clock(instant) {
                    expectTrue(false, "\(start) + \(Double(step) / 4) s: the clock shows \(shown.clock)")
                }
                if shown.elapsed != elapsedTruth(instant) {
                    stale += 1
                    if shown.elapsed != elapsedTruth(instant.addingTimeInterval(-StatusChipRefresh.elapsedGrace)) {
                        expectTrue(false, "\(start) + \(Double(step) / 4) s: \(shown.elapsed) is over 1 s stale")
                    }
                }
            }
            expectTrue(stale <= 61 * 4, "\(start): \(stale) stale samples")
        }
    }

    // MARK: Inside the chip

    /// compare.md FINAL v1 §5: padding 6, corner 10, glyph Ø 12 at x 6–18 centred at y 13.5, `3:45` 16 u bold from
    /// x 22 on baseline 18.5, the elapsed row 11.5 u semibold from x 6 on baseline 33.5; the R2 mockup's glyph.
    func testChipInsideFollowsTheR2Spec() {
        expectEqual([StatusChipLayout.padding, StatusChipLayout.cornerRadius], [6, 10])
        expectEqual(StatusChipLayout.glyph, LineMatchRect(x: 6, y: 7.5, width: 12, height: 12))
        expectEqual([StatusChipLayout.glyph.maxX, StatusChipLayout.glyph.midY], [18, 13.5])
        expectEqual([StatusChipLayout.clockX, StatusChipLayout.clockBaseline, StatusChipLayout.clockSize], [22, 18.5, 16])
        expectEqual([StatusChipLayout.elapsedX, StatusChipLayout.elapsedBaseline, StatusChipLayout.elapsedSize],
                    [6, 33.5, 11.5])
        expectEqual([StatusChipLayout.clockWeight, StatusChipLayout.elapsedWeight], [700, 600])
        // The glyph is 0.75 em of the top row, the clock starts a quarter em after it, and both rows start on the
        // padding line.
        expectEqual(StatusChipLayout.glyph.width, 0.75 * StatusChipLayout.clockSize)
        expectEqual(StatusChipLayout.glyph.maxX + 0.25 * StatusChipLayout.clockSize, StatusChipLayout.clockX)
        expectEqual([StatusChipLayout.glyph.x, StatusChipLayout.elapsedX], [StatusChipLayout.padding, StatusChipLayout.padding])
        // Measured ink (compare.md §5): 16 u digits rise up to 12.1 u, 11.5 u Han runs −9.7 / +1.0 u. Both rows stay
        // inside the 84 × 40 chip with the quoted 5.5 u bottom pad.
        expectTrue(StatusChipLayout.clockBaseline - 12.1 >= 0)
        expectEqual(StatusSlot.chipHeight - (StatusChipLayout.elapsedBaseline + 1.0), 5.5)
        expectTrue(StatusChipLayout.elapsedBaseline - 9.7 > StatusChipLayout.clockBaseline)
        // The glyph (radius 6): face 5.16, line 1.56, minute hand 3.3 up, hour hand 2.52 across; its stroke stays in
        // the 12 u box.
        let radius = StatusChipLayout.glyph.width / 2
        expectEqual(StatusChipLayout.glyphFace * radius, 5.16, accuracy: 1e-9)
        expectEqual(StatusChipLayout.glyphLine * radius, 1.56, accuracy: 1e-9)
        expectEqual(StatusChipLayout.glyphMinuteHand * radius, 3.3, accuracy: 1e-9)
        expectEqual(StatusChipLayout.glyphHourHand * radius, 2.52, accuracy: 1e-9)
        expectTrue((StatusChipLayout.glyphFace + StatusChipLayout.glyphLine / 2) * radius <= radius)
        // Corner and padding fit the 84 × 40 chip.
        expectTrue(2 * StatusChipLayout.cornerRadius < StatusSlot.chipHeight)
        expectEqual([StatusSlot.chipWidth, StatusSlot.chipHeight], [84, 40])
    }

    // MARK: App wiring (source guards; SwiftUI / AppKit are not compiled on this box)

    /// ShellView puts the layer above the content and below the parent corner and pen spark, from the same inputs and
    /// branch order as `StatusRoute(mode:…)`; AppModel reads the launch uptime once; the layer is never hittable,
    /// focusable or timed by a timer, reads the date only for the clock, and honours the accessibility settings.
    func testShellWiresTheNonHittableLayer() throws {
        let app = try Self.text("Sources/VisaGames/AppDelegate.swift")
        guard let shellStart = app.range(of: "struct ShellView: View {"),
              let branchStart = app.range(of: "private var childOrLegacy: some View {",
                                          range: shellStart.upperBound..<app.endIndex),
              let playStart = app.range(of: "private func playCanvasBoard(", range: branchStart.upperBound..<app.endIndex),
              let playEnd = app.range(of: "private var parentNotice: some View {", range: playStart.upperBound..<app.endIndex),
              let modelStart = app.range(of: "final class AppModel: ObservableObject {"),
              let modelInit = app.range(of: "\n    init() {", range: modelStart.upperBound..<app.endIndex) else {
            expectTrue(false, "ShellView / AppModel not found")
            return
        }
        let shell = Self.codeOnly(String(app[shellStart.upperBound..<branchStart.lowerBound]))
        let branches = Self.codeOnly(String(app[branchStart.upperBound..<playStart.lowerBound]))
        let stages = Self.codeOnly(String(app[playStart.upperBound..<playEnd.lowerBound]))
        // ZStack order (design §2.1): content, chip, parent corner, pen spark.
        guard let stack = shell.range(of: "return ZStack {") else {
            expectTrue(false, "ShellView ZStack not found")
            return
        }
        expectTrue(Self.inOrder(shell[stack.upperBound...], [
            "childOrLegacy", "if let statusChip {",
            "StatusClockLayer(plan: statusChip, launchUptime: model.launchUptime)", ".equatable()", ".ignoresSafeArea()",
            "if showsParentCorner {", "ParentCornerLayer(", "if childMode {", "PenSparkOverlay("
        ]), "ShellView ZStack order")
        // The plan's inputs are the ones `childOrLegacy` branches on.
        for needle in ["let statusChip = statusChipPlan",
                       "StatusRoute(mode: model.session.mode, providerBlocked: model.showProviderBlocked,",
                       "timesUp: model.showTimesUp, taskRoundOpen: model.taskRoundOpen,",
                       "letterTicketUnavailable: model.unavailableLetterTicket,",
                       "boardKind: model.activeActivityKind, playRoute: playRoute)",
                       "activeKind: model.activeActivityKind,",
                       "thinkPauseRemaining: model.thinkPauseRemainingSeconds"] {
            expectTrue(shell.contains(needle), "ShellView: \(needle)")
        }
        expectEqual(shell.components(separatedBy: "StatusClockLayer(").count, 2, "one chip layer")
        // `childOrLegacy` keeps the order `StatusRoute(mode:…)` mirrors, and the play stage its five screens (the stamp
        // English-only after a Letters round, as `StatusChipLanguage` assumes).
        expectTrue(Self.inOrder(Substring(branches), [
            "if model.session.mode == .parent {", "} else if model.showProviderBlocked {", "} else if model.showTimesUp {",
            "} else if model.session.mode == .lock && !model.taskRoundOpen && model.unavailableLetterTicket {",
            "} else if model.session.mode == .lock && !model.taskRoundOpen {",
            "} else if model.session.mode == .lock && model.taskRoundOpen {", "} else if model.session.mode == .play {",
            "} else {", "legacyShell"
        ]), "childOrLegacy branch order")
        expectTrue(Self.inOrder(Substring(stages), [
            "case .stamp:", "StampSuccessView(", "englishOnly: model.activeActivityKind?.isTapLetterFamily == true",
            "case .emptyAllowlist:", "EmptyAllowlistView(", "case .resumeChoice:", "ResumeChoiceView(",
            "case .videoPicker:", "VideoPickerView(", "case .watch:", "WatchPlaybackView("
        ]), "playCanvasBoard order")
        // AppModel reads the launch uptime once, as a constant, before anything else can run.
        let model = Self.codeOnly(String(app[modelStart.upperBound..<modelInit.lowerBound]))
        expectTrue(model.contains("\n    let launchUptime = ProcessInfo.processInfo.systemUptime\n"), "AppModel.launchUptime")
        expectEqual(Self.codeOnly(app).components(separatedBy: "launchUptime =").count, 2, "launchUptime is set once")
        expectTrue(app.contains("    private let model = AppModel()\n"), "one AppModel, built with the delegate")
        // The layer.
        let layer = Self.codeOnly(try Self.text("Sources/VisaGames/StatusClockLayer.swift"))
        for needle in [
            "struct StatusClockLayer: View, Equatable {",
            "nonisolated static func == (lhs: StatusClockLayer, rhs: StatusClockLayer) -> Bool {",
            "lhs.plan == rhs.plan && lhs.launchUptime == rhs.launchUptime",
            "plan.screenRect(screenWidth: width, screenHeight: height)",
            "TimelineView(StatusChipSchedule(launchUptime: launchUptime)) { context in",
            "StatusChipContent(date: context.date, launchUptime: launchUptime,",
            "nowUptime: ProcessInfo.processInfo.systemUptime,",
            "func entries(from startDate: Date, mode: TimelineScheduleMode) -> StatusChipRefresh {",
            "StatusChipRefresh(start: startDate, uptimeAtStart: ProcessInfo.processInfo.systemUptime,",
            ".opacity(plan.dimmed ? StatusChipStyle.thinkPauseOpacity : 1)",
            ".animation(reduceMotion ? nil : .easeInOut(duration: StatusChipStyle.thinkPauseFadeSeconds), value: plan.dimmed)",
            "@Environment(\\.accessibilityReduceMotion)", "@Environment(\\.colorSchemeContrast)",
            "@Environment(\\.accessibilityReduceTransparency)",
            "StatusChipStyle(tone: tone, increaseContrast: contrast == .increased,",
            ".accessibilityElement(children: .ignore)", ".accessibilityLabel(content.accessibilityLabel)",
            ".accessibilityAddTraits(.isStaticText)",
            ".monospacedDigit()", ".lineLimit(1)", ".fixedSize()", ".alignmentGuide(.top) { $0[.firstTextBaseline] }"
        ] {
            expectTrue(layer.contains(needle), "StatusClockLayer: \(needle)")
        }
        // Not hittable, once, on the whole layer (after its geometry reader).
        expectEqual(layer.components(separatedBy: ".allowsHitTesting(").count, 2)
        expectTrue(Self.inOrder(Substring(layer), ["GeometryReader { proxy in", ".allowsHitTesting(false)",
                                                   "private struct StatusChipView"]), "allowsHitTesting(false) on the layer")
        // Nothing to press, focus, time or store; no shrinking or truncating; no `Date()` and no `model.now`.
        for banned in ["Button", "Gesture", "onTap", "focusable", "contentShape", "Timer", "Date()", ".now", "model.",
                       "minimumScaleFactor", "truncationMode", "UserDefaults", "FileManager", "write(", "onReceive",
                       "DispatchQueue", "accessibilityHidden", "Calendar", "TimeZone"] {
            expectFalse(layer.contains(banned), "StatusClockLayer must not use \(banned)")
        }
        // VisaCore's chip code reads no clock and stores nothing; the elapsed words come from the two uptimes.
        let core = Self.codeOnly(try Self.text("Sources/VisaCore/StatusChip.swift"))
        for banned in ["Date()", "ProcessInfo", "systemUptime", "TimeZone", "Calendar", "Timer", "UserDefaults",
                       "FileManager", "DispatchQueue", ".now"] {
            expectFalse(core.contains(banned), "StatusChip.swift must not use \(banned)")
        }
        expectTrue(core.contains("let since = ElapsedSinceLaunch(launchUptime: launchUptime, nowUptime: nowUptime)"))
        // Setup (D-C0c): the chip sits over the left part of the decorative sun (1920 × 1080: sun x 1744–1884,
        // y 28–168 pt; chip x 1702.5–1815.9, y 62.1–116.1), which takes no touch and no screen reader focus.
        let theme = Self.codeOnly(try Self.text("Sources/VisaGames/ThemeViews.swift"))
        guard let sunStart = theme.range(of: "struct SoftSunRoadAccent: View {"),
              let sunEnd = theme.range(of: "struct VehicleParade", range: sunStart.upperBound..<theme.endIndex) else {
            expectTrue(false, "SoftSunRoadAccent not found")
            return
        }
        expectTrue(Self.inOrder(theme[sunStart.upperBound..<sunEnd.lowerBound], [
            "ZStack(alignment: .topTrailing) {", ".frame(width: 140, height: 140)", ".offset(x: -36, y: 28)",
            ".allowsHitTesting(false)", ".accessibilityHidden(true)"
        ]), "SoftSunRoadAccent")
        expectTrue(Self.codeOnly(app).contains("SoftSunRoadAccent(yellow: yellow, accent: accent)"))
    }

    // MARK: Helpers

    /// WCAG 2 contrast ratio of two sRGB colours.
    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            let rgb = DesignTokens.rgb(hex)
            func linear(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// Each needle found after the previous one.
    private static func inOrder(_ text: Substring, _ needles: [String]) -> Bool {
        var cursor = text.startIndex
        for needle in needles {
            guard let found = text.range(of: needle, range: cursor..<text.endIndex) else { return false }
            cursor = found.upperBound
        }
        return true
    }

    /// The repository root: three folders above this file, or the working directory (`scripts/test.sh` runs there).
    private static func text(_ path: String) throws -> String {
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = FileManager.default.fileExists(atPath: beside.appendingPathComponent("Package.swift").path)
            ? beside : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// `text` without its `//` and `///` comments, so a source guard reads code, not prose.
    private static func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            guard let comment = line.range(of: "//") else { return line }
            return line[..<comment.lowerBound]
        }.joined(separator: "\n")
    }

    /// `Fixtures/traditional-check/simplified-only.txt`: one character per entry, `#` lines are comments.
    private static func simplifiedOnly() throws -> Set<Character> {
        let text = try Self.text("Tests/VisaCoreTests/Fixtures/traditional-check/simplified-only.txt")
        var characters: Set<Character> = []
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            for character in line where !character.isWhitespace { characters.insert(character) }
        }
        return characters
    }
}
