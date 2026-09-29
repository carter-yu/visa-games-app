import Foundation

/// Paint for one canvas vector element. Colours are 0xRRGGBB from `DesignTokens.Palette`.
public struct CanvasArtStyle: Equatable, Sendable {
    public enum LineCap: Sendable { case butt, round }
    public enum LineJoin: Sendable { case miter, round }

    public var fill: UInt32?
    public var stroke: UInt32?
    public var lineWidth: Double
    public var dash: [Double]
    public var lineCap: LineCap
    public var lineJoin: LineJoin
    public var opacity: Double

    public init(fill: UInt32? = nil, stroke: UInt32? = nil, lineWidth: Double = 0, dash: [Double] = [],
                lineCap: LineCap = .butt, lineJoin: LineJoin = .miter, opacity: Double = 1) {
        self.fill = fill
        self.stroke = stroke
        self.lineWidth = lineWidth
        self.dash = dash
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.opacity = opacity
    }
}

public enum CanvasArtGeometry: Equatable, Sendable {
    case path([SVGPathCommand])
    case rect(x: Double, y: Double, width: Double, height: Double, radius: Double)
    case circle(cx: Double, cy: Double, r: Double)
    case ellipse(cx: Double, cy: Double, rx: Double, ry: Double)
}

public struct CanvasArtElement: Equatable, Sendable {
    public let geometry: CanvasArtGeometry
    public let style: CanvasArtStyle
}

/// One piece of canvas artwork in its own SVG viewBox, painted back to front.
public struct CanvasArtwork: Equatable, Sendable {
    public let name: String
    public let width: Double
    public let height: Double
    public let elements: [CanvasArtElement]
}

/// Vector artwork transcribed from the concept canvas boards (ADR 0007). Original designs only.
public enum CanvasArt {
    public static let all: [CanvasArtwork] = [
        stampy, taxi, fireEngine, metro, bus, depotScene, star, speaker, parentIcon, penSpark
    ]

    /// 「印仔 Stampy」 guide: a round yellow depot cart with a rubber-stamp handle (board 1 pose).
    public static let stampy = CanvasArtwork(name: "stampy", width: 200, height: 200, elements: [
        circle(56, 172, 17, inked(P.ink, join: .round, cap: .butt)),
        circle(144, 172, 17, inked(P.ink, join: .round, cap: .butt)),
        rect(88, 22, 24, 36, r: 6, inked(P.woodDark, join: .round, cap: .butt)),
        circle(100, 22, 16, inked(P.tomato, join: .round, cap: .butt)),
        rect(22, 52, 156, 120, r: 52, inked(P.sunny, join: .round, cap: .butt)),
        circle(94, 16, 4, filled(P.white, opacity: 0.7)),
        ellipse(74, 102, 16, 19, outlined(P.white, width: 4)),
        ellipse(126, 102, 16, 19, outlined(P.white, width: 4)),
        circle(78, 107, 8, filled(P.ink)),
        circle(130, 107, 8, filled(P.ink)),
        circle(81, 103, 3, filled(P.white)),
        circle(133, 103, 3, filled(P.white)),
        ellipse(50, 134, 11, 7, filled(P.blush)),
        ellipse(150, 134, 11, 7, filled(P.blush)),
        path("M84 132 Q100 152 116 132 Z", CanvasArtStyle(fill: P.mouth, stroke: P.ink, lineWidth: 4, lineJoin: .round))
    ])

    /// 的士短程 ticket vehicle (240×150 box shared by all vehicles).
    public static let taxi = CanvasArtwork(name: "taxi", width: 240, height: 150, elements: [
        rect(102, 10, 42, 18, r: 6, inked(P.white)),
        path("M66 62 L90 30 Q95 24 103 24 H150 Q158 24 164 31 L190 62 Z", inked(P.sunny)),
        path("M92 58 L106 36 H122 V58 Z", inked(P.glass)),
        path("M134 58 V36 H152 L168 58 Z", inked(P.glass)),
        rect(12, 58, 218, 56, r: 24, inked(P.sunny)),
        circle(64, 116, 20, inked(P.ink)),
        circle(182, 116, 20, inked(P.ink)),
        path("M28 88 H186", CanvasArtStyle(stroke: P.ink, lineWidth: 8, dash: [10, 10])),
        circle(64, 116, 8, filled(P.hubcap)),
        circle(182, 116, 8, filled(P.hubcap)),
        circle(208, 76, 10, outlined(P.white, width: 4)),
        circle(210, 78, 4.5, filled(P.ink)),
        ellipse(199, 96, 6, 4, filled(P.blush)),
        path("M205 100 Q211 105 218 100", smile(width: 4))
    ])

    public static let fireEngine = CanvasArtwork(name: "fireEngine", width: 240, height: 150, elements: [
        rect(164, 10, 22, 18, r: 6, inked(P.metro)),
        rect(12, 52, 150, 64, r: 16, inked(P.tomato)),
        path("M30 46 V52 M130 46 V52", inked(nil)),
        rect(20, 30, 120, 16, r: 8, inked(P.sunny)),
        path("M44 30 V46 M68 30 V46 M92 30 V46 M116 30 V46", inked(nil)),
        path("M148 116 V42 Q148 26 164 26 H194 Q212 26 220 44 L229 64 Q233 72 233 82 V102 Q233 116 219 116 Z",
             inked(P.tomato)),
        path("M166 40 H192 Q202 40 207 50 L213 64 H166 Z", inked(P.glass)),
        rect(28, 66, 44, 30, r: 8, inked(P.lamp)),
        rect(86, 66, 44, 30, r: 8, inked(P.lamp)),
        circle(60, 118, 20, inked(P.ink)),
        circle(190, 118, 20, inked(P.ink)),
        circle(60, 118, 8, filled(P.hubcap)),
        circle(190, 118, 8, filled(P.hubcap)),
        circle(215, 78, 10, outlined(P.white, width: 4)),
        circle(217, 80, 4.5, filled(P.ink)),
        ellipse(204, 93, 6, 4, filled(P.blush)),
        path("M211 96 Q218 102 225 96", smile(width: 4))
    ])

    public static let metro = CanvasArtwork(name: "metro", width: 240, height: 150, elements: [
        circle(46, 122, 12, inked(P.ink)),
        circle(78, 122, 12, inked(P.ink)),
        circle(164, 122, 12, inked(P.ink)),
        circle(196, 122, 12, inked(P.ink)),
        path("M10 40 Q10 26 24 26 H174 Q212 26 227 64 L231 78 Q234 90 234 100 V102 Q234 116 220 116 H24 Q10 116 10 102 Z",
             inked(P.metro)),
        rect(26, 42, 36, 30, r: 8, inked(P.glass)),
        rect(74, 42, 36, 30, r: 8, inked(P.glass)),
        rect(122, 42, 36, 30, r: 8, inked(P.glass)),
        path("M172 42 H194 Q206 46 212 62 L214 72 H172 Z", inked(P.glass)),
        rect(13, 102, 214, 8, filled(P.white)),
        circle(216, 84, 9, outlined(P.white, width: 4)),
        circle(218, 86, 4, filled(P.ink)),
        ellipse(202, 96, 5, 3.5, filled(P.blush)),
        path("M210 97 Q216 101 222 97", smile(width: 3.5))
    ])

    /// Mint bus from the activity board.
    public static let bus = CanvasArtwork(name: "bus", width: 240, height: 150, elements: [
        rect(10, 24, 222, 92, r: 22, inked(P.mint)),
        rect(24, 38, 34, 32, r: 7, inked(P.glass)),
        rect(68, 38, 34, 32, r: 7, inked(P.glass)),
        rect(112, 38, 34, 32, r: 7, inked(P.glass)),
        rect(156, 38, 30, 58, r: 7, inked(P.glass)),
        path("M198 38 H212 Q222 38 222 50 V70 H198 Z", inked(P.glass)),
        circle(58, 118, 20, inked(P.ink)),
        circle(190, 118, 20, inked(P.ink)),
        circle(58, 118, 8, filled(P.hubcap)),
        circle(190, 118, 8, filled(P.hubcap)),
        circle(214, 84, 9, outlined(P.white, width: 4)),
        circle(216, 86, 4, filled(P.ink)),
        path("M208 100 Q214 105 221 100", smile(width: 3.5))
    ])

    /// Board 1 scenery: sky, clouds, hills, the depot garage and the sandy yard (1280×720).
    public static let depotScene = CanvasArtwork(name: "depotScene", width: 1280, height: 720, elements: [
        rect(0, 0, 1280, 720, filled(P.sky)),
        ellipse(470, 96, 74, 28, filled(P.white)),
        ellipse(520, 78, 48, 34, filled(P.white)),
        ellipse(428, 84, 36, 26, filled(P.white)),
        ellipse(780, 66, 56, 22, filled(P.white)),
        ellipse(816, 52, 36, 26, filled(P.white)),
        path("M0 318 Q170 250 360 300 T720 292 T1080 282 T1280 292 V720 H0 Z", filled(P.grassLight)),
        path("M0 372 Q250 322 520 362 T1040 346 T1280 356 V720 H0 Z", filled(P.grass)),
        rect(880, 236, 330, 214, r: 12, inked(P.paper, cap: .butt)),
        path("M856 248 L1045 168 L1234 248 Z", inked(P.tomato, cap: .butt)),
        path("M896 450 V340 Q896 306 930 306 H954 Q988 306 988 340 V450 Z", inked(P.sunny, cap: .butt)),
        path("M1000 450 V340 Q1000 306 1034 306 H1058 Q1092 306 1092 340 V450 Z", inked(P.sunny, cap: .butt)),
        path("M1104 450 V340 Q1104 306 1138 306 H1162 Q1196 306 1196 340 V450 Z", inked(P.sunny, cap: .butt)),
        circle(1045, 216, 22, inked(P.sunny, cap: .butt)),
        path("M900 362 H984 M898 390 H986 M898 418 H986 M1004 362 H1088 M1002 390 H1090 M1002 418 H1090 M1108 362 H1192 M1106 390 H1194 M1106 418 H1194",
             CanvasArtStyle(stroke: P.ink, lineWidth: 3, opacity: 0.35)),
        path("M1045 203 l3.8 7.8 8.6 1.2-6.2 6 1.5 8.5-7.7-4.1-7.7 4.1 1.5-8.5-6.2-6 8.6-1.2z", filled(P.tomato)),
        rect(0, 446, 1280, 274, filled(P.sand)),
        path("M0 446 H1280", CanvasArtStyle(stroke: P.ink, lineWidth: 5)),
        path("M60 704 H1220", CanvasArtStyle(stroke: P.roadDash, lineWidth: 10, dash: [60, 40], lineCap: .round))
    ])

    /// Ticket star (24×24).
    public static let star = CanvasArtwork(name: "star", width: 24, height: 24, elements: [
        path("M12 2.8l2.8 5.8 6.4.8-4.7 4.4 1.2 6.3L12 17l-5.7 3.1 1.2-6.3-4.7-4.4 6.4-.8z",
             CanvasArtStyle(fill: P.sunny, stroke: P.ink, lineWidth: 2, lineJoin: .round))
    ])

    /// Speech-bubble speaker (24×24): the replay-voice cue.
    public static let speaker = CanvasArtwork(name: "speaker", width: 24, height: 24, elements: [
        path("M4 9.5v5h3.5L12 18.5V5.5L7.5 9.5H4z",
             CanvasArtStyle(fill: P.sunny, stroke: P.ink, lineWidth: 2.4, lineCap: .round, lineJoin: .round)),
        path("M15.5 9a4 4 0 0 1 0 6", CanvasArtStyle(stroke: P.ink, lineWidth: 2.4, lineCap: .round, lineJoin: .round)),
        path("M18.5 6.5a7.5 7.5 0 0 1 0 11", CanvasArtStyle(stroke: P.ink, lineWidth: 2.4, lineCap: .round, lineJoin: .round))
    ])

    /// Faint parent-corner mark (24×24); drawn at 45% opacity by the corner.
    public static let parentIcon = CanvasArtwork(name: "parentIcon", width: 24, height: 24, elements: [
        circle(12, 12, 3.5, CanvasArtStyle(stroke: P.ink, lineWidth: 2, lineCap: .round)),
        path("M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1",
             CanvasArtStyle(stroke: P.ink, lineWidth: 2, lineCap: .round))
    ])

    /// Pen spark glow ring (128×128) that follows the pen on the TV.
    public static let penSpark = CanvasArtwork(name: "penSpark", width: 128, height: 128, elements: [
        circle(64, 64, 56, filled(P.sunny, opacity: 0.2)),
        circle(64, 64, 44, CanvasArtStyle(stroke: P.sunny, lineWidth: 9)),
        circle(64, 64, 44, CanvasArtStyle(stroke: P.ink, lineWidth: 2, opacity: 0.5)),
        circle(64, 64, 11, outlined(P.white, width: 4)),
        path("M64 3 V14 M64 114 V125 M3 64 H14 M114 64 H125",
             CanvasArtStyle(stroke: P.white, lineWidth: 5, lineCap: .round))
    ])
}

// MARK: - Transcription helpers

private typealias P = DesignTokens.Palette

/// The canvas's common group style: 5 pt ink outline with rounded joins (and usually caps).
private func inked(_ fill: UInt32?, join: CanvasArtStyle.LineJoin = .round,
                   cap: CanvasArtStyle.LineCap = .round) -> CanvasArtStyle {
    CanvasArtStyle(fill: fill, stroke: DesignTokens.Palette.ink, lineWidth: DesignTokens.outlineWidth,
                   lineCap: cap, lineJoin: join)
}

private func outlined(_ fill: UInt32, width: Double) -> CanvasArtStyle {
    CanvasArtStyle(fill: fill, stroke: DesignTokens.Palette.ink, lineWidth: width)
}

private func filled(_ fill: UInt32, opacity: Double = 1) -> CanvasArtStyle {
    CanvasArtStyle(fill: fill, opacity: opacity)
}

private func smile(width: Double) -> CanvasArtStyle {
    CanvasArtStyle(stroke: DesignTokens.Palette.ink, lineWidth: width, lineCap: .round)
}

private func path(_ data: String, _ style: CanvasArtStyle) -> CanvasArtElement {
    // Unparsable data yields an empty path; CanvasFoundationTests fails on any empty path.
    CanvasArtElement(geometry: .path((try? SVGPathData.parse(data)) ?? []), style: style)
}

private func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, r: Double = 0,
                  _ style: CanvasArtStyle) -> CanvasArtElement {
    CanvasArtElement(geometry: .rect(x: x, y: y, width: width, height: height, radius: r), style: style)
}

private func circle(_ cx: Double, _ cy: Double, _ r: Double, _ style: CanvasArtStyle) -> CanvasArtElement {
    CanvasArtElement(geometry: .circle(cx: cx, cy: cy, r: r), style: style)
}

private func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double,
                     _ style: CanvasArtStyle) -> CanvasArtElement {
    CanvasArtElement(geometry: .ellipse(cx: cx, cy: cy, rx: rx, ry: ry), style: style)
}
