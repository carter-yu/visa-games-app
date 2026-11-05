import SwiftUI
import VisaCore

/// One parent visit's draft and immutable catalog/history snapshot.
@MainActor
final class ParentLetterSettingsState: ObservableObject {
    private let diagnosticID = UUID()
    @Published private(set) var draft: LetterPickerDraft?
    @Published private(set) var notice: String?
    @Published private(set) var repairCorrupt = false
    @Published private(set) var saveCheck = LetterPickerSaveCheck(reason: LetterPickerStatus.loadingLetters)
    /// True while the bank/history snapshot is built off the main thread (build 78).
    @Published private(set) var isLoading = false
    private(set) var history: [String] = []
    private(set) var capabilities: [String: LetterCapability] = [:]
    private var resources: LetterPickerResources?
    private var basePicker: PracticePickerModel?
    private var presets: [PracticePickerPreset] = []
    private var loadGeneration = 0

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

    func saveStatus(for load: LetterSelectionLoad) -> String {
        LetterPickerStatus.text(load: load, hasDraft: draft != nil, hasChanges: draft?.hasChanges ?? false)
    }

    func saveStatusEnglish(for load: LetterSelectionLoad) -> String {
        LetterPickerStatus.english(load: load, hasDraft: draft != nil, hasChanges: draft?.hasChanges ?? false)
    }

    func open(model: AppModel) {
        guard draft == nil, !isLoading else { return }
        ParentScrollDiagnostics.record("DRAFT open state=\(diagnosticID) load=\(model.letterParentLoad.logName)")
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        let started = ProcessInfo.processInfo.systemUptime
        model.withLetterPickerResources { [weak self, weak model] resources in
            guard let self, let model, generation == self.loadGeneration, self.isLoading else { return }
            self.isLoading = false
            self.install(resources, model: model)
            let elapsed = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
            ParentScrollDiagnostics.record("DRAFT ready state=\(self.diagnosticID) elapsedMs=\(elapsed) bank=\(resources.bankAvailable) history=\(resources.history.count) canSave=\(self.saveCheck.canSave) reason=\(self.saveCheck.reason ?? "none")")
        }
    }

    /// Performance records changed under the open editor (clear / 唔計呢段 / 計返): fetch a new
    /// history snapshot and keep the parent's draft. Save is unavailable until it arrives.
    func reloadResources(model: AppModel) {
        guard draft != nil, !isLoading else { return }
        ParentScrollDiagnostics.record("DRAFT reload state=\(diagnosticID) reason=historyChanged")
        loadGeneration &+= 1
        let generation = loadGeneration
        isLoading = true
        resources = nil
        saveCheck = LetterPickerSaveCheck(reason: LetterPickerStatus.loadingLetters)
        model.withLetterPickerResources { [weak self, weak model] resources in
            guard let self, let model, generation == self.loadGeneration, self.isLoading else { return }
            self.isLoading = false
            // The draft as it is now (edits made while loading are kept).
            self.install(resources, model: model, keeping: self.draft)
            ParentScrollDiagnostics.record("DRAFT ready state=\(self.diagnosticID) reload=true history=\(resources.history.count) canSave=\(self.saveCheck.canSave) reason=\(self.saveCheck.reason ?? "none")")
        }
    }

    private func install(_ resources: LetterPickerResources, model: AppModel, keeping kept: LetterPickerDraft? = nil) {
        self.resources = resources
        basePicker = resources.picker
        capabilities = resources.capabilities
        history = resources.history
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
                        label: letters.joined(separator: " "), subtitle: "\(title) \(index + 1)", itemIDs: letters)
                }
            }
            presets = basePicker.presets + [PracticePickerPreset(id: "practised90",
                label: "近 90 日練過", subtitle: "Practised in 90 days", itemIDs: history)] + school
        }
        if let kept {
            draft = kept // history reload: keep edits, repair choice and notice
        } else {
            draft = LetterPickerDraft(saved: model.letterParentLoad.effective ?? .defaults)
            notice = nil
            repairCorrupt = false
        }
        recheck(model: model)
    }

    func clear() {
        guard draft != nil || isLoading else { return }
        ParentScrollDiagnostics.record("DRAFT clear state=\(diagnosticID) loading=\(isLoading)")
        loadGeneration &+= 1 // a snapshot still being built is dropped on arrival
        isLoading = false
        draft = nil
        notice = nil
        repairCorrupt = false
        resources = nil
        history = []
        capabilities = [:]
        basePicker = nil
        presets = []
        saveCheck = LetterPickerSaveCheck(reason: LetterPickerStatus.loadingLetters)
    }

    func change(model: AppModel, _ edit: (inout LetterPickerDraft) -> Void) {
        guard var draft else { return }
        ParentScrollDiagnostics.record("DRAFT change begin state=\(diagnosticID)")
        edit(&draft)
        self.draft = draft
        notice = nil
        recheck(model: model)
        ParentScrollDiagnostics.record("DRAFT change end state=\(diagnosticID) selectedCount=\(draft.value.focusLetters.count) reviewCount=\(draft.value.reviewLetters.count) canSave=\(saveCheck.canSave)")
    }

    func chooseRepair(model: AppModel) {
        ParentScrollDiagnostics.record("DRAFT repair state=\(diagnosticID)")
        repairCorrupt = true
        notice = nil
        recheck(model: model)
    }

    func cancel(model: AppModel) {
        ParentScrollDiagnostics.record("DRAFT cancel state=\(diagnosticID)")
        change(model: model) { $0.cancel() }
        repairCorrupt = false
        recheck(model: model)
    }

    func revert(model: AppModel) {
        ParentScrollDiagnostics.record("DRAFT revert state=\(diagnosticID)")
        change(model: model) { $0.revert() }
        repairCorrupt = false
        recheck(model: model)
    }

    func recheck(model: AppModel) {
        guard let draft else { return }
        guard !isLoading else {
            saveCheck = LetterPickerSaveCheck(reason: LetterPickerStatus.loadingLetters)
            return
        }
        saveCheck = LetterPickerSaveCheck.evaluate(draft.value, availability: capabilities,
            writingAssigned: !model.gameAssignment.isHiddenFromMissions(.tapLetterWrite),
            allowedReview: Set(history).union(draft.saved.reviewLetters), load: model.letterParentLoad,
            repairCorruptV2: repairCorrupt, bankAvailable: basePicker != nil)
    }

    /// Every Save tap leaves one `DRAFT save … result=` line (build 78), so UAT can tell
    /// "never tapped/disabled" from "blocked", "failed" and "stored" (plus the AppModel
    /// `DRAFT save stored … v2KeyPresent=` line on success).
    func save(model: AppModel) {
        ParentScrollDiagnostics.record("DRAFT save state=\(diagnosticID) load=\(model.letterParentLoad.logName) hasChanges=\(draft?.hasChanges ?? false)")
        guard var draft, let resources else {
            ParentScrollDiagnostics.record("DRAFT save result=notReady state=\(diagnosticID) loading=\(isLoading)")
            return
        }
        recheck(model: model)
        guard saveCheck.canSave else {
            notice = saveCheck.reason
            ParentScrollDiagnostics.record("DRAFT save result=blocked state=\(diagnosticID) reason=\(saveCheck.reason ?? "none")")
            return
        }
        do {
            let saved = try model.saveLetterSelection(draft.value, resources: resources, repairCorruptV2: repairCorrupt)
            draft.acceptSaved(saved)
            self.draft = draft
            notice = "儲存咗，下局開始用。"
            repairCorrupt = false
            recheck(model: model)
            ParentScrollDiagnostics.record("DRAFT save result=saved state=\(diagnosticID) revision=\(saved.revision) focusCount=\(saved.focusLetters.count) reviewEvery=\(saved.reviewEvery)")
        } catch let error as LetterSelectionSettings.ValidationError {
            notice = LetterPickerSaveCheck.reason(for: error)
            ParentScrollDiagnostics.record("DRAFT save result=invalid state=\(diagnosticID) error=\(error)")
        } catch let error as LetterSelectionSettingsStore.StoreError {
            notice = LetterPickerSaveCheck.reason(for: error)
            ParentScrollDiagnostics.record("DRAFT save result=storeError state=\(diagnosticID) error=\(error)")
        } catch {
            notice = "儲存失敗，請再試吓。"
            ParentScrollDiagnostics.record("DRAFT save result=error state=\(diagnosticID) error=\(String(describing: type(of: error)))")
        }
    }
}

/// Pinned beside the existing parent Return bar, outside the long Games scroll content.
struct ParentLetterSettingsSaveBar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: ParentLetterSettingsState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    ParentLabel("字母設定 · \(state.saveStatus(for: model.letterParentLoad))", size: 17, weight: 900)
                    ParentLabel("Letters · \(state.saveStatusEnglish(for: model.letterParentLoad))", size: 11,
                                weight: 700, color: .inkSoft)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                ParentActionButton(title: "還原", subtitle: "Revert", symbol: "arrow.uturn.backward",
                                   fill: Color(hex: DesignTokens.Palette.paper),
                                   action: { state.revert(model: model) })
                    .disabled(state.draft == nil)
                    .opacity(state.draft == nil ? 0.45 : 1)
                ParentActionButton(title: "取消", subtitle: "Cancel", symbol: "xmark",
                                   fill: Color(hex: DesignTokens.Palette.sand),
                                   action: { state.cancel(model: model) })
                    .disabled(state.draft == nil)
                    .opacity(state.draft == nil ? 0.45 : 1)
                ParentActionButton(title: "儲存", subtitle: "Save", symbol: "checkmark",
                                   fill: Color(hex: DesignTokens.Palette.sunny),
                                   action: { state.save(model: model) })
                    .disabled(!state.saveCheck.canSave)
                    .opacity(state.saveCheck.canSave ? 1 : 0.45)
                    .accessibilityHint(state.saveCheck.reason ?? "儲存後下局開始用 / Applies next round")
            }
            .frame(height: 60)
            if let message = state.saveCheck.reason ?? state.notice {
                ParentLabel(message, size: 14, weight: 700)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 38, alignment: .top)
                    .accessibilityLabel(message)
            } else {
                // design D11: 「未儲存嘅改動唔會套用。」 near the action row (UX m6).
                VStack(alignment: .leading, spacing: 1) {
                    ParentLabel("儲存後，下局開始用。未儲存嘅改動唔會套用。", size: 12, weight: 700, color: .inkSoft)
                    ParentLabel("Saved changes start next round. Unsaved changes will not apply.", size: 11,
                                weight: 600, color: .inkSoft)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 38, alignment: .top)
            }
        }
        // UX m7: same 940 pt column (28 pt side padding) as the page content, centred, so 儲存
        // sits above the panel it saves on the 1905 pt TV window.
        .padding(.horizontal, 28)
        .frame(maxWidth: 940)
        .frame(maxWidth: .infinity)
        .frame(height: 116)
        .background(Color(hex: DesignTokens.Palette.paper)
            .overlay(Rectangle().fill(Color.ink).frame(height: 3), alignment: .bottom))
    }
}

/// One parent draft for both English letter games. The parent page owns its lifecycle.
struct ParentTapLetterSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: ParentLetterSettingsState
    let onShowWriteAssignment: () -> Void
    @State private var showMore = false
    @StateObject private var scrollTrace = ParentScrollViewTrace("ParentTapLetterSettingsView")

    /// Letters a–z in nine columns (design D2, picker-spec `preferredColumns`).
    private static let columns = 9
    private static let letterCount = 26

    var body: some View {
        let _ = scrollTrace.body("draft=\(state.draft != nil) showMore=\(showMore)")
        VStack(alignment: .leading, spacing: 15) {
            header
            VStack(alignment: .leading, spacing: 1) {
                ParentLabel("今次練邊啲字母？", size: 18, weight: 900)
                ParentLabel("Practice letters", size: 12, weight: 700, color: .inkSoft)
            }
            VStack(alignment: .leading, spacing: 2) {
                ParentLabel("撳一下亮燈，再撳一下熄燈。最少揀 1 個；想集中練習，可以先揀 3–5 個。",
                            size: 13, weight: 800)
                    .fixedSize(horizontal: false, vertical: true)
                ParentLabel("Tap a tile to light it up; tap again to switch it off. Choose at least 1; to focus, start with 3–5.",
                            size: 11, weight: 600, color: .inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                ParentLabel("儲存之後，下局開始用。", size: 12, weight: 700, color: .inkSoft)
                ParentLabel("Saved changes start next round.", size: 11, weight: 600, color: .inkSoft)
            }
            if let previous = model.letterParentLoad.previousReviewEvery {
                VStack(alignment: .leading, spacing: 2) {
                    ParentLabel("未儲存之前，小朋友照用舊設定（每 \(previous) 局溫 1 局）。儲存後只練揀咗嘅字母；想溫舊字母，可以喺下面開返。",
                                size: 12, weight: 700, color: .inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    ParentLabel("Until you save, the child keeps the previous settings (review 1 in \(previous) rounds). Saving switches to the selected letters only; you can turn review back on below.",
                                size: 11, weight: 600, color: .inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if model.letterParentLoad == .repairV1 {
                ParentBanner(text: "舊字母設定讀唔到。檢查吓呢組字母，再撳儲存修復。\nThe old letter settings couldn't be read. Check these letters, then Save to repair them.",
                             fill: Color(hex: DesignTokens.Palette.sand))
            }
            if model.letterParentLoad == .corruptV2 {
                ParentBanner(text: "字母設定讀唔到，字母遊戲暫停咗。檢查完，揀修復。\nThe letter settings couldn't be read, so letter games are paused. Check them, then choose Repair.",
                             fill: Color(hex: DesignTokens.Palette.sand))
                ParentSmallButton(title: state.repairCorrupt ? "✓ 揀咗修復 / Repair chosen" : "修復字母設定 / Repair letter settings",
                                  symbol: "wrench.and.screwdriver",
                                  fill: Color(hex: state.repairCorrupt ? DesignTokens.Palette.sunny : DesignTokens.Palette.paper)) {
                    state.chooseRepair(model: model)
                }
            }
            if let picker = state.picker, state.draft != nil {
                ParentPracticeItemPicker(model: picker, selectedIDs: Binding(
                    get: { state.selected }, set: { newValue in
                        guard let id = state.selected.symmetricDifference(newValue).first else { return }
                        state.change(model: model) { $0.toggleFocus(id) }
                    }), symbol: { item in
                        LatinLetterGlyph(letter: item.label, ink: .ink, lineWidth: 24)
                    }, capability: { _, availability in
                        Self.badge(for: availability)
                    }, capabilityLegend: [Self.findAndWriteBadge, Self.findOnlyBadge],
                    columns: Self.columns,
                    primaryPresetCount: 3, secondaryPresetTitle: "按學校次序", secondaryPresetEnglish: "School sequence",
                    placeholderAction: ParentPickerPlaceholderAction(
                        title: "睇吓練習建議", subtitle: "Review suggestions · 未開放",
                        help: "練習建議未開放：要等有足夠嘅練習紀錄先會開放。/ Review suggestions aren't available yet; they need enough practice records."),
                    onReplace: { preview, id in
                        state.change(model: model) { $0.replaceFocus(preview.includedIDs, source: id) }
                    })
                VStack(alignment: .leading, spacing: 1) {
                    ParentLabel("有玩過，唔代表已經熟晒。", size: 12, weight: 700, color: .inkSoft)
                    ParentLabel("Played before doesn't mean mastered.", size: 11, weight: 600, color: .inkSoft)
                }
                summary
                reviewControls
                moreSettings
                VStack(alignment: .leading, spacing: 1) {
                    ParentLabel("儲存、取消同還原喺頁頂。", size: 12, weight: 600, color: .inkSoft)
                    ParentLabel("Save, Cancel and Revert are pinned at the top.", size: 11, weight: 600, color: .inkSoft)
                }
            } else if state.isLoading {
                // UX n2: same preset / legend / tile sizes as the picker, so the page doesn't jump.
                ParentPracticeItemPickerPlaceholder(itemCount: Self.letterCount, columns: Self.columns, presetCount: 4,
                                                    message: LetterPickerStatus.loadingLetters,
                                                    english: LetterPickerStatus.loadingLettersEnglish)
            } else {
                ParentBanner(text: "字母卡讀唔到，暫時儲存唔到。\nThe letter cards couldn't be read, so Save isn't available.",
                             fill: Color(hex: DesignTokens.Palette.sand))
            }
        }
        .padding(16)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.paper), cornerRadius: 18,
                              shadowDepth: 4, lineWidth: 3))
        .onAppear { scrollTrace.event("appear") }
        .onDisappear { scrollTrace.event("disappear") }
        .onChange(of: showMore) { value in scrollTrace.event("disclosure more=\(value)") }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            LatinLetterGlyph(letter: "b", ink: .ink, lineWidth: 24)
                .frame(width: 30, height: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                ParentLabel("英文字母 ABC · 字母設定", size: 20, weight: 900)
                ParentLabel("Letters ABC · Shared by both letter games", size: 12, weight: 700, color: .inkSoft)
            }
            Spacer(minLength: 8)
            // UX m9 / design D4: the count on its own; the save state lives in the pinned bar.
            if let draft = state.draft {
                let count = draft.value.focusLetters.count
                ParentPill(text: "已揀 \(count) 個 / \(count) selected",
                           fill: Color(hex: count == 0 ? DesignTokens.Palette.paper : DesignTokens.Palette.sunnyPale))
            }
        }
    }

    /// Outlined panel with letter chips per game (UX n4, mockup 01).
    private var summary: some View {
        let find = state.draft?.value.focusLetters.filter { state.capabilities[$0]?.canFind == true } ?? []
        let write = state.draft?.value.focusLetters.filter { state.capabilities[$0]?.canWrite == true } ?? []
        let unavailable = state.draft?.value.focusLetters.filter { state.capabilities[$0]?.canFind != true } ?? []
        let findOnly = find.filter { !write.contains($0) }
        let writeAssigned = !model.gameAssignment.isHiddenFromMissions(.tapLetterWrite)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ParentLabel("儲存後重點練呢啲字母", size: 14, weight: 900)
                Spacer(minLength: 8)
                ParentLabel("Focus targets after saving", size: 12, weight: 700, color: .inkSoft)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            summaryDivider
            summaryRow(title: "翻字卡", english: "Find & flip", letters: find)
            summaryDivider
            summaryRow(title: "搵完寫", english: "Find & write", letters: write)
            if !findOnly.isEmpty || !unavailable.isEmpty || write.isEmpty {
                summaryDivider
                VStack(alignment: .leading, spacing: 4) {
                    if !findOnly.isEmpty {
                        ParentLabel("\(list(findOnly)) 暫時只可以搵，未可以寫。", size: 12, weight: 800)
                        ParentLabel("\(list(findOnly)): find only for now.", size: 11, weight: 600, color: .inkSoft)
                    }
                    if !unavailable.isEmpty {
                        ParentLabel("已揀・暫停：\(list(unavailable))。儲存之前要移除。", size: 12, weight: 800)
                        ParentLabel("Selected · unavailable: remove before saving.", size: 11, weight: 600,
                                    color: .inkSoft)
                    }
                    if write.isEmpty {
                        ParentLabel("呢組暫時玩唔到『搵完寫』。", size: 12, weight: 800)
                        ParentLabel("This set can't play Find & write yet.", size: 11, weight: 600, color: .inkSoft)
                        if writeAssigned {
                            ParentSmallButton(title: "返去搵完寫遊戲卡 / Go to the Find & write card",
                                              symbol: "arrow.up") {
                                onShowWriteAssignment()
                            }
                            .padding(.top, 2)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ChunkyPanel(fill: .white, cornerRadius: 12, shadowDepth: 3, lineWidth: 2))
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.ink.opacity(0.25))
            .frame(height: 1.5)
    }

    private func summaryRow(title: String, english: String, letters: [String]) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                ParentLabel(title, size: 14, weight: 900)
                ParentLabel("\(english) · focus targets", size: 11, weight: 700, color: .inkSoft)
            }
            Spacer(minLength: 8)
            if letters.isEmpty {
                ParentLabel("無 / None", size: 13, weight: 800, color: .inkSoft)
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(0..<((letters.count + 12) / 13), id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(Array(letters.dropFirst(row * 13).prefix(13)), id: \.self) { letter in
                                letterChip(letter)
                            }
                        }
                    }
                }
                ParentLabel("\(letters.count) 個", size: 11, weight: 700, color: .inkSoft)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) / \(english)：\(list(letters))")
    }

    private func letterChip(_ letter: String) -> some View {
        LatinLetterGlyph(letter: letter, ink: .ink, lineWidth: 24)
            .frame(width: 16, height: 20)
            .frame(width: 26, height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: DesignTokens.Palette.sunnyPale)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.ink, lineWidth: 2))
            .accessibilityHidden(true)
    }

    private var reviewControls: some View {
        let on = state.draft?.value.reviewEvery == 4
        let canTurnOn = !(state.candidates.isEmpty && (state.draft?.value.reviewLetters.isEmpty ?? true))
        let reviewLetters = state.draft?.value.reviewLetters ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    ParentLabel("溫習其他字母", size: 15, weight: 900)
                    ParentLabel("Review other letters", size: 11, weight: 700, color: .inkSoft)
                }
                Spacer(minLength: 8)
                ParentChoiceButton(title: "熄 · 只練揀咗嘅", subtitle: "Off · selected only", selected: !on) {
                    state.change(model: model) { $0.setReviewEvery(0, candidates: []) }
                }
                ParentChoiceButton(title: "每 4 局最多 1 局", subtitle: "Up to 1 in 4 rounds", selected: on) {
                    state.change(model: model) { $0.setReviewEvery(4, candidates: state.candidates) }
                }
                .disabled(!canTurnOn)
                .opacity(canTurnOn ? 1 : 0.45)
            }
            if on {
                ParentLabel("題目會包括：主練 \(list(state.draft?.value.focusLetters ?? []))；每 4 局最多 1 局溫 \(list(reviewLetters))。",
                            size: 12, weight: 800)
                    .fixedSize(horizontal: false, vertical: true)
                ParentLabel("翻字卡溫習：\(list(review(for: .tapLetterAll)))；搵完寫溫習：\(list(review(for: .tapLetterWrite)))。",
                            size: 12, weight: 600, color: .inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                ParentLabel("Review in Find & flip: \(list(review(for: .tapLetterAll))); in Find & write: \(list(review(for: .tapLetterWrite))).",
                            size: 11, weight: 600, color: .inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<((reviewLetters.count + 9) / 10), id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(Array(reviewLetters.dropFirst(row * 10).prefix(10)), id: \.self) { letter in
                                ParentSmallButton(title: letter, symbol: "xmark") {
                                    state.change(model: model) { $0.removeReview(letter) }
                                }
                                .accessibilityLabel("移除溫習字母 \(letter) / Remove review letter \(letter)")
                            }
                        }
                    }
                    ParentSmallButton(title: "重新揀溫習字母 / Choose review letters again", symbol: "arrow.clockwise") {
                        state.change(model: model) { $0.refreshReview(state.candidates) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                ParentLabel("只會叫小朋友搵／寫上面揀咗嘅字母；其他字母仍然可以做陪襯。", size: 12, weight: 600,
                            color: .inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                ParentLabel("Only selected letters are asked; other letters can still appear on the cards.",
                            size: 11, weight: 600, color: .inkSoft)
            }
        }
    }

    /// UX M2: the 進階 full-width button pattern (no stock disclosure); mirror guard as a 開 / 熄 pill (M1).
    private var moreSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            ParentDisclosureButton(title: "更多字母設定", english: "More letter settings", isOpen: showMore) {
                showMore.toggle()
            }
            if showMore {
                ParentOnOffRow(
                    title: "鏡像字母保護：新字母先避開易混淆嘅卡",
                    english: "Mirror guard: ease in with fewer lookalikes",
                    detail: "b 同 d 都可以揀。個字母要有一局唔使幫又搵啱晒，先會同易混淆嘅卡放埋一版；之後點錯或者用提示，就開返保護。\nb and d can both be chosen. A letter meets its lookalikes only after one clean find with no help; a miss or hint turns the guard back on.",
                    on: state.draft?.value.mirrorGuard ?? true) { value in
                    state.change(model: model) { $0.setMirrorGuard(value) }
                }
            }
        }
    }

    private static func badge(for availability: PracticePickerAvailability?) -> ParentPickerBadge {
        if availability?.consumers.contains("write") == true { return findAndWriteBadge }
        if availability?.consumers.contains("find") == true { return findOnlyBadge }
        return ParentPickerBadge(zh: "未開放", en: "Not ready", tone: .notReady)
    }
    private static var findAndWriteBadge: ParentPickerBadge {
        ParentPickerBadge(zh: "搵＋寫", en: "Find + write", tone: .full)
    }
    private static var findOnlyBadge: ParentPickerBadge {
        ParentPickerBadge(zh: "只可搵", en: "Find only", tone: .partial)
    }

    private func review(for kind: ActivityKind) -> [String] {
        state.draft?.value.review(for: kind, availability: state.capabilities) ?? []
    }
    private func list(_ letters: [String]) -> String { letters.isEmpty ? "無" : letters.joined(separator: "、") }
}
