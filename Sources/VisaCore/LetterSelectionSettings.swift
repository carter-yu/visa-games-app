import Foundation

/// V2 parent intent. Legacy settings and learning stores are never rewritten by this store.
public struct LetterSelectionSettings: Codable, Equatable, Sendable {
    public var schemaVersion = 2
    public var focusLetters: [String]
    public var focusOrder: [String]
    public var reviewEvery: Int
    public var reviewLetters: [String]
    public var mirrorGuard: Bool
    public var writingStyle: String
    public var source: String
    public var legacyPath: LetterPath
    public var revision: Int
    public var savedAt: Date

    public init(focusLetters: [String] = Array("abcde").map(String.init),
                focusOrder: [String] = Array("abcde").map(String.init), reviewEvery: Int = 0,
                reviewLetters: [String] = [], mirrorGuard: Bool = true, writingStyle: String = "lwt",
                source: String = "custom", legacyPath: LetterPath = .abc,
                revision: Int = 0, savedAt: Date = .distantPast) {
        self.focusLetters = focusLetters; self.focusOrder = focusOrder
        self.reviewEvery = reviewEvery; self.reviewLetters = reviewLetters
        self.mirrorGuard = mirrorGuard; self.writingStyle = writingStyle
        self.source = source; self.legacyPath = legacyPath
        self.revision = revision; self.savedAt = savedAt
    }

    public static let defaults = Self()

    public enum ValidationError: Error, Equatable {
        case emptyFocus, tooMany, invalidLetter, unavailableFocus, noWriteTargets, insufficientBoardLetters
        case invalidReview, invalidOrder, invalidSchema
    }

    public static func isASCII(_ token: String) -> Bool {
        token.utf8.count == 1 && token.utf8.first.map { (97...122).contains($0) } == true
    }

    public static func canonical(_ values: [String]) throws -> [String] {
        guard !values.isEmpty else { throw ValidationError.emptyFocus }
        guard values.allSatisfy(isASCII) else { throw ValidationError.invalidLetter }
        let result = Array(Set(values)).sorted()
        guard result.count <= 26 else { throw ValidationError.tooMany }
        return result
    }

    public func focus(for kind: ActivityKind, availability: [String: LetterCapability]) -> [String] {
        focusLetters.filter { kind == .tapLetterWrite ? availability[$0]?.canWrite == true : availability[$0]?.canFind == true }
    }

    public func review(for kind: ActivityKind, availability: [String: LetterCapability]) -> [String] {
        guard reviewEvery == 4 else { return [] }
        return reviewLetters.filter { !focusLetters.contains($0) &&
            (kind == .tapLetterWrite ? availability[$0]?.canWrite == true : availability[$0]?.canFind == true) }
    }

    public func validated(availability: [String: LetterCapability], writingAssigned: Bool,
                          allowedReview: Set<String>? = nil) throws -> Self {
        var next = self
        guard schemaVersion == 2 else { throw ValidationError.invalidSchema }
        next.focusLetters = try Self.canonical(focusLetters)
        guard next.focusLetters.allSatisfy({ availability[$0]?.canFind == true }) else {
            throw ValidationError.unavailableFocus
        }
        let legal = availability.filter { $0.value.canFind }.map(\.key)
        guard next.focusLetters.allSatisfy({ LetterBoardBuilder.makeScoped(seed: "validation", target: $0,
            mirrorGuard: mirrorGuard, progress: .init(), legalLetters: legal) != nil }) else {
            throw ValidationError.insufficientBoardLetters
        }
        if writingAssigned && next.focus(for: .tapLetterWrite, availability: availability).isEmpty {
            throw ValidationError.noWriteTargets
        }
        guard reviewEvery == 0 || reviewEvery == 4 else { throw ValidationError.invalidReview }
        guard reviewLetters.allSatisfy(Self.isASCII) else { throw ValidationError.invalidReview }
        next.reviewLetters = Array(Set(reviewLetters)).sorted()
        guard (reviewEvery == 0 ? next.reviewLetters.isEmpty : !next.reviewLetters.isEmpty) else {
            throw ValidationError.invalidReview
        }
        guard Set(next.reviewLetters).isDisjoint(with: next.focusLetters),
              next.reviewLetters.allSatisfy({ availability[$0]?.canFind == true }) else {
            throw ValidationError.invalidReview
        }
        guard next.reviewLetters.allSatisfy({ LetterBoardBuilder.makeScoped(seed: "validation", target: $0,
            mirrorGuard: mirrorGuard, progress: .init(), legalLetters: legal) != nil }) else {
            throw ValidationError.insufficientBoardLetters
        }
        if reviewEvery == 4 {
            guard let allowedReview, Set(next.reviewLetters).isSubset(of: allowedReview) else {
                throw ValidationError.invalidReview
            }
        }
        if Set(focusOrder) == Set(next.focusLetters) && focusOrder.count == next.focusLetters.count {
            next.focusOrder = focusOrder
        } else { next.focusOrder = next.focusLetters }
        return next
    }
}

public enum LetterSelectionLoad: Equatable {
    case fresh
    case legacy(LetterSelectionSettings, Int)
    case repairV1
    case saved(LetterSelectionSettings)
    case corruptV2

    public var effective: LetterSelectionSettings? {
        switch self {
        case .fresh: return .defaults
        case .legacy(let value, _), .saved(let value): return value
        case .repairV1: return .defaults
        case .corruptV2: return nil
        }
    }
}

public struct LetterSelectionSettingsStore {
    public static let key = "VisaGames.tapLetterSettings.v2"
    public static let corruptBackupKey = "VisaGames.tapLetterSettings.v2.corruptBackup"
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }

    public func load() -> LetterSelectionLoad {
        if defaults.object(forKey: Self.key) != nil {
            guard let data = defaults.data(forKey: Self.key),
                  var value = try? decoder().decode(LetterSelectionSettings.self, from: data),
                  value.schemaVersion == 2,
                  let focus = try? LetterSelectionSettings.canonical(value.focusLetters),
                  value.focusOrder.allSatisfy(LetterSelectionSettings.isASCII),
                  value.reviewLetters.allSatisfy(LetterSelectionSettings.isASCII),
                  value.reviewEvery == 0 || value.reviewEvery == 4,
                  (value.reviewEvery == 0) == value.reviewLetters.isEmpty,
                  Set(value.focusLetters).isDisjoint(with: value.reviewLetters) else { return .corruptV2 }
            value.focusLetters = focus
            value.reviewLetters = Array(Set(value.reviewLetters)).sorted()
            if Set(value.focusOrder) != Set(focus) || value.focusOrder.count != focus.count {
                value.focusOrder = focus
            }
            return .saved(value)
        }
        guard defaults.object(forKey: TapLetterSettingsStore.key) != nil else { return .fresh }
        guard let data = defaults.data(forKey: TapLetterSettingsStore.key),
              let old = try? JSONDecoder().decode(TapLetterSettings.self, from: data) else { return .repairV1 }
        let focus = old.validWeek
        let ordered = old.path.order.filter { focus.contains($0) } + focus.filter { !old.path.order.contains($0) }
        let draft = LetterSelectionSettings(focusLetters: focus.sorted(), focusOrder: ordered,
            mirrorGuard: old.mirrorGuard, writingStyle: old.writingStyle,
            source: "legacy", legacyPath: old.path)
        return .legacy(draft, old.reviewEvery)
    }

    public enum StoreError: Error, Equatable { case notParent, corruptStored, writeFailed }

    /// Only an explicit parent Save calls this. A no-op never writes or changes revision.
    public func save(_ draft: LetterSelectionSettings, availability: [String: LetterCapability],
                     writingAssigned: Bool, allowedReview: Set<String>? = nil,
                     at date: Date, repairCorruptV2: Bool = false) throws -> LetterSelectionSettings {
        let prior = load()
        if prior == .corruptV2 && !repairCorruptV2 { throw StoreError.corruptStored }
        var permittedReview = allowedReview ?? []
        if case .saved(let old) = prior { permittedReview.formUnion(old.reviewLetters) }
        var next = try draft.validated(availability: availability, writingAssigned: writingAssigned,
                                       allowedReview: permittedReview)
        if let effective = prior.effective {
            next.writingStyle = effective.writingStyle
            next.legacyPath = effective.legacyPath
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        var canonicalRewrite = false
        if case .saved(let old) = prior {
            var comparable = next
            comparable.revision = old.revision; comparable.savedAt = old.savedAt
            if comparable == old {
                let canonical: Data
                do { canonical = try encoder.encode(old) }
                catch { throw StoreError.writeFailed }
                if defaults.data(forKey: Self.key) == canonical { return old }
                next = old
                canonicalRewrite = true
            } else { next.revision = old.revision + 1 }
        } else { next.revision = 1 }
        if !canonicalRewrite { next.savedAt = date }
        let data: Data
        do { data = try encoder.encode(next) }
        catch { throw StoreError.writeFailed }
        let previousData = defaults.data(forKey: Self.key)
        if prior == .corruptV2, let previousObject = defaults.object(forKey: Self.key) {
            defaults.set(previousObject, forKey: Self.corruptBackupKey)
            guard defaults.object(forKey: Self.corruptBackupKey) != nil else { throw StoreError.writeFailed }
        }
        defaults.set(data, forKey: Self.key)
        guard defaults.data(forKey: Self.key) == data,
              case .saved(let readback) = load() else {
            if let previousData { defaults.set(previousData, forKey: Self.key) }
            else { defaults.removeObject(forKey: Self.key) }
            throw StoreError.writeFailed
        }
        return readback
    }
}
