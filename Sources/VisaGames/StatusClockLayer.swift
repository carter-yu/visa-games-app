import SwiftUI
import VisaCore

/// Clock + elapsed glance chip C1 (0.39.0 / 86; clock-playtime design §1.3, §2.1, §2.7, §6, §9 C1; chip-rows/
/// compare.md FINAL v1 §5): the Hong Kong `h:mm` over the time since this app started, in the slot `plan` gives.
/// `ShellView` builds the plan from the screen it shows; with no plan (parent controls, the LM family until C4, Watch
/// until C5) the layer is not there at all.
///
/// Never hit-testable, never focusable and without gestures, like `PenSparkOverlay`: taps, pen strokes and the parent
/// hold reach whatever is under it. `Equatable` + `.equatable()`: the 0.5 s shell tick does not re-render it, and it
/// never reads `model.now`. Its own timeline redraws only at the next minute of either row (`StatusChipRefresh`).
struct StatusClockLayer: View, Equatable {
    let plan: StatusChipPlan
    /// `AppModel.launchUptime`: the uptime read once at app start.
    let launchUptime: TimeInterval
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Nonisolated (Swift 6): compares only the value inputs.
    nonisolated static func == (lhs: StatusClockLayer, rhs: StatusClockLayer) -> Bool {
        lhs.plan == rhs.plan && lhs.launchUptime == rhs.launchUptime
    }

    var body: some View {
        GeometryReader { proxy in
            let width = Double(proxy.size.width)
            let height = Double(proxy.size.height)
            let rect = StatusSlot.onScreen(plan.slot, screenWidth: width, screenHeight: height)
            let stage = DesignTokens.stageLayout(screenWidth: width, screenHeight: height)
            TimelineView(StatusChipSchedule(launchUptime: launchUptime)) { context in
                // The top row reads the entry's instant; the bottom row reads only the two uptimes.
                StatusChipView(content: StatusChipContent(date: context.date, launchUptime: launchUptime,
                                                          nowUptime: ProcessInfo.processInfo.systemUptime,
                                                          language: plan.language),
                               tone: plan.tone)
            }
            .environment(\.canvasMetrics, CanvasMetrics(scale: CGFloat(stage.scale)))
            .frame(width: CGFloat(rect.width), height: CGFloat(rect.height))
            .offset(x: CGFloat(rect.x), y: CGFloat(rect.y))
        }
        .opacity(plan.dimmed ? StatusChipStyle.thinkPauseOpacity : 1)
        .animation(reduceMotion ? nil : .easeInOut(duration: StatusChipStyle.thinkPauseFadeSeconds), value: plan.dimmed)
        .allowsHitTesting(false)
    }
}

/// The R2 chip: 84 × 40 u, two fixed rows, flat (no shadow, no press state). One static-text element for VoiceOver.
private struct StatusChipView: View {
    let content: StatusChipContent
    let tone: StatusChipTone
    @Environment(\.canvasMetrics) private var metrics
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let style = StatusChipStyle(tone: tone, increaseContrast: contrast == .increased,
                                    reduceTransparency: reduceTransparency)
        let shape = RoundedRectangle(cornerRadius: u(StatusChipLayout.cornerRadius), style: .continuous)
        let glyph = StatusChipLayout.glyph
        return shape
            .fill(Color(hex: style.fill, opacity: style.fillOpacity))
            .overlay {
                shape.strokeBorder(Color(hex: style.outline, opacity: style.outlineOpacity),
                                   lineWidth: u(style.outlineWidth))
            }
            .overlay(alignment: .topLeading) {
                StatusClockGlyph()
                    .stroke(Color(hex: style.glyph),
                            style: StrokeStyle(lineWidth: u(StatusChipLayout.glyphLine * glyph.width / 2),
                                               lineCap: .round, lineJoin: .round))
                    .frame(width: u(glyph.width), height: u(glyph.height))
                    .offset(x: u(glyph.x), y: u(glyph.y))
            }
            .overlay(alignment: .topLeading) {
                row(content.clock, size: StatusChipLayout.clockSize, weight: StatusChipLayout.clockWeight,
                    color: style.text)
                    .offset(x: u(StatusChipLayout.clockX), y: u(StatusChipLayout.clockBaseline))
            }
            .overlay(alignment: .topLeading) {
                row(content.elapsed, size: StatusChipLayout.elapsedSize, weight: StatusChipLayout.elapsedWeight,
                    color: style.text)
                    .offset(x: u(StatusChipLayout.elapsedX), y: u(StatusChipLayout.elapsedBaseline))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(content.accessibilityLabel)
            .accessibilityAddTraits(.isStaticText)
    }

    /// Canvas units → points.
    private func u(_ value: Double) -> CGFloat { metrics.u(CGFloat(value)) }

    /// One row: canvas type with tabular digits, one line at its natural size (never shrunk or truncated). Its top
    /// guide is its first baseline, so the row's offset places the baseline.
    private func row(_ text: String, size: Double, weight: Int, color: UInt32) -> some View {
        Text(text)
            .font(CanvasFont.font(size: u(size), weight: weight))
            .monospacedDigit()
            .foregroundStyle(Color(hex: color))
            .lineLimit(1)
            .fixedSize()
            .alignmentGuide(.top) { $0[.firstTextBaseline] }
    }
}

/// The static clock face: a circle, the minute hand up to 12 and the hour hand across to 3 (`StatusChipLayout`).
private struct StatusClockGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let face = radius * CGFloat(StatusChipLayout.glyphFace)
        var path = Path()
        path.addEllipse(in: CGRect(x: centre.x - face, y: centre.y - face, width: face * 2, height: face * 2))
        path.move(to: CGPoint(x: centre.x, y: centre.y - radius * CGFloat(StatusChipLayout.glyphMinuteHand)))
        path.addLine(to: centre)
        path.addLine(to: CGPoint(x: centre.x + radius * CGFloat(StatusChipLayout.glyphHourHand), y: centre.y))
        return path
    }
}

/// Timeline entries at the next minute of either row (`StatusChipRefresh`): at most two redraws a minute, never per
/// frame, and no timer of its own. `startDate` is paired with the uptime read when the timeline asks for entries.
private struct StatusChipSchedule: TimelineSchedule {
    let launchUptime: TimeInterval

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> StatusChipRefresh {
        StatusChipRefresh(start: startDate, uptimeAtStart: ProcessInfo.processInfo.systemUptime,
                          launchUptime: launchUptime)
    }
}
