import Foundation

// 一架一架數 numeral-formation guidance (v0.30.0; Carter approved the Opus recommendation on
// 2026-10-18: visa-games-design/number-quantity/guidance, options.md + mockups 01–03).
//
// 標準 (default): a demo ghost car drives the numeral once with the pathway rhyme before the child
// traces (until 識咗); headlights turn the next 3 lane dots into chevrons; a sign + line just before
// each crossing / turn; after a 2 s stall a ring and the ghost car run just the next bit. Two-stroke
// numerals fade the strokes not reached yet and the car hops to the next one. Parents choose
// 多啲 / 標準 / 少啲. 識咗 = 2 clean traces of a numeral in a row; one stall drops it back.
//
// Everything here is a pure function of the spec (TapCountGuideData, generated from the Opus build
// spec), the trace board and the clock, so the Cantonese and English cards share it exactly. Tracing
// is still never wrong: guidance only shows the way and never touches fuel, misses or the trace.

// MARK: - Spec types (values live in the generated TapCountGuideData)

/// 數字設定 › 描數字提示: 多啲 / 標準 / 少啲.
public enum TapCountGuidanceLevel: String, Codable, CaseIterable, Sendable {
    case more
    case standard
    case less
}

public enum TapCountGuideDemoRule: String, Sendable {
    case always
    case untilLearned
    case never
}

public enum TapCountGuideFeature: String, Sendable, CaseIterable {
    case headlights
    case cueSigns
    case cueWords
    case fadeLaterStrokes
    case hop
}

/// Sign beside a crossing / turn: `ahead` (blue round sign, arrow along the way the car goes next)
/// or `stop` (octagon at a corner; the word is drawn by the app in the card's language).
public enum NumeralCueSign: String, Sendable {
    case ahead
    case stop
}

/// Which way the dotted hop arc bows between two strokes.
public enum TapCountHopSide: String, Sendable {
    case left
    case right
    case up
    case down
}

public struct TapCountGuideTiming: Equatable, Sendable {
    public let hopSeconds: Double
    public let cuePauseSeconds: Double
    public let mergeSeconds: Double
    public let routeFadeSeconds: Double
    public let cueLeadUnits: Double
    public let headlightDots: Int
    public let stallRingGhostSeconds: Double

    public init(hopSeconds: Double, cuePauseSeconds: Double, mergeSeconds: Double, routeFadeSeconds: Double,
                cueLeadUnits: Double, headlightDots: Int, stallRingGhostSeconds: Double) {
        self.hopSeconds = hopSeconds
        self.cuePauseSeconds = cuePauseSeconds
        self.mergeSeconds = mergeSeconds
        self.routeFadeSeconds = routeFadeSeconds
        self.cueLeadUnits = cueLeadUnits
        self.headlightDots = headlightDots
        self.stallRingGhostSeconds = stallRingGhostSeconds
    }
}

public struct TapCountGuideLevelSpec: Equatable, Sendable {
    public let demo: TapCountGuideDemoRule
    public let features: Set<TapCountGuideFeature>
    public let stallSeconds: Double?
    public let ghostToEndSeconds: Double?
    public let redemoSeconds: Double?
    /// What stays on once a numeral is 識咗 (the rest switches off).
    public let learnedKeeps: Set<TapCountGuideFeature>

    public init(demo: TapCountGuideDemoRule, features: Set<TapCountGuideFeature>, stallSeconds: Double?,
                ghostToEndSeconds: Double?, redemoSeconds: Double?, learnedKeeps: Set<TapCountGuideFeature>) {
        self.demo = demo
        self.features = features
        self.stallSeconds = stallSeconds
        self.ghostToEndSeconds = ghostToEndSeconds
        self.redemoSeconds = redemoSeconds
        self.learnedKeeps = learnedKeeps
    }
}

/// One line in both card languages. Cantonese card: `zh` + small English `zhSub`. English card:
/// `en` (+ optional small `enSub`), English only.
public struct TapCountGuideLine: Equatable, Sendable {
    public let zh: String
    public let zhSub: String
    public let en: String
    public let enSub: String

    public init(zh: String, zhSub: String, en: String, enSub: String = "") {
        self.zh = zh
        self.zhSub = zhSub
        self.en = en
        self.enSub = enSub
    }
}

/// A point on a stroke in glyph units, and which time the stroke passes nearest to it.
public struct NumeralGuidePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let pass: Int

    public init(x: Double, y: Double, pass: Int = 1) {
        self.x = x
        self.y = y
        self.pass = pass
    }
}

public struct NumeralGuideBeatSpec: Equatable, Sendable {
    public let stroke: Int
    /// Nil = the end of the stroke.
    public let until: NumeralGuidePoint?
    public let seconds: Double
    public let line: TapCountGuideLine

    public init(stroke: Int, until: NumeralGuidePoint?, seconds: Double, line: TapCountGuideLine) {
        self.stroke = stroke
        self.until = until
        self.seconds = seconds
        self.line = line
    }
}

public struct NumeralGuideCueSpec: Equatable, Sendable {
    public let stroke: Int
    public let point: NumeralGuidePoint
    public let sign: NumeralCueSign
    /// Sign centre in glyph units (clear of the lane).
    public let signAt: LineMatchPoint
    public let line: TapCountGuideLine

    public init(stroke: Int, point: NumeralGuidePoint, sign: NumeralCueSign, signAt: LineMatchPoint, line: TapCountGuideLine) {
        self.stroke = stroke
        self.point = point
        self.sign = sign
        self.signAt = signAt
        self.line = line
    }
}

public struct NumeralGuideSpec: Equatable, Sendable {
    public let numeral: Int
    public let beats: [NumeralGuideBeatSpec]
    public let merge: TapCountGuideLine
    public let cues: [NumeralGuideCueSpec]
    public let hop: TapCountGuideLine?
    public let hopSide: TapCountHopSide?
    public let lastStroke: TapCountGuideLine?

    public init(numeral: Int, beats: [NumeralGuideBeatSpec], merge: TapCountGuideLine, cues: [NumeralGuideCueSpec],
                hop: TapCountGuideLine?, hopSide: TapCountHopSide?, lastStroke: TapCountGuideLine?) {
        self.numeral = numeral
        self.beats = beats
        self.merge = merge
        self.cues = cues
        self.hop = hop
        self.hopSide = hopSide
        self.lastStroke = lastStroke
    }
}

public struct TapCountGuideParentCopy: Equatable, Sendable {
    public let title: String
    public let more: String
    public let standard: String
    public let less: String
    public let learnedNote: String
    public let moreShort: String
    public let standardShort: String
    public let lessShort: String

    public init(title: String, more: String, standard: String, less: String, learnedNote: String,
                moreShort: String, standardShort: String, lessShort: String) {
        self.title = title
        self.more = more
        self.standard = standard
        self.less = less
        self.learnedNote = learnedNote
        self.moreShort = moreShort
        self.standardShort = standardShort
        self.lessShort = lessShort
    }

    public func short(_ level: TapCountGuidanceLevel) -> String {
        switch level {
        case .more: return moreShort
        case .standard: return standardShort
        case .less: return lessShort
        }
    }

    public func detail(_ level: TapCountGuidanceLevel) -> String {
        switch level {
        case .more: return more
        case .standard: return standard
        case .less: return less
        }
    }
}

public struct TapCountGuideCopy: Equatable, Sendable {
    public let watchFirst: TapCountGuideLine
    public let yourTurn: TapCountGuideLine
    public let trayDemo: TapCountGuideLine
    public let trayTrace: TapCountGuideLine
    public let trayStall: TapCountGuideLine
    public let legendDemoCar: TapCountGuideLine
    public let legendRoute: TapCountGuideLine
    public let legendHeadlights: TapCountGuideLine
    public let legendAhead: TapCountGuideLine
    public let legendStop: TapCountGuideLine
    public let legendStrokeOrder: TapCountGuideLine
    public let legendHop: TapCountGuideLine
    public let redemo: TapCountGuideLine
    public let stopWordZh: String
    public let stopWordEn: String
    public let parent: TapCountGuideParentCopy

    public init(watchFirst: TapCountGuideLine, yourTurn: TapCountGuideLine, trayDemo: TapCountGuideLine,
                trayTrace: TapCountGuideLine, trayStall: TapCountGuideLine, legendDemoCar: TapCountGuideLine,
                legendRoute: TapCountGuideLine, legendHeadlights: TapCountGuideLine, legendAhead: TapCountGuideLine,
                legendStop: TapCountGuideLine, legendStrokeOrder: TapCountGuideLine, legendHop: TapCountGuideLine,
                redemo: TapCountGuideLine, stopWordZh: String, stopWordEn: String, parent: TapCountGuideParentCopy) {
        self.watchFirst = watchFirst
        self.yourTurn = yourTurn
        self.trayDemo = trayDemo
        self.trayTrace = trayTrace
        self.trayStall = trayStall
        self.legendDemoCar = legendDemoCar
        self.legendRoute = legendRoute
        self.legendHeadlights = legendHeadlights
        self.legendAhead = legendAhead
        self.legendStop = legendStop
        self.legendStrokeOrder = legendStrokeOrder
        self.legendHop = legendHop
        self.redemo = redemo
        self.stopWordZh = stopWordZh
        self.stopWordEn = stopWordEn
        self.parent = parent
    }
}

/// Drawing values from the Opus spec (colours 0xRRGGBB, widths in glyph units unless noted).
public struct TapCountGuideStyles: Equatable, Sendable {
    public let routeGlow: UInt32
    public let routeGlowWidth: Double
    public let routeCore: UInt32
    public let routeCoreWidth: Double
    public let routeDash: [Double]
    public let beamOuter: UInt32
    public let beamOuterWidth: Double
    public let beamInner: UInt32
    public let beamInnerWidth: Double
    public let beamInnerOpacity: Double
    public let hopArc: UInt32
    public let hopArcWidth: Double
    public let hopArcDash: [Double]
    public let fadedStrokeOpacity: Double
    public let stallRingRadius: Double
    public let stallRingFill: UInt32
    public let stallRingStroke: UInt32
    public let litGlow: UInt32
    public let litGlowWidth: Double
    public let litGlowOpacity: Double
    public let litGlowSeconds: Double

    public init(routeGlow: UInt32, routeGlowWidth: Double, routeCore: UInt32, routeCoreWidth: Double, routeDash: [Double],
                beamOuter: UInt32, beamOuterWidth: Double, beamInner: UInt32, beamInnerWidth: Double,
                beamInnerOpacity: Double, hopArc: UInt32, hopArcWidth: Double, hopArcDash: [Double],
                fadedStrokeOpacity: Double, stallRingRadius: Double, stallRingFill: UInt32, stallRingStroke: UInt32,
                litGlow: UInt32, litGlowWidth: Double, litGlowOpacity: Double, litGlowSeconds: Double) {
        self.routeGlow = routeGlow
        self.routeGlowWidth = routeGlowWidth
        self.routeCore = routeCore
        self.routeCoreWidth = routeCoreWidth
        self.routeDash = routeDash
        self.beamOuter = beamOuter
        self.beamOuterWidth = beamOuterWidth
        self.beamInner = beamInner
        self.beamInnerWidth = beamInnerWidth
        self.beamInnerOpacity = beamInnerOpacity
        self.hopArc = hopArc
        self.hopArcWidth = hopArcWidth
        self.hopArcDash = hopArcDash
        self.fadedStrokeOpacity = fadedStrokeOpacity
        self.stallRingRadius = stallRingRadius
        self.stallRingFill = stallRingFill
        self.stallRingStroke = stallRingStroke
        self.litGlow = litGlow
        self.litGlowWidth = litGlowWidth
        self.litGlowOpacity = litGlowOpacity
        self.litGlowSeconds = litGlowSeconds
    }
}

// MARK: - Plan (what a round shows, from the level and 識咗)

public struct TapCountGuidePlan: Equatable, Sendable {
    public let level: TapCountGuidanceLevel
    public let learned: Bool
    public let demo: Bool
    public let features: Set<TapCountGuideFeature>
    public let stallSeconds: Double?
    public let ghostToEndSeconds: Double?
    public let redemoSeconds: Double?

    public init(level: TapCountGuidanceLevel, learned: Bool) {
        let spec = TapCountGuideData.level(level)
        self.level = level
        self.learned = learned
        switch spec.demo {
        case .always: demo = true
        case .untilLearned: demo = !learned
        case .never: demo = false
        }
        features = learned && spec.demo != .always ? spec.features.intersection(spec.learnedKeeps) : spec.features
        stallSeconds = spec.stallSeconds
        ghostToEndSeconds = spec.ghostToEndSeconds
        redemoSeconds = spec.redemoSeconds
    }

    public var headlights: Bool { features.contains(.headlights) }
    public var cueSigns: Bool { features.contains(.cueSigns) }
    public var cueWords: Bool { features.contains(.cueWords) }
    public var fadesLaterStrokes: Bool { features.contains(.fadeLaterStrokes) }
    public var hops: Bool { features.contains(.hop) }
}

// MARK: - 識咗 progress (2 clean traces in a row; one stall drops it back)

public struct TapCountGuideProgress: Equatable, Sendable, Codable {
    public private(set) var streaks: [String: Int]

    public init(streaks: [String: Int] = [:]) { self.streaks = streaks }

    public static var cleanInARow: Int { TapCountGuideData.cleanInARow }

    public static func key(_ n: Int, language: TapCountLanguage) -> String {
        TapCountGuideData.sharedAcrossLanguages ? "\(n)" : "\(language.rawValue).\(n)"
    }

    public func streak(_ n: Int, language: TapCountLanguage) -> Int { streaks[Self.key(n, language: language)] ?? 0 }

    public func isLearned(_ n: Int, language: TapCountLanguage) -> Bool {
        streak(n, language: language) >= Self.cleanInARow
    }

    /// A clean trace: one more in a row.
    public mutating func recordClean(_ n: Int, language: TapCountLanguage) {
        streaks[Self.key(n, language: language)] = min(99, streak(n, language: language) + 1)
    }

    /// Any stall (help shown): back to learning.
    public mutating func recordStall(_ n: Int, language: TapCountLanguage) {
        streaks[Self.key(n, language: language)] = 0
    }

    public func learnedNumerals(language: TapCountLanguage) -> [Int] {
        (1...10).filter { isLearned($0, language: language) }
    }
}

/// UserDefaults; missing or corrupt → nothing learned. A failed save never reaches the child.
public struct TapCountGuideProgressStore {
    public static let key = "VisaGames.tapCountGuideProgress.v1"
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> TapCountGuideProgress {
        guard let data = defaults.data(forKey: Self.key),
              let progress = try? JSONDecoder().decode(TapCountGuideProgress.self, from: data) else {
            return TapCountGuideProgress()
        }
        return progress
    }

    public func save(_ progress: TapCountGuideProgress) {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

public struct LetterBoardGuideStyle: Equatable, Sendable {
    public let laneScale: Double
    public let carScale: Double
    public let noseUnits: Double
    public let chevScale: Double
    public let laneDotSpacing: Double
    public let stopSignScale: Double
    public let aheadSignScale: Double
    public init(laneScale: Double, carScale: Double, noseUnits: Double, chevScale: Double,
                laneDotSpacing: Double, stopSignScale: Double, aheadSignScale: Double) {
        self.laneScale = laneScale; self.carScale = carScale; self.noseUnits = noseUnits
        self.chevScale = chevScale; self.laneDotSpacing = laneDotSpacing
        self.stopSignScale = stopSignScale; self.aheadSignScale = aheadSignScale
    }
}

// MARK: - Resolved geometry (stage units, the same paths as the trace board)

public struct NumeralGuide: Equatable, Sendable {
    public struct Beat: Equatable, Sendable {
        public let stroke: Int
        public let end: Double
        public let seconds: Double
    }

    public struct Cue: Equatable, Sendable {
        public let index: Int
        public let stroke: Int
        public let distance: Double
        public let sign: NumeralCueSign
        public let signPoint: LineMatchPoint
    }

    public let numeral: Int
    public let glyphKey: String
    public let spec: NumeralGuideSpec
    public let paths: [TracePath]
    public let scale: Double
    public let offset: LineMatchPoint
    public let beats: [Beat]
    public let cues: [Cue]

    /// Nil when the numeral has no spec or a point does not lie on its stroke.
    public init?(_ n: Int) {
        guard let spec = TapCountGuideData.numeral(n) else { return nil }
        let placement = NumeralGlyphs.tracePlacement(n)
        let strokes = NumeralGlyphs.strokes(n)
        let paths = NumeralGlyphs.paths(n, offset: placement.offset, scale: placement.scale)
        guard !paths.isEmpty else { return nil }
        self.init(spec: spec, glyphKey: "\(n)", placement: placement, strokes: strokes, paths: paths)
    }

    public init?(letter: Character) {
        guard let spec = LetterGuideData.letter(letter) else { return nil }
        let placement = (offset: LineMatchPoint(x: 545, y: 142), scale: 1.0)
        let strokes = LatinGlyphs.strokes(letter).map {
            NumeralStroke($0.svg, corners: $0.corners, cusps: $0.cusps, closed: $0.closed)
        }
        let paths = LatinGlyphs.paths(letter, offset: placement.offset, scale: placement.scale)
        guard !paths.isEmpty else { return nil }
        self.init(spec: spec, glyphKey: "latin:\(letter)", placement: placement, strokes: strokes, paths: paths)
    }

    private init?(spec: NumeralGuideSpec, glyphKey: String,
                  placement: (offset: LineMatchPoint, scale: Double), strokes: [NumeralStroke], paths: [TracePath]) {
        var beats: [Beat] = []
        for beat in spec.beats {
            guard paths.indices.contains(beat.stroke), beat.seconds > 0 else { return nil }
            let path = paths[beat.stroke]
            let end: Double
            if let until = beat.until {
                guard let d = Self.distance(of: until, on: strokes[beat.stroke], stagePath: path) else { return nil }
                end = d
            } else {
                end = path.length
            }
            beats.append(Beat(stroke: beat.stroke, end: end, seconds: beat.seconds))
        }
        var cues: [Cue] = []
        for (index, cue) in spec.cues.enumerated() {
            guard paths.indices.contains(cue.stroke),
                  let d = Self.distance(of: cue.point, on: strokes[cue.stroke], stagePath: paths[cue.stroke]) else { return nil }
            let sign = LineMatchPoint(x: placement.offset.x + cue.signAt.x * placement.scale,
                                      y: placement.offset.y + cue.signAt.y * placement.scale)
            cues.append(Cue(index: index, stroke: cue.stroke, distance: d, sign: cue.sign, signPoint: sign))
        }
        self.numeral = spec.numeral
        self.glyphKey = glyphKey
        self.spec = spec
        self.paths = paths
        self.scale = placement.scale
        self.offset = placement.offset
        self.beats = beats
        self.cues = cues.sorted { ($0.stroke, $0.distance) < ($1.stroke, $1.distance) }
    }

    /// How far (glyph units) a spec point may lie from its stroke.
    public static let pointTolerance: Double = 6

    /// Glyph distance from `point` to the stroke (nearest sample; for the data test).
    public static func glyphOffset(of point: NumeralGuidePoint, on stroke: LatinStroke) -> Double? {
        glyphOffset(of: point, on: NumeralStroke(stroke.svg, corners: stroke.corners, cusps: stroke.cusps, closed: stroke.closed))
    }

    public static func glyphOffset(of point: NumeralGuidePoint, on stroke: NumeralStroke) -> Double? {
        let path = TracePath(svg: stroke.svg, corners: stroke.corners, cusps: stroke.cusps, closed: stroke.closed)
        guard let at = passDistance(point, on: path) else { return nil }
        let p = path.project(LineMatchPoint(x: point.x, y: point.y), window: max(0, at - 12)...min(path.length, at + 12))
        return p.offset
    }

    /// Arc length (glyph path) of the `pass`-th time the stroke comes within reach of `point`.
    static func passDistance(_ point: NumeralGuidePoint, on path: TracePath) -> Double? {
        let target = LineMatchPoint(x: point.x, y: point.y)
        var runs: [(distance: Double, gap: Double)] = []
        var inRun = false
        for (i, sample) in path.points.enumerated() {
            let gap = sample.distance(to: target)
            if gap <= pointTolerance + TracePath.sampleSpacing {
                if inRun, let last = runs.last {
                    if gap < last.gap { runs[runs.count - 1] = (path.cumulative[i], gap) }
                } else {
                    runs.append((path.cumulative[i], gap))
                    inRun = true
                }
            } else {
                inRun = false
            }
        }
        // A closed stroke that starts on the point counts its start and end as one pass.
        if path.closed, runs.count > 1, let first = runs.first, let last = runs.last,
           first.distance < TracePath.sampleSpacing * 3, path.length - last.distance < TracePath.sampleSpacing * 3 {
            runs.removeLast()
        }
        guard point.pass >= 1, runs.indices.contains(point.pass - 1) else { return nil }
        return runs[point.pass - 1].distance
    }

    static func distance(of point: NumeralGuidePoint, on stroke: NumeralStroke, stagePath: TracePath) -> Double? {
        let glyph = TracePath(svg: stroke.svg, corners: stroke.corners, cusps: stroke.cusps, closed: stroke.closed)
        guard glyph.length > 0, let at = passDistance(point, on: glyph) else { return nil }
        let projected = glyph.project(LineMatchPoint(x: point.x, y: point.y),
                                      window: max(0, at - 12)...min(glyph.length, at + 12))
        guard projected.offset <= pointTolerance else { return nil }
        return min(stagePath.length, projected.distance / glyph.length * stagePath.length)
    }

    /// Lane dot spacing in stage units (`stroke-dasharray 0 30` in glyph units).
    public var dotSpacing: Double { glyphKey.hasPrefix("latin:") ? LetterGuideData.board.laneDotSpacing : 30 * scale }
    public var noseUnits: Double { glyphKey.hasPrefix("latin:") ? LetterGuideData.board.noseUnits : TapCountGuideCoach.noseUnits }
    public var carScale: Double { glyphKey.hasPrefix("latin:") ? LetterGuideData.board.carScale : 0.72 }
    public var chevronScale: Double { glyphKey.hasPrefix("latin:") ? LetterGuideData.board.chevScale : scale }

    public func aheadAngle(for cue: Cue) -> Double {
        let path = paths[cue.stroke]
        return path.angle(at: min(path.length, cue.distance + 24))
    }

    /// Cues on `stroke`, in order.
    public func cues(onStroke stroke: Int) -> [Cue] { cues.filter { $0.stroke == stroke } }

    /// End of the beat that `progress` is in on `stroke` (the "next bit" a stall shows).
    public func beatEnd(stroke: Int, after progress: Double) -> Double {
        let ends = beats.filter { $0.stroke == stroke }.map(\.end)
        return ends.first { $0 > progress + 10 } ?? paths[stroke].length
    }

    /// Mean demo speed (stage units per second), used for the 8 s ghost-to-the-end.
    public var demoSpeed: Double {
        var distance = 0.0
        var seconds = 0.0
        var last: (stroke: Int, end: Double)?
        for beat in beats {
            let from = last.map { $0.stroke == beat.stroke ? $0.end : 0 } ?? 0
            distance += max(0, beat.end - from)
            seconds += beat.seconds
            last = (beat.stroke, beat.end)
        }
        return seconds > 0 ? max(60, distance / seconds) : 160
    }

    /// Control point of the dotted hop arc from the end of `from` to the start of `to`.
    public func hopControl(from: Int, to: Int) -> (start: LineMatchPoint, control: LineMatchPoint, end: LineMatchPoint) {
        let a = paths[from].end
        let b = paths[to].start
        let mid = LineMatchPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(hypot(dx, dy), 1)
        let n1 = LineMatchPoint(x: -dy / length, y: dx / length)
        let n2 = LineMatchPoint(x: dy / length, y: -dx / length)
        let pick: LineMatchPoint
        switch spec.hopSide ?? .left {
        case .left: pick = n1.x <= n2.x ? n1 : n2
        case .right: pick = n1.x >= n2.x ? n1 : n2
        case .up: pick = n1.y <= n2.y ? n1 : n2
        case .down: pick = n1.y >= n2.y ? n1 : n2
        }
        let bow = max(60, 0.65 * length)
        return (a, LineMatchPoint(x: mid.x + pick.x * bow, y: mid.y + pick.y * bow), b)
    }

    /// A point on the hop arc at 0…1, with its direction.
    public func hopPoint(from: Int, to: Int, at u: Double) -> (point: LineMatchPoint, angle: Double) {
        let (a, c, b) = hopControl(from: from, to: to)
        let t = min(max(u, 0), 1)
        let x = (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * c.x + t * t * b.x
        let y = (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * c.y + t * t * b.y
        let tx = 2 * (1 - t) * (c.x - a.x) + 2 * t * (b.x - c.x)
        let ty = 2 * (1 - t) * (c.y - a.y) + 2 * t * (b.y - c.y)
        return (LineMatchPoint(x: x, y: y), atan2(ty, tx))
    }
}

// MARK: - The demo (a pure function of time)

/// Where the ghost car is: on a stroke, or in the air on a hop (`lift` 0…1).
public struct TapCountGhostPose: Equatable, Sendable {
    public let point: LineMatchPoint
    public let angle: Double
    public let stroke: Int
    public let lift: Double
    public let opacity: Double
    /// Set while hopping: the strokes it hops between.
    public let hop: (from: Int, to: Int)?

    public static func == (a: TapCountGhostPose, b: TapCountGhostPose) -> Bool {
        a.point == b.point && a.angle == b.angle && a.stroke == b.stroke && a.lift == b.lift && a.opacity == b.opacity
            && a.hop?.from == b.hop?.from && a.hop?.to == b.hop?.to
    }
}

/// A driven stretch of the demo route and when the car finished it (the route fades after it).
public struct TapCountRoutePiece: Equatable, Sendable {
    public let stroke: Int
    public let from: Double
    public let to: Double
    public let passedAt: Double
}

public struct TapCountDemoTimeline: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        case drive(stroke: Int, from: Double, to: Double, beat: Int)
        case pause(stroke: Int, at: Double, cue: Int, beat: Int)
        case hop(from: Int, to: Int, beat: Int)
        case merge
    }

    public struct Timed: Equatable, Sendable {
        public let step: Step
        public let start: Double
        public let end: Double
    }

    public let guide: NumeralGuide
    public let steps: [Timed]
    /// When each beat's line is said (and shown in the bubble).
    public let beatStarts: [Double]
    public let mergeStart: Double
    public let duration: Double

    public init(guide: NumeralGuide, timing: TapCountGuideTiming = TapCountGuideData.timing) {
        self.guide = guide
        var steps: [Timed] = []
        var starts: [Double] = []
        var t = 0.0
        var at: (stroke: Int, distance: Double)?
        for (index, beat) in guide.beats.enumerated() {
            if let last = at, last.stroke != beat.stroke {
                steps.append(Timed(step: .hop(from: last.stroke, to: beat.stroke, beat: index), start: t, end: t + timing.hopSeconds))
                t += timing.hopSeconds
                at = (beat.stroke, 0)
            }
            starts.append(t)
            let from = at.map { $0.stroke == beat.stroke ? $0.distance : 0 } ?? 0
            let to = max(from, beat.end)
            let span = max(to - from, 0.001)
            var cursor = from
            for cue in guide.cues(onStroke: beat.stroke) where cue.distance > from + 0.5 && cue.distance <= to - 0.5 {
                let leg = (cue.distance - cursor) / span * beat.seconds
                steps.append(Timed(step: .drive(stroke: beat.stroke, from: cursor, to: cue.distance, beat: index), start: t, end: t + leg))
                t += leg
                steps.append(Timed(step: .pause(stroke: beat.stroke, at: cue.distance, cue: cue.index, beat: index),
                                   start: t, end: t + timing.cuePauseSeconds))
                t += timing.cuePauseSeconds
                cursor = cue.distance
            }
            let leg = (to - cursor) / span * beat.seconds
            steps.append(Timed(step: .drive(stroke: beat.stroke, from: cursor, to: to, beat: index), start: t, end: t + leg))
            t += leg
            at = (beat.stroke, to)
        }
        mergeStart = t
        steps.append(Timed(step: .merge, start: t, end: t + timing.mergeSeconds))
        t += timing.mergeSeconds
        self.steps = steps
        self.beatStarts = starts
        self.duration = t
    }

    public func timed(at t: Double) -> Timed? {
        guard t >= 0, t < duration else { return nil }
        return steps.first { t < $0.end } ?? steps.last
    }

    /// The beat whose line is current (the bubble's bold line); nil during the merge or after.
    public func beat(at t: Double) -> Int? {
        guard t >= 0, t < mergeStart else { return nil }
        return beatStarts.lastIndex { $0 <= t }
    }

    private static func ease(_ u: Double) -> Double { u * u * (3 - 2 * u) }

    /// The ghost car at `t` seconds into the demo; nil before 0 and after the end. With Reduce
    /// Motion the car does not glide: it sits at the end of each step (one jump per step).
    public func pose(at t: Double, reduceMotion: Bool = false) -> TapCountGhostPose? {
        guard let timed = timed(at: t) else { return nil }
        let span = max(timed.end - timed.start, 0.0001)
        let u = reduceMotion ? 1 : min(max((t - timed.start) / span, 0), 1)
        switch timed.step {
        case let .drive(stroke, from, to, _):
            let path = guide.paths[stroke]
            let d = from + (to - from) * u
            return TapCountGhostPose(point: path.point(at: d), angle: path.angle(at: min(d, path.length)), stroke: stroke,
                                     lift: 0, opacity: 1, hop: nil)
        case let .pause(stroke, at, _, _):
            let path = guide.paths[stroke]
            return TapCountGhostPose(point: path.point(at: at), angle: path.angle(at: at), stroke: stroke, lift: 0,
                                     opacity: 1, hop: nil)
        case let .hop(from, to, _):
            let p = guide.hopPoint(from: from, to: to, at: Self.ease(u))
            return TapCountGhostPose(point: p.point, angle: p.angle, stroke: to,
                                     lift: reduceMotion ? 0 : sin(Double.pi * u), opacity: 1, hop: (from, to))
        case .merge:
            guard let lastStroke = guide.beats.last?.stroke else { return nil }
            let path = guide.paths[lastStroke]
            let end = guide.beats.last?.end ?? path.length
            return TapCountGhostPose(point: path.point(at: end), angle: path.angle(at: end), stroke: lastStroke, lift: 0,
                                     opacity: reduceMotion ? 0.5 : 1 - u, hop: nil)
        }
    }

    /// The route driven by `t`, in short pieces with the time the car passed each one.
    public func route(at t: Double, reduceMotion: Bool = false) -> [TapCountRoutePiece] {
        var pieces: [TapCountRoutePiece] = []
        for timed in steps where timed.start <= t {
            guard case let .drive(stroke, from, to, _) = timed.step, to > from else { continue }
            let span = max(timed.end - timed.start, 0.0001)
            let u = reduceMotion ? 1 : min(max((t - timed.start) / span, 0), 1)
            let reached = from + (to - from) * u
            var a = from
            while a < reached - 0.01 {
                let b = min(reached, a + 24)
                let passed = timed.start + (b - from) / (to - from) * span
                pieces.append(TapCountRoutePiece(stroke: stroke, from: a, to: b, passedAt: passed))
                a = b
            }
        }
        return pieces
    }

    /// Cue signs the demo car is pausing at (the sign blinks while it waits).
    public func pausedCue(at t: Double) -> Int? {
        guard let timed = timed(at: t), case let .pause(_, _, cue, _) = timed.step else { return nil }
        return cue
    }
}

// MARK: - Help while the child traces (never a miss)

public enum TapCountGuideHelp: Equatable, Sendable {
    case none
    /// Pen down, no progress for the level's stall time: ring + ghost runs just the next bit.
    case stall(stroke: Int, from: Double, to: Double, since: Double)
    /// No progress for 8 s: the ghost drives to the end of the stroke.
    case ghostToEnd(stroke: Int, from: Double, to: Double, since: Double)
    /// No progress for 20 s, pen up: the prompt and the demo again.
    case redemo(since: Double)

    /// One key per help episode (the model notes each once).
    public var key: String? {
        switch self {
        case .none: return nil
        case let .stall(stroke, from, _, since): return "stall.\(stroke).\(Int(from)).\(Int(since * 10))"
        case let .ghostToEnd(stroke, from, _, since): return "ghost.\(stroke).\(Int(from)).\(Int(since * 10))"
        case let .redemo(since): return "redemo.\(Int(since * 10))"
        }
    }

    public var kind: String {
        switch self {
        case .none: return "none"
        case .stall: return "stall"
        case .ghostToEnd: return "ghost_to_end"
        case .redemo: return "redemo"
        }
    }
}

public enum TapCountGuideCoach {
    /// What help (if any) the board shows now. `readyAt` = when the child's turn began (the trace
    /// start, or the end of the latest demo).
    public static func help(plan: TapCountGuidePlan, guide: NumeralGuide, trace: ShapeTraceBoard, readyAt: Double,
                            now: Double) -> TapCountGuideHelp {
        guard !trace.isComplete, let path = trace.currentPath else { return .none }
        let stroke = trace.strokeIndex
        let lastMove = max(trace.lastProgressAt ?? -Double.infinity, readyAt)
        let idle = now - lastMove
        if let redemo = plan.redemoSeconds, idle >= redemo, !trace.dragging {
            return .redemo(since: lastMove + redemo)
        }
        if let ghost = plan.ghostToEndSeconds, idle >= ghost {
            return .ghostToEnd(stroke: stroke, from: trace.progress, to: path.length, since: lastMove + ghost)
        }
        if let stall = plan.stallSeconds, trace.dragging {
            let since = max(lastMove, trace.lastPenDownAt ?? -Double.infinity)
            if now - since >= stall {
                let to = min(path.length, max(guide.beatEnd(stroke: stroke, after: trace.progress), trace.progress + 40))
                return .stall(stroke: stroke, from: trace.progress, to: to, since: since + stall)
            }
        }
        return .none
    }

    /// The ghost car of a stall / ghost-to-end help at `now` (runs once, then hides).
    public static func ghostPose(_ help: TapCountGuideHelp, guide: NumeralGuide, now: Double,
                                 timing: TapCountGuideTiming = TapCountGuideData.timing,
                                 reduceMotion: Bool = false) -> TapCountGhostPose? {
        let run: (stroke: Int, from: Double, to: Double, since: Double, seconds: Double)
        switch help {
        case let .stall(s, f, t, at):
            run = (s, f, t, at, timing.stallRingGhostSeconds)
        case let .ghostToEnd(s, f, t, at):
            run = (s, f, t, at, max(0.6, (t - f) / guide.demoSpeed))
        case .none, .redemo:
            return nil
        }
        let (stroke, from, to, since, seconds) = run
        guard guide.paths.indices.contains(stroke) else { return nil }
        let u = (now - since) / seconds
        guard u >= 0, u <= 1.25 else { return nil }
        let path = guide.paths[stroke]
        let d = reduceMotion ? to : from + (to - from) * min(u, 1)
        return TapCountGhostPose(point: path.point(at: d), angle: path.angle(at: min(d, path.length)), stroke: stroke,
                                 lift: 0, opacity: u > 1 ? max(0, 1 - (u - 1) * 4) : 1, hop: nil)
    }

    /// Headlights: the next lane dots strictly ahead of the car's nose (never past the stroke end).
    public static let noseUnits: Double = 50

    public static func headlights(plan: TapCountGuidePlan, guide: NumeralGuide, trace: ShapeTraceBoard,
                                  count: Int = TapCountGuideData.timing.headlightDots) -> [Double] {
        guard plan.headlights, !trace.isComplete, let path = trace.currentPath else { return [] }
        let spacing = guide.dotSpacing
        guard spacing > 0 else { return [] }
        var m = (trace.progress + guide.noseUnits) / spacing
        m = m.rounded(.down) + 1
        var out: [Double] = []
        while out.count < count {
            let d = m * spacing
            guard d <= path.length - 4 else { break }
            out.append(d)
            m += 1
        }
        return out
    }

    /// The cue the car is approaching now (within the lead, until just past it).
    public static func activeCue(guide: NumeralGuide, trace: ShapeTraceBoard,
                                 lead: Double = TapCountGuideData.timing.cueLeadUnits) -> NumeralGuide.Cue? {
        guard !trace.isComplete else { return nil }
        return guide.cues(onStroke: trace.strokeIndex).first {
            trace.progress >= $0.distance - lead && trace.progress <= $0.distance + 30
        }
    }

    /// True for `seconds` after a stroke of a multi-stroke numeral finished (the hop to the next).
    public static func hopping(trace: ShapeTraceBoard, now: Double,
                               seconds: Double = TapCountGuideData.timing.hopSeconds) -> Double? {
        guard !trace.isComplete, trace.strokeIndex > 0, trace.progress < 0.5, let at = trace.lastProgressAt else { return nil }
        let u = (now - at) / seconds
        return u >= 0 && u < 1 ? u : nil
    }
}

// MARK: - A round's guidance state (lives in TapCountBoard)

public struct TapCountGuideRun: Equatable, Sendable {
    public let plan: TapCountGuidePlan
    public private(set) var demoStartedAt: Double?
    public private(set) var demoStoppedAt: Double?
    public private(set) var demosPlayed = 0
    public private(set) var demoSkips = 0
    /// When the child's turn began (trace start, demo end, or the touch that ended the demo).
    public private(set) var readyAt: Double
    public private(set) var helpKeys: [String] = []
    public private(set) var stalls = 0
    public private(set) var ghostsToEnd = 0
    public private(set) var redemos = 0
    public private(set) var otherHelps = 0
    public private(set) var cuesSaid: [Int] = []
    /// How long the piece on screen lasts: the car demo, or (v0.31.0) the pen's silent glance.
    public private(set) var demoDuration: Double
    /// The v0.30 car demo's length (the 20 s re-demo always uses the car).
    public let carDemoDuration: Double
    /// v0.31.0 筆順動畫: the pre-trace piece is the pen's glance, not the car (識咗 at 標準). Never both.
    public private(set) var isGlance = false
    public private(set) var glancesPlayed = 0
    public private(set) var glanceSkips = 0

    public init(plan: TapCountGuidePlan, demoDuration: Double, now: Double, demoLead: Double, glanceDuration: Double = 0) {
        self.plan = plan
        self.carDemoDuration = demoDuration
        self.demoDuration = demoDuration
        if plan.demo, demoDuration > 0 {
            demoStartedAt = now + demoLead
            demosPlayed = 1
            readyAt = now + demoLead + demoDuration
        } else if glanceDuration > 0 {
            // The car never plays when the glance does (stroke-order D3).
            self.demoDuration = glanceDuration
            isGlance = true
            glancesPlayed = 1
            demoStartedAt = now + demoLead
            readyAt = now + demoLead + glanceDuration
        } else {
            readyAt = now
        }
    }

    /// Seconds into the demo, while it plays.
    public func demoTime(now: Double) -> Double? {
        guard let start = demoStartedAt, demoStoppedAt == nil else { return nil }
        let t = now - start
        return t < demoDuration ? t : nil
    }

    /// The demo is on screen (its lead-in included): the first touch ends it.
    public func demoPending(now: Double) -> Bool {
        guard let start = demoStartedAt, demoStoppedAt == nil else { return false }
        return now < start + demoDuration
    }

    /// A touch during the demo ends it at once (input is never locked).
    @discardableResult
    public mutating func skipDemo(now: Double) -> Bool {
        guard demoPending(now: now) else { return false }
        demoStoppedAt = now
        if isGlance { glanceSkips += 1 } else { demoSkips += 1 }
        readyAt = now
        return true
    }

    public mutating func restartDemo(now: Double, lead: Double) {
        guard carDemoDuration > 0 else { return }
        isGlance = false
        demoDuration = carDemoDuration
        demoStartedAt = now + lead
        demoStoppedAt = nil
        demosPlayed += 1
        redemos += 1
        readyAt = now + lead + demoDuration
    }

    /// First time only. Any help means this trace is not clean (識咗 needs clean ones).
    @discardableResult
    public mutating func noteHelp(key: String, kind: String) -> Bool {
        guard !helpKeys.contains(key) else { return false }
        helpKeys.append(key)
        switch kind {
        case "stall": stalls += 1
        case "ghost_to_end": ghostsToEnd += 1
        case "redemo": break
        default: otherHelps += 1
        }
        return true
    }

    @discardableResult
    public mutating func noteCue(_ index: Int) -> Bool {
        guard !cuesSaid.contains(index) else { return false }
        cuesSaid.append(index)
        return true
    }

    public var clean: Bool { helpKeys.isEmpty }

    /// Seconds into the glance while the pen writes (nil for the car or when stopped).
    public func glanceTime(now: Double) -> Double? { isGlance ? demoTime(now: now) : nil }

    /// After a glance that played to the end: seconds since it ended (for the 1.5 s ink fade).
    public func glanceEndedFor(now: Double) -> Double? {
        guard isGlance, let start = demoStartedAt, demoStoppedAt == nil else { return nil }
        let dt = now - (start + demoDuration)
        return dt >= 0 ? dt : nil
    }

    public var demoCode: String {
        if demosPlayed == 0 {
            if glancesPlayed > 0 { return glanceSkips > 0 ? "glance_skipped" : "glance" }
            return "none"
        }
        return demoSkips > 0 ? "skipped" : "played"
    }
}

/// The guidance line in the voice bubble beside the trace board (cue / hop / stall), shown until `until`.
public struct TapCountGuideBubble: Equatable, Sendable {
    public let prompt: SpokenPrompt
    public let until: Double

    public init(prompt: SpokenPrompt, until: Double) {
        self.prompt = prompt
        self.until = until
    }
}
