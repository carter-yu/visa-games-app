import SwiftUI
import VisaCore

/// One parent draft for both English letter games. The view is destroyed on leaving Games.
struct ParentTapLetterSettingsView: View {
    @ObservedObject var model: AppModel
    let onShowWriteAssignment: () -> Void
    @State private var draft: LetterPickerDraft? = nil
    @State private var history: [String] = []
    @State private var notice: String? = nil
    @State private var showMore = false
    @State private var repairCorrupt = false

    private var capabilities: [String: LetterCapability] { model.letterCapabilities() }
    private var selected: Set<String> { Set(draft?.value.focusLetters ?? []) }
    private var candidates: [String] {
        history.filter { capabilities[$0]?.canFind == true && !selected.contains($0) }
    }

    private var picker: PracticePickerModel? {
        guard let base = model.letterPickerModel(enabled: selected) else { return nil }
        let school: [PracticePickerPreset] = [LetterPath.abc, .jolly, .lettersAndSounds].flatMap { path in
            let title: String
            switch path {
            case .abc: title = "ABC"
            case .jolly: title = "Jolly Phonics"
            case .lettersAndSounds: title = "Letters and Sounds"
            case .custom: title = ""
            }
            return path.groups.enumerated().map { index, letters in
                PracticePickerPreset(id: "school.\(path.rawValue).\(index + 1)",
                    label: "\(title) \(index + 1) · \(letters.joined(separator: " "))", itemIDs: letters)
            }
        }
        return PracticePickerModel(catalogID: base.catalogID, catalogRevision: base.catalogRevision,
            items: base.items, availabilityByItem: base.availabilityByItem, enabledIDs: base.enabledIDs,
            presets: base.presets + [PracticePickerPreset(id: "practised90",
                label: "近 90 日練過 / Practised in 90 days", itemIDs: history)] + school,
            minimum: base.minimum, maximum: base.maximum)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                LatinLetterGlyph(letter: "b", ink: .ink, lineWidth: 24)
                    .frame(width: 30, height: 40)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    ParentLabel("英文字母 ABC · 字母設定", size: 20, weight: 900)
                    ParentLabel("Letters ABC · Shared by both letter games", size: 12, weight: 700, color: .inkSoft)
                }
                Spacer()
                if let draft {
                    ParentLabel("\(draft.hasChanges ? "未儲存" : "已儲存") · \(draft.value.focusLetters.count) 個",
                                size: 12, weight: 700, color: .inkSoft)
                }
            }
            ParentLabel("今次練邊啲字母？", size: 18, weight: 900)
            ParentLabel("撳字格揀字母，儲存之後下一題開始用。最少揀 1 個。", size: 12, weight: 600, color: .inkSoft)
            if case .legacy(_, let previous) = model.letterParentLoad {
                ParentLabel("儲存後只練揀咗嘅字母；想溫舊字母，可以下面開返。之前設定：每 \(previous) 局溫 1 局。",
                            size: 12, weight: 700, color: .inkSoft)
            }
            if model.letterParentLoad == .repairV1 {
                ParentBanner(text: "舊字母設定讀唔到。請檢查呢組字母，再儲存修復。",
                             fill: Color(hex: DesignTokens.Palette.sand))
            }
            if model.letterParentLoad == .corruptV2 {
                ParentBanner(text: "字母設定讀唔到。字母遊戲暫停；請檢查後選擇修復。",
                             fill: Color(hex: DesignTokens.Palette.sand))
                Button(repairCorrupt ? "✓ 已選擇修復" : "修復字母設定") { repairCorrupt = true }
                    .buttonStyle(.bordered)
            }
            if let picker, draft != nil {
                ParentPracticeItemPicker(model: picker, selectedIDs: Binding(
                    get: { selected }, set: { newValue in
                        guard let id = selected.symmetricDifference(newValue).first else { return }
                        change { $0.toggleFocus(id) }
                    }), symbol: { item in
                        LatinLetterGlyph(letter: item.label, ink: .ink, lineWidth: 24)
                    }, capabilityLabel: { _, availability in
                        availability?.consumers.contains("write") == true ? "搵＋寫"
                            : availability?.consumers.contains("find") == true ? "只可搵" : "未開放"
                    }, primaryPresetCount: 3, secondaryPresetTitle: "按學校次序 / School sequence",
                    onReplace: { preview, id in
                        change { $0.replaceFocus(preview.includedIDs, source: id) }
                    })
                Button("睇吓練習建議 · 未開放") {}
                    .disabled(true)
                    .help("練習建議仲未有足夠嘅小朋友練習證據計算，暫時未開放。")
                    .accessibilityHint("未開放：練習證據分析尚未提供")
                ParentLabel("練習建議嘅小朋友練習證據分析未做好，暫時未開放。", size: 12,
                            weight: 600, color: .inkSoft)
                ParentLabel("有玩過，唔代表已經熟晒。", size: 12, weight: 600, color: .inkSoft)
                summary
                reviewControls
                DisclosureGroup("更多字母設定", isExpanded: $showMore) {
                    Toggle("鏡像字母保護", isOn: Binding(
                        get: { draft?.value.mirrorGuard ?? true },
                        set: { value in change { $0.setMirrorGuard(value) } }))
                    ParentLabel("減少容易混淆嘅字母同時出現。", size: 12, weight: 600, color: .inkSoft)
                }
                if let notice { ParentBanner(text: notice, fill: Color(hex: DesignTokens.Palette.sand)) }
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        ParentLabel("儲存後，下局開始用。", size: 12, weight: 700)
                        ParentLabel("未儲存嘅改動唔會套用。", size: 12, weight: 600, color: .inkSoft)
                    }
                    Spacer()
                    Button("還原今次改動") { change { $0.revert() }; repairCorrupt = false }
                    Button("取消") { change { $0.cancel() }; repairCorrupt = false }
                    Button("儲存") { save() }
                        .disabled(model.letterParentLoad == .corruptV2 && !repairCorrupt)
                }
                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sunny),
                                               cornerRadius: 12, shadowDepth: 2, lineWidth: 2))
            } else {
                ParentBanner(text: "字母卡未能讀取，暫時儲存唔到。", fill: Color(hex: DesignTokens.Palette.sand))
            }
        }
        .padding(16)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.paper), cornerRadius: 18,
                              shadowDepth: 4, lineWidth: 3))
        .onAppear { openDraft() }
        .onDisappear { draft = nil; notice = nil; repairCorrupt = false }
    }

    private var summary: some View {
        let find = draft?.value.focusLetters.filter { capabilities[$0]?.canFind == true } ?? []
        let write = draft?.value.focusLetters.filter { capabilities[$0]?.canWrite == true } ?? []
        let unavailable = draft?.value.focusLetters.filter { capabilities[$0]?.canFind != true } ?? []
        return VStack(alignment: .leading, spacing: 5) {
            ParentLabel("儲存後會問嘅字母", size: 14, weight: 900)
            ParentLabel("翻字卡：\(list(find))", size: 13, weight: 700)
            ParentLabel("搵完寫：\(list(write))", size: 13, weight: 700)
            if !unavailable.isEmpty {
                ParentLabel("已揀但未開放：\(list(unavailable))。請移除先儲存。", size: 12, weight: 700,
                            color: .inkSoft)
            }
            if write.isEmpty {
                ParentLabel("呢組暫時玩唔到『搵完寫』。", size: 12, weight: 700)
                if !model.gameAssignment.isHiddenFromMissions(.tapLetterWrite) {
                    Button("返去搵完寫遊戲卡設定") { onShowWriteAssignment() }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
    }

    private var reviewControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ParentLabel("溫習其他字母", size: 15, weight: 900)
            ParentLabel(draft?.value.reviewEvery == 4 ? "而家：每 4 局最多 1 局" : "而家：熄，只練揀咗嘅",
                        size: 12, weight: 700, color: .inkSoft)
            HStack {
                Button("熄 · 只練揀咗嘅") { change { $0.setReviewEvery(0, candidates: []) } }
                Button("每 4 局最多 1 局") { change { $0.setReviewEvery(4, candidates: candidates) } }
                    .disabled(candidates.isEmpty && (draft?.value.reviewLetters.isEmpty ?? true))
            }
            .buttonStyle(.bordered)
            if draft?.value.reviewEvery == 4 {
                ParentLabel("題目會包括：主練 \(list(draft?.value.focusLetters ?? []))；每 4 局最多 1 局溫 \(list(draft?.value.reviewLetters ?? []))。",
                            size: 12, weight: 700)
                ParentLabel("翻字卡溫習：\(list(review(for: .tapLetterAll)))；搵完寫溫習：\(list(review(for: .tapLetterWrite)))。",
                            size: 12, weight: 600, color: .inkSoft)
                HStack {
                    ForEach(draft?.value.reviewLetters ?? [], id: \.self) { letter in
                        Button("\(letter) ×") { change { $0.removeReview(letter) } }
                            .accessibilityLabel("移除溫習字母 \(letter)")
                    }
                    Button("重新揀溫習字母") { change { $0.refreshReview(candidates) } }
                }
                .buttonStyle(.bordered)
            }
            ParentLabel("只會叫小朋友搵／寫上面揀咗嘅字母；其他字母仍可做陪襯。", size: 12, weight: 600,
                        color: .inkSoft)
        }
    }

    private func review(for kind: ActivityKind) -> [String] {
        draft?.value.review(for: kind, availability: capabilities) ?? []
    }
    private func list(_ letters: [String]) -> String { letters.isEmpty ? "無" : letters.joined(separator: "、") }
    private func change(_ edit: (inout LetterPickerDraft) -> Void) {
        guard var draft else { return }
        edit(&draft)
        self.draft = draft
        notice = nil
    }
    private func openDraft() {
        history = model.practicedLetterTargets()
        draft = LetterPickerDraft(saved: model.letterParentLoad.effective ?? .defaults)
        notice = nil
        repairCorrupt = false
    }
    private func save() {
        guard var draft else { return }
        do {
            let saved = try model.saveLetterSelection(draft.value, repairCorruptV2: repairCorrupt)
            draft.acceptSaved(saved)
            self.draft = draft
            notice = "儲存咗，下局開始用。"
            repairCorrupt = false
        } catch let error as LetterSelectionSettings.ValidationError {
            switch error {
            case .emptyFocus: notice = "請最少揀 1 個字母。"
            case .unavailableFocus: notice = "有字母未開放，請移除先儲存。"
            case .noWriteTargets: notice = "呢組暫時玩唔到『搵完寫』。請揀可寫字母，或者喺上面關閉呢個遊戲。"
            case .invalidReview: notice = "請揀可用嘅溫習字母，或者熄咗溫習。"
            default: notice = "字母設定未能儲存，請檢查選擇。"
            }
        } catch {
            notice = "未儲存到，請再試吓。"
        }
    }
}
