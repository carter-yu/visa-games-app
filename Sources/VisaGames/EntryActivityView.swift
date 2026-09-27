import SwiftUI
import VisaCore

/// Maps VisaCore silhouette asset IDs to original in-repo VehicleKind shapes.
enum SilhouetteAsset {
    static func kind(for assetID: String) -> VehicleKind? {
        switch assetID {
        case "silhouette.hkTaxi": return .hkTaxi
        case "silhouette.nyTaxi": return .nyTaxi
        case "silhouette.fireEngine": return .fireEngine
        case "silhouette.metroTrain": return .metroTrain
        case "silhouette.toyCar": return .toyCar
        case "silhouette.crane": return .crane
        case "silhouette.tanker": return .tanker
        case "silhouette.articulatedBus": return .articulatedBus
        case "silhouette.dinoFlatbed": return .dinoFlatbed
        case "silhouette.logisticsTruck": return .logisticsTruck
        default: return nil
        }
    }
}

/// Large-target two-picture entry gate with friendly faced vehicles.
struct EntryActivityView: View {
    let question: TwoPictureQuestion
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
        VStack(spacing: 24) {
            Text(question.promptTraditionalChinese)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
            Text(question.promptEnglish)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground.opacity(0.9))
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 22, weight: .medium, design: .rounded))

            HStack(spacing: 36) {
                ForEach(question.options, id: \.id) { option in
                    Button {
                        onSelect(option.id)
                    } label: {
                        VStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .fill(Color.white.opacity(0.55))
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .stroke(Color(red: 0.45, green: 0.28, blue: 0.14), lineWidth: 5)
                                if let kind = SilhouetteAsset.kind(for: option.assetID) {
                                    FriendlyVehicleView(kind: kind, mood: .happy)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 28)
                                } else {
                                    Text("?")
                                        .font(.system(size: 64, weight: .bold, design: .rounded))
                                }
                            }
                            .frame(minWidth: 300, minHeight: 240)
                            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                            .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)

                            Text("\(option.labelTraditionalChinese) / \(option.labelEnglish)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(foreground)
                        }
                    }
                    .buttonStyle(BouncyChildButtonStyle())
                    .accessibilityLabel("\(option.labelTraditionalChinese), \(option.labelEnglish)")
                }
            }

            if let retryMessage {
                Text(retryMessage)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
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
        .frame(maxWidth: 1040)
    }
}

/// Satisfying press scale for large child targets.
struct BouncyChildButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}
