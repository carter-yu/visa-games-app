import Foundation

public enum ThemePaletteID: String, CaseIterable, Sendable, Equatable {
    case sunnyYellow
    case engineeringOrange
    case logisticsWhiteRed
    case busBlue
}

public struct ThemePack: Sendable, Equatable {
    public let id: ThemePaletteID
    public let parentLabel: String
    /// Warm sand / soft sky large-area fill — storybook depot, not dark teal walls.
    public let background: (red: Double, green: Double, blue: Double)
    public let foreground: (red: Double, green: Double, blue: Double)
    /// Primary control / vehicle accent (palette identity).
    public let accent: (red: Double, green: Double, blue: Double)
    /// Warm yellow used as highlights: tickets, sparkles, soft sun.
    public let yellow: (red: Double, green: Double, blue: Double)
    public let watermark: (red: Double, green: Double, blue: Double)
    /// Soft sky wash for storybook dunes (top of shell).
    public let sky: (red: Double, green: Double, blue: Double)
    /// Deeper ochre for dune / wooden-sign shadows.
    public let sand: (red: Double, green: Double, blue: Double)

    public static func forID(_ id: ThemePaletteID) -> ThemePack {
        switch id {
        case .sunnyYellow:
            // Default: warm ochre depot + soft sky; cheerful blue/yellow toys.
            ThemePack(id: id, parentLabel: "陽光沙地 / Sunny Sand",
                background: (0.97, 0.88, 0.64), foreground: (0.29, 0.17, 0.12),
                accent: (0.18, 0.54, 0.75), yellow: (1.00, 0.82, 0.18),
                watermark: (0.82, 0.62, 0.32),
                sky: (0.72, 0.88, 0.96), sand: (0.91, 0.74, 0.42))
        case .engineeringOrange:
            ThemePack(id: id, parentLabel: "工程橙沙 / Engineering Ochre",
                background: (0.96, 0.84, 0.62), foreground: (0.28, 0.16, 0.10),
                accent: (1.00, 0.52, 0.14), yellow: (1.00, 0.86, 0.28),
                watermark: (0.78, 0.58, 0.30),
                sky: (0.78, 0.90, 0.95), sand: (0.88, 0.68, 0.38))
        case .logisticsWhiteRed:
            ThemePack(id: id, parentLabel: "物流紅沙 / Logistics Red Sand",
                background: (0.97, 0.90, 0.78), foreground: (0.26, 0.14, 0.12),
                accent: (0.90, 0.28, 0.24), yellow: (1.00, 0.88, 0.32),
                watermark: (0.86, 0.66, 0.52),
                sky: (0.82, 0.92, 0.96), sand: (0.90, 0.76, 0.55))
        case .busBlue:
            ThemePack(id: id, parentLabel: "巴士藍沙 / Bus Blue Sand",
                background: (0.93, 0.90, 0.78), foreground: (0.14, 0.22, 0.32),
                accent: (0.22, 0.58, 0.88), yellow: (1.00, 0.90, 0.34),
                watermark: (0.55, 0.70, 0.82),
                sky: (0.68, 0.84, 0.96), sand: (0.86, 0.74, 0.48))
        }
    }

    public static func == (lhs: ThemePack, rhs: ThemePack) -> Bool {
        lhs.id == rhs.id && lhs.parentLabel == rhs.parentLabel &&
        lhs.background == rhs.background && lhs.foreground == rhs.foreground &&
        lhs.accent == rhs.accent && lhs.yellow == rhs.yellow &&
        lhs.watermark == rhs.watermark && lhs.sky == rhs.sky && lhs.sand == rhs.sand
    }
}

public struct ThemePreferenceStore {
    public static let key = "VisaGames.themePaletteID"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> ThemePaletteID {
        guard let raw = defaults.string(forKey: Self.key) else { return .sunnyYellow }
        return ThemePaletteID(rawValue: raw) ?? .sunnyYellow
    }

    public func save(_ palette: ThemePaletteID) {
        defaults.set(palette.rawValue, forKey: Self.key)
    }
}
