import SwiftUI
import VisaCore

/// Build 78 snap experiment (HYPOTHESIS, docs/parent-scroll-diagnostics.md): the parent
/// page's two adaptive LazyVGrids become eager chunked HStack rows, like the letter tiles
/// in `ParentPracticeItemPicker`. Column count and width match the old adaptive grid; the
/// width is a caller constant (`ParentGridColumns`), never measured from a row.
struct ParentEagerRows<Item: Hashable, Content: View>: View {
    let items: [Item]
    let columns: ParentGridColumns
    let spacing: CGFloat
    let rowSpacing: CGFloat
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: rowSpacing) {
            ForEach(columns.rows(itemCount: items.count), id: \.lowerBound) { row in
                HStack(spacing: spacing) {
                    ForEach(items[row], id: \.self) { item in
                        content(item)
                            .frame(width: CGFloat(columns.itemWidth))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
