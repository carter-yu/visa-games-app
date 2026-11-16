import Foundation

// patterns-sorting P0 (design §7, §5.2, §5.4, D6, D10): 跟住排設定 and 分類設定. Each family keeps its own help
// level (`TapCountGuidanceLevel`, shown 多啲／標準／少啲) and its own 廣東話語音 switch, default ON. Both apply at
// once, as 連一連設定 does. A broken or old blob loads the defaults (the Hanzi store precedent).

/// 跟住排 · 用乜嘢排: every pattern step exists for both materials, so materials never remove a step.
public enum PatternSortMaterials: String, CaseIterable, Sendable, Codable, Hashable {
    case vehicles, shapes, both

    public var allowed: [PatternSortMaterial] {
        switch self {
        case .vehicles: return [.vehicles]
        case .shapes: return [.shapes]
        case .both: return [.vehicles, .shapes]
        }
    }
}

/// 跟住排設定 (shared by 接落去 and 自己排).
public struct PatternSettings: Codable, Equatable, Sendable {
    public var materials: PatternSortMaterials
    public var guidance: TapCountGuidanceLevel
    public var audioEnabled: Bool

    public init(materials: PatternSortMaterials = .both, guidance: TapCountGuidanceLevel = .standard,
                audioEnabled: Bool = true) {
        self.materials = materials
        self.guidance = guidance
        self.audioEnabled = audioEnabled
    }

    public static let defaults = PatternSettings()
}

/// 分類設定 (shared by 邊個唔同類 and 分車房).
public struct SortSettings: Codable, Equatable, Sendable {
    public var methods: Set<PatternSortMethod>
    public var guidance: TapCountGuidanceLevel
    public var audioEnabled: Bool

    /// Design D10: every 分類方法 on except 車頭方向.
    public static let defaultMethods: Set<PatternSortMethod> = [.colour, .size, .shape, .kind, .group]

    public init(methods: Set<PatternSortMethod> = SortSettings.defaultMethods, guidance: TapCountGuidanceLevel = .standard,
                audioEnabled: Bool = true) {
        self.methods = methods
        self.guidance = guidance
        self.audioEnabled = audioEnabled
    }

    public static let defaults = SortSettings()

    /// At least one of 顏色・大細・形狀 stays on, so no enabled tier can run out of questions (§5.3). A set with all
    /// three off (only reachable from a hand-edited blob) gets 形狀 back: blocks can always be drawn.
    public func normalized() -> SortSettings {
        guard !methods.contains(where: PatternSortMethod.perceptual.contains) else { return self }
        var next = self
        next.methods.insert(.shape)
        return next
    }

    public enum MethodToggle: Equatable, Sendable {
        case updated(SortSettings)
        /// The last of 顏色・大細・形狀 stays on; the panel shows `PatternSortParentCopy.lastPerceptual`.
        case refusedLastPerceptual
    }

    /// The panel's switch: off → on always; on → off unless it is the last perceptual method.
    public func toggling(_ method: PatternSortMethod) -> MethodToggle {
        var next = self
        if methods.contains(method) {
            next.methods.remove(method)
            guard next.methods.contains(where: PatternSortMethod.perceptual.contains) else { return .refusedLastPerceptual }
        } else {
            next.methods.insert(method)
        }
        return .updated(next)
    }

    /// `game_dealt.methods` / `config_change` `sort_methods`: the on-set, sorted, space-separated
    /// (`colour group kind shape size`).
    public var methodsCode: String { methods.sorted().map(\.rawValue).joined(separator: " ") }
}

/// A saved settings change, for `config_change` (design §6.3 item 7 keys).
public struct PatternSortSettingChange: Equatable, Sendable {
    public let what: String
    public let value: String

    public init(what: String, value: String) {
        self.what = what
        self.value = value
    }

    public static func changes(from old: SortSettings, to new: SortSettings) -> [PatternSortSettingChange] {
        var result: [PatternSortSettingChange] = []
        if old.methods != new.methods { result.append(.init(what: "sort_methods", value: new.methodsCode)) }
        if old.guidance != new.guidance { result.append(.init(what: "sort_guidance", value: new.guidance.rawValue)) }
        if old.audioEnabled != new.audioEnabled {
            result.append(.init(what: "sort_audio", value: new.audioEnabled ? "on" : "off"))
        }
        return result
    }

    public static func changes(from old: PatternSettings, to new: PatternSettings) -> [PatternSortSettingChange] {
        var result: [PatternSortSettingChange] = []
        if old.materials != new.materials { result.append(.init(what: "pattern_materials", value: new.materials.rawValue)) }
        if old.guidance != new.guidance { result.append(.init(what: "pattern_guidance", value: new.guidance.rawValue)) }
        if old.audioEnabled != new.audioEnabled {
            result.append(.init(what: "pattern_audio", value: new.audioEnabled ? "on" : "off"))
        }
        return result
    }

    /// 由頭開始.
    public static let sortProgressReset = PatternSortSettingChange(what: "sort_progress", value: "reset")
    public static let patternProgressReset = PatternSortSettingChange(what: "pattern_progress", value: "reset")
}

/// `VisaGames.sortSettings.v1`; normalised on load.
public struct SortSettingsStore {
    public static let key = "VisaGames.sortSettings.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> SortSettings {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(SortSettings.self, from: data) else { return .defaults }
        return value.normalized()
    }

    public func save(_ value: SortSettings) {
        if let data = try? JSONEncoder().encode(value.normalized()) { defaults.set(data, forKey: Self.key) }
    }
}

/// `VisaGames.patternSettings.v1`.
public struct PatternSettingsStore {
    public static let key = "VisaGames.patternSettings.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> PatternSettings {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(PatternSettings.self, from: data) else { return .defaults }
        return value
    }

    public func save(_ value: PatternSettings) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.key) }
    }
}

/// The help level's fixed hint threshold (design §5.2): after the 1st miss's Think Pause at 多啲, after the 2nd at
/// 標準 and 少啲 (the `ActivityHintPolicy` count, unchanged). Fixed at deal; a change applies from the next round.
public enum PatternSortHelp {
    public static func hintThreshold(_ guidance: TapCountGuidanceLevel) -> Int {
        guidance == .more ? 1 : ActivityHintPolicy.missesBeforeAutoHint
    }

    /// Idle nudge 「試吓揀一個！」 (no light on the answer): 8 s at 多啲, 15 s at 標準, none at 少啲.
    public static func idleNudgeSeconds(_ guidance: TapCountGuidanceLevel) -> Double? {
        switch guidance {
        case .more: return 8
        case .standard: return 15
        case .less: return nil
        }
    }

    /// The stamp's 「蓋印！」, on the stamp's appearance and on its replay (astra R2): a 分類 card says it only with
    /// 分類設定's 廣東話語音 on; every other card keeps its own voice rules (true).
    public static func speaksStamp(_ kind: ActivityKind?, sortAudio: Bool) -> Bool {
        kind?.isSortFamily != true || sortAudio
    }
}
