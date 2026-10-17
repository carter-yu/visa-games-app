import Foundation

// 一架一架數 board (v0.28.0, design number-quantity §2.4–§2.10, §5, §11.2.7, ADR 0017).
// A pure value: the view runs it on a local copy per tap and hands it to the model; the app owns
// the clock. Tracing reuses `ShapeTraceBoard` unchanged (direction hint always on).

public enum TapCountStage: String, Sendable, Equatable {
    /// Tapping (★ / ★★) or picking (★★★).
    case tapping
    /// The set is counted (★ / ★★ last tap, ★★★ right OK): group glow, 「三架！」.
    case counted
    /// ★★ / ★★★: tracing the numeral.
    case tracing
    /// Finished (the app stamps the visa).
    case done
}

public enum TapCountTap: Sendable, Equatable {
    /// ★ / ★★: a new vehicle counted; `k` = how many so far (its badge number).
    case counted(k: Int)
    /// ★ / ★★: the last vehicle; the set is complete.
    case completed(k: Int)
    /// ★ / ★★: tapped an already-counted vehicle (badge flashes, no voice; `recount_attempt`).
    case recount(bay: Int)
    /// ★★★: picked; `k` = how many are picked now.
    case selected(k: Int)
    /// ★★★: un-picked; the others renumber 1…k in pick order.
    case unselected(k: Int)
    /// Same vehicle again within 0.4 s: a pen bounce, ignored.
    case doubleTapIgnored
    /// Empty bay or no bay (★★★ cones, gaps).
    case empty
    /// Input locked (Think Pause, recount playback, counted, tracing, done).
    case locked
}

public enum TapCountSubmit: Sendable, Equatable {
    /// Nothing picked: 「未揀車喎！」 — not a miss.
    case needsSelection
    case judged(correct: Bool, selected: Int)
    case locked
}

/// ★★★ 擦晒 (design §2.10): same gate as the shape-trace eraser.
public enum TapCountErase: Sendable, Equatable {
    case cleared
    /// 4th press this round: cleared, 「試吓撳 OK 啦！」, OK flashes.
    case clearedNudge
    /// 6th press: cleared, the button hides until the next OK.
    case clearedAndHidden
    case coolingDown
    case unavailable
}

/// After a miss (shown when the Think Pause ends): which badges get the orange ring.
public enum TapCountMissFeedback: String, Sendable, Equatable {
    case over
    case under
}

public struct TapCountBoard: Sendable, Equatable {
    public static let doubleTapSeconds: Double = 0.4
    public static let eraserCooldown: Double = ShapeTraceBoard.eraserCooldown
    public static let eraserNudgeAt = ShapeTraceBoard.eraserNudgeAt
    public static let eraserHideAt = ShapeTraceBoard.eraserHideAt
    /// ★ / ★★: blink the next vehicle after 8 s without a tap (at most twice a round).
    public static let nudgeAfterSeconds: Double = 8
    public static let maxNudges = 2
    /// ★★★: re-read the prompt after 10 s without a tap.
    public static let pickRepromptSeconds: Double = 10
    /// Last tap this close before OK = `fast_submit`.
    public static let fastSubmitSeconds: Double = 0.8
    /// Misses before the demo count (`ActivityHintPolicy`).
    public static let demoAfterMisses = 2

    public let question: TapCountQuestion
    public private(set) var stage: TapCountStage = .tapping
    /// Bays in tap order: counted (★ / ★★) or currently picked (★★★).
    public private(set) var order: [Int] = []
    public private(set) var locked = false
    public private(set) var lastTapBay: Int?
    public private(set) var lastTapAt: Double?
    public private(set) var firstTapAt: Double?
    public private(set) var lastActivityAt: Double?
    public private(set) var taps = 0
    public private(set) var recountAttempts = 0
    public private(set) var doubleTaps = 0
    public private(set) var untaps = 0
    public private(set) var tapIntervals: [Double] = []
    public private(set) var idleNudges = 0
    public private(set) var idleReprompts = 0
    // ★★★
    public private(set) var submits = 0
    public private(set) var misses = 0
    public private(set) var attempts: [Int] = []
    public private(set) var changesSinceSubmit = 0
    public private(set) var preSubmitChanges = 0
    public private(set) var missFeedback: TapCountMissFeedback?
    public private(set) var demoBays: [Int] = []
    public private(set) var assisted = false
    public private(set) var erases = 0
    public private(set) var erasesSinceSubmit = 0
    public private(set) var lastEraseAt: Double?
    public private(set) var eraserHidden = false
    public private(set) var eraserLocked = false
    // Tracing
    public private(set) var trace: ShapeTraceBoard?
    public private(set) var finishedAt: Double?
    public private(set) var startedAt: Double?

    public init(question: TapCountQuestion) {
        self.question = question
    }

    public var target: Int { question.target }
    public var isPick: Bool { question.isPick }
    public var isComplete: Bool { stage == .done }
    public var selectedCount: Int { order.count }
    public var remaining: Int { max(0, question.count - order.count) }

    /// Badge number of a bay (1-based pick / count order), nil when not tapped.
    public func badge(forBay bay: Int) -> Int? {
        order.firstIndex(of: bay).map { $0 + 1 }
    }

    public func isTapped(_ bay: Int) -> Bool { order.contains(bay) }

    /// The next untapped vehicle in reading order (★ / ★★ nudge target).
    public var nextUntapped: Int? { question.readingOrder.first { !order.contains($0) } }

    /// ★★★ after an over-pick: the picks past the target (orange rings, design §5.2.6).
    public var extraBays: [Int] {
        guard missFeedback == .over, order.count > target else { return [] }
        return Array(order.dropFirst(target))
    }

    /// OK lights once at least one vehicle is picked (D16).
    public var okEnabled: Bool { isPick && stage == .tapping && !order.isEmpty && !locked }

    /// 擦晒 shows on the pick stage, greyed with nothing picked; hidden after the 6th press until OK.
    public var eraserVisible: Bool { isPick && stage == .tapping && !eraserHidden }
    public var eraserEnabled: Bool { eraserVisible && !order.isEmpty && !locked }

    // MARK: Taps

    public mutating func tap(bay: Int?, now: Double) -> TapCountTap {
        guard stage == .tapping, !locked else { return .locked }
        guard let bay, question.vehicle(atBay: bay) != nil else { return .empty }
        if startedAt == nil { startedAt = now }
        if lastTapBay == bay, let last = lastTapAt, now - last < Self.doubleTapSeconds {
            doubleTaps += 1
            return .doubleTapIgnored
        }
        if let last = lastTapAt { tapIntervals.append(now - last) }
        if firstTapAt == nil { firstTapAt = now }
        lastTapBay = bay
        lastTapAt = now
        lastActivityAt = now
        taps += 1
        if isPick {
            missFeedback = nil
            changesSinceSubmit += 1
            if let index = order.firstIndex(of: bay) {
                order.remove(at: index)
                untaps += 1
                return .unselected(k: order.count)
            }
            order.append(bay)
            return .selected(k: order.count)
        }
        if order.contains(bay) {
            recountAttempts += 1
            return .recount(bay: bay)
        }
        order.append(bay)
        if order.count == question.count {
            stage = .counted
            return .completed(k: order.count)
        }
        return .counted(k: order.count)
    }

    /// Think Pause / recount playback: every input is ignored while locked.
    public mutating func setLocked(_ value: Bool) { locked = value }

    /// ★ / ★★ 8 s idle nudge (the view blinks `nextUntapped`). False once used twice.
    public mutating func nudge(now: Double) -> Bool {
        guard !isPick, stage == .tapping, idleNudges < Self.maxNudges else { return false }
        idleNudges += 1
        lastActivityAt = now
        return true
    }

    /// ★★★ 10 s idle: the prompt is read again (`idle_reprompt`).
    public mutating func reprompt(now: Double) {
        idleReprompts += 1
        lastActivityAt = now
    }

    public func idleFor(now: Double, since roundStart: Double) -> Double { now - (lastActivityAt ?? roundStart) }

    // MARK: ★★★ OK, eraser, demo

    public mutating func submit(now: Double) -> TapCountSubmit {
        guard isPick, stage == .tapping, !locked else { return .locked }
        guard !order.isEmpty else { return .needsSelection }
        submits += 1
        let k = order.count
        attempts.append(k)
        preSubmitChanges += max(0, changesSinceSubmit - k)
        changesSinceSubmit = 0
        erasesSinceSubmit = 0
        eraserHidden = false
        lastActivityAt = now
        if k == target {
            stage = .counted
            return .judged(correct: true, selected: k)
        }
        misses += 1
        missFeedback = k > target ? .over : .under
        return .judged(correct: false, selected: k)
    }

    /// Tags of the latest OK (design §5.6).
    public func submitTags(now: Double) -> [String] {
        guard let k = attempts.last else { return [] }
        var tags: [String] = []
        let diff = k - target
        if diff == 1 { tags.append("over_by_1") }
        if diff == -1 { tags.append("under_by_1") }
        if abs(diff) >= 2 { tags.append("off_by_2plus") }
        if k == question.count, diff != 0 { tags.append("tapped_all") }
        for (a, b) in [(6, 9), (2, 5), (1, 7)] where diff != 0 && ((target == a && k == b) || (target == b && k == a)) {
            tags.append("numeral_confusion:\(a)-\(b)")
        }
        if untaps > 0 { tags.append("untaps:\(untaps)") }
        if erases > 0 { tags.append("eraser_uses:\(erases)") }
        if let last = lastTapAt, now - last < Self.fastSubmitSeconds { tags.append("fast_submit") }
        return tags
    }

    public mutating func erase(now: Double) -> TapCountErase {
        guard eraserEnabled else { return .unavailable }
        if let last = lastEraseAt, now - last < Self.eraserCooldown { return .coolingDown }
        erases += 1
        erasesSinceSubmit += 1
        lastEraseAt = now
        lastActivityAt = now
        changesSinceSubmit += order.count
        order = []
        missFeedback = nil
        lastTapBay = nil
        if erasesSinceSubmit >= Self.eraserHideAt {
            eraserHidden = true
            eraserLocked = true
            return .clearedAndHidden
        }
        return erasesSinceSubmit == Self.eraserNudgeAt ? .clearedNudge : .cleared
    }

    /// After the 2nd miss's Think Pause: clear the picks and ring the first `target` vehicles in
    /// reading order; they stay ringed until OK (`hint_demo_count`; success is `assisted`).
    public mutating func startDemo() {
        guard isPick, stage == .tapping else { return }
        order = []
        missFeedback = nil
        lastTapBay = nil
        demoBays = Array(question.readingOrder.prefix(target))
        assisted = true
    }

    public var showsDemoRings: Bool { !demoBays.isEmpty && stage == .tapping }

    // MARK: Tracing

    /// ★★ / ★★★: the counted set parks in the strip and the numeral becomes the trace board.
    public mutating func startTracing(tolerance: LineMatchTolerance, colorIndex: Int = 0) {
        guard stage == .counted, question.tracesNumeral else { return }
        let q = NumeralGlyphs.traceQuestion(target, itemID: question.itemID, kind: question.kind, colorIndex: colorIndex)
        trace = ShapeTraceBoard(question: q, tolerance: tolerance, directionHint: true)
        stage = .tracing
    }

    /// The view's local trace copy after a pen event. Ignored unless it can only have come from
    /// the current one by pen events.
    public mutating func updateTrace(_ board: ShapeTraceBoard, now: Double) {
        guard stage == .tracing, let current = trace, board.isMonotonicSuccessor(of: current) else { return }
        trace = board
        if board.isComplete {
            stage = .done
            finishedAt = now
        }
    }

    /// ★: done after the reveal; ★★ / ★★★ done when the trace completes.
    public mutating func finishWithoutTrace(now: Double) {
        guard stage == .counted, !question.tracesNumeral else { return }
        stage = .done
        finishedAt = now
    }

    /// True when `self` can only have come from `older` by inputs (same question, stage never
    /// goes back, counters never drop).
    public func isMonotonicSuccessor(of older: TapCountBoard) -> Bool {
        guard question == older.question else { return false }
        let rank: [TapCountStage: Int] = [.tapping: 0, .counted: 1, .tracing: 2, .done: 3]
        guard (rank[stage] ?? 0) >= (rank[older.stage] ?? 0) else { return false }
        guard taps >= older.taps, submits >= older.submits, misses >= older.misses, erases >= older.erases else {
            return false
        }
        if !isPick, order.count < older.order.count { return false }
        return true
    }

    // MARK: Stats (design §3–§5 統計)

    public var tapOrderCode: String {
        order == question.readingOrder.filter { order.contains($0) } ? "reading" : "other"
    }

    public var meanTapSeconds: Double? {
        tapIntervals.isEmpty ? nil : tapIntervals.reduce(0, +) / Double(tapIntervals.count)
    }

    public var resultFields: [String: PerfValue] {
        var fields: [String: PerfValue] = [
            "practice": .string(isPick ? "tap_count_pick" : "tap_count"),
            "target": .int(target),
            "cars": .int(question.count),
            "taps": .int(taps),
            "recount_attempts": .int(recountAttempts),
            "double_taps": .int(doubleTaps),
            "tap_order": .string(tapOrderCode),
            "tap_ms_mean": .seconds(meanTapSeconds),
            "idle_nudges": .int(idleNudges),
            "idle_reprompts": .int(idleReprompts)
        ]
        if let startedAt, let finishedAt {
            fields["duration_ms"] = .int(Int(((finishedAt - startedAt) * 1000).rounded()))
        }
        if isPick {
            fields["submits"] = .int(submits)
            fields["misses"] = .int(misses)
            fields["first_try"] = .int(attempts.first == target ? 1 : 0)
            fields["attempts"] = .strings(attempts.map(String.init))
            fields["untaps"] = .int(untaps)
            fields["erasers"] = .int(erases)
            fields["eraser_locked"] = .int(eraserLocked ? 1 : 0)
            fields["pre_submit_changes"] = .int(preSubmitChanges)
            fields["assisted"] = .int(assisted ? 1 : 0)
        }
        if let trace {
            let t = trace.resultFields
            for key in ["off_path_count", "lifts", "wrong_start", "reverse_direction", "corner_overshoot", "corner_cut",
                        "end_overshoot", "strokes", "mean_dev_u", "tolerance"] {
                if let value = t[key] { fields["trace_\(key)"] = value }
            }
            fields["numeral"] = .int(target)
            fields["per_stroke"] = .strings(trace.perShapeRows.map { $0.replacingOccurrences(of: "numeral:", with: "numeral:\(target):") })
        }
        return fields
    }
}
