import Foundation
import VisaCore

final class ParentScrollDiagnosticsTests {
    func testJumpRequiresOneDecreaseOverTwoHundredPoints() {
        var detector = ParentScrollJumpDetector()
        expectNil(detector.observe(offset: 900, at: 1))
        expectNil(detector.observe(offset: 700, at: 2))
        expectNil(detector.observe(offset: 1_000, at: 3))
        expectTrue(detector.observe(offset: 799, at: 4) != nil)
        expectNil(detector.observe(offset: 799, at: 5))
        expectNil(detector.observe(offset: 650, at: 6))
        expectNil(detector.observe(offset: 500, at: 7))
    }

    func testRecentUpwardWheelExplainsDecreaseButOldInputDoesNot() {
        var detector = ParentScrollJumpDetector()
        expectNil(detector.observe(offset: 1_200, at: 1))
        detector.recordScrollWheel(deltaY: 20, at: 2)
        expectNil(detector.observe(offset: 800, at: 2.3))
        expectTrue(detector.observe(offset: 300, at: 2.36) != nil)
        // Long pauses do not hide an otherwise unexplained programmatic reset.
        expectNil(detector.observe(offset: 1_200, at: 20))
        expectTrue(detector.observe(offset: 0, at: 30) != nil)
    }

    func testLatestWheelDirectionWinsAndZeroDeltaKeepsIntent() {
        var detector = ParentScrollJumpDetector()
        expectNil(detector.observe(offset: 1_000, at: 1))
        detector.recordScrollWheel(deltaY: 10, at: 1.1)
        detector.recordScrollWheel(deltaY: -10, at: 1.2)
        expectTrue(detector.observe(offset: 500, at: 1.3) != nil)
        detector.recordScrollWheel(deltaY: 10, at: 1.4)
        detector.recordScrollWheel(deltaY: 0, at: 1.5)
        expectNil(detector.observe(offset: 0, at: 1.6))
    }

    func testConfirmedVideosScrollbarDragDoesNotProduceJumps() {
        var detector = ParentScrollJumpDetector()
        expectNil(detector.observe(offset: 2_902, at: 1842804.5))
        // The native scroller tracking loop can consume drag/up events without
        // sending them through a local NSEvent monitor. Its duration is not a
        // time-limited wheel gesture; the final two changes exceed that window.
        detector.beginScrollerTracking(at: 1842804.590)
        let changes: [(Double, Double)] = [
            (2_548, 1842804.829), (2_316, 1842804.834),
            (1_881, 1842804.895), (1_582.7065757174983, 1842804.928),
            (1_583, 1842804.931), (1_336, 1842804.960),
            (898, 1842805.054), (644, 1842805.074), (0, 1842805.341)
        ]
        for (offset, time) in changes {
            expectNil(detector.observe(offset: offset, at: time))
        }
        detector.endScrollerTracking(at: 1842805.5)
        expectNil(detector.observe(offset: 1_000, at: 1842806))
        expectTrue(detector.observe(offset: 0, at: 1842806.1) != nil)
    }

    func testScrollerInteractionGraceExpiresAndContentClicksDoNotSuppress() {
        var detector = ParentScrollJumpDetector()
        expectNil(detector.observe(offset: 1_500, at: 1))
        detector.recordScrollerInteraction(at: 1.1)
        expectNil(detector.observe(offset: 1_000, at: 1.4))
        expectTrue(detector.observe(offset: 500, at: 1.46) != nil)
        detector.recordEvent("mouseDown in document", at: 1.5)
        expectTrue(detector.observe(offset: 0, at: 1.6) != nil)
    }

    func testDownwardWheelSupersedesScrollerGraceButNotActiveTracking() {
        var detector = ParentScrollJumpDetector()
        expectNil(detector.observe(offset: 2_000, at: 1))
        detector.recordScrollerInteraction(at: 1.1)
        detector.recordScrollWheel(deltaY: -15, at: 1.2)
        expectTrue(detector.observe(offset: 1_500, at: 1.3) != nil)
        detector.beginScrollerTracking(at: 1.4)
        detector.recordScrollWheel(deltaY: -20, at: 1.5)
        expectNil(detector.observe(offset: 1_000, at: 1.6))
        detector.endScrollerTracking(at: 1.7)
        // A zero-delta phase ending does not cancel the scroller's newer input.
        detector.recordScrollWheel(deltaY: 0, at: 1.8)
        expectNil(detector.observe(offset: 500, at: 1.9))
        detector.recordScrollWheel(deltaY: -1, at: 1.95)
        expectTrue(detector.observe(offset: 0, at: 2) != nil)
    }

    func testNestedScrollerTrackingEndsOnlyAfterOuterTrackingReturns() {
        var detector = ParentScrollJumpDetector()
        expectNil(detector.observe(offset: 2_000, at: 1))
        detector.beginScrollerTracking(at: 1.1)
        detector.beginScrollerTracking(at: 1.2)
        detector.endScrollerTracking(at: 1.3)
        expectNil(detector.observe(offset: 1_500, at: 2))
        detector.endScrollerTracking(at: 2.1)
        expectNil(detector.observe(offset: 1_000, at: 2.4))
        expectTrue(detector.observe(offset: 500, at: 2.46) != nil)
        // An unmatched end must not create a new grace period.
        detector.endScrollerTracking(at: 2.5)
        expectTrue(detector.observe(offset: 0, at: 2.6) != nil)
    }

    func testInvalidOrFutureScrollerInputAndClockRegressionDoNotHideJumps() {
        var detector = ParentScrollJumpDetector()
        expectNil(detector.observe(offset: 2_000, at: 10))
        detector.recordScrollerInteraction(at: .nan)
        detector.beginScrollerTracking(at: .infinity)
        detector.endScrollerTracking(at: .nan)
        expectTrue(detector.observe(offset: 1_500, at: 10.1) != nil)
        detector.recordScrollerInteraction(at: 11)
        expectTrue(detector.observe(offset: 1_000, at: 10.2) != nil)
        detector.beginScrollerTracking(at: 12)
        expectTrue(detector.observe(offset: 500, at: 10.3) != nil)
        // A regressing observation resets active tracking, grace and history.
        expectNil(detector.observe(offset: 2_000, at: 1))
        detector.endScrollerTracking(at: 1.1)
        expectTrue(detector.observe(offset: 0, at: 1.2) != nil)
    }

    func testGamesDownwardWheelReversalsRemainJumpsAfterScrollbarUse() {
        let reversals: [(Double, Double)] = [
            (6_046, 3_600.724074), (6_181.724074, 3_613.485363),
            (6_492.485363, 3_909.457674)
        ]
        for (before, after) in reversals {
            var detector = ParentScrollJumpDetector()
            detector.beginScrollerTracking(at: 1)
            detector.endScrollerTracking(at: 1.5)
            expectNil(detector.observe(offset: before, at: 2))
            detector.recordScrollWheel(deltaY: -24, at: 2.01)
            expectTrue(detector.observe(offset: after, at: 2.05) != nil)
        }
    }

    func testInvalidValuesAndClockRegressionDoNotInventJumps() {
        var detector = ParentScrollJumpDetector()
        expectNil(detector.observe(offset: 1_000, at: 10))
        expectNil(detector.observe(offset: .nan, at: 10.1))
        expectNil(detector.observe(offset: 500, at: .infinity))
        detector.recordScrollWheel(deltaY: .nan, at: 10.2)
        detector.recordScrollWheel(deltaY: 10, at: .nan)
        expectTrue(detector.observe(offset: 500, at: 10.3) != nil)
        expectNil(detector.observe(offset: 0, at: 1))
        expectNil(detector.observe(offset: 1_000, at: 2))
        detector.recordScrollWheel(deltaY: 10, at: 2.2)
        detector.recordScrollWheel(deltaY: -10, at: 2.1)
        expectNil(detector.observe(offset: 0, at: 2.3))
        // Future input cannot explain an earlier offset change.
        expectNil(detector.observe(offset: 1_000, at: 3))
        detector.recordScrollWheel(deltaY: 10, at: 4)
        expectTrue(detector.observe(offset: 0, at: 3.1) != nil)
    }

    func testJumpContainsTenBoundedPrecedingEventsWithTimes() {
        var detector = ParentScrollJumpDetector()
        expectNil(detector.observe(offset: 1_000, at: 0))
        for index in 1...12 { detector.recordEvent("event-\(index)", at: Double(index)) }
        let context = detector.observe(offset: 0, at: 13) ?? []
        expectEqual(context.count, 10)
        expectTrue(context.first?.contains("3.000 event-3") == true)
        expectTrue(context.last?.contains("12.000 event-12") == true)

        detector.recordEvent(String(repeating: "x", count: 20_000), at: 14)
        expectNil(detector.observe(offset: 1_000, at: 15))
        let bounded = detector.observe(offset: 0, at: 16) ?? []
        expectEqual(bounded.count, 10)
        expectTrue(bounded.allSatisfy { $0.count < 600 })
    }

    func testLogCreatesDirectoryAndAppendsSinglePhysicalLines() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("logs/parent-scroll.log")
        let log = ParentScrollLogFile(url: url)
        try log.append("first")
        try log.append("second\ncontinued\rreturn")
        expectEqual(try String(contentsOf: url, encoding: .utf8),
                    "first\nsecond\\ncontinued\\rreturn\n")
        expectFalse(FileManager.default.fileExists(atPath: log.rotatedURL.path))
    }

    func testRotationAtByteLimitKeepsOnlyOnePreviousFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("parent-scroll.log")
        let log = ParentScrollLogFile(url: url, maxBytes: 12)
        try log.append("12345")
        try log.append("67890")
        expectFalse(FileManager.default.fileExists(atPath: log.rotatedURL.path))
        try log.append("next")
        expectEqual(try String(contentsOf: log.rotatedURL, encoding: .utf8), "12345\n67890\n")
        expectEqual(try String(contentsOf: url, encoding: .utf8), "next\n")
        try log.append("last-12")
        expectEqual(try String(contentsOf: log.rotatedURL, encoding: .utf8), "next\n")
        expectEqual(try String(contentsOf: url, encoding: .utf8), "last-12\n")
        expectEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }

    func testReopenedLogCountsExistingBytesBeforeRotation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("parent-scroll.log")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("previous\n".utf8).write(to: url)
        let log = ParentScrollLogFile(url: url, maxBytes: 12)
        try log.append("new")
        expectEqual(try String(contentsOf: log.rotatedURL, encoding: .utf8), "previous\n")
        expectEqual(try String(contentsOf: url, encoding: .utf8), "new\n")
    }

    func testOversizedUnicodeLinesStayValidUTF8AndWithinCap() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("parent-scroll.log")
        let log = ParentScrollLogFile(url: url, maxBytes: 34)
        try log.append(String(repeating: "家", count: 100))
        let first = try Data(contentsOf: url)
        expectTrue(first.count <= 34)
        expectTrue(String(data: first, encoding: .utf8) != nil)
        expectTrue(String(data: first, encoding: .utf8)?.hasSuffix("[truncated]\n") == true)
        try log.append(String(repeating: "🙂", count: 100))
        expectTrue(try Data(contentsOf: url).count <= 34)
        expectTrue(try Data(contentsOf: log.rotatedURL).count <= 34)
        expectTrue(String(data: try Data(contentsOf: url), encoding: .utf8) != nil)
    }

    func testLogFailureIsReportedToCaller() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = ParentScrollLogFile(url: directory)
        expectThrowsError(try log.append("cannot append to a directory"))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("VisaGamesParentScroll-\(UUID().uuidString)", isDirectory: true)
    }
}
