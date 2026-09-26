import SwiftUI
import VisaCore

extension Color {
    init(rgb: (red: Double, green: Double, blue: Double)) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

struct VehicleParade: View {
    let color: Color
    @State private var moving = false

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 800)
            HStack(spacing: 0) {
                row(width: width)
                row(width: width)
            }
            .frame(width: width * 2, alignment: .leading)
            .offset(x: moving ? -width : 0)
            .onAppear { moving = true }
            .animation(.linear(duration: 50).repeatForever(autoreverses: false), value: moving)
        }
        .frame(height: 92)
        .opacity(0.18)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func row(width: CGFloat) -> some View {
        HStack(spacing: 18) {
            ForEach(VehicleKind.allCases, id: \.self) { kind in
                VehicleSilhouette(kind: kind)
                    .fill(color)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
            }
        }
        .frame(width: width)
    }
}
