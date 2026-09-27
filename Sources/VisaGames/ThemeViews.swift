import SwiftUI
import VisaCore

extension Color {
    init(rgb: (red: Double, green: Double, blue: Double)) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Soft sun + road-stripe accents — yellow as highlight only, not a full-screen wash.
struct SoftSunRoadAccent: View {
    let yellow: Color
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(yellow.opacity(0.22))
                    .frame(width: 160, height: 160)
                    .blur(radius: 2)
                    .offset(x: -36, y: 28)
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == 1 ? yellow.opacity(0.28) : accent.opacity(0.18))
                            .frame(width: geometry.size.width * 0.22, height: 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 48)
                .padding(.bottom, 118)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct VehicleParade: View {
    let color: Color
    let yellow: Color
    @State private var moving = false
    @State private var bobbing = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 800)
            HStack(spacing: 0) {
                row(width: width)
                row(width: width)
            }
            .frame(width: width * 2, alignment: .leading)
            .offset(x: moving ? -width : 0, y: bobbing ? -5 : 5)
            .onAppear {
                moving = true
                bobbing = true
            }
            .animation(.linear(duration: 50).repeatForever(autoreverses: false), value: moving)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: bobbing)
        }
        .frame(height: 100)
        .opacity(0.20)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func row(width: CGFloat) -> some View {
        HStack(spacing: 22) {
            ForEach(Array(VehicleKind.allCases.enumerated()), id: \.element) { index, kind in
                ZStack(alignment: .bottomLeading) {
                    VehicleSilhouette(kind: kind)
                        .fill(color)
                    // Small yellow accent stripe — curiosity highlight, not a trademark mark.
                    Capsule()
                        .fill(yellow.opacity(0.55))
                        .frame(width: 28, height: 6)
                        .offset(x: 18, y: -22)
                        .opacity(index % 2 == 0 ? 1 : 0.7)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 78)
            }
        }
        .frame(width: width)
    }
}
