import Foundation

// patterns-sorting P0 (design §5.7 "Finish: reveal, then stamp", T16): a solved round first plays its reveal (the
// explain line, the readback) and only then stamps, exactly once. The deal seed keys the board, the reveal, the stamp,
// the hold and the release; parent entry never changes it. A separate speech generation keys speech only, and a cancel
// is never an end. Parent entry holds a revealing round at once (`enterParent()`, before any speech stops), through the
// unchanged `ChildFinishHold`, and Return releases it once, in the lock, for the same open deal.

public enum RoundRevealLane: String, Sendable, Equatable {
    /// The child's lane: stamps in the lock, holds outside it.
    case child
    /// A parent 試玩: finishes locally (no visa) and never holds; it never touches the child's reveal.
    case playtest
}

public enum RoundRevealOutcome: Sendable, Equatable {
    /// Stamp now (`applyEntrySuccess`), once, for this deal.
    case stamp(String)
    /// The playtest's local completion (no visa).
    case finishLocally(String)
    /// Held for Return (outside the lock).
    case held
    case ignored
}

public struct RoundReveal: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle
        case revealing(deal: String, generation: Int)
        case held(deal: String)
        case stamped(deal: String)
    }

    public let lane: RoundRevealLane
    public private(set) var phase: Phase = .idle
    public private(set) var hold = ChildFinishHold()

    public init(lane: RoundRevealLane) { self.lane = lane }

    public var isRevealing: Bool { if case .revealing = phase { return true } else { return false } }
    /// The deal whose reveal is on (revealing or held): the board ignores every tap while it is set.
    public var activeDeal: String? {
        switch phase {
        case .revealing(let deal, _), .held(let deal): return deal
        case .idle, .stamped: return nil
        }
    }

    /// The board returned `correct` / `complete` (once): the reveal starts on `deal` and a fresh speech generation.
    @discardableResult
    public mutating func begin(deal: String, generation: Int) -> Bool {
        guard phase == .idle, !deal.isEmpty else { return false }
        phase = .revealing(deal: deal, generation: generation)
        return true
    }

    /// The reveal's sequence ended. Only the current deal and generation count (`currentGeneration` is the lane's
    /// speech generation now: a cancel bumped it, so an old sequence's end does nothing).
    public mutating func sequenceEnded(deal: String, generation: Int, currentGeneration: Int, mode: Mode) -> RoundRevealOutcome {
        guard case .revealing(let open, let own) = phase, open == deal, own == generation,
              generation == currentGeneration else { return .ignored }
        return end(deal, mode: mode)
    }

    /// The reveal's deadline (silent length + 4 s), keyed by its deal only.
    public mutating func deadline(deal: String, mode: Mode) -> RoundRevealOutcome {
        guard case .revealing(let open, _) = phase, open == deal else { return .ignored }
        return end(deal, mode: mode)
    }

    /// `didCancel`, a stopped clip or a dropped beat: the light clears (the cursor's job); the round stays revealing.
    public func cancelled(deal: String, generation: Int) -> RoundRevealOutcome { .ignored }

    /// The first new step of parent entry, before speech stops and before the mode changes: a revealing child round
    /// is held for its own deal, recorded as finishing under the mode being entered (`.parent`).
    public mutating func enterParent() {
        guard lane == .child, case .revealing(let deal, _) = phase else { return }
        _ = hold.finishesNow(deal, mode: .parent)
        phase = .held(deal: deal)
    }

    /// Last in Return: in the lock, for the same open deal, the held round stamps once; another deal or none drops the
    /// hold; outside the lock (Return into a running test visa) it stays held until a reset.
    public mutating func returnToChild(openDeal: String?, mode: Mode) -> RoundRevealOutcome {
        guard case .held = phase else { return .ignored }
        if let deal = hold.release(openRound: openDeal, mode: mode) {
            phase = .stamped(deal: deal)
            return .stamp(deal)
        }
        if mode == .lock { phase = .idle }
        return .ignored
    }

    /// A new deal or a reset (`resetTaskRound`): back to idle, any hold dropped.
    public mutating func reset() {
        phase = .idle
        hold.drop()
    }

    private mutating func end(_ deal: String, mode: Mode) -> RoundRevealOutcome {
        switch lane {
        case .playtest:
            phase = .stamped(deal: deal)
            return .finishLocally(deal)
        case .child:
            if hold.finishesNow(deal, mode: mode) {
                phase = .stamped(deal: deal)
                return .stamp(deal)
            }
            phase = .held(deal: deal)
            return .held
        }
    }
}
