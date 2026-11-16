import Foundation

// patterns-sorting P0 (design §5.7, T13): the 邊個唔同類 round board and the after-pause step the three quiz boards
// share. Modelled on `TapLetterBoard`: found answers stay found, a known-wrong choice never costs again, a second tap
// on the same target within 0.4 s is ignored. Fuel, the Think Pause clock and rewards stay with AppModel.

/// What a board does when its Think Pause ends (design §5.7 "After-pause step").
public enum BoardAfterPause: String, Sendable, Equatable {
    /// Misses reached the deal's threshold and the hint was off: it lights the answer and stays on (assisted).
    case hint
    /// The prompt shows again.
    case tryAgain
    /// A stale call: no pause pending, another miss number, a completed board, or not the lane's current board.
    case ignored
}

/// The miss count, the pending pause and the hint of one quiz board.
public struct BoardPauseState: Sendable, Equatable {
    /// 1 at 多啲, 2 at 標準 and 少啲 (`PatternSortHelp.hintThreshold`), fixed at deal.
    public let hintThreshold: Int
    public private(set) var misses = 0
    /// The miss number whose Think Pause has not ended yet.
    public private(set) var pendingMiss: Int?
    public private(set) var hintOn = false

    public init(hintThreshold: Int) { self.hintThreshold = max(1, hintThreshold) }

    public var pausePending: Bool { pendingMiss != nil }

    mutating func noteMiss() {
        misses += 1
        pendingMiss = misses
    }

    /// Runs once per pause, for the miss that started it.
    mutating func afterPause(miss: Int, complete: Bool) -> BoardAfterPause {
        guard !complete, let pending = pendingMiss, pending == miss else { return .ignored }
        pendingMiss = nil
        if !hintOn && misses >= hintThreshold {
            hintOn = true
            return .hint
        }
        return .tryAgain
    }
}

/// The 0.6 s between a new wrong card and its miss (design §5.7: the line first, then `handleEvaluation` /
/// `playtestHandle`), bound to its lane and deal (astra R2). While one waits, only that lane's board on that deal takes
/// no tap, replay or idle nudge. The delayed callback applies the miss only for the lane's current ticket while that
/// deal is still the lane's open deal, and clears its own ticket either way, so a dropped, replaced or stale callback
/// applies, clears and blocks nothing — in its own lane, on a newer deal or in the other lane.
public struct BoardPendingMiss: Sendable, Equatable {
    public struct Ticket: Sendable, Equatable {
        public let lane: RoundRevealLane
        public let deal: String
        public let serial: Int
    }

    private var tickets: [RoundRevealLane: Ticket] = [:]
    private var serial = 0

    public init() {}

    /// No miss waits in either lane.
    public var isEmpty: Bool { tickets.isEmpty }

    /// A new wrong card in `lane` on `deal`: its miss waits for the callback.
    public mutating func begin(lane: RoundRevealLane, deal: String) -> Ticket {
        serial += 1
        let ticket = Ticket(lane: lane, deal: deal, serial: serial)
        tickets[lane] = ticket
        return ticket
    }

    /// The lane's board on `deal` waits for its miss.
    public func isPending(lane: RoundRevealLane, deal: String) -> Bool {
        tickets[lane]?.deal == deal
    }

    /// The delayed callback, with the lane's open deal now: true = apply the miss. A ticket that is no longer the
    /// lane's (dropped or replaced) does nothing; the lane's own ticket is cleared whether or not its deal is still open.
    public mutating func settle(_ ticket: Ticket, openDeal: String) -> Bool {
        guard tickets[ticket.lane] == ticket else { return false }
        tickets[ticket.lane] = nil
        return openDeal == ticket.deal
    }

    /// The lane's round goes (a new deal, a reset, a discarded or restarted 試玩): its waiting miss goes with it. The
    /// other lane keeps its own.
    public mutating func drop(lane: RoundRevealLane) {
        tickets[lane] = nil
    }
}

/// The 0.4 s same-target guard (design D9).
public enum PatternSortTiming {
    public static let doubleTap: TimeInterval = 0.4
}

public enum OddOneOutTap: String, Sendable, Equatable {
    case correct, miss, knownWrongRetap, doubleTapIgnored, ignored
}

/// One 邊個唔同類 round (design §5.7 table).
public struct OddOneOutBoard: Sendable, Equatable {
    public let question: OddOneOutQuestion
    /// The lane's deal seed this board was dealt for.
    public let deal: String
    /// 分類設定's 分類方法 when it was dealt (not a fallback's 形狀): the ladder records the round at `question.step`
    /// under these, whatever the parent changes before it ends (design §5.3, astra R1).
    public let methods: Set<PatternSortMethod>
    public private(set) var pause: BoardPauseState
    public private(set) var knownWrong: Set<Int> = []
    public private(set) var isComplete = false
    public private(set) var tapOrder: [Int] = []
    public private(set) var lastTapCard: Int?
    public private(set) var lastTapAt: TimeInterval = -.infinity

    public init(question: OddOneOutQuestion, deal: String, guidance: TapCountGuidanceLevel,
                methods: Set<PatternSortMethod>) {
        self.question = question
        self.deal = deal
        self.methods = methods
        pause = BoardPauseState(hintThreshold: PatternSortHelp.hintThreshold(guidance))
    }

    public var misses: Int { pause.misses }
    public var hintOn: Bool { pause.hintOn }
    /// A success after the hint counts as assisted.
    public var assisted: Bool { pause.hintOn }
    public var firstTry: Bool { isComplete && pause.misses == 0 }
    /// The card the hint lights (the answer), while the hint is on.
    public var hintCard: Int? { pause.hintOn ? question.answer : nil }

    /// A new wrong card is a miss and leaves a pause pending; a known-wrong card is never a miss again, before or after
    /// any pause; while a pause is pending every tap is ignored; `correct` fires once; every later tap is ignored.
    public mutating func tap(_ card: Int, at time: TimeInterval) -> OddOneOutTap {
        guard question.cards.indices.contains(card), !isComplete else { return .ignored }
        guard !pause.pausePending else { return .ignored }
        if lastTapCard == card && time - lastTapAt < PatternSortTiming.doubleTap { return .doubleTapIgnored }
        lastTapCard = card
        lastTapAt = time
        if knownWrong.contains(card) { return .knownWrongRetap }
        tapOrder.append(card)
        if card == question.answer {
            isComplete = true
            return .correct
        }
        knownWrong.insert(card)
        pause.noteMiss()
        return .miss
    }

    /// The end of the Think Pause that miss number `miss` started, for the lane whose deal is `currentDeal`.
    public mutating func afterPause(miss: Int, currentDeal: String) -> BoardAfterPause {
        guard currentDeal == deal else { return .ignored }
        return pause.afterPause(miss: miss, complete: isComplete)
    }
}
