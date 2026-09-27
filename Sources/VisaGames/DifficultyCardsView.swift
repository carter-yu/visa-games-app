import SwiftUI
import VisaCore

/// Three big mission tickets / routes — storybook depot energy for a 4yo.
struct DifficultyCardsView: View {
    let accent: Color
    let yellow: Color
    let foreground: Color
    let sand: Color
    let onSelect: (Int) -> Void

    private func routeTitle(for difficulty: ChildDifficulty) -> String {
        switch difficulty {
        case .easy: return "的士短程 / Taxi hop"
        case .medium: return "消防車任務 / Fire run"
        case .challenge: return "地鐵長程 / Metro ride"
        }
    }

    private func cheer(for difficulty: ChildDifficulty) -> String {
        switch difficulty {
        case .easy: return "一齊出發！ / Let's go!"
        case .medium: return "車隊準備好！ / Convoy ready!"
        case .challenge: return "爬到頂！ / Climb to the top!"
        }
    }

    private func mascot(for difficulty: ChildDifficulty) -> VehicleKind {
        switch difficulty {
        case .easy: return .hkTaxi
        case .medium: return .fireEngine
        case .challenge: return .metroTrain
        }
    }

    private func paint(for difficulty: ChildDifficulty) -> Color {
        switch difficulty {
        case .easy: return ToyPaint.hkTaxiRed.color
        case .medium: return ToyPaint.fireEngineRed.color
        case .challenge: return ToyPaint.metroSilverBlue.color
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Text("揀條路線出發啦 / Pick a route to start")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(foreground)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(foreground.opacity(0.85))
            HStack(spacing: 22) {
                ForEach(ChildDifficulty.allCases, id: \.rawValue) { difficulty in
                    MissionTicketButton(
                        difficulty: difficulty,
                        title: routeTitle(for: difficulty),
                        cheer: cheer(for: difficulty),
                        mascot: mascot(for: difficulty),
                        paint: paint(for: difficulty),
                        yellow: yellow,
                        foreground: foreground,
                        sand: sand,
                        accent: accent,
                        onSelect: { onSelect(difficulty.rawValue) }
                    )
                }
            }
        }
        .frame(maxWidth: 1180, minHeight: 400)
    }
}

private struct MissionTicketButton: View {
    let difficulty: ChildDifficulty
    let title: String
    let cheer: String
    let mascot: VehicleKind
    let paint: Color
    let yellow: Color
    let foreground: Color
    let sand: Color
    let accent: Color
    let onSelect: () -> Void
    @State private var pressed = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                pressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                onSelect()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                    pressed = false
                }
            }
        } label: {
            VStack(spacing: 16) {
                // Ticket stub punches
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { _ in
                        Circle()
                            .fill(sand.opacity(0.55))
                            .frame(width: 12, height: 12)
                    }
                }
                Text(String(repeating: "★", count: difficulty.rawValue))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(yellow)
                    .shadow(color: Color.orange.opacity(0.35), radius: 2)
                FriendlyVehicleView(kind: mascot, paint: paint, mood: .happy)
                    .frame(height: 92)
                    .padding(.horizontal, 12)
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(foreground)
                Text("\(difficulty.minutes) 分鐘 / min")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
                Text(cheer)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(foreground.opacity(0.8))
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 340)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.99, green: 0.95, blue: 0.82),
                                Color(red: 0.96, green: 0.86, blue: 0.62)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color(red: 0.45, green: 0.28, blue: 0.14), lineWidth: 5)
            )
            .overlay(alignment: .leading) {
                // Ticket notch
                Capsule()
                    .fill(sand.opacity(0.65))
                    .frame(width: 10, height: 64)
                    .offset(x: -5)
            }
            .shadow(color: Color.black.opacity(pressed ? 0.08 : 0.22), radius: pressed ? 4 : 12, y: pressed ? 2 : 8)
            .scaleEffect(pressed ? 0.94 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(difficulty.minutes) minutes")
    }
}
