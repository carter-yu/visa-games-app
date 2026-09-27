import Foundation

/// Carter Confirmed 2026-09-27: scaffold visa durations are 10 / 20 / 30 minutes.
public enum ChildDifficulty: Int, CaseIterable, Sendable {
    case easy = 1, medium = 2, challenge = 3

    public var minutes: Int { rawValue * 10 }
    public var seconds: TimeInterval { TimeInterval(minutes * 60) }
}
