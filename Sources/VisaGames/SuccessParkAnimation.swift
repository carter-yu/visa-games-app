import SwiftUI

/// Toy-like visa stamp / ticket-punch celebration, then a friendly vehicle parks in.
struct SuccessParkAnimation: View {
    let color: Color
    let yellow: Color
    @State private var stampIn = false
    @State private var stampFade = false
    @State private var parked = false
    @State private var bounce = false
    @State private var showSparkles = false
    @State private var fadeSparkles = false
    @State private var punchHoles = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Ticket punch holes
                if punchHoles {
                    HStack(spacing: 18) {
                        ForEach(0..<5, id: \.self) { _ in
                            Circle()
                                .stroke(yellow.opacity(0.9), lineWidth: 3)
                                .background(Circle().fill(Color.white.opacity(0.35)))
                                .frame(width: 18, height: 18)
                        }
                    }
                    .offset(y: -78)
                    .transition(.scale.combined(with: .opacity))
                }

                // Passport / visa stamp
                ZStack {
                    Circle()
                        .stroke(Color(red: 0.75, green: 0.18, blue: 0.16).opacity(0.9),
                                style: StrokeStyle(lineWidth: 6, dash: [10, 6]))
                        .frame(width: 150, height: 150)
                    Circle()
                        .stroke(Color(red: 0.75, green: 0.18, blue: 0.16), lineWidth: 3)
                        .frame(width: 128, height: 128)
                    VStack(spacing: 4) {
                        Text("簽證")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                        Text("VISA")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                        Text("OK!")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(red: 0.75, green: 0.18, blue: 0.16))
                }
                .rotationEffect(.degrees(stampIn ? -12 : -28))
                .scaleEffect(stampIn ? 1.0 : 1.6)
                .opacity(stampFade ? 0.0 : (stampIn ? 1.0 : 0.0))
                .offset(y: stampFade ? -40 : -10)

                if showSparkles {
                    ForEach(0..<6, id: \.self) { index in
                        Circle()
                            .fill(yellow.opacity(0.95))
                            .frame(width: index % 2 == 0 ? 14 : 10,
                                   height: index % 2 == 0 ? 14 : 10)
                            .offset(
                                x: CGFloat([-80, -40, 0, 40, 75, 100][index]),
                                y: CGFloat([-52, -78, -44, -82, -56, -70][index])
                            )
                            .scaleEffect(fadeSparkles ? 1.2 : 0.25)
                            .opacity(fadeSparkles ? 0.0 : 1.0)
                    }
                }

                FriendlyVehicleView(kind: .fireEngine, paint: color, mood: .happy)
                    .frame(width: 340, height: 140)
                    .shadow(color: yellow.opacity(0.45), radius: 22)
                    .scaleEffect(bounce ? 1.05 : (parked ? 1.0 : 0.96))
                    .offset(x: parked ? 0 : -geometry.size.width / 2 - 220,
                            y: bounce ? -10 : 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .onAppear {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.55)) {
                    stampIn = true
                    punchHoles = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    withAnimation(.easeOut(duration: 0.45)) { stampFade = true }
                    withAnimation(.easeOut(duration: 1.0)) { parked = true }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.48)) {
                        bounce = true
                    }
                    showSparkles = true
                    withAnimation(.easeOut(duration: 0.55)) {
                        fadeSparkles = true
                    }
                }
            }
        }
        .frame(height: 200)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
