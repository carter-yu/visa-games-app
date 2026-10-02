import Foundation

/// Pure wrong-answer consequences for the child activity round (Carter 2026-10-02).
///
/// Shrinks the **pending award** for this round only (chosen 5 / 10 / 15 ticket minutes).
/// Never touches banked `viewingSeconds` (D2). Always on — no parent feature flag.
public enum WrongAnswerPolicy: Sendable {
    /// Think-Pause duration after every incorrect answer (choices locked).
    public static let thinkPauseSeconds = 10

    /// Halve pending award minutes (integer division). Floor is **0** (not 1).
    /// Examples: 15→7→3→1→0; 10→5→2→1→0; 5→2→1→0.
    public static func halvedPendingMinutes(_ minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        return minutes / 2
    }

    /// After a miss that leaves pending at 0, finish the Think Pause then return to Depot
    /// (no stamp / no `startPlayVisa`).
    public static func shouldReturnToDepot(pendingMinutes: Int) -> Bool {
        pendingMinutes <= 0
    }

    /// Road tiles for the **earned** award (one tile ≈ 5 minutes). Stars may stay as the
    /// difficulty chosen; minutes / road follow the actual pending at success.
    public static func roadTiles(forEarnedMinutes minutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        return max(1, (minutes + 4) / 5)
    }

    public static func awardSeconds(fromPendingMinutes minutes: Int) -> TimeInterval {
        guard minutes > 0 else { return 0 }
        return TimeInterval(minutes * 60)
    }

    /// Mash / re-tap during Think Pause must not skip the pause or re-penalize.
    public static func shouldAcceptChoiceInput(choicesLocked: Bool) -> Bool {
        !choicesLocked
    }
}


/// HK Traditional Chinese microcopy for wrong-answer UX (never Simplified).
public enum WrongAnswerCopy: Sendable {
    /// Soft feedback after fuel halves (pending still > 0).
    public static let fuelHalvedTraditionalChinese = "油少咗半！再諗諗～"
    public static let fuelHalvedEnglish = "Half the fuel gone — think again~"

    /// Think-Pause overlay title.
    public static let thinkPauseTraditionalChinese = "停一停，想一想！"
    public static let thinkPauseEnglish = "Pause and think!"

    /// Stampy line when pending hits 0 and the child returns to Depot.
    public static let returnDepotTraditionalChinese = "油用晒喇，返車廠再試啦！"
    public static let returnDepotEnglish = "Out of fuel — back to the depot to try again!"

    public static var allTraditionalLines: [String] {
        [
            fuelHalvedTraditionalChinese,
            thinkPauseTraditionalChinese,
            returnDepotTraditionalChinese
        ]
    }
}
