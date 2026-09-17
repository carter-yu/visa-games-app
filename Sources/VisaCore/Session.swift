import Foundation

public struct Snapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var configured: Bool
    public var endsAt: Date?

    public init(configured: Bool = false, endsAt: Date? = nil) {
        self.configured = configured
        self.endsAt = endsAt
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
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: url))
        guard snapshot.schemaVersion == 1 else { throw StoreError.unsupportedSchema }
        return snapshot
    }

    public func save(_ snapshot: Snapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }

    public enum StoreError: Error { case unsupportedSchema }
}
