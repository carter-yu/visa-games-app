import SwiftUI
import VisaCore

/// Tile, preset and legend sizes shared by the picker and its loading placeholder (build 79),
/// so the grid area keeps one height while the cards load. Nine columns per design D2 /
/// picker-spec `preferredColumns`: 9 × 84 pt + 8 × 8 pt = 820 pt, the letter card's inner
/// width (852 pt section − 2 × 16 pt panel padding). 84 × 92 pt stays above the 64 pt target.
enum ParentPickerMetrics {
    static let tileWidth: CGFloat = 84
    static let tileHeight: CGFloat = 92
    static let tileSpacing: CGFloat = 8
    static let tileCorner: CGFloat = 12
    static let presetHeight: CGFloat = 54
    static let presetSpacing: CGFloat = 10
    static let disclosureHeight: CGFloat = 44
    static let legendHeight: CGFloat = 60
    static let sectionSpacing: CGFloat = 12
}

/// Host-supplied capability wording for one tile. The picker never decides playability.
struct ParentPickerBadge {
    enum Tone { case full, partial, notReady }
    let zh: String
    let en: String
    let tone: Tone
}

/// A preset-row action shown before it exists (睇吓練習建議, design D8/D9): always visible,
/// disabled, with its reason.
struct ParentPickerPlaceholderAction {
    let title: String
    let subtitle: String
    let help: String
}

/// Tile light states (design D2 table, picker-spec `visualStates`).
enum ParentPickerTileState: Equatable {
    /// Selected and ready: warm yellow, solid lamp + ✓, heavier outline.
    case lit
    /// Ready, not selected: muted warm fill, hollow lamp, solid outline, still tappable.
    case dim
    /// Not ready and not selected: dashed outline and lock; no lamp.
    case locked
    /// Saved/selected but no longer ready: 已揀・暫停 with a warning outline; tap removes it.
    case selectedUnavailable

    var fill: Color {
        switch self {
        case .lit: return Color(hex: DesignTokens.Palette.sunny)
        case .dim: return Color(hex: DesignTokens.Palette.hubcap)
        case .locked: return Color(hex: DesignTokens.Palette.paper)
        case .selectedUnavailable: return Color(hex: DesignTokens.Palette.fireTicket)
        }
    }
}

/// The lamp / ✓ / lock / warning marks, shared by tiles and the legend so they always match.
struct ParentPickerLamp: View {
    let state: ParentPickerTileState
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 1) {
            switch state {
            case .lit:
                Image(systemName: "lightbulb.fill")
                Image(systemName: "checkmark")
            case .dim:
                Image(systemName: "lightbulb")
            case .locked:
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.inkSoft)
            case .selectedUnavailable:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(hex: DesignTokens.Palette.tomato))
            }
        }
        .font(.system(size: size, weight: .bold))
        .foregroundStyle(Color.ink)
        .accessibilityHidden(true)
    }
}

/// Small capability / state badge at the foot of a tile (and in the legend).
struct ParentPickerBadgeView: View {
    enum Style { case full, partial, warning, plain }
    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(style == .plain ? Color.inkSoft : Color.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background {
                if style != .plain {
                    ZStack {
                        Capsule().fill(fill)
                        Capsule().strokeBorder(border, lineWidth: 1.5)
                    }
                }
            }
    }

    private var fill: Color {
        switch style {
        case .full: return .white
        case .partial: return Color(hex: DesignTokens.Palette.sand)
        case .warning: return Color(hex: DesignTokens.Palette.paper)
        case .plain: return .clear
        }
    }

    private var border: Color {
        style == .warning ? Color(hex: DesignTokens.Palette.tomato) : Color.ink
    }

    static func style(for tone: ParentPickerBadge.Tone) -> Style {
        switch tone {
        case .full: return .full
        case .partial: return .partial
        case .notReady: return .plain
        }
    }
}

/// 亮起＝已揀；暗色＝未揀；鎖住＝未開放 (design D2 legend) with the tiles' own marks, plus the
/// capability badges the host explains.
struct ParentPickerLegend: View {
    let capabilityLegend: [ParentPickerBadge]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 16) {
                item(.lit, "亮起＝已揀")
                item(.dim, "暗色＝未揀")
                item(.locked, "鎖住＝未開放")
                Spacer(minLength: 0)
            }
            ParentLabel("Lit = enabled; dim = off; locked = not ready.", size: 11, weight: 600, color: .inkSoft)
            if !capabilityLegend.isEmpty {
                HStack(spacing: 8) {
                    ParentLabel("遊戲支援 / Capability", size: 11, weight: 800, color: .inkSoft)
                    ForEach(Array(capabilityLegend.enumerated()), id: \.offset) { _, badge in
                        ParentPickerBadgeView(text: badge.zh, style: ParentPickerBadgeView.style(for: badge.tone))
                        ParentLabel(badge.en, size: 11, weight: 600, color: .inkSoft)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: ParentPickerMetrics.legendHeight, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func item(_ state: ParentPickerTileState, _ text: String) -> some View {
        HStack(spacing: 5) {
            ParentPickerLamp(state: state, size: 10)
                .frame(width: 30, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(state.fill))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(
                    state == .locked ? Color.inkSoft : Color.ink,
                    style: StrokeStyle(lineWidth: state == .lit ? 2 : 1.5, dash: state == .locked ? [3, 2] : [])))
            ParentLabel(text, size: 12, weight: 800)
        }
    }
}

/// Script-neutral parent editor. The host owns the draft, persistence and symbol renderer.
struct ParentPracticeItemPicker<Symbol: View>: View {
    let model: PracticePickerModel
    @Binding var selectedIDs: Set<String>
    let symbol: (PracticePickerItem) -> Symbol
    let capability: (PracticePickerItem, PracticePickerAvailability?) -> ParentPickerBadge
    /// Badges explained in the legend's capability line (e.g. 搵＋寫, 只可搵).
    let capabilityLegend: [ParentPickerBadge]
    /// Catalog layout from the host (letters: 9, design D2).
    let columns: Int
    let primaryPresetCount: Int
    let secondaryPresetTitle: String
    let secondaryPresetEnglish: String
    var placeholderAction: ParentPickerPlaceholderAction? = nil
    var onReplace: (PracticePickerPresetPreview, String) -> Void
    @State private var previewID: String? = nil
    @State private var showSecondaryPresets = false

    var body: some View {
        VStack(alignment: .leading, spacing: ParentPickerMetrics.sectionSpacing) {
            presetRow(Array(model.presets.prefix(primaryPresetCount)),
                      slots: primaryPresetCount + (placeholderAction == nil ? 0 : 1),
                      placeholder: placeholderAction)
            if model.presets.count > primaryPresetCount {
                ParentDisclosureButton(title: secondaryPresetTitle, english: secondaryPresetEnglish,
                                       isOpen: showSecondaryPresets) {
                    showSecondaryPresets.toggle()
                }
                .frame(height: ParentPickerMetrics.disclosureHeight)
                if showSecondaryPresets {
                    let school = Array(model.presets.dropFirst(primaryPresetCount))
                    VStack(alignment: .leading, spacing: ParentPickerMetrics.presetSpacing) {
                        ForEach(0..<((school.count + 3) / 4), id: \.self) { row in
                            presetRow(Array(school.dropFirst(row * 4).prefix(4)), slots: 4, placeholder: nil)
                        }
                    }
                }
            }
            if let previewID, let preset = model.presets.first(where: { $0.id == previewID }),
               let preview = model.previewPreset(previewID) {
                previewPanel(preset: preset, preview: preview)
            }
            ParentPickerLegend(capabilityLegend: capabilityLegend)
            grid
            gridNotes
        }
        .foregroundStyle(Color.ink)
        .onChange(of: previewID) { value in
            ParentScrollDiagnostics.record("PICKER preview present=\(value != nil)")
        }
        .onChange(of: showSecondaryPresets) { value in
            ParentScrollDiagnostics.record("PICKER schoolDisclosure expanded=\(value)")
        }
    }

    // MARK: Presets

    /// Equal-width chunky buttons; empty slots keep a short last row aligned with the row above.
    private func presetRow(_ presets: [PracticePickerPreset], slots: Int,
                           placeholder: ParentPickerPlaceholderAction?) -> some View {
        let used = presets.count + (placeholder == nil ? 0 : 1)
        return HStack(spacing: ParentPickerMetrics.presetSpacing) {
            ForEach(presets, id: \.id) { preset in
                presetButton(preset)
            }
            if let placeholder {
                placeholderButton(placeholder)
            }
            ForEach(0..<max(0, slots - used), id: \.self) { _ in
                Color.clear.frame(maxWidth: .infinity, minHeight: 1)
            }
        }
    }

    private func presetButton(_ preset: PracticePickerPreset) -> some View {
        let preview = model.previewPreset(preset.id)
        let canApply = preview?.canApply == true
        let omitted = preview?.omittedIDs ?? []
        let note = omitted.isEmpty ? preset.subtitle
            : [preset.subtitle, "\(names(omitted)) 未開放"].filter { !$0.isEmpty }.joined(separator: " · ")
        return Button { previewID = preset.id } label: {
            presetLabel(title: preset.label, subtitle: note)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: previewID == preset.id ? Color(hex: DesignTokens.Palette.sunnyPale) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 12, shadowDepth: 3, lineWidth: 2))
        .disabled(!canApply)
        .opacity(canApply ? 1 : 0.5)
        .accessibilityLabel(note.isEmpty ? preset.label : "\(preset.label) / \(note)")
        .accessibilityHint("預覽之後可以換走今次選擇 / Preview, then replace this selection")
        .help(canApply ? "預覽呢組 / Preview this group" : "呢組暫時冇可以揀嘅 / Nothing in this group is ready yet")
    }

    private func placeholderButton(_ action: ParentPickerPlaceholderAction) -> some View {
        Button(action: {}) {
            presetLabel(title: action.title, subtitle: action.subtitle)
        }
        .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.paper),
                                       cornerRadius: 12, shadowDepth: 3, lineWidth: 2))
        .disabled(true)
        .opacity(0.5)
        .help(action.help)
        .accessibilityLabel("\(action.title) / \(action.subtitle)")
        .accessibilityHint(action.help)
    }

    private func presetLabel(title: String, subtitle: String) -> some View {
        VStack(spacing: 1) {
            ParentLabel(title, size: 15, weight: 900)
            if !subtitle.isEmpty {
                ParentLabel(subtitle, size: 11, weight: 700, color: .inkSoft)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: ParentPickerMetrics.presetHeight)
    }

    private func previewPanel(preset: PracticePickerPreset, preview: PracticePickerPresetPreview) -> some View {
        let name = preset.subtitle.isEmpty ? preset.label : "\(preset.label)（\(preset.subtitle)）"
        let missing = preview.omittedIDs.isEmpty ? "" : "；\(names(preview.omittedIDs)) 未開放"
        let missingEnglish = preview.omittedIDs.isEmpty ? "" : "; \(names(preview.omittedIDs)) not ready"
        return VStack(alignment: .leading, spacing: 5) {
            ParentLabel("\(name)：會揀 \(names(preview.includedIDs))\(missing)。", size: 13, weight: 800)
                .fixedSize(horizontal: false, vertical: true)
            ParentLabel("Will choose \(names(preview.includedIDs))\(missingEnglish).", size: 11, weight: 600,
                        color: .inkSoft)
            ParentLabel("套用會換走今次選擇，之後可以再加減。", size: 12, weight: 700)
            ParentLabel("Using it replaces this selection; you can still add or remove afterwards.",
                        size: 11, weight: 600, color: .inkSoft)
            HStack(spacing: 10) {
                ParentSmallButton(title: "取消預覽 / Close preview", symbol: "xmark") {
                    self.previewID = nil
                }
                ParentSmallButton(title: "套用呢組 / Use this group", symbol: "checkmark",
                                  fill: Color(hex: DesignTokens.Palette.sunny)) {
                    onReplace(preview, preset.id)
                    self.previewID = nil
                }
                .disabled(!preview.canApply)
                .opacity(preview.canApply ? 1 : 0.45)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.metroTicket), cornerRadius: 12,
                              shadowDepth: 3, lineWidth: 2))
    }

    // MARK: Tiles

    private var grid: some View {
        let targets = model.items.filter { $0.role == .target }
        let columns = max(1, self.columns)
        return VStack(alignment: .leading, spacing: ParentPickerMetrics.tileSpacing) {
            ForEach(0..<((targets.count + columns - 1) / columns), id: \.self) { row in
                HStack(spacing: ParentPickerMetrics.tileSpacing) {
                    ForEach(Array(targets.dropFirst(row * columns).prefix(columns)), id: \.id) { item in
                        tile(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tile(_ item: PracticePickerItem) -> some View {
        let selected = selectedIDs.contains(item.id)
        let ready = model.isSelectable(item.id)
        let availability = model.availabilityByItem[item.id]
        let badge = capability(item, availability)
        let reason = availability?.reason ?? "未開放"
        let state: ParentPickerTileState = ready ? (selected ? .lit : .dim)
            : (selected ? .selectedUnavailable : .locked)
        let paused = state == .selectedUnavailable
        let spoken = "\(item.label)，\(selected ? "已揀" : "未揀")，\(paused ? "已揀・暫停" : badge.zh)\(ready ? "" : "，\(reason)")"
            + " / \(item.label), \(selected ? "enabled" : "off"), \(paused ? "Selected · unavailable" : badge.en)"
        if state == .locked {
            tileFace(item, state: state, badge: badge)
                .background(RoundedRectangle(cornerRadius: ParentPickerMetrics.tileCorner).fill(state.fill))
                .overlay(RoundedRectangle(cornerRadius: ParentPickerMetrics.tileCorner)
                    .strokeBorder(Color.inkSoft, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                .help(reason)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
                .accessibilityHint("未開放 / Not ready")
        } else {
            Button {
                ParentScrollDiagnostics.record("PICKER tile action selectedBefore=\(selected)")
                selectedIDs = PracticePickerSelection.reduce(model: model, enabledIDs: selectedIDs,
                    intent: .toggle(item.id))
            } label: {
                tileFace(item, state: state, badge: badge)
            }
            .buttonStyle(ChunkyButtonStyle(fill: state.fill, cornerRadius: ParentPickerMetrics.tileCorner,
                                           shadowDepth: 3, lineWidth: state == .lit ? 3 : 2))
            .help(ready ? "\(badge.zh) / \(badge.en)" : reason)
            .accessibilityLabel(spoken)
            .accessibilityHint(paused ? "撳一下就移除；儲存之前要移除 / Tap to remove before saving"
                : "撳一下開或者熄 / Tap to switch on or off")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    private func tileFace(_ item: PracticePickerItem, state: ParentPickerTileState,
                          badge: ParentPickerBadge) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ParentPickerLamp(state: state)
            }
            .frame(height: 14)
            symbol(item)
                .frame(width: 34, height: 42)
                .opacity(state == .locked ? 0.55 : 1)
                .accessibilityHidden(true)
            ParentPickerBadgeView(
                text: state == .selectedUnavailable ? "已揀・暫停" : badge.zh,
                style: state == .selectedUnavailable ? .warning
                    : (state == .locked ? .plain : ParentPickerBadgeView.style(for: badge.tone)))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .frame(width: ParentPickerMetrics.tileWidth, height: ParentPickerMetrics.tileHeight)
        .overlay {
            if state == .selectedUnavailable {
                // Warning outline just inside the chunky ink outline (design D2 已揀・暫停).
                RoundedRectangle(cornerRadius: ParentPickerMetrics.tileCorner - 2)
                    .strokeBorder(Color(hex: DesignTokens.Palette.tomato), lineWidth: 3)
                    .padding(2)
            }
        }
    }

    @ViewBuilder
    private var gridNotes: some View {
        let targets = model.items.filter { $0.role == .target }
        let paused = targets.filter { selectedIDs.contains($0.id) && !model.isSelectable($0.id) }
        let locked = targets.filter { !selectedIDs.contains($0.id) && !model.isSelectable($0.id) }
        if !paused.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ParentLabel("已揀・暫停：\(paused.map(\.label).joined(separator: "、"))。撳一下就移除；儲存之前要移除。",
                            size: 12, weight: 800)
                    .fixedSize(horizontal: false, vertical: true)
                ParentLabel("Selected · unavailable: tap to remove before saving.", size: 11, weight: 600,
                            color: .inkSoft)
            }
        }
        if !locked.isEmpty {
            let reasons = Array(Set(locked.compactMap { model.availabilityByItem[$0.id]?.reason })).sorted()
                .joined(separator: "；")
            VStack(alignment: .leading, spacing: 1) {
                ParentLabel("未開放：\(locked.map(\.label).joined(separator: "、"))。\(reasons)",
                            size: 11, weight: 700, color: .inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                ParentLabel("Locked items are shown for parents; they can't be chosen yet.", size: 11,
                            weight: 600, color: .inkSoft)
            }
        }
    }

    private func names(_ ids: [String]) -> String {
        guard !ids.isEmpty else { return "無" }
        return ids.map { id in model.items.first(where: { $0.id == id })?.label ?? id }.joined(separator: "、")
    }
}

/// Loading stand-in built from the picker's own preset, disclosure, legend and tile sizes
/// (build 79, UX nit n2), so the page does not collapse to one line and then jump.
struct ParentPracticeItemPickerPlaceholder: View {
    let itemCount: Int
    let columns: Int
    let presetCount: Int
    let message: String
    let english: String

    var body: some View {
        let columns = max(1, self.columns)
        let dashed = StrokeStyle(lineWidth: 2, dash: [5, 4])
        VStack(alignment: .leading, spacing: ParentPickerMetrics.sectionSpacing) {
            HStack(spacing: ParentPickerMetrics.presetSpacing) {
                ForEach(0..<max(1, presetCount), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.inkSoft.opacity(0.5), style: dashed)
                        .frame(maxWidth: .infinity)
                        .frame(height: ParentPickerMetrics.presetHeight)
                }
            }
            Color.clear.frame(height: ParentPickerMetrics.disclosureHeight)
            VStack(alignment: .leading, spacing: 3) {
                ParentLabel(message, size: 14, weight: 800, color: .inkSoft)
                ParentLabel(english, size: 11, weight: 600, color: .inkSoft)
            }
            .frame(height: ParentPickerMetrics.legendHeight, alignment: .topLeading)
            VStack(alignment: .leading, spacing: ParentPickerMetrics.tileSpacing) {
                ForEach(0..<((max(0, itemCount) + columns - 1) / columns), id: \.self) { row in
                    HStack(spacing: ParentPickerMetrics.tileSpacing) {
                        ForEach(0..<min(columns, max(0, itemCount) - row * columns), id: \.self) { _ in
                            RoundedRectangle(cornerRadius: ParentPickerMetrics.tileCorner)
                                .strokeBorder(Color.inkSoft.opacity(0.4), style: dashed)
                                .frame(width: ParentPickerMetrics.tileWidth, height: ParentPickerMetrics.tileHeight)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(message) / \(english)")
    }
}
