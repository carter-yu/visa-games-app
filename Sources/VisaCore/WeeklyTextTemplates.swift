import Foundation

// Weekly report W3 (weekly-report design §6.2–6.7, §7): the template registry and the word catalogue.
// Every sentence the report prints comes from one template here: an id, typed slots, the Hong Kong
// Traditional Chinese text and the English text. Copy is from the design where it gives copy; ADR 0023
// lists every sentence written for a gap. Selection (first matching template wins) is in WeeklyReportText.

/// One slot of a template.
public struct WeeklySlot: Sendable, Equatable {
    public let name: String
    public let type: WeeklySlotType

    public init(name: String, type: WeeklySlotType) {
        self.name = name
        self.type = type
    }
}

/// One template (design §6.2): id, typed slots, the two sentences and when it is used.
public struct WeeklyTemplate: Sendable, Equatable {
    public let id: String
    public let zh: String
    public let en: String
    public let slots: [WeeklySlot]
    /// The precondition, in words (the selection code is in `WeeklyReportText`).
    public let when: String
}

/// A word or phrase in both languages.
public struct WeeklyWords: Sendable, Equatable {
    public let zh: String
    public let en: String

    public init(_ zh: String, _ en: String) {
        self.zh = zh
        self.en = en
    }

    public var value: WeeklySlotValue { .words(zh: zh, en: en) }
}

private func entry(_ id: String, _ zh: String, _ en: String, _ slots: [(String, WeeklySlotType)] = [],
                   when: String) -> WeeklyTemplate {
    WeeklyTemplate(id: id, zh: zh, en: en, slots: slots.map { WeeklySlot(name: $0.0, type: $0.1) }, when: when)
}

public enum WeeklyTemplates {
    /// Pieces of sentences.
    static let fragments: [WeeklyTemplate] = [
        entry("frag.quiz", "{n} 局入面 {k} 局一次答啱", "{k} of {n} right first time", [("n", .int), ("k", .int)],
              when: "quiz fact, k < n"),
        entry("frag.quiz.all", "{n} 局全部一次答啱", "right first time in all {n}", [("n", .int)], when: "quiz fact, k == n"),
        entry("frag.practice", "{n} 局入面 {k} 局做得順", "smooth in {k} of {n}", [("n", .int), ("k", .int)],
              when: "practice fact, k < n"),
        entry("frag.practice.all", "{n} 局全部做得順", "smooth in all {n}", [("n", .int)], when: "practice fact, k == n"),
        entry("frag.offPath.road", "平均每條路出界 {x} 次", "off the road {x} times per road", [("x", .decimal)],
              when: "road evidence"),
        entry("frag.offPath.shape", "平均每個形狀出界 {x} 次", "off the path {x} times per shape", [("x", .decimal)],
              when: "shape evidence"),
        entry("frag.offPath.line", "平均每條線出界 {x} 次", "off the path {x} times per line", [("x", .decimal)],
              when: "line evidence"),
        entry("frag.helps", "描數字平均每次要提示 {h} 次", "needed about {h} hints per numeral", [("h", .decimal)],
              when: "count-then-trace evidence"),
        entry("frag.wrongStart", "{w}/{n} 次唔係由綠色起點開始", "started away from the green start in {w} of {n}",
              [("w", .int), ("n", .int)], when: "wrong-start evidence"),
        entry("trend.same", "（上星期 {p0}%，差唔多）", " (last week {p0}%, about the same)", [("p0", .percent)],
              when: "§4.10 same"),
        entry("trend.up", "（上星期 {p0}%，明顯進步）", " (last week {p0}%, clearly up)", [("p0", .percent)],
              when: "§4.10 up"),
        entry("trend.down", "（上星期 {p0}%，明顯少咗）", " (last week {p0}%, clearly down)", [("p0", .percent)],
              when: "§4.10 down"),
        entry("trend.unsure", "（上星期 {p0}%，變化未夠肯定）", " (last week {p0}%, change not clear yet)",
              [("p0", .percent)], when: "§4.10 unsure"),
        entry("vs.more", "，比上星期多 {d} 局", ", {d} more than last week", [("d", .int)], when: "more rounds than last week"),
        entry("vs.fewer", "，比上星期少 {d} 局", ", {d} fewer than last week", [("d", .int)],
              when: "fewer rounds than last week"),
        entry("vs.same", "，同上星期一樣", ", same as last week", when: "as many rounds as last week"),
        entry("noPlay", "（{days}冇玩）", " (none on {days})", [("days", .text)], when: "covered days without play"),
        entry("soFar.quizAll", "，全部一次答啱", ", all right first time", when: "數據唔夠 quiz, k == n"),
        entry("soFar.practiceAll", "，全部做得順", ", all smooth", when: "數據唔夠 practice, k == n"),
        entry("soFar.new", "（第一個星期玩）", " (first week)", when: "數據唔夠, new this week"),
        entry("pointer.video", "睇片時間第 {page} 頁有個問題想問你哋。", " Page {page} has a question about video time.",
              [("page", .int)], when: "Q1 is asked"),
        entry("list.item", "「{game}」（{k}/{n}）", "\"{game}\" ({k}/{n})",
              [("game", .gameName), ("k", .int), ("n", .int)], when: "page-4 other lists"),
        entry("video.item", "「{title}」（{time}）", "\"{title}\" ({time})", [("title", .verbatim), ("time", .minutes)],
              when: "D8 B video titles"),
        entry("setting.change", "{name}：{old} → {new}", "{name}: {old} → {new}",
              [("name", .words), ("old", .words), ("new", .words)], when: "⚙ with old and new labels"),
        entry("setting.value", "{name}：{new}", "{name}: {new}", [("name", .words), ("new", .words)],
              when: "⚙ with a new label only"),
        entry("setting.name", "{name}", "{name}", [("name", .words)], when: "⚙ without labels"),
        entry("setting.on", "開咗「{game}」{stars}", "turned on {stars} for \"{game}\"",
              [("game", .gameName), ("stars", .words)], when: "⚙ star assignment on"),
        entry("setting.off", "熄咗「{game}」{stars}", "turned off {stars} for \"{game}\"",
              [("game", .gameName), ("stars", .words)], when: "⚙ star assignment off"),
        entry("ev.game", "「{game}」{fact}", "\"{game}\" {fact}", [("game", .gameName), ("fact", .text)],
              when: "evidence for one game"),
        entry("ev.fuel", "「{game}」有 {z} 次油用晒", "\"{game}\" ran out of fuel {z} times",
              [("game", .gameName), ("z", .int)], when: "F6 evidence"),
        entry("ev.fast", "「{game}」好多次未聽完題目就撳（{f}/{w} 次）",
              "\"{game}\" often tapped before the question finished ({f} of {w})",
              [("game", .gameName), ("f", .int), ("w", .int)], when: "F7 evidence"),
        entry("ev.ratio", "「{game}」{k}/{n}", "\"{game}\" {k}/{n}", [("game", .gameName), ("k", .int), ("n", .int)],
              when: "A5 evidence"),
        entry("ev.list", "{items}。", "{items}.", [("items", .text)], when: "evidence sentence")
    ]

    /// Page 1 (§6.4) and the empty week (§3).
    static let pageOne: [WeeklyTemplate] = [
        entry("wr.empty", "今個星期未有紀錄。", "No play recorded this week.", when: "no countable play (§3)"),
        entry("hl.volume", "今個星期有 {days} 日玩{noPlayDays}，總共 {rounds} 局：答題 {quiz} 局、練習 {practice} 局{vsLast}。",
              "Played on {days} days{noPlayDays}: {rounds} rounds in all, {quiz} quiz and {practice} practice{vsLast}.",
              [("days", .int), ("noPlayDays", .text), ("rounds", .int), ("quiz", .int), ("practice", .int),
               ("vsLast", .text)], when: "any play"),
        entry("hl.volume.oneDay",
              "今個星期有 {days} 日玩{noPlayDays}，總共 {rounds} 局：答題 {quiz} 局、練習 {practice} 局{vsLast}。",
              "Played on {days} day{noPlayDays}: {rounds} rounds in all, {quiz} quiz and {practice} practice{vsLast}.",
              [("days", .int), ("noPlayDays", .text), ("rounds", .int), ("quiz", .int), ("practice", .int),
               ("vsLast", .text)], when: "play on one day"),
        entry("hl.rates", "答題遊戲第一次答啱 {p}%{pTrend}；練習遊戲做得順 {s}%{sTrend}。",
              "Quiz games right first time {p}%{pTrend}; practice games done smoothly {s}%{sTrend}.",
              [("p", .percent), ("pTrend", .text), ("s", .percent), ("sTrend", .text)],
              when: "quiz ≥ 5 and practice ≥ 5"),
        entry("hl.rates.quiz", "答題遊戲第一次答啱 {p}%{pTrend}。", "Quiz games right first time {p}%{pTrend}.",
              [("p", .percent), ("pTrend", .text)], when: "quiz ≥ 5, practice < 5"),
        entry("hl.rates.practice", "練習遊戲做得順 {s}%{sTrend}。", "Practice games done smoothly {s}%{sTrend}.",
              [("s", .percent), ("sTrend", .text)], when: "practice ≥ 5, quiz < 5"),
        entry("hl.games", "最穩陣係「{top1}」（{top1Fact}）；「{bot1}」仲學緊，{bot1Fact}。",
              "Steadiest: \"{top1}\" ({top1Fact}); still learning \"{bot1}\": {bot1Fact}.",
              [("top1", .gameName), ("top1Fact", .text), ("bot1", .gameName), ("bot1Fact", .text)],
              when: "≥ 1 going well and ≥ 1 still learning"),
        entry("hl.games.top", "最穩陣係「{top1}」（{top1Fact}）。", "Steadiest: \"{top1}\" ({top1Fact}).",
              [("top1", .gameName), ("top1Fact", .text)], when: "going well, none still learning"),
        entry("hl.games.bottom", "「{bot1}」仲學緊，{bot1Fact}。", "Still learning \"{bot1}\": {bot1Fact}.",
              [("bot1", .gameName), ("bot1Fact", .text)], when: "still learning, none going well"),
        entry("hl.games.none", "每個遊戲都玩得唔多，下星期再睇排名。",
              "Each game had only a few rounds; we'll look at rankings next week.", when: "not ranked"),
        entry("hl.time", "遊戲大約 {g}，睇片大約 {v}，賺到簽證 {visa}。{videoPointer}",
              "About {g} of games and {v} of videos; {visa} of visa earned.{videoPointer}",
              [("g", .minutes), ("v", .minutes), ("visa", .minutes), ("videoPointer", .text)], when: "any time"),
        entry("videos.top", "睇得最多嘅片：{items}。", "Most-watched videos: {items}.", [("items", .text)],
              when: "D8 B: top 3 videos by watched minutes")
    ]

    /// §6.5.
    static let wins: [WeeklyTemplate] = [
        entry("win.newGame", "第一次玩「{game}」。", "First time playing \"{game}\".", [("game", .gameName)],
              when: "W2 win.newGame"),
        entry("win.numeral", "識咗自己描數字 {list}（唔使提示）。", "Can now trace {list} without help.", [("list", .text)],
              when: "W2 win.numeral"),
        entry("win.streak", "「{game}」連續 {n} 次一次答啱。", "\"{game}\": right first time {n} times in a row.",
              [("game", .gameName), ("n", .int)], when: "W2 win.streak"),
        entry("win.rise", "「{game}」比上星期順咗：{k0}/{n0} → {k1}/{n1}。",
              "\"{game}\" went better than last week: {k0}/{n0} → {k1}/{n1}.",
              [("game", .gameName), ("k0", .int), ("n0", .int), ("k1", .int), ("n1", .int)], when: "W2 win.rise"),
        entry("win.firstSmooth", "第一次順順利利完成「{game}」。", "First smooth round of \"{game}\".", [("game", .gameName)],
              when: "W2 win.firstSmooth"),
        entry("win.firstTry", "第一次一次答啱「{game}」。", "First right-first-time on \"{game}\".", [("game", .gameName)],
              when: "W2 win.firstTry"),
        entry("win.cleanDay", "{day}答題全部一次答啱（{n} 局）。", "{day}: every quiz round right first time ({n}).",
              [("day", .dayName), ("n", .int)], when: "W2 win.cleanDay"),
        entry("win.noFuelOut", "成個星期冇一次油用晒。", "Never ran out of fuel all week.", when: "W2 win.noFuelOut")
    ]

    /// §6.6 game comments.
    static let comments: [WeeklyTemplate] = [
        entry("top.ft", "{n} 次入面 {k} 次一次答啱（亂估都有大約 {c}%），好穩陣。",
              "Right first time in {k} of {n} (guessing alone gives about {c}%) — very steady.",
              [("n", .int), ("k", .int), ("c", .percent)], when: "going well, quiz, k < n"),
        entry("top.ft.short", "亂估都有大約 {c}%，佢明顯高好多，好穩陣。",
              "Guessing alone gives about {c}% — well above that, very steady.", [("c", .percent)],
              when: "going well, quiz, page 4"),
        entry("top.all", "{n} 次全部一次答啱。", "Right first time in all {n} rounds.", [("n", .int)],
              when: "going well, quiz, k == n"),
        entry("top.memorised", "次次都係同一條題目，可能已經記住咗，可以加新題目。",
              "Same question every time — it may be memorised; new versions would help.",
              when: "extra, fixed kind, n ≥ 10, p ≥ 90 %"),
        entry("top.smooth", "{n} 次入面 {k} 次做得好順。", "Smooth in {k} of {n} rounds.", [("n", .int), ("k", .int)],
              when: "going well, practice, k < n"),
        entry("top.smooth.all", "{n} 次全部做得好順。", "Smooth in all {n} rounds.", [("n", .int)],
              when: "going well, practice, k == n"),
        entry("top.smooth.short", "平均每個形狀出界 {x} 次，好少出界。",
              "{x} off-path per shape on average — rarely off the path.", [("x", .decimal)],
              when: "going well, shapes, page 4, off-path < 1 per shape"),
        entry("top.smooth.short.line", "平均每條線出界 {x} 次，好少出界。",
              "{x} off-path per line on average — rarely off the path.", [("x", .decimal)],
              when: "going well, lines, page 4, off-path < 1 per line"),
        entry("top.smooth.plain", "做得好順。", "Going smoothly.", when: "going well, practice, page 4, otherwise"),
        entry("bot.ft", "呢個遊戲對佢仲有啲難：{n} 次入面 {k} 次一次答啱。",
              "This one is still tricky: right first time in {k} of {n}.", [("n", .int), ("k", .int)],
              when: "still learning, quiz"),
        entry("bot.ft.short", "呢個遊戲對佢仲有啲難，可以多啲練習。", "This one is still tricky — room to practise.",
              when: "still learning, page 4, no tag / ⚙ / fuel extra; practice otherwise"),
        entry("bot.tag", "錯嘅時候多數係「{tag}」（{m}/{w} 次）。", "When wrong, usually \"{tag}\" ({m} of {w}).",
              [("tag", .tagName), ("m", .int), ("w", .int)], when: "extra, quiz, approved top tag (§4.4)"),
        entry("bot.fuel", "有 {z} 次油用晒，建議大人陪玩一次。", "Ran out of fuel {z} times — try playing it together once.",
              [("z", .int)], when: "extra, quiz, fuel-outs ≥ 2"),
        entry("bot.stars", "★★★ 題目難啲（{k3}/{n3}），★／★★ 就順好多（{k12}/{n12}）。",
              "★★★ questions are harder ({k3}/{n3}); ★/★★ go much better ({k12}/{n12}).",
              [("k3", .int), ("n3", .int), ("k12", .int), ("n12", .int)], when: "extra, §5.4 rule"),
        entry("bot.fast", "好多次未聽完題目就撳（{f}/{w} 次）。", "Often tapped before the question finished ({f} of {w}).",
              [("f", .int), ("w", .int)], when: "extra, quiz, fast wrong ≥ 30 % with ≥ 3 wrongs"),
        entry("bot.offPath", "平均每條路出界 {x} 次。", "Off the road {x} times per road on average.", [("x", .decimal)],
              when: "still learning, roads, off-path ≥ 1 per road"),
        entry("bot.offPath.shape", "平均每個形狀出界 {x} 次。", "Off the path {x} times per shape on average.",
              [("x", .decimal)], when: "still learning, shapes, off-path ≥ 1 per shape"),
        entry("bot.offPath.line", "平均每條線出界 {x} 次。", "Off the path {x} times per line on average.",
              [("x", .decimal)], when: "still learning, lines, off-path ≥ 1 per line"),
        entry("bot.wrongStart", "{w}/{n} 次唔係由綠色起點開始。", "Started away from the green start in {w} of {n}.",
              [("w", .int), ("n", .int)], when: "extra, practice, wrong_start > 0 in ≥ 40 % of rounds"),
        entry("bot.helps", "描數字平均每次要提示 {h} 次。", "Needed about {h} hints per numeral.", [("h", .decimal)],
              when: "still learning, count-then-trace"),
        entry("any.settings", "今個星期改咗設定（{setting}），同上星期比要小心。",
              "Settings changed this week ({setting}); compare with last week carefully.", [("setting", .text)],
              when: "extra, ⚙"),
        entry("insuff.n", "玩咗 {n} 次{soFar}，再玩 {r} 局就排名。", "Played {n}×{soFar}; {r} more to rank.",
              [("n", .int), ("soFar", .text), ("r", .int)], when: "數據唔夠, 1 ≤ n < 5"),
        entry("insuff.zero", "再玩 {r} 局就排名。", "{r} more to rank.", [("r", .int)], when: "數據唔夠, n == 0"),
        entry("insuff.oneDay", "{n} 局都喺同一日玩，下星期再睇。", "All {n} rounds on one day — we'll look again next week.",
              [("n", .int)], when: "數據唔夠, all rounds on one day"),
        entry("insuff.noMethod", "未有評分方法。", "No scoring method yet.", when: "數據唔夠, no scoring method")
    ]

    /// Page 4 (§3, §5.3) and page 5 (§3).
    static let pages: [WeeklyTemplate] = [
        entry("rank.notRanked", "今個星期玩得太少，未排名。", "Too little play this week to rank the games.",
              when: "fewer than 2 qualified games"),
        entry("rank.allLearning", "今個星期每個遊戲都仲學緊，慢慢嚟。", "Every game is still being learned this week — no rush.",
              when: "ranked, no going-well game"),
        entry("rank.split", "答題 {quiz} 個、練習 {practice} 個", "{quiz} quiz, {practice} practice",
              [("quiz", .int), ("practice", .int)], when: "list heading"),
        entry("rank.alsoWell", "其他都做得好：{items}", "Also going well: {items}", [("items", .text)],
              when: "其他都做得好"),
        entry("rank.alsoLearning", "其他仲學緊：{items}", "Also still learning: {items}", [("items", .text)],
              when: "其他仲學緊"),
        entry("changes.none", "今個星期冇改設定", "No settings changed this week", when: "no settings or star changes")
    ]

    /// §7.1.
    static let family: [WeeklyTemplate] = [
        entry("F1", "一齊數嘢：落街數巴士、食飯數碗筷，每數一樣用手指點一下，最後講「總共幾多個」。",
              "Count things together: buses outside, bowls at dinner. Touch each one, then say how many altogether.",
              when: "a 數字・數量 quiz game is still learning"),
        entry("F2", "玩「搵相同」：拎兩三架玩具車，問「邊架同呢架一樣？」，再講出邊度唔同。",
              "Play \"find the same\" with two or three toy cars, then talk about what is different.",
              when: "a 觀察・配對 quiz game is still learning"),
        entry("F3", "用玩具車排隊「由短到長」；問「邊個位空咗？」「邊架載得多啲人？」",
              "Line up toy cars short to long; ask \"which spot is empty?\", \"which carries more people?\"",
              when: "a 比較・概念 quiz game is still learning"),
        entry("F4", "用粗蠟筆喺大張紙畫直線同圓圈，由綠點開始畫到紅點。",
              "With a fat crayon on big paper, draw lines and circles from a green dot to a red dot.",
              when: "a 手眼・畫線 game is still learning or often starts away from the green dot (shapes)"),
        entry("F4.roads", "用粗蠟筆喺大張紙畫直線同彎路，由綠點開始畫到紅點，慢慢跟住條路行。",
              "With a fat crayon on big paper, draw straight and curvy roads from a green dot to a red dot, slowly.",
              when: "F4 for a road game"),
        entry("F5", "喺白板或者沙度一齊寫數字，邊寫邊講口訣；由佢已經識嘅 {learned} 開始。",
              "Write numbers together on a whiteboard or in sand, saying the rhyme; start with {learned}, already learned.",
              [("learned", .text)], when: "count-then-trace still learning or help-heavy, numerals learned"),
        entry("F5.plain", "喺白板或者沙度一齊寫數字，邊寫邊講口訣。",
              "Write numbers together on a whiteboard or in sand, saying the rhyme.", when: "F5, no numeral learned"),
        entry("F6", "陪佢玩一次「{game}」，大人講出自己點諗。", "Play \"{game}\" together once and think aloud.",
              [("game", .gameName)], when: "fuel-outs ≥ 2 in a game"),
        entry("F7", "陪佢玩一兩局，提醒佢「聽完先撳」。", "Play a round or two together: \"listen first, then tap\".",
              when: "a quiz game with fast wrong ≥ 30 % (≥ 3 wrongs)"),
        entry("F8", "見到佢做得好，讚佢做嘅過程：「你好細心咁睇{winObject}！」，唔使講「你好聰明」。",
              "When something goes well, praise the effort: \"You looked at {winObject} so carefully!\" rather than \"you're clever\".",
              [("winObject", .words)], when: "any win (closing line)"),
        entry("rec.none", "今個星期冇特別建議，照舊就得。", "No special suggestions this week — carry on as usual.",
              when: "no family rule fires")
    ]

    /// §7.2.
    static let app: [WeeklyTemplate] = [
        entry("A1", "開「{pick}」★（要先試玩）：練「數出 N 架」。", "Turn on \"{pick}\" ★ (playtest it first) to practise \"pick N cars\".",
              [("pick", .gameName)], when: "countVehicles or moreFewer still learning, tapCountPick not played"),
        entry("A1.because", "{items}；「{pick}」今個星期未玩過。", "{items}; \"{pick}\" was not played this week.",
              [("items", .text), ("pick", .gameName)], when: "A1 evidence"),
        entry("A1.check", "「{game}」第一次答啱率；「{pick}」玩夠 {min} 局", "\"{game}\" right first time; \"{pick}\" played {min}+ rounds",
              [("game", .gameName), ("pick", .gameName), ("min", .int)], when: "A1 check"),
        entry("A2", "數字範圍收窄：「數字範圍」由「{from}」改做「{to}」；「點車讀數」保持開。",
              "Smaller numbers: set Numbers from {from} to {to}; keep counting aloud on.",
              [("from", .range), ("to", .range)], when: "點數 smooth < 60 %, count aloud on"),
        entry("A2.voice", "數字範圍收窄：「數字範圍」由「{from}」改做「{to}」；「點車讀數」改返開。",
              "Smaller numbers: set Numbers from {from} to {to}; turn counting aloud back on.",
              [("from", .range), ("to", .range)], when: "點數 smooth < 60 %, count aloud off"),
        entry("A2.because", "「{game}」{n} 局入面有 {r} 局要重新數。", "\"{game}\" needed a recount in {r} of {n} rounds.",
              [("game", .gameName), ("n", .int), ("r", .int)], when: "A2 evidence"),
        entry("A2.check", "點數做得順嘅比例", "tap-to-count smooth rate", when: "A2 check"),
        entry("A3", "數字範圍加大：「數字範圍」由「{from}」改做「{to}」。", "Bigger numbers: set Numbers from {from} to {to}.",
              [("from", .range), ("to", .range)], when: "點數 smooth ≥ 90 % two weeks at 1–5 or 1–7"),
        entry("A3.because", "「{game}」連續兩個星期都做得順：今個星期 {k1}/{n1}，上星期 {k0}/{n0}。",
              "\"{game}\" smooth two weeks running: {k1}/{n1} this week, {k0}/{n0} last week.",
              [("game", .gameName), ("k1", .int), ("n1", .int), ("k0", .int), ("n0", .int)], when: "A3 evidence"),
        entry("A3.check", "做得順保持 {keep}% 以上", "smooth stays at {keep}% or more", [("keep", .int)], when: "A3 check"),
        entry("A4", "描數字提示加多：「描數字提示」由「{current}」改做「{suggested}」。",
              "More tracing help: set \"Tracing help\" from {current} to {suggested}.",
              [("current", .words), ("suggested", .words)], when: "count-then-trace help-heavy or smooth < 50 %"),
        entry("A4.to", "描數字提示加多：「描數字提示」改做「{suggested}」。", "More tracing help: set \"Tracing help\" to {suggested}.",
              [("suggested", .words)], when: "A4, guidance not recorded"),
        entry("A4.scaffold", "描數字提示加多：「描數字」由「{current}」改做「{suggested}」。",
              "More tracing help: set the trace guide from \"{current}\" to \"{suggested}\".",
              [("current", .words), ("suggested", .words)], when: "A4, guidance already more, scaffold outline"),
        entry("A4.check", "每次要幾多提示、識咗幾多個數字", "hints per numeral; numerals learned", when: "A4 check"),
        entry("A4b", "提示減少：「描數字提示」由「{current}」改做「{suggested}」。",
              "Less tracing help: set \"Tracing help\" from {current} to {suggested}.",
              [("current", .words), ("suggested", .words)], when: "guide_clean ≥ 80 % two weeks"),
        entry("A4b.to", "提示減少：「描數字提示」改做「{suggested}」。", "Less tracing help: set \"Tracing help\" to {suggested}.",
              [("suggested", .words)], when: "A4b, guidance not recorded"),
        entry("A4b.scaffold", "提示減少：「描數字」由「{current}」改做「{suggested}」。",
              "Less tracing help: set the trace guide from \"{current}\" to \"{suggested}\".",
              [("current", .words), ("suggested", .words)], when: "A4b, guidance already less, scaffold dots"),
        entry("A4b.because", "「{game}」唔使提示嘅局數：今個星期 {k1}/{n1}，上星期 {k0}/{n0}。",
              "\"{game}\" traced without help: {k1}/{n1} this week, {k0}/{n0} last week.",
              [("game", .gameName), ("k1", .int), ("n1", .int), ("k0", .int), ("n0", .int)], when: "A4b evidence"),
        entry("A4b.check", "做得順保持 {keep}% 以上", "smooth stays at {keep}% or more", [("keep", .int)], when: "A4b check"),
        entry("A5", "加題目變化：{games}次次都係同一條題目，答啱九成以上，可能已經記住。",
              "Add question variants: {games} always show the same question and are right over {rate}% of the time.",
              [("games", .text), ("rate", .int)], when: "fixed kinds with p ≥ 90 % over ≥ 10 rounds"),
        entry("A5.one", "加題目變化：{games}次次都係同一條題目，答啱九成以上，可能已經記住。",
              "Add question variants: {games} always shows the same question and is right over {rate}% of the time.",
              [("games", .text), ("rate", .int)], when: "A5 for one kind"),
        entry("A5.because", "{items}（第一次答啱／局數）。", "{items} (right first time / rounds).", [("items", .text)],
              when: "A5 evidence"),
        entry("A5.check", "新題目出咗之後嘅第一次答啱率", "right first time on the new versions", when: "A5 check"),
        entry("A6.bridge", "「沿路過橋」暫時只開 ★，等「沿路送」做得順先加返；寬容度已經係「{wide}」，唔使再改。",
              "Keep \"Bridge road\" at ★ only for now and let \"Straight road\" lead; tolerance is already {wide}.",
              [("wide", .words)], when: "A6, bridge at ★★/★★★, tolerance already wide"),
        entry("A6.bridge.wide",
              "「沿路過橋」暫時只開 ★，等「沿路送」做得順先加返；或者將「連一連寬容度」由「{current}」改做「{wide}」。",
              "Keep \"Bridge road\" at ★ only for now and let \"Straight road\" lead; or set Line Match tolerance from {current} to {wide}.",
              [("current", .words), ("wide", .words)], when: "A6, bridge at ★★/★★★, tolerance not wide"),
        entry("A6.bridge.only", "「沿路過橋」暫時只開 ★，等「沿路送」做得順先加返。",
              "Keep \"Bridge road\" at ★ only for now and let \"Straight road\" lead.",
              when: "A6, bridge at ★★/★★★, tolerance not recorded"),
        entry("A6.wide", "將「連一連寬容度」由「{current}」改做「{wide}」。", "Set Line Match tolerance from {current} to {wide}.",
              [("current", .words), ("wide", .words)], when: "A6, tolerance not wide"),
        entry("A6.check", "沿路連線做得順嘅比例、每條路出界幾多次", "road matching smooth rate; times off the road per road",
              when: "A6 check"),
        entry("A7", "「{game}」少啲出「{category}」題目：比例減 {step}。",
              "Fewer \"{category}\" questions in \"{game}\": lower its weight by {step}.",
              [("game", .gameName), ("category", .words), ("step", .int)],
              when: "lineMatch still learning, ≥ 60 % of ≥ 4 wrong lines in one category"),
        entry("A7.because", "錯嘅線有 {m}/{w} 條係「{category}」題目。", "{m} of {w} wrong lines were \"{category}\" questions.",
              [("m", .int), ("w", .int), ("category", .words)], when: "A7 evidence"),
        entry("A7.check", "「{game}」第一次答啱率", "\"{game}\" right first time", [("game", .gameName)], when: "A7 check"),
        entry("A8", "開「方向提示」：畫形狀時只可以跟箭嘴方向畫。",
              "Turn on \"Direction hint\": shapes are drawn in the arrow direction only.",
              when: "shapes wrong_start in ≥ 40 % of ≥ 5 rounds, direction hint off"),
        entry("A8.check", "唔係由起點開始嘅比例", "share of rounds started away from the start", when: "A8 check"),
        entry("A9", "可以試斜線：開「畫直線加斜線」（設計建議大約 {age} 歲半）。",
              "Try slant lines: turn on \"Slant line in Lines\" (the design suggests about age {age}½).", [("age", .int)],
              when: "traceLines smooth ≥ 90 % over ≥ 10 rounds in two weeks, slant off"),
        entry("A9.because", "「{game}」兩個星期 {n} 局入面 {k} 局做得順。", "\"{game}\" smooth in {k} of {n} over two weeks.",
              [("game", .gameName), ("n", .int), ("k", .int)], when: "A9 evidence"),
        entry("A9.check", "「{game}」做得順保持 {keep}% 以上", "\"{game}\" smooth stays at {keep}% or more",
              [("game", .gameName), ("keep", .int)], when: "A9 check"),
        entry("A10.numbers", "多做一款「{area}」遊戲：數字 ↔ 數量配對，或者「邊個係 {n}？」",
              "Add another \"{area}\" game: numeral ↔ quantity matching, or \"Which one is {n}?\"",
              [("area", .words), ("n", .int)], when: "A10 for 數字・數量"),
        entry("A10", "多做一款「{area}」遊戲。", "Add another \"{area}\" game.", [("area", .words)],
              when: "a quiz area lowest two weeks running, or ≥ 2 of its quiz games still learning"),
        entry("A10.because.lowest",
              "「{area}」連續兩個星期係最低嘅答題類別：今個星期 {p1}%（亂估都有大約 {c}%），上星期 {p0}%。",
              "\"{area}\" was the lowest quiz area two weeks running: {p1}% this week (guessing gives about {c}%), {p0}% last week.",
              [("area", .words), ("p1", .percent), ("c", .percent), ("p0", .percent)], when: "A10 evidence, lowest"),
        entry("A10.because.learning", "「{area}」有 {count} 個答題遊戲仲學緊：{games}。",
              "{count} \"{area}\" quiz games are still learning: {games}.",
              [("area", .words), ("count", .int), ("games", .text)], when: "A10 evidence, still learning"),
        entry("A10.check", "「{area}」嘅第一次答啱率（兩個星期）", "right first time in \"{area}\" over two weeks",
              [("area", .words)], when: "A10 check"),
        entry("A11", "「{area}」可以加難度：★★★ 題目／{choices} 個選擇。", "\"{area}\" can get harder: ★★★ questions or {choices} choices.",
              [("area", .words), ("choices", .int)], when: "every ranked quiz game of an area going well two weeks"),
        entry("A11.because", "「{area}」嘅遊戲連續兩個星期都做得好：{games}。",
              "Every ranked \"{area}\" game went well two weeks running: {games}.",
              [("area", .words), ("games", .text)], when: "A11 evidence"),
        entry("A11.check", "繼續做得好", "stays going well", when: "A11 check"),
        entry("A12", "試吓題目講完先解鎖選擇（UX 實驗）。",
              "Try unlocking the choices only after the question has been read out (UX experiment).",
              when: "fast wrong ≥ 30 % of ≥ 3 wrongs across quiz games"),
        entry("A12.because", "答錯嘅時候，有 {f}/{w} 次係未聽完題目就撳。", "{f} of {w} wrong taps came before the question finished.",
              [("f", .int), ("w", .int)], when: "A12 evidence"),
        entry("A12.check", "未聽完就撳嘅比例", "share of taps before the question finished", when: "A12 check"),
        entry("app.none", "今個星期冇需要改嘅設定。", "No settings need changing this week.", when: "no app rule fires"),
        entry("set.value", "{setting}: {from} → {to}", "{setting}: {from} → {to}",
              [("setting", .words), ("from", .words), ("to", .words)], when: "setting line"),
        entry("set.range", "{setting}: {from} → {to}", "{setting}: {from} → {to}",
              [("setting", .words), ("from", .range), ("to", .range)], when: "range setting line"),
        entry("set.weight", "{setting}: {from} → {to}", "{setting}: {from} → {to}",
              [("setting", .words), ("from", .int), ("to", .int)], when: "weight setting line"),
        entry("set.to", "{setting} → {to}", "{setting} → {to}", [("setting", .words), ("to", .words)],
              when: "setting line, current value not recorded"),
        entry("set.assignment", "assignment {kind} {stars}: {from} → {to}", "assignment {kind} {stars}: {from} → {to}",
              [("kind", .verbatim), ("stars", .words), ("from", .words), ("to", .words)], when: "star assignment line"),
        entry("set.generated", "QuestionGeneration.generatedKinds: add {kinds} (Codex task)",
              "QuestionGeneration.generatedKinds: add {kinds} (Codex task)", [("kinds", .verbatim)], when: "A5 line")
    ]

    /// §7.3.
    static let questions: [WeeklyTemplate] = [
        entry("Q1",
              "今個星期有玩嘅日子平均每日睇片大約 {h}（每次揀片之後平均播 {m} 分鐘）。呢個係咪你哋預期？有冇時候電視自己播緊、冇人睇住？",
              "On days with play, videos ran about {h} a day (about {m} min per pick). Is that what you expect? Is the TV sometimes left playing with nobody watching?",
              [("h", .minutes), ("m", .int)], when: "video ≥ 90 minutes per day played"),
        entry("Q1.noPicks", "今個星期有玩嘅日子平均每日睇片大約 {h}。呢個係咪你哋預期？有冇時候電視自己播緊、冇人睇住？",
              "On days with play, videos ran about {h} a day. Is that what you expect? Is the TV sometimes left playing with nobody watching?",
              [("h", .minutes)], when: "Q1 without a counted play"),
        entry("Q1.note", "App 只知道片播咗幾耐，唔知道有冇人睇住。",
              "The app only knows how long videos played, not whether anyone was watching.", when: "always with Q1"),
        entry("Q2", "今個星期有 {n} 局冇計（家長試玩／測試）。如果有啲其實係 {name} 玩嘅，可以喺「表現 › 最近玩過」撳「計返」。",
              "{n} rounds were not counted (parent testing). If some were actually {name}'s, use 表現 › 最近玩過 › 計返.",
              [("n", .int), ("name", .verbatim)], when: "excluded rounds ≥ 20 % of all rounds"),
        entry("Q2.one", "今個星期有 {n} 局冇計（家長試玩／測試）。如果有啲其實係 {name} 玩嘅，可以喺「表現 › 最近玩過」撳「計返」。",
              "{n} round was not counted (parent testing). If it was actually {name}'s, use 表現 › 最近玩過 › 計返.",
              [("n", .int), ("name", .verbatim)], when: "Q2 with one round")
    ]

    public static let all: [WeeklyTemplate] = Array([fragments, pageOne, wins, comments, pages, family, app, questions].joined())

    public static let byID: [String: WeeklyTemplate] = Dictionary(all.map { ($0.id, $0) },
                                                                    uniquingKeysWith: { first, _ in first })

    /// Renders template `id`. Unknown ids, missing or extra slots and slots of the wrong type are
    /// reported in `problems` (the checks require none).
    public static func render(_ id: String, _ values: [String: WeeklySlotValue] = [:]) -> WeeklySentence {
        guard let template = byID[id] else {
            return WeeklySentence(id: id, problems: ["unknown template \(id)"])
        }
        var zhParts: [String: String] = [:]
        var enParts: [String: String] = [:]
        var traceable: [WeeklyTraceable] = []
        var verbatim: [String] = []
        var problems: [String] = []
        for slot in template.slots {
            guard let value = values[slot.name] else {
                problems.append("\(id): no value for slot \(slot.name)")
                continue
            }
            if value.type != slot.type {
                problems.append("\(id): slot \(slot.name) is \(slot.type.rawValue), got \(value.type.rawValue)")
            }
            let piece = WeeklyFormat.piece(value)
            zhParts[slot.name] = piece.zh
            enParts[slot.name] = piece.en
            traceable += piece.traceable
            verbatim += piece.verbatim
            problems += piece.problems
        }
        let declared = Set(template.slots.map(\.name))
        for name in values.keys.sorted() where !declared.contains(name) {
            problems.append("\(id): extra value \(name)")
        }
        var missing: [String] = []
        let zh = WeeklyFormat.fill(template.zh, zhParts, missing: &missing)
        let en = WeeklyFormat.fill(template.en, enParts, missing: &missing)
        for name in missing {
            problems.append("\(id): placeholder without a value \(name)")
        }
        return WeeklySentence(id: id, zh: zh, en: en, traceable: traceable, verbatim: verbatim, problems: problems)
    }
}

/// Words the templates put in slots: approved tag names, labels of settings, F8 objects, constants.
public enum WeeklyTextCatalog {
    /// perf-review-design §8.5 approved tag strings (the tags `answer_attempt.tags` can carry).
    public static let tagNames: [String: WeeklyWords] = [
        "same_shape": WeeklyWords("同款唔同色", "same shape, different colour"),
        "same_color": WeeklyWords("同色唔同款", "same colour, different shape"),
        "under_by_1": WeeklyWords("少數咗一架", "counted one too few"),
        "over_by_1": WeeklyWords("多數咗一架", "counted one too many"),
        "longest_first": WeeklyWords("由長排到短", "ordered long to short"),
        "screen_order": WeeklyWords("跟位置撳", "tapped in screen order"),
        "warm_color": WeeklyWords("揀咗顏色似嘅", "picked by colour"),
        "smaller": WeeklyWords("揀咗細嘅", "picked the smaller one"),
        "fewer": WeeklyWords("揀咗少啲嗰邊", "picked the side with fewer"),
        "vehicle_attraction": WeeklyWords("撳咗有車嘅位", "tapped a bay with a vehicle")
    ]

    public static func tagName(_ tag: String) -> WeeklyWords? {
        tagNames[tag]
    }

    /// `LineMatchTolerance` labels plus the two 「跟…」 choices of the shape and tap-count settings.
    public static func tolerance(_ value: String) -> WeeklyWords? {
        if let known = LineMatchTolerance(rawValue: value) {
            return WeeklyWords(known.labelTraditionalChinese, known.labelEnglish)
        }
        switch value {
        case "follow_lineMatch": return WeeklyWords("跟連一連", "Same as Line Match")
        case "follow_shape_trace": return WeeklyWords("跟畫形狀", "Same as Shapes")
        default: return nil
        }
    }

    /// 描數字提示 levels (`TapCountGuidanceLevel`).
    public static func guidance(_ value: String) -> WeeklyWords? {
        switch value {
        case "more": return WeeklyWords("多啲", "More")
        case "standard": return WeeklyWords("標準", "Standard")
        case "less": return WeeklyWords("少啲", "Less")
        default: return nil
        }
    }

    /// 描數字 trace guide (`TapCountTraceScaffold`).
    public static func scaffold(_ value: String) -> WeeklyWords? {
        switch value {
        case "dots": return WeeklyWords("虛線路", "dotted lane")
        case "outline": return WeeklyWords("淡框 + 箭嘴", "outline + arrows")
        default: return nil
        }
    }

    /// `gen` values.
    public static func generation(_ value: String) -> WeeklyWords? {
        switch value {
        case "fixed_v0": return WeeklyWords("同一題", "Same question")
        case "variants_v1": return WeeklyWords("多款題目", "Varied questions")
        default: return nil
        }
    }

    /// `LineMatchCategory` titles.
    public static func category(_ value: String) -> WeeklyWords? {
        guard let known = LineMatchCategory(rawValue: value) else { return nil }
        return WeeklyWords(known.titleTraditionalChinese, known.titleEnglish)
    }

    /// Value labels of a setting, by `labels` key.
    static func label(_ labels: String, _ value: String) -> WeeklyWords? {
        switch labels {
        case "tolerance": return tolerance(value)
        case "guidance": return guidance(value)
        case "scaffold": return scaffold(value)
        case "generation": return generation(value)
        default: return nil
        }
    }

    /// any.settings names of `config_change.what` values: (name, value labels key).
    public static func configName(_ what: String) -> (name: WeeklyWords, labels: String)? {
        switch what {
        case "lineMatch_tolerance": return (WeeklyWords("連一連寬容度", "Line Match tolerance"), "tolerance")
        case "lineMatch_category_weight", "lineMatch_category_mix":
            return (WeeklyWords("連一連類別比例", "Line Match category mix"), "")
        case "shapeTrace_tolerance": return (WeeklyWords("畫形狀寬容度", "Shapes tolerance"), "tolerance")
        case "shapeTrace_shape_weight", "shapeTrace_shape_mix": return (WeeklyWords("畫形狀比例", "Shape mix"), "")
        case "shapeTrace_direction_hint": return (WeeklyWords("方向提示", "Direction hint"), "")
        case "shapeTrace_corner_stop": return (WeeklyWords("轉角停一停", "Corner stop"), "")
        case "shapeTrace_slant_lines": return (WeeklyWords("畫直線加斜線", "Slant line in Lines"), "")
        case "shapeTrace_dot_style": return (WeeklyWords("虛線款式", "Dot style"), "")
        case "tapCount_range": return (WeeklyWords("數字範圍", "Numbers range"), "")
        case "tapCount_count_voice": return (WeeklyWords("點車讀數", "Count aloud"), "")
        case "tapCount_english": return (WeeklyWords("加英文", "English word"), "")
        case "tapCount_badge_style": return (WeeklyWords("數字牌", "Badges"), "")
        case "tapCount_trace_scaffold": return (WeeklyWords("描數字", "Trace guide"), "")
        case "tapCount_guidance": return (WeeklyWords("描數字提示", "Tracing help"), "guidance")
        case "tapCount_stroke_order": return (WeeklyWords("筆順動畫", "Stroke order"), "")
        case "tapCount_tolerance": return (WeeklyWords("一架一架數寬容度", "Tap & Count tolerance"), "tolerance")
        default: return nil
        }
    }

    /// any.settings names of deal (or result) signature fields; `tolerance` depends on the game's family.
    public static func fieldName(_ field: String, kind: String) -> (name: WeeklyWords, labels: String)? {
        switch field {
        case "tolerance":
            guard let known = ActivityKind(rawValue: kind) else { return nil }
            if known.isLineMatchFamily { return (WeeklyWords("連一連寬容度", "Line Match tolerance"), "tolerance") }
            if known.isShapeTraceFamily { return (WeeklyWords("畫形狀寬容度", "Shapes tolerance"), "tolerance") }
            if known.isTapCountFamily { return (WeeklyWords("一架一架數寬容度", "Tap & Count tolerance"), "tolerance") }
            return nil
        case "gen": return (WeeklyWords("題目來源", "Question source"), "generation")
        case "level", "shape_trace_level": return (WeeklyWords("難度", "Level"), "")
        case "trace_scaffold": return (WeeklyWords("描數字", "Trace guide"), "scaffold")
        case "range": return (WeeklyWords("數字範圍", "Numbers range"), "")
        case "count_voice": return (WeeklyWords("點車讀數", "Count aloud"), "")
        case "english": return (WeeklyWords("加英文", "English word"), "")
        case "direction_coaching": return (WeeklyWords("方向提示", "Direction hint"), "")
        case "stop_coaching": return (WeeklyWords("轉角停一停", "Corner stop"), "")
        case "slant_enabled": return (WeeklyWords("畫直線加斜線", "Slant line in Lines"), "")
        case "dot_style": return (WeeklyWords("虛線款式", "Dot style"), "")
        case "category_mix": return (WeeklyWords("連一連類別比例", "Line Match category mix"), "")
        case "shape_mix": return (WeeklyWords("畫形狀比例", "Shape mix"), "")
        case "guide_level": return (WeeklyWords("描數字提示", "Tracing help"), "guidance")
        default: return nil
        }
    }

    public static let starShiftName = WeeklyWords("★★★ 題目比例", "share of ★★★ rounds")

    /// F8 {winObject}: what the child looked at in the game of the win.
    public static func winObject(kind: String) -> WeeklyWords {
        guard let known = ActivityKind(rawValue: kind) else { return winObjectQuestions }
        switch known {
        case .twoPictureChoose, .findTheSame, .countVehicles, .capacityCompare, .tapCountAll, .tapCountPick,
             .tapCountAllEnglish, .tapCountPickEnglish:
            return WeeklyWords("啲車", "the vehicles")
        case .sequenceShortToLong: return WeeklyWords("個車隊", "the convoy")
        case .halfMatch: return WeeklyWords("兩邊", "both halves")
        case .shapeCousin, .traceShapesDotted, .traceShapesArrows, .traceShapesFree: return WeeklyWords("啲形狀", "the shapes")
        case .moreFewer: return WeeklyWords("兩個停車場", "both car parks")
        case .shadowMatch: return WeeklyWords("影子", "the shadow")
        case .emptyBay: return WeeklyWords("啲車位", "the parking bays")
        case .lineMatch: return WeeklyWords("啲圖同字", "the pictures and words")
        case .lineMatchGuidedStraight, .lineMatchGuidedBridge: return WeeklyWords("條路", "the road")
        case .traceLines: return WeeklyWords("條線", "the lines")
        case .tapCountTrace, .tapCountTraceEnglish: return WeeklyWords("個數字", "the numbers")
        case .tapLetterAll, .tapLetterWrite: return WeeklyWords("啲字母", "the letters")
        }
    }

    public static let winObjectNumerals = WeeklyWords("啲數字", "the numbers")
    public static let winObjectQuestions = WeeklyWords("題目", "each question")

    /// Digits that are copy or rule constants rather than metrics: path → the values allowed there.
    public static let constants: [String: [String]] = [
        "copy.page.questions": ["6"], "copy.A10.example": ["3"], "copy.A9.age": ["4"], "copy.A11.choices": ["4"],
        "copy.range.start": ["1"], "rule.memorised_rate": ["90"], "rule.minimum_rounds": ["5"], "rule.A3.keep": ["80"],
        "rule.A4b.keep": ["70"], "rule.A9.keep": ["80"], "rule.A7.step": ["10"], "rule.A2.range": ["5"],
        "rule.A3.range": ["7", "10"]
    ]

    /// Every catalogue word, for the word and Traditional-only checks.
    public static var allWords: [WeeklyWords] {
        var words = Array(tagNames.values)
        for value in ["narrow", "standard", "wide", "follow_lineMatch", "follow_shape_trace"] {
            if let label = tolerance(value) { words.append(label) }
        }
        for value in ["more", "standard", "less"] {
            if let label = guidance(value) { words.append(label) }
        }
        for value in ["dots", "outline"] {
            if let label = scaffold(value) { words.append(label) }
        }
        for value in ["fixed_v0", "variants_v1"] {
            if let label = generation(value) { words.append(label) }
        }
        for category in LineMatchCategory.allCases {
            if let label = self.category(category.rawValue) { words.append(label) }
        }
        let whats = ["lineMatch_tolerance", "lineMatch_category_weight", "shapeTrace_tolerance", "shapeTrace_shape_weight",
                     "shapeTrace_direction_hint", "shapeTrace_corner_stop", "shapeTrace_slant_lines", "shapeTrace_dot_style",
                     "tapCount_range", "tapCount_count_voice", "tapCount_english", "tapCount_badge_style",
                     "tapCount_trace_scaffold", "tapCount_guidance", "tapCount_stroke_order", "tapCount_tolerance"]
        for what in whats {
            if let name = configName(what) { words.append(name.name) }
        }
        for field in WeeklySignature.dealFields + WeeklySignature.resultFields {
            if let name = fieldName(field, kind: ActivityKind.lineMatch.rawValue) { words.append(name.name) }
        }
        words.append(starShiftName)
        for kind in ActivityKind.allCases {
            words.append(winObject(kind: kind.rawValue))
            words.append(WeeklyWords(kind.parentCardTitle, kind.parentCardEnglish))
        }
        words.append(winObjectNumerals)
        words.append(winObjectQuestions)
        for area in WeeklyArea.allCases {
            words.append(WeeklyWords(area.zh, area.en))
        }
        return words
    }
}
