import Foundation

public enum TapLetterTap: Equatable, Sendable {
    case found, allFound, miss, knownWrongRetap, foundRetap, doubleTapIgnored, ignored
}

/// Per-card state for the two-target Find & flip board. Pause and reward clocks stay with AppModel.
public struct TapLetterBoard: Sendable {
    public let deal: TapLetterDeal
    public private(set) var found: Set<Int> = []
    public private(set) var knownWrong: Set<Int> = []
    public private(set) var misses = 0
    public private(set) var assisted = false
    public private(set) var tapOrder: [Int] = []
    public private(set) var lastTapAt: TimeInterval = -.infinity
    public private(set) var lastTapCard: Int? = nil

    public init(deal: TapLetterDeal) { self.deal = deal }
    public var remaining: Int { max(0, 2 - found.count) }
    public var isComplete: Bool { remaining == 0 }
    public var hintCard: Int? { deal.board.targetCards.first { !found.contains($0) } }

    public mutating func showHint() { assisted = true }

    public mutating func tap(_ card: Int, at time: TimeInterval) -> TapLetterTap {
        guard (0..<10).contains(card), !isComplete else { return .ignored }
        if lastTapCard == card && time - lastTapAt < 0.4 { return .doubleTapIgnored }
        lastTapCard = card
        lastTapAt = time
        if found.contains(card) { return .foundRetap }
        if knownWrong.contains(card) { return .knownWrongRetap }
        tapOrder.append(card)
        if deal.board.targetCards.contains(card) {
            found.insert(card)
            return isComplete ? .allFound : .found
        }
        knownWrong.insert(card)
        misses += 1
        return .miss
    }
}

/// Appendix A. Child copy for this English-only card.
public enum TapLetterCopy {
    public static func prompt(_ x: String) -> String { "Find the letter \(x)! Tap every \(x)." }
    public static func header(_ x: String) -> String { "Tap every \(x)!" }
    public static func findAgain(_ x: String) -> String { "Find \(x)!" }
    public static func idle(_ x: String) -> String { "Find the letter \(x)!" }
    public static func remaining(_ count: Int) -> String { count == 0 ? "All found!" : "\(count) more to find" }
    public static func wrong(_ y: String) -> String { "That's \(y)." }
    public static func hint(_ x: String) -> String { "Here's \("aeiou".contains(x) ? "an" : "a") \(x)!" }
    public static func allFound(_ x: String, _ first: String, _ second: String) -> String {
        "\(x) is for \(first) and \(second)!"
    }
}

/// Number of completed child rounds, including retry and review lanes.
public struct LetterRoundIndexStore {
    public static let key = "VisaGames.tapLetterRoundIndex.v1"
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> Int { max(0, defaults.integer(forKey: Self.key)) }
    public func save(_ value: Int) { defaults.set(max(0, value), forKey: Self.key) }
}
