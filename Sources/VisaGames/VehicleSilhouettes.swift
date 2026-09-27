import SwiftUI
import AppKit

/// Original cute vehicle silhouettes inspired by recognizable real-world types
/// (HK red taxi, NY yellow taxi, HK fire engine, metro train, long works trucks).
/// Original IP only — no licensed character faces, no protected transit logos.
/// Option 4 hybrid: illustrated hero PNGs (tickets / parade leader / success) +
/// simple procedural fleet for dense games. Front *is* the face on heroes.
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
        func roundBody(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 12) {
            path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h),
                                cornerSize: CGSize(width: r, height: r))
        }
        func wheel(_ x: CGFloat, y: CGFloat = 56, size: CGFloat = 18) {
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
            // Chubbier rounded city taxi — soft toy cab, facing right.
            roundBody(40, 34, 112, 28, 14)
            roundBody(57, 13, 82, 39, 19)
            // Soft roof lamp
            roundBody(86, 8, 24, 10, 5)
            // Rounded nose / bumper bulb (face sits here)
            roundBody(125, 29, 43, 34, 16)
            wheel(52, y: 54, size: 20); wheel(124, y: 54, size: 20)
        case .fireEngine:
            // Soft cab (left, facing left) + rounded rear box with ladder hint.
            roundBody(16, 26, 74, 36, 14)
            roundBody(86, 20, 80, 42, 12)
            roundBody(14, 12, 74, 46, 18)
            // Nose bulb at cab front
            roundBody(3, 27, 45, 36, 17)
            roundBody(94, 10, 64, 7, 3)
            roundBody(150, 10, 7, 18, 3)
            wheel(32, y: 56, size: 18); wheel(108, y: 56, size: 18); wheel(146, y: 56, size: 18)
        case .metroTrain:
            // Chubby metro car — rounded ends; face on left front (no transit roundel).
            roundBody(6, 20, 178, 40, 20)
            // Side windows are painted separately, without internal silhouette seams.
            // Pantograph hint
            roundBody(86, 6, 5, 14, 2); roundBody(76, 6, 26, 5, 2)
            // Broad rounded metro front, distinct from a steam locomotive.
            roundBody(2, 19, 45, 44, 20)
            wheel(30, y: 56, size: 18); wheel(88, y: 56, size: 18); wheel(148, y: 56, size: 18)
        case .toyCar:
            roundBody(46, 32, 98, 30, 15)
            roundBody(60, 12, 76, 42, 20)
            roundBody(122, 28, 43, 35, 17)
            wheel(56, y: 54, size: 20); wheel(116, y: 54, size: 20)
        case .crane:
            roundBody(8, 38, 118, 24, 12); roundBody(124, 42, 44, 18, 10)
            outline([CGPoint(x: 126, y: 42), CGPoint(x: 136, y: 28),
                     CGPoint(x: 164, y: 28), CGPoint(x: 176, y: 42)])
            outline([CGPoint(x: 40, y: 40), CGPoint(x: 128, y: 4),
                     CGPoint(x: 134, y: 10), CGPoint(x: 56, y: 44)])
            roundBody(114, 10, 4, 22, 2); roundBody(108, 28, 18, 4, 2)
            roundBody(145, 31, 39, 32, 14)
            wheel(26, y: 56, size: 18); wheel(100, y: 56, size: 18); wheel(148, y: 56, size: 18)
        case .tanker:
            roundBody(12, 22, 118, 36, 18)
            roundBody(124, 36, 46, 24, 12)
            outline([CGPoint(x: 128, y: 36), CGPoint(x: 140, y: 26),
                     CGPoint(x: 164, y: 26), CGPoint(x: 176, y: 36)])
            roundBody(145, 29, 39, 34, 15)
            wheel(28, y: 56, size: 18); wheel(104, y: 56, size: 18); wheel(150, y: 56, size: 18)
        case .articulatedBus:
            roundBody(6, 20, 80, 42, 14); roundBody(92, 20, 90, 42, 14)
            outline([CGPoint(x: 84, y: 24), CGPoint(x: 94, y: 18),
                     CGPoint(x: 94, y: 62), CGPoint(x: 84, y: 62)])
            roundBody(2, 24, 42, 39, 18)
            wheel(24, y: 56, size: 18); wheel(112, y: 56, size: 18); wheel(158, y: 56, size: 18)
        case .dinoFlatbed:
            roundBody(8, 50, 126, 12, 6); roundBody(130, 40, 44, 20, 10)
            outline([CGPoint(x: 34, y: 50), CGPoint(x: 44, y: 36),
                     CGPoint(x: 52, y: 26), CGPoint(x: 68, y: 24),
                     CGPoint(x: 80, y: 30), CGPoint(x: 92, y: 22),
                     CGPoint(x: 104, y: 18), CGPoint(x: 116, y: 22),
                     CGPoint(x: 120, y: 28), CGPoint(x: 110, y: 30),
                     CGPoint(x: 98, y: 28), CGPoint(x: 88, y: 42),
                     CGPoint(x: 84, y: 50), CGPoint(x: 76, y: 50),
                     CGPoint(x: 72, y: 40), CGPoint(x: 60, y: 44),
                     CGPoint(x: 56, y: 50)])
            roundBody(145, 32, 39, 31, 14)
            wheel(26, y: 56, size: 18); wheel(106, y: 56, size: 18); wheel(150, y: 56, size: 18)
        case .logisticsTruck:
            roundBody(8, 18, 116, 42, 12); roundBody(122, 34, 48, 26, 12)
            outline([CGPoint(x: 124, y: 34), CGPoint(x: 138, y: 22),
                     CGPoint(x: 162, y: 22), CGPoint(x: 178, y: 34)])
            roundBody(145, 27, 41, 36, 16)
            wheel(24, y: 56, size: 18); wheel(100, y: 56, size: 18); wheel(152, y: 56, size: 18)
        }
        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: rect.width / 190, y: rect.height / 80))
    }
}

/// High-saturation kid paints — warmer storybook fills, recognizable city colors without brand marks.
enum ToyPaint: CaseIterable {
    case hkTaxiRed, nyTaxiYellow, fireEngineRed, metroSilverBlue
    case skyBlue, cherryRed, sunflower, meadowGreen, tangerine, grape

    var color: Color {
        switch self {
        case .hkTaxiRed: return Color(red: 0.90, green: 0.22, blue: 0.24)
        case .nyTaxiYellow: return Color(red: 1.00, green: 0.84, blue: 0.18)
        case .fireEngineRed: return Color(red: 0.94, green: 0.24, blue: 0.22)
        case .metroSilverBlue: return Color(red: 0.62, green: 0.78, blue: 0.88)
        case .skyBlue: return Color(red: 0.28, green: 0.62, blue: 0.88)
        case .cherryRed: return Color(red: 0.92, green: 0.34, blue: 0.32)
        case .sunflower: return Color(red: 1.00, green: 0.86, blue: 0.28)
        case .meadowGreen: return Color(red: 0.36, green: 0.70, blue: 0.44)
        case .tangerine: return Color(red: 1.00, green: 0.62, blue: 0.28)
        case .grape: return Color(red: 0.62, green: 0.44, blue: 0.82)
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

/// Features share the silhouette's 190 x 80 drawing space.
/// Eyes are large half-lidded headlight / boiler-front sockets — the face *is* the front.
struct VehicleFaceOverlay: View {
    let kind: VehicleKind
    let mood: VehicleFaceMood

    private let ink = Color(red: 0.32, green: 0.22, blue: 0.18)
    var paint: Color? = nil
    private let sclera = Color(red: 1.0, green: 0.98, blue: 0.92)
    private let blush = Color(red: 1.0, green: 0.62, blue: 0.58)

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 190, y: size.height / 80)
            let layout = faceAnchor
            let eyeWidth = layout.eyeWidth
            let eyeHeight = layout.eyeHeight

            // Soft cheek blush under each eye — painterly storybook cue.
            for side in [-1.0, 1.0] {
                let cx = layout.center.x + CGFloat(side) * eyeWidth * 0.72
                let blushRect = CGRect(x: cx - eyeWidth * 0.28,
                                       y: layout.center.y + eyeHeight * 0.42,
                                       width: eyeWidth * 0.55, height: eyeHeight * 0.28)
                context.fill(Path(ellipseIn: blushRect), with: .color(blush.opacity(0.45)))
            }

            for side in [-1.0, 1.0] {
                let centerX = layout.center.x + CGFloat(side) * eyeWidth * 0.62
                let rect = CGRect(x: centerX - eyeWidth / 2,
                                  y: layout.center.y - eyeHeight / 2,
                                  width: eyeWidth, height: eyeHeight)
                drawEye(in: rect, context: context)
            }

            // Tiny soft nostrils between eyes on the front disc.
            if layout.showNose {
                let noseY = layout.center.y + eyeHeight * 0.38
                for side in [-1.0, 1.0] {
                    let n = CGRect(x: layout.center.x + CGFloat(side) * 3.2 - 1.4,
                                   y: noseY, width: 2.8, height: 2.4)
                    context.fill(Path(ellipseIn: n), with: .color(ink.opacity(0.55)))
                }
            }

            // Bumper / grille smile — short soft curve.
            let smileWidth = eyeWidth * 0.95
            let smileDepth: CGFloat = mood == .happy ? 4.2 : (mood == .sleepy ? 1.2 : 2.2)
            var smile = Path()
            smile.move(to: CGPoint(x: layout.center.x - smileWidth / 2, y: layout.mouthY))
            smile.addQuadCurve(to: CGPoint(x: layout.center.x + smileWidth / 2, y: layout.mouthY),
                               control: CGPoint(x: layout.center.x, y: layout.mouthY + smileDepth))
            context.stroke(smile, with: .color(ink),
                           style: StrokeStyle(lineWidth: 1.35, lineCap: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawEye(in rect: CGRect, context: GraphicsContext) {
        // Soft oval headlight socket (not a floating white plate).
        let socket = Path(ellipseIn: rect)
        // Heavier lids — storybook sleepy default; calm still half-lidded; happy a bit more open.
        let lidFraction: CGFloat = mood == .sleepy ? 0.62 : (mood == .happy ? 0.38 : 0.52)
        let lidY = rect.minY + rect.height * lidFraction
        var eyeContext = context
        eyeContext.clip(to: socket)
        // The eyelid is painted metal, continuous with the hood.
        let lidPaint = paint ?? ToyPaint.forKind(kind).color
        eyeContext.fill(socket, with: .color(lidPaint))
        eyeContext.fill(socket, with: .linearGradient(
            Gradient(colors: [sclera.opacity(0.30), sclera.opacity(0.04)]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY),
            endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
        // Cream sclera only in the open lower part
        eyeContext.fill(Path(CGRect(x: rect.minX - 1, y: lidY,
                                    width: rect.width + 2, height: rect.maxY - lidY + 1)),
                        with: .color(sclera))
        // Low gentle pupil
        let pupilSize = min(rect.width, rect.height) * 0.28
        let pupil = CGRect(x: rect.midX - pupilSize / 2,
                           y: rect.maxY - pupilSize - rect.height * 0.10,
                           width: pupilSize, height: pupilSize * 0.92)
        eyeContext.fill(Path(ellipseIn: pupil), with: .color(ink))
        // Tiny highlight
        let spark = CGRect(x: pupil.midX + pupilSize * 0.12,
                           y: pupil.minY + pupilSize * 0.08,
                           width: pupilSize * 0.28, height: pupilSize * 0.28)
        eyeContext.fill(Path(ellipseIn: spark), with: .color(Color.white.opacity(0.85)))
        // Soft hooded lid stroke
        var lid = Path()
        lid.move(to: CGPoint(x: rect.minX + 1, y: lidY))
        lid.addQuadCurve(to: CGPoint(x: rect.maxX - 1, y: lidY),
                         control: CGPoint(x: rect.midX, y: lidY + rect.height * 0.10))
        eyeContext.stroke(lid, with: .color(ink),
                          style: StrokeStyle(lineWidth: 1.65, lineCap: .round))
        // Outer soft outline
        context.stroke(socket, with: .color(ink.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
    }

    /// Eyes fit inside each broad hood or cab front, clear of side windows and wheels.
    private var faceAnchor: (center: CGPoint, eyeWidth: CGFloat, eyeHeight: CGFloat, mouthY: CGFloat, showNose: Bool) {
        switch kind {
        case .hkTaxi, .nyTaxi:
            return (CGPoint(x: 147, y: 42), 14, 17, 56, false)
        case .fireEngine:
            return (CGPoint(x: 25, y: 41), 15, 18, 56, false)
        case .metroTrain:
            return (CGPoint(x: 24, y: 37), 15, 20, 55, false)
        case .toyCar:
            return (CGPoint(x: 143, y: 41), 14, 17, 56, false)
        case .crane:
            return (CGPoint(x: 164, y: 43), 13, 16, 57, false)
        case .tanker:
            return (CGPoint(x: 164, y: 42), 13, 17, 57, false)
        case .articulatedBus:
            return (CGPoint(x: 23, y: 40), 14, 18, 56, false)
        case .dinoFlatbed:
            return (CGPoint(x: 164, y: 44), 13, 15, 57, false)
        case .logisticsTruck:
            return (CGPoint(x: 165, y: 41), 14, 18, 57, false)
        }
    }
}

/// Painted details use the same coordinates as the body and never handle input.
private struct VehicleBodyDetails: View {
    let kind: VehicleKind

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 190, y: size.height / 80)
            let ink = Color(red: 0.32, green: 0.22, blue: 0.18)
            let cream = Color(red: 1, green: 0.94, blue: 0.77)
            let body = VehicleSilhouette(kind: kind).path(in: CGRect(x: 0, y: 0, width: 190, height: 80))
            context.fill(body, with: .linearGradient(
                Gradient(colors: [cream.opacity(0.42), cream.opacity(0.08), ink.opacity(0.12)]),
                startPoint: CGPoint(x: 20, y: 8), endPoint: CGPoint(x: 100, y: 70)))

            func panel(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, color: Color) {
                let shape = Path(roundedRect: CGRect(x: x, y: y, width: w, height: h),
                                 cornerRadius: 4)
                context.fill(shape, with: .color(color))
                context.stroke(shape, with: .color(ink.opacity(0.75)), lineWidth: 1.1)
            }
            let glass = Color(red: 0.67, green: 0.82, blue: 0.79)
            let wheels: [CGFloat]
            let wheelSize: CGFloat
            switch kind {
            case .hkTaxi, .nyTaxi:
                // Silver HK roof and small amber NY roof lamp; eyes stay on the hood.
                panel(72, 17, 49, 5, color: kind == .hkTaxi ? cream : .yellow)
                panel(64, 25, 24, 15, color: glass)
                panel(94, 25, 25, 15, color: glass)
                wheels = [52, 124]; wheelSize = 20
            case .toyCar:
                panel(68, 21, 23, 19, color: glass)
                panel(97, 21, 23, 19, color: glass)
                wheels = [56, 116]; wheelSize = 20
            case .fireEngine:
                panel(51, 19, 24, 22, color: glass)
                panel(96, 31, 60, 7, color: cream)
                panel(99, 45, 24, 10, color: cream.opacity(0.65))
                panel(130, 45, 24, 10, color: cream.opacity(0.65))
                wheels = [32, 108, 146]; wheelSize = 18
            case .metroTrain:
                for x in [CGFloat(53), 85, 117, 149] {
                    panel(x, 27, 23, 16, color: glass)
                }
                panel(51, 48, 123, 5, color: Color(red: 0.23, green: 0.48, blue: 0.69))
                wheels = [30, 88, 148]; wheelSize = 18
            case .articulatedBus:
                for x in [CGFloat(49), 101, 128, 155] {
                    panel(x, 27, 20, 17, color: glass)
                }
                for x in [CGFloat(85), 89, 93] {
                    panel(x, 28, 1, 28, color: cream.opacity(0.6))
                }
                wheels = [24, 112, 158]; wheelSize = 18
            case .crane:
                panel(131, 32, 13, 13, color: glass)
                wheels = [26, 100, 148]; wheelSize = 18
            case .tanker:
                panel(131, 30, 13, 15, color: glass)
                panel(27, 28, 85, 6, color: cream.opacity(0.5))
                wheels = [28, 104, 150]; wheelSize = 18
            case .dinoFlatbed:
                panel(132, 37, 11, 12, color: glass)
                wheels = [26, 106, 150]; wheelSize = 18
            case .logisticsTruck:
                panel(129, 28, 14, 17, color: glass)
                panel(20, 26, 91, 6, color: cream.opacity(0.5))
                wheels = [24, 100, 152]; wheelSize = 18
            }
            for x in wheels {
                let tire = CGRect(x: x, y: wheelSize == 20 ? 54 : 56,
                                  width: wheelSize, height: wheelSize)
                context.fill(Path(ellipseIn: tire), with: .color(ink))
                context.fill(Path(ellipseIn: tire.insetBy(dx: wheelSize * 0.28, dy: wheelSize * 0.28)),
                             with: .color(cream.opacity(0.85)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Hybrid Option 4 visual role — illustrated heroes vs simple procedural fleet.
enum VehicleVisualRole: Hashable {
    /// Tickets / parade leader / success stamp — prefer raster hero PNG.
    case hero
    /// Dense games (count / sequence / find-same clutter) — simple silhouette, minimal/no face.
    case fleet
}

/// Bundle resource names for richly faced hero PNGs under Resources/Vehicles/.
enum VehicleHeroAsset {
    static func resourceName(for kind: VehicleKind) -> String? {
        switch kind {
        case .hkTaxi: return "hero-hk-taxi"
        case .nyTaxi: return "hero-ny-taxi"
        case .fireEngine: return "hero-fire-engine"
        case .metroTrain: return "hero-metro-train"
        default: return nil
        }
    }

    /// Loads from Contents/Resources/Vehicles/ (preferred) or flat Resources /.
    static func image(for kind: VehicleKind) -> NSImage? {
        guard let name = resourceName(for: kind) else { return nil }
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Vehicles")
            ?? Bundle.main.url(forResource: name, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: name)
    }
}

struct FriendlyVehicleView: View {
    let kind: VehicleKind
    var paint: Color? = nil
    var mood: VehicleFaceMood = .calm
    /// Legacy toggle; ignored when `role == .fleet` (fleet never draws the storybook face).
    var showFace: Bool = true
    /// Option 4 hybrid: `.hero` uses PNG when available; `.fleet` stays procedural + faceless.
    var role: VehicleVisualRole = .fleet

    var body: some View {
        if role == .hero, let nsImage = VehicleHeroAsset.image(for: kind) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            proceduralBody(drawFace: role == .hero && showFace)
        }
    }

    /// Simple fleet / hero fallback: same color language; faces only when hero PNG missing.
    @ViewBuilder
    private func proceduralBody(drawFace: Bool) -> some View {
        let fill = paint ?? ToyPaint.forKind(kind).color
        ZStack {
            VehicleSilhouette(kind: kind)
                .fill(fill.opacity(0.28))
                .offset(y: 2)
                .blur(radius: 1.2)
            VehicleSilhouette(kind: kind)
                .fill(fill)
                .overlay(
                    VehicleSilhouette(kind: kind)
                        .stroke(Color(red: 0.32, green: 0.22, blue: 0.18).opacity(0.72),
                                style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                )
                .shadow(color: Color.brown.opacity(0.14), radius: 4, y: 2)
            VehicleBodyDetails(kind: kind)
                .clipShape(VehicleSilhouette(kind: kind))
            if drawFace {
                VehicleFaceOverlay(kind: kind, mood: mood, paint: fill)
            }
        }
    }
}
