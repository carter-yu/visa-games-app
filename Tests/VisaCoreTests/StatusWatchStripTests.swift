import Foundation
import VisaCore

/// Clock + elapsed chip C5 (0.39.0 / 87): the Watch status strip (clock-playtime design Decision 7, §2.3 row 12,
/// §2.5, §6, §7.1 L3, §9 C5; chip-rows/compare.md FINAL v1 §4: the R2 chip in a strip above the player, player top
/// 118.8 pt at 1920 × 1080, a 16:9 video −10.4% linear / −19.7% area). The Watch plan, the strip maths for the rect
/// the chip layer draws, and source guards on the Watch view and the layer, which this box cannot compile. Expected
/// values are written out here, never recomputed with the code under test.
final class StatusWatchStripTests {
    /// The strip slot on a 16:9 stage and its keep-out (canvas units), S (compare.md §4–§5).
    private static let strip = LineMatchRect(x: 1196, y: 0, width: 84, height: 40)
    private static let stripKeepOut = LineMatchRect(x: 1188, y: 0, width: 92, height: 48)
    private static let s = LineMatchRect(x: 1190, y: 6, width: 84, height: 40)

    private static func shown(_ mode: Mode, providerBlocked: Bool = false, timesUp: Bool = false,
                              taskRoundOpen: Bool = false, unavailable: Bool = false, kind: ActivityKind? = nil,
                              play: PlayStageRoute = .watch) -> StatusRoute? {
        StatusRoute(mode: mode, providerBlocked: providerBlocked, timesUp: timesUp, taskRoundOpen: taskRoundOpen,
                    letterTicketUnavailable: unavailable, boardKind: kind, playRoute: play)
    }

    // MARK: Plan

    /// Decision 7: a playing video shows the chip, at the strip slot in the night tone, with the Cantonese row and the
    /// label every Cantonese screen gets. Only the LM family stays hidden (until C4).
    func testWatchShowsTheNightChipInTheStrip() {
        expectEqual(StatusSlot.watchStrip, Self.strip)
        expectEqual(StatusSlot.watchStripKeepOut, Self.stripKeepOut)
        expectEqual(StatusSlot.rect(for: .watch), Self.strip)
        expectEqual(StatusSlot.keepOut(for: .watch), Self.stripKeepOut)
        // The keep-out is the chip plus the 8 u gap on its open sides (left and below); its top and right are the
        // canvas edges, which a 16:9 stage puts on the safe lines.
        expectEqual([Self.strip.x - Self.stripKeepOut.x, Self.stripKeepOut.maxY - Self.strip.maxY], [8, 8])
        expectEqual([Self.stripKeepOut.y, Self.stripKeepOut.maxX], [0, 1280])
        // The hidden rule is the LM family alone, the one route without a slot or a plan.
        expectEqual(StatusChipPlan.hiddenRoutes, [.lineMatchFamily])
        expectEqual(StatusRoute.allCases.filter { StatusSlot.rect(for: $0) == nil }, [.lineMatchFamily])
        expectEqual(StatusRoute.allCases.filter { StatusChipPlan(route: $0, activeKind: nil, thinkPauseRemaining: 0) == nil },
                    [.lineMatchFamily])
        // Through the shell: a playing video is Watch, whatever ran last and whatever the round flags say; the chip
        // is at the strip slot, night, Cantonese (even after a Letters round), not dimmed.
        var watchPlans = 0
        for kind in [nil, ActivityKind.findTheSame, .tapLetterAll, .tapLetterWrite, .tapCountPickEnglish, .lineMatch] {
            for open in [false, true] {
                let route = Self.shown(.play, taskRoundOpen: open, unavailable: open, kind: kind)
                expectEqual(route, .watch)
                guard let plan = StatusChipPlan(route: route, activeKind: kind, thinkPauseRemaining: 0) else {
                    expectTrue(false, "no Watch chip after \(String(describing: kind))")
                    return
                }
                expectEqual(plan.route, .watch)
                expectEqual(plan.slot, Self.strip)
                expectEqual(plan.tone, .night)
                expectEqual(plan.language, .cantonese)
                expectFalse(plan.dimmed)
                watchPlans += 1
            }
        }
        expectEqual(watchPlans, 12)
        // Over a playing video, Time's up (night) and provider blocked (day) take the screen and the chip goes to S;
        // parent controls show no child chip.
        let timesUp = StatusChipPlan(route: Self.shown(.play, timesUp: true), activeKind: nil, thinkPauseRemaining: 0)
        expectEqual(timesUp?.slot, Self.s)
        expectEqual(timesUp?.tone, .night)
        let blocked = StatusChipPlan(route: Self.shown(.play, providerBlocked: true), activeKind: nil, thinkPauseRemaining: 0)
        expectEqual(blocked?.slot, Self.s)
        expectEqual(blocked?.tone, .day)
        expectNil(StatusChipPlan(route: Self.shown(.parent), activeKind: nil, thinkPauseRemaining: 0))
        // The night style on the dark player (design §1.3): Ink 80 %, a 2 u Paper outline at 35 %, Paper text.
        let style = StatusChipStyle(tone: .night, increaseContrast: false, reduceTransparency: false)
        expectEqual([style.fill, style.outline, style.text, style.glyph], [0x3A2718, 0xFFF6DF, 0xFFF6DF, 0xFFF6DF])
        expectEqual([style.fillOpacity, style.outlineOpacity, style.outlineWidth], [0.8, 0.35, 2])
        // The same words and the same one accessibility label as the depot's (Appendix A clock.a11y + chip.a11y).
        let at1545 = PerfCodec.parseTimestamp("2026-11-10T07:45:00Z")!
        let label = "而家時間：下午3時45分。由開App計：52 分鐘 / Time now: 3:45 PM. Since app start: 52 min"
        for route in [StatusRoute.watch, .depot] {
            guard let plan = StatusChipPlan(route: route, activeKind: .tapLetterAll, thinkPauseRemaining: 0) else {
                expectTrue(false, "no plan on \(route)")
                return
            }
            let content = StatusChipContent(date: at1545, launchUptime: 100, nowUptime: 3_220, language: plan.language)
            expectEqual([content.clock, content.elapsed, content.accessibilityLabel], ["3:45", "52 分鐘", label])
        }
    }

    // MARK: L3 strip maths

    /// §7.1 L3 for the rect the chip layer draws on Watch (`StatusChipPlan.screenRect`): at 1920 × 1080, 1280 × 720 and
    /// 1512 × 982 it is the strip's chip, inside the TV safe rect with its right edge on the safe line; the player the
    /// Watch view lays out starts 8 u under it (118.8 pt at 1080p) with today's sides and bottom; the chip touches
    /// neither the player, its web view nor the video; a 16:9 video is 10.4% narrower (19.7% less area). At
    /// 1512 × 982 the stage is letterboxed, and the strip slot mapped through it would sit on the player, so the layer
    /// must not map the Watch slot through the stage. Every other route still does.
    func testWatchChipStaysOffThePlayerAtEverySize() {
        struct Row {
            let width: Double, height: Double, unit: Double
            let chip: [Double]                       // x, maxX, y, maxY (pt)
            let top: Double, gap: Double, bottom: Double
            let video: [Double], todayVideo: [Double]
            let linear: Double, area: Double
            let staged: [Double]                     // the strip slot through the stage: y, maxY
            let stagedOnPlayer: Bool
            let depot: [Double]                      // S through the stage: x, maxX, y, maxY
        }
        let rows = [
            // compare.md §4 and design §2.2.
            Row(width: 1920, height: 1080, unit: 1.35, chip: [1710.6, 1824.0, 54.0, 108.0], top: 118.8, gap: 10.8,
                bottom: 931.5, video: [1406.4, 791.1], todayVideo: [1569.6, 882.9], linear: -0.104, area: -0.197,
                staged: [54.0, 108.0], stagedOnPlayer: false, depot: [1702.5, 1815.9, 62.1, 116.1]),
            Row(width: 1280, height: 720, unit: 0.9, chip: [1140.4, 1216.0, 36.0, 72.0], top: 79.2, gap: 7.2,
                bottom: 621.0, video: [937.6, 527.4], todayVideo: [1046.4, 588.6], linear: -0.104, area: -0.197,
                staged: [36.0, 72.0], stagedOnPlayer: false, depot: [1135.0, 1210.6, 41.4, 77.4]),
            // Taller than 16:9 (the dev MacBook): the stage sits 108.275 pt down, the strip at the safe top 49.1 pt.
            Row(width: 1512, height: 982, unit: 1.063125, chip: [1347.0975, 1436.4, 49.1, 91.625], top: 100.13,
                gap: 8.505, bottom: 865.05625, video: [1329.6289, 747.91625], todayVideo: [1418.445, 797.8753],
                linear: -0.0626, area: -0.1213, staged: [108.275, 150.8], stagedOnPlayer: true,
                depot: [1340.7, 1430.0, 114.7, 157.2])
        ]
        guard let plan = StatusChipPlan(route: .watch, activeKind: nil, thinkPauseRemaining: 0),
              let depot = StatusChipPlan(route: .depot, activeKind: nil, thinkPauseRemaining: 0) else {
            expectTrue(false, "no Watch / depot plan")
            return
        }
        for row in rows {
            let label = "\(Int(row.width)) × \(Int(row.height))"
            let chip = plan.screenRect(screenWidth: row.width, screenHeight: row.height)
            for (actual, value) in zip([chip.x, chip.maxX, chip.y, chip.maxY], row.chip) {
                expectEqual(actual, value, accuracy: 0.001)
            }
            let safe = StatusSlot.safeRect(screenWidth: row.width, screenHeight: row.height)
            expectTrue(Self.contains(safe, chip), "\(label): chip inside the safe rect")
            expectEqual(chip.maxX, safe.maxX, accuracy: 1e-9)
            expectEqual(chip.y, safe.y, accuracy: 1e-9)
            // The Watch view lays its player under the same chip.
            let layout = WatchStripLayout(screenWidth: row.width, screenHeight: row.height, strip: true)
            let today = WatchStripLayout(screenWidth: row.width, screenHeight: row.height, strip: false)
            expectEqual(layout.chip, chip, label)
            expectEqual(layout.player.y, row.top, accuracy: 0.001)
            expectEqual(layout.player.y - chip.maxY, row.gap, accuracy: 0.001)
            expectTrue(layout.player.y >= chip.maxY + 8 * row.unit - 1e-9, "\(label): player 8 u under the chip")
            expectEqual(layout.player.maxY, row.bottom, accuracy: 0.001)
            expectEqual(today.player.maxY, row.bottom, accuracy: 0.001)
            expectEqual([layout.player.x, layout.player.width], [today.player.x, today.player.width], label)
            for rect in [layout.player, layout.webView, layout.video] {
                expectFalse(chip.intersects(rect), "\(label): chip on \(rect)")
            }
            for (actual, value) in zip([layout.video.width, layout.video.height, today.video.width, today.video.height],
                                       row.video + row.todayVideo) {
                expectEqual(actual, value, accuracy: 0.001)
            }
            let change = layout.videoChange(from: today)
            expectEqual(change.linear, row.linear, accuracy: 0.0005)
            expectEqual(change.area, row.area, accuracy: 0.0005)
            // The strip slot through the stage: the same rect on 16:9, on the player when letterboxed.
            let staged = StatusSlot.onScreen(StatusSlot.watchStrip, screenWidth: row.width, screenHeight: row.height)
            expectEqual(staged.y, row.staged[0], accuracy: 0.001)
            expectEqual(staged.maxY, row.staged[1], accuracy: 0.001)
            expectEqual(staged.intersects(layout.player), row.stagedOnPlayer, label)
            // Every other route maps its slot through the stage (design §2.2): the depot's S.
            let s = depot.screenRect(screenWidth: row.width, screenHeight: row.height)
            for (actual, value) in zip([s.x, s.maxX, s.y, s.maxY], row.depot) {
                expectEqual(actual, value, accuracy: 0.05)
            }
        }
        // On 16:9 the keep-out's bottom edge is the player's top: 118.8 pt at 1080p, 79.2 pt at 720p.
        for (width, height, keepOut) in [(1920.0, 1080.0, [1699.8, 1824.0, 54.0, 118.8]),
                                         (1280, 720, [1133.2, 1216.0, 36.0, 79.2])] {
            let rect = StatusSlot.onScreen(StatusSlot.watchStripKeepOut, screenWidth: width, screenHeight: height)
            for (actual, value) in zip([rect.x, rect.maxX, rect.y, rect.maxY], keepOut) {
                expectEqual(actual, value, accuracy: 0.001)
            }
            let player = WatchStripLayout(screenWidth: width, screenHeight: height, strip: true).player
            expectEqual(player.y, rect.maxY, accuracy: 1e-9)
        }
        // Any window from 800 × 600 to 3840 × 2160: the same rules, and never more than the 16:9 loss.
        var sizes = 0
        for width in stride(from: 800.0, through: 3_840, by: 160) {
            for height in stride(from: 600.0, through: 2_160, by: 120) {
                let unit = DesignTokens.stageLayout(screenWidth: width, screenHeight: height).scale
                let chip = plan.screenRect(screenWidth: width, screenHeight: height)
                let layout = WatchStripLayout(screenWidth: width, screenHeight: height, strip: true)
                let today = WatchStripLayout(screenWidth: width, screenHeight: height, strip: false)
                let safe = StatusSlot.safeRect(screenWidth: width, screenHeight: height)
                let label = "\(width) × \(height)"
                expectEqual(layout.chip, chip, label)
                expectTrue(Self.contains(safe, chip) && abs(chip.maxX - safe.maxX) < 1e-9 && abs(chip.y - safe.y) < 1e-9,
                           "\(label): chip at the safe top right")
                expectTrue(layout.player.y >= chip.maxY + 8 * unit - 1e-9, "\(label): player 8 u under the chip")
                expectFalse(chip.intersects(layout.player) || chip.intersects(layout.webView), "\(label): chip on the player")
                let change = layout.videoChange(from: today)
                expectTrue(change.linear <= 1e-12 && change.linear >= -0.104 - 0.0005, "\(label): \(change.linear)")
                expectTrue(change.area >= -0.197 - 0.0005, "\(label): \(change.area)")
                sizes += 1
            }
        }
        expectEqual(sizes, 20 * 14)
    }

    // MARK: App wiring (source guards; SwiftUI / AppKit are not compiled on this box)

    /// The Watch view starts its player at `WatchStripLayout`'s player top, for the size it is given, and draws no chip
    /// and nothing over the web view; the strip is static; the road strip, its readout, glow, pulse and garage hold
    /// are as before. ShellView's one non-hittable chip layer draws the Watch chip at `plan.screenRect`, the same way
    /// as on every screen, with nothing that takes focus or keys; Watch keeps the garage as its parent entry.
    func testWatchViewLaysThePlayerUnderTheStrip() throws {
        let views = try Self.text("Sources/VisaGames/StampWatchTimesUpViews.swift")
        guard let watchStart = views.range(of: "struct WatchPlaybackView: View {"),
              let bodyStart = views.range(of: "private func watchBody(", range: watchStart.upperBound..<views.endIndex),
              let roadStart = views.range(of: "struct RoadTimerStrip: View {", range: bodyStart.upperBound..<views.endIndex),
              let roadEnd = views.range(of: "// MARK: - Board 5", range: roadStart.upperBound..<views.endIndex) else {
            expectTrue(false, "WatchPlaybackView / watchBody / RoadTimerStrip not found")
            return
        }
        let watchView = Self.codeOnly(String(views[watchStart.upperBound..<bodyStart.lowerBound]))
        let watchBody = Self.codeOnly(String(views[bodyStart.lowerBound..<roadStart.lowerBound]))
        let road = Self.codeOnly(String(views[roadStart.lowerBound..<roadEnd.lowerBound]))
        // The player top comes from the shared layout at the view's own size; no hard-coded points.
        expectTrue(Self.inOrder(Substring(watchView), [
            "GeometryReader { proxy in", "let width = Double(proxy.size.width)", "let height = Double(proxy.size.height)",
            "DesignTokens.stageLayout(screenWidth: width, screenHeight: height)",
            "let strip = WatchStripLayout(screenWidth: width, screenHeight: height, strip: true)",
            "watchBody(metrics: metrics, playerTop: CGFloat(strip.player.y))", ".ignoresSafeArea()"
        ]), "WatchPlaybackView: the player top from WatchStripLayout")
        expectTrue(Self.inOrder(Substring(watchBody), [
            "private func watchBody(metrics: CanvasMetrics, playerTop: CGFloat) -> some View {",
            "Color(hex: DesignTokens.Palette.ink)", "VStack(spacing: metrics.u(12)) {", "ScopedPlayerView(",
            ".clipShape(RoundedRectangle(cornerRadius: metrics.u(20), style: .continuous))", ".padding(metrics.u(8))",
            "} else {", ".frame(maxWidth: .infinity, maxHeight: .infinity)", ".padding(.horizontal, metrics.u(36))",
            ".padding(.top, playerTop)", "RoadTimerStrip(ticket: ticket, progress: progress, onParentUnlock: onParentUnlock)",
            ".padding(.horizontal, metrics.u(36))", ".padding(.bottom, metrics.u(20))"
        ]), "watchBody: the player under the strip, the road strip at the bottom")
        expectEqual(watchBody.components(separatedBy: ".padding(.top,").count, 2, "one top inset, the strip's")
        expectFalse(watchBody.contains(".padding(.top, metrics.u(20))"), "the pre-C5 20 u top is gone")
        for number in ["118.8", "1.35", "0.05", "safeAreaFraction"] {
            expectFalse(watchView.contains(number) || watchBody.contains(number), "hard-coded \(number)")
        }
        // No chip in the Watch view, nothing over the web view (its only modifiers are the clip and the inset; the
        // frame outline is the player's one overlay), and a static strip.
        for banned in ["StatusClockLayer", "StatusChip", "StatusSlot", "TimelineView", ".animation(", "withAnimation",
                       "Timer.", "Timer(", ".overlay(alignment"] {
            expectFalse(watchView.contains(banned) || watchBody.contains(banned), "Watch view must not use \(banned)")
        }
        expectEqual(watchBody.components(separatedBy: ".overlay(").count, 2, "the frame outline is the only overlay")
        guard let player = watchBody.range(of: "ScopedPlayerView("),
              let placeholder = watchBody.range(of: "} else {", range: player.upperBound..<watchBody.endIndex) else {
            expectTrue(false, "ScopedPlayerView call not found")
            return
        }
        let playerCall = watchBody[player.upperBound..<placeholder.lowerBound]
        for banned in [".overlay", ".background", "ZStack", ".padding(.top"] {
            expectFalse(playerCall.contains(banned), "the web view gets \(banned)")
        }
        let scoped = Self.codeOnly(try Self.text("Sources/VisaGames/ScopedPlayerView.swift"))
        for banned in ["StatusClockLayer", "StatusChip", "StatusSlot", "WatchStripLayout"] {
            expectFalse(scoped.contains(banned), "ScopedPlayerView must not use \(banned)")
        }
        // The road strip as before: the 78 u band, the 仲有 N 分鐘 readout, the last-minute red outline, glow and pulse
        // (steady with Reduce Motion), and the 3 s parent hold over the garage.
        for needle in [
            "let roadHeight = metrics.u(78)", ".frame(height: metrics.u(78))",
            "CanvasText(\"仲有 \\(progress.remainingMinutesCeil) 分鐘\", size: 18, weight: 800,",
            ".offset(x: geo.size.width * 0.55)",
            ".strokeBorder(progress.almostHome ? Color(hex: DesignTokens.Palette.stampRed) : Color.ink,",
            "lineWidth: metrics.u(progress.almostHome ? 6 : 4))",
            ".shadow(color: glowColor.opacity(almostHomeGlowOpacity), radius: metrics.u(18))",
            "GarageGlyph(lit: progress.almostHome)", "ParentCornerEntry(onUnlock: onParentUnlock, size: 72, showsMark: false)",
            ".frame(width: metrics.u(72), height: metrics.u(72))", ".frame(maxWidth: .infinity, alignment: .trailing)",
            ".accessibilityLabel(\"仲有 \\(progress.remainingMinutesCeil) 分鐘 / \\(progress.remainingMinutesCeil) minutes left\")",
            ".onChange(of: progress.almostHome) { updatePulse($0) }", "if reduceMotion { return 0.9 }",
            "return pulse ? 0.95 : 0.35", "withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {"
        ] {
            expectTrue(road.contains(needle), "RoadTimerStrip: \(needle)")
        }
        // One chip: ShellView's layer is the app's only `StatusClockLayer(` and the layer the only place that draws
        // `StatusChipView(`.
        let files = try Self.appSources()
        expectTrue(files.count > 40 && files.contains { $0.name == "AppDelegate.swift" }
                   && files.contains { $0.name == "StatusClockLayer.swift" }, "app sources")
        var layerCalls: [String] = []
        var chipViews: [String] = []
        for file in files {
            for _ in 1..<file.code.components(separatedBy: "StatusClockLayer(").count { layerCalls.append(file.name) }
            for _ in 1..<file.code.components(separatedBy: "StatusChipView(").count { chipViews.append(file.name) }
        }
        expectEqual(layerCalls, ["AppDelegate.swift"])
        expectEqual(chipViews, ["StatusClockLayer.swift"])
        // ShellView draws that layer for Watch as for any route with a plan, and keeps the garage as Watch's parent
        // entry (no parent corner while watching).
        let app = Self.codeOnly(try Self.text("Sources/VisaGames/AppDelegate.swift"))
        guard let chipStart = app.range(of: "if let statusChip {"),
              let cornerStart = app.range(of: "if showsParentCorner {", range: chipStart.upperBound..<app.endIndex) else {
            expectTrue(false, "ShellView chip layer not found")
            return
        }
        let chipBlock = app[chipStart.upperBound..<cornerStart.lowerBound]
        expectTrue(chipBlock.contains("StatusClockLayer(plan: statusChip, launchUptime: model.launchUptime)"))
        expectFalse(chipBlock.contains("watching") || chipBlock.contains("isWatching") || chipBlock.contains(".watch"),
                    "no Watch special case around the layer")
        expectTrue(app.contains("let showsParentCorner = childMode && !watching && !onDepot"), "garage hold on Watch")
        // The layer places the chip with the plan's rect (the strip's on Watch) and takes no focus, keys or hover.
        let layer = Self.codeOnly(try Self.text("Sources/VisaGames/StatusClockLayer.swift"))
        expectTrue(layer.contains("let rect = plan.screenRect(screenWidth: width, screenHeight: height)"), "plan.screenRect")
        expectFalse(layer.contains("StatusSlot.onScreen("), "the Watch slot must not go through the stage")
        for banned in ["focused", "FocusState", "onKeyPress", "keyboardShortcut", "onMoveCommand", "onExitCommand",
                       "onCommand", "FirstResponder", "NSView", "onHover"] {
            expectFalse(layer.contains(banned), "StatusClockLayer must not use \(banned)")
        }
        expectTrue(Self.inOrder(Substring(layer), ["GeometryReader { proxy in", ".allowsHitTesting(false)",
                                                   "private struct StatusChipView"]), "non-hittable layer")
    }

    // MARK: Helpers

    private static func contains(_ outer: LineMatchRect, _ inner: LineMatchRect) -> Bool {
        inner.x >= outer.x - 1e-9 && inner.maxX <= outer.maxX + 1e-9
            && inner.y >= outer.y - 1e-9 && inner.maxY <= outer.maxY + 1e-9
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
    private static func root() -> URL {
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: beside.appendingPathComponent("Package.swift").path)
            ? beside : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func text(_ path: String) throws -> String {
        try String(contentsOf: root().appendingPathComponent(path), encoding: .utf8)
    }

    /// The app target's Swift files, code only.
    private static func appSources() throws -> [(name: String, code: String)] {
        let folder = root().appendingPathComponent("Sources/VisaGames")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") }
        return try names.sorted().map { name in
            (name, codeOnly(try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)))
        }
    }

    /// `text` without its `//` and `///` comments, so a source guard reads code, not prose.
    private static func codeOnly(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
            guard let comment = line.range(of: "//") else { return line }
            return line[..<comment.lowerBound]
        }.joined(separator: "\n")
    }
}
