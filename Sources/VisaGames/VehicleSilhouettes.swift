import SwiftUI

enum VehicleKind: CaseIterable, Hashable {
    case crane, tanker, articulatedBus, dinoFlatbed, logisticsTruck
}

struct VehicleSilhouette: Shape {
    let kind: VehicleKind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func body(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            path.addRect(CGRect(x: x, y: y, width: w, height: h))
        }
        func wheel(_ x: CGFloat) {
            path.addEllipse(in: CGRect(x: x, y: 58, width: 16, height: 16))
        }
        func outline(_ points: [CGPoint]) {
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }

        switch kind {
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
