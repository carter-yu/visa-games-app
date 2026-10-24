import Foundation

public struct LetterWord: Codable, Equatable, Sendable {
    public let id: String
    public let word: String
    public let tier: String
    public let imageID: String
    public let voiceKey: String
    public let glossZH: String
    public let highlight: [Int]
    public let anchor: Bool?
    enum CodingKeys: String, CodingKey {
        case id, word, tier, highlight, anchor
        case imageID = "image_id", voiceKey = "voice_key", glossZH = "gloss_zh"
    }
}

public struct LetterWordEntry: Codable, Sendable {
    public let status: String
    public let anchor: String
    public let words: [LetterWord]?
}

public struct LetterWordBank: Codable, Sendable {
    public let schema: String
    public let letters: [String: LetterWordEntry]

    public static func load(url: URL) throws -> Self {
        let bank = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard bank.schema == "visagames.tapLetter.wordBank.v1" else { throw BankError.invalidSchema }
        return bank
    }

    public static func loadBundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "starter-bank", withExtension: "json", subdirectory: "LetterTap") else {
            throw BankError.missingResource
        }
        return try load(url: url)
    }

    public enum BankError: Error { case invalidSchema, missingResource }

    /// A nil result means this letter has only an approved anchor and no two-word deck yet.
    public func deal(letter: String, box: LetterBox, seed: String, decks: inout LetterWordDecks,
                     now: Date) -> [LetterWord] {
        guard let entry = letters[letter], let all = entry.words else { return [] }
        let hidden = Set(decks.hiddenIDs[letter] ?? [])
        let pool = all.filter { !hidden.contains($0.id) && ($0.tier == "core" || box >= .practising) }
        guard pool.count >= 2 else { return [] }
        var deck = decks.letters[letter] ?? LetterWordDeck()
        let ids = Set(pool.map(\.id))
        deck.remaining = deck.remaining.filter { ids.contains($0) }
        var result: [LetterWord] = []
        if !deck.hasDealtAnchor, let anchor = pool.first(where: { $0.anchor == true }) {
            result.append(anchor)
            deck.hasDealtAnchor = true
            deck.lastID = anchor.id
            deck.seenIDs.append(anchor.id)
            deck.remaining.removeAll { $0 == anchor.id }
        }
        while result.count < 2 {
            let school = (decks.schoolWords[letter] ?? []).filter { $0.expiresAt > now && ids.contains($0.id) }
            let picked: String?
            if let id = school.map(\.id).first(where: { id in !result.contains(where: { $0.id == id }) && id != deck.lastID }) {
                picked = id
                deck.remaining.removeAll { $0 == id }
            } else {
                if deck.remaining.isEmpty {
                    var candidates = pool.map(\.id).filter { !deck.seenIDs.contains($0) }
                    if candidates.isEmpty { deck.seenIDs = []; candidates = pool.map(\.id) }
                    var rng = QuestionRNG(seed: seed, salt: "letter-words-\(letter)-\(deck.shuffleCount)")
                    deck.remaining = rng.shuffled(candidates)
                    deck.shuffleCount += 1
                    if deck.remaining.first == deck.lastID && deck.remaining.count > 1 { deck.remaining.swapAt(0, 1) }
                }
                if !deck.remaining.contains(where: { id in !result.contains(where: { $0.id == id }) }) {
                    var rng = QuestionRNG(seed: seed, salt: "letter-words-\(letter)-\(deck.shuffleCount)")
                    deck.seenIDs = []
                    deck.remaining = rng.shuffled(pool.map(\.id).filter { id in !result.contains(where: { $0.id == id }) })
                    deck.shuffleCount += 1
                }
                picked = deck.remaining.first(where: { id in !result.contains(where: { $0.id == id }) })
                if let picked { deck.remaining.removeAll { $0 == picked } }
            }
            guard let picked, let word = pool.first(where: { $0.id == picked }) else { break }
            result.append(word)
            deck.lastID = picked
            if !deck.seenIDs.contains(picked) { deck.seenIDs.append(picked) }
        }
        decks.letters[letter] = deck
        return result
    }
}

public struct SchoolWord: Codable, Equatable, Sendable {
    public let id: String
    public let expiresAt: Date
    public init(id: String, expiresAt: Date) { self.id = id; self.expiresAt = expiresAt }
}

public struct LetterWordDeck: Codable, Equatable, Sendable {
    public var remaining: [String] = []
    public var seenIDs: [String] = []
    public var lastID: String?
    public var hasDealtAnchor = false
    public var shuffleCount = 0
    public init() {}
}

public struct LetterWordDecks: Codable, Equatable, Sendable {
    public var letters: [String: LetterWordDeck] = [:]
    public var hiddenIDs: [String: [String]] = [:]
    public var schoolWords: [String: [SchoolWord]] = [:]
    public init() {}

    @discardableResult public mutating func hide(_ id: String, for letter: String, bank: LetterWordBank) -> Bool {
        guard let words = bank.letters[letter]?.words,
              words.contains(where: { $0.id == id }) else { return false }
        let remaining = words.filter { $0.id != id && !(hiddenIDs[letter] ?? []).contains($0.id) }
        guard remaining.count >= 2, remaining.filter({ $0.tier == "core" }).count >= 2 else { return false }
        var hidden = hiddenIDs[letter] ?? []
        if !hidden.contains(id) { hidden.append(id) }
        hiddenIDs[letter] = hidden
        return true
    }

    public mutating func feature(_ id: String, for letter: String, at date: Date) {
        var featured = schoolWords[letter] ?? []
        featured.removeAll { $0.id == id }
        featured.append(SchoolWord(id: id, expiresAt: date.addingTimeInterval(7 * 86_400)))
        schoolWords[letter] = featured
    }
}

public struct LetterWordDecksStore {
    public static let key = "VisaGames.letterWordDecks.v1"
    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() -> LetterWordDecks {
        guard let data = defaults.data(forKey: Self.key),
              let value = try? JSONDecoder().decode(LetterWordDecks.self, from: data) else { return LetterWordDecks() }
        return value
    }
    public func save(_ value: LetterWordDecks) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

public struct TapLetterDeal: Sendable {
    public let target: String
    public let lane: LetterLane
    public let board: LetterBoard
    public let words: [LetterWord]
    public let glyphScale: Double
    public let decks: LetterWordDecks
}

public enum TapLetterGenerator {
    public static func make(seed: String, n: Int, settings: TapLetterSettings, progress: LetterProgress,
                            decks: LetterWordDecks, bank: LetterWordBank, now: Date) -> TapLetterDeal? {
        let choice = LetterScheduler.next(seed: seed, n: n, settings: settings, progress: progress, now: now)
        let board = LetterBoardBuilder.make(seed: seed, target: choice.target, settings: settings, progress: progress)
        var nextDecks = decks
        let words = bank.deal(letter: choice.target, box: progress.state(for: choice.target).box,
                              seed: seed, decks: &nextDecks, now: now)
        guard words.count == 2 else { return nil }
        return TapLetterDeal(target: choice.target, lane: choice.lane, board: board, words: words,
                             glyphScale: board.letters.contains(where: { "gjpqy".contains($0) }) ? 0.5 : 0.55,
                             decks: nextDecks)
    }
}
