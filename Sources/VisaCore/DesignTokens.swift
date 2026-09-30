import Foundation

/// Child-facing design tokens from the concept canvas (ADR 0007).
/// Artboards are authored at 1280×720. The app scales them to the screen and keeps all
/// interactive content inside a 5% TV safe area; backdrops bleed to the screen edges.
public enum DesignTokens {
    public typealias RGB = (red: Double, green: Double, blue: Double)

    /// 0xRRGGBB → 0...1 channels.
    public static func rgb(_ hex: UInt32) -> RGB {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    public enum Palette {
        // Brief tokens.
        public static let ink: UInt32 = 0x3A2718
        public static let sky: UInt32 = 0xA8E0F7
        public static let grass: UInt32 = 0x6FC063
        public static let sand: UInt32 = 0xF4CD74
        public static let sunny: UInt32 = 0xFFC928
        public static let tomato: UInt32 = 0xF0553A
        public static let metro: UInt32 = 0x2F7DE1
        public static let mint: UInt32 = 0x3CC49A
        public static let paper: UInt32 = 0xFFF6DF
        public static let stampRed: UInt32 = 0xD93A2B
        public static let road: UInt32 = 0x5B5F73
        // Supporting canvas colours.
        public static let white: UInt32 = 0xFFFFFF
        public static let inkSoft: UInt32 = 0x5A4636
        public static let grassLight: UInt32 = 0x8BD37B
        public static let roadDash: UInt32 = 0xE6B24F
        public static let sunnyPale: UInt32 = 0xFFE071
        public static let wood: UInt32 = 0xE8B77A
        public static let woodDark: UInt32 = 0xC98B4F
        public static let passportBlue: UInt32 = 0x2F4B8F
        public static let glass: UInt32 = 0xCFEFFF
        public static let hubcap: UInt32 = 0xE9E2D6
        public static let blush: UInt32 = 0xFF9C8A
        public static let mouth: UInt32 = 0x8C2E1E
        public static let lamp: UInt32 = 0xFFE7A3
        public static let taxiTicket: UInt32 = 0xFFF4C7
        public static let fireTicket: UInt32 = 0xFFE3DA
        public static let fireTicketHeader: UInt32 = 0xFFB8A6
        public static let metroTicket: UInt32 = 0xDDEBFF
        public static let metroTicketHeader: UInt32 = 0xA9CCF8
    }

    public static let referenceWidth: Double = 1280
    public static let referenceHeight: Double = 720
    public static let safeAreaFraction: Double = 0.05

    public static let outlineWidth: Double = 5
    public static let pressedOffset: Double = 6
    public static let pressedShadowDepth: Double = 2
    public static let hoverLift: Double = 4
    public static let choiceCardWidth: Double = 300
    public static let choiceCardHeight: Double = 210
    public static let maxChoices = 3
    public static let parentHoldSeconds: Double = 3

    /// Where the 1280×720 artboard lands on a screen.
    public struct StageLayout: Equatable, Sendable {
        /// Content scale: the whole artboard fits inside the TV safe area.
        public let scale: Double
        public let originX: Double
        public let originY: Double
        /// Backdrop scale: the artboard's scenery fills the screen edge to edge.
        public let backdropScale: Double
        public let backdropOriginX: Double
        public let backdropOriginY: Double

        public static let identity = StageLayout(scale: 1, originX: 0, originY: 0,
                                                 backdropScale: 1, backdropOriginX: 0, backdropOriginY: 0)
    }

    public static func stageLayout(screenWidth width: Double, screenHeight height: Double) -> StageLayout {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return .identity }
        let safeWidth = width * (1 - 2 * safeAreaFraction)
        let safeHeight = height * (1 - 2 * safeAreaFraction)
        let scale = min(safeWidth / referenceWidth, safeHeight / referenceHeight)
        let fill = max(width / referenceWidth, height / referenceHeight)
        return StageLayout(
            scale: scale,
            originX: (width - referenceWidth * scale) / 2,
            originY: (height - referenceHeight * scale) / 2,
            backdropScale: fill,
            backdropOriginX: (width - referenceWidth * fill) / 2,
            backdropOriginY: (height - referenceHeight * fill) / 2
        )
    }
}
