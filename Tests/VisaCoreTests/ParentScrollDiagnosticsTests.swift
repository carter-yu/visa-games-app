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
