import Foundation

/// Parent-configured reward inputs for the durable model.
/// ADR 0002 D1/D3: callers (tests / later parent UI) supply the numbers; this type
/// does not invent a production default allowance or cap.
public struct RewardPolicy: Sendable, Equatable, Codable {
    public var initialAllowanceSeconds: TimeInterval
    public var rewardCapSeconds: TimeInterval

    public init(initialAllowanceSeconds: TimeInterval, rewardCapSeconds: TimeInterval) {
        self.initialAllowanceSeconds = initialAllowanceSeconds
        self.rewardCapSeconds = rewardCapSeconds
    }
}

/// How a completion was achieved. Assisted and unassisted are recorded separately (D7).
public enum SuccessKind: String, Sendable, Equatable, Codable {
    case unassisted
    case assisted
}

/// One recorded completion success. Distinct from the absolute session deadline (`Snapshot.endsAt`).
public struct SuccessRecord: Sendable, Equatable, Codable {
    public var completionID: String
    public var kind: SuccessKind
    public var awardedSeconds: TimeInterval
    public var recordedAt: Date

    public init(
        completionID: String,
        kind: SuccessKind,
        awardedSeconds: TimeInterval,
        recordedAt: Date
    ) {
        self.completionID = completionID
        self.kind = kind
        self.awardedSeconds = awardedSeconds
        self.recordedAt = recordedAt
    }
}

/// Outcome of attempting to apply a completion reward.
public enum RewardApplyOutcome: Sendable, Equatable {
    /// Reward seconds were added to today's viewing budget (may be less than requested when capped).
    case awarded(TimeInterval)
    /// The same stable completion ID was already awarded; budget unchanged.
    case duplicateRejected
}

/// Durable reward/allowance fields persisted atomically inside `Snapshot` (schemaVersion 2+).
/// Viewing budget remains separate from answering time and from `Snapshot.endsAt`.
public struct RewardState: Sendable, Equatable, Codable {
    public var initialAllowanceSeconds: TimeInterval
    public var rewardCapSeconds: TimeInterval
    public var entryActivityCompleted: Bool
    /// Stable completion IDs that have already received a reward grant (sorted for stable encoding).
    public var awardedCompletionIDs: [String]
    public var successRecords: [SuccessRecord]
    /// Viewing seconds banked for `budgetDayStart`'s calendar day. Not the session `endsAt`.
    public var viewingSeconds: TimeInterval
    /// Start-of-day instant that owns `viewingSeconds`. Nil = no day established.
    public var budgetDayStart: Date?

    public init(
        initialAllowanceSeconds: TimeInterval,
        rewardCapSeconds: TimeInterval,
        entryActivityCompleted: Bool = false,
        awardedCompletionIDs: [String] = [],
        successRecords: [SuccessRecord] = [],
        viewingSeconds: TimeInterval = 0,
        budgetDayStart: Date? = nil
    ) {
        self.initialAllowanceSeconds = initialAllowanceSeconds
        self.rewardCapSeconds = rewardCapSeconds
        self.entryActivityCompleted = entryActivityCompleted
        self.awardedCompletionIDs = awardedCompletionIDs
        self.successRecords = successRecords
        self.viewingSeconds = viewingSeconds
        self.budgetDayStart = budgetDayStart
    }

    public var policy: RewardPolicy {
        RewardPolicy(
            initialAllowanceSeconds: initialAllowanceSeconds,
            rewardCapSeconds: rewardCapSeconds
        )
    }
}

/// Pure reward decision and viewing-budget application with durable export/import (P1-2).
///
/// Viewing budget is separate from answering time and from the absolute session
/// deadline (`Snapshot.endsAt` / `Session`).
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

    /// Restore from durable snapshot state. Call `normalizeAfterLoad` after restore.
    public init(state: RewardState) {
        self.policy = state.policy
        self.successRecords = state.successRecords
        self.entryActivityCompleted = state.entryActivityCompleted
        self.awardedCompletionIDs = Set(state.awardedCompletionIDs)
        self.viewingSeconds = state.viewingSeconds
        self.budgetDayStart = state.budgetDayStart
    }

    /// Export durable fields for atomic persistence with `Snapshot`.
    public func exportState() -> RewardState {
        RewardState(
            initialAllowanceSeconds: policy.initialAllowanceSeconds,
            rewardCapSeconds: policy.rewardCapSeconds,
            entryActivityCompleted: entryActivityCompleted,
            awardedCompletionIDs: awardedCompletionIDs.sorted(),
            successRecords: successRecords,
            viewingSeconds: viewingSeconds,
            budgetDayStart: budgetDayStart
        )
    }

    /// Normalize day-boundary / stale budget on relaunch, wake, or clock change.
    /// Does not invent a new allowance or reset parent-configured policy.
    public mutating func normalizeAfterLoad(now: Date, calendar: Calendar) {
        normalizeDay(now: now, calendar: calendar)
        if viewingSeconds > policy.rewardCapSeconds {
            viewingSeconds = max(0, policy.rewardCapSeconds)
        }
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

    /// D2: answering does not consume viewing budget.
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
