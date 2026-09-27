import SwiftUI
import VisaCore

extension Color {
    init(rgb: (red: Double, green: Double, blue: Double)) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Soft painted sky + ochre dunes + wooden station-sign energy (original shapes).
struct StorybookWorldBackground: View {
    let theme: ThemePack

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [
                        Color(rgb: theme.sky),
                        Color(rgb: theme.background),
                        Color(rgb: theme.sand)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                // Soft sun
                Circle()
                    .fill(Color(rgb: theme.yellow).opacity(0.55))
                    .frame(width: min(220, w * 0.18), height: min(220, w * 0.18))
                    .blur(radius: 2)
                    .offset(x: w * 0.32, y: h * 0.06)
                // Distant soft pyramids / depot roofs (abstract triangles — original).
                HStack(spacing: w * 0.04) {
                    Triangle()
                        .fill(Color(rgb: theme.sand).opacity(0.55))
                        .frame(width: w * 0.14, height: h * 0.16)
                    Triangle()
                        .fill(Color(rgb: theme.watermark).opacity(0.4))
                        .frame(width: w * 0.2, height: h * 0.22)
                    Triangle()
                        .fill(Color(rgb: theme.sand).opacity(0.5))
                        .frame(width: w * 0.12, height: h * 0.14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, h * 0.12)
                .opacity(0.85)
                // Rolling dune bands
                VStack {
                    Spacer()
                    Ellipse()
                        .fill(Color(rgb: theme.sand).opacity(0.55))
                        .frame(height: h * 0.28)
                        .offset(y: h * 0.06)
                    Ellipse()
                        .fill(Color(rgb: theme.watermark).opacity(0.35))
                        .frame(height: h * 0.22)
                        .offset(y: -h * 0.02)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Wooden station sign — big rounded title plate for depot / lock shell.
struct WoodenStationSign: View {
    let title: String
    let subtitle: String
    let foreground: Color
    let yellow: Color
    let sand: Color

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 36)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.93, green: 0.82, blue: 0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color(red: 0.45, green: 0.28, blue: 0.14), lineWidth: 5)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
        )
        .overlay(alignment: .top) {
            // Rope / hang cues
            HStack {
                Capsule().fill(sand.opacity(0.9)).frame(width: 8, height: 18)
                Spacer()
                Capsule().fill(sand.opacity(0.9)).frame(width: 8, height: 18)
            }
            .padding(.horizontal, 40)
            .offset(y: -14)
        }
    }
}

/// Soft sun + road-stripe accents kept for compatibility; dunes carry most mood now.
struct SoftSunRoadAccent: View {
    let yellow: Color
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(yellow.opacity(0.28))
                    .frame(width: 140, height: 140)
                    .blur(radius: 2)
                    .offset(x: -36, y: 28)
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == 1 ? yellow.opacity(0.35) : accent.opacity(0.22))
                            .frame(width: geometry.size.width * 0.18, height: 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 48)
                .padding(.bottom, 100)
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

    /// Recognizable city + works convoy for depot parade (original art).
    private static let paradeKinds: [VehicleKind] = [
        .hkTaxi, .nyTaxi, .fireEngine, .metroTrain, .crane, .logisticsTruck
    ]

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
            .animation(.linear(duration: 42).repeatForever(autoreverses: false), value: moving)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: bobbing)
        }
        .frame(height: 110)
        .opacity(0.55)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func row(width: CGFloat) -> some View {
        HStack(spacing: 18) {
            ForEach(Array(Self.paradeKinds.enumerated()), id: \.element) { index, kind in
                // Option 4 hybrid: illustrated leader + simple faceless fleet fillers.
                FriendlyVehicleView(
                    kind: kind,
                    paint: ToyPaint.forKind(kind).color.opacity(0.95),
                    mood: index % 2 == 0 ? .happy : .calm,
                    role: index == 0 ? .hero : .fleet
                )
                .frame(maxWidth: .infinity)
                .frame(height: 86)
            }
        }
        .frame(width: width)
    }
}
