import Foundation

// v0.31.0 筆順動畫 (stroke-order animation), digits only (S0–S2).
// Design: visa-games-design/stroke-order/design.md D1–D15 (Opus 5.5), approved by Carter 2026-10-19.
// One player for every script: a timeline over the glyph's own centre lines, played at one of three
// doses (教 teach / 提 remind / 一閃 glance). Digits are never authored twice: the strokes come from
// `NumeralGlyphs` and the teach timing from `TapCountGuideData` (D12). Letters and Chinese characters
// (D13–D14) plug in later through `StrokeGlyph` (no data shipped yet).
// Nothing here can mark the child wrong; the player has no judgement and never takes input away.

// MARK: - Settings, doses

/// Parent setting per script (D4). Digits default to 提.
public enum StrokeOrderSetting: String, Codable, CaseIterable, Sendable {
    case teach, remind, off
}

/// How much the player shows (D1).
public enum StrokeOrderDosage: String, Codable, CaseIterable, Sendable {
    case teach, remind, glance
}

/// Scripts the model covers (D11). Only `.digit` has data in v0.31.0.
public enum StrokeScript: String, Codable, Sendable {
    case digit, latin, hanzi
}

/// Parent copy (D4; Opus wrote it in design.md, Carter approved it).
public enum StrokeOrderCopy {
    public static let title = "筆順動畫 · Stroke-order animation"
    public static func short(_ setting: StrokeOrderSetting) -> String {
        switch setting {
        case .teach: return "教"
        case .remind: return "提"
        case .off: return "熄"
        }
    }
    public static func detail(_ setting: StrokeOrderSetting) -> String {
        switch setting {
        case .teach:
            return "教：慢慢寫，讀口訣；4、5、10 有 ①② · Teach: slow, with the rhyme; 1 and 2 badges on 4, 5, 10"
        case .remind:
            return "提（預設）：數字亮起時筆仔寫一次（約 2 秒，靜音）；識咗嘅快啲；描之前閃 3 次就收 · Remind (default): the pen writes the number as it lights up (about 2 s, silent); quicker once learned; 3 quick glances before tracing, then none"
        case .off:
            return "熄：唔用筆仔，同 v0.30 一樣 · Off: no pen, as in v0.30"
        }
    }
}

// MARK: - Pacing (D7; build/stroke-order-model.json tables.pacing)

public struct StrokeOrderPacing: Equatable, Sendable {
    public let speed: Double          // glyph units per second
    public let useBeatSeconds: Bool
    public let minStroke: Double
    public let turnPause: Double
    public let lift: Double
    public let leadIn: Double
    public let endHold: Double

    public static func of(_ dosage: StrokeOrderDosage) -> StrokeOrderPacing {
        switch dosage {
        case .teach:
            return StrokeOrderPacing(speed: 200, useBeatSeconds: true, minStroke: 0.6, turnPause: 0.3, lift: 0.6,
                                     leadIn: 0.4, endHold: 0.6)
        case .remind:
            return StrokeOrderPacing(speed: 420, useBeatSeconds: false, minStroke: 0.35, turnPause: 0.12, lift: 0.35,
                                     leadIn: 0.25, endHold: 0.3)
        case .glance:
            return StrokeOrderPacing(speed: 700, useBeatSeconds: false, minStroke: 0.2, turnPause: 0, lift: 0.15,
                                     leadIn: 0, endHold: 0.1)
        }
    }

    /// Ink left on a trace board fades over this long (★ plate: the ink is the revealed numeral and stays).
    public static let inkFadeSeconds = 1.5
    /// Reduce Motion: each segment fades in over this long instead of the pen gliding (D9).
    public static let reduceMotionFadeSeconds = 0.2
}

// MARK: - Generic glyph (D11; digits adapt NumeralGlyphs, D12)

public struct StrokeGlyph: Equatable, Sendable {
    public struct Stroke: Equatable, Sendable {
        /// Centre line in writing direction (glyph units).
        public let path: TracePath
        /// Stop-and-turn and turn-back points along the stroke (glyph-unit distances, ascending).
        public let turns: [Double]
        /// 筆劃 kind (required for hanzi later; nil for digits).
        public let kind: String?
    }

    public let id: String
    public let script: StrokeScript
    public let strokes: [Stroke]
    public let box: (width: Double, height: Double)
    /// Key shared with the v0.30 識咗 progress (digits: "1"–"10").
    public let progressKey: String

    public static func == (a: StrokeGlyph, b: StrokeGlyph) -> Bool {
        a.id == b.id && a.strokes == b.strokes && a.box.width == b.box.width && a.box.height == b.box.height
    }

    /// Digits 1–10 from `NumeralGlyphs` (no second copy of the paths). Nil outside 1–10.
    public static func digit(_ n: Int) -> StrokeGlyph? {
        guard (1...10).contains(n) else { return nil }
        let paths = NumeralGlyphs.paths(n, offset: LineMatchPoint(x: 0, y: 0), scale: 1)
        guard !paths.isEmpty else { return nil }
        let strokes = paths.map { path in
            Stroke(path: path, turns: (path.corners + path.cusps).filter { $0 > 0.5 && $0 < path.length - 0.5 }.sorted(),
                   kind: nil)
        }
        return StrokeGlyph(id: "digit:\(n)", script: .digit, strokes: strokes, box: NumeralGlyphs.box(n),
                           progressKey: "\(n)")
    }
}

// MARK: - Timeline (D7, D9)

public struct StrokeOrderTimeline: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case lead
        case draw(stroke: Int, from: Double, to: Double)
        case pause(stroke: Int, at: Double)
        case lift(from: Int, to: Int)
        case hold
    }

    public struct Step: Equatable, Sendable {
        public let kind: Kind
        public let start: Double
        public let end: Double
    }

    /// Where the pen is at a moment: on a stroke (distance along it), or lifting between strokes.
    public struct Pose: Equatable, Sendable {
        public let stroke: Int
        /// Glyph-unit distance on `stroke` written so far.
        public let distance: Double
        /// Lift between strokes: (from, to, 0…1).
        public let lift: (from: Int, to: Int, u: Double)?
        public let penDown: Bool
        /// Reduce Motion: opacity of the newest segment while it fades in (1 otherwise).
        public let newestOpacity: Double
        /// Reduce Motion: where the newest segment starts on `stroke`.
        public let newestFrom: Double

        public static func == (a: Pose, b: Pose) -> Bool {
            a.stroke == b.stroke && a.distance == b.distance && a.penDown == b.penDown
                && a.lift?.from == b.lift?.from && a.lift?.to == b.lift?.to && a.lift?.u == b.lift?.u
                && a.newestOpacity == b.newestOpacity && a.newestFrom == b.newestFrom
        }
    }

    public let glyph: StrokeGlyph
    public let dosage: StrokeOrderDosage
    public let steps: [Step]
    public let duration: Double

    public init(glyph: StrokeGlyph, dosage: StrokeOrderDosage, beatSeconds: [Int: Double] = [:]) {
        self.glyph = glyph
        self.dosage = dosage
        let pace = StrokeOrderPacing.of(dosage)
        var steps: [Step] = []
        var t = 0.0
        if pace.leadIn > 0 {
            steps.append(Step(kind: .lead, start: 0, end: pace.leadIn))
            t = pace.leadIn
        }
        for (index, stroke) in glyph.strokes.enumerated() {
            if index > 0 {
                steps.append(Step(kind: .lift(from: index - 1, to: index), start: t, end: t + pace.lift))
                t += pace.lift
            }
            let length = stroke.path.length
            var seconds = length / pace.speed
            if pace.useBeatSeconds, let beat = beatSeconds[index] { seconds = beat }
            seconds = max(pace.minStroke, seconds)
            var cursor = 0.0
            let turns = Set(stroke.turns)
            for boundary in Self.chunkBoundaries(stroke, single: glyph.strokes.count == 1) {
                let leg = (boundary - cursor) / max(length, 0.001) * seconds
                if leg > 0 {
                    steps.append(Step(kind: .draw(stroke: index, from: cursor, to: boundary), start: t, end: t + leg))
                    t += leg
                }
                cursor = boundary
                if boundary < length, turns.contains(boundary), pace.turnPause > 0 {
                    steps.append(Step(kind: .pause(stroke: index, at: boundary), start: t, end: t + pace.turnPause))
                    t += pace.turnPause
                }
            }
        }
        if pace.endHold > 0 {
            steps.append(Step(kind: .hold, start: t, end: t + pace.endHold))
            t += pace.endHold
        }
        self.steps = steps
        self.duration = t
    }

    /// Digits: the glyph from `NumeralGlyphs`; 教 uses the v0.30 rhyme beat seconds per stroke.
    public static func digit(_ n: Int, dosage: StrokeOrderDosage) -> StrokeOrderTimeline? {
        guard let glyph = StrokeGlyph.digit(n) else { return nil }
        var beats: [Int: Double] = [:]
        if dosage == .teach, let spec = TapCountGuideData.numeral(n) {
            for beat in spec.beats { beats[beat.stroke, default: 0] += beat.seconds }
        }
        return StrokeOrderTimeline(glyph: glyph, dosage: dosage, beatSeconds: beats)
    }

    /// Draw segments of a stroke: split at its turns; a lone stroke with no turns is split in 4, so
    /// Reduce Motion can show it in steps (D9). The last boundary is the stroke's length.
    static func chunkBoundaries(_ stroke: StrokeGlyph.Stroke, single: Bool) -> [Double] {
        let length = stroke.path.length
        if !stroke.turns.isEmpty { return stroke.turns + [length] }
        return single ? [0.25, 0.5, 0.75, 1].map { $0 * length } : [length]
    }

    /// Pose at `t` seconds. With Reduce Motion the pen does not glide: each chunk appears whole and fades in.
    public func pose(at t: Double, reduceMotion: Bool = false) -> Pose {
        let clamped = min(max(t, 0), duration)
        var last = Pose(stroke: 0, distance: 0, lift: nil, penDown: false, newestOpacity: 1, newestFrom: 0)
        for step in steps {
            if clamped < step.start { break }
            let u = step.end > step.start ? min(1, (clamped - step.start) / (step.end - step.start)) : 1
            switch step.kind {
            case .lead:
                last = Pose(stroke: 0, distance: 0, lift: nil, penDown: true, newestOpacity: 1, newestFrom: 0)
            case .draw(let stroke, let from, let to):
                if reduceMotion {
                    // The pen does not glide: the whole segment appears and fades in.
                    let fade = min(1, (clamped - step.start) / StrokeOrderPacing.reduceMotionFadeSeconds)
                    last = Pose(stroke: stroke, distance: to, lift: nil, penDown: true, newestOpacity: fade, newestFrom: from)
                } else {
                    last = Pose(stroke: stroke, distance: from + (to - from) * u, lift: nil, penDown: true,
                                newestOpacity: 1, newestFrom: 0)
                }
            case .pause(let stroke, let at):
                last = Pose(stroke: stroke, distance: max(at, last.stroke == stroke ? last.distance : 0), lift: nil,
                            penDown: true, newestOpacity: 1, newestFrom: 0)
            case .lift(let from, let to):
                let fromLength = glyph.strokes[from].path.length
                last = Pose(stroke: from, distance: fromLength, lift: (from, to, u), penDown: false,
                            newestOpacity: 1, newestFrom: 0)
                if u >= 1 {
                    last = Pose(stroke: to, distance: 0, lift: nil, penDown: true, newestOpacity: 1, newestFrom: 0)
                }
            case .hold:
                let lastIndex = glyph.strokes.count - 1
                last = Pose(stroke: lastIndex, distance: glyph.strokes[lastIndex].path.length, lift: nil, penDown: false,
                            newestOpacity: 1, newestFrom: 0)
            }
        }
        return last
    }

    /// Ink written by `t`: per stroke, the distance reached (0 = nothing yet).
    public func inked(at t: Double, reduceMotion: Bool = false) -> [Double] {
        let pose = self.pose(at: t, reduceMotion: reduceMotion)
        return glyph.strokes.indices.map { index in
            if index < pose.stroke { return glyph.strokes[index].path.length }
            if index == pose.stroke { return pose.distance }
            return 0
        }
    }

    /// True once every stroke is written (the hold may still be running).
    public func written(at t: Double) -> Bool {
        guard let lastDraw = steps.last(where: { if case .draw = $0.kind { return true }; return false }) else { return true }
        return t >= lastDraw.end
    }
}

// MARK: - Progress (glances after 識咗, the 7-day refresh; D3)

public struct StrokeOrderProgress: Codable, Equatable, Sendable {
    /// Quick glances after a glyph is learned, before none (Carter: 3).
    public static let glanceBudget = 3
    /// A learned glyph not traced for this many days gets one refresh glance (Carter: 7).
    public static let refreshDays = 7

    public var glancesLeft: [String: Int] = [:]
    public var lastTracedDay: [String: Int] = [:]

    public init() {}

    public enum GlanceReason: String, Sendable { case budget, refresh }

    public func remaining(_ key: String) -> Int { glancesLeft[key] ?? Self.glanceBudget }

    /// Whether a learned glyph should glance now, and why.
    public func dueGlance(_ key: String, today: Int) -> GlanceReason? {
        if remaining(key) > 0 { return .budget }
        if let last = lastTracedDay[key], today - last >= Self.refreshDays { return .refresh }
        return nil
    }

    /// A glance played. Budget glances count down; a refresh glance leaves the budget at 0.
    public mutating func consume(_ key: String, reason: GlanceReason) {
        if reason == .budget { glancesLeft[key] = max(0, remaining(key) - 1) }
    }

    /// A trace of this glyph started today (for the refresh rule).
    public mutating func noteTraced(_ key: String, today: Int) { lastTracedDay[key] = today }

    /// Back to learning (a stall): the budget refills for when it is learned again.
    public mutating func reset(_ key: String) { glancesLeft[key] = nil }

    /// Local calendar day number for `clock` (seconds since the reference date).
    public static func day(clock: Double, timeZone: TimeZone = .current) -> Int {
        let date = Date(timeIntervalSinceReferenceDate: clock)
        let local = clock + Double(timeZone.secondsFromGMT(for: date))
        return Int((local / 86_400).rounded(.down))
    }
}

/// UserDefaults; missing or corrupt → empty. A failed save never reaches the child.
public struct StrokeOrderProgressStore {
    public static let key = "VisaGames.strokeOrderProgress.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> StrokeOrderProgress {
        guard let data = defaults.data(forKey: Self.key),
              let progress = try? JSONDecoder().decode(StrokeOrderProgress.self, from: data) else { return StrokeOrderProgress() }
        return progress
    }

    public func save(_ progress: StrokeOrderProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

// MARK: - Dosage rules (build/stroke-order-model.json tables.dosageRules)

public enum StrokeOrderPlan {
    /// ★ reveal: the pen writes the numeral as it lights up. Off → nil (plain v0.30 reveal).
    public static func star1(setting: StrokeOrderSetting, learned: Bool) -> StrokeOrderDosage? {
        switch setting {
        case .off: return nil
        case .teach: return .teach
        case .remind: return learned ? .glance : .remind
        }
    }

    /// ★★ / ★★★ before the trace: a silent glance replaces the car demo only for a learned numeral
    /// at 標準 (多啲 always shows the car; 少啲 shows nothing). Never together with the car demo.
    public static func star2Glance(setting: StrokeOrderSetting, guidance: TapCountGuidanceLevel, learned: Bool,
                                   carDemo: Bool, progress: StrokeOrderProgress, key: String,
                                   today: Int) -> StrokeOrderProgress.GlanceReason? {
        guard setting != .off, guidance == .standard, learned, !carDemo else { return nil }
        return progress.dueGlance(key, today: today)
    }

    /// ★: replays by tapping the numeral plate after the pen has written it.
    public static let maxReplays = 2
}

/// ★ reveal state on the board (the pen writing the lit numeral; tap = finish now, tap after = replay).
public struct StrokeOrderReveal: Equatable, Sendable {
    public let dosage: StrokeOrderDosage
    public let duration: Double
    public private(set) var startedAt: Double
    public private(set) var finishedEarlyAt: Double?
    public private(set) var replays = 0
    public private(set) var skips = 0

    public init(dosage: StrokeOrderDosage, duration: Double, startAt: Double) {
        self.dosage = dosage
        self.duration = duration
        self.startedAt = startAt
    }

    /// Seconds into the write, or nil when not writing (before the start, finished, or skipped).
    public func time(now: Double) -> Double? {
        guard finishedEarlyAt == nil else { return nil }
        let t = now - startedAt
        return t >= 0 && t < duration ? t : nil
    }

    public func writing(now: Double) -> Bool { finishedEarlyAt == nil && now < startedAt + duration }

    /// When the pen is done (finished or skipped), for the ★ finish timer.
    public func endsAt(now: Double) -> Double {
        if let early = finishedEarlyAt { return early }
        return startedAt + duration
    }

    /// A tap on the plate: while writing → finish now; afterwards → replay (at most 2). Returns what happened.
    public enum TapResult: Equatable, Sendable { case finished, replayed, ignored }

    public mutating func tap(now: Double) -> TapResult {
        if writing(now: now) {
            finishedEarlyAt = now
            skips += 1
            return .finished
        }
        guard replays < StrokeOrderPlan.maxReplays else { return .ignored }
        replays += 1
        startedAt = now
        finishedEarlyAt = nil
        return .replayed
    }
}
