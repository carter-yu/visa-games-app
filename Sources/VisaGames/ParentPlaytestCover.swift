import SwiftUI
import VisaCore

/// Playtest sits on top of parent settings. `session.mode` stays `.parent`.
/// The board is the same child activity host; answers stay local (no visa, stamp, or ledger).
struct ParentPlaytestCover: View {
    @ObservedObject var model: AppModel
    let kind: ActivityKind

    var body: some View {
        VStack(spacing: 0) {
            bar
            if model.playtestCompleted {
                Text("試玩完成，冇發簽證。 / Playtest finished. No visa.")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(hex: DesignTokens.Palette.paper))
                    .overlay(Rectangle().fill(Color.ink).frame(height: 3), alignment: .bottom)
                    .accessibilityLabel("試玩完成，冇發簽證。 Playtest finished. No visa.")
            }
            CanvasActivityHost(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: DesignTokens.Palette.sand).ignoresSafeArea())
    }

    private var bar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                ParentLabel("試玩 · \(kind.parentCardTitle)", size: 20, weight: 900)
                ParentLabel("Playtest", size: 12, weight: 700, color: .inkSoft)
            }
            Text("冇簽證 / No visa")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(hex: DesignTokens.Palette.sand)))
                .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2))
            Spacer(minLength: 8)
            Button(action: { model.endPlaytestToParent() }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 16, weight: .heavy))
                    VStack(alignment: .leading, spacing: 0) {
                        ParentLabel("返回家長", size: 16, weight: 900)
                        ParentLabel("Back to parent", size: 11, weight: 700, color: .inkSoft)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .buttonStyle(ChunkyButtonStyle(
                fill: Color(hex: DesignTokens.Palette.mint),
                cornerRadius: 16,
                shadowDepth: 4,
                lineWidth: 3
            ))
            .accessibilityLabel("返回家長 Back to parent")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Color(hex: DesignTokens.Palette.sand)
                .overlay(Rectangle().fill(Color.ink).frame(height: 3), alignment: .bottom)
        )
    }
}
