import SwiftUI
import VisaCore

/// Draws canvas vector artwork, crisp at any TV size. `.fit` keeps the whole artwork visible;
/// `.fill` covers the frame edge to edge (backdrops).
struct VectorArtView: View {
    let artwork: CanvasArtwork
    var contentMode: ContentMode = .fit

    var body: some View {
        Canvas { context, size in
            VectorArtRenderer.draw(artwork, in: &context, size: size, contentMode: contentMode)
        }
        .accessibilityHidden(true)
    }
}

enum VectorArtRenderer {
    static func draw(_ artwork: CanvasArtwork, in context: inout GraphicsContext, size: CGSize,
                     contentMode: ContentMode) {
        guard artwork.width > 0, artwork.height > 0, size.width > 0, size.height > 0 else { return }
        let scaleX = size.width / artwork.width
        let scaleY = size.height / artwork.height
        let scale = contentMode == .fit ? min(scaleX, scaleY) : max(scaleX, scaleY)
        var canvas = context
        canvas.translateBy(x: (size.width - artwork.width * scale) / 2, y: (size.height - artwork.height * scale) / 2)
        canvas.scaleBy(x: scale, y: scale)
        for element in artwork.elements {
            draw(element, in: canvas)
        }
    }

    private static func draw(_ element: CanvasArtElement, in context: GraphicsContext) {
        var layer = context
        layer.opacity = context.opacity * element.style.opacity
        let path = Path(canvasGeometry: element.geometry)
        if let fill = element.style.fill {
            layer.fill(path, with: .color(Color(hex: fill)))
        }
        if let stroke = element.style.stroke, element.style.lineWidth > 0 {
            layer.stroke(path, with: .color(Color(hex: stroke)), style: StrokeStyle(
                lineWidth: element.style.lineWidth,
                lineCap: element.style.lineCap == .round ? .round : .butt,
                lineJoin: element.style.lineJoin == .round ? .round : .miter,
                dash: element.style.dash.map { CGFloat($0) }
            ))
        }
    }
}

extension Path {
    init(canvasGeometry geometry: CanvasArtGeometry) {
        switch geometry {
        case let .path(commands):
            self.init()
            for command in commands {
                switch command {
                case let .move(x, y): move(to: CGPoint(x: x, y: y))
                case let .line(x, y): addLine(to: CGPoint(x: x, y: y))
                case let .quad(cx, cy, x, y): addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
                case let .cubic(c1x, c1y, c2x, c2y, x, y):
                    addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
                case .close: closeSubpath()
                }
            }
        case let .rect(x, y, width, height, radius):
            let rect = CGRect(x: x, y: y, width: width, height: height)
            let corner = min(radius, width / 2, height / 2)
            self.init(roundedRect: rect, cornerRadius: max(0, corner), style: .circular)
        case let .circle(cx, cy, r):
            self.init(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        case let .ellipse(cx, cy, rx, ry):
            self.init(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
        }
    }
}
