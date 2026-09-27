import SwiftUI
import VisaCore

/// Maps VisaCore silhouette asset IDs to original in-repo VehicleKind shapes (no trademark IP).
enum SilhouetteAsset {
    static func kind(for assetID: String) -> VehicleKind? {
        switch assetID {
        case "silhouette.crane": return .crane
        case "silhouette.tanker": return .tanker
        case "silhouette.articulatedBus": return .articulatedBus
        case "silhouette.dinoFlatbed": return .dinoFlatbed
        case "silhouette.logisticsTruck": return .logisticsTruck
        default: return nil
        }
    }
}

/// Large-target two-picture entry gate for Wacom pen / finger (M3 / ADR 0004).
struct EntryActivityView: View {
    let question: TwoPictureQuestion
    let accent: Color
    let yellow: Color
    let foreground: Color
    let retryMessage: String?
    let hintUsed: Bool
    let onSelect: (String) -> Void
    let onHint: () -> Void
    let onSpeakPrompt: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Text(question.promptTraditionalChinese)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(question.promptEnglish)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 22, weight: .medium, design: .rounded))

            HStack(spacing: 36) {
                ForEach(question.options, id: \.id) { option in
                    Button {
                        onSelect(option.id)
                    } label: {
                        VStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(Color.white.opacity(0.14))
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(yellow.opacity(0.85), lineWidth: 4)
                                if let kind = SilhouetteAsset.kind(for: option.assetID) {
                                    VehicleSilhouette(kind: kind)
                                        .fill(accent)
                                        .padding(.horizontal, 28)
                                        .padding(.vertical, 36)
                                } else {
                                    Text("?")
                                        .font(.system(size: 64, weight: .bold, design: .rounded))
                                }
                            }
                            .frame(minWidth: 280, minHeight: 220)
                            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                            Text("\(option.labelTraditionalChinese) / \(option.labelEnglish)")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(foreground)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.labelTraditionalChinese), \(option.labelEnglish)")
                }
            }

            if let retryMessage {
                Text(retryMessage)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
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
        .frame(maxWidth: 980)
    }
}
