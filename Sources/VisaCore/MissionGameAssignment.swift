import Foundation

/// Which mission tickets (★1 / ★2 / ★3) may deal each built activity.
///
/// Stars are visa length. Since v0.22.0 (D1, ADR 0009) they are also the question tier for
/// generated kinds (`QuestionGeneration.generatedKinds`): ★ = L1, ★★ = L2, ★★★ = L3.
/// A kind may be on several stars.
/// The last on-kind for a star cannot be turned off — the child ticket must always
/// have a deal. A kind with every star off stays in the parent catalog (playtest)
/// but is omitted from that star's pool.
///
/// Persistence is UserDefaults beside the video allowlist, **not** the reward
/// `Snapshot`. `AppModel.resetStorage` must not clear this map. Missing store,
/// corrupt JSON, or an empty on-set for a star → the default-on kinds (today's deal).
/// A kind the store has never seen joins all three stars (opt-out), except the D7
/// default-off kinds (`ActivityCatalog.defaultOffKinds`, v0.24.1 連一連 three cards), which join no star
/// until a parent turns one on.
public struct MissionGameAssignment: Equatable, Sendable {
    /// Stars that are ON. A missing key means "never stored" → all stars on.
    /// An empty set means the parent hid this game from every mission.
    public var enabledStars: [ActivityKind: Set<ChildDifficulty>]

    public init(enabledStars: [ActivityKind: Set<ChildDifficulty>] = [:]) {
        self.enabledStars = enabledStars
    }

    /// Fresh install: every default-on kind on all three stars, D7 default-off kinds on none.
    public static var defaults: MissionGameAssignment {
        let pairs = ActivityCatalog.playableKinds.map { ($0, defaultStars(for: $0)) }
        return MissionGameAssignment(enabledStars: Dictionary(uniqueKeysWithValues: pairs))
    }

    /// Stars a kind has before the parent changes it (D7: none for default-off kinds).
    public static func defaultStars(for kind: ActivityKind) -> Set<ChildDifficulty> {
        ActivityCatalog.defaultOffKinds.contains(kind) ? [] : Set(ChildDifficulty.allCases)
    }

    public static let emptyTierBanner =
        "每個星級至少要有一個遊戲 / Each star needs at least one game"

    /// Fill unseen playable kinds with their default stars (all three; none for D7 kinds).
    /// Drop unknown keys.
    public func normalized() -> MissionGameAssignment {
        var next = self
        for kind in ActivityCatalog.playableKinds where next.enabledStars[kind] == nil {
            next.enabledStars[kind] = Self.defaultStars(for: kind)
        }
        next.enabledStars = next.enabledStars.filter { ActivityCatalog.playableKinds.contains($0.key) }
        return next
    }

    public func isEnabled(_ kind: ActivityKind, star: ChildDifficulty) -> Bool {
        let stars = enabledStars[kind] ?? Self.defaultStars(for: kind)
        return stars.contains(star)
    }

    /// All three stars off — hidden from missions, still playtestable.
    public func isHiddenFromMissions(_ kind: ActivityKind) -> Bool {
        ChildDifficulty.allCases.allSatisfy { !isEnabled(kind, star: $0) }
    }

    /// Kinds this ticket may deal, in catalog order. Empty on-set → the default-on kinds.
    public func pool(for star: ChildDifficulty) -> [ActivityKind] {
        let on = ActivityCatalog.playableKinds.filter { isEnabled($0, star: star) }
        return on.isEmpty ? ActivityCatalog.defaultOnKinds : on
    }

    public enum ToggleOutcome: Equatable {
        case updated(MissionGameAssignment)
        case rejectedLastStar
    }

    /// Toggle one star on one kind. Turning a star on does not clear the others.
    public func toggling(_ kind: ActivityKind, star: ChildDifficulty) -> ToggleOutcome {
        guard ActivityCatalog.playableKinds.contains(kind) else { return .rejectedLastStar }
        var next = normalized()
        var set = next.enabledStars[kind] ?? Self.defaultStars(for: kind)
        if set.contains(star) {
            let othersOn = ActivityCatalog.playableKinds.contains { other in
                other != kind && next.isEnabled(other, star: star)
            }
            if !othersOn { return .rejectedLastStar }
            set.remove(star)
        } else {
            set.insert(star)
        }
        next.enabledStars[kind] = set
        return .updated(next)
    }
}

/// UserDefaults store beside `VideoAllowlistStore`. Not the reward snapshot.
public struct MissionGameAssignmentStore {
    public static let key = "VisaGames.missionGameAssignment.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> MissionGameAssignment {
        guard let data = defaults.data(forKey: Self.key) else { return .defaults }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return .defaults }
        return payload.assignment.normalized()
    }

    public func save(_ assignment: MissionGameAssignment) {
        let payload = Payload(assignment: assignment.normalized())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private struct Payload: Codable {
        var starsByKind: [String: [Int]]

        init(assignment: MissionGameAssignment) {
            var map: [String: [Int]] = [:]
            for (kind, stars) in assignment.enabledStars {
                map[kind.rawValue] = stars.map(\.rawValue).sorted()
            }
            starsByKind = map
        }

        var assignment: MissionGameAssignment {
            var enabled: [ActivityKind: Set<ChildDifficulty>] = [:]
            for (raw, values) in starsByKind {
                guard let kind = ActivityKind(rawValue: raw) else { continue }
                enabled[kind] = Set(values.compactMap { ChildDifficulty(rawValue: $0) })
            }
            return MissionGameAssignment(enabledStars: enabled)
        }
    }
}
