import Foundation
import VisaCore

/// Hanzi H3 write board (0.38.0 / 84): 搵完寫's 田字格 write round against design hanzi-tap v2 § Writing, its H3 row
/// and child copy table (LOCKED D5, D10–D12) and the six-target addendum. Offline: reads the bundled pack, the
/// Traditional-only fixture and the app source.
final class HanziWriteTests {
    private static let week = ["人", "上", "下", "左", "右", "木"]
    private static let day = Date(timeIntervalSince1970: 1_800_000_000)
    private static let packURL = URL(fileURLWithPath: "Resources/HanziTap/hanzi-pack.json")
    /// AppModel's `tapCountGuideDemoLead` (the watch-first line before the car sets off).
    private static let lead = 1.4

    private func loadPack() throws -> HanziPack { try HanziPack.load(url: Self.packURL) }

    private func editedPack(_ edit: (inout [String: Any]) -> Void) throws -> HanziPack {
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: Self.packURL)) as! [String: Any]
        edit(&root)
        return try HanziPack.load(data: JSONSerialization.data(withJSONObject: root))
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
    }

    /// `name`'s declaration in `text`, up to the next member declaration at the same indent (or the end of the type).
    private func body(of name: String, in text: String) -> String {
        guard let start = text.range(of: name) else { return "" }
        let after = text[start.upperBound...]
        let ends = ["\n    func ", "\n    private func ", "\n    var ", "\n    private var ", "\n}\n"]
            .compactMap { after.range(of: $0)?.lowerBound }
        return String(text[start.lowerBound..<(ends.min() ?? text.endIndex)])
    }

    /// A completed find of `kind` whose target is `glyph`. With no progress the scheduler deals the week's first
    /// target, so the parent week leads with `glyph` (人's week is the pack's).
    private func found(_ glyph: String, kind: ActivityKind = .tapHanziWrite, pack: HanziPack) -> TapHanziBoard? {
        let settings = HanziTapSettings(week: [glyph] + Self.week.filter { $0 != glyph })
        for n in 1...60 {
            guard let deal = TapHanziGenerator.make(seed: "write-\(glyph)-\(n)", kind: kind, n: n, settings: settings,
                                                    progress: HanziProgress(), decks: HanziCueDecks(), pack: pack,
                                                    now: Self.day).deal,
                  deal.board.target == glyph, var board = TapHanziBoard(deal: deal, pack: pack) else { continue }
            _ = board.tap(deal.board.targetCards[0], at: 1)
            _ = board.tap(deal.board.targetCards[1], at: 2)
            return board
        }
        return nil
    }

    /// A begun write round on `glyph`; the demo (when the plan plays one) is dismissed at `now + 0.2`.
    private func writing(_ glyph: String, pack: HanziPack, level: TapCountGuidanceLevel = .standard, learned: Bool = false,
                         tolerance: LineMatchTolerance = .standard, now: Double = 100) -> TapHanziWriteRound? {
        guard let board = found(glyph, pack: pack),
              var round = TapHanziWriteRound(found: board, pack: pack, tolerance: tolerance) else { return nil }
        round.begin(plan: TapCountGuidePlan(level: level, learned: learned), now: now, demoLead: Self.lead)
        if round.demoPending(now: now + 0.2) { _ = round.penDown(at: LineMatchPoint(x: 0, y: 0), now: now + 0.2) }
        return round
    }

    /// One pen-down on the current stroke at its start, then 6-unit moves along it to `until` (default: past its end).
    @discardableResult
    private func drive(_ round: inout TapHanziWriteRound, clock: inout Double, until: Double? = nil,
                       coach: Bool = false) -> [ShapeTraceMove] {
        guard let path = round.trace.currentPath else { return [] }
        clock += 0.1
        _ = round.penDown(at: path.start, now: clock)
        var moves: [ShapeTraceMove] = []
        var d = 0.0
        while d <= (until ?? path.length + 16) {
            clock += 0.02
            let move = round.penMove(to: path.point(at: min(d, path.length)), now: clock)
            if coach { _ = round.coachTick(now: clock, demoLead: Self.lead) }
            moves.append(move)
            if case .strokeDone = move { break }
            if case .allDone = move { break }
            d += 6
        }
        return moves
    }

    /// When each coach help first starts after a pen-down on the car at `down` that never moves, lifted at `lift`
    /// (seconds after `down`; sampled every 0.05 s for 40 s).
    private func helpOnsets(_ round: inout TapHanziWriteRound, down: Double, lift: Double) -> [String: Double] {
        var onsets: [String: Double] = [:]
        guard let start = round.trace.currentPath?.start,
              case .trace(.grabbed) = round.penDown(at: start, now: down) else {
            expectTrue(false, "the pen takes the car")
            return onsets
        }
        var t = down
        var lifted = false
        while t < down + 40 {
            t += 0.05
            if !lifted, t - down >= lift { round.penUp(); lifted = true }
            for event in round.coachTick(now: t, demoLead: Self.lead) {
                let name: String
                switch event {
                case .help(let help): name = help.kind
                case .redemo: name = "redemo"
                case .cue: name = "cue"
                }
                if onsets[name] == nil { onsets[name] = t - down }
            }
        }
        return onsets
    }

    private func inSquare(_ p: LineMatchPoint, margin: Double = 0) -> Bool {
        let s = HanziWriteBoard.square
        return p.x - margin >= s.x - 1e-9 && p.x + margin <= s.x + s.width + 1e-9
            && p.y - margin >= s.y - 1e-9 && p.y + margin <= s.y + s.height + 1e-9
    }

    /// Gap from `p` to `r` (0 inside it).
    private func gap(_ p: LineMatchPoint, _ r: LineMatchRect) -> Double {
        hypot(max(r.x - p.x, 0, p.x - (r.x + r.width)), max(r.y - p.y, 0, p.y - (r.y + r.height)))
    }

    /// (1) Geometry: the 田字格 placement, projection of every beat and cue point, numbered starts with arrows and
    /// leaders (D10, D12), signs inside the square and clear of every lane, corner and number (D11), and the compact
    /// 0.6 style injected for Hanzi while letters and numerals keep theirs.
    func testBoardPlacementStartsAndSignClearance() throws {
        let pack = try loadPack()
        let square = HanziWriteBoard.square, card = HanziWriteBoard.card
        let k = HanziWriteBoard.scale
        expectEqual(card, LineMatchRect(x: 440, y: 126, width: 400, height: 408), "the letter write card's frame")
        expectTrue(square.x >= card.x && square.y >= card.y && square.x + square.width <= card.x + card.width
                   && square.y + square.height <= card.y + card.height, "the 田字格 sits on the card")
        expectEqual(square.width, square.height)
        expectEqual(k, 350.0 / 300.0, accuracy: 1e-12)
        expectEqual(HanziWriteBoard.laneWidth, HanziGlyphs.laneWidth * k, accuracy: 1e-12)
        let half = HanziWriteBoard.laneWidth / 2
        let labelRadius = HanziWriteBoard.labelRadius * k
        var stops: [String] = []
        for glyph in Self.week {
            let entry = pack.characters[glyph]!
            let paths = HanziWriteBoard.paths(glyph, in: pack)
            expectEqual(paths, HanziGlyphs.paths(glyph, in: pack, offset: HanziWriteBoard.offset, scale: k))
            // A guide exists only when every beat and cue point projects onto its stroke (`NumeralGuide.init`).
            guard let guide = HanziWriteBoard.guide(glyph, in: pack) else {
                expectTrue(false, "guide on the board for \(glyph)")
                continue
            }
            expectEqual(guide.paths, paths)
            for path in paths {
                expectTrue(path.points.allSatisfy { inSquare($0, margin: half) }, "lane inside the 田字格: \(glyph)")
            }
            for (beat, spec) in zip(guide.beats, entry.guide.beats) {
                guard let until = spec.until else {
                    expectEqual(beat.end, paths[beat.stroke].length, accuracy: 1e-9)
                    continue
                }
                let on = paths[beat.stroke].point(at: beat.end)
                expectTrue(on.distance(to: HanziWriteBoard.stage(until.point.point)) <= 1, "beat point on its stroke: \(glyph)")
            }
            for cue in guide.cues {
                let spec = entry.guide.cues[cue.index]
                let on = paths[cue.stroke].point(at: cue.distance)
                expectTrue(on.distance(to: HanziWriteBoard.stage(spec.point.point)) <= 1, "cue point on its stroke: \(glyph)")
                expectTrue(cue.signPoint.distance(to: HanziWriteBoard.stage(spec.signAt.point)) < 1e-9)
                let box = HanziWriteBoard.signBox(cue, guide: guide)
                expectTrue(inSquare(LineMatchPoint(x: box.x, y: box.y))
                           && inSquare(LineMatchPoint(x: box.x + box.width, y: box.y + box.height)),
                           "\(glyph) \(cue.sign) sign inside the 田字格: \(box)")
                // Clear of every stroke's lane by at least half a lane (so clear of its own cue point and corner).
                for (index, path) in paths.enumerated() {
                    var nearest = gap(path.end, box)
                    var d = 0.0
                    while d <= path.length {
                        nearest = min(nearest, gap(path.point(at: d), box))
                        d += 1
                    }
                    expectTrue(nearest >= half, "\(glyph) \(cue.sign) sign clear of stroke \(index + 1): \(nearest)")
                }
                switch cue.sign {
                case .ahead:
                    // D11: only where the pen-down stroke meets a finished stroke, and the demo never waits there.
                    expectTrue(paths[..<cue.stroke].contains { $0.project(on).offset <= 2 * k }, "AHEAD at a junction: \(glyph)")
                    expectFalse(guide.demoPauses(at: cue), "no pause at AHEAD: \(glyph)")
                case .stop:
                    stops.append(glyph)
                    expectTrue(paths[cue.stroke].corners.contains { abs($0 - cue.distance) < 0.5 }, "STOP at the true turn")
                    expectTrue(guide.demoPauses(at: cue))
                }
            }
            for current in [0, paths.count - 1, nil] as [Int?] {
                let marks = HanziWriteBoard.startMarks(glyph, in: pack, current: current)
                expectEqual(marks.map(\.label), (1...paths.count).map(String.init), glyph)
                expectEqual(marks.filter(\.acceptsInput).map(\.stroke), current.map { [$0] } ?? [], "one start takes the pen")
                for mark in marks {
                    let stroke = entry.strokes[mark.stroke]
                    expectTrue(mark.start.distance(to: HanziWriteBoard.stage(stroke.start.point)) < 1e-9)
                    expectTrue(mark.start.distance(to: paths[mark.stroke].start) < 0.01, "a start never moves: \(glyph)")
                    expectEqual(mark.leader, stroke.marker?.reviewLabelOffset != nil)
                    expectTrue(mark.leader || mark.labelAt == mark.start)
                    expectTrue(inSquare(mark.labelAt, margin: labelRadius), "number inside the 田字格: \(glyph) \(mark.label)")
                    let lead = HanziWriteBoard.arrowLead * k
                    expectTrue(mark.arrowAt.distance(to: paths[mark.stroke].point(at: lead)) < 1e-9, "arrow on its stroke")
                    expectEqual(mark.arrowAngle, paths[mark.stroke].angle(at: lead), accuracy: 1e-9)
                    let state: HanziStartMark.State = current.map {
                        mark.stroke < $0 ? .done : mark.stroke == $0 ? .current : .future } ?? .done
                    expectEqual(mark.state, state)
                    for cue in guide.cues {
                        expectTrue(gap(mark.labelAt, HanziWriteBoard.signBox(cue, guide: guide)) >= labelRadius,
                                   "\(glyph) number \(mark.label) clear of the \(cue.sign) sign")
                    }
                }
                for (i, a) in marks.enumerated() {
                    for b in marks[(i + 1)...] {
                        expectTrue(a.labelAt.distance(to: b.labelAt) >= 2 * labelRadius, "\(glyph) numbers apart")
                    }
                }
            }
        }
        expectEqual(stops, ["右"], "one STOP in the set: 右's 橫折")
        // D12: 右's ③ and ④ share one true start with two leaders and two arrows (③ down, ④ across); the corner is not a start.
        let right = HanziWriteBoard.startMarks("右", in: pack, current: 3)
        expectEqual(right[2].start, right[3].start)
        expectTrue(right[2].leader && right[3].leader && right[2].labelAt != right[3].labelAt)
        expectEqual(right[2].arrowAngle, Double.pi / 2, accuracy: 1e-9)
        expectEqual(right[3].arrowAngle, 0, accuracy: 1e-9)
        expectTrue(right[3].acceptsInput && !right[2].acceptsInput && right[4].state == .future)
        let corner = HanziWriteBoard.stage(LineMatchPoint(x: 226, y: 160))
        expectFalse(right.contains { $0.start.distance(to: corner) < 1 || $0.labelAt.distance(to: corner) < 1 })
        expectTrue(HanziWriteBoard.startMarks("入", in: pack, current: 0).isEmpty && HanziWriteBoard.guide("入", in: pack) == nil,
                   "find-only glyphs are never written")

        // The compact style is injected for Hanzi (a `hanzi:` key alone would draw numeral-sized); AHEAD 0.8 keeps
        // the locked 上 / 左 sign centres (y 282) inside the 田字格. Letters and numerals keep their own values.
        let ren = HanziWriteBoard.guide("人", in: pack)!
        expectEqual(ren.glyphKey, "hanzi:人")
        expectEqual([ren.carScale, ren.noseUnits, ren.chevronScale, ren.dotSpacing, ren.stopSignScale, ren.aheadSignScale],
                    [0.6, 42, 0.7, 30, 0.8, 0.8])
        expectEqual(ren.compactStyles, LetterGuideData.styles)
        expectEqual(ren.cuePauses, .stopTurns)
        let letterBoard = LetterGuideData.board
        for letter in LatinGlyphs.supported {
            guard let guide = NumeralGuide(letter: letter) else { expectTrue(false, "guide for \(letter)"); continue }
            expectEqual(guide.compactBoard, letterBoard)
            expectEqual(guide.compactStyles, LetterGuideData.styles)
            expectEqual(guide.cuePauses, .insideBeats)
            expectEqual([guide.carScale, guide.noseUnits, guide.chevronScale, guide.dotSpacing, guide.stopSignScale,
                         guide.aheadSignScale],
                        [letterBoard.carScale, letterBoard.noseUnits, letterBoard.chevScale, letterBoard.laneDotSpacing,
                         letterBoard.stopSignScale, letterBoard.aheadSignScale], "letter \(letter) unchanged")
        }
        for n in 1...10 {
            guard let guide = NumeralGuide(n) else { expectTrue(false, "guide for \(n)"); continue }
            expectTrue(guide.compactBoard == nil && guide.compactStyles == nil && guide.cuePauses == .insideBeats)
            expectEqual([guide.carScale, guide.noseUnits, guide.chevronScale, guide.dotSpacing, guide.stopSignScale,
                         guide.aheadSignScale],
                        [0.72, TapCountGuideCoach.noseUnits, guide.scale, 30 * guide.scale, 0.8, 1], "numeral \(n) unchanged")
        }
    }

    /// (2) The demo: 右 waits exactly once, 0.3 s at its 橫折 corner with the car's wheels down on the same stroke (no
    /// hop); no other glyph waits anywhere and no AHEAD makes the car wait. Reduce Motion never glides or lifts.
    /// Letter and numeral demos keep the pre-H3 rule.
    func testDemoPausesOnceAtTheRightTurnAndNeverAtAhead() throws {
        let pack = try loadPack()
        let timing = TapCountGuideData.timing
        for glyph in Self.week {
            let guide = HanziWriteBoard.guide(glyph, in: pack)!
            let timeline = TapCountDemoTimeline(guide: guide)
            let pauses = timeline.steps.filter { if case .pause = $0.step { return true } else { return false } }
            let hops = timeline.steps.filter { if case .hop = $0.step { return true } else { return false } }
            expectEqual(hops.count, guide.paths.count - 1, "one hop per lift: \(glyph)")
            let beats = guide.beats.reduce(0) { $0 + $1.seconds }
            expectEqual(timeline.duration, beats + Double(hops.count) * timing.hopSeconds
                        + Double(pauses.count) * timing.cuePauseSeconds + timing.mergeSeconds, accuracy: 1e-9)
            // Reduce Motion: every mid-step pose sits at its step's end and nothing leaves the ground.
            for timed in timeline.steps {
                let mid = (timed.start + timed.end) / 2
                guard let still = timeline.pose(at: mid, reduceMotion: true) else { continue }
                expectEqual(still.lift, 0, accuracy: 1e-12)
                if case let .drive(stroke, _, to, _) = timed.step {
                    expectTrue(still.point.distance(to: guide.paths[stroke].point(at: to)) < 0.01, "RM snaps: \(glyph)")
                }
                if case .hop = timed.step { expectTrue((timeline.pose(at: mid)?.lift ?? 0) > 0.5, "a hop lifts: \(glyph)") }
            }
            let route = timeline.route(at: timeline.mergeStart, reduceMotion: true)
            for (index, path) in guide.paths.enumerated() {
                expectEqual(route.filter { $0.stroke == index }.reduce(0) { $0 + ($1.to - $1.from) }, path.length, accuracy: 2)
            }
            for ahead in guide.cues where ahead.sign == .ahead {
                expectFalse(pauses.contains { if case let .pause(_, _, cue, _) = $0.step { return cue == ahead.index }
                                              return false }, "the car passes AHEAD: \(glyph)")
            }
            guard glyph == "右" else {
                expectTrue(pauses.isEmpty, "no fake turn in \(glyph)")
                continue
            }
            expectEqual(pauses.count, 1, "右 waits exactly once")
            let stop = guide.cues.first { $0.sign == .stop }!
            guard let i = timeline.steps.firstIndex(of: pauses[0]), case let .pause(stroke, at, cue, beat) = pauses[0].step,
                  case let .drive(before, _, into, _) = timeline.steps[i - 1].step,
                  case let .drive(after, outOf, _, _) = timeline.steps[i + 1].step else {
                expectTrue(false, "右 drives into the corner, waits, drives on")
                continue
            }
            expectEqual([stroke, cue, beat, before, after], [3, stop.index, 3, 3, 3], "the 橫折 beat, same stroke, no hop")
            expectEqual(at, guide.paths[3].corners[0], accuracy: 1e-9)
            expectEqual(into, at, accuracy: 1e-9)
            expectEqual(outOf, at, accuracy: 1e-9)
            expectEqual(pauses[0].end - pauses[0].start, timing.cuePauseSeconds, accuracy: 1e-9)
            expectEqual(pack.characters["右"]!.guide.cornerContract!.demoPauseSeconds, timing.cuePauseSeconds, accuracy: 1e-9)
            let mid = (pauses[0].start + pauses[0].end) / 2
            expectEqual(timeline.pausedCue(at: mid), stop.index, "the STOP sign blinks while the car waits")
            for reduceMotion in [false, true] {
                let pose = timeline.pose(at: mid, reduceMotion: reduceMotion)!
                expectTrue(pose.point.distance(to: HanziWriteBoard.stage(LineMatchPoint(x: 226, y: 160))) < 1e-6)
                expectTrue(pose.lift == 0 && pose.stroke == 3 && pose.hop == nil, "wheels down at the corner")
            }
        }
        // Letters and numerals: still a wait at every cue strictly inside a beat (the pre-H3 rule) and nowhere else.
        func preH3Pauses(_ guide: NumeralGuide) -> [Int] {
            var out: [Int] = []
            var at: (stroke: Int, distance: Double)?
            for beat in guide.beats {
                let from = at.map { $0.stroke == beat.stroke ? $0.distance : 0 } ?? 0
                let to = max(from, beat.end)
                for cue in guide.cues(onStroke: beat.stroke) where cue.distance > from + 0.5 && cue.distance <= to - 0.5 {
                    out.append(cue.index)
                }
                at = (beat.stroke, to)
            }
            return out
        }
        let others = (1...10).compactMap { NumeralGuide($0) } + LatinGlyphs.supported.compactMap { NumeralGuide(letter: $0) }
        expectEqual(others.count, 10 + LatinGlyphs.supported.count)
        for guide in others {
            let pauses = TapCountDemoTimeline(guide: guide).steps.compactMap { timed -> Int? in
                if case let .pause(_, _, cue, _) = timed.step { return cue } else { return nil }
            }
            expectEqual(pauses, preH3Pauses(guide), guide.glyphKey)
        }
    }

    /// (3) The round: only a completed 搵完寫 find opens it; a touch during the demo ends it and paints nothing; then the
    /// shared coach timers run (標準 2 / 8 / 20 s, 多啲 1 / 5 / 15 s, 少啲 no demo, headlights or signs and an 8 s
    /// safety-net ghost), help ghosts honour Reduce Motion, and the re-demo plays at most twice.
    func testDemoDismissPaintsNothingAndCoachTimers() throws {
        let pack = try loadPack()
        guard let ren = found("人", pack: pack), let flip = found("人", kind: .tapHanziAll, pack: pack),
              let deal = TapHanziGenerator.make(seed: "write-open", kind: .tapHanziWrite, n: 1, settings: .defaults,
                                                progress: HanziProgress(), decks: HanziCueDecks(), pack: pack,
                                                now: Self.day).deal,
              let open = TapHanziBoard(deal: deal, pack: pack) else {
            expectTrue(false, "Hanzi finds")
            return
        }
        expectNil(TapHanziWriteRound(found: flip, pack: pack))
        expectNil(TapHanziWriteRound(found: open, pack: pack))
        guard var round = TapHanziWriteRound(found: ren, pack: pack) else { expectTrue(false, "write round"); return }
        expectEqual(round.phase, .transition)
        expectEqual(round.glyph, "人")
        expectEqual(round.trace.question.kind, .tapHanziWrite)
        expectEqual(round.trace.question.laneWidth, HanziWriteBoard.laneWidth, accuracy: 1e-12)
        expectEqual(round.trace.shapes[0].strokes, HanziWriteBoard.paths("人", in: pack))
        let start = round.trace.currentPath!.start
        expectEqual(round.penDown(at: start, now: 99), .ignored, "no pen before writing begins")
        round.begin(plan: TapCountGuidePlan(level: .standard, learned: false), now: 100, demoLead: Self.lead)
        round.begin(plan: TapCountGuidePlan(level: .less, learned: false), now: 200, demoLead: Self.lead)
        expectEqual(round.coach?.plan.level, .standard, "begins once")
        expectEqual(round.coach?.demoStartedAt ?? 0, 100 + Self.lead, accuracy: 1e-9)
        let end = 100 + Self.lead + round.timeline.duration
        expectTrue(round.demoPending(now: 100) && round.demoPending(now: end - 0.01))
        expectFalse(round.demoPending(now: end + 0.01))
        expectTrue(round.coachTick(now: 103, demoLead: Self.lead).isEmpty, "no help while the demo plays")
        // A touch during the demo ends it; nothing is painted, not even by that touch's moves.
        let before = round.trace
        expectEqual(round.penDown(at: start, now: 102), .demoDismissed)
        expectEqual(round.trace, before, "a dismissing touch paints nothing")
        for d in stride(from: 0.0, through: 60, by: 6) {
            expectEqual(round.penMove(to: round.trace.currentPath!.point(at: d), now: 102 + d / 100), .ignored)
        }
        round.penUp()
        expectTrue(round.trace.progress == 0 && round.trace.penDowns == 0 && round.trace.lifts == 0)
        expectFalse(round.demoPending(now: 102.1))
        expectEqual(round.coach?.demoCode, "skipped")
        expectEqual(round.coach?.readyAt ?? 0, 102, accuracy: 1e-9)
        expectTrue(round.clean, "dismissing the demo is not help")
        expectEqual(round.board, ren)

        // 標準 (提): ring + ghost of the next bit at 2 s, ghost to the end at 8 s, the demo again at 20 s with the pen up.
        var standard = round
        let onsets = helpOnsets(&standard, down: 103, lift: 9)
        expectEqual(Set(onsets.keys), ["stall", "ghost_to_end", "redemo"])
        expectEqual(onsets["stall"] ?? 0, 2, accuracy: 0.06)
        expectEqual(onsets["ghost_to_end"] ?? 0, 8, accuracy: 0.06)
        expectEqual(onsets["redemo"] ?? 0, 20, accuracy: 0.06)
        expectFalse(standard.clean)
        // The re-demo starts the child's turn again at its end (the shared coach's `readyAt`), so with the pen still up
        // the 8 s ghost comes once more inside the 40 s window, timed from the re-demo's end.
        expectEqual([standard.coach?.stalls, standard.coach?.ghostsToEnd, standard.coach?.redemos], [1, 2, 1])
        let againAt = standard.coach!.readyAt + 8
        expectTrue(againAt < 103 + 40)
        expectEqual(standard.coach!.helpKeys.filter { $0.hasPrefix("ghost.") }.last,
                    TapCountGuideHelp.ghostToEnd(stroke: 0, from: 0, to: 0, since: againAt).key)
        expectTrue(standard.demoPending(now: 103 + 20.1), "the car plays again")
        expectEqual(standard.board, ren, "help never touches the find")
        expectEqual(standard.trace.progress, 0)
        // The stall ghost runs the rest of 人's 撇 (one beat), once; Reduce Motion puts it at the end of its run.
        var stalled = round
        _ = stalled.penDown(at: start, now: 103)
        let events = stalled.coachTick(now: 105.01, demoLead: Self.lead)
        guard case let .help(stall)? = events.first, case let .stall(stroke, from, to, since) = stall else {
            expectTrue(false, "stall at 2 s: \(events)")
            return
        }
        expectEqual([stroke], [0])
        expectEqual(from, 0, accuracy: 1e-9)
        expectEqual(to, stalled.guide.paths[0].length, accuracy: 1e-9)
        expectEqual(since, 105, accuracy: 1e-9)
        expectTrue(stalled.coachTick(now: 105.5, demoLead: Self.lead).isEmpty, "noted once per episode")
        let path = stalled.guide.paths[0]
        expectTrue(TapCountGuideCoach.ghostPose(stall, guide: stalled.guide, now: 105.3) != nil)
        let still = TapCountGuideCoach.ghostPose(stall, guide: stalled.guide, now: 105.3, reduceMotion: true)!
        expectTrue(still.point.distance(to: path.point(at: to)) < 1e-6 && still.lift == 0)
        // Headlights: three chevrons on the 30-unit dots ahead of the nose; 少啲 has none.
        expectEqual(TapCountGuideCoach.headlights(plan: stalled.coach!.plan, guide: stalled.guide, trace: stalled.trace),
                    [60, 90, 120])
        // The re-demo plays at most twice per round.
        var idle = round
        var redemos = 0
        _ = idle.penDown(at: start, now: 103)
        idle.penUp()
        var t = 103.0
        while t < 260 {
            t += 0.1
            redemos += idle.coachTick(now: t, demoLead: Self.lead).filter { $0 == .redemo }.count
        }
        expectEqual(redemos, TapHanziWriteRound.maxRedemos)
        expectEqual(TapHanziWriteRound.maxRedemos, 2)

        // 多啲 (教): a demo every time, help at 1 / 5 / 15 s.
        var more = writing("人", pack: pack, level: .more, learned: true)!
        expectEqual(more.coach?.demoCode, "skipped", "多啲 demos even once learned")
        let moreOnsets = helpOnsets(&more, down: 101, lift: 6)
        expectEqual(moreOnsets["stall"] ?? 0, 1, accuracy: 0.06)
        expectEqual(moreOnsets["ghost_to_end"] ?? 0, 5, accuracy: 0.06)
        expectEqual(moreOnsets["redemo"] ?? 0, 15, accuracy: 0.06)
        // 少啲 (熄): no demo, headlights or signs; only the 8 s safety-net ghost.
        var less = writing("右", pack: pack, level: .less)!
        expectFalse(less.demoPending(now: 100))
        expectEqual(less.coach?.demoCode, "none")
        expectTrue(TapCountGuideCoach.headlights(plan: less.coach!.plan, guide: less.guide, trace: less.trace).isEmpty)
        expectFalse(less.coach!.plan.cueSigns || less.coach!.plan.cueWords || less.coach!.plan.headlights)
        let lessOnsets = helpOnsets(&less, down: 101, lift: 9)
        expectEqual(Set(lessOnsets.keys), ["ghost_to_end"])
        expectEqual(lessOnsets["ghost_to_end"] ?? 0, 8, accuracy: 0.06)
        // 標準 once learned: no demo; headlights stay, signs and their lines go.
        let learned = writing("右", pack: pack, level: .standard, learned: true)!
        expectFalse(learned.demoPending(now: 100))
        expectTrue(learned.coach!.plan.headlights && !learned.coach!.plan.cueSigns && !learned.coach!.plan.cueWords)
    }

    /// (4) 右's 橫折: the car stops at the true corner with the pen down, a run-on is coached, the pen turns down and the
    /// same stroke finishes with no lift and no new start; no other stroke of the set has a corner stop.
    func testRightCornerStopKeepsThePenDownAndNoFalseStops() throws {
        let pack = try loadPack()
        for glyph in Self.week {
            for tolerance in [LineMatchTolerance.narrow, .standard, .wide] {
                guard var round = writing(glyph, pack: pack, level: .less, tolerance: tolerance) else {
                    expectTrue(false, "round for \(glyph)")
                    continue
                }
                var clock = 101.0
                var corners: [Int] = []
                var downs = 0
                while !round.trace.isComplete && downs < 10 {
                    let stroke = round.trace.strokeIndex
                    downs += 1
                    for move in drive(&round, clock: &clock) where move == .cornerReached { corners.append(stroke) }
                    round.penUp()
                }
                expectTrue(round.canStamp, "\(glyph) at \(tolerance)")
                expectEqual(round.phase, .done)
                expectEqual([downs, round.trace.penDowns], [round.guide.paths.count, round.guide.paths.count],
                            "one pen-down per stroke: \(glyph) at \(tolerance)")
                expectEqual(round.trace.lifts, 0)
                expectEqual(corners, glyph == "右" ? [3] : [], "corner stops: \(glyph) at \(tolerance)")
                expectEqual(round.guide.paths.map { $0.corners.count }, glyph == "右" ? [0, 0, 0, 1, 0] : round.guide.paths.map { _ in 0 })
            }
        }
        guard var right = writing("右", pack: pack) else { expectTrue(false, "右"); return }
        var clock = 101.0
        for _ in 0..<3 {
            drive(&right, clock: &clock, coach: true)
            right.penUp()
        }
        expectEqual(right.trace.strokeIndex, 3)
        let path = right.trace.currentPath!
        let corner = path.corners[0]
        let stop = right.guide.cues.first { $0.sign == .stop }!
        expectTrue(path.point(at: corner).distance(to: HanziWriteBoard.stage(LineMatchPoint(x: 226, y: 160))) < 1e-6)
        expectEqual(stop.distance, corner, accuracy: 0.5)
        expectEqual(right.guide.beats[3].end, corner, accuracy: 0.5)
        // A stall short of the corner: the ghost runs to the corner (the end of 「口字上面橫過去！」), not past it.
        var short = right
        drive(&short, clock: &clock, until: 40)
        let shortAt = clock
        let shortHelp = short.coachTick(now: shortAt + 2.01, demoLead: Self.lead)
        guard case let .help(.stall(_, _, to, _))? = shortHelp.first(where: { if case .help = $0 { return true } else { return false } }) else {
            expectTrue(false, "stall before the corner: \(shortHelp)")
            return
        }
        expectEqual(to, corner, accuracy: 0.5)
        // Into the corner, then on past it the old way: the car waits there and the run-on is coached; the pen stays down.
        let downs = right.trace.penDowns
        clock += 0.1
        _ = right.penDown(at: path.start, now: clock)
        var reached = 0
        var cueLines: [NumeralCueSign] = []
        var d = 0.0
        while d <= corner + 30 {
            clock += 0.02
            let point = d <= corner ? path.point(at: d)
                : LineMatchPoint(x: path.point(at: corner).x + (d - corner), y: path.point(at: corner).y)
            if right.penMove(to: point, now: clock) == .cornerReached { reached += 1 }
            for case .cue(let cue) in right.coachTick(now: clock, demoLead: Self.lead) { cueLines.append(cue.sign) }
            d += 6
        }
        expectEqual(reached, 1)
        expectEqual(cueLines, [.stop], "the corner line once, before the turn")
        expectEqual(right.trace.progress, corner, accuracy: 0.01)
        expectEqual(right.trace.cornerOvershoots, 1)
        expectTrue(right.trace.strokeIndex == 3 && right.trace.dragging, "same stroke, pen down")
        // Turn down without lifting: the same pen-down finishes the 橫折.
        var e = corner
        while right.trace.strokeIndex == 3 && e <= path.length + 12 {
            clock += 0.02
            _ = right.penMove(to: path.point(at: min(e, path.length)), now: clock)
            e += 6
        }
        expectEqual(right.trace.strokeIndex, 4)
        expectEqual(right.trace.penDowns, downs + 1)
        expectEqual(right.trace.lifts, 0)
        expectTrue(right.clean, "the corner stop and a run-on are coaching, never a lost clean write")
    }

    /// (5) 下's 點 is a short down-right stroke: a tap, a nudge or a run down the finished 豎 never draws it; the stroke
    /// itself does, at every tolerance (the 0.7 floor; without it 闊 took the dot on the first move). A stationary tap
    /// on the dot's end or anywhere past 70% of it, with the view's same-point move and a resting pen's jitter, draws
    /// nothing and is coached as a start at the red end; a press on the car or taps marching along the dot never move
    /// the car. The shared pen rule drew the dot from that tap at its end.
    func testXiaDotIsAShortDownRightStroke() throws {
        let pack = try loadPack()
        let paths = HanziWriteBoard.paths("下", in: pack)
        let bar = paths[0], vertical = paths[1], dot = paths[2]
        expectTrue(dot.end.x > dot.start.x && dot.end.y > dot.start.y, "down-right")
        expectTrue(dot.start.x > vertical.start.x && dot.start.y > bar.start.y + HanziWriteBoard.laneWidth, "beside the 豎, below the 橫")
        expectTrue(dot.length < 0.4 * vertical.length, "short")
        for tolerance in [LineMatchTolerance.narrow, .standard, .wide] {
            guard var round = writing("下", pack: pack, level: .less, tolerance: tolerance) else {
                expectTrue(false, "下 at \(tolerance)")
                continue
            }
            expectTrue(round.trace.arrivalDistance(dot) >= HanziWriteBoard.minimumArrivalFraction * dot.length - 1e-9)
            var clock = 101.0
            for _ in 0..<2 {
                drive(&round, clock: &clock)
                round.penUp()
            }
            expectEqual(round.trace.strokeIndex, 2)
            // Stationary taps on the end and past 70% (the view sends the pen-down point again as its first move, and a
            // resting pen jitters): each is a coached start at the red end, and nothing is drawn.
            for share in [1.0, 0.9, 0.8, 0.75, 0.71] {
                var tap = round
                let at = dot.point(at: dot.length * share)
                clock += 0.1
                expectEqual(tap.penDown(at: at, now: clock), .trace(.reverse), "a tap at \(share) of the dot (\(tolerance))")
                for (i, jitter) in [0.0, 1.5, -1.5, 0.0].enumerated() {
                    let still = LineMatchPoint(x: at.x + jitter, y: at.y + jitter)
                    expectEqual(tap.penMove(to: still, now: clock + 0.02 * Double(i + 1)), .ignored)
                }
                tap.penUp()
                expectTrue(tap.trace.strokeIndex == 2 && tap.trace.progress == 0 && !tap.canStamp,
                           "nothing drawn by a tap at \(share) (\(tolerance))")
                expectEqual(tap.trace.reverseDirections, round.trace.reverseDirections + 1)
            }
            // A press on the car itself, held still: it takes the car, which moves only as far as the jittering pen.
            var press = round
            clock += 0.1
            expectEqual(press.penDown(at: dot.start, now: clock), .trace(.grabbed(shape: 0, stroke: 2)))
            expectEqual(press.penMove(to: dot.start, now: clock + 0.02), .waiting, "the pen-down point never draws")
            for (i, jitter) in [1.0, -1.0, 1.5, -1.5, 1.0].enumerated() {
                _ = press.penMove(to: LineMatchPoint(x: dot.start.x + jitter, y: dot.start.y + jitter),
                                  now: clock + 0.04 + 0.02 * Double(i))
            }
            // The furthest the jitter reaches along the dot: (1.5, 1.5) onto its down-right direction.
            let reach = 1.5 * ((dot.end.x - dot.start.x) + (dot.end.y - dot.start.y)) / dot.length
            expectTrue(press.trace.strokeIndex == 2 && press.trace.progress <= reach + 1e-9,
                       "a press moves the car no further than the pen (\(tolerance)): \(press.trace.progress)")
            // Taps marching along the dot, each lifted where it landed: the car never moves.
            var taps = round
            for step in 1...12 {
                let at = dot.point(at: Double(step) * 6)
                clock += 0.1
                _ = taps.penDown(at: at, now: clock)
                _ = taps.penMove(to: at, now: clock + 0.02)
                taps.penUp()
            }
            expectTrue(taps.trace.strokeIndex == 2 && taps.trace.progress == 0, "taps never draw the dot (\(tolerance))")
            // A pen that lands mid-dot, away from the car, and slides on to the end never takes the car.
            var slide = round
            clock += 0.1
            expectEqual(slide.penDown(at: dot.point(at: dot.length * 0.6), now: clock), .trace(.notNearVehicle))
            var s = dot.length * 0.6
            while s <= dot.length {
                clock += 0.02
                _ = slide.penMove(to: dot.point(at: s), now: clock)
                s += 3
            }
            expectTrue(!slide.trace.holding && slide.trace.progress == 0 && slide.trace.strokeIndex == 2,
                       "a slide that never reaches the car takes nothing (\(tolerance))")
            // A tap on the dot's start.
            clock += 0.1
            _ = round.penDown(at: dot.start, now: clock)
            _ = round.penMove(to: dot.point(at: 3), now: clock + 0.02)
            round.penUp()
            expectEqual(round.trace.strokeIndex, 2, "a tap is not the dot (\(tolerance))")
            // A nudge short of 70%.
            clock += 0.1
            _ = round.penDown(at: dot.point(at: round.trace.progress), now: clock)
            var d = round.trace.progress
            while d < 0.68 * dot.length {
                clock += 0.02
                _ = round.penMove(to: dot.point(at: d), now: clock)
                d += 2
            }
            round.penUp()
            expectEqual(round.trace.strokeIndex, 2, "a nudge is not the dot (\(tolerance))")
            expectTrue(round.trace.progress < round.trace.arrivalDistance(dot))
            // Down the finished 豎 beside the dot: off the dot's lane, never drawn.
            clock += 0.1
            let side = HanziWriteBoard.stage(LineMatchPoint(x: 142, y: 160))
            _ = round.penDown(at: side, now: clock)
            var y = 160.0
            while y <= 254 {
                clock += 0.02
                _ = round.penMove(to: HanziWriteBoard.stage(LineMatchPoint(x: 142, y: y)), now: clock)
                y += 5
            }
            round.penUp()
            expectEqual(round.trace.strokeIndex, 2, "the 豎 is not the dot (\(tolerance))")
            // The short down-right stroke finishes it, and the glyph.
            let moves = drive(&round, clock: &clock)
            expectEqual(moves.last, .allDone, "the dot drawn at \(tolerance)")
            expectTrue(round.canStamp)
        }
        // The pre-H3 trace (no floor) took 闊's dot as drawn before it moved: the floor is what prevents a tap.
        let shape = ShapeTraceShape(slot: "hanzi", kind: .numeral, strokes: paths, colorIndex: 0, frame: HanziWriteBoard.square)
        let noFloor = ShapeTraceQuestion(itemID: "h0", kind: .tapHanziWrite, level: .l2, scene: .numeralBoard, shift: 0,
            big: true, slant: false, shapes: [shape], laneWidth: HanziWriteBoard.laneWidth, promptKey: "",
            promptTraditionalChinese: "", promptEnglish: "")
        expectTrue(ShapeTraceBoard(question: noFloor, tolerance: .wide).arrivalDistance(dot) <= 0)
        expectEqual(noFloor.minimumArrivalFraction, 0, "every other trace keeps the old arrival rule")
        expectEqual(noFloor.penRule, .shared, "and the shared pen rule")
        // With the floor but the shared pen rule, the stationary tap on the dot's end took the car 70.87 units away (inside
        // the 90-unit grab) and the view's same-point move drew the dot: the floor alone never stopped a tap.
        let floorOnly = ShapeTraceQuestion(itemID: "h0", kind: .tapHanziWrite, level: .l2, scene: .numeralBoard, shift: 0,
            big: true, slant: false, shapes: [shape], laneWidth: HanziWriteBoard.laneWidth, promptKey: "",
            promptTraditionalChinese: "", promptEnglish: "", minimumArrivalFraction: HanziWriteBoard.minimumArrivalFraction)
        var old = ShapeTraceBoard(question: floorOnly)
        var t = 0.0
        for path in paths.prefix(2) {
            t += 0.1
            _ = old.penDown(at: path.start, now: t)
            for d in stride(from: 0.0, through: path.length + 12, by: 6) {
                t += 0.02
                if case .strokeDone = old.penMove(to: path.point(at: min(d, path.length)), now: t) { break }
            }
            old.penUp()
        }
        expectEqual(old.strokeIndex, 2)
        expectEqual(dot.end.distance(to: old.vehiclePoint!), dot.length, accuracy: 1e-9)
        expectEqual(old.penDown(at: dot.end, now: t + 1), .grabbed(shape: 0, stroke: 2))
        expectEqual(old.penMove(to: dot.end, now: t + 1.02), .allDone, "the shared rule drew the dot from a still tap")
    }

    /// (6) Writing is practice: wrong starts, a reversal, off-path wandering, a lift and a stall are coached, count
    /// against a clean write only, and never change the find (misses, hint, visa minutes) or its recognition record.
    func testWritingIsPracticeWithZeroPenalties() throws {
        let pack = try loadPack()
        for glyph in Self.week {
            guard let board = found(glyph, pack: pack), var round = writing(glyph, pack: pack) else {
                expectTrue(false, "round for \(glyph)")
                continue
            }
            var clock = 101.0
            let first = round.trace.currentPath!
            // A start at the red end (a reversal).
            expectEqual(round.penDown(at: first.end, now: clock), .trace(.reverse))
            round.penUp()
            if glyph == "右" {
                clock += 0.1
                let later = round.trace.shapes[0].strokes[4].start
                expectEqual(round.penDown(at: later, now: clock), .trace(.wrongStart), "another stroke's start")
                round.penUp()
            }
            // Off the lane and back, then a lift half way.
            clock += 0.1
            _ = round.penDown(at: first.start, now: clock)
            var d = 0.0
            while d < first.length / 2 {
                clock += 0.02
                let p = first.point(at: d)
                _ = round.penMove(to: d > 30 && d < 42 ? LineMatchPoint(x: p.x + 60, y: p.y + 60) : p, now: clock)
                d += 6
            }
            round.penUp()
            // Back on the car: a 2 s stall.
            clock += 0.1
            _ = round.penDown(at: round.trace.vehiclePoint!, now: clock)
            let stalled = round.coachTick(now: clock + 2.05, demoLead: Self.lead)
            expectTrue(stalled.contains { if case .help(.stall) = $0 { return true } else { return false } }, "stall: \(glyph)")
            clock += 2.1
            round.penUp()
            while !round.trace.isComplete {
                drive(&round, clock: &clock, coach: true)
                round.penUp()
            }
            expectTrue(round.canStamp, glyph)
            expectEqual(round.board, board, "writing never changes the find: \(glyph)")
            expectEqual([round.board.misses, board.misses], [0, 0])
            expectEqual(round.board.assisted, board.assisted)
            expectTrue(round.board.isClean, "the recognition record stays the find's: \(glyph)")
            expectFalse(round.clean)
            expectTrue(round.trace.reverseDirections >= 1 && round.trace.offPathCount >= 1 && round.trace.lifts >= 1)
            expectTrue((round.coach?.stalls ?? 0) >= 1)
            let fields = round.resultFields
            expectEqual(fields["write_clean"], .bool(false))
            expectEqual(fields["guide_level"], .string("standard"))
            expectEqual(fields["off_path"], .int(round.trace.offPathCount))
            expectEqual(fields["strokes_drawn"], .int(round.guide.paths.count))
            // A clean write after the demo: no help, start to end; two in a row make the glyph learned.
            guard var clean = TapHanziWriteRound(found: board, pack: pack) else { continue }
            clean.begin(plan: TapCountGuidePlan(level: .standard, learned: false), now: 0, demoLead: Self.lead)
            var tidy = Self.lead + clean.timeline.duration + 0.2
            expectFalse(clean.demoPending(now: tidy))
            while !clean.trace.isComplete {
                drive(&clean, clock: &tidy, coach: true)
                clean.penUp()
            }
            expectTrue(clean.canStamp && clean.clean, "a clean write of \(glyph)")
            expectEqual(clean.coach?.demoCode, "played")
            expectEqual(clean.resultFields["write_clean"], .bool(true))
            var progress = HanziWriteProgress()
            progress.record(glyph, clean: clean.clean, pack: pack)
            progress.record(glyph, clean: clean.clean, pack: pack)
            expectTrue(progress.isLearned(glyph))
            progress.record(glyph, clean: round.clean, pack: pack)
            expectFalse(progress.isLearned(glyph), "a coached write resets the streak")
            expectEqual(progress.streaks.keys.sorted(), ["hanzi:\(glyph)"])
        }

        // AppModel: the write path never takes a penalty, fuel, hint or recognition record, and stamps with the find's
        // own hint only (SwiftUI / AppKit are not built on this box).
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let start = model.range(of: "// MARK: - 中文字 · 搵完寫 / Find & write (Hanzi H3, 0.38.0 / 84)")
        let end = model.range(of: "// MARK: - 一架一架數 / Tap & Count")
        expectTrue(start != nil && end != nil && start!.upperBound < end!.lowerBound)
        let write = String(model[start!.upperBound..<end!.lowerBound])
        for banned in ["handleEvaluation(", "playtestHandle(", "pendingAwardMinutes", "playtestPendingMinutes", "showHint(",
                       "tapHanziPenaltyPending", "hanziProgress.record", "HanziProgressStore", "applyEntrySuccess",
                       "guideVoice.", "assisted"] {
            expectFalse(write.contains(banned), "the write path never touches \(banned)")
        }
        let stamp = body(of: "private func finishTapHanziRound(", in: model)
        expectTrue(stamp.contains("applyEntrySuccess(assisted: board.assisted)"), "the visa follows the find's hint only")
        expectTrue(stamp.contains("tapHanziRecordWrite(write.glyph, clean: write.clean, playtest: playtest)"))
        expectEqual(model.components(separatedBy: "HanziWriteProgressStore().save(").count, 2, "one writing save")
        let record = body(of: "private func tapHanziRecordWrite(", in: model)
        let preview = record.range(of: "if playtest {"), save = record.range(of: "HanziWriteProgressStore().save(")
        expectTrue(preview != nil && save != nil && preview!.lowerBound < save!.lowerBound, "a playtest saves only its preview")
        expectTrue(record.components(separatedBy: "if playtest {")[1].components(separatedBy: "}")[0].contains("return"))
        expectTrue(body(of: "private func clearHanziPreview(", in: model).contains("previewHanziWriteProgress = nil"))
    }

    /// (7) The write lines are the pack's HK Traditional copy, filled for every target; a missing line or placeholder
    /// gives no copy.
    func testWriteCopyIsThePacksHongKongTraditional() throws {
        let pack = try loadPack()
        guard let copy = HanziWriteCopy(pack: pack) else { expectTrue(false, "write copy"); return }
        expectTrue(copy.headerParts == ("而家寫『", "』！") && copy.doneParts == ("你寫咗『", "』！"))
        expectEqual(copy.subline, "由綠色起點，跟住箭嘴寫。")
        expectEqual(copy.watch("右"), "而家寫『右』！先睇車仔。")
        expectEqual(copy.turn("右"), "到你喇！跟住箭嘴寫『右』。")
        expectEqual(copy.reprompt("右"), "喺綠色箭嘴開始，寫『右』！")
        expectEqual(copy.done("右"), "你寫咗『右』！")
        expectEqual(copy.redemo, "再睇車仔行一次！")
        expectEqual(copy.stopWord, "停")
        expectEqual(copy.trayDemo, HanziWriteLine("先睇車仔"))
        expectEqual(copy.trayTrace, HanziWriteLine("跟住白色箭嘴行"))
        expectEqual(copy.trayStall, HanziWriteLine("睇吓車仔點行", sub: "再由你架車繼續"))
        expectEqual(copy.legendHeadlights, HanziWriteLine("頭燈", sub: "睇下一段"))
        expectEqual(copy.legendAhead, HanziWriteLine("繼續", sub: "經過交接位"))
        expectEqual(copy.legendStop, HanziWriteLine("停", sub: "停一停，再轉彎"))
        expectEqual(copy.stopCue("停一停，轉彎直落！"), HanziWriteLine("停一停，轉彎直落！", sub: "轉彎唔提筆。"))
        expectEqual(copy.strokeCount(4, of: 5), "第 4 / 5 筆")
        expectEqual([HanziWriteCopy.findChip, HanziWriteCopy.writeChip], ["搵晒", "寫"])
        let right = HanziWriteBoard.guide("右", in: pack)!
        expectEqual(right.spec.cues.map(\.line.zh), ["撇過橫線，唔使停！", "停一停，轉彎直落！"])
        expectEqual([right.spec.merge.zh, right.spec.hop?.zh], ["到你喇！", "提起筆，去下一個起點。"])
        var lines = [copy.headerParts.before, copy.headerParts.after, copy.doneParts.before, copy.doneParts.after,
                     copy.subline, copy.redemo, copy.stopWord, HanziWriteCopy.findChip, HanziWriteCopy.writeChip,
                     copy.strokeCount(2, of: 3)]
        for line in [copy.trayDemo, copy.trayTrace, copy.trayStall, copy.legendHeadlights, copy.legendAhead, copy.legendStop,
                     copy.stopCue("")] {
            lines += [line.text] + [line.sub].compactMap { $0 }
        }
        for glyph in Self.week {
            lines += [copy.watch(glyph), copy.turn(glyph), copy.reprompt(glyph), copy.done(glyph)]
            let guide = HanziWriteBoard.guide(glyph, in: pack)!
            lines += guide.spec.beats.map(\.line.zh) + guide.spec.cues.map(\.line.zh) + [guide.spec.merge.zh]
                + [guide.spec.hop?.zh].compactMap { $0 }
        }
        let fixture = URL(fileURLWithPath: "Tests/VisaCoreTests/Fixtures/traditional-check/simplified-only.txt")
        // 托 (托住) is standard Traditional; the fixture lists it only as Simplified for 託 (as in HanziGlyphTests).
        let simplified = Set(try String(contentsOf: fixture, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") }.joined().filter { !$0.isWhitespace }).subtracting(["托"])
        for line in lines where !line.isEmpty {
            expectTrue(isTraditionalChineseOnly(line) && perfTraditionalOnly(line), line)
            expectFalse(line.contains { simplified.contains($0) }, "Simplified character in \(line)")
            expectFalse(line.contains { $0.isASCII && $0.isLetter }, "no ASCII letters in \(line)")
            expectFalse(line.contains("{") || line.contains("熄"), line)
        }
        // Fails closed: a missing write line or placeholder gives no copy (and no write board).
        expectNil(HanziWriteCopy(pack: try editedPack { root in
            var lines = root["copy"] as! [String: Any]
            lines["writeTurn"] = nil
            root["copy"] = lines
        }))
        expectNil(HanziWriteCopy(pack: try editedPack { root in
            var lines = root["copy"] as! [String: Any]
            lines["writeDone"] = ["zhHK": "你寫咗！", "en": "You wrote it!"]
            root["copy"] = lines
        }))
    }

    /// (8) Wiring: 搵完寫 is playable since build 84, still OFF until its own playtest (D6); after its find the write
    /// round opens (not a stub) and its stamp goes back through the find's parent-controls hold; 翻字卡 still stamps
    /// after the find; the shared drawing reads the injected style.
    func testWiringEntersTheWriteRoundAfterTheFind() throws {
        expectEqual(Array(ActivityCatalog.playableKinds.suffix(2)), [.tapHanziAll, .tapHanziWrite])
        expectEqual(ActivityCatalog.playableKinds.count, 27)
        for kind in [ActivityKind.tapHanziAll, .tapHanziWrite] {
            expectTrue(ActivityCatalog.defaultOffKinds.contains(kind) && kind.requiresPlaytestBeforeStars)
            expectFalse(ActivityCatalog.defaultOnKinds.contains(kind))
            expectEqual(MissionGameAssignment.defaultStars(for: kind), [])
            expectFalse(ParentPlaytestLog().allowsStars(for: kind))
            expectTrue(ParentPlaytestLog().recording(kind, on: Self.day).allowsStars(for: kind))
        }
        expectFalse(ParentPlaytestLog().recording(.tapHanziAll, on: Self.day).allowsStars(for: .tapHanziWrite), "its own playtest")
        let fresh = MissionGameAssignment.defaults
        expectEqual(fresh.enabledStars[.tapHanziWrite], [])
        for star in ChildDifficulty.allCases {
            expectFalse(fresh.pool(for: star).contains { $0.isTapHanziFamily })
        }
        // A build-83 assignment (26 kinds, 翻字卡 turned on for ★) reloads with 搵完寫 OFF and nothing else changed.
        var stored: [String: [Int]] = [:]
        for kind in ActivityCatalog.playableKinds where kind != .tapHanziWrite {
            stored[kind.rawValue] = ChildDifficulty.allCases.filter { fresh.isEnabled(kind, star: $0) }.map(\.rawValue)
        }
        stored["tapHanziAll"] = [1]
        let older = UserDefaults(suiteName: "VisaGames.hanziBuild83.\(UUID().uuidString)")!
        older.set(try JSONSerialization.data(withJSONObject: ["starsByKind": stored]), forKey: MissionGameAssignmentStore.key)
        let upgraded = MissionGameAssignmentStore(defaults: older).load()
        expectEqual(upgraded.enabledStars.count, 27)
        expectEqual(upgraded.enabledStars[.tapHanziWrite], [])
        expectEqual(upgraded.enabledStars[.tapHanziAll], [.easy])
        for kind in ActivityCatalog.playableKinds where !kind.isTapHanziFamily {
            expectEqual(upgraded.enabledStars[kind], fresh.enabledStars[kind], kind.rawValue)
        }
        expectTrue(upgraded.isHiddenFromMissions(.tapHanziWrite))
        // The find's finish: 翻字卡 stamps; 搵完寫 waits for its write round.
        let pack = try loadPack()
        expectEqual(found("上", kind: .tapHanziAll, pack: pack)?.finish, .stamp)
        expectEqual(found("上", pack: pack)?.finish, .awaitWriteRound)

        // App source guards (SwiftUI / AppKit are not built on this box).
        let host = try source("Sources/VisaGames/CanvasActivityHost.swift")
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let view = try source("Sources/VisaGames/TapHanziWriteBoardView.swift")
        let drawing = try source("Sources/VisaGames/TapCountGuideDrawing.swift")
        expectTrue(host.contains("if shownKind == .tapHanziWrite, let round = model.currentTapHanziWriteRound"))
        expectTrue(host.contains("round.phase == .writing || round.phase == .done {\n                TapHanziWriteBoardView(round: round"))
        expectTrue(host.contains("TapHanziBoardView(board: board"), "the find phase keeps the H2 board")
        let find = body(of: "private func finishTapHanziFind(", in: model)
        let hold = find.range(of: "if !playtest, taskRoundOpen, !tapHanziFinishHold.finishesNow(token, mode: session.mode) {")
        let branch = find.range(of: "case .awaitWriteRound:")
        expectTrue(hold != nil && branch != nil && hold!.lowerBound < branch!.lowerBound, "held before writing or stamping")
        let awaiting = String(find[branch!.upperBound...])
        expectTrue(awaiting.contains("?.canStamp == true {\n                finishTapHanziRound(token: token, playtest: playtest)"))
        expectTrue(awaiting.contains("beginTapHanziWriting(token: token, playtest: playtest)"))
        expectEqual(find.components(separatedBy: "finishTapHanziRound(token: token, playtest: playtest)").count, 3)
        expectEqual(model.components(separatedBy: "finishTapHanziRound(token:").count, 4, "its only caller: finishTapHanziFind")
        let stamp = body(of: "private func finishTapHanziRound(", in: model)
        expectTrue(stamp.contains("guard board.finish == .stamp || write?.canStamp == true else { return }"))
        expectTrue(stamp.contains("let write = playtest ? playtestTapHanziWriteRound : tapHanziWriteRound"))
        let begin = body(of: "private func beginTapHanziWriting(", in: model)
        expectTrue(begin.contains("let board = playtest ? playtestTapHanziBoard : tapHanziBoard"))
        expectTrue(begin.contains("(playtest ? playtestTapHanziWriteRound : tapHanziWriteRound) == nil"), "begins once")
        expectTrue(begin.contains("TapCountGuidePlan(level: tapCountSettings.guidance"), "the shared level, never migrated")
        let move = body(of: "func tapHanziWritePenMove(", in: model)
        expectTrue(move.contains("self?.finishTapHanziFind(token: token, playtest: playtest)"), "the stamp goes through the hold")
        expectFalse(move.contains("finishTapHanziRound"))
        let down = body(of: "func tapHanziWritePenDown(", in: model)
        let dismissed = down.components(separatedBy: "case .demoDismissed:")
        expectEqual(dismissed.count, 2)
        expectTrue(dismissed[1].components(separatedBy: "case .trace")[0].contains("return false"), "the view drops the touch")
        expectTrue(model.contains("var currentTapHanziWriteRound: TapHanziWriteRound? { tapHanziUsesPlaytest ? playtestTapHanziWriteRound : tapHanziWriteRound }"))
        expectTrue(body(of: "private var tapHanziWriteInputOpen", in: model).contains("session.mode == .lock && taskRoundOpen"))
        expectTrue(body(of: "func tick(", in: model).contains("tapHanziWriteTick(now: current.timeIntervalSinceReferenceDate)"))
        expectTrue(body(of: "private func resetTaskRound(", in: model).contains("tapHanziWriteRound = nil"))
        expectTrue(body(of: "private func discardPlaytestCover(", in: model).contains("playtestTapHanziWriteRound = nil"))
        expectTrue(body(of: "func speakTapHanziPrompt()", in: model).contains("copy.reprompt(round.glyph)")
                   || body(of: "func speakTapHanziPrompt()", in: model).contains("writeCopy.reprompt(round.glyph)"))
        // The write board: the shared coach drawing with Reduce Motion, the pack's paths, no Latin furniture.
        for needle in ["accessibilityReduceMotion", "reduceMotion: reduceMotion", "HanziWriteBoard.startMarks(",
                       "HanziWriteBoard.square", "TapCountDrawing.guideMotion(", "TapCountDrawing.guideHeadlights(",
                       "TapCountDrawing.guideCueSign(", "HanziGlyphView(glyph: glyph", "swallowed = !onDown(point)",
                       "stopWord: copy.stopWord"] {
            expectTrue(view.contains(needle), "write board uses \(needle)")
        }
        for banned in ["LatinLetterGlyph", "LetterWordArt", "LetterGuideData", "TapLetterWriteRound", "\"STOP\"", "guideVoice"] {
            expectFalse(view.contains(banned), "write board avoids \(banned)")
        }
        // The numbered starts are drawn above the cars: at rest the paint car sits on the current start (as the letter
        // board draws its markers after its guidance layer).
        let card = body(of: "private var writingCard", in: view)
        let cars = card.range(of: "            guidanceLayer\n"), starts = card.range(of: "drawStarts(in: &g)")
        expectTrue(cars != nil && starts != nil && cars!.upperBound < starts!.lowerBound, "starts above the guidance layer")
        expectEqual(card.components(separatedBy: "drawStarts(in: &g)").count, 2, "drawn once")
        // A scheduled demo line is said only on its own lane, on screen with its pen open; parent controls drop them all.
        let speech = body(of: "private func scheduleTapHanziDemoSpeech(", in: model)
        expectTrue(speech.contains("self.tapHanziUsesPlaytest == playtest, self.tapHanziWriteInputOpen,"))
        let parent = body(of: "private func enterParentAfterAuthentication(", in: model)
        let stop = parent.range(of: "guideVoice.stop()"), drop = parent.range(of: "tapHanziGuideSpeechGeneration += 1")
        expectTrue(stop != nil && drop != nil && stop!.upperBound < drop!.lowerBound, "entering parent drops the beat lines")
        // A help's line is the beat its capped ghost drives in.
        let coached = body(of: "private func tapHanziWriteCoached(", in: model)
        expectTrue(coached.contains("guard plan.cueWords, let index = round.helpBeat else { continue }"))
        expectFalse(coached.contains("progress + 10"))
        // The shared drawing takes the style the guide carries, never a `latin:` key test.
        expectFalse(drawing.contains("hasPrefix(\"latin:\")"))
        for needle in ["compactStyles?.beamOuterWidth", "compactStyles?.routeGlowWidth", "compactStyles?.stallRingRadius",
                       "scale: guide.aheadSignScale", "scale: guide.stopSignScale"] {
            expectTrue(drawing.contains(needle), "drawing reads \(needle)")
        }
    }

    /// (9) D10, only the current numbered start takes the pen. For every target and stroke, a pen-down on a later
    /// stroke's own start (its actual point; 上's ② lies 88.67 units from ①, inside the shared 90-unit grab) is a
    /// coached wrong start that draws nothing, also with the view's same-point move; the current start takes the car;
    /// 右's shared ③ / ④ start belongs to whichever is current (D12). A pen held still anywhere on a stroke never moves
    /// the car, yet a pen that takes it half a lane ahead still finishes every stroke in one pen-down. Letters and
    /// numerals keep the shared pen rule.
    func testOnlyTheCurrentStartTakesThePen() throws {
        let pack = try loadPack()
        expectEqual(HanziWriteBoard.holdRadius, 21, accuracy: 1e-9)
        for glyph in Self.week {
            guard var round = writing(glyph, pack: pack, level: .less) else {
                expectTrue(false, "round for \(glyph)")
                continue
            }
            expectEqual(round.trace.question.penRule, .orderedStarts(holdRadius: HanziWriteBoard.holdRadius))
            expectEqual(round.trace.vehicleRadius, HanziWriteBoard.holdRadius, "a slide takes the car only as near")
            let strokes = pack.characters[glyph]!.strokes
            var clock = 101.0
            var later = 0
            for current in strokes.indices {
                expectEqual(round.trace.strokeIndex, current)
                let own = round.trace.currentPath!
                let marks = HanziWriteBoard.startMarks(glyph, in: pack, current: current)
                for next in strokes.indices where next > current {
                    let start = HanziWriteBoard.stage(strokes[next].start.point)
                    guard start.distance(to: own.start) > 0.5 else { continue }
                    later += 1
                    expectFalse(marks[next].acceptsInput)
                    var tap = round
                    clock += 0.1
                    expectEqual(tap.penDown(at: start, now: clock), .trace(.wrongStart),
                                "\(glyph): a tap on start \(next + 1) while \(current + 1) is current")
                    expectEqual(tap.penMove(to: start, now: clock + 0.02), .ignored)
                    tap.penUp()
                    expectTrue(tap.trace.strokeIndex == current && tap.trace.progress == 0, "\(glyph): nothing drawn")
                    expectEqual(tap.trace.wrongStarts, round.trace.wrongStarts + 1)
                    expectFalse(tap.clean, "a wrong start is coached")
                    expectEqual(tap.board, round.board, "never a miss")
                }
                var take = round
                expectTrue(marks[current].acceptsInput)
                expectEqual(take.penDown(at: own.start, now: clock + 0.1), .trace(.grabbed(shape: 0, stroke: current)))
                // A pen held still anywhere on the stroke (the view sends its point again) never moves the car.
                var d = 0.0
                while d <= own.length {
                    var still = round
                    let at = own.point(at: d)
                    _ = still.penDown(at: at, now: clock + 0.2)
                    _ = still.penMove(to: at, now: clock + 0.22)
                    expectTrue(still.trace.progress == 0 && still.trace.strokeIndex == current,
                               "\(glyph) stroke \(current + 1): a still pen at \(d) draws nothing")
                    d += 3
                }
                drive(&round, clock: &clock)
                round.penUp()
            }
            expectTrue(round.canStamp, glyph)
            expectTrue(later > 0, "\(glyph) has later starts to tap")
        }

        // The reported case: 上's ② at glyph (137, 119) while ① waits at rest.
        guard var shang = writing("上", pack: pack, level: .less) else { expectTrue(false, "上"); return }
        let two = HanziWriteBoard.stage(LineMatchPoint(x: 137, y: 119))
        expectEqual(two.distance(to: shang.trace.vehiclePoint!), 76 * HanziWriteBoard.scale, accuracy: 1e-9)
        expectTrue(two.distance(to: shang.trace.vehiclePoint!) < ShapeTraceBoard.grabRadius, "inside the shared grab")
        expectEqual(shang.penDown(at: two, now: 101), .trace(.wrongStart))
        expectEqual(shang.penMove(to: two, now: 101.02), .ignored)
        expectEqual(shang.trace.progress, 0, "① is not painted")

        // D12: 右's ③ and ④ share (118, 160). It takes ③ while ③ is current; with ③ part-drawn it is still ③'s own
        // start (the car waits further down and the pen slides on to it), never a wrong start; then it takes ④.
        guard var right = writing("右", pack: pack, level: .less) else { expectTrue(false, "右"); return }
        var clock = 101.0
        for _ in 0..<2 {
            drive(&right, clock: &clock)
            right.penUp()
        }
        let shared = HanziWriteBoard.stage(LineMatchPoint(x: 118, y: 160))
        var third = right
        expectEqual(third.penDown(at: shared, now: clock + 0.1), .trace(.grabbed(shape: 0, stroke: 2)))
        drive(&right, clock: &clock, until: 40)
        right.penUp()
        let parked = right.trace.progress
        expectTrue(parked > HanziWriteBoard.holdRadius && right.trace.strokeIndex == 2, "③ part-drawn: \(parked)")
        clock += 0.1
        expectEqual(right.penDown(at: shared, now: clock), .trace(.notNearVehicle), "③'s own start, behind the car")
        var y = 0.0
        while y <= parked + 24 {
            clock += 0.02
            _ = right.penMove(to: right.trace.currentPath!.point(at: y), now: clock)
            y += 6
        }
        expectTrue(right.trace.progress > parked && right.trace.wrongStarts == 0, "the pen slid on to the car and drove it")
        right.penUp()
        drive(&right, clock: &clock)
        right.penUp()
        expectEqual(right.trace.strokeIndex, 3)
        var fourth = right
        expectEqual(fourth.penDown(at: shared, now: clock + 0.1), .trace(.grabbed(shape: 0, stroke: 3)))

        // Half a lane ahead: the car keeps the pen's lead but still finishes each stroke in that one pen-down, at every
        // tolerance (下's 點 is the tightest: 70.87 − 21 = 49.87 ≥ its 49.61 floor).
        for glyph in Self.week {
            for tolerance in LineMatchTolerance.allCases {
                guard var round = writing(glyph, pack: pack, level: .less, tolerance: tolerance) else {
                    expectTrue(false, "\(glyph) at \(tolerance)")
                    continue
                }
                var clock = 101.0
                var aheadDots = 0
                while !round.trace.isComplete {
                    let stroke = round.trace.strokeIndex
                    let path = round.trace.currentPath!
                    expectTrue(path.length - round.trace.arrivalDistance(path) >= HanziWriteBoard.holdRadius,
                               "\(glyph) stroke \(stroke + 1) finishes from half a lane ahead (\(tolerance))")
                    let lead = HanziWriteBoard.holdRadius - 0.01
                    clock += 0.1
                    guard round.penDown(at: path.point(at: lead), now: clock) == .trace(.grabbed(shape: 0, stroke: stroke)) else {
                        // Nearer a later start than the car (木's ③ beside ④): coached, so start at the car instead.
                        round.penUp()
                        drive(&round, clock: &clock)
                        round.penUp()
                        continue
                    }
                    var moves: [ShapeTraceMove] = []
                    var d = lead
                    while d <= path.length + 12, round.trace.strokeIndex == stroke, !round.trace.isComplete {
                        clock += 0.02
                        moves.append(round.penMove(to: path.point(at: min(d, path.length)), now: clock))
                        d += 6
                    }
                    expectTrue(moves.contains { if case .strokeDone = $0 { return true }; return $0 == .allDone },
                               "\(glyph) stroke \(stroke + 1) from \(lead) ahead (\(tolerance))")
                    if glyph == "下" && stroke == 2 { aheadDots += 1 }
                    round.penUp()
                }
                expectTrue(round.canStamp && round.trace.lifts == 0, "\(glyph) at \(tolerance)")
                if glyph == "下" { expectEqual(aheadDots, 1, "the dot from half a lane ahead (\(tolerance))") }
            }
        }

        // Letters and numerals keep the shared rule: f's cross-stroke end lies 80 units from the car at rest on its first
        // stroke, inside the 90-unit grab, so the car is taken before any other marker is checked.
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        guard let deal = TapLetterGenerator.make(seed: "pen-f", n: 1, settings: TapLetterSettings(thisWeek: ["f"]),
                                                 progress: LetterProgress(), decks: LetterWordDecks(), bank: bank,
                                                 now: Self.day), deal.target == "f" else {
            expectTrue(false, "an f deal")
            return
        }
        var letter = TapLetterWriteRound(deal: deal).trace
        expectEqual(letter.question.penRule, .shared)
        expectEqual(letter.vehicleRadius, ShapeTraceBoard.grabRadius)
        let cross = letter.shapes[0].strokes[1].end
        expectEqual(cross.distance(to: letter.vehiclePoint!), 80, accuracy: 0.5)
        expectEqual(letter.penDown(at: cross, now: 1), .grabbed(shape: 0, stroke: 0))
        for n in 1...10 {
            expectEqual(NumeralGlyphs.traceQuestion(n, itemID: "pen", kind: .tapCountTrace, colorIndex: 0).penRule, .shared)
        }
    }

    /// (10) The 2 s ghost never runs through 右's STOP: stalled 18 and 6 units before the 橫折 corner it stops at the
    /// corner (the shared rule ran on to 148 and to the stroke's end), the same in the reducer and in the view's
    /// help, with or without Reduce Motion; at the corner it turns down. The 8 s ghost still runs to the end. Every
    /// other Hanzi stroke, and every letter and numeral, keeps the shared stall end.
    func testStallGhostStopsAtTheRightTurn() throws {
        let pack = try loadPack()
        guard var right = writing("右", pack: pack) else { expectTrue(false, "右"); return }
        var clock = 101.0
        for _ in 0..<3 {
            drive(&right, clock: &clock, coach: true)
            right.penUp()
        }
        expectEqual(right.trace.strokeIndex, 3)
        let path = right.trace.currentPath!
        let corner = path.corners[0]
        expectEqual(corner, 108 * HanziWriteBoard.scale, accuracy: 1e-9)
        let cornerPoint = path.point(at: corner)
        for before in [18.0, 6.0, 0.0] {
            var stall = right
            clock += 0.1
            _ = stall.penDown(at: path.start, now: clock)
            var d = 0.0
            while d < corner - before {
                d = min(d + 6, corner - before)
                clock += 0.02
                _ = stall.penMove(to: path.point(at: d), now: clock)
                _ = stall.coachTick(now: clock, demoLead: Self.lead)
            }
            expectEqual(stall.trace.progress, corner - before, accuracy: 1e-9)
            let at = clock + 2.01
            let view = TapCountGuideCoach.help(plan: stall.coach!.plan, guide: stall.guide, trace: stall.trace,
                                               readyAt: stall.coach!.readyAt, now: at)
            let shared = min(path.length, max(stall.guide.beatEnd(stroke: 3, after: corner - before), corner - before + 40))
            let reducer = stall.coachTick(now: at, demoLead: Self.lead).compactMap { event -> TapCountGuideHelp? in
                if case .help(let help) = event { return help } else { return nil }
            }
            expectEqual(reducer, [view], "the reducer starts the help the view draws (\(before) before the corner)")
            guard case let .stall(stroke, from, to, _) = view else {
                expectTrue(false, "a stall \(before) before the corner: \(view)")
                continue
            }
            expectEqual(stroke, 3)
            expectEqual(from, corner - before, accuracy: 1e-9)
            if before > 0 {
                expectEqual(to, corner, accuracy: 1e-9)
                expectTrue(shared > corner + 1, "the shared rule ran past the corner: \(shared)")
                expectEqual(stall.helpBeat, 3, "the line of the beat into the corner")
                expectEqual(stall.guide.spec.beats[3].line.zh, "口字上面橫過去！")
                // The ghost stays on the top of 口 for its whole run, gliding or (Reduce Motion) placed at its end.
                for reduceMotion in [false, true] {
                    var u = 0.0
                    while u <= 1.25 {
                        let now = at + u * TapCountGuideData.timing.stallRingGhostSeconds
                        if let pose = TapCountGuideCoach.ghostPose(view, guide: stall.guide, now: now, reduceMotion: reduceMotion) {
                            expectTrue(pose.point.x <= cornerPoint.x + 1e-9 && abs(pose.point.y - cornerPoint.y) < 1e-9,
                                       "the ghost never turns down before the car is at the corner: \(pose.point)")
                        }
                        u += 0.05
                    }
                }
            } else {
                // At the corner: the ghost turns down to the end of 橫折.
                expectEqual(to, path.length, accuracy: 1e-9)
                expectEqual(stall.helpBeat, 4)
                expectEqual(stall.guide.spec.beats[4].line.zh, "轉彎直落！")
            }
            // The 8 s ghost still runs to the stroke's end (design § Writing).
            let long = TapCountGuideCoach.help(plan: stall.coach!.plan, guide: stall.guide, trace: stall.trace,
                                               readyAt: stall.coach!.readyAt, now: clock + 8.01)
            guard case let .ghostToEnd(_, _, end, _) = long else { expectTrue(false, "8 s ghost: \(long)"); continue }
            expectEqual(end, path.length, accuracy: 1e-9)
        }
        // No other Hanzi stroke has a STOP or a beat end inside it, so each keeps the shared stall end; nor do letters
        // and numerals, which keep it everywhere.
        func sharedEnd(_ guide: NumeralGuide, _ stroke: Int, _ progress: Double) -> Double {
            let length = guide.paths[stroke].length
            return min(length, max(guide.beatEnd(stroke: stroke, after: progress), progress + 40))
        }
        var guides = Self.week.compactMap { HanziWriteBoard.guide($0, in: pack) }
        expectEqual(guides.count, Self.week.count)
        guides += (1...10).compactMap { NumeralGuide($0) } + LatinGlyphs.supported.compactMap { NumeralGuide(letter: $0) }
        for guide in guides {
            for (stroke, path) in guide.paths.enumerated() where !(guide.glyphKey == "hanzi:右" && stroke == 3) {
                var p = 0.0
                while p < path.length {
                    expectEqual(guide.stallGhostEnd(stroke: stroke, progress: p, length: path.length), sharedEnd(guide, stroke, p),
                                accuracy: 1e-9)
                    p += 2
                }
            }
        }
    }

    /// (11) D10 for a slide too: a pen that lands off the car and slides onto it takes the car only where a pen-down at
    /// that point would. Nearer a later stroke's start, the red end or a later stroke's end than the car, the slide
    /// takes nothing and is that pen-down's coached wrong start or reversal (the same counts and help, once a touch,
    /// never a miss); slid on to where a pen-down takes the car, it takes it, so a pen slid along its stroke past a later
    /// start still reaches a car parked after a lift. Swept over every target and stroke, with the car at rest and parked
    /// part-way. A slide onto the car itself, or onto 右's shared ③ / ④ start, takes it; letters and numerals keep the
    /// shared slide.
    func testASlideTakesTheCarOnlyWhereAPenDownWould() throws {
        let pack = try loadPack()
        let off = HanziWriteBoard.stage(LineMatchPoint(x: 170, y: 145))
        // The reported case: 木 with ③ current. ④'s start (149, 132) lies 17.34 units from ③'s car, inside the hold.
        guard var mu = writing("木", pack: pack, level: .less) else { expectTrue(false, "木"); return }
        var clock = 101.0
        for _ in 0..<2 {
            drive(&mu, clock: &clock)
            mu.penUp()
        }
        expectEqual(mu.trace.strokeIndex, 2)
        let car = mu.trace.vehiclePoint!
        let four = HanziWriteBoard.stage(LineMatchPoint(x: 149, y: 132))
        expectEqual(four.distance(to: car), 17.34, accuracy: 0.005)
        expectTrue(four.distance(to: car) < HanziWriteBoard.holdRadius, "inside the hold radius")
        var pressed = mu
        clock += 0.1
        expectEqual(pressed.penDown(at: four, now: clock), .trace(.wrongStart), "a pen-down on ④'s start")
        var slide = mu
        expectEqual(slide.penDown(at: off, now: clock), .trace(.notNearVehicle))
        expectTrue(slide.trace.dragging, "the pen is down off the car")
        expectEqual(slide.penMove(to: four, now: clock + 0.02), .away, "the slide onto ④'s start takes nothing")
        expectFalse(slide.trace.holding, "the car is not taken")
        expectEqual(slide.trace.wrongStarts, mu.trace.wrongStarts + 1)
        expectEqual([slide.trace.wrongStarts, slide.trace.reverseDirections],
                    [pressed.trace.wrongStarts, pressed.trace.reverseDirections], "counted as the pen-down")
        expectEqual(slide.coach?.helpKeys, pressed.coach?.helpKeys, "coached as the pen-down")
        expectFalse(slide.clean, "a wrong start is coached")
        expectEqual(slide.board, mu.board, "never a miss")
        // On down-right toward (151, 134), then down ④'s side of ③: nothing is painted, and the wrong start counts once.
        for (x, y) in [(150.0, 133.0), (151.0, 134.0), (148.0, 136.0), (146.0, 140.0), (143.0, 145.0), (140.0, 150.0)] {
            clock += 0.02
            expectEqual(slide.penMove(to: HanziWriteBoard.stage(LineMatchPoint(x: x, y: y)), now: clock), .away)
        }
        expectTrue(slide.trace.strokeIndex == 2 && slide.trace.progress == 0 && !slide.trace.holding, "③ is not painted")
        expectEqual(slide.trace.wrongStarts, pressed.trace.wrongStarts, "one wrong start for the touch")
        // Only the current start takes the pen: slid on to ③'s car, the same touch takes it and draws ③.
        clock += 0.02
        _ = slide.penMove(to: car, now: clock)
        expectTrue(slide.trace.holding, "③'s own car takes the pen")
        let three = slide.trace.currentPath!
        var last = ShapeTraceMove.ignored
        var d = 0.0
        while d <= three.length + 12, slide.trace.strokeIndex == 2 {
            clock += 0.02
            last = slide.penMove(to: three.point(at: min(d, three.length)), now: clock)
            d += 6
        }
        expectEqual(last, .strokeDone(shape: 0, stroke: 2))
        expectEqual(slide.trace.wrongStarts, pressed.trace.wrongStarts, "still the one wrong start")
        // A slide onto ③'s car itself takes it and draws ③ in the same touch.
        var onto = mu
        clock += 0.1
        _ = onto.penDown(at: off, now: clock)
        _ = onto.penMove(to: car, now: clock + 0.02)
        expectTrue(onto.trace.holding, "a slide onto the car takes it")
        last = .ignored
        d = 0
        while d <= three.length + 12, onto.trace.strokeIndex == 2 {
            clock += 0.02
            last = onto.penMove(to: three.point(at: min(d, three.length)), now: clock)
            d += 6
        }
        expectEqual(last, .strokeDone(shape: 0, stroke: 2))
        expectTrue(onto.trace.wrongStarts == 0 && onto.clean, "a slide onto the car is a clean start")

        // After a lift half-way along ①, a pen pressed at ①'s start and slid along it reaches the parked car in that one
        // touch, past a later start on the way (上's and 下's ②, 木's ③): that start is coached at most once.
        for glyph in Self.week {
            guard var lifted = writing(glyph, pack: pack, level: .less) else { expectTrue(false, glyph); continue }
            let first = lifted.trace.currentPath!
            drive(&lifted, clock: &clock, until: first.length / 2)
            lifted.penUp()
            let parked = lifted.trace.progress
            expectTrue(parked > HanziWriteBoard.holdRadius && lifted.trace.strokeIndex == 0, "\(glyph): ① parked at \(parked)")
            let moves = drive(&lifted, clock: &clock)
            expectEqual(moves.last, .strokeDone(shape: 0, stroke: 0), "\(glyph): ① resumed in one touch")
            expectTrue(lifted.trace.wrongStarts <= 1, "\(glyph): \(lifted.trace.wrongStarts) wrong starts")
        }

        // D12: a slide onto 右's shared (118, 160) takes ③ while ③ is current, and ④ once ③ is drawn.
        guard var right = writing("右", pack: pack, level: .less) else { expectTrue(false, "右"); return }
        for _ in 0..<2 {
            drive(&right, clock: &clock)
            right.penUp()
        }
        let shared = HanziWriteBoard.stage(LineMatchPoint(x: 118, y: 160))
        for stroke in [2, 3] {
            expectEqual(right.trace.strokeIndex, stroke)
            var anchor = right
            clock += 0.1
            expectEqual(anchor.penDown(at: off, now: clock), .trace(.notNearVehicle))
            _ = anchor.penMove(to: shared, now: clock + 0.02)
            expectTrue(anchor.trace.holding && anchor.trace.wrongStarts == 0, "a slide onto the shared start takes \(stroke + 1)")
            drive(&right, clock: &clock)
            right.penUp()
        }

        // Every target and stroke, with the car at rest and parked after a lift at 25, 50 and 65% (short of the 70%
        // floor): at every point within the hold radius of the car, a slide from a press in a corner of the square takes
        // the car exactly where a pen-down takes it, and is otherwise that pen-down's wrong start or reversal, once.
        let corners = [LineMatchPoint(x: 470, y: 170), LineMatchPoint(x: 810, y: 170), LineMatchPoint(x: 470, y: 510),
                       LineMatchPoint(x: 810, y: 510)]
        let radius = HanziWriteBoard.holdRadius
        var taken = 0, refused = 0, reversals = 0
        for glyph in Self.week {
            guard var round = writing(glyph, pack: pack, level: .less) else { expectTrue(false, glyph); continue }
            var clock = 101.0
            for stroke in round.trace.shapes[0].strokes.indices {
                expectEqual(round.trace.strokeIndex, stroke)
                let path = round.trace.currentPath!
                for share in [0.0, 0.25, 0.5, 0.65] {
                    var parked = round
                    if share > 0 {
                        drive(&parked, clock: &clock, until: share * path.length)
                        parked.penUp()
                    }
                    expectEqual(parked.trace.strokeIndex, stroke)
                    let at = parked.trace.vehiclePoint!
                    guard let press = corners.first(where: { corner in
                        var probe = parked
                        return probe.penDown(at: corner, now: clock) == .trace(.notNearVehicle)
                    }) else {
                        expectTrue(false, "\(glyph) stroke \(stroke + 1): a press off the car")
                        continue
                    }
                    var dx = -radius
                    while dx <= radius {
                        var dy = -radius
                        while dy <= radius {
                            let p = LineMatchPoint(x: at.x + dx, y: at.y + dy)
                            dy += 3
                            guard p.distance(to: at) <= radius else { continue }
                            clock += 0.01
                            var down = parked
                            let verdict = down.penDown(at: p, now: clock)
                            var slide = parked
                            _ = slide.penDown(at: press, now: clock)
                            let move = slide.penMove(to: p, now: clock + 0.005)
                            let place = "\(glyph) stroke \(stroke + 1) parked at \(share): (\(p.x), \(p.y))"
                            if verdict == .trace(.grabbed(shape: 0, stroke: stroke)) {
                                taken += 1
                                expectTrue(slide.trace.holding && slide.trace.wrongStarts == parked.trace.wrongStarts,
                                           "\(place): a slide takes the car as the pen-down does")
                                continue
                            }
                            expectTrue(verdict == .trace(.wrongStart) || verdict == .trace(.reverse), "\(place): \(verdict)")
                            refused += 1
                            if verdict == .trace(.reverse) { reversals += 1 }
                            expectEqual(move, .away, place)
                            expectFalse(slide.trace.holding, "\(place): the slide takes nothing")
                            expectEqual([slide.trace.wrongStarts, slide.trace.reverseDirections],
                                        [down.trace.wrongStarts, down.trace.reverseDirections], "\(place): counted as the pen-down")
                            expectEqual(slide.coach?.helpKeys, down.coach?.helpKeys, "\(place): coached as the pen-down")
                            expectEqual(slide.penMove(to: p, now: clock + 0.008), .away, place)
                            expectEqual([slide.trace.wrongStarts, slide.trace.reverseDirections],
                                        [down.trace.wrongStarts, down.trace.reverseDirections], "\(place): once a touch")
                            expectTrue(!slide.trace.holding && slide.trace.progress == parked.trace.progress,
                                       "\(place): nothing painted")
                        }
                        dx += 3
                    }
                }
                drive(&round, clock: &clock)
                round.penUp()
            }
            expectTrue(round.canStamp, glyph)
        }
        expectTrue(refused > 0 && reversals > 0 && taken > refused, "taken \(taken), refused \(refused), reversals \(reversals)")

        // Letters and numerals keep the shared slide: from a press in the stage's corner, f's car is taken by a slide onto
        // its cross-stroke end (80 units off, inside the 90-unit grab), where a Hanzi slide is refused, and each
        // numeral's car by a slide 85 units below it.
        let bank = try LetterWordBank.load(url: URL(fileURLWithPath: "Resources/LetterTap/starter-bank.json"))
        guard let deal = TapLetterGenerator.make(seed: "pen-f", n: 1, settings: TapLetterSettings(thisWeek: ["f"]),
                                                 progress: LetterProgress(), decks: LetterWordDecks(), bank: bank,
                                                 now: Self.day), deal.target == "f" else {
            expectTrue(false, "an f deal")
            return
        }
        let corner = LineMatchPoint(x: 20, y: 700)
        var letter = TapLetterWriteRound(deal: deal).trace
        let cross = letter.shapes[0].strokes[1].end
        expectEqual(cross.distance(to: letter.vehiclePoint!), 80, accuracy: 0.5)
        expectEqual(letter.penDown(at: corner, now: 1), .notNearVehicle)
        _ = letter.penMove(to: cross, now: 1.02)
        expectTrue(letter.holding && letter.wrongStarts == 0, "the shared slide takes f's car")
        for n in 1...10 {
            var numeral = ShapeTraceBoard(question: NumeralGlyphs.traceQuestion(n, itemID: "pen", kind: .tapCountTrace,
                                                                                colorIndex: 0))
            let at = numeral.vehiclePoint!
            expectEqual(numeral.penDown(at: corner, now: 1), .notNearVehicle)
            _ = numeral.penMove(to: LineMatchPoint(x: at.x, y: at.y + 85), now: 1.02)
            expectTrue(numeral.holding && numeral.wrongStarts == 0, "the shared slide takes \(n)'s car")
        }

        // The app coaches a refused slide as a refused pen-down: the same reprompt, from the pen-move handler.
        let model = try source("Sources/VisaGames/AppDelegate.swift")
        let reprompt = body(of: "private func tapHanziWriteReprompt(", in: model)
        expectTrue(reprompt.contains("tapHanziShowWriteBubble(HanziWriteLine(copy.reprompt(round.glyph)), seconds: 3)"))
        expectTrue(reprompt.contains("tapHanziSpeak(\"write.reprompt.\\(round.glyph)\", copy.reprompt(round.glyph), queued: false)"))
        expectTrue(body(of: "func tapHanziWritePenDown(", in: model)
            .contains("if down == .wrongStart || down == .reverse { tapHanziWriteReprompt(round, copy: copy) }"))
        let move = body(of: "func tapHanziWritePenMove(", in: model)
        let counted = move.range(of: "let wrongStarts = round.trace.wrongStarts"), moved = move.range(of: "round.penMove(to: point")
        expectTrue(counted != nil && moved != nil && counted!.upperBound < moved!.lowerBound, "counted before the move")
        expectTrue(move.contains("if round.trace.wrongStarts > wrongStarts { tapHanziWriteReprompt(round, copy: copy) }"))
    }
}
