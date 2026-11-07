import Foundation

/// The depot ticket's letter-availability transition (build 78). `AppModel.selectDifficulty`
/// asks `prepare` first and changes round state only for `.ready`, so a failed letter (or, since
/// Hanzi H2, Hanzi) deal leaves the round untouched. Every recovery route clears the protected unavailable state
/// without needing a letter Save.
public struct LetterTicketDesk: Equatable, Sendable {
    public private(set) var unavailable = false

    public init() {}

    public enum Recovery: String, CaseIterable, Sendable {
        case parentEntered, returnedToChild, testVisa, assignmentChanged, lettersSaved, ticketDealt
    }

    public enum Outcome<Board> {
        /// Nothing changed except `unavailable`; the reason is for logs only.
        case unavailable(reason: String)
        /// The caller now resets and fills its round with this kind and (letter and Hanzi kinds) board.
        case ready(seed: String, kind: ActivityKind, letterBoard: Board?)
    }

    /// Kinds whose round needs a dealt board, which can fail: letters (build 78) and Hanzi (H2, build 83).
    public static func dealsBoard(_ kind: ActivityKind) -> Bool { kind.isTapLetterFamily || kind.isTapHanziFamily }

    /// Picks the kind and deals the only fallible payload (a letter or Hanzi board) before the caller
    /// touches any round state. `dealLetterBoard` is called only for `dealsBoard` kinds.
    public mutating func prepare<Board>(pool: [ActivityKind], seed: String,
                                        dealLetterBoard: (ActivityKind) -> Board?) -> Outcome<Board> {
        guard !pool.isEmpty else {
            unavailable = true
            return .unavailable(reason: "noEligibleKind")
        }
        let kind = ActivityCatalog.kind(forRoundSeed: seed, pool: pool)
        var board: Board?
        if Self.dealsBoard(kind) {
            guard let dealt = dealLetterBoard(kind) else {
                unavailable = true
                return .unavailable(reason: "no\(kind.isTapHanziFamily ? "Hanzi" : "Letter")Deal kind=\(kind.rawValue)")
            }
            board = dealt
        }
        unavailable = false
        return .ready(seed: seed, kind: kind, letterBoard: board)
    }

    /// Returns true when the state actually changed (for logging).
    @discardableResult
    public mutating func recover(_ route: Recovery) -> Bool {
        guard unavailable else { return false }
        unavailable = false
        return true
    }
}
