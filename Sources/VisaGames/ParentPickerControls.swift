import SwiftUI
import VisaCore

/// Build 79 (UX review M1/M2): the letter picker's controls reuse the parent page's own
/// patterns instead of stock macOS buttons, toggles and disclosure groups.

/// The 進階 pattern (v0.20.1, `ParentSettingsView.advancedSection`): a full-width plain button
/// with a chevron and 打開 / 收埋 hint. A macOS `DisclosureGroup` only toggles from its small
/// chevron, so pen or finger taps on its words did nothing (UAT 2026-10-09).
struct ParentDisclosureButton: View {
    let title: String
    let english: String
    let isOpen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 14, weight: .heavy))
                    .frame(width: 16)
                ParentLabel(title, size: 15, weight: 800)
                ParentLabel(english, size: 12, weight: 700, color: .inkSoft)
                Spacer(minLength: 8)
                Text(isOpen ? "收埋 / Hide" : "打開 / Show")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.inkSoft)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) / \(english)")
        .accessibilityValue(isOpen ? "打開咗 / Open" : "收埋咗 / Closed")
    }
}

/// The count card's chunky choice button (`ParentTapCountSettingsView.choiceButton`): sunny
/// when chosen, paper otherwise; HK Chinese title over a smaller English line.
struct ParentChoiceButton: View {
    let title: String
    var subtitle: String = ""
    let selected: Bool
    var minWidth: CGFloat = 104
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                ParentLabel(title, size: 16, weight: 900)
                if !subtitle.isEmpty {
                    ParentLabel(subtitle, size: 10, weight: 700, color: .inkSoft)
                }
            }
            .frame(minWidth: minWidth)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: selected ? Color(hex: DesignTokens.Palette.sunny) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 12, shadowDepth: selected ? 2 : 3, lineWidth: 2))
        .accessibilityLabel(subtitle.isEmpty ? title : "\(title) / \(subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The count card's on/off pill (`ParentTapCountSettingsView.toggleRow`), 開／關 wording
/// from `ParentToggleCopy` (Carter, build 80).
struct ParentOnOffRow: View {
    let title: String
    let english: String
    let detail: String
    let on: Bool
    let action: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: { action(!on) }) {
                ParentLabel(ParentToggleCopy.pill(on), size: 14, weight: 900)
                    .frame(width: 70)
                    .padding(.vertical, 5)
            }
            .buttonStyle(ChunkyButtonStyle(
                fill: on ? Color(hex: DesignTokens.Palette.sunny) : Color(hex: DesignTokens.Palette.paper),
                cornerRadius: 12, shadowDepth: on ? 2 : 3, lineWidth: 2))
            .accessibilityLabel("\(title) \(on ? ParentToggleCopy.on : ParentToggleCopy.off) / \(english) \(on ? "on" : "off")")
            VStack(alignment: .leading, spacing: 1) {
                ParentLabel(title, size: 14, weight: 800)
                ParentLabel(english, size: 11, weight: 700, color: .inkSoft)
                ParentLabel(detail, size: 11, weight: 600, color: .inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
