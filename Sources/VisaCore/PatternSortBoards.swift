import Foundation

// patterns-sorting P0 (design §5.7, T13): the round boards of 接落去, 分車房 and 自己排. Their UI slices are P2, P4
// and P5; P0 pins the contract. The after-pause step is `BoardPauseState` (`OddOneOutBoard.swift`).

public enum PatternRoundTap: String, Sendable, Equatable {
    case filled, complete, miss, knownWrongRetap, doubleTapIgnored, ignored
}

/// 接落去: blanks fill left to right; a right answer stays for the rest of the round (the letter board's rule, not the
/// convoy's reset); a wrong choice is a miss only the first time for that blank.
public struct PatternRound: Sendable, Equatable {
    public let question: PatternQuestion
    public let deal: String
    public private(set) var pause: BoardPauseState
    /// The choice placed in each filled blank, left to right.
    public private(set) var filled: [Int] = []
    /// Known-wrong choices per blank.
    public private(set) var knownWrong: [Set<Int>]
    public private(set) var isComplete = false
    public private(set) var lastTapChoice: Int?
    public private(set) var lastTapAt: TimeInterval = -.infinity

    public init(question: PatternQuestion, deal: String, guidance: TapCountGuidanceLevel) {
        self.question = question
        self.deal = deal
        pause = BoardPauseState(hintThreshold: PatternSortHelp.hintThreshold(guidance))
        knownWrong = Array(repeating: [], count: question.row.blanks.count)
    }

    public var misses: Int { pause.misses }
    public var assisted: Bool { pause.hintOn }
    public var firstTry: Bool { isComplete && pause.misses == 0 }
    /// The blank now judged (index into `question.row.blanks`).
    public var currentBlank: Int? { filled.count < question.row.blanks.count ? filled.count : nil }
    /// The choice the hint lights for the current blank.
    public var hintChoice: Int? {
        guard pause.hintOn, let blank = currentBlank else { return nil }
        return question.answers[blank]
    }

    public mutating func tap(choice: Int, at time: TimeInterval) -> PatternRoundTap {
        guard question.choices.indices.contains(choice), !isComplete, let blank = currentBlank else { return .ignored }
        guard !pause.pausePending else { return .ignored }
        if lastTapChoice == choice && time - lastTapAt < PatternSortTiming.doubleTap { return .doubleTapIgnored }
        lastTapChoice = choice
        lastTapAt = time
        if knownWrong[blank].contains(choice) { return .knownWrongRetap }
        if choice == question.answers[blank] {
            filled.append(choice)
            if filled.count == question.row.blanks.count {
                isComplete = true
                return .complete
            }
            return .filled
        }
        knownWrong[blank].insert(choice)
        pause.noteMiss()
        return .miss
    }

    public mutating func afterPause(miss: Int, currentDeal: String) -> BoardAfterPause {
        guard currentDeal == deal else { return .ignored }
        return pause.afterPause(miss: miss, complete: isComplete)
    }
}

public enum SortGaragesTap: String, Sendable, Equatable {
    case parked, complete, miss, knownWrongRetap, doubleTapIgnored, ignored
}

/// 分車房: only the front vehicle is judged; a drag-drop calls the same function; known-wrong is per vehicle and starts
/// empty for the next one; once the hint is on it stays on for every later vehicle.
public struct SortGaragesBoard: Sendable, Equatable {
    public let question: SortGaragesQuestion
    public let deal: String
    public private(set) var pause: BoardPauseState
    /// The garage each parked vehicle went into, front first.
    public private(set) var placed: [Int] = []
    /// Known-wrong garages of the front vehicle.
    public private(set) var knownWrong: Set<Int> = []
    public private(set) var isComplete = false
    public private(set) var lastTapGarage: Int?
    public private(set) var lastTapAt: TimeInterval = -.infinity

    public init(question: SortGaragesQuestion, deal: String, guidance: TapCountGuidanceLevel) {
        self.question = question
        self.deal = deal
        pause = BoardPauseState(hintThreshold: PatternSortHelp.hintThreshold(guidance))
    }

    public var misses: Int { pause.misses }
    public var assisted: Bool { pause.hintOn }
    public var firstTry: Bool { isComplete && pause.misses == 0 }
    /// The queue index of the vehicle at the junction.
    public var front: Int? { placed.count < question.queue.count ? placed.count : nil }
    /// The garage the hint lights for the front vehicle (on for every later vehicle once shown).
    public var hintGarage: Int? {
        guard pause.hintOn, let front else { return nil }
        return question.garages[front]
    }

    /// A tap on a garage, or a drag of the front vehicle dropped on it (the same choice).
    public mutating func choose(garage: Int, at time: TimeInterval) -> SortGaragesTap {
        guard (0..<2).contains(garage), !isComplete, let front else { return .ignored }
        guard !pause.pausePending else { return .ignored }
        if lastTapGarage == garage && time - lastTapAt < PatternSortTiming.doubleTap { return .doubleTapIgnored }
        lastTapGarage = garage
        lastTapAt = time
        if knownWrong.contains(garage) { return .knownWrongRetap }
        if garage == question.garages[front] {
            placed.append(garage)
            knownWrong = []
            if placed.count == question.queue.count {
                isComplete = true
                return .complete
            }
            return .parked
        }
        knownWrong.insert(garage)
        pause.noteMiss()
        return .miss
    }

    public mutating func afterPause(miss: Int, currentDeal: String) -> BoardAfterPause {
        guard currentDeal == deal else { return .ignored }
        return pause.afterPause(miss: miss, complete: isComplete)
    }
}

public enum PatternMakeTap: String, Sendable, Equatable {
    case placed, undone, complete, ignored
}

/// 自己排 (practice, never wrong): pieces fill slots 1–8; 退返一格 works with 1–7 placed; the 8th piece completes the
/// board once, then place and undo are ignored.
public struct PatternMakeBoard: Sendable, Equatable {
    public let palette: PatternMakePalette
    public let deal: String
    /// Palette index of each placed piece, slot 1 first.
    public private(set) var placed: [Int] = []
    public private(set) var undos = 0
    public private(set) var isComplete = false

    public init(palette: PatternMakePalette, deal: String) {
        self.palette = palette
        self.deal = deal
    }

    public mutating func place(_ piece: Int) -> PatternMakeTap {
        guard palette.pieces.indices.contains(piece), !isComplete, placed.count < PatternMakeGenerator.slots else {
            return .ignored
        }
        placed.append(piece)
        if placed.count == PatternMakeGenerator.slots {
            isComplete = true
            return .complete
        }
        return .placed
    }

    public mutating func undo() -> PatternMakeTap {
        guard !isComplete, (1..<PatternMakeGenerator.slots).contains(placed.count) else { return .ignored }
        placed.removeLast()
        undos += 1
        return .undone
    }

    /// The finished row's repeat, for the readback and `made_unit` (nil while open, or when nothing repeats).
    public var detected: PatternUnit? {
        isComplete ? PatternDetector.detect(placed.map { palette.pieces[$0].code }) : nil
    }
}
