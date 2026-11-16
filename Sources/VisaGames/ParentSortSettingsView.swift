import SwiftUI
import VisaCore

/// 家長 → 遊戲 → 分類設定 (patterns-sorting P1, design §7, minimal): 分類方法 (six switches; the last of 顏色・大細・形狀
/// stays on), 提示 多啲／標準／少啲 (the one label table) and 廣東話語音 開／關. Shared by 邊個唔同類 and 分車房 (P4).
/// Applies at once, as 連一連設定 does; every change is a `config_change` for the weekly ⚙. Buttons only, no text input.
struct ParentSortSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let settings = model.sortSettings
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                PatternSortLookView(look: PatternSortLook(.vehicle(.mixer), .yellow))
                    .frame(width: 54, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    ParentLabel(PatternSortParentCopy.sortTitle, size: 20, weight: 900)
                    ParentLabel(PatternSortParentCopy.sortSubtitle, size: 12, weight: 700, color: .inkSoft)
                }
            }
            if let notice = model.sortSettingsNotice {
                ParentBanner(text: notice, fill: Color(hex: DesignTokens.Palette.taxiTicket))
            }
            VStack(alignment: .leading, spacing: 8) {
                ParentLabel("\(PatternSortParentCopy.methodsTitle) / \(PatternSortParentCopy.methodsEnglish)", size: 15, weight: 800)
                HStack(spacing: 10) {
                    ForEach(PatternSortMethod.allCases, id: \.self) { method in
                        ParentChoiceButton(title: method.zh, subtitle: method.en, selected: settings.methods.contains(method),
                                           minWidth: 96) {
                            model.toggleSortMethod(method)
                        }
                    }
                }
                ParentLabel("\(PatternSortParentCopy.methodsDetail) / \(PatternSortParentCopy.methodsDetailEnglish)",
                            size: 12, weight: 600, color: .inkSoft)
                ParentLabel("\(PatternSortParentCopy.methodsMeaning) / \(PatternSortParentCopy.methodsMeaningEnglish)",
                            size: 12, weight: 600, color: .inkSoft)
                ParentLabel("\(PatternSortParentCopy.lastPerceptual) / \(PatternSortParentCopy.lastPerceptualEnglish)",
                            size: 12, weight: 700, color: .inkSoft)
            }
            VStack(alignment: .leading, spacing: 8) {
                ParentLabel("\(PatternSortParentCopy.helpTitle) / \(PatternSortParentCopy.helpEnglish)", size: 15, weight: 800)
                HStack(spacing: 10) {
                    ForEach(HanziParentCopy.coachLabels, id: \.short) { label in
                        ParentChoiceButton(title: label.short, selected: settings.guidance == label.level) {
                            model.setSortGuidance(label.level)
                        }
                    }
                }
                ParentLabel("\(PatternSortParentCopy.helpDetail(settings.guidance).zh) / \(PatternSortParentCopy.helpDetail(settings.guidance).en)",
                            size: 12, weight: 600, color: .inkSoft)
            }
            VStack(alignment: .leading, spacing: 8) {
                ParentLabel("\(PatternSortParentCopy.audioTitle) / \(PatternSortParentCopy.audioEnglish)", size: 15, weight: 800)
                HStack(spacing: 10) {
                    ParentChoiceButton(title: ParentToggleCopy.on, subtitle: "On", selected: settings.audioEnabled) {
                        model.setSortAudio(true)
                    }
                    ParentChoiceButton(title: ParentToggleCopy.off, subtitle: "Off", selected: !settings.audioEnabled) {
                        model.setSortAudio(false)
                    }
                }
                ParentLabel(PatternSortParentCopy.audioDetail, size: 12, weight: 600, color: .inkSoft)
            }
            ParentLabel("\(PatternSortParentCopy.appliesNow) / \(PatternSortParentCopy.appliesNowEnglish)",
                        size: 12, weight: 700, color: .inkSoft)
        }
        .padding(16)
        .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.paper), cornerRadius: 18,
                              shadowDepth: 4, lineWidth: 3))
    }
}
