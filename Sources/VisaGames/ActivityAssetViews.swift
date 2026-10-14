import SwiftUI
import VisaCore

/// Resolves VisaCore asset IDs (`silhouette.*` / `prop.*`) for child activity art.
enum ActivityAsset {
    enum Resolved: Equatable {
        case vehicle(VehicleKind)
        /// v0.22.0 find-the-same L3 look: flipped and / or a sticker (`VehicleLook`).
        case styledVehicle(VehicleKind, mirrored: Bool, decor: VehicleDecor?)
        case prop(DepotPropKind)
    }

    static func resolve(_ assetID: String) -> Resolved? {
        if let kind = SilhouetteAsset.kind(for: assetID) {
            return .vehicle(kind)
        }
        if let look = VehicleLook(assetID: assetID),
           let kind = SilhouetteAsset.kind(for: look.vehicle.assetID) {
            return .styledVehicle(kind, mirrored: look.mirrored, decor: look.decor)
        }
        switch assetID {
        case "prop.sun": return .prop(.sun)
        case "prop.cloud": return .prop(.cloud)
        case "prop.trafficCone": return .prop(.trafficCone)
        case "prop.trafficLight": return .prop(.trafficLight)
        case "prop.garageDoor": return .prop(.garageDoor)
        case "prop.stamp": return .prop(.stamp)
        case "prop.ticket": return .prop(.ticket)
        case "prop.toolbox": return .prop(.toolbox)
        default: return nil
        }
    }
}

/// Colored hero or soft prop for activity cards.
struct ActivityAssetView: View {
    let assetID: String
    var mood: VehicleFaceMood = .happy
    /// When true, draw vehicle as a black silhouette (shadow-match target).
    var asShadow: Bool = false

    var body: some View {
        switch ActivityAsset.resolve(assetID) {
        case .vehicle(let kind):
            if asShadow {
                Color.black.opacity(0.88)
                    .mask(FriendlyVehicleView(kind: kind, mood: .calm, role: .hero))
            } else {
                FriendlyVehicleView(kind: kind, mood: mood, role: .hero)
            }
        case .styledVehicle(let kind, let mirrored, let decor):
            StyledVehicleView(kind: kind, mirrored: mirrored, decor: decor, mood: mood)
        case .prop(let kind):
            DepotPropView(kind: kind)
        case .none:
            Text("?")
                .font(.system(size: 48, weight: .bold, design: .rounded))
        }
    }
}

/// Hero PNG plus the find-the-same L3 details. The sticker sits on the fitted image and
/// flips with the vehicle, so "facing" and "sticker" stay one difference each.
struct StyledVehicleView: View {
    let kind: VehicleKind
    let mirrored: Bool
    let decor: VehicleDecor?
    var mood: VehicleFaceMood = .happy

    var body: some View {
        FriendlyVehicleView(kind: kind, mood: mood, role: .hero)
            .overlay {
                if let decor {
                    VehicleDecorOverlay(decor: decor)
                }
            }
            .scaleEffect(x: mirrored ? -1 : 1, y: 1)
    }
}

/// Vector stickers in the storybook style: thick ink outline, flat bright fill.
/// Drawn in the image's own bounds (top-left area, over the roof / upper body).
struct VehicleDecorOverlay: View {
    let decor: VehicleDecor

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height)
            let line = max(2, unit * 0.028)
            let ink = Color.ink
            switch decor {
            case .star:
                // Round white badge with a sunny star (reads on every hero colour).
                let center = CGPoint(x: size.width * 0.30, y: size.height * 0.30)
                let radius = unit * 0.19
                let badge = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                   width: radius * 2, height: radius * 2))
                context.fill(badge, with: .color(Color(hex: DesignTokens.Palette.paper)))
                context.stroke(badge, with: .color(ink), lineWidth: line)
                let star = Self.starPath(center: center, outer: radius * 0.78, inner: radius * 0.34)
                context.fill(star, with: .color(Color(hex: DesignTokens.Palette.sunny)))
                context.stroke(star, with: .color(ink), style: StrokeStyle(lineWidth: line * 0.8, lineJoin: .round))
            case .flag:
                // Pole from the upper body with a blue pennant pointing toward the front.
                let poleX = size.width * 0.16
                let top = size.height * 0.02
                let bottom = size.height * 0.46
                let pole = Path(roundedRect: CGRect(x: poleX - line, y: top, width: line * 2, height: bottom - top),
                                cornerRadius: line)
                context.fill(pole, with: .color(Color(hex: DesignTokens.Palette.paper)))
                context.stroke(pole, with: .color(ink), lineWidth: line * 0.8)
                var pennant = Path()
                pennant.move(to: CGPoint(x: poleX + line, y: top + line))
                pennant.addLine(to: CGPoint(x: poleX + unit * 0.34, y: top + unit * 0.12))
                pennant.addLine(to: CGPoint(x: poleX + line, y: top + unit * 0.24))
                pennant.closeSubpath()
                context.fill(pennant, with: .color(Color(hex: DesignTokens.Palette.metro)))
                context.stroke(pennant, with: .color(ink), style: StrokeStyle(lineWidth: line, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func starPath(center: CGPoint, outer: CGFloat, inner: CGFloat) -> Path {
        var path = Path()
        for index in 0..<10 {
            let radius = index.isMultiple(of: 2) ? outer : inner
            let angle = -CGFloat.pi / 2 + CGFloat(index) * CGFloat.pi / 5
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// Count stimulus: vehicles at the generated placements (row / two rows / scatter),
/// scaled from `CountCanvas` units into the panel. The fixed v0 item keeps its single row.
struct CountStimulusView: View {
    let question: CountQuestion

    var body: some View {
        if let variant = question.variant {
            GeometryReader { geo in
                let canvasWidth = CGFloat(CountCanvas.width)
                let canvasHeight = CGFloat(CountCanvas.height)
                let scale: CGFloat = min(geo.size.width / canvasWidth, geo.size.height / canvasHeight)
                let originX: CGFloat = (geo.size.width - canvasWidth * scale) / 2
                let originY: CGFloat = (geo.size.height - canvasHeight * scale) / 2
                ZStack(alignment: .topLeading) {
                    ForEach(Array(variant.placements.enumerated()), id: \.offset) { _, spot in
                        ActivityAssetView(assetID: variant.vehicle.assetID, mood: .calm)
                            .frame(width: CGFloat(spot.width) * scale, height: CGFloat(spot.height) * scale)
                            .position(x: originX + CGFloat(spot.x) * scale, y: originY + CGFloat(spot.y) * scale)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(variant.vehicle.nameTraditionalChinese) / \(variant.vehicle.nameEnglish)")
        } else {
            HStack(spacing: 8) {
                ForEach(Array(question.vehicleAssetIDs.enumerated()), id: \.offset) { _, assetID in
                    ActivityAssetView(assetID: assetID, mood: .calm)
                }
            }
        }
    }
}

/// Clips a vehicle/prop to its left or right half for half-match.
struct HalfVehicleClip: View {
    let assetID: String
    let side: HalfSide
    var mood: VehicleFaceMood = .calm

    enum HalfSide { case left, right }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ActivityAssetView(assetID: assetID, mood: mood)
                .frame(width: w * 2, height: h)
                .offset(x: side == .left ? 0 : -w)
                .frame(width: w, height: h, alignment: .leading)
                .clipped()
        }
    }
}

/// Shared prompt + hint chrome for the v0.8 activity pack.
struct ActivityPromptChrome: View {
    let promptZH: String
    let promptEN: String
    let foreground: Color
    let accent: Color
    let yellow: Color
    let retryMessage: String?
    let hintUsed: Bool
    let onHint: () -> Void
    let onSpeakPrompt: () -> Void
    var titleSize: CGFloat = 34

    var body: some View {
        VStack(spacing: 12) {
            Text(promptZH)
                .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
            Text(promptEN)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 18, weight: .medium, design: .rounded))
            if let retryMessage {
                Text(retryMessage)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 20) {
                Button(hintUsed ? "提示已用 / Hint used" : "提示 / Hint", action: onHint)
                    .disabled(hintUsed)
                    .tint(accent)
                Button("聽提示（稍後） / Hear prompt (later)", action: onSpeakPrompt)
                    .tint(yellow)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
