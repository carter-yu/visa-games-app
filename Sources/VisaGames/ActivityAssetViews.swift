import SwiftUI
import VisaCore

/// Resolves VisaCore asset IDs (`silhouette.*` / `prop.*`) for child activity art.
enum ActivityAsset {
    enum Resolved: Equatable {
        case vehicle(VehicleKind)
        case prop(DepotPropKind)
    }

    static func resolve(_ assetID: String) -> Resolved? {
        if let kind = SilhouetteAsset.kind(for: assetID) {
            return .vehicle(kind)
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
        case .prop(let kind):
            DepotPropView(kind: kind)
        case .none:
            Text("?")
                .font(.system(size: 48, weight: .bold, design: .rounded))
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
