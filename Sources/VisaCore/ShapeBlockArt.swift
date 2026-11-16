import Foundation

// patterns-sorting (design §3.3, D7): 圓形, 正方形, 三角形 and the new 長方形 as blocks riding a small two-wheel
// cart. Original art from `CanvasArtGeometry` primitives in palette colours (no licensed asset). The block's body is
// the tap-count body sentinel, so `TapCountArt.tinted(_:body:)` paints it in any palette colour.

public enum ShapeBlockArt {
    static let ink: UInt32 = 0x2B2630
    static let cart: UInt32 = 0x7A6F80
    static let wheel: UInt32 = 0x5A5160
    static let hub: UInt32 = 0xD9D6DE

    /// 200 × 160 box; the cart spans x 30–170 (with strokes 28–172).
    public static func artwork(_ shape: PatternSortShape) -> CanvasArtwork {
        let body = CanvasArtStyle(fill: TapCountArt.bodySentinel, stroke: ink, lineWidth: 4, lineCap: .round, lineJoin: .round)
        let block: CanvasArtGeometry
        switch shape {
        case .circle: block = .circle(cx: 100, cy: 62, r: 46)
        case .square: block = .rect(x: 56, y: 18, width: 88, height: 88, radius: 6)
        case .triangle: block = .path([.move(x: 100, y: 12), .line(x: 152, y: 106), .line(x: 48, y: 106), .close])
        case .rectangle: block = .rect(x: 30, y: 42, width: 140, height: 64, radius: 6)
        }
        let inked = { (fill: UInt32) in CanvasArtStyle(fill: fill, stroke: ink, lineWidth: 4, lineCap: .round, lineJoin: .round) }
        return CanvasArtwork(name: "patternSort.block.\(shape.rawValue)", width: 200, height: 160, elements: [
            CanvasArtElement(geometry: block, style: body),
            CanvasArtElement(geometry: .rect(x: 30, y: 110, width: 140, height: 22, radius: 8), style: inked(cart)),
            CanvasArtElement(geometry: .circle(cx: 62, cy: 138, r: 14), style: inked(wheel)),
            CanvasArtElement(geometry: .circle(cx: 138, cy: 138, r: 14), style: inked(wheel)),
            CanvasArtElement(geometry: .circle(cx: 62, cy: 138, r: 5), style: CanvasArtStyle(fill: hub)),
            CanvasArtElement(geometry: .circle(cx: 138, cy: 138, r: 5), style: CanvasArtStyle(fill: hub))
        ])
    }

    /// The block painted in `colour`.
    public static func tinted(_ shape: PatternSortShape, colour: PatternSortColour) -> CanvasArtwork {
        TapCountArt.tinted(artwork(shape), body: colour.rgb)
    }

    /// The vector art of any piece except props (props are PNGs, `PatternSortProp.assetID`).
    public static func art(_ look: PatternSortLook) -> CanvasArtwork? {
        switch look.piece {
        case .block(let shape): return tinted(shape, colour: look.colour)
        case .vehicle(let model):
            return TapCountArt.named(model.rawValue).map { TapCountArt.tinted($0, body: look.colour.rgb) }
        case .prop: return nil
        }
    }
}
