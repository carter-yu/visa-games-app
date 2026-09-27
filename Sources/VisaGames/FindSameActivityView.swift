import SwiftUI
import VisaCore

/// Find-the-same entry gate with faced vehicles and bigger taps.
struct FindSameActivityView: View {
    let question: FindSameQuestion
    let accent: Color
    let yellow: Color
    let foreground: Color
    let sand: Color
    let retryMessage: String?
    let hintUsed: Bool
    let onSelect: (String) -> Void
    let onHint: () -> Void
    let onSpeakPrompt: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(question.promptTraditionalChinese)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
            Text(question.promptEnglish)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 20, weight: .medium, design: .rounded))

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(yellow, lineWidth: 5)
                if let kind = SilhouetteAsset.kind(for: question.targetAssetID) {
                    FriendlyVehicleView(kind: kind, mood: .calm, role: .fleet)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 22)
                }
            }
            .frame(minWidth: 380, minHeight: 150)
            .shadow(color: Color.black.opacity(0.1), radius: 6, y: 3)
            .accessibilityLabel("目標 / Target")

            HStack(spacing: 24) {
                ForEach(question.options, id: \.id) { option in
                    Button {
                        onSelect(option.id)
                    } label: {
                        VStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .fill(Color.white.opacity(0.55))
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(Color(red: 0.45, green: 0.28, blue: 0.14), lineWidth: 4)
                                if let kind = SilhouetteAsset.kind(for: option.assetID) {
                                    FriendlyVehicleView(kind: kind, mood: .happy, role: .fleet)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 22)
                                }
                            }
                            .frame(minWidth: 220, minHeight: 170)
                            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                            Text("\(option.labelTraditionalChinese) / \(option.labelEnglish)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(foreground)
                        }
                    }
                    .buttonStyle(BouncyChildButtonStyle())
                    .accessibilityLabel("\(option.labelTraditionalChinese), \(option.labelEnglish)")
                }
            }

            if let retryMessage {
                Text(retryMessage)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
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
        .background(sand.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: 1140)
    }
}
