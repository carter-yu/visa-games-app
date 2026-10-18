import Foundation

/// v0.29.0 English tap-count cards: every child-facing word, English only (no Chinese characters;
/// a test checks). Copy by Claude Code Opus 5.5 (`number-quantity/english/english-copy.md`).
/// Spoken by the en-GB voice, which reads the digits on screen as words ("Draw 4" → "draw four");
/// a recorded clip `Voice/<key>.m4a` wins when bundled. Parent-card text (bilingual) is at the end.
public enum TapCountEnglishCopy {
    private static func line(_ key: String, _ text: String) -> SpokenPrompt {
        .englishOnly(key: "en.tapCount.\(key)", text)
    }

    /// "four" (lowercase number word).
    static func word(_ n: Int) -> String { TapCountNumber.en(n) }
    /// "Four" (sentence start).
    static func Word(_ n: Int) -> String { TapCountNumber.enCapitalised(n) }
    /// ★/★★ scenes have one vehicle type and use its name; ★★★ yards are mixed, so "vehicle(s)".
    static func vehicles(_ n: Int, _ scene: TapCountScene, pick: Bool = false) -> String {
        if pick { return n == 1 ? "vehicle" : "vehicles" }
        return n == 1 ? scene.vehicleEnglishSingular : scene.vehicleEnglishPlural
    }
    static func counting(_ k: Int) -> String {
        (1...max(k, 1)).map { $0 == 1 ? Word($0) : word($0) }.joined(separator: ", ")
    }

    public static let familyTitle = "Tap & Count"
    public static func chipSubtitle(_ kind: ActivityKind) -> String {
        switch kind.tapCountBase ?? kind {
        case .tapCountTrace: return "Count & draw"
        case .tapCountPick: return "Just right"
        default: return "Tap each one"
        }
    }

    // MARK: Header prompts and voice

    public static func allPrompt(_ scene: TapCountScene) -> SpokenPrompt {
        line("all.prompt.\(scene.rawValue)", "Tap every \(scene.vehicleEnglishSingular)!")
    }
    public static func pickPrompt(_ n: Int) -> SpokenPrompt {
        line("pick.prompt.\(n)", "Tap \(n) \(n == 1 ? "vehicle" : "vehicles"), then press OK!")
    }
    public static func countedTracePrompt(_ n: Int, pick: Bool) -> SpokenPrompt {
        pick ? line("pick.right.\(n)", "Just right! Now draw \(n)!")
             : line("trace.counted.\(n)", "\(Word(n))! Now draw \(n)!")
    }
    public static func tracePrompt(_ n: Int) -> SpokenPrompt {
        line("trace.prompt.\(n)", "Start at the green arrow. Draw \(n)!")
    }
    public static let traceNext = line("trace.next", "Now the next line!")
    public static func donePrompt(_ n: Int, scene: TapCountScene) -> SpokenPrompt {
        line("done.\(n).\(scene.rawValue)", "Well done! \(Word(n)) \(vehicles(n, scene))!")
    }
    public static func traceDonePrompt(_ n: Int) -> SpokenPrompt {
        line("trace.done.\(n)", "Great! You drew \(n == 8 ? "an" : "a") \(n)!")
    }
    /// Per tap (queued, never cut).
    public static func number(_ n: Int) -> SpokenPrompt { line("number.\(n)", word(n)) }
    /// After the last tap: the noun names the whole set (what 架 does in Cantonese).
    public static func total(_ n: Int, scene: TapCountScene) -> SpokenPrompt {
        line("total.\(n).\(scene.rawValue)", "\(Word(n)) \(vehicles(n, scene))!")
    }
    public static func recount(_ k: Int) -> SpokenPrompt {
        line("pick.recount.\(k)", "\(counting(k)). That's \(word(k)).")
    }
    public static func need(_ n: Int) -> SpokenPrompt { line("pick.need.\(n)", "We need \(word(n))!") }
    public static let noneYet = line("pick.noneYet", "Tap some vehicles first!")
    /// After Clear nothing is picked, so "Try pressing OK!" would only get "Tap some vehicles first!".
    public static let eraserNudge = line("pick.eraserNudge", "Count, then press OK!")
    /// The demo rings the first N vehicles; the child taps them (it does not pick them itself).
    public static func demo(_ n: Int) -> SpokenPrompt {
        line("pick.demo.\(n)", "\(counting(n)). Tap these \(word(n)), then press OK!")
    }
    public static let cornerPrompt = line("trace.corner", "Stop! Now turn.")
    public static let offPathPrompt = line("trace.offroad", "Back onto the road!")
    public static let offPathSmall = "the car is waiting for you"
    public static let wrongStartPrompt = line("trace.wrongStart", "Start at the green arrow!")
    public static let reversePrompt = line("trace.reverse", "Follow the arrow!")

    // MARK: Bubbles

    /// Count bubble beside the badge and the reveal bubble: the lowercase word ("two").
    public static func countWord(_ n: Int) -> String { word(n) }
    public static func recountTotal(_ k: Int) -> String { "That's \(word(k))." }

    // MARK: Tray

    public static func remaining(_ n: Int) -> String { "\(n) more to go" }
    public static let allTappedTray = "All counted!"
    public static let stepTap = "Count"
    public static func stepPick(_ n: Int) -> String { "Pick \(n)" }
    public static func stepTrace(_ n: Int) -> String { "Draw \(n)" }
    public static func countedChip(_ n: Int, pick: Bool) -> (String, String) {
        ("\(Word(n))!", pick ? "\(n) picked" : "\(n) counted")
    }
    public static let traceStatus = ("Keep going!", "along the road")
    public static let lastStrokeHat = ("Now the hat on top!", "left to right")
    public static let legendTapped = ("Counted", "lit up, with a number")
    public static let legendNotYet = ("Not yet", "tap it to count it")
    public static let legendStart = ("Start", "green arrow = start")
    public static let legendStop = ("Stop", "red arrow = stop")
    public static let legendStrokeNumber = ("Line order", "line 1 first, then 2")
    public static let legendStrokeDone = ("Line done", "tick = finished")
    public static let stampNextTray = "Next: your stamp!"
    public static let noMissTray = "Nothing to get wrong"
    public static func visaTray(_ minutes: Int) -> String { "\(minutes)-minute visa" }
    public static let firstTryTray = "First try: no fuel lost"
    public static func strokesDoneTray(_ n: Int, scene: TapCountScene, pick: Bool) -> (String, String) {
        ("\(Word(n)) \(vehicles(n, scene, pick: pick))!", pick ? "all picked and drawn" : "all counted and drawn")
    }

    // MARK: Buttons, Think Pause card, ticket, sound stars

    public static let eraser = ("Clear", "all")
    public static let okSub = "Done"
    public static let thinkPause = ("Pause and think!", "Look at what you picked.")
    public static let fuelHalved = "Half the fuel is gone."
    public static func fuelDropLine(from before: Int, to after: Int) -> String { "\(before) → \(after) min · then try again" }
    public static let minutesWord = "min"
    public static let visaWord = "Visa"
    public static let tapMarkTram = "ding"
    public static let tapMarkHorn = "beep"
    public static let hint = "Hint: count one by one. Stop when you have enough."

    // MARK: Parent cards (bilingual is fine here)

    public static func parentCardTitle(_ kind: ActivityKind) -> String {
        switch kind.tapCountBase ?? kind {
        case .tapCountTrace: return "一架一架數（英文）· 數完畫"
        case .tapCountPick: return "一架一架數（英文）· 揀啱數"
        default: return "一架一架數（英文）· 點一點"
        }
    }
    public static func parentCardEnglish(_ kind: ActivityKind) -> String {
        "Tap & Count in English · \(chipSubtitle(kind))"
    }
    public static func parentShortLabel(_ kind: ActivityKind) -> String {
        switch kind.tapCountBase ?? kind {
        case .tapCountTrace: return "數完畫（英文）"
        case .tapCountPick: return "揀啱數（英文）"
        default: return "點一點（英文）"
        }
    }
    public static func parentHelpTraditionalChinese(_ kind: ActivityKind) -> String {
        "同「一架一架數」一模一樣嘅玩法，但小朋友見到同聽到嘅全部係英文（英式英語語音）。"
    }
    public static func parentHelpEnglish(_ kind: ActivityKind) -> String {
        "The same game as its Cantonese card, but everything your child sees and hears is in English (British voice)."
    }
}
