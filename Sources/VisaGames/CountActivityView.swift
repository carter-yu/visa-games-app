import SwiftUI
import VisaCore

/// Count-to-N entry gate with faced convoy row + big number pads.
struct CountActivityView: View {
    let question: CountQuestion
    let accent: Color
    let yellow: Color
    let foreground: Color
    let sand: Color
    let retryMessage: String?
    let hintUsed: Bool
    let onSelectCount: (Int) -> Void
    let onHint: () -> Void
    let onSpeakPrompt: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Text(question.promptTraditionalChinese)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
            Text(question.promptEnglish)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 20, weight: .medium, design: .rounded))

            HStack(spacing: 18) {
                ForEach(Array(question.vehicleAssetIDs.enumerated()), id: \.offset) { index, assetID in
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.55))
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color(red: 0.45, green: 0.28, blue: 0.14), lineWidth: 3)
                        if let kind = SilhouetteAsset.kind(for: assetID) {
                            FriendlyVehicleView(
                                kind: kind,
                                mood: index % 2 == 0 ? .happy : .calm
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 18)
                        }
                    }
                    .frame(minWidth: 170, minHeight: 130)
                }
            }

            HStack(spacing: 28) {
                ForEach(question.choiceCounts, id: \.self) { count in
                    Button {
                        onSelectCount(count)
                    } label: {
                        Text("\(count)")
                            .font(.system(size: 60, weight: .heavy, design: .rounded))
                            .foregroundStyle(foreground)
                            .frame(minWidth: 130, minHeight: 130)
                            .background(
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .fill(Color.white.opacity(0.65))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .stroke(yellow, lineWidth: 5)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 30))
                    }
                    .buttonStyle(BouncyChildButtonStyle())
                    .accessibilityLabel("\(count)")
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
        .foregroundStyle(foreground)
    }
}
