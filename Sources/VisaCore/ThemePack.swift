import Foundation

public enum ThemePaletteID: String, CaseIterable, Sendable, Equatable {
    case engineeringOrange
    case logisticsWhiteRed
    case busBlue
}

public struct ThemePack: Sendable, Equatable {
    public let id: ThemePaletteID
    public let parentLabel: String
    public let background: (red: Double, green: Double, blue: Double)
    public let foreground: (red: Double, green: Double, blue: Double)
    public let accent: (red: Double, green: Double, blue: Double)
    public let watermark: (red: Double, green: Double, blue: Double)

    public static func forID(_ id: ThemePaletteID) -> ThemePack {
        switch id {
        case .engineeringOrange:
            ThemePack(id: id, parentLabel: "工程橙 / Engineering Orange",
                background: (0.08, 0.12, 0.17), foreground: (1, 0.97, 0.91),
                accent: (1, 0.55, 0.18), watermark: (0.85, 0.62, 0.36))
        case .logisticsWhiteRed:
            ThemePack(id: id, parentLabel: "物流白紅 / Logistics White-Red",
                background: (0.13, 0.14, 0.17), foreground: (1, 0.98, 0.96),
                accent: (0.92, 0.28, 0.25), watermark: (0.92, 0.72, 0.68))
        case .busBlue:
            ThemePack(id: id, parentLabel: "巴士藍 / Bus Blue",
                background: (0.06, 0.13, 0.24), foreground: (0.94, 0.98, 1),
                accent: (0.30, 0.67, 0.96), watermark: (0.54, 0.75, 0.91))
        }
    }

    public static func == (lhs: ThemePack, rhs: ThemePack) -> Bool {
        lhs.id == rhs.id && lhs.parentLabel == rhs.parentLabel &&
        lhs.background == rhs.background && lhs.foreground == rhs.foreground &&
        lhs.accent == rhs.accent && lhs.watermark == rhs.watermark
    }
}

public struct ThemePreferenceStore {
    public static let key = "VisaGames.themePaletteID"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> ThemePaletteID {
        guard let raw = defaults.string(forKey: Self.key) else { return .engineeringOrange }
        return ThemePaletteID(rawValue: raw) ?? .engineeringOrange
    }

    public func save(_ palette: ThemePaletteID) {
        defaults.set(palette.rawValue, forKey: Self.key)
    }
}
