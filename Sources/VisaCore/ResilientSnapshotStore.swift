import Foundation

/// v0.21.4: a failed `state.json` write must never block daily use (Carter 2026-10-11).
/// The in-memory snapshot is always authoritative; failed writes stay pending and are
/// retried. Callers show a parent-only banner while `isDegraded`.
public final class ResilientSnapshotStore: @unchecked Sendable {
    public typealias Writer = (Snapshot) throws -> Void

    private let writer: Writer
    public private(set) var pending: Snapshot?
    public private(set) var lastError: String?
    public private(set) var consecutiveFailures = 0
    public private(set) var lastAttempt: Date?
    public static let retryInterval: TimeInterval = 15

    public init(writer: @escaping Writer) { self.writer = writer }

    public var isDegraded: Bool { pending != nil }

    public enum Outcome: Equatable, Sendable {
        case saved
        /// Write failed; snapshot kept in memory and queued for retry.
        case queued(error: String)
        /// Earlier failure cleared by this successful write.
        case recovered
    }

    /// Persist `snapshot`. Never throws; the caller always keeps `snapshot` in memory.
    @discardableResult
    public func commit(_ snapshot: Snapshot, now: Date = Date()) -> Outcome {
        lastAttempt = now
        do {
            try writer(snapshot)
            let wasDegraded = isDegraded
            pending = nil
            lastError = nil
            consecutiveFailures = 0
            return wasDegraded ? .recovered : .saved
        } catch {
            pending = snapshot
            consecutiveFailures += 1
            lastError = Self.describe(error)
            return .queued(error: lastError ?? "unknown")
        }
    }

    /// Retry the newest pending snapshot when due. Returns nil when nothing was attempted.
    @discardableResult
    public func retryIfDue(now: Date = Date()) -> Outcome? {
        guard let pending else { return nil }
        if let last = lastAttempt, now.timeIntervalSince(last) < Self.retryInterval { return nil }
        return commit(pending, now: now)
    }

    public static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var parts = ["\(ns.domain)#\(ns.code)"]
        if let path = ns.userInfo[NSFilePathErrorKey] as? String { parts.append("path=\(path)") }
        if let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("under=\(under.domain)#\(under.code)")
        }
        parts.append(ns.localizedDescription)
        return String(parts.joined(separator: " ").prefix(300))
    }
}
