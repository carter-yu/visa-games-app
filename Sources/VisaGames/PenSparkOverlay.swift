import AppKit
import SwiftUI
import VisaCore

/// Tracks the pen for the glow. Fed by an observe-only event monitor: every event is passed on
/// unchanged, so kiosk key blocking and clicks are unaffected.
@MainActor
final class PenSparkModel: ObservableObject {
    @Published private(set) var state = PenSparkState()

    func handle(_ event: NSEvent) {
        let now = Date()
        if event.type == .tabletProximity || event.subtype == .tabletProximity {
            state.proximity(entering: event.isEnteringProximity, now: now)
            VisaGamesLog.append("pen proximity — 筆近板 entering=\(event.isEnteringProximity) device=\(event.pointingDeviceType.rawValue)")
            return
        }
        guard let point = viewPoint(for: event) else { return }
        switch event.type {
        case .mouseMoved:
            if state.hover(x: point.x, y: point.y, now: now) {
                VisaGamesLog.append("pen hover observed — 筆尖懸停 x=\(Int(point.x)) y=\(Int(point.y))")
            }
        case .leftMouseDown, .leftMouseDragged:
            state.touch(x: point.x, y: point.y, now: now)
        case .leftMouseUp:
            state.lift(x: point.x, y: point.y, now: now)
        default:
            break
        }
    }

    func tick(now: Date) {
        var next = state
        next.tick(now: now)
        if next != state { state = next }
    }

    /// Window point → top-left-origin point in the hosting view (the SwiftUI root).
    private func viewPoint(for event: NSEvent) -> CGPoint? {
        guard let view = event.window?.contentView else { return nil }
        let local = view.convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x, y: view.isFlipped ? local.y : view.bounds.height - local.y)
    }
}

/// The canvas's pen spark ring, drawn above child screens and never hit-testable.
struct PenSparkOverlay: View {
    @ObservedObject var model: PenSparkModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let layout = DesignTokens.stageLayout(screenWidth: Double(proxy.size.width),
                                                  screenHeight: Double(proxy.size.height))
            let size = CGFloat(CanvasArt.penSpark.width * layout.scale)
            if let position = model.state.position {
                VectorArtView(artwork: CanvasArt.penSpark)
                    .frame(width: size, height: size)
                    .opacity(model.state.isVisible ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.state.isVisible)
                    .position(x: position.x, y: position.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
