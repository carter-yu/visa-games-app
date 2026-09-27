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
    /// Calming soft blue/green large-area fill — never bedroom-yellow walls.
    public let background: (red: Double, green: Double, blue: Double)
    public let foreground: (red: Double, green: Double, blue: Double)
    /// Primary control / vehicle accent (palette identity).
    public let accent: (red: Double, green: Double, blue: Double)
    /// Warm yellow used only as highlights: buttons, sparkles, soft sun/road stripes.
    public let yellow: (red: Double, green: Double, blue: Double)
    public let watermark: (red: Double, green: Double, blue: Double)

    public static func forID(_ id: ThemePaletteID) -> ThemePack {
        switch id {
        case .sunnyYellow:
            // Accent-forward default: soft sky + mint background, cheerful yellow accents.
            ThemePack(id: id, parentLabel: "陽光黃 / Sunny Yellow",
                background: (0.10, 0.22, 0.28), foreground: (1.00, 0.98, 0.92),
                accent: (1.00, 0.82, 0.18), yellow: (1.00, 0.92, 0.35),
                watermark: (0.72, 0.82, 0.55))
        case .engineeringOrange:
            // Warmer orange identity + yellow highlights on soft blue-green walls.
            ThemePack(id: id, parentLabel: "工程橙 / Engineering Orange",
                background: (0.09, 0.18, 0.22), foreground: (1.00, 0.97, 0.91),
                accent: (1.00, 0.58, 0.16), yellow: (1.00, 0.86, 0.28),
                watermark: (0.78, 0.68, 0.40))
        case .logisticsWhiteRed:
            // Keep white-red identity; yellow for button/sparkle highlights only.
            ThemePack(id: id, parentLabel: "物流白紅 / Logistics White-Red",
                background: (0.12, 0.18, 0.22), foreground: (1.00, 0.98, 0.96),
                accent: (0.92, 0.30, 0.26), yellow: (1.00, 0.88, 0.32),
                watermark: (0.90, 0.74, 0.68))
        case .busBlue:
            // Keep bus-blue identity; yellow highlights for curiosity/focus accents.
            ThemePack(id: id, parentLabel: "巴士藍 / Bus Blue",
                background: (0.07, 0.16, 0.26), foreground: (0.94, 0.98, 1.00),
                accent: (0.30, 0.67, 0.96), yellow: (1.00, 0.90, 0.34),
                watermark: (0.52, 0.74, 0.88))
        }
    }

    public static func == (lhs: ThemePack, rhs: ThemePack) -> Bool {
        lhs.id == rhs.id && lhs.parentLabel == rhs.parentLabel &&
        lhs.background == rhs.background && lhs.foreground == rhs.foreground &&
        lhs.accent == rhs.accent && lhs.yellow == rhs.yellow && lhs.watermark == rhs.watermark
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
