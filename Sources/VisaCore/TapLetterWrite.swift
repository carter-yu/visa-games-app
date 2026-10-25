import Foundation

/// The find result is retained while a letter is traced. Writing has no miss transition.
public struct TapLetterWriteRound: Sendable {
    public enum Phase: Sendable, Equatable { case finding, transition, writing, done }
    public private(set) var board: TapLetterBoard
    public private(set) var trace: ShapeTraceBoard
    public private(set) var phase: Phase = .finding
    public private(set) var demoActive = false
    public var canStamp: Bool { phase == .done && trace.isComplete }

    public init(deal: TapLetterDeal) {
        board = TapLetterBoard(deal: deal)
        trace = Self.makeTrace(letter: deal.target)
    }

    @discardableResult public mutating func tap(_ card: Int, at time: TimeInterval) -> TapLetterTap {
        guard phase == .finding else { return .ignored }
        let result = board.tap(card, at: time)
        if result == .allFound { phase = .transition }
        return result
    }

    public mutating func acceptFoundBoard(_ found: TapLetterBoard) {
        guard phase == .finding, found.isComplete, found.deal.target == board.deal.target else { return }
        board = found
        phase = .transition
    }

    public mutating func beginWriting(demo: Bool = true) {
        guard phase == .transition else { return }
        phase = .writing
        demoActive = demo
    }

    /// A touch during the guidance animation ends it without changing the trace.
    @discardableResult public mutating func endDemoNoPaint() -> Bool {
        guard phase == .writing, demoActive else { return false }
        demoActive = false
        return true
    }

    public mutating func finishDemo() { demoActive = false }
    public mutating func restartDemo() { guard phase == .writing else { return }; demoActive = true }

    public mutating func acceptTrace(_ next: ShapeTraceBoard) {
        guard phase == .writing, !demoActive, next.isMonotonicSuccessor(of: trace) else { return }
        trace = next
        if next.isComplete { phase = .done }
    }

    private static func makeTrace(letter: String) -> ShapeTraceBoard {
        let character = letter.first ?? "a"
        let paths = LatinGlyphs.paths(character, offset: LineMatchPoint(x: 545, y: 142), scale: 1)
        let shape = ShapeTraceShape(slot: "letter", kind: .numeral, strokes: paths,
                                    colorIndex: 0, frame: LineMatchRect(x: 545, y: 142, width: 190, height: 380))
        let question = ShapeTraceQuestion(itemID: "tapLetter.write.\(letter)", kind: .tapLetterWrite,
            level: .l2, scene: .numeralBoard, shift: 0, big: true, slant: false,
            shapes: [shape], laneWidth: LatinGlyphs.laneWidth, promptKey: "tapLetter.write.\(letter)",
            promptTraditionalChinese: "", promptEnglish: TapLetterCopy.writePrompt(letter))
        return ShapeTraceBoard(question: question)
    }
}

extension TapLetterCopy {
    public static func writePrompt(_ x: String) -> String { "Now write \(x)!" }
    public static func writeReprompt(_ x: String) -> String { "Start at the green arrow. Write \(x)!" }
    public static func writeDone(_ x: String) -> String { "You wrote \(x)!" }
    public static let cueDownAgain = "Stop! Now straight down!"
    public static let cueBackUp = "Stop! Back up!"
    public static func mnemonic(_ x: String) -> [String] {
        switch x {
        case "a": return ["Round like a c…", "Up, stop!", "And down!"]
        case "b": return ["Down from the top…", "Back up, stop!", "Round the tummy!"]
        case "c": return ["Round like a c!"]
        case "d": return ["Round like a c…", "Up high to the top, stop!", "And straight down!"]
        case "e": return ["Across the middle…", "Then round like a c!"]
        default: return []
        }
    }
}

/// Two consecutive clean traces make a letter familiar with writing guidance.
public struct LetterWriteProgress: Codable, Sendable, Equatable {
    public private(set) var streaks: [String: Int] = [:]
    public init() {}
    public func isLearned(_ letter: String) -> Bool { (streaks[letter] ?? 0) >= 2 }
    public mutating func record(_ letter: String, clean: Bool) {
        streaks[letter] = clean ? min(99, (streaks[letter] ?? 0) + 1) : 0
    }
}

public struct LetterWriteProgressStore {
    public static let key = "VisaGames.letterWriteProgress.v1"
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> LetterWriteProgress {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(LetterWriteProgress.self, from: data) else { return .init() }
        return value
    }
    public func save(_ value: LetterWriteProgress) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
