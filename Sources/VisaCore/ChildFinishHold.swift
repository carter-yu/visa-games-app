import Foundation

/// A child round's delayed finish (Hanzi H2: the find's plaque stroke reveal, then the stamp) can come due while
/// parent controls are open. The stamp cannot start a visa there (`Session.startPlayVisa` needs the lock), so
/// finishing would save the round and leave it completed, taking no taps, with no visa. AppModel asks this hold
/// first: outside the lock the finish is held for its round, and Return to the child lock releases it once while
/// that round is still the open one. A reset or a new round drops it. Only the Hanzi find uses it so far.
public struct ChildFinishHold: Equatable, Sendable {
    /// The held round's deal seed; nil when nothing is held.
    public private(set) var round: String?

    public init() {}

    /// `round`'s finish is due. In the child lock it finishes now (true) and nothing stays held; in any other mode
    /// it is held (false) until `release`.
    public mutating func finishesNow(_ round: String, mode: Mode) -> Bool {
        guard mode == .lock else {
            self.round = round
            return false
        }
        self.round = nil
        return true
    }

    /// Return to the child. In the lock: the held round, once, if it is still `openRound` (any other held round is
    /// dropped). Outside the lock (Return into a running visa) nothing is released and the hold stays until a reset.
    public mutating func release(openRound: String?, mode: Mode) -> String? {
        guard mode == .lock, let held = round else { return nil }
        round = nil
        return held == openRound ? held : nil
    }

    /// The round was reset or replaced: nothing finishes on Return.
    public mutating func drop() { round = nil }
}
