import SwiftUI
import VisaCore

struct DifficultyCardsView: View {
    let accent: Color
    let yellow: Color
    let onSelect: (Int) -> Void

    private func label(for difficulty: ChildDifficulty) -> String {
        switch difficulty {
        case .easy: return "簡單 / Easy"
        case .medium: return "適中 / Medium"
        case .challenge: return "挑戰 / Challenge"
        }
    }

    var body: some View {
        VStack(spacing: 28) {
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            HStack(spacing: 24) {
                ForEach(ChildDifficulty.allCases, id: \.rawValue) { difficulty in
                    Button { onSelect(difficulty.rawValue) } label: {
                        VStack(spacing: 28) {
                            Text(String(repeating: "★", count: difficulty.rawValue))
                                .foregroundStyle(yellow)
                            Text(label(for: difficulty))
                            Text("\(difficulty.minutes) 分鐘 / min")
                        }
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 260)
                        .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 28))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(yellow, lineWidth: 4))
                        .contentShape(RoundedRectangle(cornerRadius: 28))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 1100, minHeight: 380)
    }
}
