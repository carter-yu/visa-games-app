import Foundation

public enum LetterPath: String, Codable, CaseIterable, Sendable {
    case abc, jolly, lettersAndSounds, custom

    public var groups: [[String]] {
        let groups: [String]
        switch self {
        case .abc: groups = ["abcde", "fghij", "klmno", "pqrst", "uvwxyz"]
        case .jolly: groups = ["satipn", "ckehrmd", "goulfb", "jzwvyxq"]
        case .lettersAndSounds: groups = ["satp", "inmd", "gock", "eur", "hbfl", "jvwx", "yzq"]
        case .custom: groups = []
        }
        return groups.map { $0.map(String.init) }
    }

    public var order: [String] { groups.flatMap { $0 } }
}

public struct TapLetterSettings: Codable, Equatable, Sendable {
    public var thisWeek: [String]
    public var path: LetterPath
    public var reviewEvery: Int
    public var mirrorGuard: Bool
    public var writingStyle: String

    public init(thisWeek: [String] = Array("abcde").map(String.init), path: LetterPath = .abc,
                reviewEvery: Int = 4, mirrorGuard: Bool = true, writingStyle: String = "lwt") {
        self.thisWeek = thisWeek
        self.path = path
        self.reviewEvery = reviewEvery
        self.mirrorGuard = mirrorGuard
        self.writingStyle = writingStyle
    }

    public static let defaults = Self()
    public var validWeek: [String] {
        let letters = thisWeek.filter { $0.count == 1 && $0.first?.isASCII == true && $0.first?.isLowercase == true }
        var unique: [String] = []
        for letter in letters where !unique.contains(letter) { unique.append(letter) }
        return Array(unique.prefix(7)).isEmpty ? Self.defaults.thisWeek : Array(unique.prefix(7))
    }
}

public struct TapLetterSettingsStore {
    public static let key = "VisaGames.tapLetterSettings.v1"
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> TapLetterSettings {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(TapLetterSettings.self, from: data) else { return .defaults }
        return value
    }
    public func save(_ value: TapLetterSettings) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

public enum LetterBox: String, Codable, Sendable, Comparable {
    case learning, practising, known
    public static func < (lhs: Self, rhs: Self) -> Bool {
        let ranks: [Self: Int] = [.learning: 0, .practising: 1, .known: 2]
        return ranks[lhs, default: 0] < ranks[rhs, default: 0]
    }
}

public struct LetterState: Codable, Equatable, Sendable {
    public var box: LetterBox = .learning
    public var lastSeen: Date?
    public var cleanRounds = 0
    public var firstCleanDay: Date?
    public var hasTargetRound = false
    public init() {}
}

public struct LetterRetry: Codable, Equatable, Sendable {
    public let letter: String
    public let dueRound: Int
    public init(letter: String, dueRound: Int) { self.letter = letter; self.dueRound = dueRound }
}

public struct LetterProgress: Codable, Equatable, Sendable {
    public var letters: [String: LetterState] = [:]
    public var retryQueue: [LetterRetry] = []
    public var lastTarget: String?
    public var weekDeals: [String] = []
    public init() {}
    public func state(for letter: String) -> LetterState { letters[letter] ?? LetterState() }

    public mutating func record(_ letter: String, clean: Bool, round: Int, at date: Date, lane: LetterLane = .week) {
        var state = state(for: letter)
        state.hasTargetRound = true
        state.lastSeen = date
        if clean {
            state.cleanRounds += 1
            if state.firstCleanDay == nil { state.firstCleanDay = date }
            if state.cleanRounds >= 3, let first = state.firstCleanDay,
               !Calendar(identifier: .gregorian).isDate(first, inSameDayAs: date) { state.box = .known }
            else if state.cleanRounds >= 2 { state.box = .practising }
        } else {
            state.cleanRounds = 0
            state.firstCleanDay = nil
            state.box = .learning
            retryQueue.append(LetterRetry(letter: letter, dueRound: round + 3))
        }
        letters[letter] = state
        lastTarget = letter
        retryQueue.removeAll { $0.letter == letter && $0.dueRound <= round }
        if lane == .week { weekDeals.append(letter) }
    }
}

public struct LetterProgressStore {
    public static let key = "VisaGames.letterProgress.v1"
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> LetterProgress {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(LetterProgress.self, from: data) else { return LetterProgress() }
        return value
    }
    public func save(_ value: LetterProgress) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

public enum LetterLane: String, Codable, Sendable { case review, retry, week }
public struct LetterChoice: Equatable, Sendable {
    public let target: String
    public let lane: LetterLane
}

public enum LetterScheduler {
    public static func next(seed: String, n: Int, settings: TapLetterSettings,
                            progress: LetterProgress, now: Date) -> LetterChoice {
        let week = settings.validWeek
        let old = progress.letters.filter { !week.contains($0.key) && $0.value.hasTargetRound &&
            now.timeIntervalSince($0.value.lastSeen ?? now) >= ($0.value.box == .known ? 7 : $0.value.box == .practising ? 2 : 0) * 86_400 }
        if settings.reviewEvery > 0 && n % settings.reviewEvery == 0 {
            let ordered = old.sorted { lhs, rhs in
                if lhs.value.box != rhs.value.box { return lhs.value.box < rhs.value.box }
                if lhs.value.lastSeen != rhs.value.lastSeen { return (lhs.value.lastSeen ?? .distantPast) < (rhs.value.lastSeen ?? .distantPast) }
                return (settings.path.order.firstIndex(of: lhs.key) ?? 99) < (settings.path.order.firstIndex(of: rhs.key) ?? 99)
            }
            if let letter = ordered.first(where: { $0.key != progress.lastTarget })?.key {
                return LetterChoice(target: letter, lane: .review)
            }
        }
        if let retry = progress.retryQueue.filter({ $0.dueRound <= n && $0.letter != progress.lastTarget })
            .sorted(by: { $0.dueRound < $1.dueRound }).first {
            return LetterChoice(target: retry.letter, lane: .retry)
        }
        let count = progress.weekDeals.count
        let cycle = count / week.count
        let used = Set(progress.weekDeals.suffix(count % week.count))
        let order: [String]
        if cycle == 0 { order = settings.path.order.filter { week.contains($0) } + week.filter { !settings.path.order.contains($0) } }
        else {
            var rng = QuestionRNG(seed: seed, salt: "letter-week-\(cycle)")
            order = rng.shuffled(week)
        }
        let available = order.filter { !used.contains($0) }
        let target = available.first(where: { $0 != progress.lastTarget }) ?? available.first ?? week[0]
        return LetterChoice(target: target, lane: .week)
    }
}

public struct LetterBoard: Equatable, Sendable {
    public let target: String
    public let letters: [String]
    public let rows: [[String]]
    public var targetCards: [Int] { rows.enumerated().compactMap { row, cells in cells.firstIndex(of: target).map { row * 5 + $0 } } }
}

public enum LetterBoardBuilder {
    private static let partners: [String: String] = ["b":"dpq", "d":"bpq", "p":"qbd", "q":"pbd", "n":"u", "u":"n", "m":"w", "w":"m"]
    public static func make(seed: String, target: String, settings: TapLetterSettings,
                            progress: LetterProgress) -> LetterBoard {
        let blocked = settings.mirrorGuard && progress.state(for: target).cleanRounds == 0
            ? Set((partners[target] ?? "").map(String.init)) : []
        var letters = [target]
        func add(_ values: [String]) {
            for value in values where letters.count < 5 && value != target && !letters.contains(value) && !blocked.contains(value) {
                letters.append(value)
            }
        }
        let week = settings.validWeek
        let confusables = ["b":"dpqa", "d":"bpqac", "c":"oeadb", "n":"umhr", "u":"nv"]
        if !week.contains(target) {
            let previous = progress.letters.filter { !week.contains($0.key) && $0.value.hasTargetRound }
                .sorted { ($0.value.lastSeen ?? .distantPast) > ($1.value.lastSeen ?? .distantPast) }.map(\.key)
            add((confusables[target] ?? "").map(String.init).filter { previous.contains($0) })
        }
        if week.count > 5 {
            add((confusables[target] ?? "").map(String.init).filter { week.contains($0) })
            var selection = QuestionRNG(seed: seed, salt: "letter-board-set-\(progress.weekDeals.count / week.count)")
            add(selection.shuffled(week))
        } else { add(week) }
        let old = progress.letters.filter { !week.contains($0.key) && $0.value.hasTargetRound }
            .sorted { ($0.value.lastSeen ?? .distantPast) > ($1.value.lastSeen ?? .distantPast) }.map(\.key)
        add(old)
        add((confusables[target] ?? "").map(String.init).filter { progress.state(for: $0).box >= .practising && progress.state(for: $0).hasTargetRound })
        add(settings.path.order)
        add(Array("abcdefghijklmnopqrstuvwxyz").map(String.init))
        var rng = QuestionRNG(seed: seed, salt: "letter-board-\(target)")
        func valid(_ rows: [[String]]) -> Bool {
            rows[0] != rows[1] && rows[0].firstIndex(of: target) != rows[1].firstIndex(of: target) &&
            !rows.contains(Array("abcde").map(String.init)) && !rows.contains(Array("edcba").map(String.init)) &&
            !rows.contains(letters) && !rows.contains(Array(letters.reversed()))
        }
        for _ in 0..<50 {
            let rows = [rng.shuffled(letters), rng.shuffled(letters)]
            if valid(rows) { return LetterBoard(target: target, letters: letters, rows: rows) }
        }
        let first = [letters[2], letters[4], letters[0], letters[3], letters[1]]
        for shift in 1..<5 {
            let second = Array(first.suffix(shift)) + Array(first.prefix(5 - shift))
            if valid([first, second]) { return LetterBoard(target: target, letters: letters, rows: [first, second]) }
        }
        return LetterBoard(target: target, letters: letters, rows: [first, [first[1], first[2], first[3], first[4], first[0]]])
    }
}
