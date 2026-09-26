import Foundation

/// Parent-configured reward inputs for the in-memory model.
/// ADR 0002 D1/D3: callers (tests / later parent UI) supply the numbers; this type
/// does not invent a production default allowance or cap.
public struct RewardPolicy: Sendable, Equatable {
    public var initialAllowanceSeconds: TimeInterval
    public var rewardCapSeconds: TimeInterval

    public init(initialAllowanceSeconds: TimeInterval, rewardCapSeconds: TimeInterval) {
        self.initialAllowanceSeconds = initialAllowanceSeconds
        self.rewardCapSeconds = rewardCapSeconds
    }
}

/// How a completion was achieved. Assisted and unassisted are recorded separately (D7).
public enum SuccessKind: String, Sendable, Equatable {
    case unassisted
    case assisted
}

/// One recorded completion success. Distinct from the absolute session deadline (`Snapshot.endsAt`).
public struct SuccessRecord: Sendable, Equatable {
    public var completionID: String
    public var kind: SuccessKind
    public var awardedSeconds: TimeInterval
    public var recordedAt: Date
}

/// Outcome of attempting to apply a completion reward.
public enum RewardApplyOutcome: Sendable, Equatable {
    /// Reward seconds were added to today's viewing budget (may be less than requested when capped).
    case awarded(TimeInterval)
    /// The same stable completion ID was already awarded; budget unchanged.
    case duplicateRejected
}

/// Pure in-memory reward decision and viewing-budget application (P1-1).
///
/// Viewing budget is separate from answering time and from the absolute session
/// deadline (`Snapshot.endsAt` / `Session`). P1-2 will persist this state.
///
/// Day-boundary assumption (ADR 0002 D3 + D5): the "day" is the calendar day of
/// `now` in the injected `Calendar` (timezone included). Remaining viewing budget
/// does not carry into a later calendar day, and crossing midnight does not create
/// a new allowance — only an explicit entry unlock or completion award can refill.
public struct RewardLedger: Sendable {
    public private(set) var policy: RewardPolicy
    public private(set) var successRecords: [SuccessRecord]
    public private(set) var entryActivityCompleted: Bool

    /// Completion IDs that have already received a reward grant.
    private var awardedCompletionIDs: Set<String>
    /// Viewing seconds banked for `budgetDayStart`'s calendar day. Not the session `endsAt`.
    private var viewingSeconds: TimeInterval
    /// Start-of-day instant (injected calendar) that owns `viewingSeconds`. Nil = no day established.
    private var budgetDayStart: Date?

    public init(policy: RewardPolicy) {
        self.policy = policy
        self.successRecords = []
        self.entryActivityCompleted = false
        self.awardedCompletionIDs = []
        self.viewingSeconds = 0
        self.budgetDayStart = nil
    }

    /// Viewing seconds available at `now`, applying the no-next-day-carryover rule.
    public func availableViewingSeconds(now: Date, calendar: Calendar) -> TimeInterval {
        guard let dayStart = budgetDayStart else { return 0 }
        guard Self.sameCalendarDay(dayStart, now, calendar: calendar) else { return 0 }
        return max(0, viewingSeconds)
    }

    /// D1: completing the short entry activity unlocks the configured initial allowance once.
    @discardableResult
    public mutating func completeEntryActivity(now: Date, calendar: Calendar) -> TimeInterval {
        normalizeDay(now: now, calendar: calendar)
        guard !entryActivityCompleted else {
            return availableViewingSeconds(now: now, calendar: calendar)
        }
        entryActivityCompleted = true
        let granted = cappedAdd(policy.initialAllowanceSeconds, now: now, calendar: calendar)
        return granted
    }

    /// D3: award at most once per stable completion ID; enforce parent-set cap; no next-day carryover.
    @discardableResult
    public mutating func applyCompletion(
        id: String,
        rewardSeconds: TimeInterval,
        kind: SuccessKind,
        now: Date,
        calendar: Calendar
    ) -> RewardApplyOutcome {
        normalizeDay(now: now, calendar: calendar)
        guard !awardedCompletionIDs.contains(id) else { return .duplicateRejected }
        guard rewardSeconds.isFinite, rewardSeconds > 0 else {
            awardedCompletionIDs.insert(id)
            successRecords.append(
                SuccessRecord(completionID: id, kind: kind, awardedSeconds: 0, recordedAt: now)
            )
            return .awarded(0)
        }

        let granted = cappedAdd(rewardSeconds, now: now, calendar: calendar)
        awardedCompletionIDs.insert(id)
        successRecords.append(
            SuccessRecord(completionID: id, kind: kind, awardedSeconds: granted, recordedAt: now)
        )
        return .awarded(granted)
    }

    /// D7: language replay does not reduce the reward or viewing budget.
    public mutating func recordLanguageReplay(completionID: String) {
        // Intentionally a no-op on viewing budget and prior awarded seconds.
        _ = completionID
    }

    /// D2: answering does not consume viewing budget. Records nothing durable in P1-1.
    public mutating func noteAnswering(durationSeconds: TimeInterval) {
        // Intentionally a no-op on viewing budget.
        _ = durationSeconds
    }

    // MARK: - Internals

    private mutating func normalizeDay(now: Date, calendar: Calendar) {
        guard let dayStart = budgetDayStart else { return }
        if !Self.sameCalendarDay(dayStart, now, calendar: calendar) {
            // No next-day carryover and no invented daily allowance refill.
            viewingSeconds = 0
            budgetDayStart = nil
        }
    }

    private mutating func cappedAdd(
        _ requested: TimeInterval,
        now: Date,
        calendar: Calendar
    ) -> TimeInterval {
        if budgetDayStart == nil {
            budgetDayStart = Self.startOfDay(now, calendar: calendar)
        }
        let room = max(0, policy.rewardCapSeconds - viewingSeconds)
        let granted = min(max(0, requested), room)
        viewingSeconds += granted
        return granted
    }

    private static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func sameCalendarDay(_ a: Date, _ b: Date, calendar: Calendar) -> Bool {
        calendar.isDate(a, inSameDayAs: b)
    }
}
