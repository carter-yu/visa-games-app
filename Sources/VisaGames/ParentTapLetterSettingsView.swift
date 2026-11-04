import SwiftUI
import VisaCore

/// One parent visit's draft and immutable catalog/history snapshot.
@MainActor
final class ParentLetterSettingsState: ObservableObject {
    @Published private(set) var draft: LetterPickerDraft?
    @Published private(set) var notice: String?
    @Published private(set) var repairCorrupt = false
    @Published private(set) var saveCheck = LetterPickerSaveCheck(reason: "字母卡載入中。")
    private(set) var history: [String] = []
    private(set) var capabilities: [String: LetterCapability] = [:]
    private var basePicker: PracticePickerModel?
    private var presets: [PracticePickerPreset] = []

    var selected: Set<String> { Set(draft?.value.focusLetters ?? []) }
    var candidates: [String] {
        history.filter { capabilities[$0]?.canFind == true && !selected.contains($0) }
    }
    var picker: PracticePickerModel? {
        guard let base = basePicker else { return nil }
        return PracticePickerModel(catalogID: base.catalogID, catalogRevision: base.catalogRevision,
            items: base.items, availabilityByItem: base.availabilityByItem, enabledIDs: selected,
            presets: presets, minimum: base.minimum, maximum: base.maximum)
    }

    func open(model: AppModel) {
        guard draft == nil else { return }
        let snapshot = model.letterPickerSnapshot()
        basePicker = snapshot?.0
        capabilities = snapshot?.1 ?? [:]
        history = model.practicedLetterTargets()
        if let basePicker {
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
            presets = basePicker.presets + [PracticePickerPreset(id: "practised90",
                label: "近 90 日練過 / Practised in 90 days", itemIDs: history)] + school
        }
        draft = LetterPickerDraft(saved: model.letterParentLoad.effective ?? .defaults)
        notice = nil
        repairCorrupt = false
        recheck(model: model)
    }

    func clear() {
        draft = nil
        notice = nil
        repairCorrupt = false
        history = []
        capabilities = [:]
        basePicker = nil
        presets = []
        saveCheck = LetterPickerSaveCheck(reason: "字母卡載入中。")
    }

    func change(model: AppModel, _ edit: (inout LetterPickerDraft) -> Void) {
        guard var draft else { return }
        edit(&draft)
        self.draft = draft
        notice = nil
        recheck(model: model)
    }

    func chooseRepair(model: AppModel) {
        repairCorrupt = true
        notice = nil
        recheck(model: model)
    }

    func cancel(model: AppModel) {
        change(model: model) { $0.cancel() }
        repairCorrupt = false
        recheck(model: model)
    }

    func revert(model: AppModel) {
        change(model: model) { $0.revert() }
        repairCorrupt = false
        recheck(model: model)
    }

    func recheck(model: AppModel) {
        guard let draft else { return }
        saveCheck = LetterPickerSaveCheck.evaluate(draft.value, availability: capabilities,
            writingAssigned: !model.gameAssignment.isHiddenFromMissions(.tapLetterWrite),
            allowedReview: Set(history).union(draft.saved.reviewLetters), load: model.letterParentLoad,
            repairCorruptV2: repairCorrupt, bankAvailable: basePicker != nil)
    }

    func save(model: AppModel) {
        guard var draft else { return }
        recheck(model: model)
        guard saveCheck.canSave else { notice = saveCheck.reason; return }
        do {
            let saved = try model.saveLetterSelection(draft.value, repairCorruptV2: repairCorrupt)
            draft.acceptSaved(saved)
            self.draft = draft
            notice = "儲存咗，下局開始用。"
            repairCorrupt = false
            recheck(model: model)
        } catch let error as LetterSelectionSettings.ValidationError {
            notice = LetterPickerSaveCheck.reason(for: error)
        } catch let error as LetterSelectionSettingsStore.StoreError {
            notice = LetterPickerSaveCheck.reason(for: error)
        } catch {
            notice = "儲存失敗，請再試吓。"
        }
    }
}

/// Pinned beside the existing parent Return bar, outside the long Games scroll content.
struct ParentLetterSettingsSaveBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: ParentLetterSettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ParentLabel("字母設定 · \(state.draft?.hasChanges == true ? "未儲存" : "已儲存")",
                            size: 15, weight: 900)
                Spacer(minLength: 8)
                Button("還原") { state.revert(model: model) }
                Button("取消") { state.cancel(model: model) }
                Button("儲存") { state.save(model: model) }
                    .disabled(!state.saveCheck.canSave)
                    .accessibilityHint(state.saveCheck.reason ?? "儲存後下一局開始用")
            }
            .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sunny),
                                           cornerRadius: 12, shadowDepth: 2, lineWidth: 2))
            if let message = state.saveCheck.reason ?? state.notice {
                ParentLabel(message, size: 12, weight: 700, color: .inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ParentLabel("儲存後，下局開始用。", size: 12, weight: 600, color: .inkSoft)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 9)
        .background(Color(hex: DesignTokens.Palette.paper)
            .overlay(Rectangle().fill(Color.ink).frame(height: 2), alignment: .bottom))
    }
}

/// One parent draft for both English letter games. The view is destroyed on leaving Games.
struct ParentTapLetterSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: ParentLetterSettingsState
    let onShowWriteAssignment: () -> Void
    @State private var showMore = false

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
                if let draft = state.draft {
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
                Button(state.repairCorrupt ? "✓ 已選擇修復" : "修復字母設定") {
                    state.chooseRepair(model: model)
                }
                    .buttonStyle(.bordered)
            }
            if let picker = state.picker, state.draft != nil {
                ParentPracticeItemPicker(model: picker, selectedIDs: Binding(
                    get: { state.selected }, set: { newValue in
                        guard let id = state.selected.symmetricDifference(newValue).first else { return }
                        state.change(model: model) { $0.toggleFocus(id) }
                    }), symbol: { item in
                        LatinLetterGlyph(letter: item.label, ink: .ink, lineWidth: 24)
                    }, capabilityLabel: { _, availability in
                        availability?.consumers.contains("write") == true ? "搵＋寫"
                            : availability?.consumers.contains("find") == true ? "只可搵" : "未開放"
                    }, primaryPresetCount: 3, secondaryPresetTitle: "按學校次序 / School sequence",
                    onReplace: { preview, id in
                        state.change(model: model) { $0.replaceFocus(preview.includedIDs, source: id) }
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
                        get: { state.draft?.value.mirrorGuard ?? true },
                        set: { value in state.change(model: model) { $0.setMirrorGuard(value) } }))
                    ParentLabel("減少容易混淆嘅字母同時出現。", size: 12, weight: 600, color: .inkSoft)
                }
                ParentLabel("儲存、取消同還原按鈕固定喺頁頂。", size: 12, weight: 600, color: .inkSoft)
            } else {
                ParentBanner(text: "字母卡未能讀取，暫時儲存唔到。", fill: Color(hex: DesignTokens.Palette.sand))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.paper), cornerRadius: 18,
                              shadowDepth: 4, lineWidth: 3))
        .onAppear { state.open(model: model) }
        .onChange(of: model.gameAssignment) { _ in state.recheck(model: model) }
        .onDisappear { state.clear() }
    }

    private var summary: some View {
        let find = state.draft?.value.focusLetters.filter { state.capabilities[$0]?.canFind == true } ?? []
        let write = state.draft?.value.focusLetters.filter { state.capabilities[$0]?.canWrite == true } ?? []
        let unavailable = state.draft?.value.focusLetters.filter { state.capabilities[$0]?.canFind != true } ?? []
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
            ParentLabel(state.draft?.value.reviewEvery == 4 ? "而家：每 4 局最多 1 局" : "而家：熄，只練揀咗嘅",
                        size: 12, weight: 700, color: .inkSoft)
            HStack {
                Button("熄 · 只練揀咗嘅") { state.change(model: model) { $0.setReviewEvery(0, candidates: []) } }
                Button("每 4 局最多 1 局") { state.change(model: model) { $0.setReviewEvery(4, candidates: state.candidates) } }
                    .disabled(state.candidates.isEmpty && (state.draft?.value.reviewLetters.isEmpty ?? true))
            }
            .buttonStyle(.bordered)
            if state.draft?.value.reviewEvery == 4 {
                ParentLabel("題目會包括：主練 \(list(state.draft?.value.focusLetters ?? []))；每 4 局最多 1 局溫 \(list(state.draft?.value.reviewLetters ?? []))。",
                            size: 12, weight: 700)
                ParentLabel("翻字卡溫習：\(list(review(for: .tapLetterAll)))；搵完寫溫習：\(list(review(for: .tapLetterWrite)))。",
                            size: 12, weight: 600, color: .inkSoft)
                HStack {
                    ForEach(state.draft?.value.reviewLetters ?? [], id: \.self) { letter in
                        Button("\(letter) ×") { state.change(model: model) { $0.removeReview(letter) } }
                            .accessibilityLabel("移除溫習字母 \(letter)")
                    }
                    Button("重新揀溫習字母") { state.change(model: model) { $0.refreshReview(state.candidates) } }
                }
                .buttonStyle(.bordered)
            }
            ParentLabel("只會叫小朋友搵／寫上面揀咗嘅字母；其他字母仍可做陪襯。", size: 12, weight: 600,
                        color: .inkSoft)
        }
    }

    private func review(for kind: ActivityKind) -> [String] {
        state.draft?.value.review(for: kind, availability: state.capabilities) ?? []
    }
    private func list(_ letters: [String]) -> String { letters.isEmpty ? "無" : letters.joined(separator: "、") }
}
