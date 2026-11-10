import Foundation
import VisaCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Clock + elapsed chip C0 (0.39.0 / 85): clock-playtime design §7.1 L1, L2, L3 and L-E at the R2 84 × 40 u size
/// (Locked decision 1, Carter 2026-11-10; chip-rows/compare.md FINAL v1 §4–§5) and its Appendix A copy. Expected
/// strings and numbers are the design's own, written out here, never recomputed with the code under test.
final class StatusClockTests {
    /// An instant written in UTC, so its Hong Kong time is plain arithmetic: HKT = UTC + 8 all year.
    private static func utc(_ stamp: String) -> Date { PerfCodec.parseTimestamp(stamp)! }

    // MARK: L1 clock

    /// L1: 12-hour `h:mm`, no AM/PM, no seconds, Hong Kong; the 24-hour alternative.
    func testClockIsTwelveHourHongKongWithoutSeconds() {
        // (UTC instant, chip, 24-hour)
        let cases: [(String, String, String)] = [
            ("2026-11-09T16:05:00Z", "12:05", "00:05"),
            ("2026-11-10T04:00:00Z", "12:00", "12:00"),
            ("2026-11-10T07:45:00Z", "3:45", "15:45"),
            ("2026-11-10T01:07:00Z", "9:07", "09:07"),
            ("2026-11-10T04:55:00Z", "12:55", "12:55"),
            ("2026-11-10T03:59:59.999Z", "11:59", "11:59"),
            ("2026-11-10T05:00:00Z", "1:00", "13:00"),
            ("2026-11-10T07:45:59.999Z", "3:45", "15:45"),
            ("2026-11-10T15:59:59Z", "11:59", "23:59"),
            ("2026-11-10T16:00:00Z", "12:00", "00:00")
        ]
        for (stamp, chip, twentyFour) in cases {
            expectEqual(StatusClockText.clock(Self.utc(stamp)), chip, stamp)
            expectEqual(StatusClockText.clock24(Self.utc(stamp)), twentyFour, stamp)
        }
        // Every minute of a Hong Kong day: 12, 1 … 11 twice over, the minute always two digits.
        let midnight = Self.utc("2026-11-09T16:00:00Z")
        var readings: [String] = []
        for minute in 0..<1440 {
            let text = StatusClockText.clock(midnight.addingTimeInterval(Double(minute * 60)))
            let hour = minute / 60 % 12 == 0 ? 12 : minute / 60 % 12
            expectEqual(text, "\(hour):\(minute % 60 < 10 ? "0" : "")\(minute % 60)")
            readings.append(text)
        }
        expectEqual([readings[0], readings[59], readings[60], readings[719], readings[720], readings[1439]],
                    ["12:00", "12:59", "1:00", "11:59", "12:00", "11:59"])
        expectEqual(Set(readings).count, 720)
        expectEqual(readings.map(\.count).max(), 5)
    }

    /// L1: the output stays Hong Kong when the process's own zone is UTC, New York or Kolkata (a half-hour zone,
    /// so even the minutes would move); the source never asks the host for a zone, calendar or locale.
    func testClockStaysHongKongWhateverTheProcessZone() throws {
        let instants = ["2026-11-10T07:45:00Z", "2026-11-09T16:05:00Z", "2026-11-10T04:00:00Z"].map(Self.utc)
        let processZone = TimeZone.current.identifier
        // Each zone's offset on 2026-11-10 (New York is on EST again from 1 November): proof the process zone moved.
        let zones: [(String, Int)] = [("UTC", 0), ("America/New_York", -18_000), ("Asia/Kolkata", 19_800)]
        for (identifier, offset) in zones {
            withProcessTimeZone(identifier) {
                expectEqual(TimeZone.current.secondsFromGMT(for: instants[0]), offset, identifier)
                expectEqual(instants.map(StatusClockText.clock), ["3:45", "12:05", "12:00"], identifier)
                expectEqual(instants.map(StatusClockText.clock24), ["15:45", "00:05", "12:00"], identifier)
                expectEqual(StatusClockText.accessibility(instants[0]).bilingual,
                            "而家時間：下午3時45分 / Time now: 3:45 PM", identifier)
            }
        }
        expectEqual(TimeZone.current.identifier, processZone, "the process zone is restored")
        let code = Self.codeOnly(try Self.text("Sources/VisaCore/StatusClock.swift"))
        for banned in ["TimeZone.current", "autoupdatingCurrent", "Locale", "Calendar.current", "NSTimeZone",
                       "DateFormatter", "String(format:"] {
            expectFalse(code.contains(banned), "StatusClock.swift must not use \(banned)")
        }
        expectTrue(code.contains("PerfClock.calendar(PerfClock.hongKong)"), "the stats files' Hong Kong zone")
    }

    /// L1: the spoken time carries the period in both languages (Appendix A clock.a11y, design §6).
    func testClockSpeaksItsPeriodInBothLanguages() {
        let cases: [(String, String, String)] = [
            ("2026-11-10T07:45:00Z", "而家時間：下午3時45分", "Time now: 3:45 PM"),
            ("2026-11-09T16:05:00Z", "而家時間：上午12時05分", "Time now: 12:05 AM"),
            ("2026-11-10T04:00:00Z", "而家時間：下午12時00分", "Time now: 12:00 PM"),
            ("2026-11-10T01:07:00Z", "而家時間：上午9時07分", "Time now: 9:07 AM"),
            ("2026-11-10T03:59:59Z", "而家時間：上午11時59分", "Time now: 11:59 AM"),
            ("2026-11-10T15:59:00Z", "而家時間：下午11時59分", "Time now: 11:59 PM")
        ]
        for (stamp, zh, en) in cases {
            expectEqual(StatusClockText.accessibility(Self.utc(stamp)), StatusChipText(zh: zh, en: en), stamp)
        }
        expectEqual(StatusClockText.accessibility(Self.utc("2026-11-10T07:45:00Z")).bilingual,
                    "而家時間：下午3時45分 / Time now: 3:45 PM")
        expectEqual(StatusChipCopy.hongKongTime, StatusChipText(zh: "香港時間", en: "HK time"))
    }

    // MARK: L-E elapsed since launch

    /// L-E: floored whole minutes from two uptimes, in the Cantonese and the English (ABC) board formats.
    func testElapsedFloorsWholeMinutesOnBothBoards() {
        let launch = 86_400.5
        // (seconds since launch, minutes, Cantonese board, ABC board)
        let cases: [(Double, Int, String, String)] = [
            (0, 0, "0 分鐘", "0 min"),
            (59, 0, "0 分鐘", "0 min"),
            (59.75, 0, "0 分鐘", "0 min"),
            (60, 1, "1 分鐘", "1 min"),
            (119.5, 1, "1 分鐘", "1 min"),
            (3_179, 52, "52 分鐘", "52 min"),
            (3_540, 59, "59 分鐘", "59 min"),
            (3_599.75, 59, "59 分鐘", "59 min"),
            (3_600, 60, "1 小時 0 分", "1 h 0 min"),
            (3_900, 65, "1 小時 5 分", "1 h 5 min"),
            (39_540, 659, "10 小時 59 分", "10 h 59 min"),
            (359_940, 5_999, "99 小時 59 分", "99 h 59 min"),
            (359_999.75, 5_999, "99 小時 59 分", "99 h 59 min"),
            (360_000, 6_000, "99+ 小時", "99+ h"),
            (3_600_000, 60_000, "99+ 小時", "99+ h")
        ]
        for (seconds, minutes, zh, en) in cases {
            let elapsed = ElapsedSinceLaunch(launchUptime: launch, nowUptime: launch + seconds)
            expectEqual(elapsed.minutes, minutes, "\(seconds) s")
            expectEqual(elapsed.text, StatusChipText(zh: zh, en: en), "\(seconds) s")
        }
        // Accessibility (chip.a11y) and the parent bar caption (bar.sinceStart) carry the chip's own figure.
        let at = { (seconds: Double) in ElapsedSinceLaunch(launchUptime: launch, nowUptime: launch + seconds) }
        expectEqual(at(3_120).accessibility, StatusChipText(zh: "由開App計：52 分鐘", en: "Since app start: 52 min"))
        expectEqual(at(3_120).accessibility.bilingual, "由開App計：52 分鐘 / Since app start: 52 min")
        expectEqual(at(3_120).parentCaption, StatusChipText(zh: "由開App計 52 分鐘", en: "52 min since app start"))
        expectEqual(at(3_900).accessibility, StatusChipText(zh: "由開App計：1 小時 5 分", en: "Since app start: 1 h 5 min"))
        expectEqual(at(3_900).parentCaption, StatusChipText(zh: "由開App計 1 小時 5 分", en: "1 h 5 min since app start"))
        expectEqual(at(360_000).accessibility, StatusChipText(zh: "由開App計：99+ 小時", en: "Since app start: 99+ h"))
        // Every minute to past the cap, half a minute in: the minute it is in, and only the seven shapes the fixed
        // chip is budgeted for, the widest `99 小時 59 分` / `99 h 59 min` (compare.md §2, §5).
        var zhShapes = Set<String>()
        var enShapes = Set<String>()
        for minute in 0...6_001 {
            let elapsed = at(Double(minute) * 60 + 30)
            expectEqual(elapsed.minutes, minute)
            zhShapes.insert(String(elapsed.text.zh.map { $0.isASCII && $0.isNumber ? "0" : $0 }))
            enShapes.insert(String(elapsed.text.en.map { $0.isASCII && $0.isNumber ? "0" : $0 }))
        }
        expectEqual(zhShapes, ["0 分鐘", "00 分鐘", "0 小時 0 分", "0 小時 00 分", "00 小時 0 分", "00 小時 00 分", "00+ 小時"])
        expectEqual(enShapes, ["0 min", "00 min", "0 h 0 min", "0 h 00 min", "00 h 0 min", "00 h 00 min", "00+ h"])
        expectEqual(ElapsedSinceLaunch.overflowMinutes, 6_000)
    }

    /// L-E: monotonic only. A backwards or broken uptime shows 0, never a negative or a trap; the process zone changes
    /// nothing; and the type's code reads no clock at all (it takes two uptimes, no `Date`).
    func testElapsedReadsOnlyTheTwoUptimes() throws {
        let broken: [(Double, Double)] = [(500, 499), (500, 0), (500, -60), (.nan, 600), (500, .nan), (500, .infinity),
                                          (-.infinity, 500)]
        for (launch, now) in broken {
            let elapsed = ElapsedSinceLaunch(launchUptime: launch, nowUptime: now)
            expectEqual(elapsed.minutes, 0, "\(launch) → \(now)")
            expectEqual(elapsed.text, StatusChipText(zh: "0 分鐘", en: "0 min"))
        }
        expectEqual(ElapsedSinceLaunch(launchUptime: 0, nowUptime: 1e300).text, StatusChipText(zh: "99+ 小時", en: "99+ h"))
        // The same two uptimes give the same figure whatever the process zone.
        let fiftyTwo = ElapsedSinceLaunch(launchUptime: 1_000, nowUptime: 4_120)
        for identifier in ["UTC", "America/New_York", "Asia/Kolkata"] {
            withProcessTimeZone(identifier) {
                expectEqual(ElapsedSinceLaunch(launchUptime: 1_000, nowUptime: 4_120), fiftyTwo, identifier)
                expectEqual(fiftyTwo.text.zh, "52 分鐘", identifier)
            }
        }
        let code = Self.codeOnly(try Self.text("Sources/VisaCore/StatusClock.swift"))
        guard let start = code.range(of: "public struct ElapsedSinceLaunch"),
              let end = code.range(of: "\n}", range: start.upperBound..<code.endIndex) else {
            expectTrue(false, "ElapsedSinceLaunch not found")
            return
        }
        let body = code[start.lowerBound..<end.upperBound]
        for banned in ["Date", "Calendar", "TimeZone", "ProcessInfo", "systemUptime", "Clock", "DispatchTime", "mach_"] {
            expectFalse(body.contains(banned), "ElapsedSinceLaunch must not read \(banned)")
        }
        expectEqual(body.components(separatedBy: "init(").count, 2, "one initializer")
        expectTrue(body.contains("public init(launchUptime: TimeInterval, nowUptime: TimeInterval)"))
    }

    // MARK: L2 slots

    /// L2: the R2 rects, inside the canvas and the TV safe rect, and on screen as design §2.2 / compare.md §5 give them.
    func testSlotsAreTheR2RectsOnEveryScreen() {
        expectEqual([StatusSlot.chipWidth, StatusSlot.chipHeight], [84, 40])
        let canvas = LineMatchRect(x: 0, y: 0, width: 1280, height: 720)
        // (rect, [x, maxX, y, maxY])
        let edges: [(LineMatchRect, [Double])] = [
            (StatusSlot.main, [1190, 1274, 6, 46]),
            (StatusSlot.mainKeepOut, [1182, 1280, 0, 56]),
            (StatusSlot.picker, [1042, 1126, 6, 46]),
            (StatusSlot.pickerKeepOut, [1034, 1132, 0, 56]),
            (StatusSlot.watchStrip, [1196, 1280, 0, 40])
        ]
        for (rect, expected) in edges {
            expectEqual([rect.x, rect.maxX, rect.y, rect.maxY], expected)
            expectTrue(Self.contains(canvas, rect), "\(rect) inside 1280 × 720")
        }
        expectTrue(Self.contains(StatusSlot.mainKeepOut, StatusSlot.main))
        expectTrue(Self.contains(StatusSlot.pickerKeepOut, StatusSlot.picker))
        // S on rows 1–3, 5–7 and 9–11, S_pick on the picker, hidden on the LM family and Watch (design §9 C1).
        let picked: [StatusRoute: LineMatchRect] = [.videoPicker: StatusSlot.picker]
        let hidden: Set<StatusRoute> = [.lineMatchFamily, .watch]
        expectEqual(StatusRoute.allCases.count, 12)
        for route in StatusRoute.allCases {
            if hidden.contains(route) {
                expectNil(StatusSlot.rect(for: route))
                expectNil(StatusSlot.keepOut(for: route))
            } else {
                expectEqual(StatusSlot.rect(for: route), picked[route] ?? StatusSlot.main, "\(route)")
                expectEqual(StatusSlot.keepOut(for: route), picked[route] == nil ? StatusSlot.mainKeepOut
                                                                                 : StatusSlot.pickerKeepOut, "\(route)")
            }
        }
        // Screen points, [x, maxX, y, maxY], as the design prints them (one decimal).
        let screens: [(Double, Double, LineMatchRect, [Double])] = [
            (1920, 1080, StatusSlot.main, [1702.5, 1815.9, 62.1, 116.1]),
            (1920, 1080, StatusSlot.mainKeepOut, [1691.7, 1824.0, 54.0, 129.6]),
            (1920, 1080, StatusSlot.picker, [1502.7, 1616.1, 62.1, 116.1]),
            (1920, 1080, StatusSlot.watchStrip, [1710.6, 1824.0, 54.0, 108.0]),
            (1280, 720, StatusSlot.main, [1135.0, 1210.6, 41.4, 77.4]),
            (1512, 982, StatusSlot.main, [1340.7, 1430.0, 114.7, 157.2])
        ]
        for (width, height, rect, expected) in screens {
            let screen = StatusSlot.onScreen(rect, screenWidth: width, screenHeight: height)
            for (actual, value) in zip([screen.x, screen.maxX, screen.y, screen.maxY], expected) {
                expectEqual(actual, value, accuracy: 0.05)
            }
            expectTrue(Self.contains(StatusSlot.safeRect(screenWidth: width, screenHeight: height), screen))
        }
        // 113.4 × 54.0 pt on the TV.
        let tv = StatusSlot.onScreen(StatusSlot.main, screenWidth: 1920, screenHeight: 1080)
        expectEqual(tv.width, 113.4, accuracy: 1e-9)
        expectEqual(tv.height, 54.0, accuracy: 1e-9)
    }

    /// L2 / I10: each slot and keep-out is clear of the documented neighbours on its own route. Today's LM header
    /// covers S, which is why the chip is hidden there until the C4 nudge; the picker's ticket art covers S, which is
    /// why the picker uses S_pick. Every game kind has a header family.
    func testSlotsClearTheirRoutesNeighbours() {
        // §7.1 L2's neighbour rects (design §2.3 / §2.4, from the app views).
        let boardTwoCluster = LineMatchRect(x: 980, y: 28, width: 184, height: 122)
        let hanziLetterHeader = LineMatchRect(x: 82, y: 17, width: 1100, height: 92)
        let pickerArt = LineMatchRect(x: 1134, y: 17, width: 110, height: 70)
        let nudgedHeader = LineMatchRect(x: 20, y: 16, width: 1162, height: 96)
        let nudgedBadge = LineMatchRect(x: 948, y: 27, width: 220, height: 74)
        let todayBadge = LineMatchRect(x: 1026, y: 27, width: 220, height: 74)
        let parentCorner = LineMatchLayout.parentCornerKeepOut
        expectEqual(parentCorner, LineMatchRect(x: 1196, y: 640, width: 84, height: 80))
        let neighbours: [StatusRoute: [LineMatchRect]] = [
            .boardTwo: [boardTwoCluster], .hanziLetter: [hanziLetterHeader], .videoPicker: [pickerArt]
        ]
        var checked = 0
        for route in StatusRoute.allCases {
            guard let slot = StatusSlot.rect(for: route), let keepOut = StatusSlot.keepOut(for: route) else { continue }
            for rect in (neighbours[route] ?? []) + [parentCorner] {
                expectFalse(slot.intersects(rect), "\(route): slot on \(rect)")
                expectFalse(keepOut.intersects(rect), "\(route): keep-out on \(rect)")
                checked += 1
            }
        }
        expectEqual(checked, 13)
        // The clear space the design quotes (u).
        expectEqual(StatusSlot.main.gap(to: hanziLetterHeader), 8)
        expectEqual(StatusSlot.main.gap(to: boardTwoCluster), 26)
        expectEqual(StatusSlot.picker.gap(to: pickerArt), 8)
        expectEqual(StatusSlot.pickerKeepOut.gap(to: pickerArt), 2)
        // The picker needs S_pick: S and K sit on the ticket art.
        expectTrue(StatusSlot.main.intersects(pickerArt) && StatusSlot.mainKeepOut.intersects(pickerArt))
        // S_pick is only for the picker: it sits in the band the other headers use.
        expectTrue(StatusSlot.picker.intersects(hanziLetterHeader) && StatusSlot.picker.intersects(boardTwoCluster))
        // LM family today: the header panel (20, 16, 1240, 96) and the visa badge run under S, so no chip until C4.
        expectEqual(LineMatchLayout.header, LineMatchRect(x: 20, y: 16, width: 1240, height: 96))
        expectTrue(LineMatchLayout.header.intersects(StatusSlot.main))
        expectTrue(todayBadge.intersects(StatusSlot.main))
        expectNil(StatusSlot.rect(for: .lineMatchFamily))
        // After the 78 u nudge (§2.4) the header ends at 1182, like Hanzi / Letter: S and K are clear.
        for rect in [nudgedHeader, nudgedBadge] {
            expectFalse(rect.intersects(StatusSlot.main) || rect.intersects(StatusSlot.mainKeepOut), "\(rect)")
        }
        expectEqual(StatusSlot.main.gap(to: nudgedHeader), 8)
        // Header families (design §2.3 rows 2–4: 10 + 4 + 13 kinds).
        let boardTwo: [ActivityKind] = [.twoPictureChoose, .findTheSame, .countVehicles, .sequenceShortToLong, .halfMatch,
                                        .shapeCousin, .capacityCompare, .moreFewer, .shadowMatch, .emptyBay]
        let hanziLetter: [ActivityKind] = [.tapLetterAll, .tapLetterWrite, .tapHanziAll, .tapHanziWrite]
        let lineMatchFamily: [ActivityKind] = [.lineMatch, .lineMatchGuidedStraight, .lineMatchGuidedBridge,
                                               .traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree,
                                               .tapCountAll, .tapCountTrace, .tapCountPick, .tapCountAllEnglish,
                                               .tapCountTraceEnglish, .tapCountPickEnglish]
        expectEqual(Set(boardTwo + hanziLetter + lineMatchFamily), Set(ActivityKind.allCases))
        expectEqual(boardTwo.count + hanziLetter.count + lineMatchFamily.count, ActivityKind.allCases.count)
        for kind in boardTwo { expectEqual(StatusRoute(board: kind), .boardTwo, "\(kind)") }
        for kind in hanziLetter { expectEqual(StatusRoute(board: kind), .hanziLetter, "\(kind)") }
        for kind in lineMatchFamily { expectEqual(StatusRoute(board: kind), .lineMatchFamily, "\(kind)") }
    }

    // MARK: L3 Watch strip

    /// L3: the strip chip sits inside the TV safe rect, the player starts 8 u under it, today's sides, road strip and
    /// bottom stay, and the video shrinks by §2.5's R2 figures on 16:9 (−10.4% linear, −19.7% area, each ±0.05
    /// percentage points) and by less at 1512 × 982. The model's insets are today's Watch view's.
    func testWatchStripKeepsTheChipOffTheVideo() throws {
        struct Expected {
            let width: Double, height: Double, unit: Double
            let chip: [Double]                       // x, maxX, y, maxY
            let top: Double, frame: Double, web: Double, video: [Double]
            let todayTop: Double, todayFrame: Double, todayWeb: Double, todayVideo: [Double]
            let linear: Double, area: Double
        }
        let rows = [
            // compare.md §4 at 1920 × 1080.
            Expected(width: 1920, height: 1080, unit: 1.35, chip: [1710.6, 1824.0, 54.0, 108.0],
                     top: 118.8, frame: 812.7, web: 791.1, video: [1406.4, 791.1],
                     todayTop: 27.0, todayFrame: 904.5, todayWeb: 882.9, todayVideo: [1569.6, 882.9],
                     linear: -0.104, area: -0.197),
            Expected(width: 1280, height: 720, unit: 0.9, chip: [1140.4, 1216.0, 36.0, 72.0],
                     top: 79.2, frame: 541.8, web: 527.4, video: [937.6, 527.4],
                     todayTop: 18.0, todayFrame: 603.0, todayWeb: 588.6, todayVideo: [1046.4, 588.6],
                     linear: -0.104, area: -0.197),
            // Taller than 16:9: today's video is width-limited, the strip's height-limited.
            Expected(width: 1512, height: 982, unit: 1.063125, chip: [1347.0975, 1436.4, 49.1, 91.625],
                     top: 100.13, frame: 764.92625, web: 747.91625, video: [1329.6289, 747.91625],
                     todayTop: 21.2625, todayFrame: 843.79375, todayWeb: 826.78375, todayVideo: [1418.445, 797.8753],
                     linear: -0.0626, area: -0.1213)
        ]
        for row in rows {
            let label = "\(Int(row.width)) × \(Int(row.height))"
            let today = WatchStripLayout(screenWidth: row.width, screenHeight: row.height, strip: false)
            let strip = WatchStripLayout(screenWidth: row.width, screenHeight: row.height, strip: true)
            expectNil(today.chip)
            guard let chip = strip.chip else {
                expectTrue(false, "\(label): no chip")
                return
            }
            for (actual, value) in zip([chip.x, chip.maxX, chip.y, chip.maxY], row.chip) {
                expectEqual(actual, value, accuracy: 0.001)
            }
            let safe = StatusSlot.safeRect(screenWidth: row.width, screenHeight: row.height)
            expectTrue(Self.contains(safe, chip), "\(label): chip inside the safe rect")
            expectEqual(chip.maxX, safe.maxX, accuracy: 1e-9)
            expectEqual(chip.y, safe.y, accuracy: 1e-9)
            expectTrue(strip.player.y >= chip.maxY + 8 * row.unit - 1e-9, "\(label): player 8 u under the chip")
            expectFalse(chip.intersects(strip.player), label)
            for (actual, value) in [(strip.player.y, row.top), (strip.player.height, row.frame),
                                    (strip.webView.height, row.web), (strip.video.width, row.video[0]),
                                    (strip.video.height, row.video[1]), (today.player.y, row.todayTop),
                                    (today.player.height, row.todayFrame), (today.webView.height, row.todayWeb),
                                    (today.video.width, row.todayVideo[0]), (today.video.height, row.todayVideo[1])] {
                expectEqual(actual, value, accuracy: 0.001)
            }
            // Only the top moves: same sides, road strip and bottom; the video stays inside the web view.
            expectEqual([strip.player.x, strip.player.width], [today.player.x, today.player.width])
            expectEqual(strip.player.maxY, today.player.maxY, accuracy: 1e-9)
            for layout in [today, strip] {
                expectTrue(Self.contains(layout.webView, layout.video), "\(label): video inside the web view")
            }
            let change = strip.videoChange(from: today)
            expectEqual(change.linear, row.linear, accuracy: 0.0005)
            expectEqual(change.area, row.area, accuracy: 0.0005)
            expectTrue(change.linear >= -0.104 - 0.0005 && change.area >= -0.197 - 0.0005, "\(label): within §2.5")
        }
        // On 16:9 the strip chip is the canvas rect x 1196–1280, y 0–40 on the stage.
        for (width, height) in [(1920.0, 1080.0), (1280, 720)] {
            let chip = WatchStripLayout(screenWidth: width, screenHeight: height, strip: true).chip
            let stage = StatusSlot.onScreen(StatusSlot.watchStrip, screenWidth: width, screenHeight: height)
            expectTrue(chip.map { abs($0.x - stage.x) + abs($0.y - stage.y) + abs($0.maxX - stage.maxX)
                + abs($0.maxY - stage.maxY) < 1e-9 } ?? false, "\(width) × \(height)")
        }
        // The model's insets are today's Watch view's (`StampWatchTimesUpViews` watchBody and the road strip).
        expectEqual([WatchStripLayout.sideInset, WatchStripLayout.topInset, WatchStripLayout.stackSpacing,
                     WatchStripLayout.roadHeight, WatchStripLayout.bottomInset, WatchStripLayout.webViewInset,
                     WatchStripLayout.chipGap], [36, 20, 12, 78, 20, 8, 8])
        let view = try Self.text("Sources/VisaGames/StampWatchTimesUpViews.swift")
        guard let start = view.range(of: "private func watchBody("),
              let road = view.range(of: "struct RoadTimerStrip", range: start.upperBound..<view.endIndex),
              let roadEnd = view.range(of: "\n}", range: road.upperBound..<view.endIndex) else {
            expectTrue(false, "watchBody / RoadTimerStrip not found")
            return
        }
        let body = view[start.upperBound..<road.lowerBound]
        for needle in ["VStack(spacing: metrics.u(12))", ".padding(metrics.u(8))", ".padding(.horizontal, metrics.u(36))",
                       ".padding(.top, metrics.u(20))", ".padding(.bottom, metrics.u(20))", "RoadTimerStrip("] {
            expectTrue(body.contains(needle), "watchBody: \(needle)")
        }
        expectTrue(view[road.upperBound..<roadEnd.lowerBound].contains(".frame(height: metrics.u(78))"), "road strip 78 u")
    }

    // MARK: Copy

    /// Appendix A as the design writes it, every string the chip can produce in HK Traditional Chinese (the OpenCC
    /// fixture and both lists), English boards without Chinese, and Traditional-only sources.
    func testChipCopyIsHongKongTraditional() throws {
        expectEqual(StatusChipCopy.minutes(52), StatusChipText(zh: "52 分鐘", en: "52 min"))
        expectEqual(StatusChipCopy.hours(1, minutes: 5), StatusChipText(zh: "1 小時 5 分", en: "1 h 5 min"))
        expectEqual(StatusChipCopy.overflow, StatusChipText(zh: "99+ 小時", en: "99+ h"))
        expectEqual(StatusChipCopy.sinceStartAccessibility(StatusChipCopy.minutes(52)),
                    StatusChipText(zh: "由開App計：52 分鐘", en: "Since app start: 52 min"))
        expectEqual(StatusChipCopy.sinceStartCaption(StatusChipCopy.minutes(52)),
                    StatusChipText(zh: "由開App計 52 分鐘", en: "52 min since app start"))
        expectEqual(StatusChipCopy.timeNow(afternoon: true, hour: 3, minute: 45),
                    StatusChipText(zh: "而家時間：下午3時45分", en: "Time now: 3:45 PM"))
        expectEqual(StatusChipCopy.hongKongTime, StatusChipText(zh: "香港時間", en: "HK time"))
        var texts = [StatusChipCopy.overflow, StatusChipCopy.hongKongTime]
        for minute in 0...6_001 {
            let elapsed = ElapsedSinceLaunch(launchUptime: 0, nowUptime: Double(minute) * 60)
            texts += [elapsed.text, elapsed.accessibility, elapsed.parentCaption]
        }
        let midnight = Self.utc("2026-11-09T16:00:00Z")
        for minute in 0..<1440 {
            texts.append(StatusClockText.accessibility(midnight.addingTimeInterval(Double(minute * 60))))
        }
        let simplified = try Self.simplifiedOnly()
        // The fixture lists the Simplified forms of this copy's characters (開 計 鐘 時 間), so the check can fail.
        expectTrue(Array("开计钟时间").allSatisfy { simplified.contains($0) })
        expectTrue("由开App计：52 分钟".contains { simplified.contains($0) })
        for text in texts {
            expectFalse(text.zh.contains { simplified.contains($0) }, "Simplified character in \(text.zh)")
            expectTrue(isTraditionalChineseOnly(text.zh) && perfTraditionalOnly(text.zh), text.zh)
            expectTrue(text.en.allSatisfy(\.isASCII), "ABC boards show no Chinese: \(text.en)")
            expectFalse(text.zh.contains("{") || text.en.contains("{"), "unfilled placeholder")
        }
        expectEqual(texts.count, 2 + 6_002 * 3 + 1_440)
        for name in ["StatusClock.swift", "StatusSlot.swift"] {
            let source = try Self.text("Sources/VisaCore/\(name)")
            expectFalse(source.contains { simplified.contains($0) }, "\(name) has a Simplified character")
            expectTrue(isTraditionalChineseOnly(source) && perfTraditionalOnly(source), name)
        }
    }

    // MARK: Helpers

    /// Runs `body` with the process's own zone forced to `identifier` (TZ and Foundation's default), then restores both.
    private func withProcessTimeZone(_ identifier: String, _ body: () -> Void) {
        guard let zone = TimeZone(identifier: identifier) else {
            preconditionFailure("no time zone \(identifier)")
        }
        let savedDefault = NSTimeZone.default
        let savedTZ = getenv("TZ").map { String(cString: $0) }
        setenv("TZ", identifier, 1)
        tzset()
        NSTimeZone.resetSystemTimeZone()
        NSTimeZone.default = zone
        defer {
            if let savedTZ { setenv("TZ", savedTZ, 1) } else { unsetenv("TZ") }
            tzset()
            NSTimeZone.resetSystemTimeZone()
            NSTimeZone.default = savedDefault
        }
        body()
    }

    private static func contains(_ outer: LineMatchRect, _ inner: LineMatchRect) -> Bool {
        inner.x >= outer.x - 1e-9 && inner.maxX <= outer.maxX + 1e-9
            && inner.y >= outer.y - 1e-9 && inner.maxY <= outer.maxY + 1e-9
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
