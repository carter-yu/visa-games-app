import SwiftUI

/// Original cute vehicle silhouettes inspired by recognizable real-world types
/// (HK red taxi, NY yellow taxi, HK fire engine, metro train, long works trucks).
/// Original IP only — no licensed character faces, no protected transit logos.
enum VehicleKind: CaseIterable, Hashable {
    case hkTaxi
    case nyTaxi
    case fireEngine
    case metroTrain
    case toyCar
    case crane
    case tanker
    case articulatedBus
    case dinoFlatbed
    case logisticsTruck
}

enum VehicleFaceMood: Hashable {
    case calm, happy, sleepy
}

struct VehicleSilhouette: Shape {
    let kind: VehicleKind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func body(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        func wheel(_ x: CGFloat, y: CGFloat = 58, size: CGFloat = 16) {
            path.addEllipse(in: CGRect(x: x, y: y, width: size, height: size))
        }
        func outline(_ points: [CGPoint]) {
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }

        switch kind {
        case .hkTaxi, .nyTaxi:
            // Rounded city taxi silhouette (shared body; paint differs).
            path.addRoundedRect(in: CGRect(x: 42, y: 36, width: 106, height: 26),
                                cornerSize: CGSize(width: 10, height: 10))
            outline([CGPoint(x: 58, y: 36), CGPoint(x: 72, y: 18),
                     CGPoint(x: 120, y: 18), CGPoint(x: 136, y: 36)])
            // Roof lamp
            path.addRoundedRect(in: CGRect(x: 88, y: 10, width: 22, height: 10),
                                cornerSize: CGSize(width: 4, height: 4))
            wheel(54, y: 56, size: 18); wheel(126, y: 56, size: 18)
        case .fireEngine:
            // Cab + boxy rear with ladder hint — original cute fire truck.
            body(18, 28, 70, 34)
            body(88, 22, 78, 40)
            outline([CGPoint(x: 18, y: 28), CGPoint(x: 30, y: 14),
                     CGPoint(x: 72, y: 14), CGPoint(x: 88, y: 28)])
            // Ladder rail
            body(96, 12, 62, 6)
            body(152, 12, 6, 18)
            wheel(34); wheel(110); wheel(148)
        case .metroTrain:
            // Long rounded metro car — HK-inspired colors via paint, no roundel logo.
            path.addRoundedRect(in: CGRect(x: 8, y: 22, width: 174, height: 38),
                                cornerSize: CGSize(width: 14, height: 14))
            // Window band
            path.addRoundedRect(in: CGRect(x: 22, y: 30, width: 28, height: 16),
                                cornerSize: CGSize(width: 4, height: 4))
            path.addRoundedRect(in: CGRect(x: 58, y: 30, width: 28, height: 16),
                                cornerSize: CGSize(width: 4, height: 4))
            path.addRoundedRect(in: CGRect(x: 94, y: 30, width: 28, height: 16),
                                cornerSize: CGSize(width: 4, height: 4))
            path.addRoundedRect(in: CGRect(x: 130, y: 30, width: 28, height: 16),
                                cornerSize: CGSize(width: 4, height: 4))
            // Pantograph hint (not a logo)
            body(88, 8, 4, 14); body(78, 8, 24, 4)
            wheel(28); wheel(86); wheel(148)
        case .toyCar:
            path.addRoundedRect(in: CGRect(x: 48, y: 34, width: 94, height: 28),
                                cornerSize: CGSize(width: 12, height: 12))
            outline([CGPoint(x: 62, y: 34), CGPoint(x: 74, y: 18),
                     CGPoint(x: 118, y: 18), CGPoint(x: 132, y: 34)])
            wheel(58, y: 56, size: 18); wheel(118, y: 56, size: 18)
        case .crane:
            body(10, 39, 117, 22); body(128, 45, 49, 16)
            outline([CGPoint(x: 128, y: 45), CGPoint(x: 138, y: 31),
                     CGPoint(x: 165, y: 31), CGPoint(x: 177, y: 45)])
            outline([CGPoint(x: 40, y: 40), CGPoint(x: 128, y: 4),
                     CGPoint(x: 133, y: 10), CGPoint(x: 56, y: 43)])
            body(116, 11, 3, 22); body(109, 30, 17, 3)
            wheel(27); wheel(103); wheel(150)
        case .tanker:
            path.addRoundedRect(in: CGRect(x: 13, y: 24, width: 117, height: 33),
                                cornerSize: CGSize(width: 16, height: 16))
            body(127, 39, 47, 22)
            outline([CGPoint(x: 130, y: 39), CGPoint(x: 142, y: 29),
                     CGPoint(x: 164, y: 29), CGPoint(x: 174, y: 39)])
            wheel(29); wheel(106); wheel(151)
        case .articulatedBus:
            body(8, 22, 77, 39); body(93, 22, 91, 39)
            outline([CGPoint(x: 85, y: 24), CGPoint(x: 93, y: 20),
                     CGPoint(x: 93, y: 61), CGPoint(x: 85, y: 61)])
            wheel(25); wheel(113); wheel(160)
        case .dinoFlatbed:
            body(9, 51, 125, 10); body(133, 43, 43, 18)
            outline([CGPoint(x: 35, y: 51), CGPoint(x: 45, y: 38),
                     CGPoint(x: 53, y: 28), CGPoint(x: 67, y: 26),
                     CGPoint(x: 79, y: 31), CGPoint(x: 92, y: 23),
                     CGPoint(x: 104, y: 19), CGPoint(x: 116, y: 22),
                     CGPoint(x: 119, y: 28), CGPoint(x: 109, y: 30),
                     CGPoint(x: 98, y: 29), CGPoint(x: 87, y: 42),
                     CGPoint(x: 83, y: 51), CGPoint(x: 76, y: 51),
                     CGPoint(x: 73, y: 41), CGPoint(x: 61, y: 45),
                     CGPoint(x: 57, y: 51)])
            wheel(27); wheel(107); wheel(151)
        case .logisticsTruck:
            body(10, 20, 113, 40); body(126, 38, 52, 22)
            outline([CGPoint(x: 126, y: 38), CGPoint(x: 139, y: 27),
                     CGPoint(x: 161, y: 27), CGPoint(x: 178, y: 38)])
            wheel(26); wheel(101); wheel(153)
        }
        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 190, y: rect.height / 80))
    }
}

/// High-saturation kid paints — recognizable city colors without brand marks.
enum ToyPaint: CaseIterable {
    case hkTaxiRed, nyTaxiYellow, fireEngineRed, metroSilverBlue
    case skyBlue, cherryRed, sunflower, meadowGreen, tangerine, grape

    var color: Color {
        switch self {
        case .hkTaxiRed: return Color(red: 0.86, green: 0.12, blue: 0.14)
        case .nyTaxiYellow: return Color(red: 1.00, green: 0.80, blue: 0.08)
        case .fireEngineRed: return Color(red: 0.92, green: 0.16, blue: 0.14)
        case .metroSilverBlue: return Color(red: 0.55, green: 0.72, blue: 0.82) // soft metal + blue stripe via overlay
        case .skyBlue: return Color(red: 0.20, green: 0.55, blue: 0.82)
        case .cherryRed: return Color(red: 0.90, green: 0.28, blue: 0.26)
        case .sunflower: return Color(red: 1.00, green: 0.82, blue: 0.18)
        case .meadowGreen: return Color(red: 0.28, green: 0.62, blue: 0.38)
        case .tangerine: return Color(red: 1.00, green: 0.55, blue: 0.18)
        case .grape: return Color(red: 0.55, green: 0.38, blue: 0.78)
        }
    }

    static func forKind(_ kind: VehicleKind) -> ToyPaint {
        switch kind {
        case .hkTaxi: return .hkTaxiRed
        case .nyTaxi: return .nyTaxiYellow
        case .fireEngine: return .fireEngineRed
        case .metroTrain: return .metroSilverBlue
        case .toyCar: return .sunflower
        case .crane: return .tangerine
        case .tanker: return .skyBlue
        case .articulatedBus: return .cherryRed
        case .dinoFlatbed: return .meadowGreen
        case .logisticsTruck: return .grape
        }
    }
}

struct VehicleFaceOverlay: View {
    let kind: VehicleKind
    let mood: VehicleFaceMood

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let anchor = faceAnchor(in: CGSize(width: w, height: h))
            let eyeW = max(10, w * 0.055)
            let eyeH: CGFloat = {
                switch mood {
                case .sleepy: return eyeW * 0.55
                case .calm: return eyeW * 0.85
                case .happy: return eyeW * 0.95
                }
            }()
            ZStack {
                RoundedRectangle(cornerRadius: eyeW * 0.8, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: eyeW * 3.4, height: eyeW * 2.2)
                    .overlay(
                        RoundedRectangle(cornerRadius: eyeW * 0.8, style: .continuous)
                            .stroke(Color.black.opacity(0.18), lineWidth: 1.5)
                    )
                HStack(spacing: eyeW * 0.55) {
                    eye(size: CGSize(width: eyeW, height: eyeH))
                    eye(size: CGSize(width: eyeW, height: eyeH))
                }
                .offset(y: mood == .sleepy ? -eyeW * 0.1 : -eyeW * 0.15)
                Capsule()
                    .fill(Color(red: 0.35, green: 0.18, blue: 0.12).opacity(0.85))
                    .frame(width: mood == .happy ? eyeW * 1.35 : eyeW * 0.9,
                           height: mood == .happy ? eyeW * 0.28 : eyeW * 0.16)
                    .offset(y: eyeW * 0.55)
            }
            .position(anchor)
        }
        .allowsHitTesting(false)
    }

    private func eye(size: CGSize) -> some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Color.white)
                .frame(width: size.width, height: size.height)
            Capsule()
                .fill(Color(red: 0.18, green: 0.12, blue: 0.10))
                .frame(width: size.width * 0.55, height: size.height * (mood == .sleepy ? 0.35 : 0.55))
                .offset(y: mood == .sleepy ? size.height * 0.15 : size.height * 0.2)
            Capsule()
                .fill(Color(red: 0.45, green: 0.28, blue: 0.18).opacity(0.35))
                .frame(width: size.width, height: size.height * 0.28)
                .offset(y: -size.height * 0.05)
        }
    }

    private func faceAnchor(in size: CGSize) -> CGPoint {
        let sx = size.width / 190
        let sy = size.height / 80
        let design: CGPoint
        switch kind {
        case .hkTaxi, .nyTaxi: design = CGPoint(x: 78, y: 30)
        case .fireEngine: design = CGPoint(x: 48, y: 28)
        case .metroTrain: design = CGPoint(x: 36, y: 36)
        case .toyCar: design = CGPoint(x: 102, y: 28)
        case .crane: design = CGPoint(x: 150, y: 38)
        case .tanker: design = CGPoint(x: 148, y: 34)
        case .articulatedBus: design = CGPoint(x: 40, y: 34)
        case .dinoFlatbed: design = CGPoint(x: 152, y: 40)
        case .logisticsTruck: design = CGPoint(x: 150, y: 34)
        }
        return CGPoint(x: design.x * sx, y: design.y * sy)
    }
}

struct FriendlyVehicleView: View {
    let kind: VehicleKind
    var paint: Color? = nil
    var mood: VehicleFaceMood = .calm
    var showFace: Bool = true

    var body: some View {
        let fill = paint ?? ToyPaint.forKind(kind).color
        ZStack {
            VehicleSilhouette(kind: kind)
                .fill(fill)
                .shadow(color: Color.black.opacity(0.18), radius: 4, y: 3)
            // Metro: original blue window stripe (not a transit logo).
            if kind == .metroTrain {
                Capsule()
                    .fill(Color(red: 0.10, green: 0.35, blue: 0.72).opacity(0.85))
                    .frame(height: 8)
                    .padding(.horizontal, 22)
                    .offset(y: 6)
            }
            // Soft highlight
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(height: 6)
                .padding(.horizontal, 28)
                .offset(y: -8)
                .opacity(0.8)
            if showFace {
                VehicleFaceOverlay(kind: kind, mood: mood)
            }
        }
    }
}
