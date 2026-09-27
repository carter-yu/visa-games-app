import SwiftUI

struct SuccessParkAnimation: View {
    let color: Color
    let yellow: Color
    @State private var parked = false
    @State private var bounce = false
    @State private var showSparkles = false
    @State private var fadeSparkles = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if showSparkles {
                    ForEach(0..<5, id: \.self) { index in
                        Circle()
                            .fill(yellow.opacity(0.95))
                            .frame(width: index % 2 == 0 ? 14 : 10,
                                   height: index % 2 == 0 ? 14 : 10)
                            .offset(
                                x: CGFloat([-70, -30, 10, 50, 85][index]),
                                y: CGFloat([-48, -70, -40, -75, -52][index])
                            )
                            .scaleEffect(fadeSparkles ? 1.2 : 0.25)
                            .opacity(fadeSparkles ? 0.0 : 1.0)
                    }
                }

                ZStack(alignment: .center) {
                    VehicleSilhouette(kind: .logisticsTruck)
                        .fill(color)
                    Capsule()
                        .fill(yellow.opacity(0.75))
                        .frame(width: 48, height: 9)
                        .offset(x: -40, y: 6)
                }
                .frame(width: 320, height: 132)
                .shadow(color: yellow.opacity(0.45), radius: 22)
                .scaleEffect(bounce ? 1.05 : (parked ? 1.0 : 0.96))
                .offset(x: parked ? 0 : -geometry.size.width / 2 - 200,
                        y: bounce ? -12 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .onAppear {
                withAnimation(.easeOut(duration: 1.05)) { parked = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
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
        .frame(height: 168)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
