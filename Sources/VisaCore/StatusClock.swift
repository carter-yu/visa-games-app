import Foundation

// Clock + elapsed status chip C0 (0.39.0 / 85): clock-playtime design, Locked decisions 1–5 at the R2 size
// (84 × 40 u, Carter 2026-11-10), §1.2, §6, §9 C0 and Appendix A; chip-rows/compare.md FINAL v1 §5. The words the
// chip shows and speaks: the Hong Kong wall clock on the top row, the time since this app launch on the bottom row.
// Pure text: no view, timer, storage or AppModel hook (C1 draws the chip, C2 the parent bar caption).

// MARK: - Copy

/// One chip string in both board languages: `zh` on Cantonese boards, `en` on the English (ABC) boards.
public struct StatusChipText: Equatable, Sendable {
    public let zh: String
    public let en: String

    public init(zh: String, en: String) {
        self.zh = zh
        self.en = en
    }

    /// Both languages in one label, Cantonese first (design §6; the `MissionTicket.accessibilityLabel` form).
    public var bilingual: String { "\(zh) / \(en)" }
}

/// Every new chip string (Appendix A and the R2 `99+` overflow), Hong Kong Traditional Chinese and English only.
/// Appendix A rows that belong to the optional C6 play-time history (today, card, notes, flags, save banners) are
/// not here.
public enum StatusChipCopy {
    /// chip.elapsed, under 60 min: `52 分鐘` / `52 min`.
    public static func minutes(_ n: Int) -> StatusChipText {
        StatusChipText(zh: "\(n) 分鐘", en: "\(n) min")
    }

    /// chip.elapsedHours, 60 min to 99 h 59 min: `1 小時 5 分` / `1 h 5 min`.
    public static func hours(_ h: Int, minutes m: Int) -> StatusChipText {
        StatusChipText(zh: "\(h) 小時 \(m) 分", en: "\(h) h \(m) min")
    }

    /// From 100 h: the fixed-size chip never needs a third hour digit (R2 overflow policy).
    public static let overflow = StatusChipText(zh: "99+ 小時", en: "99+ h")

    /// chip.a11y: `由開App計：52 分鐘` / `Since app start: 52 min`, with the chip's own text from 60 min.
    public static func sinceStartAccessibility(_ elapsed: StatusChipText) -> StatusChipText {
        StatusChipText(zh: "由開App計：\(elapsed.zh)", en: "Since app start: \(elapsed.en)")
    }

    /// bar.sinceStart, the parent bar caption beside the chip: `由開App計 52 分鐘` / `52 min since app start`.
    public static func sinceStartCaption(_ elapsed: StatusChipText) -> StatusChipText {
        StatusChipText(zh: "由開App計 \(elapsed.zh)", en: "\(elapsed.en) since app start")
    }

    /// clock.a11y: `而家時間：下午3時45分` / `Time now: 3:45 PM`. `hour` is already 12-hour (1–12).
    public static func timeNow(afternoon: Bool, hour: Int, minute: Int) -> StatusChipText {
        let mm = twoDigits(minute)
        return StatusChipText(zh: "而家時間：\(afternoon ? "下午" : "上午")\(hour)時\(mm)分",
                              en: "Time now: \(hour):\(mm) \(afternoon ? "PM" : "AM")")
    }

    /// bar.hkTime: the parent bar's tag when the Mac's own zone is not Hong Kong (the child chip never changes).
    public static let hongKongTime = StatusChipText(zh: "香港時間", en: "HK time")
}

// MARK: - Clock

/// The chip's top row: the Mac's clock as `h:mm` (Decisions 2 and 3).
///
/// 12-hour without AM/PM or seconds, the hour without a leading zero: 00:05 → `12:05`, 12:00 → `12:00`,
/// 15:45 → `3:45`. Always Asia/Hong_Kong (`PerfClock.hongKong`, the stats files' zone), whatever the process or Mac
/// zone: Gregorian calendar fields and integer formatting, no locale and no `DateFormatter` template.
public enum StatusClockText {
    /// `3:45`.
    public static func clock(_ date: Date) -> String {
        let time = hongKongTime(date)
        return "\(twelveHour(time.hour)):\(twoDigits(time.minute))"
    }

    /// `15:45`: the 24-hour alternative (design §1.2, L1).
    public static func clock24(_ date: Date) -> String {
        let time = hongKongTime(date)
        return "\(twoDigits(time.hour)):\(twoDigits(time.minute))"
    }

    /// The spoken time with its period: `而家時間：下午3時45分` / `Time now: 3:45 PM`.
    public static func accessibility(_ date: Date) -> StatusChipText {
        let time = hongKongTime(date)
        return StatusChipCopy.timeNow(afternoon: time.hour >= 12, hour: twelveHour(time.hour), minute: time.minute)
    }

    /// Hour 0–23 and minute 0–59 on the Hong Kong wall clock. Seconds are dropped, never rounded up.
    private static func hongKongTime(_ date: Date) -> (hour: Int, minute: Int) {
        let parts = PerfClock.calendar(PerfClock.hongKong).dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func twelveHour(_ hour: Int) -> Int { hour % 12 == 0 ? 12 : hour % 12 }
}

/// `7` → `07`.
private func twoDigits(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

// MARK: - Elapsed since launch

/// The chip's bottom row: time since this app launch, counting everything (Decisions 1, 4 and 5; Q1–Q3).
///
/// Built only from two monotonic uptimes in seconds (`ProcessInfo.systemUptime`, the perf recorder's `mono`). No wall
/// clock goes in, so a clock change, NTP step or zone change cannot move it. The app reads the launch uptime once at
/// start (C1). The uptime does not advance while the Mac sleeps, so sleep is excluded without resetting the figure
/// (Q1 default); only a relaunch starts again at 0.
public struct ElapsedSinceLaunch: Equatable, Sendable {
    /// From 100 h the chip shows `99+ 小時` / `99+ h`.
    public static let overflowMinutes = 100 * 60

    /// Whole minutes, floored: `52 分鐘` means at least 52 and under 53. 0 when the uptime went backwards or an input
    /// is not finite.
    public let minutes: Int

    public init(launchUptime: TimeInterval, nowUptime: TimeInterval) {
        let seconds = nowUptime - launchUptime
        guard seconds.isFinite, seconds > 0 else {
            minutes = 0
            return
        }
        // Capped so no input can trap the conversion; the text stops at 100 h anyway.
        minutes = Int(min((seconds / 60).rounded(.down), Double(Int32.max)))
    }

    /// `0 分鐘`…`59 分鐘`, `1 小時 0 分`…`99 小時 59 分`, then `99+ 小時` (English `52 min`, `1 h 5 min`, `99+ h`).
    public var text: StatusChipText {
        if minutes >= Self.overflowMinutes { return StatusChipCopy.overflow }
        if minutes < 60 { return StatusChipCopy.minutes(minutes) }
        return StatusChipCopy.hours(minutes / 60, minutes: minutes % 60)
    }

    /// The chip's accessibility text: `由開App計：52 分鐘` / `Since app start: 52 min`.
    public var accessibility: StatusChipText { StatusChipCopy.sinceStartAccessibility(text) }

    /// The parent bar caption (C2): `由開App計 52 分鐘` / `52 min since app start`.
    public var parentCaption: StatusChipText { StatusChipCopy.sinceStartCaption(text) }
}
