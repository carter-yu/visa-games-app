import Foundation

// patterns-sorting P0 (design §5.4, T14): a spoken sequence (a line, or a row word that lights its item), the one
// engine it plays on, its silent timing and deadline, and the cursor that follows it. The app's `speakSequence` (P1)
// feeds the cursor; every event carries the deal and the speech generation, and an old one does nothing.

public enum ReadThroughUnitKind: String, Sendable, Equatable {
    /// A row word (0.8 s on the silent beat).
    case word
    /// A whole line (1.6 s on the silent beat).
    case line
}

/// One unit of a sequence: its clip key, the words spoken, and the item it lights (nil: no light).
public struct ReadThroughUnit: Sendable, Equatable {
    public let key: String
    public let text: String
    public let kind: ReadThroughUnitKind
    public let light: Int?

    public init(key: String, text: String, kind: ReadThroughUnitKind, light: Int? = nil) {
        self.key = key
        self.text = text
        self.kind = kind
        self.light = light
    }
}

/// Chosen once per sequence; a sequence never mixes engines.
public enum ReadThroughEngine: String, Sendable, Equatable, CaseIterable {
    case clips
    case systemVoice = "system_voice"
    case silentBeat = "silent_beat"

    /// Voice switch off → silent beat; every unit has a clip → clips; otherwise a zh-HK / yue-HK voice → system voice;
    /// otherwise → silent beat. So recordings for only some units, with no Cantonese voice, give the silent beat, never a
    /// half-spoken row.
    public static func choose(voiceOn: Bool, units: [ReadThroughUnit], hasClip: (String) -> Bool,
                              cantoneseVoice: Bool) -> ReadThroughEngine {
        guard voiceOn, !units.isEmpty else { return .silentBeat }
        if units.allSatisfy({ hasClip($0.key) }) { return .clips }
        return cantoneseVoice ? .systemVoice : .silentBeat
    }
}

/// A sequence's deadline (silent length + 4 s), in order (astra R2): stop the speaker's sequence only while it is still
/// this one — the same deal and generation — so an overlong clip or utterance stops while a newer sequence, the other
/// lane's or none keeps playing; then end the cursor and the reveal (once; held outside the lock).
public enum ReadThroughDeadline {
    public static func stopsSpeech(currentDeal: String?, currentGeneration: Int?, deal: String, generation: Int) -> Bool {
        currentDeal == deal && currentGeneration == generation
    }
}

/// The clips engine, all or nothing (astra R1): every unit's clip is loaded before any plays. Unit i's clip starts item
/// i and the end follows the last clip; one clip that does not load (or start) sends the whole sequence to the engine
/// `choose` picks with no clips. So no unit takes another's index and no end comes before every unit has played.
public enum ReadThroughClipPlan: Equatable, Sendable {
    /// Unit i starts `starts[i]` seconds from now; the sequence ends `end` seconds from now.
    case clips(starts: [TimeInterval], end: TimeInterval)
    case fallback(ReadThroughEngine)

    /// The clip queue's gap after each clip.
    public static let gap: TimeInterval = 0.1

    /// `durations[i]`: unit i's clip length in seconds, nil when it did not load.
    public static func plan(durations: [TimeInterval?], units: [ReadThroughUnit], cantoneseVoice: Bool) -> ReadThroughClipPlan {
        guard !units.isEmpty, durations.count == units.count, durations.allSatisfy({ $0 != nil }) else {
            return .fallback(ReadThroughEngine.choose(voiceOn: true, units: units, hasClip: { _ in false },
                                                      cantoneseVoice: cantoneseVoice))
        }
        var starts: [TimeInterval] = []
        var at: TimeInterval = 0
        for duration in durations {
            starts.append(at)
            at += (duration ?? 0) + gap
        }
        return .clips(starts: starts, end: at)
    }
}

/// The silent beat: 0.8 s per row word, 1.6 s per line, at least 2.4 s (the 中文字 find's minimum finish delay).
public enum ReadThroughTiming {
    public static let wordBeat: TimeInterval = 0.8
    public static let lineBeat: TimeInterval = 1.6
    public static let minimum: TimeInterval = 2.4
    /// Every sequence ends by its silent length + 4 s, even if no end event ever arrives.
    public static let deadlineSlack: TimeInterval = 4

    public static func beat(_ unit: ReadThroughUnit) -> TimeInterval { unit.kind == .word ? wordBeat : lineBeat }

    /// When each unit starts on the silent beat.
    public static func beatStarts(_ units: [ReadThroughUnit]) -> [TimeInterval] {
        var start: TimeInterval = 0
        return units.map { unit in
            defer { start += beat(unit) }
            return start
        }
    }

    public static func silentLength(_ units: [ReadThroughUnit]) -> TimeInterval {
        max(minimum, units.reduce(0) { $0 + beat($1) })
    }

    public static func deadline(_ units: [ReadThroughUnit]) -> TimeInterval { silentLength(units) + deadlineSlack }
}

/// The state of the one sequence on screen: idle, playing (with the lit item), or done.
public struct ReadThroughCursor: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case idle
        /// `index`: the unit that has started (nil before the first start event).
        case playing(index: Int?)
        case done
    }

    public private(set) var state: State = .idle
    public private(set) var deal: String?
    public private(set) var generation: Int?
    public private(set) var units: [ReadThroughUnit] = []
    public private(set) var engine: ReadThroughEngine = .silentBeat
    /// The lit item (a row slot, a card, the sign), or nil.
    public private(set) var light: Int?

    public init() {}

    /// A new sequence (a replay is a new start with a new generation, from item 1).
    public mutating func start(units: [ReadThroughUnit], deal: String, generation: Int, engine: ReadThroughEngine) {
        self.units = units
        self.deal = deal
        self.generation = generation
        self.engine = engine
        state = .playing(index: nil)
        light = nil
    }

    private func current(_ deal: String, _ generation: Int) -> Bool {
        state != .idle && state != .done && self.deal == deal && self.generation == generation
    }

    /// `didStart` of unit i, a clip's start time, or a beat: unit i lights its item.
    @discardableResult
    public mutating func unitStarted(_ index: Int, deal: String, generation: Int) -> Bool {
        guard current(deal, generation), units.indices.contains(index) else { return false }
        state = .playing(index: index)
        light = units[index].light
        return true
    }

    /// `didFinish` of the last unit, the last clip's end or the last beat: the sequence ends.
    @discardableResult
    public mutating func finished(deal: String, generation: Int) -> Bool {
        guard current(deal, generation) else { return false }
        state = .done
        light = nil
        return true
    }

    /// `didCancel`, a stopped clip (no callback: the app calls this itself) or a dropped beat: the light clears; a
    /// cancel is never an end.
    @discardableResult
    public mutating func cancelled(deal: String, generation: Int) -> Bool {
        guard current(deal, generation) else { return false }
        light = nil
        return true
    }

    /// The deadline (silent length + 4 s) of this deal and generation: ends a sequence that got no end event.
    @discardableResult
    public mutating func deadline(deal: String, generation: Int) -> Bool {
        guard current(deal, generation) else { return false }
        state = .done
        light = nil
        return true
    }

    /// Leaving the board or a new deal.
    public mutating func reset() { self = ReadThroughCursor() }
}
