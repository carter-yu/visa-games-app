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

/// Features share the silhouette's 190 x 80 drawing space, including at small sizes.
/// Each eye is a cab window; the painted body between windows and bumper is the face.
struct VehicleFaceOverlay: View {
    let kind: VehicleKind
    let mood: VehicleFaceMood

    private let ink = Color(red: 0.29, green: 0.20, blue: 0.16)
    private let glass = Color(red: 0.57, green: 0.76, blue: 0.77)
    private let sclera = Color(red: 1.0, green: 0.97, blue: 0.87)

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 190, y: size.height / 80)
            let layout = faceAnchor
            let eyeWidth = layout.eyeWidth
            let eyeHeight = layout.eyeHeight
            for side in [-1.0, 1.0] {
                let centerX = layout.center.x + CGFloat(side) * eyeWidth * 0.66
                let rect = CGRect(x: centerX - eyeWidth / 2,
                                  y: layout.center.y - eyeHeight / 2,
                                  width: eyeWidth, height: eyeHeight)
                drawEye(in: rect, context: context)
            }

            // A small bumper/hood smile, separate from the windshield glass.
            let smileWidth = eyeWidth * (mood == .happy ? 1.05 : 0.75)
            let smileDepth: CGFloat = mood == .happy ? 3.0 : (mood == .sleepy ? 0.6 : 1.6)
            var smile = Path()
            smile.move(to: CGPoint(x: layout.center.x - smileWidth / 2, y: layout.mouthY))
            smile.addQuadCurve(to: CGPoint(x: layout.center.x + smileWidth / 2, y: layout.mouthY),
                               control: CGPoint(x: layout.center.x, y: layout.mouthY + smileDepth))
            context.stroke(smile, with: .color(ink),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawEye(in rect: CGRect, context: GraphicsContext) {
        let socket = Path(roundedRect: rect,
                          cornerRadius: rect.width * 0.45)
        let lidFraction: CGFloat = mood == .sleepy ? 0.57 : (mood == .happy ? 0.29 : 0.42)
        let lidY = rect.minY + rect.height * lidFraction
        var eyeContext = context
        eyeContext.clip(to: socket)
        eyeContext.fill(socket, with: .color(glass))
        // Cream whites only below the hooded lid; no shared white face plate.
        eyeContext.fill(Path(CGRect(x: rect.minX, y: lidY,
                                    width: rect.width, height: rect.maxY - lidY)),
                        with: .color(sclera))
        let pupilSize = rect.width * 0.32
        let pupil = CGRect(x: rect.midX - pupilSize / 2,
                           y: rect.maxY - pupilSize - rect.height * 0.12,
                           width: pupilSize, height: pupilSize)
        eyeContext.fill(Path(ellipseIn: pupil), with: .color(ink))
        var lid = Path()
        lid.move(to: CGPoint(x: rect.minX, y: lidY))
        lid.addQuadCurve(to: CGPoint(x: rect.maxX, y: lidY),
                         control: CGPoint(x: rect.midX, y: lidY + rect.height * 0.08))
        eyeContext.stroke(lid, with: .color(ink),
                          style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        context.stroke(socket, with: .color(ink),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
    }

    // Cab-specific anchors keep both sockets inside the actual vehicle body.
    // The low flatbed cab uses smaller headlight-zone eyes instead of a floating windshield.
    private var faceAnchor: (center: CGPoint, eyeWidth: CGFloat, eyeHeight: CGFloat, mouthY: CGFloat) {
        switch kind {
        case .hkTaxi, .nyTaxi:
            return (CGPoint(x: 94, y: 29), 12, 13, 46)
        case .fireEngine:
            return (CGPoint(x: 49, y: 28), 15, 17, 47)
        case .metroTrain:
            return (CGPoint(x: 32, y: 36), 12, 17, 51)
        case .toyCar:
            return (CGPoint(x: 96, y: 28), 11, 12, 44)
        case .crane:
            return (CGPoint(x: 152, y: 41), 9, 12, 55)
        case .tanker:
            return (CGPoint(x: 151, y: 39), 9, 12, 53)
        case .articulatedBus:
            return (CGPoint(x: 31, y: 35), 13, 18, 52)
        case .dinoFlatbed:
            return (CGPoint(x: 155, y: 49), 8, 9, 57)
        case .logisticsTruck:
            return (CGPoint(x: 151, y: 38), 10, 13, 53)
        }
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
                .overlay(
                    VehicleSilhouette(kind: kind)
                        .stroke(Color(red: 0.29, green: 0.20, blue: 0.16).opacity(0.8),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                )
                .shadow(color: Color.brown.opacity(0.16), radius: 4, y: 3)
            // Metro: original blue window stripe (not a transit logo).
            if kind == .metroTrain {
                Capsule()
                    .fill(Color(red: 0.10, green: 0.35, blue: 0.72).opacity(0.85))
                    .frame(height: 8)
                    .padding(.horizontal, 22)
                    .offset(y: 6)
                    .clipShape(VehicleSilhouette(kind: kind))
            }
            // Soft highlight
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(height: 6)
                .padding(.horizontal, 28)
                .offset(y: -8)
                .opacity(0.8)
                .clipShape(VehicleSilhouette(kind: kind))
            if showFace {
                VehicleFaceOverlay(kind: kind, mood: mood)
            }
        }
    }
}
