import SwiftUI
import VisaCore

/// Count-to-N entry gate: row of silhouettes + large number buttons (M4).
struct CountActivityView: View {
    let question: CountQuestion
    let accent: Color
    let yellow: Color
    let foreground: Color
    let retryMessage: String?
    let hintUsed: Bool
    let onSelectCount: (Int) -> Void
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

            HStack(spacing: 20) {
                ForEach(Array(question.vehicleAssetIDs.enumerated()), id: \.offset) { _, assetID in
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.14))
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(yellow.opacity(0.75), lineWidth: 3)
                        if let kind = SilhouetteAsset.kind(for: assetID) {
                            VehicleSilhouette(kind: kind)
                                .fill(accent)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 22)
                        }
                    }
                    .frame(minWidth: 160, minHeight: 120)
                }
            }

            HStack(spacing: 28) {
                ForEach(question.choiceCounts, id: \.self) { count in
                    Button {
                        onSelectCount(count)
                    } label: {
                        Text("\(count)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .frame(minWidth: 120, minHeight: 120)
                            .background(accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 28))
                            .overlay(RoundedRectangle(cornerRadius: 28).stroke(yellow, lineWidth: 4))
                            .contentShape(RoundedRectangle(cornerRadius: 28))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(count)")
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
        .foregroundStyle(foreground)
    }
}
