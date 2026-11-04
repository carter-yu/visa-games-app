import Foundation

/// Observes top-relative offsets without changing scrolling. Times must use one
/// monotonic clock (the app uses system uptime). Create a detector per scroll view.
public struct ParentScrollJumpDetector: Sendable {
    private let jumpThreshold: Double
    private let upwardWheelWindow: TimeInterval
    private let scrollerInputWindow: TimeInterval
    private let contextLimit: Int
    private var previousOffset: Double?
    private var previousObservationTime: TimeInterval?
    private var lastWheel: (deltaY: Double, time: TimeInterval)?
    private var lastScrollerInteraction: TimeInterval?
    private var scrollerTrackingStartedAt: TimeInterval?
    private var scrollerTrackingDepth = 0
    private var context: [String] = []

    public init(jumpThreshold: Double = 200, upwardWheelWindow: TimeInterval = 0.35,
                contextLimit: Int = 10, scrollerInputWindow: TimeInterval = 0.35) {
        self.jumpThreshold = jumpThreshold.isFinite ? max(0, jumpThreshold) : 200
        self.upwardWheelWindow = upwardWheelWindow.isFinite ? max(0, upwardWheelWindow) : 0.35
        self.scrollerInputWindow = scrollerInputWindow.isFinite ? max(0, scrollerInputWindow) : 0.35
        self.contextLimit = min(100, max(1, contextLimit))
    }

    public mutating func recordEvent(_ description: String, at time: TimeInterval) {
        guard time.isFinite else { return }
        // Bound each entry as well as the count; callers pass event metadata only.
        let bounded = String(description.prefix(512))
        context.append(String(format: "%.3f", time) + " " + bounded)
        if context.count > contextLimit { context.removeFirst(context.count - contextLimit) }
    }

    /// NSEvent.scrollingDeltaY > 0 requests movement toward the document top.
    /// Zero-delta phase-ending events do not cancel that direction. Keep the most
    /// recent nonzero input so a newer downward wheel cannot hide a reset.
    public mutating func recordScrollWheel(deltaY: Double, at time: TimeInterval) {
        guard deltaY.isFinite, time.isFinite else { return }
        recordEvent("wheel deltaY=\(deltaY)", at: time)
        guard deltaY != 0, time >= (lastWheel?.time ?? -Double.infinity) else { return }
        lastWheel = (deltaY, time)
    }

    /// Call only for a mouse-down/drag hit-tested to this scroll view's scroller.
    /// A mouse event elsewhere in the document does not establish scroll intent.
    public mutating func recordScrollerInteraction(at time: TimeInterval) {
        guard time.isFinite, time >= (lastScrollerInteraction ?? -Double.infinity) else { return }
        lastScrollerInteraction = time
        recordEvent("scroller interaction", at: time)
    }

    /// Brackets the actual native scroller tracking call. AppKit can consume
    /// subsequent drag/up events inside that call without invoking local monitors.
    /// Nesting supports inherited method hooks that forward to another hooked
    /// implementation; tracking ends only after the outermost call returns.
    public mutating func beginScrollerTracking(at time: TimeInterval) {
        guard time.isFinite, scrollerTrackingDepth < Int.max else { return }
        if scrollerTrackingDepth == 0 { scrollerTrackingStartedAt = time }
        scrollerTrackingDepth += 1
        recordScrollerInteraction(at: time)
        recordEvent("scroller tracking begin depth=\(scrollerTrackingDepth)", at: time)
    }

    public mutating func endScrollerTracking(at time: TimeInterval) {
        guard time.isFinite, scrollerTrackingDepth > 0,
              time >= (scrollerTrackingStartedAt ?? time) else { return }
        scrollerTrackingDepth -= 1
        recordEvent("scroller tracking end depth=\(scrollerTrackingDepth)", at: time)
        if scrollerTrackingDepth == 0 {
            scrollerTrackingStartedAt = nil
            recordScrollerInteraction(at: time)
        }
    }

    /// Returns the preceding bounded context only for an unexplained decrease
    /// greater than the threshold. The caller logs JUMP with old/new geometry.
    /// Every bounds notification must reach this method, even if normal log lines
    /// are throttled, so a large change cannot be lost between samples.
    public mutating func observe(offset: Double, at time: TimeInterval) -> [String]? {
        guard offset.isFinite, time.isFinite else { return nil }
        if let previousTime = previousObservationTime, time < previousTime {
            previousOffset = nil
            lastWheel = nil
            lastScrollerInteraction = nil
            scrollerTrackingStartedAt = nil
            scrollerTrackingDepth = 0
            context.removeAll(keepingCapacity: true)
        }
        let upwardAge = lastWheel.map { time - $0.time }
        let hasRecentUpwardInput = lastWheel.map { $0.deltaY > 0 } == true
            && upwardAge.map { $0 >= 0 && $0 <= upwardWheelWindow } == true
        let scrollerAge = lastScrollerInteraction.map { time - $0 }
        let hasNewerDownwardWheel = lastWheel.map {
            $0.deltaY < 0 && $0.time <= time && $0.time >= (lastScrollerInteraction ?? .infinity)
        } == true
        let hasRecentScrollerInput = scrollerAge.map { $0 >= 0 && $0 <= scrollerInputWindow } == true
            && !hasNewerDownwardWheel
        let isTrackingScroller = scrollerTrackingDepth > 0
            && scrollerTrackingStartedAt.map { time >= $0 } == true
        let jumped = previousOffset.map { $0 - offset > jumpThreshold } == true
            && !hasRecentUpwardInput && !hasRecentScrollerInput && !isTrackingScroller
        let precedingContext = jumped ? context : nil
        previousOffset = offset
        previousObservationTime = time
        recordEvent("offset=\(offset)", at: time)
        return precedingContext
    }
}

/// Small append-only diagnostic sink with one rotated sibling, `parent-scroll.log.1`.
/// Initialization performs no I/O and may precede publication to a logging queue.
/// The caller must serialize append calls and close the final handle off the UI
/// event path by releasing the last reference on that queue. This class does not
/// synchronize or fsync each record; diagnostics are best effort, not state.
public final class ParentScrollLogFile {
    public let url: URL
    public var rotatedURL: URL { url.appendingPathExtension("1") }
    private let maxBytes: Int
    private var handle: FileHandle?
    private var byteCount = 0

    public init(url: URL, maxBytes: Int = 1_048_576) {
        self.url = url
        self.maxBytes = max(1, maxBytes)
    }

    deinit { try? handle?.close() }

    public func append(_ line: String) throws {
        let data = boundedLine(line)
        do {
            try openIfNeeded()
            if byteCount > 0 && byteCount > maxBytes - data.count {
                try rotate()
                try openIfNeeded()
            }
            try handle?.write(contentsOf: data)
            byteCount += data.count
        } catch {
            // Reopen and recalculate the actual size after a partial write/failure.
            try? handle?.close()
            handle = nil
            throw error
        }
    }

    private func openIfNeeded() throws {
        guard handle == nil else { return }
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: url.path) {
            guard manager.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        let opened = try FileHandle(forWritingTo: url)
        do {
            let size = try opened.seekToEnd()
            byteCount = Int(min(size, UInt64(Int.max)))
            handle = opened
        } catch {
            try? opened.close()
            throw error
        }
    }

    private func rotate() throws {
        try handle?.close()
        handle = nil
        let manager = FileManager.default
        if manager.fileExists(atPath: rotatedURL.path) { try manager.removeItem(at: rotatedURL) }
        try manager.moveItem(at: url, to: rotatedURL)
        byteCount = 0
    }

    private func boundedLine(_ line: String) -> Data {
        let limit = min(maxBytes, 8_192)
        let escaped = String(line.prefix(limit)).replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        var bytes = Data(escaped.utf8)
        if bytes.count >= limit {
            let marker = Data("[truncated]".utf8)
            let suffix = marker.count < limit ? marker : Data()
            bytes = Data(bytes.prefix(limit - suffix.count - 1))
            // At most three bytes need removing when a UTF-8 scalar was split.
            while String(data: bytes, encoding: .utf8) == nil { bytes.removeLast() }
            bytes.append(suffix)
        }
        bytes.append(0x0A)
        return bytes
    }
}
