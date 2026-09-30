import Foundation

public struct PenSparkPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Where the pen glow is and whether it shows. The glow follows the pen while it hovers
/// (when the tablet reports hover) and otherwise appears on touch-down. It never blocks input.
public struct PenSparkState: Equatable, Sendable {
    public static let idleHideSeconds: Double = 2.5

    public private(set) var position: PenSparkPoint?
    public private(set) var isVisible = false
    public private(set) var inProximity = false
    /// Evidence for the hover question: a buttonless move arrived while the pen was in proximity.
    public private(set) var hoverObserved = false
    private var hoverSeenThisApproach = false
    private var lastActivity: Date?

    public init() {}

    public mutating func proximity(entering: Bool, now: Date) {
        inProximity = entering
        hoverSeenThisApproach = false
        lastActivity = now
        if !entering { isVisible = false }
    }

    /// Pointer moved with no button down. Returns true the first time pen hover is seen in one approach.
    @discardableResult
    public mutating func hover(x: Double, y: Double, now: Date) -> Bool {
        show(x: x, y: y, now: now)
        guard inProximity, !hoverSeenThisApproach else { return false }
        hoverSeenThisApproach = true
        hoverObserved = true
        return true
    }

    public mutating func touch(x: Double, y: Double, now: Date) {
        show(x: x, y: y, now: now)
    }

    public mutating func lift(x: Double, y: Double, now: Date) {
        show(x: x, y: y, now: now)
    }

    public mutating func tick(now: Date) {
        guard isVisible, let lastActivity, now.timeIntervalSince(lastActivity) > Self.idleHideSeconds else { return }
        isVisible = false
    }

    private mutating func show(x: Double, y: Double, now: Date) {
        position = PenSparkPoint(x: x, y: y)
        isVisible = true
        lastActivity = now
    }
}
