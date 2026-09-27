import Foundation

public struct Snapshot: Codable, Equatable, Sendable {
    /// Current on-disk schema. v1 had configured + endsAt only; v2 adds optional reward state.
    public var schemaVersion = 2
    public var configured: Bool
    public var endsAt: Date?
    /// Durable reward/allowance state (ADR 0002). Nil means no reward ledger has been recorded yet.
    public var reward: RewardState?

    public init(configured: Bool = false, endsAt: Date? = nil, reward: RewardState? = nil) {
        self.schemaVersion = 2
        self.configured = configured
        self.endsAt = endsAt
        self.reward = reward
    }
}

public enum Mode: Sendable { case setup, lock, parent, play }

public struct Session: Sendable {
    public private(set) var snapshot: Snapshot
    public private(set) var mode: Mode
    public var allowsExit: Bool { mode == .parent }

    public func blocksKey(isEscape: Bool, hasCommand: Bool) -> Bool {
        !allowsExit && (isEscape || hasCommand)
    }

    public init(snapshot: Snapshot, now: Date) {
        self.snapshot = snapshot
        mode = .lock
        normalize(now: now)
    }

    private mutating func normalize(now: Date) {
        if !snapshot.configured || (snapshot.endsAt.map { $0 <= now } ?? false) {
            snapshot.endsAt = nil
        }
        if mode != .parent {
            mode = !snapshot.configured ? .setup : snapshot.endsAt == nil ? .lock : .play
        }
    }

    public mutating func tick(now: Date) { normalize(now: now) }

    public mutating func enterParent(authenticated: Bool, now: Date) {
        normalize(now: now)
        if authenticated { mode = .parent }
    }

    public mutating func completeSetup() {
        guard mode == .parent, !snapshot.configured else { return }
        snapshot.configured = true
        mode = .lock
    }

    public mutating func leaveParent(now: Date) {
        guard mode == .parent else { return }
        mode = .lock
        normalize(now: now)
    }

    public mutating func grant(seconds: TimeInterval, now: Date) {
        guard mode == .parent, snapshot.configured, seconds.isFinite,
              seconds > 0, seconds <= 3600 else { return }
        snapshot.endsAt = now.addingTimeInterval(seconds)
        mode = .play
    }

    /// Parent / persistence seam: replace durable reward state without touching endsAt.
    public mutating func replaceRewardState(_ reward: RewardState?) {
        snapshot.reward = reward
    }

    public func remaining(at now: Date) -> Int {
        guard let endsAt = snapshot.endsAt else { return 0 }
        return Int(min(3600, max(0, ceil(endsAt.timeIntervalSince(now)))))
    }
}

public struct SnapshotStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: url.path) else { return Snapshot() }
        let data = try Data(contentsOf: url)
        let header = try JSONDecoder().decode(SchemaHeader.self, from: data)
        switch header.schemaVersion {
        case 1:
            let legacy = try JSONDecoder().decode(SnapshotV1.self, from: data)
            // Migrate v1 → v2 in memory: preserve visa fields; no invented reward/allowance.
            return Snapshot(configured: legacy.configured, endsAt: legacy.endsAt, reward: nil)
        case 2:
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            guard snapshot.schemaVersion == 2 else { throw StoreError.unsupportedSchema }
            if let reward = snapshot.reward {
                try Self.validateRewardState(reward)
            }
            return snapshot
        default:
            throw StoreError.unsupportedSchema
        }
    }

    public func save(_ snapshot: Snapshot) throws {
        var toSave = snapshot
        toSave.schemaVersion = 2
        if let reward = toSave.reward {
            try Self.validateRewardState(reward)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(toSave).write(to: url, options: .atomic)
    }

    /// Fail closed on non-finite, negative, or otherwise unusable reward fields.
    public static func validateRewardState(_ state: RewardState) throws {
        let numericFields: [TimeInterval] = [
            state.initialAllowanceSeconds,
            state.rewardCapSeconds,
            state.viewingSeconds
        ]
        for value in numericFields {
            guard value.isFinite, value >= 0 else { throw StoreError.corruptState }
        }
        for id in state.awardedCompletionIDs {
            guard !id.isEmpty else { throw StoreError.corruptState }
        }
        for record in state.successRecords {
            guard !record.completionID.isEmpty,
                  record.awardedSeconds.isFinite,
                  record.awardedSeconds >= 0 else { throw StoreError.corruptState }
        }
    }

    public enum StoreError: Error {
        case unsupportedSchema
        case corruptState
    }

    private struct SchemaHeader: Codable {
        var schemaVersion: Int
    }

    /// Legacy on-disk shape before reward persistence (schemaVersion 1).
    private struct SnapshotV1: Codable {
        var schemaVersion: Int
        var configured: Bool
        var endsAt: Date?
    }
}
