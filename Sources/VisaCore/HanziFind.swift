import Foundation

// Hanzi H2 finding core (0.38.0 / 83): design hanzi-tap v2 § ★ 搵字翻卡 and its child copy table. The 2 × 5 board's
// per-card state (the letter board's tap rules), what every card and collection slot shows, the find copy from
// the pack, and what follows the last find. Pure: `TapHanziBoardView` draws it and AppModel owns the clocks,
// the Think Pause, voice and saving. No write round (H3) and no parent card or report (H4).

// MARK: - Board

/// Per-card state for one 中文字 Find & flip deal. Pause and reward clocks stay with AppModel.
public struct TapHanziBoard: Equatable, Sendable {
    public let deal: HanziDeal
    public private(set) var found: Set<Int> = []
    public private(set) var knownWrong: Set<Int> = []
    public private(set) var misses = 0
    public private(set) var assisted = false
    public private(set) var tapOrder: [Int] = []
    public private(set) var lastTapAt: TimeInterval = -.infinity
    public private(set) var lastTapCard: Int? = nil

    /// Nil unless every state can be drawn from `pack`: each card's glyph has centre lines, and the target has
    /// a meaning and one cue picture with artwork per target card. A glyph never falls back to another glyph
    /// or to a font, so no card can lose it.
    public init?(deal: HanziDeal, pack: HanziPack) {
        let board = deal.board
        guard board.rows.count == 2, board.rows.allSatisfy({ $0.count == 5 }), board.targetCards.count == 2,
              board.cards.allSatisfy({ !HanziGlyphs.paths($0, in: pack).isEmpty }),
              let character = pack.characters[board.target], !character.meaning.zhHK.isEmpty,
              deal.cues.count == board.targetCards.count,
              deal.cues.allSatisfy({ character.cuePictures.contains($0) && HanziCueArt.picture($0) != nil }) else {
            return nil
        }
        self.deal = deal
    }

    public var target: String { deal.board.target }
    public var remaining: Int { max(0, deal.board.targetCards.count - found.count) }
    public var isComplete: Bool { remaining == 0 }
    public var hintCard: Int? { deal.board.targetCards.first { !found.contains($0) } }
    /// Found first try with no hint: the letter rule `HanziProgress.record` takes as `clean`.
    public var isClean: Bool { misses == 0 && !assisted }
    public func glyph(at card: Int) -> String? {
        deal.board.cards.indices.contains(card) ? deal.board.cards[card] : nil
    }

    public mutating func showHint() { assisted = true }

    /// `TapLetterBoard.tap`'s rules: the same card again within 0.4 s, a found card or a known-wrong card never adds
    /// a miss; only the first tap on each wrong card is one.
    public mutating func tap(_ card: Int, at time: TimeInterval) -> TapLetterTap {
        guard deal.board.cards.indices.contains(card), !isComplete else { return .ignored }
        if lastTapCard == card && time - lastTapAt < 0.4 { return .doubleTapIgnored }
        lastTapCard = card
        lastTapAt = time
        if found.contains(card) { return .foundRetap }
        if knownWrong.contains(card) { return .knownWrongRetap }
        tapOrder.append(card)
        if deal.board.targetCards.contains(card) {
            found.insert(card)
            return isComplete ? .allFound : .found
        }
        knownWrong.insert(card)
        misses += 1
        return .miss
    }

    /// What follows the last find (design: "Both found: brief plaque stroke reveal, then ★ stamp / ★★ write").
    public var finish: HanziFindFinish { deal.kind == .tapHanziWrite ? .awaitWriteRound : .stamp }
}

/// After both targets are found.
public enum HanziFindFinish: Equatable, Sendable {
    /// 翻字卡: the round is done and stamps.
    case stamp
    /// 搵完寫: the write round takes over. It is H3 (田字格); until then the find result is held and never stamped,
    /// and the kind stays out of `ActivityCatalog.playableKinds`.
    case awaitWriteRound
}

// MARK: - Faces and collection slots

/// A found target's flipped card: the cue picture, the target glyph and its meaning (design ★ 搵字翻卡).
public struct HanziFlipArt: Equatable, Sendable {
    public let glyph: String
    /// `HanziCueArt.picture` ID.
    public let picture: String
    /// HK Traditional; a hand picture names the child's own hand (D7 「我隻左手」).
    public let meaning: String

    public init(glyph: String, picture: String, meaning: String) {
        self.glyph = glyph
        self.picture = picture
        self.meaning = meaning
    }
}

/// What one card shows. Both cases carry the glyph, so every state draws it.
public enum HanziCardFace: Equatable, Sendable {
    /// Unopened: the glyph on the plain card. Every unopened card has the same background, colour and scale,
    /// with no picture, colour or frequency clue.
    case glyph(String)
    case flipped(HanziFlipArt)

    public var glyph: String {
        switch self {
        case .glyph(let glyph): return glyph
        case .flipped(let art): return art.glyph
        }
    }
}

extension TapHanziBoard {
    /// The face of `card` (row-major 0…9); nil off the board. A target card flips once found; the other target
    /// stays an unmarked glyph until it is found too.
    public func face(_ card: Int, pack: HanziPack) -> HanziCardFace? {
        guard let glyph = glyph(at: card) else { return nil }
        guard found.contains(card), let slot = deal.board.targetCards.firstIndex(of: card) else { return .glyph(glyph) }
        return .flipped(flipArt(slot: slot, pack: pack))
    }

    /// Collection slot 0 / 1 (the first / second target card): its flip art once that card is found, else nil.
    public func slot(_ index: Int, pack: HanziPack) -> HanziFlipArt? {
        guard deal.board.targetCards.indices.contains(index), found.contains(deal.board.targetCards[index]) else {
            return nil
        }
        return flipArt(slot: index, pack: pack)
    }

    private func flipArt(slot: Int, pack: HanziPack) -> HanziFlipArt {
        let character = pack.characters[target]
        let meaning = character?.meaningCue?.zhHK ?? character?.meaning.zhHK ?? ""
        return HanziFlipArt(glyph: target, picture: deal.cues[slot], meaning: meaning)
    }
}

// MARK: - Copy

/// The finding lines from the pack's child copy (design child copy table), with `{H}` (target), `{Y}` (tapped
/// glyph) and `{MEANING_ZH}` filled. HK Traditional `zhHK` is shown and, only with audio on, spoken; `en` is the
/// engineering English for logs. Jyutping and voice keys stay separate pack fields.
public struct HanziFindCopy: Equatable, Sendable {
    /// Every line the find board shows; a pack missing one, or a template without its placeholder, gives no copy.
    public static let keys: [String: [String]] = [
        "prompt": ["{H}"], "header": ["{H}"], "findSubline": [], "findAgain": ["{H}"], "idle": ["{H}"],
        "remainingOne": [], "allFound": [], "wrong": ["{Y}"], "hint": ["{H}"], "foundPair": ["{H}", "{MEANING_ZH}"]
    ]

    private let lines: [String: HanziText]

    public init?(pack: HanziPack) {
        var lines: [String: HanziText] = [:]
        for (key, placeholders) in Self.keys {
            guard let line = pack.copy[key], !line.zhHK.isEmpty,
                  placeholders.allSatisfy({ line.zhHK.components(separatedBy: $0).count == 2 }) else { return nil }
            lines[key] = line
        }
        self.lines = lines
    }

    private func zh(_ key: String, _ fill: [String: String] = [:]) -> String {
        fill.reduce(lines[key]?.zhHK ?? "") { $0.replacingOccurrences(of: $1.key, with: $1.value) }
    }

    /// 「搵晒『上』！點晒兩張。」 — the reprompt line.
    public func prompt(_ glyph: String) -> String { zh("prompt", ["{H}": glyph]) }
    /// 「搵晒『上』！」
    public func header(_ glyph: String) -> String { zh("header", ["{H}": glyph]) }
    /// The header around its glyph, so the view can draw the glyph from its centre lines: 「搵晒『」, 「』！」.
    public var headerParts: (before: String, after: String) {
        let parts = zh("header").components(separatedBy: "{H}")
        return (parts.first ?? "", parts.count > 1 ? parts[1] : "")
    }
    /// 「點晒兩張。」
    public var subline: String { zh("findSubline") }
    /// 「再搵『上』！」 after a Think Pause.
    public func findAgain(_ glyph: String) -> String { zh("findAgain", ["{H}": glyph]) }
    /// 「搵『上』！」 after ten idle seconds.
    public func idle(_ glyph: String) -> String { zh("idle", ["{H}": glyph]) }
    /// The tray: two to find → 「點晒兩張。」, one → 「仲有一張」, none → 「搵晒喇！」.
    public func remaining(_ count: Int) -> String {
        count <= 0 ? zh("allFound") : count == 1 ? zh("remainingOne") : zh("findSubline")
    }
    /// 「嗰個係『右』。」 for a wrong card, a first miss or a known-wrong retap.
    public func wrong(_ tapped: String) -> String { zh("wrong", ["{Y}": tapped]) }
    /// 「呢張係『上』！」 with the hint ring, after a second miss.
    public func hint(_ glyph: String) -> String { zh("hint", ["{H}": glyph]) }
    /// 「『上』，上面！」 on a flip, with the target's pack meaning.
    public func foundPair(_ glyph: String, pack: HanziPack) -> String {
        zh("foundPair", ["{H}": glyph, "{MEANING_ZH}": pack.characters[glyph]?.meaning.zhHK ?? ""])
    }
    /// 「搵晒喇！」
    public var allFound: String { zh("allFound") }
}
