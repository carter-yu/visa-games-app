import SwiftUI
import VisaCore

/// 家長 → 遊戲 → 畫形狀設定 (v0.25.0, design shape-trace §5): shape mix (圓 / 方 / 三角, steps of
/// 5; the last shape cannot be turned off; 還原預設), tolerance (跟連一連 / 窄 / 標準 / 闊),
/// direction hint, corner stop, slant lines and the dotted guide style. Shared by the 畫線畫形
/// cards. Plain stacks and buttons only — no text input, no animation.
struct ParentShapeTraceSettingsView: View {
    let settings: ShapeTraceSettings
    /// The 連一連 tolerance (what 「跟連一連」 follows).
    let lineMatchTolerance: LineMatchTolerance
    let banner: String?
    let onAdjust: (ShapeTraceMixShape, Int) -> Void
    let onResetMix: () -> Void
    let onTolerance: (LineMatchTolerance?) -> Void
    let onDirectionHint: (Bool) -> Void
    let onCornerStop: (Bool) -> Void
    let onSlantLines: (Bool) -> Void
    let onDotStyle: (ShapeTraceDotStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VectorArtView(artwork: ShapeTraceArt.paintCar)
                    .frame(width: 54, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    ParentLabel(ShapeTraceCopy.settingsTitle, size: 20, weight: 900)
                    ParentLabel(ShapeTraceCopy.settingsSubtitle, size: 12, weight: 700, color: .inkSoft)
                }
            }
            if let banner {
                ParentBanner(text: banner, fill: Color(hex: DesignTokens.Palette.taxiTicket))
            }
            mixSection
            toleranceSection
            VStack(alignment: .leading, spacing: 8) {
                toggleRow(title: "方向提示 / Direction hint",
                          detail: "開：只可以跟箭嘴方向畫；熄：由紅色嗰頭開始都得 / On: arrow direction only; off: either end",
                          on: settings.directionHint, action: onDirectionHint)
                toggleRow(title: "到角位停一停 / Stop at corners",
                          detail: "開：轉角有「停」牌同提示；架車無論點都會喺角位等 / On: stop sign and voice; the car always waits",
                          on: settings.cornerStop, action: onCornerStop)
                toggleRow(title: "畫直線加斜線 / Slant line in Lines",
                          detail: "大約四歲半先開 / Usually from about 4½",
                          on: settings.slantLines, action: onSlantLines)
            }
            VStack(alignment: .leading, spacing: 8) {
                ParentLabel("虛線款式 / Guide style", size: 15, weight: 800)
                HStack(spacing: 10) {
                    ForEach(ShapeTraceDotStyle.allCases, id: \.self) { style in
                        choiceButton(title: style.labelTraditionalChinese, subtitle: style.labelEnglish,
                                     selected: settings.dotStyle == style) { onDotStyle(style) }
                    }
                }
            }
            ParentLabel("小貼士：\(ShapeTraceCopy.parentTip)", size: 12, weight: 600, color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.paper), cornerRadius: 18,
                              shadowDepth: 4, lineWidth: 3))
    }

    private var mixSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ParentLabel("形狀比例 / Shape mix", size: 15, weight: 800)
                Spacer(minLength: 8)
                Button(action: onResetMix) {
                    ParentLabel("還原預設 / Defaults", size: 13, weight: 800)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.paper),
                                               cornerRadius: 12, shadowDepth: 3, lineWidth: 2))
                .disabled(settings.hasDefaultMix)
                .opacity(settings.hasDefaultMix ? 0.45 : 1)
            }
            ForEach(ShapeTraceMixShape.allCases, id: \.self) { shape in
                weightRow(shape)
            }
            ParentLabel("跟虛線每輪畫一款形狀。三角形 = ★ 尖頂 ∧。0 = 唔出。 / One shape per round. Triangle = ★ spire ∧. 0 = never.",
                        size: 12, weight: 600, color: .inkSoft)
        }
    }

    private var toleranceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ParentLabel("畫線寬容度 / Tolerance", size: 15, weight: 800)
            HStack(spacing: 10) {
                choiceButton(title: ShapeTraceCopy.toleranceFollow, subtitle: ShapeTraceCopy.toleranceFollowEnglish,
                             selected: settings.tolerance == nil) { onTolerance(nil) }
                ForEach(LineMatchTolerance.allCases, id: \.self) { tolerance in
                    choiceButton(title: tolerance.labelTraditionalChinese, subtitle: tolerance.labelEnglish,
                                 selected: settings.tolerance == tolerance) { onTolerance(tolerance) }
                }
            }
            let effective = settings.effectiveTolerance(lineMatch: lineMatchTolerance)
            ParentLabel("而家：\(effective.labelTraditionalChinese)，路面 ×\(String(format: "%.1f", effective.roadWidthFactor))（出咗界都唔算錯，架車會等） / Now: corridor ×\(String(format: "%.1f", effective.roadWidthFactor)); off the lane is never wrong",
                        size: 12, weight: 600, color: .inkSoft)
        }
    }

    private func choiceButton(title: String, subtitle: String, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ParentLabel(title, size: 16, weight: 900)
                ParentLabel(subtitle, size: 10, weight: 700, color: .inkSoft)
            }
            .frame(width: 104)
            .padding(.vertical, 6)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: selected ? Color(hex: DesignTokens.Palette.sunny) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 12, shadowDepth: selected ? 2 : 3, lineWidth: 2))
        .accessibilityLabel("\(title) / \(subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleRow(title: String, detail: String, on: Bool, action: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: { action(!on) }) {
                ParentLabel(on ? "開 On" : "熄 Off", size: 14, weight: 900)
                    .frame(width: 70)
                    .padding(.vertical, 5)
            }
            .buttonStyle(ChunkyButtonStyle(
                fill: on ? Color(hex: DesignTokens.Palette.sunny) : Color(hex: DesignTokens.Palette.paper),
                cornerRadius: 12, shadowDepth: on ? 2 : 3, lineWidth: 2))
            .accessibilityLabel("\(title) \(on ? "開" : "熄")")
            VStack(alignment: .leading, spacing: 0) {
                ParentLabel(title, size: 14, weight: 800)
                ParentLabel(detail, size: 11, weight: 600, color: .inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func weightRow(_ shape: ShapeTraceMixShape) -> some View {
        let weight = settings.weight(shape)
        let share = Int((settings.share(of: shape) * 100).rounded())
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                ParentLabel(shape.titleTraditionalChinese, size: 15, weight: 800)
                ParentLabel(shape.titleEnglish, size: 11, weight: 700, color: .inkSoft)
            }
            .frame(width: 120, alignment: .leading)
            stepButton(symbol: "minus", enabled: weight > 0) { onAdjust(shape, -1) }
            ParentLabel("\(weight)", size: 18, weight: 900)
                .frame(width: 44)
            stepButton(symbol: "plus", enabled: weight < ShapeTraceSettings.maxWeight) { onAdjust(shape, 1) }
            ParentLabel(weight == 0 ? "唔出 / off" : "約 \(share)% / about \(share)%",
                        size: 13, weight: 700, color: .inkSoft)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(shape.titleTraditionalChinese) \(weight)")
    }

    private func stepButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.ink)
                .frame(width: 34, height: 28)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sunnyPale),
                                       cornerRadius: 10, shadowDepth: 3, lineWidth: 2))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
