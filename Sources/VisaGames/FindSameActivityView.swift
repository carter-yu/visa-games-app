import SwiftUI
import VisaCore

/// Find-the-same entry gate: target silhouette on top, large matching options below (M4).
struct FindSameActivityView: View {
    let question: FindSameQuestion
    let accent: Color
    let yellow: Color
    let foreground: Color
    let retryMessage: String?
    let hintUsed: Bool
    let onSelect: (String) -> Void
    let onHint: () -> Void
    let onSpeakPrompt: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text(question.promptTraditionalChinese)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(question.promptEnglish)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 20, weight: .medium, design: .rounded))

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(yellow.opacity(0.9), lineWidth: 4)
                if let kind = SilhouetteAsset.kind(for: question.targetAssetID) {
                    VehicleSilhouette(kind: kind)
                        .fill(accent)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 28)
                }
            }
            .frame(minWidth: 360, minHeight: 140)
            .accessibilityLabel("目標 / Target")

            HStack(spacing: 28) {
                ForEach(question.options, id: \.id) { option in
                    Button {
                        onSelect(option.id)
                    } label: {
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(yellow.opacity(0.85), lineWidth: 4)
                                if let kind = SilhouetteAsset.kind(for: option.assetID) {
                                    VehicleSilhouette(kind: kind)
                                        .fill(accent)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 28)
                                }
                            }
                            .frame(minWidth: 200, minHeight: 160)
                            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                            Text("\(option.labelTraditionalChinese) / \(option.labelEnglish)")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(foreground)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.labelTraditionalChinese), \(option.labelEnglish)")
                }
            }

            if let retryMessage {
                Text(retryMessage)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(yellow)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 20) {
                Button(hintUsed ? "提示已用 / Hint used" : "提示 / Hint", action: onHint)
                    .disabled(hintUsed)
                    .tint(accent)
                Button("聽提示（稍後） / Hear prompt (later)", action: onSpeakPrompt)
                    .tint(yellow)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: 1100)
    }
}
