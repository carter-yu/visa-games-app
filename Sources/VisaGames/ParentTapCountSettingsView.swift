import SwiftUI
import VisaCore

/// 數字設定: shared by the 3 一架一架數 cards (v0.28.0, design §10). UserDefaults only.
struct ParentTapCountSettingsView: View {
    let settings: TapCountSettings
    let shapeTraceSettings: ShapeTraceSettings
    let lineMatchTolerance: LineMatchTolerance
    let onRange: (TapCountRange) -> Void
    let onCountVoice: (Bool) -> Void
    let onEnglish: (Bool) -> Void
    let onBadgeStyle: (TapCountBadgeStyle) -> Void
    let onScaffold: (TapCountTraceScaffold) -> Void
    let onTolerance: (LineMatchTolerance?) -> Void
    /// v0.30.0 描數字提示 (多啲 / 標準 / 少啲) and the numerals the child has 識咗 (2 clean traces in a row).
    var learnedNumerals: [Int] = []
    var onGuidance: (TapCountGuidanceLevel) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TapCountIconView(kind: .tapCountAll)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    ParentLabel("\(TapCountCopy.parentGroupTitle) · \(TapCountCopy.settingsTitle)", size: 20, weight: 900)
                    ParentLabel("\(TapCountCopy.familyEnglish) · \(TapCountCopy.settingsSubtitle)", size: 12, weight: 700,
                                color: .inkSoft)
                }
            }
            ParentLabel("\(TapCountCopy.parentDefaultOff) / \(TapCountCopy.parentDefaultOffEnglish)", size: 12, weight: 600,
                        color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            choiceRow(title: TapCountCopy.rangeTitle, english: TapCountCopy.rangeEnglish) {
                ForEach(TapCountRange.allCases, id: \.self) { range in
                    choiceButton(title: range.label, subtitle: "", selected: settings.range == range) { onRange(range) }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                toggleRow(title: TapCountCopy.countVoiceTitle, detail: TapCountCopy.countVoiceEnglish,
                          on: settings.countVoice, action: onCountVoice)
                toggleRow(title: TapCountCopy.englishTitle, detail: TapCountCopy.englishEnglish,
                          on: settings.english, action: onEnglish)
            }
            choiceRow(title: TapCountCopy.badgeTitle, english: TapCountCopy.badgeEnglish) {
                ForEach(TapCountBadgeStyle.allCases, id: \.self) { style in
                    choiceButton(title: style.labelTraditionalChinese, subtitle: "",
                                 selected: settings.badgeStyle == style) { onBadgeStyle(style) }
                }
            }
            choiceRow(title: TapCountCopy.scaffoldTitle, english: TapCountCopy.scaffoldEnglish) {
                ForEach(TapCountTraceScaffold.allCases, id: \.self) { scaffold in
                    choiceButton(title: scaffold.labelTraditionalChinese, subtitle: "",
                                 selected: settings.traceScaffold == scaffold) { onScaffold(scaffold) }
                }
            }
            guidanceRow
            VStack(alignment: .leading, spacing: 8) {
                choiceRow(title: TapCountCopy.toleranceTitle, english: TapCountCopy.toleranceEnglish) {
                    choiceButton(title: TapCountCopy.toleranceFollow, subtitle: "",
                                 selected: settings.tolerance == nil) { onTolerance(nil) }
                    ForEach(LineMatchTolerance.allCases, id: \.self) { tolerance in
                        choiceButton(title: tolerance.labelTraditionalChinese, subtitle: tolerance.labelEnglish,
                                     selected: settings.tolerance == tolerance) { onTolerance(tolerance) }
                    }
                }
                let effective = settings.effectiveTolerance(shapeTrace: shapeTraceSettings, lineMatch: lineMatchTolerance)
                ParentLabel("而家：\(effective.labelTraditionalChinese) / Now: \(effective.labelEnglish)",
                            size: 12, weight: 600, color: .inkSoft)
            }
            ParentLabel("\(TapCountCopy.parentTip) / \(TapCountCopy.parentTipEnglish)", size: 12, weight: 600, color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.paper), cornerRadius: 18,
                              shadowDepth: 4, lineWidth: 3))
    }

    /// 描數字提示 (copy from the Opus guidance spec; ★★ / ★★★, both card languages).
    private var guidanceRow: some View {
        let parent = TapCountGuideData.copy.parent
        return VStack(alignment: .leading, spacing: 8) {
            ParentLabel(parent.title, size: 15, weight: 800)
            HStack(spacing: 10) {
                ForEach(TapCountGuidanceLevel.allCases, id: \.self) { level in
                    choiceButton(title: parent.short(level), subtitle: "",
                                 selected: settings.guidance == level) { onGuidance(level) }
                }
            }
            ParentLabel(parent.detail(settings.guidance), size: 12, weight: 600, color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            let learned = learnedNumerals.sorted().map(String.init).joined(separator: "、")
            ParentLabel(learned.isEmpty ? parent.learnedNote : "\(parent.learnedNote) \(learned)",
                        size: 12, weight: 600, color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choiceRow<Content: View>(title: String, english: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ParentLabel("\(title) / \(english)", size: 15, weight: 800)
            HStack(spacing: 10) { content() }
        }
    }

    private func choiceButton(title: String, subtitle: String, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ParentLabel(title, size: 16, weight: 900)
                if !subtitle.isEmpty {
                    ParentLabel(subtitle, size: 10, weight: 700, color: .inkSoft)
                }
            }
            .frame(width: 104)
            .padding(.vertical, 6)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: selected ? Color(hex: DesignTokens.Palette.sunny) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 12, shadowDepth: selected ? 2 : 3, lineWidth: 2))
        .accessibilityLabel(subtitle.isEmpty ? title : "\(title) / \(subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func toggleRow(title: String, detail: String, on: Bool, action: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: { action(!on) }) {
                ParentLabel(on ? "\(TapCountCopy.on) On" : "\(TapCountCopy.off) Off", size: 14, weight: 900)
                    .frame(width: 70)
                    .padding(.vertical, 5)
            }
            .buttonStyle(ChunkyButtonStyle(
                fill: on ? Color(hex: DesignTokens.Palette.sunny) : Color(hex: DesignTokens.Palette.paper),
                cornerRadius: 12, shadowDepth: on ? 2 : 3, lineWidth: 2))
            .accessibilityLabel("\(title) \(on ? TapCountCopy.on : TapCountCopy.off)")
            VStack(alignment: .leading, spacing: 0) {
                ParentLabel(title, size: 14, weight: 800)
                ParentLabel(detail, size: 11, weight: 600, color: .inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Parent card icon (mockup 09 tiles): the tile art plus its count badges' digits.
struct TapCountIconView: View {
    let kind: ActivityKind

    private var artwork: CanvasArtwork {
        switch kind.tapCountBase ?? kind {
        case .tapCountTrace: return TapCountArt.iconTrace
        case .tapCountPick: return TapCountArt.iconPick
        default: return TapCountArt.iconAll
        }
    }

    /// Digit centres in tile units (mockup 09 text positions minus the tile origin).
    private var digits: [(String, CGPoint, CGFloat)] {
        switch kind.tapCountBase ?? kind {
        case .tapCountAll: return [("1", CGPoint(x: 16, y: 26), 12), ("2", CGPoint(x: 40, y: 26), 12), ("3", CGPoint(x: 64, y: 26), 12)]
        case .tapCountPick: return [("1", CGPoint(x: 34, y: 13), 11), ("2", CGPoint(x: 72, y: 13), 11)]
        default: return []
        }
    }

    var body: some View {
        let art = artwork
        let anchor = TapCountArt.anchor(art)
        let marks = digits
        Canvas { context, size in
            var g = context
            let scale = min(size.width, size.height) / 80
            g.scaleBy(x: scale, y: scale)
            var layer = g
            layer.translateBy(x: -anchor.x, y: -anchor.y)
            VectorArtRenderer.draw(art, in: &layer, size: CGSize(width: art.width, height: art.height), contentMode: .fit)
            for (text, point, size) in marks {
                g.draw(Text(text).font(CanvasFont.font(size: size, weight: 800)).foregroundColor(Color(hex: 0x2B2630)),
                       at: point, anchor: .center)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
