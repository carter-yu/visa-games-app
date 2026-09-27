import SwiftUI
import VisaCore

/// Short→long convoy: tap vehicles in order from shortest to longest.
struct SequenceActivityView: View {
    let question: SequenceQuestion
    let accent: Color
    let yellow: Color
    let foreground: Color
    let sand: Color
    let retryMessage: String?
    let hintUsed: Bool
    let tappedAssetIDs: [String]
    let onTapAsset: (String) -> Void
    let onHint: () -> Void
    let onSpeakPrompt: () -> Void

    /// Shuffled display order so the correct order is not left-to-right.
    private var displayOrder: [String] {
        // Stable shuffle from completionID so layout does not jump across redraws.
        let seed = question.completionID.unicodeScalars.reduce(into: 0) { $0 = $0 &* 31 &+ Int($1.value) }
        var items = question.orderedAssetIDs
        var state = seed == 0 ? 1 : abs(seed)
        for i in stride(from: items.count - 1, through: 1, by: -1) {
            state = state &* 1103515245 &+ 12345
            let j = abs(state) % (i + 1)
            items.swapAt(i, j)
        }
        return items
    }

    private func displayWidth(for assetID: String) -> CGFloat {
        guard let index = question.orderedAssetIDs.firstIndex(of: assetID) else { return 160 }
        // Short → long visual scale so a 4yo can see length differences.
        let scales: [CGFloat] = [0.62, 0.78, 0.92, 1.08]
        let scale = scales[min(index, scales.count - 1)]
        return 200 * scale
    }

    private func isSelected(_ assetID: String) -> Bool {
        tappedAssetIDs.contains(assetID)
    }

    private func selectionIndex(for assetID: String) -> Int? {
        tappedAssetIDs.firstIndex(of: assetID).map { $0 + 1 }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(question.promptTraditionalChinese)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
            Text(question.promptEnglish)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 20, weight: .medium, design: .rounded))

            // Progress dots for convoy order so far
            HStack(spacing: 12) {
                ForEach(0..<question.orderedAssetIDs.count, id: \.self) { index in
                    ZStack {
                        Circle()
                            .fill(index < tappedAssetIDs.count ? yellow : Color.white.opacity(0.5))
                            .frame(width: 28, height: 28)
                        if index < tappedAssetIDs.count {
                            Text("\(index + 1)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(foreground)
                        }
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 20) {
                ForEach(displayOrder, id: \.self) { assetID in
                    Button {
                        onTapAsset(assetID)
                    } label: {
                        VStack(spacing: 10) {
                            ZStack(alignment: .topTrailing) {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color.white.opacity(isSelected(assetID) ? 0.85 : 0.55))
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(
                                        isSelected(assetID) ? yellow : Color(red: 0.45, green: 0.28, blue: 0.14),
                                        lineWidth: isSelected(assetID) ? 6 : 4
                                    )
                                if let kind = SilhouetteAsset.kind(for: assetID) {
                                    FriendlyVehicleView(kind: kind, mood: isSelected(assetID) ? .happy : .calm, role: .fleet)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 16)
                                }
                                if let n = selectionIndex(for: assetID) {
                                    Text("\(n)")
                                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                                        .foregroundStyle(foreground)
                                        .padding(8)
                                        .background(Circle().fill(yellow))
                                        .offset(x: 6, y: -6)
                                }
                            }
                            .frame(width: displayWidth(for: assetID), height: 140)
                            .opacity(isSelected(assetID) ? 0.72 : 1.0)
                        }
                    }
                    .buttonStyle(BouncyChildButtonStyle())
                    .disabled(isSelected(assetID))
                    .accessibilityLabel("vehicle \(assetID)")
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
        .frame(maxWidth: 1180)
    }
}
