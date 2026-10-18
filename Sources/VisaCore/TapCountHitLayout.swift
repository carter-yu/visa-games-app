import Foundation

/// v0.28.1: one source of truth for where a tap-count vehicle is drawn and where it can be tapped.
///
/// The board view draws every vehicle from `drawnFrame` and lays one tap target per occupied bay on
/// `hitRect`. Both are in stage units (1280×720, origin at the top-left of the stage), so the tap
/// target and the drawing cannot drift apart. v0.28.0 hit-tested in the workspace overlay's own
/// coordinates (origin y = 118) as if they were stage coordinates, which moved every target down
/// by 118u (about one ten-frame row).
public enum TapCountVehicleLayout {
    /// Half the 12u gap between neighbouring bays: hit targets grow into the gap but never overlap.
    public static let hitPad: Double = 6

    public static func art(_ model: TapCountModel) -> CanvasArtwork {
        switch model {
        case .tram: return TapCountArt.tram
        case .fireEngine: return TapCountArt.fireEngine
        case .digger: return TapCountArt.digger
        case .dumper: return TapCountArt.dumper
        case .mixer: return TapCountArt.mixer
        case .dozer: return TapCountArt.dozer
        case .roller: return TapCountArt.roller
        case .craneTruck: return TapCountArt.craneTruck
        case .plane: return TapCountArt.plane
        case .bus: return TapCountArt.bus
        }
    }

    /// The mockup scales (row 0.92; cells 0.7), shrunk only when a wider model would leave its bay.
    public static func scale(_ model: TapCountModel, layout: TapCountLayout) -> Double {
        let width = max(1, art(model).width)
        switch layout {
        case .row: return min(0.92, 226 / width)
        case .tenFrame, .yard: return min(0.7, 200 / width)
        }
    }

    /// Where the vehicle's art box lands on the stage on the tapping stage (before any bounce).
    public static func drawnFrame(_ vehicle: TapCountVehicle, in question: TapCountQuestion) -> LineMatchRect {
        let artwork = art(vehicle.model)
        let k = scale(vehicle.model, layout: question.layout)
        let ground = question.ground(vehicle)
        let anchor = TapCountArt.anchor(artwork)
        return LineMatchRect(x: ground.x - anchor.x * k, y: ground.y - anchor.y * k,
                             width: artwork.width * k, height: artwork.height * k)
    }

    /// The tap target for a bay, in stage units: the bay grown by `hitPad` into the gaps.
    public static func hitRect(bay: Int, in question: TapCountQuestion) -> LineMatchRect {
        let r = question.bayRect(bay)
        return LineMatchRect(x: r.x - hitPad, y: r.y - hitPad,
                             width: r.width + 2 * hitPad, height: r.height + 2 * hitPad)
    }

    /// One tap target per vehicle (empty bays take no taps).
    public static func hitTargets(_ question: TapCountQuestion) -> [(bay: Int, rect: LineMatchRect)] {
        question.occupiedBays.map { ($0, hitRect(bay: $0, in: question)) }
    }

    /// The bay whose tap target contains a stage point (nil = between or outside targets).
    public static func bay(atStage point: LineMatchPoint, in question: TapCountQuestion) -> Int? {
        hitTargets(question).first { target in
            let r = target.rect
            return point.x >= r.x && point.x <= r.maxX && point.y >= r.y && point.y <= r.maxY
        }?.bay
    }
}
