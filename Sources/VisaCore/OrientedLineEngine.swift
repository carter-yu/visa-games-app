import Foundation

// 畫直線・四方 pen rule `connectedCoverage` (four-direction design §5.1–5.4), for the new kind only: 畫直線 · 熱身 and
// every other trace keep `ShapeTraceBoard` exactly as it was. Progress s runs from 0 at the actual green start to L at
// the actual red finish, so nothing here uses screen x or y: moving left is forward on ← and ↙.
//
// The frontier F (0 ≤ F ≤ L) is the road swept forward while joined; it never goes down and the car's nose sits on it.
// A segment (one pen-down, or a slide into the corridor) joins at its first sample on earned road (s ≤ F, the green
// sign included) and only then earns: each joined sample with s > F sets F = min(L, s). Joining credits nothing; drawing
// before the join never counts and its ink stays faded forever. Lift, a lateral exit, a system cancel, a jump of more
// than 150 u along the line, or a refused touch end the segment and keep F. The line is done at the joined forward sample
// that makes F ≥ L − 10, and only there. Backtracking is neutral. Nothing is ever wrong: refusals are coached, counted
// and never a miss. Pure value: the view runs it on a local copy per pen event and hands it over on pen-up and when a
// line finishes. Raw pen points are kept in memory for drawing only, never in results or logs.

public enum OrientedLinePenDown: Sendable, Equatable {
    /// On the green sign, the car or earned road (s ≤ F): a joined segment; nothing is credited until s passes F.
    case joined
    /// In the corridor ahead of F (even by 1 u): an unjoined segment; it earns only once it slides back onto earned road.
    case unjoined
    /// Outside the judged corridor: nothing; sliding in starts a segment at the entry point.
    case outside
    /// The red sign or the finish zone with F < 10: refused (`lines.reverse`), inert until lift.
    case refusedReverse
    /// The same with the car mid-line: refused (`lines.earlyFinish`), inert until lift.
    case refusedEarlyFinish
    /// Everything is drawn.
    case ignored
}

/// Why a segment ended while the pen stayed down.
public enum OrientedLineBreak: Sendable, Equatable {
    /// A lateral exit from the judged corridor (counted in `off_path_count`).
    case offRoad
    /// Past either sign centre along the line (not a lateral exit; not counted).
    case beyondEnd
    /// More than 150 u along the line from the last sample: the later sample starts a new segment.
    case gap
}

public enum OrientedLineMove: Sendable, Equatable {
    /// A joined forward sample moved F.
    case earned
    /// Nothing changed (backtracking, waiting at F, an unjoined sweep, still outside).
    case neutral
    /// The segment joined here (it earns from the next forward sample).
    case joined
    case segmentEnded(OrientedLineBreak)
    /// A line is done; more lines follow.
    case lineDone(Int)
    /// The last line is done.
    case allDone
    case ignored
}

/// The pen's segment state.
public enum OrientedLineSegment: Sendable, Equatable {
    /// Pen up, or down outside the corridor after an exit or an outside touch.
    case none
    case unjoined
    case joined
    /// A refused touch: inert until lift.
    case refused
    /// The touch that finished a line: inert until lift (the next line needs its own pen-down).
    case finished
}

/// Why the 2 s ring shows on the car.
public enum OrientedLineAway: Sendable, Equatable {
    /// The pen left the road: `trace.offroad`, once per line.
    case offRoad
    /// The pen is down but not joined: `lines.wrongStart` at F = 0, else `lines.pause`.
    case notJoined
}

/// One ink sample: where the pen was, and whether it was drawn while joined (normal navy) or not (faded, forever).
public struct OrientedInkSample: Sendable, Equatable {
    public let point: LineMatchPoint
    public let counted: Bool

    public init(point: LineMatchPoint, counted: Bool) {
        self.point = point
        self.counted = counted
    }
}

/// Practice stats of one line (`per_shape` row).
public struct OrientedLineStats: Sendable, Equatable {
    public var deviationSum = 0.0
    public var deviationSamples = 0
    public var maxDeviation = 0.0
    public var lifts = 0
    public var offPath = 0
    public var reverseDirections = 0
    public var wrongStarts = 0
    public var earlyFinishTaps = 0
    public var startedAt: Double?
    public var finishedAt: Double?

    public init() {}

    public var meanDeviation: Double? { deviationSamples > 0 ? deviationSum / Double(deviationSamples) : nil }
}

public struct OrientedLineBoard: Sendable, Equatable {
    /// A sample this far along the line from the previous one ends the segment (PROVISIONAL).
    public static let sampleGap: Double = 150
    /// The ring after this long away (today's hint time).
    public static let hintAfterSeconds: Double = 2
    /// A lift counts once the car has left the start.
    public static let liftMinimum: Double = 0.5
    /// Ink: one point every 4 u, capped per line (memory only, for drawing).
    public static let inkSpacing: Double = 4
    public static let inkPointCap = 4000

    public let question: OrientedLineQuestion

    public private(set) var lineIndex = 0
    /// F on the current line.
    public private(set) var frontier = 0.0
    public private(set) var segment: OrientedLineSegment = .none
    public private(set) var penIsDown = false
    /// s of the segment's last sample (the gap check).
    public private(set) var lastS: Double?
    /// The pen has been down without a joined segment since then (the 2 s ring).
    public private(set) var awaySince: Double?
    /// The pen left the road at this time and has not re-entered (`trace.offroad`).
    public private(set) var offRoadSince: Double?
    /// When F last moved, or the current line became current.
    public private(set) var lastProgressAt: Double?
    /// When the current joined segment joined (the pause timer starts at the later of this and the last progress).
    public private(set) var joinedAt: Double?
    public private(set) var lastPenDownAt: Double?
    public private(set) var strokes = 0
    public private(set) var unjoinedSegments = 0
    public private(set) var segmentGaps = 0
    public private(set) var offPathCount = 0
    public private(set) var lifts = 0
    public private(set) var reverseDirections = 0
    public private(set) var wrongStarts = 0
    public private(set) var earlyFinishTaps = 0
    /// Largest |Δs| between two samples of a segment (playtest diagnostics, U3).
    public private(set) var maxSampleGap = 0.0
    public private(set) var lineStats: [OrientedLineStats]
    /// Ink per line: one polyline per segment or touch.
    public private(set) var ink: [[[OrientedInkSample]]]
    public private(set) var startedAt: Double?
    public private(set) var finishedAt: Double?

    public init(question: OrientedLineQuestion) {
        self.question = question
        lineStats = question.lines.map { _ in OrientedLineStats() }
        ink = question.lines.map { _ in [] }
    }

    public var lines: [OrientedLine] { question.lines }
    public var isComplete: Bool { !lines.isEmpty && lineIndex >= lines.count }
    public var currentLine: OrientedLine? { isComplete ? nil : lines[lineIndex] }
    public var remainingLines: Int { max(0, lines.count - lineIndex) }
    /// Judged half-width from the dealt 畫線寬容度 (never the live setting).
    public var halfWidth: Double { question.halfWidth }

    public func isDone(line: Int) -> Bool { line < lineIndex }

    /// The car's nose: F on the current line.
    public var carPoint: LineMatchPoint? { currentLine?.point(at: frontier) }

    /// The 2 s ring, and why (nil when nothing is due).
    public func away(now: Double) -> OrientedLineAway? {
        guard penIsDown, !isComplete else { return nil }
        if segment == .none, let since = offRoadSince, now - since >= Self.hintAfterSeconds { return .offRoad }
        if segment == .none || segment == .unjoined, let since = awaySince, now - since >= Self.hintAfterSeconds {
            return .notJoined
        }
        return nil
    }

    // MARK: Pen events

    public mutating func penDown(at p: LineMatchPoint, now: Double) -> OrientedLinePenDown {
        endSegment()
        guard let line = currentLine else { return .ignored }
        penIsDown = true
        strokes += 1
        lastPenDownAt = now
        if startedAt == nil { startedAt = now }
        if lastProgressAt == nil { lastProgressAt = now }
        if lineStats[lineIndex].startedAt == nil { lineStats[lineIndex].startedAt = now }
        let s = line.progress(of: p)
        let inside = line.isInside(p, halfWidth: halfWidth)
        // The red sign or the finish zone: refused, whatever any old switch says; never driven backwards.
        if frontier < line.completion, line.onRedSign(p) || (inside && s >= line.completion) {
            segment = .refused
            reverseDirections += 1
            wrongStarts += 1
            lineStats[lineIndex].reverseDirections += 1
            lineStats[lineIndex].wrongStarts += 1
            if frontier < OrientedLine.finishBand { return .refusedReverse }
            earlyFinishTaps += 1
            lineStats[lineIndex].earlyFinishTaps += 1
            return .refusedEarlyFinish
        }
        if line.onGreenSign(p) || (inside && s <= frontier) {
            beginSegment(joined: true, s: s, now: now)
            addInk(p, counted: true, newStroke: true)
            return .joined
        }
        addInk(p, counted: false, newStroke: true)
        awaySince = now
        if inside {
            beginSegment(joined: false, s: s, now: now)
            return .unjoined
        }
        return .outside
    }

    public mutating func penMove(to p: LineMatchPoint, now: Double) -> OrientedLineMove {
        guard penIsDown, let line = currentLine, segment != .refused, segment != .finished else { return .ignored }
        let s = line.progress(of: p)
        let inside = line.isInside(p, halfWidth: halfWidth)
        if segment == .none {
            guard inside else {
                addInk(p, counted: false, newStroke: false)
                return .neutral
            }
            // Sliding in: a segment starts at the entry point, joined only on earned road.
            let joined = s <= frontier || line.onGreenSign(p)
            beginSegment(joined: joined, s: s, now: now)
            addInk(p, counted: joined, newStroke: true)
            return joined ? .joined : .neutral
        }
        guard inside else {
            let lateral = abs(line.lateral(of: p)) > halfWidth
            if lateral {
                offPathCount += 1
                lineStats[lineIndex].offPath += 1
                offRoadSince = now
            }
            segment = .none
            lastS = nil
            joinedAt = nil
            if awaySince == nil { awaySince = now }
            addInk(p, counted: false, newStroke: true)
            return .segmentEnded(lateral ? .offRoad : .beyondEnd)
        }
        if let last = lastS {
            let step = abs(s - last)
            maxSampleGap = max(maxSampleGap, step)
            if step > Self.sampleGap {
                segmentGaps += 1
                let joined = s <= frontier
                beginSegment(joined: joined, s: s, now: now)
                if !joined, awaySince == nil { awaySince = now }
                addInk(p, counted: joined, newStroke: true)
                return .segmentEnded(.gap)
            }
        }
        lastS = s
        if segment == .unjoined {
            guard s <= frontier else {
                addInk(p, counted: false, newStroke: false)
                return .neutral
            }
            // Actual overlap with earned road, no tolerance: it joins here and credits nothing.
            segment = .joined
            joinedAt = now
            awaySince = nil
            offRoadSince = nil
            addInk(p, counted: true, newStroke: false)
            return .joined
        }
        let d = abs(line.lateral(of: p))
        lineStats[lineIndex].deviationSum += d
        lineStats[lineIndex].deviationSamples += 1
        lineStats[lineIndex].maxDeviation = max(lineStats[lineIndex].maxDeviation, d)
        addInk(p, counted: true, newStroke: false)
        guard s > frontier else { return .neutral }
        frontier = min(line.length, s)
        lastProgressAt = now
        guard frontier >= line.completion else { return .earned }
        return finishLine(now: now)
    }

    /// Pen up: the segment ends, F is kept; a joined segment that has moved the car counts one lift.
    public mutating func penUp() {
        if segment == .joined, frontier > Self.liftMinimum, !isComplete {
            lifts += 1
            lineStats[lineIndex].lifts += 1
        }
        endSegment()
    }

    /// System cancel or the parent lock: like a lift, but never counted.
    public mutating func cancelStroke() {
        endSegment()
    }

    private mutating func endSegment() {
        segment = .none
        penIsDown = false
        lastS = nil
        awaySince = nil
        offRoadSince = nil
        joinedAt = nil
    }

    private mutating func beginSegment(joined: Bool, s: Double, now: Double) {
        segment = joined ? .joined : .unjoined
        lastS = s
        if joined {
            joinedAt = now
            awaySince = nil
            offRoadSince = nil
        } else {
            unjoinedSegments += 1
        }
    }

    private mutating func finishLine(now: Double) -> OrientedLineMove {
        let index = lineIndex
        lineStats[index].finishedAt = now
        segment = .finished
        lastS = nil
        awaySince = nil
        offRoadSince = nil
        joinedAt = nil
        lineIndex += 1
        frontier = 0
        lastProgressAt = now
        if isComplete {
            finishedAt = now
            return .allDone
        }
        return .lineDone(index)
    }

    private var inkCount: Int { ink.indices.contains(lineIndex) ? ink[lineIndex].reduce(0) { $0 + $1.count } : 0 }

    private mutating func addInk(_ p: LineMatchPoint, counted: Bool, newStroke: Bool) {
        guard ink.indices.contains(lineIndex), inkCount < Self.inkPointCap else { return }
        let sample = OrientedInkSample(point: p, counted: counted)
        if newStroke || ink[lineIndex].isEmpty {
            ink[lineIndex].append([sample])
            return
        }
        let last = ink[lineIndex].count - 1
        // Spacing keeps memory small; a change of counted state always starts its own point.
        if let previous = ink[lineIndex][last].last, previous.counted == counted,
           previous.point.distance(to: p) < Self.inkSpacing { return }
        ink[lineIndex][last].append(sample)
    }

    // MARK: Commits

    /// Lines finished so far plus F: what can only grow.
    public func isMonotonicSuccessor(of older: OrientedLineBoard) -> Bool {
        guard question == older.question, lineIndex >= older.lineIndex else { return false }
        if lineIndex == older.lineIndex {
            guard frontier >= older.frontier, inkCount >= older.inkCount else { return false }
        }
        return strokes >= older.strokes && offPathCount >= older.offPathCount && lifts >= older.lifts
            && wrongStarts >= older.wrongStarts && reverseDirections >= older.reverseDirections
            && earlyFinishTaps >= older.earlyFinishTaps && unjoinedSegments >= older.unjoinedSegments
            && segmentGaps >= older.segmentGaps
    }

    // MARK: Stats (practice; never mastery evidence)

    public var meanDeviation: Double? {
        let samples = lineStats.reduce(0) { $0 + $1.deviationSamples }
        guard samples > 0 else { return nil }
        return lineStats.reduce(0) { $0 + $1.deviationSum } / Double(samples)
    }

    /// The oriented kinds drawn (one exposure each).
    public var exposures: [String] {
        lines.prefix(min(lineIndex, lines.count)).map(\.variant.factToken)
    }

    /// `per_shape` rows in 畫直線 · 熱身's columns, per oriented variant:
    /// `kind:mean_dev:max_dev:lifts:off_path:overshoot:cut:end_overshoot:reverse:wrong_start:ms` (no corners: 0).
    public var perShapeRows: [String] {
        lines.indices.map { index in
            let s = lineStats[index]
            let mean = s.meanDeviation.map { String(format: "%.1f", $0) } ?? ""
            let ms = (s.startedAt != nil && s.finishedAt != nil)
                ? String(Int((((s.finishedAt ?? 0) - (s.startedAt ?? 0)) * 1000).rounded())) : ""
            return [lines[index].variant.factToken, mean, String(format: "%.1f", s.maxDeviation), String(s.lifts),
                    String(s.offPath), "0", "0", "0", String(s.reverseDirections), String(s.wrongStarts), ms]
                .joined(separator: ":")
        }
    }

    /// `round_result` fields: 畫直線 · 熱身's practice fields, `off_path_count` as lateral exits (`trace_rule`), and the
    /// new diagnostics. `max_sample_gap_u` only for a parent's 試玩 (U3).
    public func resultFields(playtest: Bool) -> [String: PerfValue] {
        var fields: [String: PerfValue] = [
            "practice": .string("shape_trace"),
            "trace_rule": .string(OrientedLineFacts.traceRule),
            "shapes_done": .int(min(lineIndex, lines.count)),
            "shapes_total": .int(lines.count),
            "off_path_count": .int(offPathCount),
            "lifts": .int(lifts),
            "wrong_start": .int(wrongStarts),
            "reverse_direction": .int(reverseDirections),
            "early_finish_taps": .int(earlyFinishTaps),
            "unjoined_segments": .int(unjoinedSegments),
            "segment_gaps": .int(segmentGaps),
            "strokes": .int(strokes),
            "exposures": .strings(exposures),
            "per_shape": .strings(perShapeRows),
            "tolerance": .string(question.dealt.tolerance.rawValue),
            "mean_dev_u": .seconds(meanDeviation),
            "shape_trace_level": .string(ActivityLevel.l1.code)
        ]
        if let startedAt, let finishedAt {
            fields["duration_ms"] = .int(Int(((finishedAt - startedAt) * 1000).rounded()))
        }
        if playtest { fields["max_sample_gap_u"] = .seconds(maxSampleGap) }
        return fields
    }
}
