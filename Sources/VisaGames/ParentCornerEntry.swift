import SwiftUI
import VisaCore

/// Faint parent corner (ADR 0007): only a 3-second hold starts the existing macOS parent
/// authentication. A tap does nothing, so the child path has no one-tap route to the prompt.
///
/// `showsMark: false` makes an invisible hold target layered over other art (the Watch garage
/// glyph, v0.11.0) so the art stays a garage, not a Parent button.
struct ParentCornerEntry: View {
    let onUnlock: () -> Void
    /// Canvas units.
    var size: CGFloat = 44
    var showsMark = true
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        ZStack {
            if showsMark {
                Circle().fill(Color.ink.opacity(0.08))
                VectorArtView(artwork: CanvasArt.parentIcon)
                    .frame(width: metrics.u(22), height: metrics.u(22))
                    .opacity(0.45)
            } else {
                Color.clear
            }
        }
        .frame(width: metrics.u(size), height: metrics.u(size))
        .contentShape(showsMark ? AnyShape(Circle()) : AnyShape(Rectangle()))
        .onLongPressGesture(minimumDuration: DesignTokens.parentHoldSeconds, maximumDistance: metrics.u(24)) {
            onUnlock()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("家長（長按三秒）/ Parent (hold 3 seconds)")
    }
}

/// Parent corner for child screens that are not yet canvas boards, at the same spot as board 1.
///
/// v0.22.2: hittable region is only the corner control. Do not wrap it in a full-screen
/// hittable full-screen stage/GeometryReader content stack — that overlay could swallow ticket
/// taps on the board underneath (0.22.1 depot hang sample: idle main thread, no app frames
/// past `main`). DepotHomeView already embeds `ParentCornerEntry`; ShellView skips this layer
/// on the depot.
struct ParentCornerLayer: View {
    let onUnlock: () -> Void
    @State private var scale: CGFloat = 1
    @State private var originX: CGFloat = 0
    @State private var originY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Size reader only — must not participate in hit testing.
            GeometryReader { proxy in
                let stage = DesignTokens.stageLayout(screenWidth: Double(proxy.size.width),
                                                     screenHeight: Double(proxy.size.height))
                Color.clear.preference(
                    key: ParentCornerStageKey.self,
                    value: ParentCornerStage(
                        scale: CGFloat(stage.scale),
                        originX: CGFloat(stage.originX),
                        originY: CGFloat(stage.originY)
                    )
                )
            }
            .allowsHitTesting(false)

            ParentCornerEntry(onUnlock: onUnlock)
                .environment(\.canvasMetrics, CanvasMetrics(scale: scale))
                .offset(x: originX + 1220 * scale, y: originY + 664 * scale)
        }
        .onPreferenceChange(ParentCornerStageKey.self) { stage in
            scale = stage.scale
            originX = stage.originX
            originY = stage.originY
        }
    }
}

private struct ParentCornerStage: Equatable {
    var scale: CGFloat
    var originX: CGFloat
    var originY: CGFloat
}

private struct ParentCornerStageKey: PreferenceKey {
    static var defaultValue: ParentCornerStage { ParentCornerStage(scale: 1, originX: 0, originY: 0) }
    static func reduce(value: inout ParentCornerStage, nextValue: () -> ParentCornerStage) {
        value = nextValue()
    }
}
