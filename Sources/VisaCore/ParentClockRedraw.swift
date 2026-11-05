import Foundation

/// Whether a 0.5 s tick must redraw the shell (build 78). `now` is no longer @Published, so
/// the plain parent settings page is not rebuilt twice a second (snap HYPOTHESIS 2).
public enum ParentClockRedraw {
    /// - previous: the clock value the screen was last drawn with (the old `now`).
    /// - current: this tick's time.
    /// Child modes, the parent playtest cover and the parent finder draw from the clock on
    /// every tick. The settings page draws from it only for the 加咗 card flash: every tick
    /// while the flash was or is active, so the tick that crosses `flashUntil` (however late,
    /// e.g. after a stall or sleep) redraws once and the card does not stay lit.
    public static func needed(isParent: Bool, playtest: Bool, browserOpen: Bool,
                              flashUntil: Date?, previous: Date, current: Date) -> Bool {
        guard isParent else { return true }
        if playtest || browserOpen { return true }
        guard let flashUntil else { return false }
        return previous < flashUntil || current < flashUntil
    }
}
