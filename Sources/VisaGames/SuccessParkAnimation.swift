import SwiftUI

struct SuccessParkAnimation: View {
    let color: Color
    @State private var parked = false

    var body: some View {
        GeometryReader { geometry in
            VehicleSilhouette(kind: .logisticsTruck)
                .fill(color)
                .frame(width: 240, height: 100)
                .shadow(color: color.opacity(0.35), radius: 18)
                .offset(x: parked ? 0 : -geometry.size.width / 2 - 160)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .onAppear { withAnimation(.easeOut(duration: 1.3)) { parked = true } }
        }
        .frame(height: 120)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
