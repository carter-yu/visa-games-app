import SwiftUI
import VisaCore

/// Faint parent corner (ADR 0007): only a 3-second hold starts the existing macOS parent
/// authentication. A tap does nothing, so the child path has no one-tap route to the prompt.
struct ParentCornerEntry: View {
    let onUnlock: () -> Void
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        ZStack {
            Circle().fill(Color.ink.opacity(0.08))
            VectorArtView(artwork: CanvasArt.parentIcon)
                .frame(width: metrics.u(22), height: metrics.u(22))
                .opacity(0.45)
        }
        .frame(width: metrics.u(44), height: metrics.u(44))
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: DesignTokens.parentHoldSeconds, maximumDistance: metrics.u(24)) {
            onUnlock()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("家長（長按三秒）/ Parent (hold 3 seconds)")
    }
}

/// Parent corner for child screens that are not yet canvas boards, at the same spot as board 1.
struct ParentCornerLayer: View {
    let onUnlock: () -> Void

    var body: some View {
        CanvasStage {
            Color.clear.allowsHitTesting(false)
        } content: {
            ParentCornerEntry(onUnlock: onUnlock)
                .canvasPlaced(x: 1220, y: 664)
        }
    }
}
