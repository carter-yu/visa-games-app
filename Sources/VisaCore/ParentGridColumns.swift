import Foundation

/// Eager replacement for `GridItem(.adaptive(minimum:maximum:), spacing:)` on the parent
/// page (build 78). Same column count and column width as the adaptive grid, but the host
/// lays the rows out as plain HStacks, so no row height is ever estimated offscreen.
/// Snap fix status: HYPOTHESIS (docs/parent-scroll-diagnostics.md, build 78).
public struct ParentGridColumns: Equatable, Sendable {
    public let count: Int
    public let itemWidth: Double

    public init(width: Double, minimum: Double, maximum: Double = .infinity, spacing: Double) {
        let width = width.isFinite ? max(0, width) : 0
        let minimum = minimum.isFinite && minimum > 0 ? minimum : 1
        let maximum = maximum.isNaN ? .infinity : max(minimum, maximum)
        let gap = spacing.isFinite ? max(0, spacing) : 0
        let fitted = ((width + gap) / (minimum + gap)).rounded(.down)
        count = Int(min(max(1, fitted), 1_000))
        itemWidth = min(maximum, max(0, (width - Double(count - 1) * gap) / Double(count)))
    }

    /// Item index ranges per row, in order; the last row may be short (it stays leading).
    public func rows(itemCount: Int) -> [Range<Int>] {
        let total = max(0, itemCount)
        return stride(from: 0, to: total, by: count).map { $0..<min($0 + count, total) }
    }

    /// The kiosk window is always the full screen; the smallest Mac display mode is 1280 pt wide.
    public static let kioskMinimumViewportWidth = 1280.0

    /// The parent page's inner card width: content cap 940, page padding 28 + 28, section
    /// panel padding 16 + 16, minus a vertical scroller gutter (legacy scrollers: 15 pt).
    /// Any viewport ≥ 956 pt gives 852 pt (the build-76 log: viewport 1905).
    public static func parentContentWidth(viewportWidth: Double, scrollerGutter: Double = 16) -> Double {
        guard viewportWidth.isFinite else { return 0 }
        return max(0, min(940, viewportWidth - scrollerGutter) - 2 * 28 - 2 * 16)
    }
}
