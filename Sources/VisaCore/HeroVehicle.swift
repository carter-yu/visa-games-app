import Foundation

/// The 10 illustrated hero vehicles (Resources/Vehicles) as plain data for generators.
/// UI-free: the app maps `assetID` to `VehicleKind` art. Colours and body families are
/// read off the hero PNGs (they cannot be recoloured safely, design §5 / §7).
public enum HeroVehicle: String, CaseIterable, Sendable, Codable, Hashable {
    case hkTaxi, nyTaxi, fireEngine, metroTrain, toyCar, crane, tanker, articulatedBus, dinoFlatbed, logisticsTruck

    /// Main body colour as the child sees it on the TV.
    public enum Paint: String, Sendable, Codable, Hashable {
        case red, yellow, orange, blue, silver, green, purple
    }

    /// Body family: what the outline looks like at card size.
    public enum Body: String, Sendable, Codable, Hashable {
        /// Short rounded car (taxis, toy car).
        case car
        /// Cab + working body (fire engine, crane, tanker, flatbed, box truck).
        case truck
        /// Long passenger body with a row of windows (bus, metro).
        case long
    }

    public var assetID: String { "silhouette.\(rawValue)" }

    public init?(assetID: String) {
        let prefix = "silhouette."
        guard assetID.hasPrefix(prefix) else { return nil }
        self.init(rawValue: String(assetID.dropFirst(prefix.count)))
    }

    public var paint: Paint {
        switch self {
        case .hkTaxi, .fireEngine, .articulatedBus: return .red
        case .nyTaxi, .toyCar: return .yellow
        case .crane: return .orange
        case .tanker: return .blue
        case .metroTrain: return .silver
        case .dinoFlatbed: return .green
        case .logisticsTruck: return .purple
        }
    }

    public var body: Body {
        switch self {
        case .hkTaxi, .nyTaxi, .toyCar: return .car
        case .fireEngine, .crane, .tanker, .dinoFlatbed, .logisticsTruck: return .truck
        case .metroTrain, .articulatedBus: return .long
        }
    }

    /// HK Traditional name (same words as the existing catalog labels).
    public var nameTraditionalChinese: String {
        switch self {
        case .hkTaxi: return "紅的"
        case .nyTaxi: return "黃的"
        case .fireEngine: return "消防車"
        case .metroTrain: return "地鐵"
        case .toyCar: return "玩具車"
        case .crane: return "吊臂車"
        case .tanker: return "油罐車"
        case .articulatedBus: return "巴士"
        case .dinoFlatbed: return "恐龍板車"
        case .logisticsTruck: return "貨車"
        }
    }

    public var nameEnglish: String {
        switch self {
        case .hkTaxi: return "Red taxi"
        case .nyTaxi: return "Yellow taxi"
        case .fireEngine: return "Fire truck"
        case .metroTrain: return "Metro train"
        case .toyCar: return "Toy car"
        case .crane: return "Crane truck"
        case .tanker: return "Tanker"
        case .articulatedBus: return "Bus"
        case .dinoFlatbed: return "Dino truck"
        case .logisticsTruck: return "Box truck"
        }
    }

    /// Lower-case plural for prompts ("How many buses?").
    public var pluralEnglish: String {
        switch self {
        case .hkTaxi: return "red taxis"
        case .nyTaxi: return "yellow taxis"
        case .fireEngine: return "fire trucks"
        case .metroTrain: return "metro trains"
        case .toyCar: return "toy cars"
        case .crane: return "crane trucks"
        case .tanker: return "tankers"
        case .articulatedBus: return "buses"
        case .dinoFlatbed: return "dino trucks"
        case .logisticsTruck: return "box trucks"
        }
    }

    /// Same paint *and* same body: too close to tell apart at card size on the TV
    /// (yellow taxi vs yellow toy car). Never shown together in one question.
    public static let lookalikes: [Set<HeroVehicle>] = [[.nyTaxi, .toyCar]]

    public func isLookalike(of other: HeroVehicle) -> Bool {
        other != self && Self.lookalikes.contains { $0.contains(self) && $0.contains(other) }
    }

    /// How many of the two salient features (paint, body) match `other`.
    public func sharedSalientFeatures(with other: HeroVehicle) -> Int {
        (paint == other.paint ? 1 : 0) + (body == other.body ? 1 : 0)
    }
}

/// Vector sticker drawn on a hero (find-the-same L3 detail differences).
public enum VehicleDecor: String, CaseIterable, Sendable, Codable, Hashable {
    /// Big yellow star sticker on the body.
    case star
    /// Small pennant on a pole above the roof.
    case flag

    public var nameTraditionalChinese: String {
        switch self {
        case .star: return "星星"
        case .flag: return "旗仔"
        }
    }

    public var nameEnglish: String {
        switch self {
        case .star: return "star"
        case .flag: return "flag"
        }
    }
}

/// One feature where two looks differ. Raw values feed the `diff:*` tags (design §5).
public enum VehicleFeature: String, CaseIterable, Sendable, Hashable {
    case color, type, facing, decor
}

/// A hero vehicle as drawn: type, facing and an optional sticker.
/// `assetID` stays the plain `silhouette.*` id for the default look, so every existing
/// asset id is a valid look; variants append `+mirror` / `+star` / `+flag`.
public struct VehicleLook: Sendable, Codable, Hashable {
    public var vehicle: HeroVehicle
    /// Drawn flipped left↔right (the whole vehicle, sticker included).
    public var mirrored: Bool
    public var decor: VehicleDecor?

    public init(vehicle: HeroVehicle, mirrored: Bool = false, decor: VehicleDecor? = nil) {
        self.vehicle = vehicle
        self.mirrored = mirrored
        self.decor = decor
    }

    public var assetID: String {
        var id = vehicle.assetID
        if mirrored { id += "+mirror" }
        if let decor { id += "+\(decor.rawValue)" }
        return id
    }

    /// Short stable code for item / choice ids, e.g. `hkTaxi+mirror+star`.
    public var code: String {
        String(assetID.dropFirst("silhouette.".count))
    }

    /// Parses `silhouette.<vehicle>[+mirror][+star|+flag]`. Unknown parts fail closed (nil).
    public init?(assetID: String) {
        let parts = assetID.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let first = parts.first, let vehicle = HeroVehicle(assetID: first) else { return nil }
        var mirrored = false
        var decor: VehicleDecor?
        for part in parts.dropFirst() {
            if part == "mirror", !mirrored {
                mirrored = true
            } else if let parsed = VehicleDecor(rawValue: part), decor == nil {
                decor = parsed
            } else {
                return nil
            }
        }
        self.init(vehicle: vehicle, mirrored: mirrored, decor: decor)
    }

    /// Features that differ from `other`. Type change implies the paint may differ too:
    /// `.color` is reported when the paint differs, `.type` when the vehicle differs.
    public func differences(from other: VehicleLook) -> [VehicleFeature] {
        var result: [VehicleFeature] = []
        if vehicle.paint != other.vehicle.paint { result.append(.color) }
        if vehicle != other.vehicle { result.append(.type) }
        if mirrored != other.mirrored { result.append(.facing) }
        if decor != other.decor { result.append(.decor) }
        return result
    }

    /// Option label, e.g. 「紅的 · 有星星 · 掉轉頭」 / "Red taxi, star, flipped".
    public var labelTraditionalChinese: String {
        var parts = [vehicle.nameTraditionalChinese]
        if let decor { parts.append("有\(decor.nameTraditionalChinese)") }
        if mirrored { parts.append("掉轉頭") }
        return parts.joined(separator: " · ")
    }

    public var labelEnglish: String {
        var parts = [vehicle.nameEnglish]
        if let decor { parts.append(decor.nameEnglish) }
        if mirrored { parts.append("flipped") }
        return parts.joined(separator: ", ")
    }
}
