import Foundation

/// Raw addresses captured synchronously on the observing thread. Symbolication
/// belongs to the log writer and happens only when a jump requests a block.
public struct ParentScrollStackSample: Sendable {
    public let time: TimeInterval
    public let detail: String
    public let addresses: [UInt]
}

/// Bounded diagnostic history; it never reads or changes a view or scroll state.
public struct ParentScrollStackHistory: Sendable {
    public static let maximumFrames = 96
    private let historyLimit: Int
    private let frameLimit: Int
    private let recentWindow: TimeInterval
    private let maxHeightCapturesPerSecond: Int
    private let jumpInterval: TimeInterval
    private var heights: [ParentScrollStackSample] = []
    private var heightCaptureTimes: [TimeInterval] = []
    private var lastHeightWasRateLimited = false
    private var lastTime: TimeInterval?
    private var lastJumpTime: TimeInterval?

    public init(historyLimit: Int = 8, frameLimit: Int = ParentScrollStackHistory.maximumFrames,
                recentWindow: TimeInterval = 2,
                maxHeightCapturesPerSecond: Int = 20,
                jumpInterval: TimeInterval = 1) {
        self.historyLimit = min(8, max(1, historyLimit))
        self.frameLimit = min(Self.maximumFrames, max(1, frameLimit))
        self.recentWindow = recentWindow.isFinite ? min(2, max(0, recentWindow)) : 2
        self.maxHeightCapturesPerSecond = min(20, max(1, maxHeightCapturesPerSecond))
        self.jumpInterval = jumpInterval.isFinite ? max(1, jumpInterval) : 1
    }

    public mutating func recordHeightChange(from: Double, to: Double,
                                            at time: TimeInterval, source: String,
                                            capture: () -> [UInt]) {
        guard from.isFinite, to.isFinite, from != to, accept(time: time) else { return }
        expire(at: time)
        let rateLimited = heightCaptureTimes.count >= maxHeightCapturesPerSecond
        let addresses: [UInt]
        if rateLimited {
            addresses = []
        } else {
            addresses = Array(capture().prefix(frameLimit))
            heightCaptureTimes.append(time)
        }
        let detail = "from=\(from) to=\(to) rateLimited=\(rateLimited) source=\(source)"
        let sample = ParentScrollStackSample(time: time, detail: Self.bounded(detail),
                                             addresses: addresses)
        // Keep the latest omitted event explicit without letting a tight burst
        // replace every earlier captured stack with empty placeholders.
        if rateLimited, lastHeightWasRateLimited, !heights.isEmpty {
            heights[heights.count - 1] = sample
        } else {
            heights.append(sample)
            if heights.count > historyLimit { heights.removeFirst(heights.count - historyLimit) }
        }
        lastHeightWasRateLimited = rateLimited
    }

    public mutating func takeJump(at time: TimeInterval, detail: String,
                                  capture: () -> [UInt])
        -> (jump: ParentScrollStackSample, heights: [ParentScrollStackSample])? {
        guard accept(time: time) else { return nil }
        expire(at: time)
        if let lastJumpTime, time - lastJumpTime < jumpInterval { return nil }
        lastJumpTime = time
        let jump = ParentScrollStackSample(time: time, detail: Self.bounded(detail),
                                            addresses: Array(capture().prefix(frameLimit)))
        return (jump: jump, heights: heights)
    }

    private mutating func accept(time: TimeInterval) -> Bool {
        guard time.isFinite else { return false }
        if let lastTime, time < lastTime {
            heights.removeAll(keepingCapacity: true)
            heightCaptureTimes.removeAll(keepingCapacity: true)
            lastHeightWasRateLimited = false
            lastJumpTime = nil
        }
        lastTime = time
        return true
    }

    private mutating func expire(at time: TimeInterval) {
        heights.removeAll { time - $0.time > recentWindow }
        heightCaptureTimes.removeAll { time - $0 >= 1 }
        if heights.isEmpty { lastHeightWasRateLimited = false }
    }

    private static func bounded(_ value: String) -> String {
        // Bound bytes rather than characters: one grapheme can contain an
        // arbitrarily large number of combining Unicode scalars.
        var bytes = Array(value.utf8.prefix(1_024))
        while !bytes.isEmpty {
            if let result = String(bytes: bytes, encoding: .utf8) { return result }
            bytes.removeLast()
            // A valid Swift String can be cut only within its final scalar.
        }
        return ""
    }
}
