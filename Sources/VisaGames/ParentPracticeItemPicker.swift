import SwiftUI
import VisaCore

/// Script-neutral parent editor. The host owns the draft, persistence and symbol renderer.
struct ParentPracticeItemPicker<Symbol: View>: View {
    let model: PracticePickerModel
    @Binding var selectedIDs: Set<String>
    let symbol: (PracticePickerItem) -> Symbol
    let capabilityLabel: (PracticePickerItem, PracticePickerAvailability?) -> String
    let primaryPresetCount: Int
    let secondaryPresetTitle: String
    var onReplace: (PracticePickerPresetPreview, String) -> Void
    @State private var previewID: String? = nil
    @State private var showSecondaryPresets = false

    private let ink = Color(hex: DesignTokens.Palette.ink)
    private let paper = Color(hex: DesignTokens.Palette.paper)
    private let sunny = Color(hex: DesignTokens.Palette.sunny)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(Array(model.presets.prefix(primaryPresetCount)), id: \.id) { preset in
                    presetButton(preset)
                }
            }
            if model.presets.count > primaryPresetCount {
                DisclosureGroup(secondaryPresetTitle, isExpanded: $showSecondaryPresets) {
                    VStack(spacing: 8) {
                        ForEach(Array(model.presets.dropFirst(primaryPresetCount)), id: \.id) { preset in
                            presetButton(preset)
                        }
                    }
                }
            }
            if let previewID, let preset = model.presets.first(where: { $0.id == previewID }),
               let preview = model.previewPreset(previewID) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(preset.label)：會揀 \(names(preview.includedIDs))；未開放 \(names(preview.omittedIDs))。")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("套用會換走今次選擇，之後可以再加減。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    HStack {
                        Button("取消預覽") { self.previewID = nil }
                        Button("套用呢組") {
                            onReplace(preview, preset.id)
                            self.previewID = nil
                        }
                        .disabled(!preview.canApply)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color(hex: DesignTokens.Palette.sky).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("亮燈：揀咗　○ 暗燈：可揀　□ 鎖住：未開放")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            let targets = model.items.filter { $0.role == .target }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<((targets.count + 6) / 7), id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(Array(targets.dropFirst(row * 7).prefix(7)), id: \.id) { item in
                            tile(item).frame(width: 86)
                        }
                    }
                }
            }
            let locked = model.items.filter { $0.role == .target && !model.isSelectable($0.id) }
            if !locked.isEmpty {
                let lockedNames = locked.map(\.label).joined(separator: "、")
                let lockedReasons = Array(Set(locked.compactMap {
                    model.availabilityByItem[$0.id]?.reason
                })).sorted().joined(separator: "；")
                Text("未開放：\(lockedNames)。\(lockedReasons)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(ink)
    }

    private func names(_ ids: [String]) -> String { ids.isEmpty ? "無" : ids.joined(separator: "、") }

    private func presetButton(_ preset: PracticePickerPreset) -> some View {
        Button { previewID = preset.id } label: {
            Text(preset.label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(ChunkyButtonStyle(fill: paper, cornerRadius: 12, shadowDepth: 2, lineWidth: 2))
        .disabled(model.previewPreset(preset.id)?.canApply != true)
        .accessibilityHint("預覽後可以取代今次選擇")
        .help(model.previewPreset(preset.id)?.canApply == true ? "預覽呢組" : "呢組暫時冇可用項目")
    }

    private func tile(_ item: PracticePickerItem) -> some View {
        let selected = selectedIDs.contains(item.id)
        let availability = model.availabilityByItem[item.id]
        let ready = model.isSelectable(item.id)
        let badge = capabilityLabel(item, availability)
        let reason = availability?.reason ?? "未開放"
        return Button {
            selectedIDs = PracticePickerSelection.reduce(model: model, enabledIDs: selectedIDs,
                intent: .toggle(item.id))
        } label: {
            VStack(spacing: 3) {
                HStack {
                    Spacer()
                    Image(systemName: ready ? (selected ? "lightbulb.fill" : "lightbulb") : "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                }
                symbol(item)
                    .frame(width: 38, height: 48)
                    .accessibilityHidden(true)
                Text(badge)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(5)
            .background(selected ? sunny : paper, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(ink.opacity(ready ? 1 : 0.5), style: StrokeStyle(lineWidth: selected ? 3 : 2,
                    dash: ready ? [] : [5, 4])))
        }
        .buttonStyle(.plain)
        .disabled(!ready && !selected)
        .help(ready ? badge : reason)
        .accessibilityLabel("\(item.label)，\(selected ? "揀咗" : "未揀")，\(badge)\(ready ? "" : "，\(reason)")")
        .accessibilityHint(!ready && selected ? "可移除，儲存前必須移除" : ready ? "撳一下切換選擇" : "未開放")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
