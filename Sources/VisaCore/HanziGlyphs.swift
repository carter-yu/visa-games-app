import Foundation

// Hanzi H0 data pack: design hanzi-tap v2 (LOCKED 2026-11-03, D1–D12) plus the six-target addendum
// (2026-11-06). `Resources/HanziTap/hanzi-pack.json` holds the ordered centre lines in a 300 × 300 田字格 box
// (origin top-left), numbered starts, guide beats and cues, cue picture IDs, child copy and MOE provenance.
// Pure data: no game, board or setting reads it before H1. A glyph the pack does not name has no strokes;
// nothing falls back to another glyph.

/// A point written as `[x, y]` in the pack.
public struct HanziPoint: Decodable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        x = try values.decode(Double.self)
        y = try values.decode(Double.self)
        guard values.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: "a point has exactly two numbers")
        }
    }

    public var point: LineMatchPoint { LineMatchPoint(x: x, y: y) }
}

/// One line in HK Traditional Chinese and engineering English; optional small sub-lines.
public struct HanziText: Decodable, Equatable, Sendable {
    public let zhHK: String
    public let en: String
    public let zhHKSub: String?
    public let enSub: String?
}

/// A numbered start (D10). Only the current ordered start accepts input; the review overview may move the
/// label by `reviewLabelOffset` with a leader back to the real start, which never moves.
public struct HanziStartMarker: Decodable, Equatable, Sendable {
    public let label: String
    public let anchor: HanziPoint
    public let reviewLabelOffset: HanziPoint?
    public let leaderToActualStart: Bool?
}

/// One pen-down stroke: centre line in writing direction plus its 筆劃 name.
public struct HanziStroke: Decodable, Equatable, Sendable {
    public static let kinds: Set<String> = ["橫", "豎", "撇", "捺", "點", "橫折"]

    public let n: Int
    public let type: String
    public let typeEn: String
    public let svg: String
    public let start: HanziPoint
    public let end: HanziPoint
    /// True turns inside the stroke (右 stroke 4 only); a STOP sign may only sit on one of these (D11).
    public let corners: [HanziPoint]
    /// Targets only; find-only glyphs are never written.
    public let marker: HanziStartMarker?

    enum CodingKeys: String, CodingKey { case n, type, typeEn, svg, start, end, corners, marker }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        n = try values.decode(Int.self, forKey: .n)
        type = try values.decode(String.self, forKey: .type)
        typeEn = try values.decode(String.self, forKey: .typeEn)
        svg = try values.decode(String.self, forKey: .svg)
        start = try values.decode(HanziPoint.self, forKey: .start)
        end = try values.decode(HanziPoint.self, forKey: .end)
        corners = try values.decodeIfPresent([HanziPoint].self, forKey: .corners) ?? []
        marker = try values.decodeIfPresent(HanziStartMarker.self, forKey: .marker)
    }
}

/// A point on a stroke and which time the stroke passes nearest to it.
public struct HanziGuidePoint: Decodable, Equatable, Sendable {
    public let point: HanziPoint
    public let pass: Int
}

public struct HanziGuideBeat: Decodable, Equatable, Sendable {
    /// Zero-based stroke index.
    public let stroke: Int
    /// Nil = the end of the stroke (`"end"` in the pack).
    public let until: HanziGuidePoint?
    public let seconds: Double
    public let line: HanziText

    enum CodingKeys: String, CodingKey { case stroke, until, seconds, line }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stroke = try values.decode(Int.self, forKey: .stroke)
        seconds = try values.decode(Double.self, forKey: .seconds)
        line = try values.decode(HanziText.self, forKey: .line)
        if let word = try? values.decode(String.self, forKey: .until) {
            guard word == "end" else {
                throw DecodingError.dataCorruptedError(forKey: .until, in: values,
                                                       debugDescription: "until is \"end\" or a point")
            }
            until = nil
        } else {
            until = try values.decode(HanziGuidePoint.self, forKey: .until)
        }
    }
}

public enum HanziCueSign: String, Decodable, Sendable {
    case ahead, stop
}

public struct HanziGuideCue: Decodable, Equatable, Sendable {
    public let stroke: Int
    public let point: HanziPoint
    public let pass: Int
    public let sign: HanziCueSign
    /// Sign centre in glyph units; clearance is validated in H3.
    public let signAt: HanziPoint
    public let line: HanziText
    public let status: String
}

/// 右's 橫折: one pen-down stroke that pauses once at the corner (H3 adapter).
public struct HanziCornerContract: Decodable, Equatable, Sendable {
    public let strokeOneBased: Int
    public let point: HanziPoint
    public let penDownContinuous: Bool
    public let newStartAtCorner: Bool
    public let demoPauseSeconds: Double
    public let pauseExactlyOnce: Bool
    public let aheadMustNotPause: Bool
}

public struct HanziGuide: Decodable, Equatable, Sendable {
    public let beats: [HanziGuideBeat]
    public let merge: HanziText
    public let cues: [HanziGuideCue]
    public let lastStroke: HanziText
    public let hop: HanziText
    public let cornerContract: HanziCornerContract?
}

/// MOE stroke tracks used to author a centre line: each stroke's track start and end in the MOE 2048 grid,
/// and the uniform map into the 300 × 300 box.
public struct HanziMOETrack: Decodable, Equatable, Sendable {
    public struct Map: Decodable, Equatable, Sendable {
        public let scale: Double
        public let from: HanziPoint
        public let to: HanziPoint
    }

    public let map: Map
    public let ends: [[HanziPoint]]

    public func mapped(_ p: HanziPoint) -> LineMatchPoint {
        LineMatchPoint(x: map.to.x + (p.x - map.from.x) * map.scale, y: map.to.y + (p.y - map.from.y) * map.scale)
    }
}

public struct HanziMOESource: Decodable, Equatable, Sendable {
    public let page: String
    public let strokeData: String
    public let strokeCount: Int
    public let retrieved: String
    /// What was compared with MOE: "count", "order" and, with `track`, "shape".
    public let checked: [String]
    public let note: String
    public let track: HanziMOETrack?
}

/// 左 / 右 picture cards: the child's own hand plus a red direction arrow (D7).
public struct HanziMeaningCue: Decodable, Equatable, Sendable {
    public let zhHK: String
    public let referenceFrame: String
    public let directionArrow: String
}

/// 右's 口 inset (D12): strokes 3 and 4 share one start with separate labelled leaders.
public struct HanziMouthInset: Decodable, Equatable, Sendable {
    public let strokesOneBased: [Int]
    public let stepLabels: [String]
    public let directions: [String]
    public let sharedStart: HanziPoint
    public let sharedStartStrokes: [Int]
    public let sharedStartLabels: [String]
    public let separateLabelLeaders: Bool
    public let stopCorner: HanziPoint
    public let noLiftAtCorner: Bool
}

/// A week target: written and found.
public struct HanziCharacter: Decodable, Equatable, Sendable {
    public let id: String
    public let jyutping: String
    public let voiceKey: String
    public let meaning: HanziText
    public let meaningCue: HanziMeaningCue?
    /// Two `illustrations.svg` symbol IDs for the flipped card and the write screen.
    public let cuePictures: [String]
    public let sourceStatus: String
    public let strokes: [HanziStroke]
    public let guide: HanziGuide
    public let mouthInset: HanziMouthInset?
    public let moeSource: HanziMOESource
}

/// A find-only distractor: never a target, never written, no writing progress (D2).
public struct HanziFindOnly: Decodable, Equatable, Sendable {
    public let id: String
    public let jyutping: String
    public let voiceKey: String
    public let meaning: HanziText
    public let confusableWith: [String]
    public let approval: String
    /// The design requires a display form to pass H0 review before a deal shows it.
    public let displayFormVerified: Bool
    public let displayFormNote: String
    public let sourceStatus: String
    /// Display centre lines for the card face.
    public let strokes: [HanziStroke]
    public let moeSource: HanziMOESource
}

public struct HanziBoardSpec: Decodable, Equatable, Sendable {
    public struct Scheduler: Decodable, Equatable, Sendable {
        public let cycleTargetsOnceBeforeShuffle: Bool
        public let noImmediateTargetRepeat: Bool
        public let retryAfterInterveningRounds: Int
        public let reviewEveryRounds: Int
        public let balancedSet: String
    }

    public let rows: Int
    public let columns: Int
    public let targetCards: Int
    public let oneTargetPerRow: Bool
    public let symbolsPerRow: Int
    public let distinctRows: Bool
    public let distinctTargetColumns: Bool
    public let targetWeek: [String]
    public let approvedFindOnlyPool: [String]
    public let confusablePairs: [[String]]
    public let rowSetRule: String
    public let guardMode: String
    public let findOnlyDealRule: String
    public let scheduler: Scheduler
}

/// Defaults a fresh or unreadable Hanzi setting falls back to: both games and jyutping OFF, 廣東話語音 ON (Carter
/// 2026-11-13 overrode D4's audio default).
public struct HanziPackDefaults: Decodable, Equatable, Sendable {
    public let week: [String]
    public let findEnabled: Bool
    public let writeEnabled: Bool
    public let audioEnabled: Bool
    public let jyutpingEnabled: Bool
    public let reviewEveryRounds: Int
    public let confusableGuard: Bool
    public let grid: String
    public let miziGridEnabled: Bool
    public let guideLevel: TapCountGuidanceLevel
    public let strokeOrder: String
    public let unlockStarsAfterOwnPlaytest: Bool
}

public struct HanziPack: Decodable, Equatable, Sendable {
    public static let schemaID = "visagames.hanziPack.v1"

    public struct CoordinateSystem: Decodable, Equatable, Sendable {
        public let width: Double
        public let height: Double
        public let origin: String
    }

    public struct CueArt: Decodable, Equatable, Sendable {
        public let sprite: String
        public let stylesheet: String
        public let viewBox: String
    }

    public let schema: String
    public let status: String
    public let coordinateSystem: CoordinateSystem
    public let cueArt: CueArt
    public let defaults: HanziPackDefaults
    public let board: HanziBoardSpec
    public let characters: [String: HanziCharacter]
    public let findOnly: [String: HanziFindOnly]
    public let copy: [String: HanziText]

    public enum LoadError: Error, Equatable {
        case invalidSchema(String)
        case missingResource
        case invalid([String])
    }

    /// Decodes and checks a pack; any problem fails the whole load (no partial pack).
    public static func load(data: Data) throws -> HanziPack {
        let pack = try JSONDecoder().decode(HanziPack.self, from: data)
        guard pack.schema == schemaID else { throw LoadError.invalidSchema(pack.schema) }
        let problems = pack.problems
        guard problems.isEmpty else { throw LoadError.invalid(problems) }
        return pack
    }

    public static func load(url: URL) throws -> HanziPack {
        try load(data: Data(contentsOf: url))
    }

    public static func loadBundled() throws -> HanziPack {
        guard let url = Bundle.main.url(forResource: "hanzi-pack", withExtension: "json", subdirectory: "HanziTap") else {
            throw LoadError.missingResource
        }
        return try load(url: url)
    }

    public func isTarget(_ glyph: String) -> Bool { characters[glyph] != nil }
    public func isFindOnly(_ glyph: String) -> Bool { findOnly[glyph] != nil }

    /// Centre lines of a target or find-only glyph; empty for anything else.
    public func strokes(of glyph: String) -> [HanziStroke] {
        characters[glyph]?.strokes ?? findOnly[glyph]?.strokes ?? []
    }

    /// Find-only glyphs a deal may show: approved and with a verified display form, in pool order.
    public var dealableFindOnly: [String] {
        board.approvedFindOnlyPool.filter { findOnly[$0]?.displayFormVerified == true }
    }

    /// Reference and geometry invariants the H1+ consumers rely on. Empty for a usable pack.
    public var problems: [String] {
        var found: [String] = []
        func check(_ condition: Bool, _ message: @autoclosure () -> String) {
            if !condition { found.append(message()) }
        }
        let week = board.targetWeek
        let pool = board.approvedFindOnlyPool
        check(coordinateSystem.width == HanziGlyphs.boxSize.width && coordinateSystem.height == HanziGlyphs.boxSize.height
              && coordinateSystem.origin == "top-left", "coordinate system")
        check(defaults.week == week, "defaults.week differs from board.targetWeek")
        check(!week.isEmpty && Set(week).count == week.count, "week glyphs empty or repeated")
        // The fallback for a short parent week (`HanziTapSettings.validWeek`) must itself be long enough.
        check(week.count >= HanziScheduler.minimumWeek, "fewer than \(HanziScheduler.minimumWeek) week targets")
        check(Set(pool).count == pool.count, "find-only pool repeats a glyph")
        check(Set(week).isDisjoint(with: pool), "a glyph is both target and find-only")
        check(Set(characters.keys) == Set(week), "characters do not match the week")
        check(Set(findOnly.keys) == Set(pool), "find-only entries do not match the pool")
        check(board.columns == board.symbolsPerRow, "a row must hold symbolsPerRow distinct glyphs")
        check(!board.oneTargetPerRow || board.targetCards == board.rows, "one target per row")
        check(board.symbolsPerRow <= week.count + pool.count, "not enough glyphs for a row")
        let known = Set(week + pool)
        for pair in board.confusablePairs {
            check(pair.count == 2 && pair[0] != pair[1] && pair.allSatisfy(known.contains)
                  && pair.contains(where: week.contains), "confusable pair \(pair)")
        }
        for (glyph, entry) in findOnly {
            check(!entry.confusableWith.isEmpty && entry.confusableWith.allSatisfy { target in
                week.contains(target) && board.confusablePairs.contains { Set($0) == [glyph, target] }
            }, "\(glyph) confusableWith")
            check(entry.id == "hanzi:\(glyph)", "\(glyph) id")
            found += Self.strokeProblems(glyph, entry.strokes, moe: entry.moeSource, box: coordinateSystem)
        }
        for (glyph, entry) in characters {
            check(entry.id == "hanzi:\(glyph)", "\(glyph) id")
            check(!entry.cuePictures.isEmpty && Set(entry.cuePictures).count == entry.cuePictures.count,
                  "\(glyph) cue pictures")
            found += Self.strokeProblems(glyph, entry.strokes, moe: entry.moeSource, box: coordinateSystem)
            for stroke in entry.strokes {
                check(stroke.marker?.label == "\(stroke.n)" && stroke.marker.map {
                    $0.anchor.point.distance(to: stroke.start.point) < 0.5 } == true, "\(glyph) marker \(stroke.n)")
            }
            let count = entry.strokes.count
            let beats = entry.guide.beats
            check(!beats.isEmpty && beats.allSatisfy { (0..<count).contains($0.stroke) && $0.seconds > 0 },
                  "\(glyph) beats")
            check(zip(beats, beats.dropFirst()).allSatisfy { $0.stroke <= $1.stroke }, "\(glyph) beats in order")
            for index in 0..<count {
                check(beats.last(where: { $0.stroke == index }).map { $0.until == nil } == true,
                      "\(glyph) stroke \(index + 1) needs a beat that ends it")
            }
            for cue in entry.guide.cues {
                check((0..<count).contains(cue.stroke), "\(glyph) cue stroke")
                if cue.sign == .stop, (0..<count).contains(cue.stroke) {
                    check(entry.strokes[cue.stroke].corners.contains { $0.point.distance(to: cue.point.point) < 0.5 },
                          "\(glyph) STOP is only allowed at a true turn")
                }
            }
        }
        for (key, line) in copy {
            check(!line.zhHK.isEmpty && !line.en.isEmpty, "copy \(key)")
        }
        return found
    }

    private static func strokeProblems(_ glyph: String, _ strokes: [HanziStroke], moe: HanziMOESource,
                                       box: CoordinateSystem) -> [String] {
        var found: [String] = []
        if glyph.count != 1 { found.append("\(glyph) is not one character") }
        if strokes.isEmpty { found.append("\(glyph) has no strokes") }
        if moe.strokeCount != strokes.count { found.append("\(glyph) stroke count \(strokes.count) vs MOE \(moe.strokeCount)") }
        if let track = moe.track, track.ends.count != strokes.count || track.ends.contains(where: { $0.count != 2 }) {
            found.append("\(glyph) MOE track ends")
        }
        for (index, stroke) in strokes.enumerated() {
            let name = "\(glyph) stroke \(index + 1)"
            if stroke.n != index + 1 { found.append("\(name) numbered \(stroke.n)") }
            if !HanziStroke.kinds.contains(stroke.type) { found.append("\(name) kind \(stroke.type)") }
            guard let commands = try? SVGPathData.parse(stroke.svg), case .move? = commands.first,
                  commands.dropFirst().allSatisfy({ if case .move = $0 { return false } else { return true } }),
                  commands.count > 1 else {
                found.append("\(name) path is not one subpath")
                continue
            }
            let path = TracePath(svg: stroke.svg, corners: stroke.corners.map(\.point))
            if path.start.distance(to: stroke.start.point) > 0.5 || path.end.distance(to: stroke.end.point) > 0.5 {
                found.append("\(name) start/end differ from the path")
            }
            if path.corners.count != stroke.corners.count { found.append("\(name) corner is not a path join") }
            if !path.points.allSatisfy({ (0...box.width).contains($0.x) && (0...box.height).contains($0.y) }) {
                found.append("\(name) leaves the box")
            }
        }
        return found
    }
}

/// Glyph-box constants and trace paths for pack glyphs (the Hanzi counterpart of `LatinGlyphs`).
public enum HanziGlyphs {
    public static let boxSize = (width: 300.0, height: 300.0)
    /// Proposed lane width (design geometryTuningProposed); to be tuned on the Mac mini in H3.
    public static let laneWidth: Double = 36

    /// Centre lines mapped by `scale` then `offset`, with their true turns; empty for an unknown glyph.
    public static func paths(_ glyph: String, in pack: HanziPack, offset: LineMatchPoint = LineMatchPoint(x: 0, y: 0),
                             scale: Double = 1) -> [TracePath] {
        pack.strokes(of: glyph).map {
            TracePath(svg: $0.svg, scale: scale, offset: offset, corners: $0.corners.map(\.point))
        }
    }
}

// MARK: - Glyph / guide adapters (H1): pack targets as the shared stroke-order and guide types

extension StrokeGlyph {
    /// A target for the shared stroke-order player (stroke-order D11, D14), as `latin(_:)`: `hanzi:<glyph>` id and
    /// progress key, the 300 × 300 box, the pack's strokes in MOE order (D5) with their 筆劃 kind, and a turn only
    /// at a declared true corner (右's 橫折). Nil for a find-only or unknown glyph: it is never written.
    public static func hanzi(_ glyph: String, in pack: HanziPack) -> StrokeGlyph? {
        guard let character = pack.characters[glyph] else { return nil }
        let paths = HanziGlyphs.paths(glyph, in: pack)
        guard !paths.isEmpty, paths.count == character.strokes.count else { return nil }
        let strokes = zip(paths, character.strokes).map { path, stroke in
            Stroke(path: path, turns: path.corners.filter { $0 > 0.5 && $0 < path.length - 0.5 }, kind: stroke.type)
        }
        return StrokeGlyph(id: "hanzi:\(glyph)", script: .hanzi, strokes: strokes, box: HanziGlyphs.boxSize,
                           progressKey: "hanzi:\(glyph)", orderStandard: "MOE")
    }
}

/// The Hanzi counterpart of `LetterGuideData.letter`: a target's pack guide as the shared `NumeralGuideSpec`
/// (beats, merge line, AHEAD / STOP cues, hop and last-stroke lines), in pack order. `zh` / `zhSub` are the pack's
/// HK Traditional `zhHK` / `zhHKSub`; `en` is its engineering English. Nil for a find-only or unknown glyph. The 田字格
/// placement and the write round are `HanziWriteBoard` / `TapHanziWriteRound` (H3).
public enum HanziGuideData {
    /// The compact board style every Hanzi guide carries (design hanzi-tap v2 `styles.compactBoard`, the letter
    /// board's values): 0.6 car, 42-unit nose, 0.7 chevrons, 30-unit lane dots, STOP 0.8. AHEAD is 0.8 rather than the
    /// letters' 1.0: at 1.0 the locked 上 / 左 sign centres (y 282) put the sign outside the 300 × 300 box (H3).
    public static let board = LetterBoardGuideStyle(laneScale: LetterGuideData.board.laneScale, carScale: 0.6,
                                                    noseUnits: 42, chevScale: 0.7, laneDotSpacing: 30,
                                                    stopSignScale: 0.8, aheadSignScale: 0.8)
    /// Route, beam, stall-ring and glow widths in stage units: the letter board's (design `styles`: route 19 / 6 with a
    /// 9 / 7 dash, beam 30 / 12, ring 40).
    public static let styles = LetterGuideData.styles

    public static func spec(_ glyph: String, in pack: HanziPack) -> NumeralGuideSpec? {
        guard let guide = pack.characters[glyph]?.guide else { return nil }
        func line(_ text: HanziText) -> TapCountGuideLine {
            TapCountGuideLine(zh: text.zhHK, zhSub: text.zhHKSub ?? "", en: text.en, enSub: text.enSub ?? "")
        }
        func point(_ p: HanziPoint, pass: Int) -> NumeralGuidePoint { NumeralGuidePoint(x: p.x, y: p.y, pass: pass) }
        let beats = guide.beats.map {
            NumeralGuideBeatSpec(stroke: $0.stroke, until: $0.until.map { point($0.point, pass: $0.pass) },
                                 seconds: $0.seconds, line: line($0.line))
        }
        let cues = guide.cues.map {
            NumeralGuideCueSpec(stroke: $0.stroke, point: point($0.point, pass: $0.pass),
                                sign: $0.sign == .stop ? .stop : .ahead, signAt: $0.signAt.point, line: line($0.line))
        }
        return NumeralGuideSpec(numeral: 0, beats: beats, merge: line(guide.merge), cues: cues, hop: line(guide.hop),
                                hopSide: nil, lastStroke: line(guide.lastStroke))
    }
}
