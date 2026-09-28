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
                // Soft illustrated sun + cloud props (fallback to soft circle if missing).
                DepotPropView(kind: .sun)
                    .frame(width: min(200, w * 0.16), height: min(200, w * 0.16))
                    .opacity(0.92)
                    .offset(x: w * 0.34, y: h * 0.04)
                DepotPropView(kind: .cloud)
                    .frame(width: min(260, w * 0.22), height: min(140, h * 0.12))
                    .opacity(0.75)
                    .offset(x: -w * 0.28, y: h * 0.08)
                DepotPropView(kind: .cloud)
                    .frame(width: min(180, w * 0.14), height: min(100, h * 0.09))
                    .opacity(0.55)
                    .offset(x: w * 0.12, y: h * 0.02)
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

    /// Full illustrated convoy — every slot uses hero PNGs (v0.7.4).
    private static let paradeKinds: [VehicleKind] = [
        .hkTaxi, .nyTaxi, .fireEngine, .metroTrain,
        .crane, .tanker, .articulatedBus, .logisticsTruck, .toyCar, .dinoFlatbed
    ]

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1000)
            ZStack(alignment: .bottom) {
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
                .animation(.linear(duration: 48).repeatForever(autoreverses: false), value: moving)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: bobbing)

                // Soft roadside props (preschool cues; non-interactive).
                HStack {
                    DepotPropView(kind: .trafficCone)
                        .frame(width: 36, height: 44)
                        .opacity(0.85)
                    Spacer()
                    DepotPropView(kind: .trafficLight)
                        .frame(width: 28, height: 56)
                        .opacity(0.8)
                    Spacer()
                    DepotPropView(kind: .trafficCone)
                        .frame(width: 36, height: 44)
                        .opacity(0.85)
                }
                .padding(.horizontal, 28)
                .offset(y: 8)
            }
        }
        .frame(height: 118)
        .opacity(0.88)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func row(width: CGFloat) -> some View {
        HStack(spacing: 14) {
            ForEach(Array(Self.paradeKinds.enumerated()), id: \.element) { index, kind in
                FriendlyVehicleView(
                    kind: kind,
                    paint: ToyPaint.forKind(kind).color.opacity(0.95),
                    mood: index % 2 == 0 ? .happy : .calm,
                    role: .hero
                )
                .frame(maxWidth: .infinity)
                .frame(height: 92)
            }
        }
        .frame(width: width)
    }
}
