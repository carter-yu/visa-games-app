import SwiftUI
import VisaCore

/// One parent visit's draft and immutable catalog/history snapshot.
@MainActor
final class ParentLetterSettingsState: ObservableObject {
    private let diagnosticID = UUID()
    @Published private(set) var draft: LetterPickerDraft?
    /// Save feedback in HK Chinese + English (build 80); set by the same paths as before.
    @Published private(set) var notice: LetterPickerMessage?
    @Published private(set) var repairCorrupt = false
    @Published private(set) var saveCheck = LetterPickerSaveCheck(message: LetterPickerSaveCheck.loading)
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
        saveCheck = LetterPickerSaveCheck(message: LetterPickerSaveCheck.loading)
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
                        label: letters.joined(separator: " "),
                        subtitle: "\(title) \(index + 1) · \(letters.count) letters", listsItems: true,
                        itemIDs: letters)
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
        saveCheck = LetterPickerSaveCheck(message: LetterPickerSaveCheck.loading)
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
            saveCheck = LetterPickerSaveCheck(message: LetterPickerSaveCheck.loading)
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
            notice = saveCheck.message
            ParentScrollDiagnostics.record("DRAFT save result=blocked state=\(diagnosticID) reason=\(saveCheck.reason ?? "none")")
            return
        }
        do {
            let saved = try model.saveLetterSelection(draft.value, resources: resources, repairCorruptV2: repairCorrupt)
            draft.acceptSaved(saved)
            self.draft = draft
            notice = LetterPickerSaveCheck.saved
            repairCorrupt = false
            recheck(model: model)
            ParentScrollDiagnostics.record("DRAFT save result=saved state=\(diagnosticID) revision=\(saved.revision) focusCount=\(saved.focusLetters.count) reviewEvery=\(saved.reviewEvery)")
        } catch let error as LetterSelectionSettings.ValidationError {
            notice = LetterPickerSaveCheck.message(for: error)
            ParentScrollDiagnostics.record("DRAFT save result=invalid state=\(diagnosticID) error=\(error)")
        } catch let error as LetterSelectionSettingsStore.StoreError {
            notice = LetterPickerSaveCheck.message(for: error)
            ParentScrollDiagnostics.record("DRAFT save result=storeError state=\(diagnosticID) error=\(error)")
        } catch {
            notice = LetterPickerSaveCheck.saveFailed
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
                    .accessibilityHint(state.saveCheck.message.map { "\($0.zh) / \($0.en)" }
                        ?? "儲存後下局開始用 / Applies next round")
            }
            .frame(height: 60)
            // UX m5 (build 80): block reasons, storage errors and save notices in both languages.
            if let message = state.saveCheck.message ?? state.notice {
                VStack(alignment: .leading, spacing: 1) {
                    ParentLabel(message.zh, size: 14, weight: 700)
                    ParentLabel(message.en, size: 11, weight: 600, color: .inkSoft)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 38, alignment: .top)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(message.zh) / \(message.en)")
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
                ParentLabel("撳一下亮燈，再撳一下關燈。最少揀 1 個；想集中練習，可以先揀 3–5 個。",
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
            if let picker = state.picker, let sections = loadedSections {
                ParentPracticeItemPicker(model: picker, selectedIDs: Binding(
                    get: { state.selected }, set: { newValue in
                        guard let id = state.selected.symmetricDifference(newValue).first else { return }
                        state.change(model: model) { $0.toggleFocus(id) }
                    }), symbol: { item in
                        ParentLetterSymbol(letter: item.label, fallbackSize: 34)
                    }, capability: { _, availability in
                        Self.badge(for: availability)
                    }, capabilityLegend: [Self.findAndWriteBadge, Self.findOnlyBadge],
                    columns: Self.columns,
                    primaryPresetCount: 3, secondaryPresetTitle: "按學校次序", secondaryPresetEnglish: "School sequence",
                    placeholderAction: ParentPickerPlaceholderAction(
                        title: "睇吓練習建議", subtitle: "Review suggestions", note: "呢個版本未有 · Not in this build",
                        help: "呢個版本未有練習建議。/ Review suggestions aren't available in this build."),
                    onReplace: { preview, id in
                        state.change(model: model) { $0.replaceFocus(preview.includedIDs, source: id) }
                    })
                belowGrid(sections, interactive: true)
            } else if state.isLoading {
                // Build 80 (UX n2): the whole loaded card structure, drawn from the saved settings
                // the draft will start from, so loading → loaded keeps one height.
                ParentPracticeItemPickerPlaceholder(itemCount: Self.letterCount, columns: Self.columns, presetCount: 4,
                                                    message: LetterPickerStatus.loadingLetters,
                                                    english: LetterPickerStatus.loadingLettersEnglish)
                belowGrid(provisionalSections, interactive: false)
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

    // MARK: Sections below the grid (build 80: one layout while loading and when loaded)

    /// What the sections below the grid show. Loaded: the draft and the loaded capabilities.
    /// Loading: the saved settings the draft will start from (known before the off-main load,
    /// same source as `ParentLetterSettingsState.install`), letters not resolved per game yet.
    /// The per-game split and its warnings are VisaCore `LetterSelectionSummary`.
    private struct Sections {
        var summary: LetterSelectionSummary
        var reviewOn: Bool
        var reviewLetters: [String]
        var reviewFind: [String]
        var reviewWrite: [String]
        var mirrorGuard: Bool
        var resolved: Bool { summary.resolved }
        var focus: [String] { summary.focus }
    }

    private var loadedSections: Sections? {
        guard let value = state.draft?.value else { return nil }
        return Sections(summary: LetterSelectionSummary(focus: value.focusLetters, capabilities: state.capabilities),
                        reviewOn: value.reviewEvery == 4, reviewLetters: value.reviewLetters,
                        reviewFind: review(for: .tapLetterAll), reviewWrite: review(for: .tapLetterWrite),
                        mirrorGuard: value.mirrorGuard)
    }

    private var provisionalSections: Sections {
        let value = model.letterParentLoad.effective ?? .defaults
        return Sections(summary: .loading(focus: value.focusLetters),
                        reviewOn: value.reviewEvery == 4, reviewLetters: value.reviewLetters,
                        reviewFind: [], reviewWrite: [], mirrorGuard: value.mirrorGuard)
    }

    /// Footnote, summary, review, more settings and footer, in that order, for both states.
    /// While loading they are dimmed and inactive; only their content differs, not their layout.
    @ViewBuilder
    private func belowGrid(_ sections: Sections, interactive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ParentLabel("有玩過，唔代表已經熟晒。", size: 12, weight: 700, color: .inkSoft)
            ParentLabel("Played before doesn't mean mastered.", size: 11, weight: 600, color: .inkSoft)
        }
        summary(sections)
            .opacity(interactive ? 1 : 0.55)
        reviewControls(sections)
            .disabled(!interactive)
            .opacity(interactive ? 1 : 0.55)
        moreSettings(sections)
            .disabled(!interactive)
            .opacity(interactive ? 1 : 0.55)
        VStack(alignment: .leading, spacing: 1) {
            ParentLabel("儲存、取消同還原喺頁頂。", size: 12, weight: 600, color: .inkSoft)
            ParentLabel("Save, Cancel and Revert are pinned at the top.", size: 11, weight: 600, color: .inkSoft)
        }
    }

    /// Outlined panel with letter chips per game (UX n4, mockup 01). Each row reserves chip
    /// rows for the whole focus set, and every capability warning shares one fixed status row
    /// (fix round 1), so loading and loaded panels are the same height for any selection.
    private func summary(_ sections: Sections) -> some View {
        let summary = sections.summary
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
            summaryRow(title: "翻字卡", english: "Find & flip", letters: summary.find,
                       resolved: summary.resolved, chipRows: summary.chipRows)
            summaryDivider
            summaryRow(title: "搵完寫", english: "Find & write", letters: summary.write,
                       resolved: summary.resolved, chipRows: summary.chipRows)
            summaryDivider
            summaryStatus(summary, showRecovery: summary.writeEmpty && writeAssigned)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ChunkyPanel(fill: .white, cornerRadius: 12, shadowDepth: 3, lineWidth: 2))
    }

    /// Fits two text lines and the chunky recovery button.
    private static let statusRowHeight: CGFloat = 44

    /// Always present: loading, every warning joined (已揀・暫停 / find only / nothing to
    /// write), or all clear. The 搵完寫 recovery button sits on the right of the same row.
    private func summaryStatus(_ summary: LetterSelectionSummary, showRecovery: Bool) -> some View {
        let status = summary.status
        let icon = !summary.resolved ? "hourglass"
            : summary.hasWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        let tint = summary.hasWarning ? Color(hex: DesignTokens.Palette.tomato) : Color.inkSoft
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                ParentLabel(status.zh, size: 12, weight: 800, color: summary.hasWarning ? .ink : .inkSoft)
                ParentLabel(status.en, size: 11, weight: 600, color: .inkSoft)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(status.zh) / \(status.en)")
            Spacer(minLength: 8)
            if showRecovery {
                ParentSmallButton(title: "返去搵完寫遊戲卡 / Go to the Find & write card", symbol: "arrow.up") {
                    onShowWriteAssignment()
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.statusRowHeight)
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(Color.ink.opacity(0.25))
            .frame(height: 1.5)
    }

    private static let chipSize = CGSize(width: 26, height: 28)
    private static let chipSpacing: CGFloat = 4

    private func summaryRow(title: String, english: String, letters: [String], resolved: Bool,
                            chipRows: Int) -> some View {
        let reserved = CGFloat(chipRows) * Self.chipSize.height + CGFloat(chipRows - 1) * Self.chipSpacing
        let perRow = LetterSelectionSummary.chipsPerRow
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                ParentLabel(title, size: 14, weight: 900)
                ParentLabel("\(english) · focus targets", size: 11, weight: 700, color: .inkSoft)
            }
            Spacer(minLength: 8)
            if letters.isEmpty {
                ParentLabel("無 / None", size: 13, weight: 800, color: .inkSoft)
            } else {
                VStack(alignment: .trailing, spacing: Self.chipSpacing) {
                    ForEach(0..<((letters.count + perRow - 1) / perRow), id: \.self) { row in
                        HStack(spacing: Self.chipSpacing) {
                            ForEach(Array(letters.dropFirst(row * perRow).prefix(perRow)), id: \.self) { letter in
                                letterChip(resolved ? letter : nil)
                            }
                        }
                    }
                }
                ParentLabel(resolved ? "\(letters.count) 個" : "…", size: 11, weight: 700, color: .inkSoft)
            }
        }
        .frame(minHeight: reserved)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(resolved ? "\(title) / \(english)：\(list(letters))"
            : "\(title) / \(english)：\(LetterPickerStatus.loadingLetters)")
    }

    /// A blank chip (no letter) while the cards load.
    private func letterChip(_ letter: String?) -> some View {
        ZStack {
            if let letter {
                ParentLetterSymbol(letter: letter, fallbackSize: 16)
                    .frame(width: 16, height: 20)
            }
        }
        .frame(width: Self.chipSize.width, height: Self.chipSize.height)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: DesignTokens.Palette.sunnyPale)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.ink, lineWidth: 2))
        .accessibilityHidden(true)
    }

    private func reviewControls(_ sections: Sections) -> some View {
        let on = sections.reviewOn
        let canTurnOn = sections.resolved
            && !(state.candidates.isEmpty && (state.draft?.value.reviewLetters.isEmpty ?? true))
        let reviewLetters = sections.reviewLetters
        let findReview = sections.resolved ? list(sections.reviewFind) : LetterPickerStatus.loadingLetters
        let writeReview = sections.resolved ? list(sections.reviewWrite) : LetterPickerStatus.loadingLetters
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    ParentLabel("溫習其他字母", size: 15, weight: 900)
                    ParentLabel("Review other letters", size: 11, weight: 700, color: .inkSoft)
                }
                Spacer(minLength: 8)
                ParentChoiceButton(title: "\(ParentToggleCopy.off) · 只練揀咗嘅", subtitle: "Off · selected only",
                                   selected: !on) {
                    state.change(model: model) { $0.setReviewEvery(0, candidates: []) }
                }
                ParentChoiceButton(title: "每 4 局最多 1 局", subtitle: "Up to 1 in 4 rounds", selected: on) {
                    state.change(model: model) { $0.setReviewEvery(4, candidates: state.candidates) }
                }
                .disabled(!canTurnOn)
                .opacity(canTurnOn || !sections.resolved ? 1 : 0.45)
            }
            if on {
                ParentLabel("題目會包括：主練 \(list(sections.focus))；每 4 局最多 1 局溫 \(list(reviewLetters))。",
                            size: 12, weight: 800)
                    .fixedSize(horizontal: false, vertical: true)
                // One line each in both states (loading shows 「字母卡載入中…」 here).
                ParentLabel("翻字卡溫習：\(findReview)；搵完寫溫習：\(writeReview)。",
                            size: 12, weight: 600, color: .inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                ParentLabel("Review in Find & flip: \(sections.resolved ? list(sections.reviewFind) : "…"); in Find & write: \(sections.resolved ? list(sections.reviewWrite) : "…").",
                            size: 11, weight: 600, color: .inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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

    /// UX M2: the 進階 full-width button pattern (no stock disclosure); mirror guard as a
    /// 開／關 pill (M1; Carter's wording, build 80).
    private func moreSettings(_ sections: Sections) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ParentDisclosureButton(title: "更多字母設定", english: "More letter settings", isOpen: showMore) {
                showMore.toggle()
            }
            if showMore {
                ParentOnOffRow(
                    title: "鏡像字母保護：新字母先避開易混淆嘅卡",
                    english: "Mirror guard: ease in with fewer lookalikes",
                    detail: "b 同 d 都可以揀。個字母要有一局唔使幫又搵啱晒，先會同易混淆嘅卡放埋一版；之後點錯或者用提示，就開返保護。\nb and d can both be chosen. A letter meets its lookalikes only after one clean find with no help; a miss or hint turns the guard back on.",
                    on: sections.mirrorGuard) { value in
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

/// Parent-only letter symbol (build 80). Letters with authored centre lines use the same
/// `LatinLetterGlyph` as before. The 15 letters without paths (i j l m n p q r s t v w x y z)
/// would draw nothing, so parent tiles and chips show them in the app's rounded font instead.
/// Child boards keep `LatinLetterGlyph`; readiness never looks at this view.
struct ParentLetterSymbol: View {
    let letter: String
    /// Point size of the text fallback (tiles 34, summary chips 16).
    let fallbackSize: CGFloat

    var body: some View {
        if LatinGlyphs.hasPaths(letter) {
            LatinLetterGlyph(letter: letter, ink: .ink, lineWidth: 24)
        } else {
            Text(letter)
                .font(CanvasFont.font(size: fallbackSize, weight: 700))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(letter)
        }
    }
}
