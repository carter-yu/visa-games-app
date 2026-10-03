import Foundation

/// Carter Confirmed 2026-10-02: visa durations are 5 / 10 / 15 minutes (supersedes 2026-09-27 10/20/30 scaffold).
public enum ChildDifficulty: Int, CaseIterable, Sendable, Hashable {
    case easy = 1, medium = 2, challenge = 3

    public var minutes: Int { rawValue * 5 }
    public var seconds: TimeInterval { TimeInterval(minutes * 60) }
}
