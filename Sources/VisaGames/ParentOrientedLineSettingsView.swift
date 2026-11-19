import SwiftUI
import VisaCore

/// 家長 → 遊戲 → 畫直線・四方設定 (0.42.0; four-direction design §3.2, §3.4, §6.3, §8.2; Carter C2, C3): this card's own
/// 線形 (only 橫線 · 斜線 · 橫斜都有) and 方向 in two rows, four thumbnails lit for what the choice deals, 畫線提示 and its own 畫線寬容度. Saved at
/// once and used from the next round; changing 線形 or 方向 shows 「改咗線款，建議試玩」. Nothing here is shared with
/// 畫直線 · 熱身 or 畫形狀設定. Plain stacks and buttons only — no text input, no animation.
struct ParentOrientedLineSettingsView: View {
    let settings: OrientedLineSettings
    let advisory: Bool
    let playtestedOn: Date?
    let learned: [OrientedLineVariant]
    let onShape: (OrientedLineShapeSetting) -> Void
    let onDirection: (OrientedLineDirectionSetting) -> Void
    let onHelp: (TapCountGuidanceLevel) -> Void
    let onTolerance: (LineMatchTolerance) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(OrientedLineVariant.allCases.map(\.arrow).joined(separator: " "))
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(Color.ink)
                    .fixedSize()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    ParentLabel(OrientedLineCopy.settingsTitle, size: 20, weight: 900)
                    ParentLabel(OrientedLineCopy.settingsSubtitle, size: 12, weight: 700, color: .inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if advisory {
                ParentBanner(text: OrientedLineCopy.changedAdvisory, fill: Color(hex: DesignTokens.Palette.taxiTicket))
            }
            row(OrientedLineCopy.shapeTitle) {
                ForEach(OrientedLineShapeSetting.allCases, id: \.self) { shape in
                    choiceButton(title: shape.labelTraditionalChinese, subtitle: shape.labelEnglish,
                                 selected: settings.lineShape == shape) { onShape(shape) }
                }
            }
            row(OrientedLineCopy.directionTitle) {
                ForEach(OrientedLineDirectionSetting.allCases, id: \.self) { direction in
                    choiceButton(title: direction.labelTraditionalChinese, subtitle: direction.labelEnglish,
                                 selected: settings.lineDirection == direction) { onDirection(direction) }
                }
            }
            thumbnails
            row(OrientedLineCopy.helpTitle) {
                ForEach(TapCountGuidanceLevel.allCases, id: \.self) { level in
                    let label = OrientedLineCopy.helpLabel(level)
                    choiceButton(title: label.zh, subtitle: label.en, selected: settings.lineHelp == level) { onHelp(level) }
                }
            }
            let detail = OrientedLineCopy.helpDetail(settings.lineHelp)
            ParentLabel("\(detail.zh) / \(detail.en)", size: 12, weight: 600, color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            ParentLabel(learnedLine, size: 12, weight: 600, color: .inkSoft)
            row(OrientedLineCopy.toleranceTitle) {
                ForEach(LineMatchTolerance.allCases, id: \.self) { tolerance in
                    choiceButton(title: tolerance.labelTraditionalChinese, subtitle: tolerance.labelEnglish,
                                 selected: settings.tolerance == tolerance) { onTolerance(tolerance) }
                }
            }
            ParentLabel(OrientedLineCopy.toleranceNow(settings.tolerance), size: 12, weight: 600, color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            ParentLabel(OrientedLineCopy.toleranceNote, size: 12, weight: 600, color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            ParentLabel(OrientedLineCopy.nextRoundNote, size: 12, weight: 600, color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.paper), cornerRadius: 18,
                              shadowDepth: 4, lineWidth: 3))
    }

    /// 識咗 per oriented variant (this card's own record; it starts empty and is never copied).
    private var learnedLine: String {
        let arrows = learned.map(\.arrow).joined(separator: " ")
        return arrows.isEmpty ? "識咗：未有 / Learned: none yet" : "識咗：\(arrows) / Learned: \(arrows)"
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ParentLabel(title, size: 15, weight: 800)
            HStack(spacing: 10) { content() }
        }
    }

    /// Four thumbnails (→ ← ↗ ↙): green at each one's actual start, red at its finish; lit when this choice deals it.
    private var thumbnails: some View {
        VStack(alignment: .leading, spacing: 8) {
            ParentLabel(OrientedLineCopy.thumbnailsTitle, size: 13, weight: 800)
            HStack(spacing: 10) {
                ForEach(OrientedLineVariant.allCases, id: \.self) { variant in
                    let lit = settings.variants.contains(variant)
                    Canvas { context, size in
                        Self.drawThumbnail(variant, in: &context, size: size)
                    }
                    .frame(width: 96, height: 64)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(lit ? Color(hex: DesignTokens.Palette.sunnyPale) : Color(hex: DesignTokens.Palette.paper)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.ink.opacity(lit ? 1 : 0.3), lineWidth: lit ? 3 : 1.5))
                    .opacity(lit ? 1 : 0.45)
                    .accessibilityLabel("\(variant.arrow) \(lit ? "會出" : "唔出") / \(lit ? "dealt" : "not dealt")")
                }
            }
        }
    }

    /// The variant's own road in a 96 × 64 tile: the same geometry as the board, scaled down.
    static func drawThumbnail(_ variant: OrientedLineVariant, in g: inout GraphicsContext, size: CGSize) {
        let footprint: OrientedLineFootprint = variant.isHorizontal ? .horizontal(left: 1, right: 1, row: 1) : .diagonal(1)
        let line = OrientedLine(variant: variant, footprint: footprint)
        let bounds = line.outerBounds
        let scale = min(size.width / CGFloat(bounds.width), size.height / CGFloat(bounds.height)) * 0.9
        let dx = (size.width - CGFloat(bounds.width) * scale) / 2 - CGFloat(bounds.x) * scale
        let dy = (size.height - CGFloat(bounds.height) * scale) / 2 - CGFloat(bounds.y) * scale
        func p(_ point: LineMatchPoint) -> CGPoint { CGPoint(x: CGFloat(point.x) * scale + dx, y: CGFloat(point.y) * scale + dy) }
        var road = Path()
        road.move(to: p(line.greenSign))
        road.addLine(to: p(line.redSign))
        g.stroke(road, with: .color(Color.ink), style: StrokeStyle(lineWidth: 112 * scale, lineCap: .round))
        g.stroke(road, with: .color(Color(hex: 0xFFF9EC)), style: StrokeStyle(lineWidth: 100 * scale, lineCap: .round))
        let r = CGFloat(OrientedLine.signPaintedRadius) * scale
        for (point, color) in [(line.greenSign, LM.go), (line.redSign, LM.end)] {
            let c = p(point)
            g.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
        }
        // The way, along u from green to red (never toward green).
        var arrow = Path()
        let from = p(line.point(at: line.length * 0.2)), to = p(line.point(at: line.length * 0.8))
        arrow.move(to: from)
        arrow.addLine(to: to)
        g.stroke(arrow, with: .color(Color.ink), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        let angle = line.angle
        var head = Path()
        head.move(to: CGPoint(x: to.x - 9 * cos(angle - 0.5), y: to.y - 9 * sin(angle - 0.5)))
        head.addLine(to: to)
        head.addLine(to: CGPoint(x: to.x - 9 * cos(angle + 0.5), y: to.y - 9 * sin(angle + 0.5)))
        g.stroke(head, with: .color(Color.ink), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }

    private func choiceButton(title: String, subtitle: String, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ParentLabel(title, size: 16, weight: 900)
                ParentLabel(subtitle, size: 10, weight: 700, color: .inkSoft)
            }
            .frame(width: 124)
            .padding(.vertical, 6)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: selected ? Color(hex: DesignTokens.Palette.sunny) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 12, shadowDepth: selected ? 2 : 3, lineWidth: 2))
        .accessibilityLabel("\(title) / \(subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
