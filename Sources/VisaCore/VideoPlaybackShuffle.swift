import Foundation

/// Child allowlist playback order: shuffle rather than fixed `videos.first` every visa.
/// Pure seam — no UI, no WebKit. Reshuffles when the deck is exhausted; avoids an
/// immediate repeat of the last played id when the allowlist has more than one video.
public struct VideoPlaybackShuffle: Sendable, Equatable, Codable {
    /// Remaining shuffled ids still to play before the next reshuffle.
    public private(set) var remainingIDs: [String]
    /// Last id handed to scoped playback (persisted so consecutive visas do not always restart the same clip).
    public private(set) var lastPlayedVideoID: String?

    public init(remainingIDs: [String] = [], lastPlayedVideoID: String? = nil) {
        self.remainingIDs = remainingIDs
        self.lastPlayedVideoID = lastPlayedVideoID
    }

    /// Next allowlisted id to play, or nil when the allowlist is empty.
    /// `allowlistIDs` should be the current parent order; membership is re-checked so removals drop stale queue entries.
    public mutating func nextVideoID(
        from allowlistIDs: [String],
        using rng: inout some RandomNumberGenerator
    ) -> String? {
        let live = Self.deduped(allowlistIDs)
        guard !live.isEmpty else {
            remainingIDs = []
            return nil
        }
        let liveSet = Set(live)
        remainingIDs = remainingIDs.filter { liveSet.contains($0) }
        if remainingIDs.isEmpty {
            remainingIDs = Self.shuffledDeck(from: live, avoidingImmediateRepeatOf: lastPlayedVideoID, using: &rng)
        }
        guard !remainingIDs.isEmpty else { return nil }
        let picked = remainingIDs.removeFirst()
        lastPlayedVideoID = picked
        return picked
    }

    /// Build a shuffled deck. When `count > 1` and the first draw would equal `lastPlayed`, rotate so it is not first.
    public static func shuffledDeck(
        from ids: [String],
        avoidingImmediateRepeatOf lastPlayed: String?,
        using rng: inout some RandomNumberGenerator
    ) -> [String] {
        var deck = deduped(ids)
        guard deck.count > 1 else { return deck }
        // Fisher–Yates
        for i in stride(from: deck.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0...i, using: &rng)
            deck.swapAt(i, j)
        }
        if let lastPlayed, deck.first == lastPlayed {
            // Move the immediate-repeat candidate off the front (swap with a later slot).
            let swapIndex = Int.random(in: 1..<deck.count, using: &rng)
            deck.swapAt(0, swapIndex)
        }
        return deck
    }

    private static func deduped(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in ids {
            let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !seen.contains(id) else { continue }
            seen.insert(id)
            result.append(id)
        }
        return result
    }
}

/// Persist shuffle cursor beside the allowlist (UserDefaults scaffold; not Snapshot schema).
public struct VideoPlaybackShuffleStore {
    public static let key = "VisaGames.videoPlaybackShuffle.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> VideoPlaybackShuffle {
        guard let data = defaults.data(forKey: Self.key) else { return VideoPlaybackShuffle() }
        return (try? JSONDecoder().decode(VideoPlaybackShuffle.self, from: data)) ?? VideoPlaybackShuffle()
    }

    public func save(_ state: VideoPlaybackShuffle) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// Deterministic RNG for offline VisaCoreChecks (not cryptographic).
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    public mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
