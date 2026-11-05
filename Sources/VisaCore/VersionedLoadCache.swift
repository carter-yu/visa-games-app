import Foundation

/// One cached value built by an asynchronous load, with explicit invalidation (build 78).
/// Used for the parent letter editor's bank + 90-day history snapshot: clearing performance
/// records or (un)excluding a session invalidates it, a load already in flight is then
/// dropped on arrival, and waiters still pending get a fresh load instead.
/// Not thread-safe: the host confines it to one actor (the app uses the main actor).
public struct VersionedLoadCache<Value, Waiter> {
    public private(set) var value: Value?
    public private(set) var generation = 0
    private var waiters: [Waiter] = []
    private var loading: Int?

    public init() {}

    public enum Request {
        /// Deliver this cached value to the waiter now.
        case cached(Value)
        /// Start a load and pass this token to `deliver`.
        case startLoad(token: Int)
        /// A current load is already running; the waiter is queued.
        case queued
    }

    public mutating func request(_ waiter: Waiter) -> Request {
        if let value { return .cached(value) }
        waiters.append(waiter)
        if loading == generation { return .queued }
        loading = generation
        return .startLoad(token: generation)
    }

    /// A finished load. Returns the waiters to call, or nil when the token is stale
    /// (the cache was invalidated or reset while it ran).
    public mutating func deliver(_ loaded: Value, token: Int) -> [Waiter]? {
        guard token == generation, loading == token else { return nil }
        loading = nil
        value = loaded
        let ready = waiters
        waiters = []
        return ready
    }

    /// The source data changed. Drops the value and any in-flight result. When waiters are
    /// still pending, returns a new token: the host must start a fresh load for them.
    public mutating func invalidate() -> Int? {
        generation &+= 1
        value = nil
        loading = nil
        guard !waiters.isEmpty else { return nil }
        loading = generation
        return generation
    }

    /// Leaving the parent page: drop everything, including pending waiters.
    public mutating func reset() {
        generation &+= 1
        value = nil
        loading = nil
        waiters = []
    }
}
