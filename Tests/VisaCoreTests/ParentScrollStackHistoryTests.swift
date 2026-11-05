import Foundation
import VisaCore

final class ParentScrollStackHistoryTests {
    func testHeightStacksStayRawUntilJumpAndKeepOnlyRecentEntries() {
        var history = ParentScrollStackHistory()
        var captures = 0
        history.recordHeightChange(from: 100, to: 110, at: 1, source: "document") {
            captures += 1
            return [11, 12]
        }
        history.recordHeightChange(from: 110, to: 120, at: 2, source: "frame notification") {
            captures += 1
            return [21, 22]
        }
        expectEqual(captures, 2)
        let block = history.takeJump(at: 3.1, detail: "offset 900 -> 0") {
            captures += 1
            return [31, 32]
        }
        expectEqual(captures, 3)
        expectEqual(block?.jump.addresses, [31, 32])
        expectEqual(block?.heights.count, 1)
        expectEqual(block?.heights.first?.addresses, [21, 22])
        expectEqual(block?.heights.first?.time, 2)
        expectTrue(block?.heights.first?.detail.contains("from=110.0 to=120.0") == true)
        expectTrue(block?.heights.first?.detail.contains("source=frame notification") == true)
    }

    func testHistoryAndEveryStackHaveHardBounds() {
        var history = ParentScrollStackHistory(historyLimit: 1_000, frameLimit: 1_000,
                                              recentWindow: 1_000)
        for index in 0..<12 {
            history.recordHeightChange(from: Double(index), to: Double(index + 1),
                                       at: Double(index) * 0.1, source: "height") {
                Array(0..<UInt(200))
            }
        }
        let block = history.takeJump(at: 1.2, detail: "jump") { Array(0..<UInt(200)) }
        expectEqual(block?.heights.count, 8)
        expectEqual(block?.heights.first?.time, 0.4)
        expectTrue(block?.heights.allSatisfy { $0.addresses.count == 96 } == true)
        expectEqual(block?.jump.addresses.count, 96)
        expectEqual(block?.jump.addresses.last, 95)
        let expired = history.takeJump(at: 4, detail: "later jump") { [99] }
        expectEqual(expired?.heights.count, 0)
    }

    func testCaptureBudgetKeepsLatestHeightMetadataWithoutLosingPriorStacks() {
        var history = ParentScrollStackHistory()
        var captures = 0
        for index in 0..<100 {
            history.recordHeightChange(from: Double(index), to: Double(index + 1),
                                       at: Double(index) * 0.001, source: "burst") {
                captures += 1
                return [UInt(index)]
            }
        }
        expectEqual(captures, 20)
        let block = history.takeJump(at: 0.1, detail: "jump") { [123] }
        expectEqual(block?.heights.count, 8)
        expectEqual(block?.heights.last?.time, 0.099)
        expectEqual(block?.heights.last?.addresses, [])
        expectTrue(block?.heights.last?.detail.contains("from=99.0 to=100.0") == true)
        expectTrue(block?.heights.last?.detail.contains("rateLimited=true") == true)
        expectTrue(block?.heights.dropLast().allSatisfy { !$0.addresses.isEmpty } == true)
        history.recordHeightChange(from: 100, to: 101, at: 1, source: "next second") {
            captures += 1
            return [200]
        }
        expectEqual(captures, 21)
    }

    func testJumpCooldownDoesNotCaptureAndCannotBeConfiguredAway() {
        var history = ParentScrollStackHistory(jumpInterval: 0)
        var captures = 0
        expectTrue(history.takeJump(at: 1, detail: "first") {
            captures += 1
            return [1]
        } != nil)
        expectNil(history.takeJump(at: 1.99, detail: "suppressed") {
            captures += 1
            return [2]
        })
        expectEqual(captures, 1)
        expectTrue(history.takeJump(at: 2, detail: "next") {
            captures += 1
            return [3]
        } != nil)
        expectEqual(captures, 2)
    }

    func testInvalidValuesDoNotCaptureAndClockRegressionClearsHistoryAndCooldown() {
        var history = ParentScrollStackHistory()
        var captures = 0
        let capture: () -> [UInt] = { captures += 1; return [1] }
        history.recordHeightChange(from: .nan, to: 2, at: 1, source: "invalid", capture: capture)
        history.recordHeightChange(from: 1, to: .infinity, at: 1, source: "invalid", capture: capture)
        history.recordHeightChange(from: 1, to: 2, at: .nan, source: "invalid", capture: capture)
        history.recordHeightChange(from: 1, to: 1, at: 1, source: "unchanged", capture: capture)
        expectNil(history.takeJump(at: .infinity, detail: "invalid", capture: capture))
        expectEqual(captures, 0)
        history.recordHeightChange(from: 1, to: 2, at: 10, source: "old clock", capture: capture)
        expectTrue(history.takeJump(at: 10.1, detail: "old jump", capture: capture) != nil)
        let fresh = history.takeJump(at: 1, detail: "new clock", capture: capture)
        expectTrue(fresh != nil)
        expectEqual(fresh?.heights.count, 0)
        history.recordHeightChange(from: 2, to: 3, at: 0.5, source: "reset again", capture: capture)
        let reset = history.takeJump(at: 0.6, detail: "fresh", capture: capture)
        expectEqual(reset?.heights.count, 1)
        expectEqual(reset?.heights.first?.time, 0.5)
        expectEqual(captures, 5)
    }

    func testConfigurationAndUnicodeMetadataAreBounded() {
        var history = ParentScrollStackHistory(historyLimit: -1, frameLimit: -1,
                                              recentWindow: .nan,
                                              maxHeightCapturesPerSecond: -1,
                                              jumpInterval: .infinity)
        let source = String(repeating: "家🙂", count: 10_000)
        history.recordHeightChange(from: 1, to: 2, at: 1, source: source) { [1, 2, 3] }
        let block = history.takeJump(at: 1.1, detail: source) { [4, 5, 6] }
        expectEqual(block?.heights.count, 1)
        expectEqual(block?.heights.first?.addresses, [1])
        expectEqual(block?.jump.addresses, [4])
        expectTrue((block?.heights.first?.detail.utf8.count ?? 10_000) <= 1_024)
        expectTrue((block?.jump.detail.utf8.count ?? 10_000) <= 1_024)
        expectFalse(block?.jump.detail.contains("�") ?? true)
        // Invalid nonfinite intervals use finite defaults, not an infinite lockout.
        expectTrue(history.takeJump(at: 2.1, detail: "next") { [7] } != nil)
    }
}
