import Foundation
import VisaCore

/// Canvas design tokens, stage fitting, SVG path parsing and vector artwork (ADR 0007).
final class CanvasFoundationTests {
    func testPaletteMatchesCanvasTokens() {
        let palette = DesignTokens.Palette.self
        expectEqual(palette.ink, 0x3A2718)
        expectEqual(palette.sky, 0xA8E0F7)
        expectEqual(palette.grass, 0x6FC063)
        expectEqual(palette.sand, 0xF4CD74)
        expectEqual(palette.sunny, 0xFFC928)
        expectEqual(palette.tomato, 0xF0553A)
        expectEqual(palette.metro, 0x2F7DE1)
        expectEqual(palette.mint, 0x3CC49A)
        expectEqual(palette.paper, 0xFFF6DF)
        expectEqual(palette.stampRed, 0xD93A2B)
        expectEqual(palette.road, 0x5B5F73)
        let ink = DesignTokens.rgb(palette.ink)
        expectEqual(ink.red, 58.0 / 255)
        expectEqual(ink.green, 39.0 / 255)
        expectEqual(ink.blue, 24.0 / 255)
    }

    func testTargetsAndTimingTokens() {
        expectEqual(DesignTokens.outlineWidth, 5)
        expectEqual(DesignTokens.maxChoices, 3)
        expectEqual(DesignTokens.parentHoldSeconds, 3)
        expectEqual(DesignTokens.pressedOffset, 6)
        expectEqual(DesignTokens.pressedShadowDepth, 2)
        let cardShare = DesignTokens.choiceCardWidth / DesignTokens.referenceWidth
        expectTrue(cardShare > 0.22 && cardShare < 0.24)
    }

    func testStageFitsReferenceInsideTVSafeArea() {
        let reference = DesignTokens.stageLayout(screenWidth: 1280, screenHeight: 720)
        expectClose(reference.scale, 0.9)
        expectClose(reference.originX, 64)
        expectClose(reference.originY, 36)

        let fullHD = DesignTokens.stageLayout(screenWidth: 1920, screenHeight: 1080)
        expectClose(fullHD.scale, 1.35)
        expectClose(fullHD.originX, 96)
        expectClose(fullHD.originY, 54)

        for (width, height) in [(1920.0, 1080.0), (3840, 2160), (1440, 900), (1024, 768), (2560, 1080)] {
            let layout = DesignTokens.stageLayout(screenWidth: width, screenHeight: height)
            let safeX = width * DesignTokens.safeAreaFraction
            let safeY = height * DesignTokens.safeAreaFraction
            let contentWidth = DesignTokens.referenceWidth * layout.scale
            let contentHeight = DesignTokens.referenceHeight * layout.scale
            expectTrue(layout.originX >= safeX - 0.0001)
            expectTrue(layout.originY >= safeY - 0.0001)
            expectTrue(layout.originX + contentWidth <= width - safeX + 0.0001)
            expectTrue(layout.originY + contentHeight <= height - safeY + 0.0001)
            // Backdrop covers the whole screen (full bleed).
            expectTrue(layout.backdropOriginX <= 0.0001 && layout.backdropOriginY <= 0.0001)
            expectTrue(layout.backdropOriginX + DesignTokens.referenceWidth * layout.backdropScale >= width - 0.0001)
            expectTrue(layout.backdropOriginY + DesignTokens.referenceHeight * layout.backdropScale >= height - 0.0001)
        }
    }

    func testStageFailsSafeForDegenerateSizes() {
        for (width, height) in [(0.0, 0.0), (-10, 720), (.nan, 720), (1280, .infinity)] {
            let layout = DesignTokens.stageLayout(screenWidth: width, screenHeight: height)
            expectEqual(layout, .identity)
        }
    }

    func testSVGPathParsesAbsoluteRelativeAndSmoothCommands() throws {
        let hills = try SVGPathData.parse("M0 318 Q170 250 360 300 T720 292")
        expectEqual(hills, [
            .move(x: 0, y: 318),
            .quad(cx: 170, cy: 250, x: 360, y: 300),
            .quad(cx: 550, cy: 350, x: 720, y: 292)
        ])

        let star = try SVGPathData.parse("M1045 203 l3.8 7.8 8.6 1.2-6.2 6z")
        expectEqual(star.count, 5)
        expectEqual(star[0], .move(x: 1045, y: 203))
        expectNear(star[1], x: 1048.8, y: 210.8)
        expectNear(star[2], x: 1057.4, y: 212)
        expectNear(star[3], x: 1051.2, y: 218)
        expectEqual(star[4], .close)

        let lines = try SVGPathData.parse("M900 362 H984 M898 390 H986 M46 90 V40")
        expectEqual(lines, [
            .move(x: 900, y: 362), .line(x: 984, y: 362),
            .move(x: 898, y: 390), .line(x: 986, y: 390),
            .move(x: 46, y: 90), .line(x: 46, y: 40)
        ])

        let packed = try SVGPathData.parse("M12 2.8l2.8 5.8 6.4.8")
        expectNear(packed[2], x: 21.2, y: 9.4)

        let afterClose = try SVGPathData.parse("M10 10 L20 10 Z l5 5")
        expectEqual(afterClose.last, .line(x: 15, y: 15))

        let separators = try SVGPathData.parse("M1,2L3,4M.5 1e2")
        expectEqual(separators, [.move(x: 1, y: 2), .line(x: 3, y: 4), .move(x: 0.5, y: 100)])

        let implicitLine = try SVGPathData.parse("m10 10 5 0 0 5")
        expectEqual(implicitLine, [.move(x: 10, y: 10), .line(x: 15, y: 10), .line(x: 15, y: 15)])

        let cubic = try SVGPathData.parse("M0 0 C10 0 20 10 20 20 S30 40 40 40")
        expectEqual(cubic[2], .cubic(c1x: 20, c1y: 30, c2x: 30, c2y: 40, x: 40, y: 40))

        expectEqual(try SVGPathData.parse(""), [])
    }

    func testSVGArcBecomesCubicsThatBulgeTheRightWay() throws {
        // Speaker wave from the canvas: a small clockwise arc from (15.5, 9) to (15.5, 15).
        let wave = try SVGPathData.parse("M15.5 9a4 4 0 0 1 0 6")
        expectEqual(wave.first, .move(x: 15.5, y: 9))
        guard case let .cubic(c1x, _, c2x, _, x, y)? = wave.last else {
            preconditionFailure("Expected the arc to end in a cubic segment")
        }
        expectTrue(abs(x - 15.5) < 0.0001 && abs(y - 15) < 0.0001)
        expectTrue(c1x > 15.5 && c2x > 15.5) // bulges right, like the speaker waves
        expectTrue(wave.count >= 2)
    }

    func testSVGPathRejectsMalformedData() {
        expectThrowsError(try SVGPathData.parse("M10"))
        expectThrowsError(try SVGPathData.parse("10 20"))
        expectThrowsError(try SVGPathData.parse("M0 0 X5 5"))
        expectThrowsError(try SVGPathData.parse("M0 0 Z 5 5"))
    }

    func testCanvasArtworkIsCompleteAndParsed() {
        expectTrue(CanvasArt.all.count >= 8)
        var names = Set<String>()
        for artwork in CanvasArt.all {
            expectTrue(artwork.width > 0 && artwork.height > 0)
            expectFalse(artwork.elements.isEmpty)
            expectTrue(names.insert(artwork.name).inserted)
            for element in artwork.elements {
                if case let .path(commands) = element.geometry {
                    expectFalse(commands.isEmpty) // an unparsable path would be empty
                }
                expectTrue(element.style.fill != nil || element.style.stroke != nil)
                expectTrue(element.style.opacity > 0 && element.style.opacity <= 1)
            }
        }
        // Vehicle art shares the canvas's 240×150 box so cards can swap vehicles freely.
        for vehicle in [CanvasArt.taxi, CanvasArt.fireEngine, CanvasArt.metro, CanvasArt.bus] {
            expectEqual(vehicle.width, 240)
            expectEqual(vehicle.height, 150)
        }
        expectEqual(CanvasArt.depotScene.width, DesignTokens.referenceWidth)
        expectEqual(CanvasArt.depotScene.height, DesignTokens.referenceHeight)
    }

    func testMissionTicketsFollowCanvas() {
        expectEqual(MissionTicket.all.map(\.difficulty), [.easy, .medium, .challenge])
        expectEqual(MissionTicket.all.map(\.titleTraditionalChinese), ["的士短程", "消防車任務", "地鐵長程"])
        for ticket in MissionTicket.all {
            let stars = ticket.difficulty.rawValue
            expectEqual(ticket.stars, stars)
            expectEqual(ticket.roadTiles, stars) // one road tile = 10 minutes
            expectEqual(ticket.minutesLabel, "\(stars * 10) 分鐘")
            expectTrue(ticket.accessibilityLabel.contains(" / "))
            expectTrue(isTraditionalChineseOnly(ticket.titleTraditionalChinese))
        }
    }
}

final class CantoneseVoiceTests {
    private func voice(_ id: String, _ language: String, quality: Int = 1) -> SpeechVoiceInfo {
        SpeechVoiceInfo(identifier: id, name: id, language: language, qualityRank: quality)
    }

    func testPicksHongKongCantoneseOnly() {
        let voices = [voice("tingting", "zh-CN"), voice("meijia", "zh-TW"), voice("sinji", "zh-HK"), voice("samantha", "en-US")]
        expectEqual(CantoneseVoicePicker.pick(from: voices)?.identifier, "sinji")
        expectEqual(CantoneseVoicePicker.pick(from: [voice("x", "zh_HK")])?.identifier, "x")
    }

    func testNeverFallsBackToMandarin() {
        let voices = [voice("tingting", "zh-CN"), voice("meijia", "zh-TW")]
        expectNil(CantoneseVoicePicker.pick(from: voices))
        expectNil(CantoneseVoicePicker.pick(from: []))
    }

    func testPrefersHigherQualityVoice() {
        let voices = [voice("compact", "zh-HK", quality: 1), voice("premium", "zh-HK", quality: 3), voice("enhanced", "zh-HK", quality: 2)]
        expectEqual(CantoneseVoicePicker.pick(from: voices)?.identifier, "premium")
    }

    func testSpokenLinesAreBilingualTraditional() {
        for line in SpokenPrompt.allUXLines {
            expectFalse(line.traditionalChinese.isEmpty)
            expectFalse(line.english.isEmpty)
            expectTrue(isTraditionalChineseOnly(line.traditionalChinese))
        }
        expectEqual(SpokenPrompt.depotPickTicket.traditionalChinese, "揀一張車票！")
        expectEqual(SpokenPrompt.depotPickTicket.english, "Pick a ticket!")
        expectEqual(SpokenPrompt.stamped.traditionalChinese, "蓋印！")
    }
}

final class PenSparkTests {
    private let start = Date(timeIntervalSince1970: 5_000)

    func testHoverInProximityShowsSparkAndRecordsHover() {
        var spark = PenSparkState()
        spark.proximity(entering: true, now: start)
        expectFalse(spark.isVisible)
        let firstHover = spark.hover(x: 100, y: 200, now: start)
        expectTrue(firstHover)
        expectTrue(spark.isVisible)
        expectEqual(spark.position, PenSparkPoint(x: 100, y: 200))
        expectFalse(spark.hover(x: 110, y: 205, now: start)) // only the first hover per approach is new evidence
        spark.proximity(entering: false, now: start)
        expectFalse(spark.isVisible)
        spark.proximity(entering: true, now: start)
        expectTrue(spark.hover(x: 1, y: 1, now: start))
    }

    func testTouchShowsSparkWithoutHoverSupport() {
        var spark = PenSparkState()
        spark.touch(x: 40, y: 50, now: start)
        expectTrue(spark.isVisible)
        expectFalse(spark.hoverObserved)
        spark.lift(x: 42, y: 52, now: start)
        expectTrue(spark.isVisible)
        expectEqual(spark.position, PenSparkPoint(x: 42, y: 52))
    }

    func testSparkHidesAfterIdle() {
        var spark = PenSparkState()
        spark.touch(x: 40, y: 50, now: start)
        spark.tick(now: start.addingTimeInterval(PenSparkState.idleHideSeconds - 0.1))
        expectTrue(spark.isVisible)
        spark.tick(now: start.addingTimeInterval(PenSparkState.idleHideSeconds + 0.1))
        expectFalse(spark.isVisible)
    }

    func testMouseMoveOutsideProximityIsNotPenHoverEvidence() {
        var spark = PenSparkState()
        expectFalse(spark.hover(x: 5, y: 5, now: start))
        expectTrue(spark.isVisible)
        expectFalse(spark.hoverObserved)
    }
}

/// Rejects common Simplified-only characters that could slip into child-facing lines.
func isTraditionalChineseOnly(_ text: String) -> Bool {
    let simplifiedOnly: Set<Character> = ["张", "车", "证", "厂", "钟", "选", "听", "简", "务", "长", "铁", "发", "这", "个", "们", "来", "对", "说", "还", "时"]
    return !text.contains(where: { simplifiedOnly.contains($0) })
}

private func expectClose(_ actual: Double, _ expected: Double, file: StaticString = #file, line: UInt = #line) {
    precondition(abs(actual - expected) < 0.0001, "Expected \(expected), got \(actual)", file: file, line: line)
}

private func expectNear(_ command: SVGPathCommand, x: Double, y: Double, file: StaticString = #file, line: UInt = #line) {
    guard case let .line(actualX, actualY) = command else {
        preconditionFailure("Expected a line command, got \(command)", file: file, line: line)
    }
    precondition(abs(actualX - x) < 0.0001 && abs(actualY - y) < 0.0001,
                 "Expected (\(x), \(y)), got (\(actualX), \(actualY))", file: file, line: line)
}
