import Foundation

/// One visit to the video picker. The full allowlist is shuffled once with
/// `ActivityChoiceOrder` (Fisher–Yates, `SeededGenerator`). Pages are slices of
/// that deck — never a second shuffle. The visit seed is minted by the app when
/// the picker is entered and is not stored in UserDefaults. This is not
/// `VideoPlaybackShuffle` (that deck is the legacy next-id queue).
public enum VideoPickerDeck {
    public static let pageSize = 8

    public static func ordered<T>(_ items: [T], seed: String) -> [T] {
        ActivityChoiceOrder.shuffled(items, seed: "videoPicker|\(seed)")
    }

    /// 0 items → 0 pages (empty bay, not the picker). 1...8 → one page. 9+ → more.
    public static func pageCount(itemCount: Int, pageSize: Int = pageSize) -> Int {
        guard itemCount > 0, pageSize > 0 else { return 0 }
        return (itemCount + pageSize - 1) / pageSize
    }

    public static func showsPager(itemCount: Int, pageSize: Int = pageSize) -> Bool {
        pageCount(itemCount: itemCount, pageSize: pageSize) > 1
    }

    /// Slice of the already-shuffled deck. The last page may be short; the view
    /// keeps the empty slots after those cards.
    public static func page<T>(_ deck: [T], index: Int, pageSize: Int = pageSize) -> [T] {
        guard pageSize > 0, index >= 0 else { return [] }
        let start = index * pageSize
        guard start < deck.count else { return [] }
        let end = min(start + pageSize, deck.count)
        return Array(deck[start..<end])
    }
}

/// Parking bay for one chunky action button. Same button, three leading x positions,
/// one y. Chosen once per visit from a seed. Not animated across the artboard.
public enum BayDock: String, CaseIterable, Equatable, Sendable {
    case left
    case center
    case right

    /// Artboard y for every dock (1280×720).
    public static let canvasY = 560
    /// Right edge budget for the departure pair (button + vehicle).
    public static let pairBudget = 380
    /// Button must end by here so it stays ~80 units clear of the parent-hold dot at x 1220.
    public static let clearLeadingEdge = 1140

    public var leadingX: Int {
        switch self {
        case .left: return 72
        case .center: return 400
        case .right: return 760
        }
    }

    /// First bay of a seeded shuffle of the three docks. Same seed, same bay.
    public static func chosen(seed: String) -> BayDock {
        let order = ActivityChoiceOrder.shuffled(
            [BayDock.left, BayDock.center, BayDock.right],
            seed: "bayDock|\(seed)"
        )
        return order[0]
    }
}
