import Foundation

// patterns-sorting P0 (design §5.6, T15): the one geometry table for the new cards, in canvas units on the
// 1280 × 720 artboard. Only the new kinds use it; every older board keeps its own layout (choice rows at x 110).

public enum PatternSortLayout {
    public static let stageWidth = 1280.0
    public static let centreX = 640.0

    // MARK: Choice rows (2, 3 or 4 cards) and garages

    public static let choiceTop = 430.0
    public static let cardHeight = DesignTokens.choiceCardHeight
    public static let cardGap = 24.0

    /// 300 u cards in rows of up to 3, 240 u in rows of 4 (the convoy's width).
    public static func cardWidth(_ count: Int) -> Double { count > DesignTokens.maxChoices ? 240 : DesignTokens.choiceCardWidth }

    public static func rowWidth(_ count: Int) -> Double {
        Double(count) * cardWidth(count) + Double(max(count - 1, 0)) * cardGap
    }

    /// Left edge of a centred row: x = 640 − row width / 2 (2 cards: 328, 3: 166, 4: 124).
    public static func rowX(_ count: Int) -> Double { centreX - rowWidth(count) / 2 }

    /// The gap between the row's cards on screen, in points at stage `scale` (astra R2): it scales like the cards and the
    /// row's left edge, so the row stays centred at every stage scale. (An older board's `HStack(spacing: 24)` gap is 24
    /// points at any scale.)
    public static func rowGapPoints(scale: Double) -> Double { cardGap * scale }

    /// The row's centre in canvas units as the screen lays it out at stage `scale`: the left edge (`canvasPlaced`) and
    /// the cards (`ChoiceCardChrome`) scale with the stage; the gap is `gapPoints` points.
    public static func screenRowCentre(_ count: Int, scale: Double, gapPoints: Double) -> Double {
        let width = Double(count) * scale * cardWidth(count) + Double(max(count - 1, 0)) * gapPoints
        return (scale * rowX(count) + width / 2) / scale
    }

    public static func choiceRects(_ count: Int) -> [LineMatchRect] {
        (0..<count).map { i in
            LineMatchRect(x: rowX(count) + Double(i) * (cardWidth(count) + cardGap), y: choiceTop,
                          width: cardWidth(count), height: cardHeight)
        }
    }

    public static let garageWidth = 400.0
    /// The wider gap keeps a pen slip off the other garage.
    public static let garageGap = 80.0

    /// x 200–600 and 680–1080.
    public static func garageRects() -> [LineMatchRect] {
        let left = centreX - garageWidth - garageGap / 2
        return (0..<2).map { i in
            LineMatchRect(x: left + Double(i) * (garageWidth + garageGap), y: choiceTop, width: garageWidth, height: cardHeight)
        }
    }

    // MARK: Stimulus panel, pattern strip, sorting queue

    /// The count-size panel (860 × 260 at (210, 152)).
    public static let panel = LineMatchRect(x: 210, y: 152, width: 860, height: 260)
    /// The 邊個唔同類 emblem or category sign (420 × 150, centred in the standard 420 × 220 stimulus panel).
    public static let emblem = LineMatchRect(x: 430, y: 195, width: 420, height: 150)

    public static let stripLeft = 236.0
    public static let stripWidth = 808.0

    public static func stripPitch(_ n: Int) -> Double { stripWidth / Double(max(n, 1)) }

    /// Slot centres: 236 + (808 / n)(i + ½).
    public static func stripCentres(_ n: Int) -> [Double] {
        (0..<n).map { stripLeft + stripPitch(n) * (Double($0) + 0.5) }
    }

    /// Each piece ≤ 0.9 × the pitch, measured with its strokes.
    public static func maxPieceWidth(_ n: Int) -> Double { 0.9 * stripPitch(n) }

    /// One scale for every piece of a row, so the widest art (with strokes) fits its slot; small pieces then ×0.62.
    public static func pieceScale(widestArt: Double, n: Int) -> Double {
        guard widestArt > 0 else { return 1 }
        return min(1, maxPieceWidth(n) / widestArt)
    }

    /// The sorting queue: the front vehicle at the junction (centre x 640), up to 5 waiting, each ≤ 64 wide, 70 apart.
    public static let queueFrontX = 640.0
    public static let queueWaitingWidth = 64.0
    public static let queueSpacing = 70.0
    public static let queueY = 230.0

    public static func queueWaiting(_ count: Int) -> [LineMatchRect] {
        (1...max(1, min(count, 5))).prefix(min(count, 5)).map { k in
            LineMatchRect(x: queueFrontX - queueSpacing * Double(k) - queueWaitingWidth / 2, y: queueY,
                          width: queueWaitingWidth, height: queueWaitingWidth)
        }
    }

    // MARK: Header, bubble, keep-outs

    public static let headerX = 980.0

    /// Every new kind keeps the header's single cone (design D13; 分車房 included).
    public static func coneTotal(_ kind: ActivityKind) -> Int { 1 }

    /// The cone + fuel cluster: n cones are 28n + 8(n − 1) + 28 u; the fuel pill keeps it at least 184 u.
    public static func headerWidth(cones: Int) -> Double {
        max(184, Double(28 * cones + 8 * max(cones - 1, 0) + 28))
    }

    public static func headerRect(_ kind: ActivityKind) -> LineMatchRect {
        LineMatchRect(x: headerX, y: 28, width: headerWidth(cones: coneTotal(kind)), height: 72)
    }

    /// The bubble starts at x 166 (Stampy 110 u + 16 u) and is scaled 0.85 from there.
    public static let bubbleLeft = 166.0
    public static let bubbleMaxRight = 825.0
    public static let bubbleMaxChinese = 18
    public static let bubbleMaxEnglish = 52

    /// right edge = 166 + 0.85 × (213 + text width): zh 30 u per character, English bounded at 0.6 em of 18 u.
    public static func bubbleRightEdge(zh: String, en: String) -> Double {
        let width = max(Double(zh.count) * 30, Double(en.count) * 0.6 * 18)
        return bubbleLeft + 0.85 * (213 + width)
    }

    public static func fitsBubble(zh: String, en: String) -> Bool {
        zh.count <= bubbleMaxChinese && en.count <= bubbleMaxEnglish && bubbleRightEdge(zh: zh, en: en) <= bubbleMaxRight
    }

    /// Clock keep-out K (x 1182–1280, y 0–56) and the parent corner (1196, 640, 84, 80): nothing may sit in either.
    public static let keepOuts = [StatusSlot.mainKeepOut, LineMatchLayout.parentCornerKeepOut]
}
