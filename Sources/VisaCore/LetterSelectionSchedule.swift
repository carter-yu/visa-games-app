import Foundation

/// V2 scheduling state is separate from the legacy weekDeals array and from parent drafts.
public struct LetterSelectionSchedule: Codable, Equatable, Sendable {
    public var completedChildRounds = 0
    public var focusBags: [String: [String]] = [:]
    public var signatures: [String: String] = [:]
    public var cycles: [String: Int] = [:]
    public var reviewOpportunityUsedAtCompleted: Int?
    public init() {}

    public mutating func completedChildRound() { completedChildRounds += 1 }

    public mutating func next(seed: String, kind: ActivityKind, n: Int,
                              settings: LetterSelectionSettings, availability: [String: LetterCapability],
                              progress: LetterProgress, now: Date) -> LetterChoice? {
        let focus = settings.focus(for: kind, availability: availability)
        guard !focus.isEmpty else { return nil }
        let review = settings.review(for: kind, availability: availability)
        let key = kind.rawValue
        let order = settings.focusOrder.filter { focus.contains($0) } + focus.filter { !settings.focusOrder.contains($0) }
        let signature = focus.sorted().joined() + "|" + order.joined()
        if signatures[key] != signature {
            signatures[key] = signature; focusBags[key] = []; cycles[key] = 0
        }
        func due(_ letter: String) -> Bool {
            let state = progress.state(for: letter)
            let days = state.box == .known ? 7 : state.box == .practising ? 2 : 0
            return now.timeIntervalSince(state.lastSeen ?? .distantPast) >= Double(days * 86_400)
        }
        func retry(in pool: [String]) -> String? {
            let possible = progress.retryQueue.filter { $0.dueRound <= n && pool.contains($0.letter) && due($0.letter) }
                .sorted { $0.dueRound == $1.dueRound ? $0.letter < $1.letter : $0.dueRound < $1.dueRound }
            return (possible.first { $0.letter != progress.lastTarget } ?? possible.first)?.letter
        }
        if settings.reviewEvery == 4 && completedChildRounds % 4 == 3 &&
            reviewOpportunityUsedAtCompleted != completedChildRounds {
            reviewOpportunityUsedAtCompleted = completedChildRounds
            if let letter = retry(in: review) { return LetterChoice(target: letter, lane: .review) }
            let eligible = review.filter(due).sorted { lhs, rhs in
                let a = progress.state(for: lhs), b = progress.state(for: rhs)
                if a.box != b.box { return a.box < b.box }
                if a.lastSeen != b.lastSeen { return (a.lastSeen ?? .distantPast) < (b.lastSeen ?? .distantPast) }
                return lhs < rhs
            }
            if let letter = (eligible.first { $0 != progress.lastTarget } ?? eligible.first) {
                return LetterChoice(target: letter, lane: .review)
            }
        }
        if let letter = retry(in: focus) { return LetterChoice(target: letter, lane: .retry) }
        var bag = focusBags[key] ?? []
        if bag.isEmpty {
            let cycle = cycles[key] ?? 0
            if cycle == 0 { bag = order }
            else {
                var rng = QuestionRNG(seed: seed, salt: "letter-focus-\(key)-\(signature)-\(cycle)")
                bag = rng.shuffled(order)
            }
            cycles[key] = cycle + 1
        }
        if let first = bag.first, first == progress.lastTarget, bag.count > 1,
           let alternative = bag.firstIndex(where: { $0 != progress.lastTarget }) {
            bag.swapAt(0, alternative)
        }
        let target = bag.removeFirst()
        focusBags[key] = bag
        return LetterChoice(target: target, lane: .week)
    }
}

public struct LetterSelectionScheduleStore {
    public static let key = "VisaGames.letterSelectionSchedule.v2"
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> LetterSelectionSchedule {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(LetterSelectionSchedule.self, from: data) else { return .init() }
        return value
    }
    public func save(_ value: LetterSelectionSchedule) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.key) }
    }
}
