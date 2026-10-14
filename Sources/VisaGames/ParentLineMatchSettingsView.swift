import SwiftUI
import VisaCore

/// 家長 → 遊戲 → 連一連設定 (v0.23.0 / v0.24.1): line tolerance 窄 / 標準 / 闊 and the
/// category weights (0–100 in steps of 5; 0 = never; the last category cannot be turned off;
/// 還原預設). Shared by 沿路送 / 沿路過橋 / 自己配. Plain stacks and buttons only — no text
/// input, no grids, no animation.
struct ParentLineMatchSettingsView: View {
    let settings: LineMatchSettings
    let banner: String?
    let onTolerance: (LineMatchTolerance) -> Void
    let onAdjust: (LineMatchCategory, Int) -> Void
    let onResetMix: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VectorArtView(artwork: LineMatchArt.miniTruck)
                    .frame(width: 54, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    ParentLabel("連一連設定", size: 20, weight: 900)
                    ParentLabel("Line Match settings · 三個遊戲共用；每個要喺上面開星級 / shared by the three cards; each off until a star is on",
                                size: 12, weight: 700, color: .inkSoft)
                }
            }
            if let banner {
                ParentBanner(text: banner, fill: Color(hex: DesignTokens.Palette.taxiTicket))
            }
            VStack(alignment: .leading, spacing: 8) {
                ParentLabel("畫線寬容度 / Line tolerance", size: 15, weight: 800)
                HStack(spacing: 10) {
                    ForEach(LineMatchTolerance.allCases, id: \.self) { tolerance in
                        toleranceButton(tolerance)
                    }
                }
                ParentLabel("判定範圍：點附近 \(Int(settings.tolerance.dotRadius))u；引導路面 ×\(String(format: "%.1f", settings.tolerance.roadWidthFactor))（畫出嚟嘅點同路唔變） / Hit radius around each dot; guided road corridor",
                            size: 12, weight: 600, color: .inkSoft)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ParentLabel("類別比例 / Category mix", size: 15, weight: 800)
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
                ForEach(LineMatchCategory.allCases, id: \.self) { category in
                    weightRow(category)
                }
                ParentLabel("★ 唔出十二生肖。0 = 唔出。沿路送用 ★ 題庫；沿路過橋用 ★★ 題庫。 / ★ never deals the zodiac. 0 = never. Straight uses ★ items; bridge uses ★★.",
                            size: 12, weight: 600, color: .inkSoft)
            }
        }
        .padding(16)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.paper), cornerRadius: 18,
                              shadowDepth: 4, lineWidth: 3))
    }

    private func toleranceButton(_ tolerance: LineMatchTolerance) -> some View {
        let selected = settings.tolerance == tolerance
        return Button(action: { onTolerance(tolerance) }) {
            VStack(spacing: 0) {
                ParentLabel(tolerance.labelTraditionalChinese, size: 18, weight: 900)
                ParentLabel(tolerance.labelEnglish, size: 11, weight: 700, color: .inkSoft)
            }
            .frame(width: 96)
            .padding(.vertical, 6)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: selected ? Color(hex: DesignTokens.Palette.sunny) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 12, shadowDepth: selected ? 2 : 3, lineWidth: 2))
        .accessibilityLabel("寬容度 \(tolerance.labelTraditionalChinese) / Tolerance \(tolerance.labelEnglish)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func weightRow(_ category: LineMatchCategory) -> some View {
        let weight = settings.weight(category)
        let share = Int((settings.share(of: category, at: .l3) * 100).rounded())
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                ParentLabel(category.titleTraditionalChinese, size: 15, weight: 800)
                ParentLabel(category.titleEnglish, size: 11, weight: 700, color: .inkSoft)
            }
            .frame(width: 120, alignment: .leading)
            stepButton(symbol: "minus", enabled: weight > 0) { onAdjust(category, -1) }
            ParentLabel("\(weight)", size: 18, weight: 900)
                .frame(width: 44)
            stepButton(symbol: "plus", enabled: weight < LineMatchSettings.maxWeight) { onAdjust(category, 1) }
            ParentLabel(weight == 0 ? "唔出 / off" : "約 \(share)% / about \(share)%",
                        size: 13, weight: 700, color: .inkSoft)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(category.titleTraditionalChinese) \(weight)")
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
