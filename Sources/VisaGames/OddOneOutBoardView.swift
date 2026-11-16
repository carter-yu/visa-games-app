import SwiftUI
import VisaCore

/// One 分類 card or row piece (patterns-sorting P1): a tap-count vehicle tinted from its own palette or a shape block on
/// its cart (`ShapeBlockArt.art`), or a prop PNG; 細 at 0.62, 車頭向另一邊 mirrored. Text-free; the accessibility label
/// says it in both languages (「黃色挖泥車 / Yellow digger」).
struct PatternSortLookView: View {
    let look: PatternSortLook

    var body: some View {
        Group {
            if let prop = look.piece.prop {
                ActivityAssetView(assetID: prop.assetID)
            } else if let art = ShapeBlockArt.art(look) {
                VectorArtView(artwork: art)
            }
        }
        .scaleEffect(x: look.facing == .mirrored ? -look.size.scale : look.size.scale, y: look.size.scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(look.labelZH) / \(look.labelEN)")
    }
}

/// The 邊個唔同類 stimulus panel (design §4.2): the emblem (three grey dots and one sunny star, the idea "3 alike,
/// 1 different", never the answer), or on a category round the category sign (the word and its grey anchor model). The
/// read-through lights it with an outline and opacity only, no bounce (design §5.5).
struct OddOneOutStimulusView: View {
    let question: OddOneOutQuestion
    let lit: Bool
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        content
            .padding(metrics.u(10))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.u(22), style: .continuous)
                    .strokeBorder(Color(hex: DesignTokens.Palette.sunny), lineWidth: metrics.u(lit ? 8 : 0))
            )
            .opacity(lit ? 1 : 0.9)
    }

    @ViewBuilder
    private var content: some View {
        if let sign = OddOneOutCopy.sign(question) {
            HStack(spacing: metrics.u(18)) {
                if let art = sign.anchor.model.flatMap({ TapCountArt.named($0.rawValue) }) {
                    VectorArtView(artwork: art)
                        .grayscale(1)
                        .opacity(0.75)
                        .frame(width: metrics.u(150), height: metrics.u(110))
                }
                CanvasText(sign.word, size: 56, weight: 900)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(sign.word) / \(sign.english)")
        } else {
            HStack(spacing: metrics.u(22)) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color(hex: 0xB9BFC8))
                        .frame(width: metrics.u(46), height: metrics.u(46))
                }
                Image(systemName: "star.fill")
                    .font(.system(size: metrics.u(54), weight: .bold))
                    .foregroundStyle(Color(hex: DesignTokens.Palette.sunny))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("三個一樣，一個唔同 / Three alike, one different")
        }
    }
}
