import SwiftUI
import VisaCore

/// 中文字設定 (Hanzi H4): design hanzi-tap v2 § Parent settings, shared by 中文字 · 翻字卡 and 中文字 · 搵完寫. The letter
/// settings' draft + save pattern (`HanziSettingsDraft`): edits change this visit's draft only, 儲存 stores it through
/// `AppModel.saveHanziSettings`, 還原 drops it, and leaving the Games tab discards it. Every line comes from
/// `HanziParentCopy`, the 描字提示 labels from its one table. 筆順動畫 is the existing stroke-order setting: shown here,
/// changed only on the 數字設定 card. No percentage sliders.
struct ParentTapHanziSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft: HanziSettingsDraft?
    /// 「最少要揀 3 個字。」 after a refused toggle; cleared by the next edit.
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            header
            ParentLabel("\(HanziParentCopy.defaultOff) / \(HanziParentCopy.defaultOffEnglish)", size: 12, weight: 600,
                        color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let pack = model.tapHanziPack, let draft {
                weekRow(draft, pack: pack)
                reviewRow(draft)
                ParentOnOffRow(title: HanziParentCopy.guardTitle, english: HanziParentCopy.guardEnglish,
                               detail: HanziParentCopy.guardDetail, on: draft.value.confusableGuard) { value in
                    edit { $0.setConfusableGuard(value) }
                }
                coachRow(draft)
                gridRow
                strokeOrderRow
                ParentOnOffRow(title: HanziParentCopy.jyutpingTitle, english: HanziParentCopy.jyutpingEnglish,
                               detail: HanziParentCopy.jyutpingDetail, on: draft.value.jyutpingEnabled) { value in
                    edit { $0.setJyutping(value) }
                }
                ParentOnOffRow(title: HanziParentCopy.audioTitle, english: HanziParentCopy.audioEnglish,
                               detail: HanziParentCopy.audioDetail, on: draft.value.audioEnabled) { value in
                    edit { $0.setAudio(value) }
                }
                saveRow(draft)
            } else if model.tapHanziPack == nil {
                ParentBanner(text: HanziParentCopy.packUnavailable, fill: Color(hex: DesignTokens.Palette.sand))
            }
        }
        .padding(16)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.paper), cornerRadius: 18,
                              shadowDepth: 4, lineWidth: 3))
        .onAppear {
            if draft == nil { draft = HanziSettingsDraft(saved: model.tapHanziSettings) }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            // The play board's robot (D8): no separate icon language.
            VectorArtView(artwork: HanziCueArt.robot)
                .frame(width: 44, height: 37)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                ParentLabel(HanziParentCopy.settingsTitle, size: 20, weight: 900)
                ParentLabel(HanziParentCopy.settingsSubtitle, size: 12, weight: 700, color: .inkSoft)
            }
            Spacer(minLength: 8)
            if let draft {
                ParentPill(text: "\(HanziParentCopy.status(hasChanges: draft.hasChanges)) / \(HanziParentCopy.statusEnglish(hasChanges: draft.hasChanges))",
                           fill: Color(hex: draft.hasChanges ? DesignTokens.Palette.sunnyPale : DesignTokens.Palette.paper))
            }
        }
    }

    /// 今星期: one tile per pack target, drawn from its centre lines; find-only glyphs are listed, never selectable.
    private func weekRow(_ draft: HanziSettingsDraft, pack: HanziPack) -> some View {
        let chosen = draft.week(in: pack)
        return VStack(alignment: .leading, spacing: 8) {
            ParentLabel("\(HanziParentCopy.weekTitle) / \(HanziParentCopy.weekEnglish)", size: 15, weight: 800)
            HStack(spacing: 10) {
                ForEach(pack.board.targetWeek, id: \.self) { glyph in
                    glyphTile(glyph, pack: pack, selected: chosen.contains(glyph)) {
                        guard var next = self.draft else { return }
                        if next.toggleWeek(glyph, in: pack) == .belowMinimum {
                            notice = "\(HanziParentCopy.weekMinimum) / \(HanziParentCopy.weekMinimumEnglish)"
                        } else {
                            self.draft = next
                            notice = nil
                        }
                    }
                }
            }
            ParentLabel("\(HanziParentCopy.weekDetail) / \(HanziParentCopy.weekDetailEnglish)", size: 12, weight: 600,
                        color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let notice {
                ParentLabel(notice, size: 12, weight: 800)
            }
            HStack(spacing: 8) {
                ParentLabel("\(HanziParentCopy.findOnlyTitle) / \(HanziParentCopy.findOnlyEnglish)", size: 12, weight: 800,
                            color: .inkSoft)
                ForEach(pack.dealableFindOnly, id: \.self) { glyph in
                    HanziGlyphView(glyph: glyph, pack: pack, ink: .inkSoft, lineWidth: 26)
                        .frame(width: 22, height: 22)
                }
            }
            ParentLabel("\(HanziParentCopy.findOnlyDetail) / \(HanziParentCopy.findOnlyDetailEnglish)", size: 11,
                        weight: 600, color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func glyphTile(_ glyph: String, pack: HanziPack, selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HanziGlyphView(glyph: glyph, pack: pack, ink: .ink, lineWidth: 24)
                .frame(width: 34, height: 34)
                .padding(8)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: selected ? Color(hex: DesignTokens.Palette.sunny) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 12, shadowDepth: selected ? 2 : 3, lineWidth: 2))
        .accessibilityLabel("\(glyph) \(selected ? ParentToggleCopy.on : ParentToggleCopy.off)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 溫習「每 4 輪 1 輪」 or 關.
    private func reviewRow(_ draft: HanziSettingsDraft) -> some View {
        let on = draft.value.reviewEvery == 4
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                ParentLabel(HanziParentCopy.reviewTitle, size: 15, weight: 900)
                ParentLabel(HanziParentCopy.reviewEnglish, size: 11, weight: 700, color: .inkSoft)
            }
            Spacer(minLength: 8)
            ParentChoiceButton(title: ParentToggleCopy.off, subtitle: HanziParentCopy.reviewOffEnglish, selected: !on) {
                edit { $0.setReviewEvery(0) }
            }
            ParentChoiceButton(title: HanziParentCopy.reviewOn, subtitle: HanziParentCopy.reviewOnEnglish, selected: on) {
                edit { $0.setReviewEvery(4) }
            }
        }
    }

    /// 描字提示: Hanzi's own coach level, labels from the one table (D9 open: Carter decides the words).
    private func coachRow(_ draft: HanziSettingsDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ParentLabel("\(HanziParentCopy.coachTitle) / \(HanziParentCopy.coachEnglish)", size: 15, weight: 800)
            HStack(spacing: 10) {
                ForEach(HanziParentCopy.coachLabels, id: \.short) { label in
                    ParentChoiceButton(title: label.short, selected: draft.value.guidance == label.level) {
                        edit { $0.setGuidance(label.level) }
                    }
                }
            }
            ParentLabel(HanziParentCopy.coachLine(draft.value.guidance), size: 12, weight: 700)
                .fixedSize(horizontal: false, vertical: true)
            ParentLabel(HanziParentCopy.coach(draft.value.guidance).english, size: 11, weight: 600, color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            ParentLabel("\(HanziParentCopy.coachScope) / \(HanziParentCopy.coachScopeEnglish)", size: 11, weight: 600,
                        color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 寫字格: 田字格 only (D3); the write board draws no 米字格.
    private var gridRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            ParentLabel("\(HanziParentCopy.gridTitle) / \(HanziParentCopy.gridEnglish)", size: 15, weight: 800)
            HStack(spacing: 10) {
                ParentPill(text: "\(HanziParentCopy.gridTianzi) / \(HanziParentCopy.gridTianziEnglish)",
                           fill: Color(hex: DesignTokens.Palette.sunnyPale))
                ParentLabel("\(HanziParentCopy.gridNote) / \(HanziParentCopy.gridNoteEnglish)", size: 11, weight: 600,
                            color: .inkSoft)
            }
        }
    }

    /// 筆順動畫「跟現有設定」: the existing setting's current value, read only.
    private var strokeOrderRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            ParentLabel("\(HanziParentCopy.strokeOrderTitle) / \(HanziParentCopy.strokeOrderEnglish)", size: 15, weight: 800)
            ParentLabel("\(HanziParentCopy.strokeOrderNow(model.tapCountSettings.strokeOrder)) / \(HanziParentCopy.strokeOrderNowEnglish)",
                        size: 13, weight: 800)
            ParentLabel("\(HanziParentCopy.strokeOrderWhere) / \(HanziParentCopy.strokeOrderWhereEnglish)", size: 11,
                        weight: 600, color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveRow(_ draft: HanziSettingsDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Spacer(minLength: 8)
                ParentActionButton(title: "還原", subtitle: "Revert", symbol: "arrow.uturn.backward",
                                   fill: Color(hex: DesignTokens.Palette.paper),
                                   action: { edit { $0.revert() } })
                    .disabled(!draft.hasChanges)
                    .opacity(draft.hasChanges ? 1 : 0.45)
                ParentActionButton(title: "儲存", subtitle: "Save", symbol: "checkmark",
                                   fill: Color(hex: DesignTokens.Palette.sunny),
                                   action: { save() })
                    .disabled(!draft.hasChanges)
                    .opacity(draft.hasChanges ? 1 : 0.45)
            }
            ParentLabel("\(HanziParentCopy.saveNote) / \(HanziParentCopy.saveNoteEnglish)", size: 12, weight: 600,
                        color: .inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func edit(_ change: (inout HanziSettingsDraft) -> Void) {
        guard var next = draft else { return }
        change(&next)
        draft = next
        notice = nil
    }

    private func save() {
        guard var next = draft, next.hasChanges else { return }
        next.acceptSaved(model.saveHanziSettings(next.value))
        draft = next
        notice = nil
    }
}
