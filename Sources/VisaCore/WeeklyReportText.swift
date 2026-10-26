import Foundation

// Weekly report W3 (weekly-report design §12 W3: §6 templates, highlights, §7 recommendations and
// questions; D6 B, D7, D8 B): the report's text, built from the W1 metrics and the W2 analysis with the
// deterministic templates of `WeeklyTemplates`. First matching template wins; every printed number is
// traced. Pure and deterministic: the same events, rollup, window, name and titles always give the same
// text. ADR 0023 records the choices made where the design left room.

/// One game's sentences (§6.6). `comment` holds the long forms; `short` the page-4 forms, where the row
/// already shows k/n.
public struct WeeklyGameText: Sendable, Equatable {
    public var kind: String
    public var type: WeeklyRoundType
    public var placement: WeeklyPlacement
    /// 「14 局入面 6 局一次答啱」 (n ≥ 1).
    public var fact: WeeklySentence?
    /// Main sentence, then at most one extra.
    public var comment: [WeeklySentence]
    public var short: [WeeklySentence]
}

/// Page-4 lines (§3, §5.3).
public struct WeeklyRankingText: Sendable, Equatable {
    /// 「今個星期玩得太少，未排名。」 or 「今個星期每個遊戲都仲學緊，慢慢嚟。」.
    public var status: WeeklySentence?
    /// 「答題 3 個、練習 2 個」.
    public var topSplit: WeeklySentence?
    public var stillLearningSplit: WeeklySentence?
    /// 「其他都做得好：…」 / 「其他仲學緊：…」.
    public var alsoWell: WeeklySentence?
    public var alsoLearning: WeeklySentence?
}

/// §7.1 屋企人可以做.
public struct WeeklyFamilyItem: Sendable, Equatable {
    public var id: String
    public var text: WeeklySentence
    /// 因為 … (numbers from the report).
    public var because: WeeklySentence
    /// The games that fed the item (each feeds at most one family item).
    public var kinds: [String]
}

/// §7.2 App 改動 (Carter decides; nothing is applied).
public struct WeeklyAppItem: Sendable, Equatable {
    public var id: String
    public var text: WeeklySentence
    public var because: WeeklySentence
    /// What to check next week.
    public var check: WeeklySentence
    /// Setting lines, e.g. "TapCountSettings.guidance: standard → more" (the same text in both languages).
    public var settings: [WeeklySentence]
    /// The value read from this week's records and the suggestion, as recorded values.
    public var current: String?
    public var suggested: String?
    /// The games that fed the item (each feeds at most one app item).
    public var kinds: [String]
}

/// §7.3 想問你哋.
public struct WeeklyQuestion: Sendable, Equatable {
    public var id: String
    public var question: WeeklySentence
    public var note: WeeklySentence?
}

/// W3 output: every sentence of the report, plus the W2 analysis it was built from.
public struct WeeklyReportText: Sendable, Equatable {
    public static let textVersion = 1
    /// D7: the child's name in the report text (W5b adds the parent-set nickname).
    public static let defaultChildName = "Cedric"
    /// Page 6 holds the questions (§3); the page-1 video pointer names it.
    public static let questionsPage = 6
    /// §7: at most 3 family items (F8 is an extra closing line) and 4 app items.
    public static let familyMaximum = 3
    public static let appMaximum = 4

    public var analysis: WeeklyAnalysis
    public var childName: String
    /// 「今個星期未有紀錄。」 when nothing countable happened (§3).
    public var empty: WeeklySentence?
    /// §6.4: hl.volume, hl.rates, hl.games, hl.time (each optional).
    public var highlights: [WeeklySentence]
    /// §6.5: every win in W2 priority order; the first 3 are shown.
    public var winCandidates: [WeeklySentence]
    /// W2 game order.
    public var games: [WeeklyGameText]
    public var ranking: WeeklyRankingText
    /// D8 B: the most-watched videos.
    public var videos: WeeklySentence?
    /// Page 5: 「今個星期冇改設定」 when nothing changed.
    public var changes: [WeeklySentence]
    public var family: [WeeklyFamilyItem]
    /// F8, the closing line when there is a win.
    public var praise: WeeklySentence?
    public var familyNone: WeeklySentence?
    public var app: [WeeklyAppItem]
    public var appNone: WeeklySentence?
    public var questions: [WeeklyQuestion]
    /// The `facts` block of the JSON (where `facts.` paths point).
    public var facts: PerfValue

    public var wins: [WeeklySentence] { Array(winCandidates.prefix(WeeklyWin.maximum)) }

    /// Every sentence (and setting line) in the model, for the checks.
    public var allSentences: [WeeklySentence] {
        var out: [WeeklySentence] = []
        if let empty { out.append(empty) }
        out += highlights
        out += winCandidates
        for game in games {
            if let fact = game.fact { out.append(fact) }
            out += game.comment
            out += game.short
        }
        for line in [ranking.status, ranking.topSplit, ranking.stillLearningSplit, ranking.alsoWell, ranking.alsoLearning] {
            if let line { out.append(line) }
        }
        if let videos { out.append(videos) }
        out += changes
        for item in family {
            out.append(item.text)
            out.append(item.because)
        }
        if let praise { out.append(praise) }
        if let familyNone { out.append(familyNone) }
        for item in app {
            out.append(item.text)
            out.append(item.because)
            out.append(item.check)
            out += item.settings
        }
        if let appNone { out.append(appNone) }
        for question in questions {
            out.append(question.question)
            if let note = question.note { out.append(note) }
        }
        return out
    }

    /// Rendering problems of every sentence; the checks require none.
    public var problems: [String] { allSentences.flatMap(\.problems) }
}

public enum WeeklyReportTextBuilder {
    /// `childName` is printed where the design names the child (D7, default Cedric). `videoTitles` maps
    /// video ids to the parent's labels (D8 B; titles are shown as recorded, ids when unknown).
    public static func build(events: [PerfEvent], rollup: PerfRollup, window: WeeklyWindow,
                             childName: String = WeeklyReportText.defaultChildName,
                             videoTitles: [String: String] = [:]) -> WeeklyReportText {
        let ordered = PerfCodec.ordered(events)
        let excluded = PerfFilter.excludedSessions(in: ordered)
        let index = WeeklyMetricsBuilder.Index(ordered: ordered, excluded: excluded, rollup: rollup)
        let model = WeeklyMetricsBuilder.build(ordered: ordered, index: index, window: window)
        let analysis = WeeklyAnalysisBuilder.analyse(model: model, ordered: ordered, index: index, rollup: rollup)
        let facts = WeeklyTextFacts(index: index, model: model, rollup: rollup, videoTitles: videoTitles)
        let name = childName.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = WeeklyTextContext(analysis: analysis, facts: facts,
                                        childName: name.isEmpty ? WeeklyReportText.defaultChildName : name)
        return context.text()
    }
}

/// Renders template `id` (see `WeeklyTemplates.render`).
private func say(_ id: String, _ values: [String: WeeklySlotValue] = [:]) -> WeeklySentence {
    WeeklyTemplates.render(id, values)
}

/// The games already used by an item of one recommendation section.
private struct WeeklyClaims {
    private(set) var keys: Set<WeeklyRowKey> = []

    func isFree(_ game: WeeklyGame) -> Bool {
        !keys.contains(WeeklyRowKey(game))
    }

    mutating func claim(_ games: [WeeklyGame]) {
        for game in games { keys.insert(WeeklyRowKey(game)) }
    }
}

struct WeeklyTextContext {
    static let quizAreas: [WeeklyArea] = [.numbers, .matching, .comparing, .letters]
    static let minimumRounds = WeeklyRanking.minimumRounds

    let analysis: WeeklyAnalysis
    let facts: WeeklyTextFacts
    let childName: String
    let model: WeeklyModel
    let rows: [WeeklyRowKey: WeeklyKindMetrics]
    let gamesByKey: [WeeklyRowKey: WeeklyGame]
    let daysPlayed: Int
    let gameMs: Int
    let videoMs: Int
    let visaMinutes: Int
    let plays: Int
    let excludedTotal: Int
    let quizFastWrong: Int
    let quizWrongAttempts: Int
    /// Q1: video ≥ 90 minutes per day played.
    let asksAboutVideo: Bool

    init(analysis: WeeklyAnalysis, facts: WeeklyTextFacts, childName: String) {
        self.analysis = analysis
        self.facts = facts
        self.childName = childName
        let model = analysis.model
        self.model = model
        var rows: [WeeklyRowKey: WeeklyKindMetrics] = [:]
        for row in model.current.kinds { rows[WeeklyRowKey(kind: row.kind, type: row.type)] = row }
        self.rows = rows
        var games: [WeeklyRowKey: WeeklyGame] = [:]
        for game in analysis.games { games[WeeklyRowKey(game)] = game }
        self.gamesByKey = games
        let current = model.current
        daysPlayed = current.daysPlayed
        gameMs = current.quizMs + current.practiceMs
        videoMs = current.videoMs
        visaMinutes = current.visaMinutes
        plays = current.plays
        excludedTotal = current.excludedTotal
        var fast = 0, wrong = 0
        for row in current.kinds where row.type == .quiz {
            fast += row.fastWrong
            wrong += row.wrongAttempts
        }
        quizFastWrong = fast
        quizWrongAttempts = wrong
        asksAboutVideo = current.daysPlayed > 0 && current.videoMs >= 90 * 60_000 * current.daysPlayed
    }

    // MARK: The model

    func text() -> WeeklyReportText {
        let countable = daysPlayed > 0
        var games: [WeeklyGameText] = []
        for game in analysis.games {
            let forms = comments(game)
            games.append(WeeklyGameText(kind: game.kind, type: game.type, placement: game.placement, fact: fact(game),
                                        comment: forms.comment, short: forms.short))
        }
        var candidates: [WeeklySentence] = []
        for (offset, win) in analysis.winCandidates.enumerated() {
            candidates.append(winSentence(offset, win))
        }
        let familyPart: (items: [WeeklyFamilyItem], praise: WeeklySentence?, none: WeeklySentence?) =
            countable ? familyItems() : (items: [], praise: nil, none: nil)
        let appPart: (items: [WeeklyAppItem], none: WeeklySentence?) =
            countable ? appItems() : (items: [], none: nil)
        return WeeklyReportText(
            analysis: analysis, childName: childName, empty: countable ? nil : say("wr.empty"),
            highlights: highlights(), winCandidates: candidates, games: games, ranking: rankingText(),
            videos: videosSentence(), changes: changesLines(), family: familyPart.items, praise: familyPart.praise,
            familyNone: familyPart.none, app: appPart.items, appNone: appPart.none, questions: questions(),
            facts: factsJSON()
        )
    }

    // MARK: Paths and pieces

    func gamePath(_ game: WeeklyGame) -> String {
        "analysis.games[" + WeeklyRowKey(game).text + "]"
    }

    func metricsPath(_ game: WeeklyGame) -> String {
        "metrics.current.kinds[" + WeeklyRowKey(game).text + "]"
    }

    func factsPath(_ game: WeeklyGame) -> String {
        "facts.games[" + WeeklyRowKey(game).text + "]"
    }

    func row(_ game: WeeklyGame) -> WeeklyKindMetrics? {
        rows[WeeklyRowKey(game)]
    }

    func rowFacts(_ game: WeeklyGame) -> WeeklyRowFacts {
        facts.rows[WeeklyRowKey(game)] ?? WeeklyRowFacts()
    }

    func game(_ kind: String, _ type: WeeklyRoundType) -> WeeklyGame? {
        gamesByKey[WeeklyRowKey(kind: kind, type: type)]
    }

    /// The still-learning list, 答題 first (W2 order).
    func stillLearning(_ type: WeeklyRoundType) -> [WeeklyGame] {
        let kinds = type == .quiz ? analysis.ranking.stillLearning.quiz : analysis.ranking.stillLearning.practice
        var out: [WeeklyGame] = []
        for kind in kinds {
            if let found = game(kind, type) { out.append(found) }
        }
        return out
    }

    /// "road", "shape" or "line": how off-path is counted for a practice kind.
    func offPathUnit(_ kind: String) -> String? {
        switch WeeklyPracticeFamily.of(kind: kind) {
        case .roads?: return "road"
        case .lines?: return "line"
        case .shapes?: return "shape"
        default: return nil
        }
    }

    /// wrong_start > 0 in ≥ 40 % of the rounds that wrote it.
    func wrongStartHigh(_ facts: WeeklyRowFacts) -> Bool {
        facts.wrongStartKnown >= 1 && 10 * facts.wrongStart >= 4 * facts.wrongStartKnown
    }

    /// bot.fast: ≥ 3 wrong attempts, ≥ 30 % of them before the question finished.
    func fastRule(_ row: WeeklyKindMetrics) -> Bool {
        row.wrongAttempts >= 3 && 10 * row.fastWrong >= 3 * row.wrongAttempts
    }

    func fact(_ game: WeeklyGame) -> WeeklySentence? {
        guard game.n >= 1 else { return nil }
        let path = gamePath(game)
        let n = WeeklySlotValue.int(game.n, path: path + ".n")
        let k = WeeklySlotValue.int(game.k, path: path + ".k")
        switch game.type {
        case .quiz:
            return game.k == game.n ? say("frag.quiz.all", ["n": n]) : say("frag.quiz", ["n": n, "k": k])
        case .practice:
            return game.k == game.n ? say("frag.practice.all", ["n": n]) : say("frag.practice", ["n": n, "k": k])
        }
    }

    func numeralList(_ values: [Int], path: String, zhLast: String?) -> WeeklySentence {
        var parts: [WeeklySentence] = []
        for (offset, value) in values.enumerated() {
            let text = String(value)
            parts.append(WeeklySentence(zh: text, en: text, traceable: [
                WeeklyTraceable(path: path + "[" + String(offset) + "]", value: text)
            ]))
        }
        return WeeklySentence.listed(parts, zh: "、", zhLast: zhLast)
    }

    /// 「a」、「b」 / "a" and "b".
    func gameList(_ kinds: [String]) -> WeeklySentence {
        var parts: [WeeklySentence] = []
        for kind in kinds {
            let name = WeeklyFormat.piece(.game(kind))
            parts.append(WeeklySentence(zh: "「" + name.zh + "」", en: "\"" + name.en + "\"", verbatim: name.verbatim))
        }
        return WeeklySentence.listed(parts)
    }

    func evidenceList(_ parts: [WeeklySentence]) -> WeeklySentence {
        say("ev.list", ["items": .text(WeeklySentence.joined(parts, zh: "；", en: "; "))])
    }

    func evidence(_ game: WeeklyGame, _ fact: WeeklySentence) -> WeeklySentence {
        say("ev.game", ["game": .game(game.kind), "fact": .text(fact)])
    }

    func offPathValue(_ game: WeeklyGame, _ facts: WeeklyRowFacts) -> WeeklySlotValue {
        .decimal(tenths: WeeklyFormat.tenths(facts.offPath, facts.offPathUnits),
                 path: factsPath(game) + ".off_path/off_path_units#1dp")
    }

    func helpsValue(_ game: WeeklyGame, _ row: WeeklyKindMetrics) -> WeeklySlotValue {
        .decimal(tenths: WeeklyFormat.tenths(row.guideHelpsTotal, row.guideHelpsRounds),
                 path: metricsPath(game) + ".guide_helps_mean#1dp")
    }

    func machine(_ text: String) -> WeeklySlotValue {
        .words(zh: text, en: text)
    }

    func settingLine(_ setting: String, _ from: String, _ to: String) -> WeeklySentence {
        say("set.value", ["setting": machine(setting), "from": machine(from), "to": machine(to)])
    }

    func settingLine(_ setting: String, to: String) -> WeeklySentence {
        say("set.to", ["setting": machine(setting), "to": machine(to)])
    }

    // MARK: §6.4 highlights

    func trend(_ comparison: WeeklyRateComparison, path: String) -> WeeklySentence {
        guard let change = comparison.change else { return .empty }
        let id: String
        switch change {
        case .same: id = "trend.same"
        case .up: id = "trend.up"
        case .down: id = "trend.down"
        case .unsure: id = "trend.unsure"
        }
        return say(id, ["p0": .percent(WeeklyFormat.percent(comparison.k0, of: comparison.n0), path: path)])
    }

    func firstGame(_ lists: WeeklyKindLists) -> WeeklyGame? {
        if let kind = lists.quiz.first { return game(kind, .quiz) }
        if let kind = lists.practice.first { return game(kind, .practice) }
        return nil
    }

    func highlights() -> [WeeklySentence] {
        guard daysPlayed > 0 else { return [] }
        var out: [WeeklySentence] = []
        let current = model.current
        let totals = current.totals

        var noPlay: [Int] = []
        for day in facts.coveredDays where !current.days[day].played { noPlay.append(day) }
        var noPlayText = WeeklySentence.empty
        if !noPlay.isEmpty {
            let days = WeeklySentence(zh: noPlay.map { WeeklyFormat.dayNamesZH[$0] }.joined(separator: "、"),
                                      en: noPlay.map { WeeklyFormat.dayNamesEN[$0] }.joined(separator: ", "))
            noPlayText = say("noPlay", ["days": .text(days)])
        }
        var vsLast = WeeklySentence.empty
        if !analysis.comparison.baseline {
            let difference = analysis.comparison.rounds.current - analysis.comparison.rounds.previous
            if difference > 0 {
                vsLast = say("vs.more", ["d": .int(difference, path: "facts.rounds_change")])
            } else if difference < 0 {
                vsLast = say("vs.fewer", ["d": .int(-difference, path: "facts.rounds_change")])
            } else {
                vsLast = say("vs.same")
            }
        }
        out.append(say(daysPlayed == 1 ? "hl.volume.oneDay" : "hl.volume", [
            "days": .int(daysPlayed, path: "metrics.current.totals.days_played"), "noPlayDays": .text(noPlayText),
            "rounds": .int(totals.rounds, path: "metrics.current.totals.rounds"),
            "quiz": .int(totals.quizRounds, path: "metrics.current.totals.quiz_rounds"),
            "practice": .int(totals.practiceRounds, path: "metrics.current.totals.practice_rounds"),
            "vsLast": .text(vsLast)
        ]))

        let quiz = analysis.comparison.quiz, practice = analysis.comparison.practice
        let hasQuiz = quiz.n1 >= Self.minimumRounds, hasPractice = practice.n1 >= Self.minimumRounds
        let p = WeeklySlotValue.percent(WeeklyFormat.percent(quiz.k1, of: quiz.n1), path: "metrics.current.totals.quiz_rate#pct")
        let s = WeeklySlotValue.percent(WeeklyFormat.percent(practice.k1, of: practice.n1),
                                        path: "metrics.current.totals.practice_rate#pct")
        let pTrend = trend(quiz, path: "metrics.previous.totals.quiz_rate#pct")
        let sTrend = trend(practice, path: "metrics.previous.totals.practice_rate#pct")
        if hasQuiz && hasPractice {
            out.append(say("hl.rates", ["p": p, "pTrend": .text(pTrend), "s": s, "sTrend": .text(sTrend)]))
        } else if hasQuiz {
            out.append(say("hl.rates.quiz", ["p": p, "pTrend": .text(pTrend)]))
        } else if hasPractice {
            out.append(say("hl.rates.practice", ["s": s, "sTrend": .text(sTrend)]))
        }

        let ranking = analysis.ranking
        if !ranking.ranked {
            out.append(say("hl.games.none"))
        } else {
            let top = firstGame(ranking.top), bottom = firstGame(ranking.stillLearning)
            if let top, let bottom {
                let topFact = fact(top) ?? .empty, bottomFact = fact(bottom) ?? .empty
                out.append(say("hl.games", ["top1": .game(top.kind), "top1Fact": .text(topFact), "bot1": .game(bottom.kind),
                                            "bot1Fact": .text(bottomFact)]))
            } else if let top {
                let topFact = fact(top) ?? .empty
                out.append(say("hl.games.top", ["top1": .game(top.kind), "top1Fact": .text(topFact)]))
            } else if let bottom {
                let bottomFact = fact(bottom) ?? .empty
                out.append(say("hl.games.bottom", ["bot1": .game(bottom.kind), "bot1Fact": .text(bottomFact)]))
            }
        }

        if gameMs > 0 || videoMs > 0 || visaMinutes > 0 {
            var pointer = WeeklySentence.empty
            if asksAboutVideo {
                pointer = say("pointer.video", ["page": .int(WeeklyReportText.questionsPage, path: "copy.page.questions")])
            }
            out.append(say("hl.time", [
                "g": .minutes(WeeklyFormat.minutes(ms: gameMs), path: "metrics.current.totals.game_min"),
                "v": .minutes(WeeklyFormat.minutes(ms: videoMs), path: "metrics.current.totals.video_min"),
                "visa": .minutes(visaMinutes, path: "metrics.current.totals.visa_min"),
                "videoPointer": .text(pointer)
            ]))
        }
        return out
    }

    // MARK: §6.5 wins

    func winSentence(_ offset: Int, _ win: WeeklyWin) -> WeeklySentence {
        let path = "analysis.win_candidates[" + String(offset) + "]"
        switch win {
        case .newGame(kind: let kind):
            return say("win.newGame", ["game": .game(kind)])
        case .numeral(numerals: let numerals):
            return say("win.numeral", ["list": .text(numeralList(numerals, path: path + ".numerals", zhLast: nil))])
        case .streak(kind: let kind, run: let run):
            return say("win.streak", ["game": .game(kind), "n": .int(run, path: path + ".run")])
        case .rise(kind: let kind, type: _, k0: let k0, n0: let n0, k1: let k1, n1: let n1):
            return say("win.rise", ["game": .game(kind), "k0": .int(k0, path: path + ".k0"), "n0": .int(n0, path: path + ".n0"),
                                    "k1": .int(k1, path: path + ".k1"), "n1": .int(n1, path: path + ".n1")])
        case .firstSmooth(kind: let kind, day: _):
            return say("win.firstSmooth", ["game": .game(kind)])
        case .firstTry(kind: let kind, earlier: _, day: _):
            return say("win.firstTry", ["game": .game(kind)])
        case .cleanDay(day: let day, rounds: let rounds):
            return say("win.cleanDay", ["day": .day(day), "n": .int(rounds, path: path + ".rounds")])
        case .noFuelOut:
            return say("win.noFuelOut")
        }
    }

    // MARK: §6.6 game comments

    /// any.settings {setting}: the first ⚙ reason that has words.
    func settingText(_ game: WeeklyGame) -> WeeklySentence? {
        for reason in game.settings {
            switch reason {
            case .config(what: let what, value: let value, star: let star, date: let date):
                if what == "assignment" {
                    let stars = WeeklyFormat.stars(star ?? 1)
                    let id = value == "true" ? "setting.on" : "setting.off"
                    return say(id, ["game": .game(game.kind), "stars": .words(zh: stars, en: stars)])
                }
                guard let named = WeeklyTextCatalog.configName(what) else { continue }
                var old: String?
                for setting in analysis.changes.settings where setting.what == what && setting.date == date
                    && setting.new == value {
                    old = setting.old
                    break
                }
                if let value, let newLabel = WeeklyTextCatalog.label(named.labels, value) {
                    if let old, let oldLabel = WeeklyTextCatalog.label(named.labels, old) {
                        return say("setting.change", ["name": named.name.value, "old": oldLabel.value, "new": newLabel.value])
                    }
                    return say("setting.value", ["name": named.name.value, "new": newLabel.value])
                }
                return say("setting.name", ["name": named.name.value])
            case .signature(field: let field, old: let from, new: let to):
                guard let named = WeeklyTextCatalog.fieldName(field, kind: game.kind) else { continue }
                if let oldLabel = WeeklyTextCatalog.label(named.labels, from),
                   let newLabel = WeeklyTextCatalog.label(named.labels, to) {
                    return say("setting.change", ["name": named.name.value, "old": oldLabel.value, "new": newLabel.value])
                }
                return say("setting.name", ["name": named.name.value])
            case .stars:
                return say("setting.name", ["name": WeeklyTextCatalog.starShiftName.value])
            }
        }
        return nil
    }

    func anySettings(_ game: WeeklyGame) -> WeeklySentence? {
        guard !game.settings.isEmpty, let setting = settingText(game) else { return nil }
        return say("any.settings", ["setting": .text(setting)])
    }

    func comments(_ game: WeeklyGame) -> (comment: [WeeklySentence], short: [WeeklySentence]) {
        let path = gamePath(game)
        let n = WeeklySlotValue.int(game.n, path: path + ".n")
        let k = WeeklySlotValue.int(game.k, path: path + ".k")
        let settings = anySettings(game)
        let gameFacts = rowFacts(game)
        let unit = game.type == .practice ? offPathUnit(game.kind) : nil
        let hasOffPath = unit != nil && gameFacts.offPathUnits > 0

        switch game.placement {
        case .top, .alsoWell:
            let main: WeeklySentence
            let shortMain: WeeklySentence
            var extra: WeeklySentence?
            switch game.type {
            case .quiz:
                let chance = WeeklySlotValue.percent(WeeklyFormat.percent(game.chance ?? 0), path: path + ".chance#pct")
                main = game.k == game.n ? say("top.all", ["n": n]) : say("top.ft", ["n": n, "k": k, "c": chance])
                shortMain = say("top.ft.short", ["c": chance])
                extra = game.memorised ? say("top.memorised") : settings
            case .practice:
                main = game.k == game.n ? say("top.smooth.all", ["n": n]) : say("top.smooth", ["n": n, "k": k])
                if (unit == "shape" || unit == "line") && hasOffPath && gameFacts.offPath < gameFacts.offPathUnits {
                    shortMain = say(unit == "shape" ? "top.smooth.short" : "top.smooth.short.line",
                                    ["x": offPathValue(game, gameFacts)])
                } else {
                    shortMain = say("top.smooth.plain")
                }
                extra = settings
            }
            let tail = extra.map { [$0] } ?? []
            return ([main] + tail, [shortMain] + tail)
        case .stillLearning, .alsoLearning:
            switch game.type {
            case .quiz:
                let main = say("bot.ft", ["n": n, "k": k])
                var tag: WeeklySentence?
                var fast: WeeklySentence?
                if let gameRow = self.row(game) {
                    let metrics = metricsPath(game)
                    if let topTag = gameRow.topWrongTag, WeeklyTextCatalog.tagName(topTag) != nil {
                        tag = say("bot.tag", ["tag": .tag(topTag),
                                              "m": .int(gameRow.topWrongTagCount, path: metrics + ".top_wrong_tag_count"),
                                              "w": .int(gameRow.wrongAttempts, path: metrics + ".wrong_attempts")])
                    }
                    if fastRule(gameRow) {
                        fast = say("bot.fast", ["f": .int(gameRow.fastWrong, path: metrics + ".fast_wrong"),
                                                "w": .int(gameRow.wrongAttempts, path: metrics + ".wrong_attempts")])
                    }
                }
                var fuel: WeeklySentence?
                if game.zeroed >= 2 { fuel = say("bot.fuel", ["z": .int(game.zeroed, path: path + ".zeroed")]) }
                var stars: WeeklySentence?
                if let rule = game.starRule {
                    stars = say("bot.stars", ["k3": .int(rule.k3, path: path + ".star_rule.k3"),
                                              "n3": .int(rule.n3, path: path + ".star_rule.n3"),
                                              "k12": .int(rule.k12, path: path + ".star_rule.k12"),
                                              "n12": .int(rule.n12, path: path + ".star_rule.n12")])
                }
                let extra = tag ?? fuel ?? stars ?? fast ?? settings
                let blocked = tag != nil || fuel != nil || settings != nil
                let tail = extra.map { [$0] } ?? []
                var short: [WeeklySentence] = []
                if !blocked { short.append(say("bot.ft.short")) }
                return ([main] + tail, short + tail)
            case .practice:
                let main: WeeklySentence
                if WeeklyPracticeFamily.of(kind: game.kind) == .tapTrace, let gameRow = self.row(game),
                   gameRow.guideHelpsRounds > 0 {
                    main = say("bot.helps", ["h": helpsValue(game, gameRow)])
                } else if let unit, hasOffPath, gameFacts.offPath >= gameFacts.offPathUnits {
                    let id = unit == "road" ? "bot.offPath" : unit == "shape" ? "bot.offPath.shape" : "bot.offPath.line"
                    main = say(id, ["x": offPathValue(game, gameFacts)])
                } else {
                    main = say("bot.ft.short")
                }
                var extra: WeeklySentence?
                if wrongStartHigh(gameFacts) {
                    let gameFactsPath = factsPath(game)
                    extra = say("bot.wrongStart", [
                        "w": .int(gameFacts.wrongStart, path: gameFactsPath + ".wrong_start"),
                        "n": .int(gameFacts.wrongStartKnown, path: gameFactsPath + ".wrong_start_known")
                    ])
                } else {
                    extra = settings
                }
                let forms = [main] + (extra.map { [$0] } ?? [])
                return (forms, forms)
            }
        case .insufficient:
            guard let entry = analysis.ranking.insufficient.first(where: { $0.kind == game.kind && $0.type == game.type }) else {
                return ([], [])
            }
            let entryPath = "analysis.ranking.insufficient[" + WeeklyRowKey(game).text + "]"
            let main: WeeklySentence
            switch entry.reason {
            case .noMethod:
                main = say("insuff.noMethod")
            case .oneDay:
                main = say("insuff.oneDay", ["n": .int(entry.n, path: entryPath + ".n")])
            case .tooFew:
                if entry.n >= 1 {
                    var soFar = WeeklySentence.empty
                    if entry.k == entry.n {
                        soFar = say(game.type == .quiz ? "soFar.quizAll" : "soFar.practiceAll")
                    } else if game.isNew {
                        soFar = say("soFar.new")
                    }
                    main = say("insuff.n", ["n": .int(entry.n, path: entryPath + ".n"), "soFar": .text(soFar),
                                            "r": .int(entry.more, path: entryPath + ".more")])
                } else {
                    main = say("insuff.zero", ["r": .int(entry.more, path: entryPath + ".more")])
                }
            }
            return ([main], [main])
        }
    }

    // MARK: Page 4 and page 5 lines

    func rankingText() -> WeeklyRankingText {
        let ranking = analysis.ranking
        var text = WeeklyRankingText()
        guard ranking.ranked else {
            if !analysis.games.isEmpty { text.status = say("rank.notRanked") }
            return text
        }
        if ranking.top.count == 0 { text.status = say("rank.allLearning") }
        text.topSplit = split(ranking.top, name: "top")
        text.stillLearningSplit = split(ranking.stillLearning, name: "still_learning")
        text.alsoWell = otherList(ranking.alsoWell, id: "rank.alsoWell")
        text.alsoLearning = otherList(ranking.alsoLearning, id: "rank.alsoLearning")
        return text
    }

    func split(_ lists: WeeklyKindLists, name: String) -> WeeklySentence? {
        guard lists.count > 0 else { return nil }
        return say("rank.split", ["quiz": .int(lists.quiz.count, path: "analysis.ranking." + name + ".quiz#count"),
                                  "practice": .int(lists.practice.count, path: "analysis.ranking." + name + ".practice#count")])
    }

    func otherList(_ lists: WeeklyKindLists, id: String) -> WeeklySentence? {
        var items: [WeeklySentence] = []
        for (kinds, type) in [(lists.quiz, WeeklyRoundType.quiz), (lists.practice, WeeklyRoundType.practice)] {
            for kind in kinds {
                guard let found = game(kind, type) else { continue }
                let path = gamePath(found)
                items.append(say("list.item", ["game": .game(kind), "k": .int(found.k, path: path + ".k"),
                                               "n": .int(found.n, path: path + ".n")]))
            }
        }
        guard !items.isEmpty else { return nil }
        return say(id, ["items": .text(WeeklySentence.joined(items, zh: "、", en: ", "))])
    }

    func videosSentence() -> WeeklySentence? {
        guard daysPlayed > 0, !facts.videos.isEmpty else { return nil }
        var items: [WeeklySentence] = []
        for (offset, video) in facts.videos.enumerated() {
            items.append(say("video.item", ["title": .verbatim(video.title),
                                            "time": .minutes(WeeklyFormat.minutes(ms: video.watchedMs),
                                                             path: "facts.videos[" + String(offset) + "].minutes")]))
        }
        return say("videos.top", ["items": .text(WeeklySentence.joined(items, zh: "、", en: ", "))])
    }

    func changesLines() -> [WeeklySentence] {
        guard daysPlayed > 0, analysis.changes.settings.isEmpty, analysis.changes.assignments.isEmpty else { return [] }
        return [say("changes.none")]
    }

    // MARK: §7.1 family items

    func winObject() -> WeeklyWords? {
        let shown = analysis.wins
        guard let first = shown.first else { return nil }
        var chosen = first
        for win in shown {
            switch win {
            case .streak, .firstTry, .cleanDay, .noFuelOut:
                chosen = win
            case .rise(kind: _, type: let type, k0: _, n0: _, k1: _, n1: _) where type == .quiz:
                chosen = win
            default:
                continue
            }
            break
        }
        switch chosen {
        case .numeral: return WeeklyTextCatalog.winObjectNumerals
        case .cleanDay, .noFuelOut: return WeeklyTextCatalog.winObjectQuestions
        case .newGame(kind: let kind), .streak(kind: let kind, run: _), .firstSmooth(kind: let kind, day: _),
             .firstTry(kind: let kind, earlier: _, day: _):
            return WeeklyTextCatalog.winObject(kind: kind)
        case .rise(kind: let kind, type: _, k0: _, n0: _, k1: _, n1: _):
            return WeeklyTextCatalog.winObject(kind: kind)
        }
    }

    func familyItems() -> (items: [WeeklyFamilyItem], praise: WeeklySentence?, none: WeeklySentence?) {
        var items: [WeeklyFamilyItem] = []
        var claims = WeeklyClaims()
        let full = WeeklyReportText.familyMaximum

        // F6: fuel-outs ≥ 2 in a game (the most fuel-outs, then game order).
        var fuel: WeeklyGame?
        for game in analysis.games where game.type == .quiz && game.zeroed >= 2 && claims.isFree(game) {
            if let best = fuel, best.zeroed >= game.zeroed { continue }
            fuel = game
        }
        if let game = fuel, items.count < full {
            let because = evidenceList([say("ev.fuel", ["game": .game(game.kind),
                                                        "z": .int(game.zeroed, path: gamePath(game) + ".zeroed")])])
            items.append(WeeklyFamilyItem(id: "F6", text: say("F6", ["game": .game(game.kind)]), because: because,
                                          kinds: [game.kind]))
            claims.claim([game])
        }

        // F1: a 數字・數量 quiz game is still learning.
        let numbers = stillLearning(.quiz).filter { $0.area == .numbers && claims.isFree($0) }
        if !numbers.isEmpty, items.count < full {
            var parts: [WeeklySentence] = []
            for game in numbers { parts.append(evidence(game, fact(game) ?? .empty)) }
            items.append(WeeklyFamilyItem(id: "F1", text: say("F1"), because: evidenceList(parts), kinds: numbers.map(\.kind)))
            claims.claim(numbers)
        }

        // F5: count-then-trace still learning, or help-heavy over ≥ 5 rounds.
        var tracing: [WeeklyGame] = []
        for game in analysis.games where game.type == .practice && WeeklyPracticeFamily.of(kind: game.kind) == .tapTrace
            && claims.isFree(game) {
            if game.placement == .stillLearning || (game.helpHeavy && game.n >= Self.minimumRounds) { tracing.append(game) }
        }
        if !tracing.isEmpty, items.count < full {
            var parts: [WeeklySentence] = []
            for game in tracing {
                if let gameRow = self.row(game), gameRow.guideHelpsRounds > 0 {
                    parts.append(evidence(game, say("frag.helps", ["h": helpsValue(game, gameRow)])))
                } else {
                    parts.append(evidence(game, fact(game) ?? .empty))
                }
            }
            let text: WeeklySentence
            if facts.numeralsLearned.isEmpty {
                text = say("F5.plain")
            } else {
                let learned = numeralList(facts.numeralsLearned, path: "facts.numerals_learned", zhLast: " 同 ")
                text = say("F5", ["learned": .text(learned)])
            }
            items.append(WeeklyFamilyItem(id: "F5", text: text, because: evidenceList(parts), kinds: tracing.map(\.kind)))
            claims.claim(tracing)
        }

        // F4: a 手眼・畫線 practice game is still learning, or often starts away from the green dot.
        var pen: [WeeklyGame] = []
        for game in analysis.games where game.type == .practice && game.area == .pen && claims.isFree(game) {
            let gameFacts = rowFacts(game)
            let often = gameFacts.wrongStartKnown >= Self.minimumRounds && wrongStartHigh(gameFacts)
            if game.placement == .stillLearning || often { pen.append(game) }
        }
        if let first = pen.first, items.count < full {
            var parts: [WeeklySentence] = []
            for game in pen {
                let gameFacts = rowFacts(game)
                let gameFactsPath = factsPath(game)
                var evidenceFact: WeeklySentence
                if game.placement != .stillLearning {
                    evidenceFact = say("frag.wrongStart", [
                        "w": .int(gameFacts.wrongStart, path: gameFactsPath + ".wrong_start"),
                        "n": .int(gameFacts.wrongStartKnown, path: gameFactsPath + ".wrong_start_known")
                    ])
                } else {
                    evidenceFact = fact(game) ?? .empty
                    if let unit = offPathUnit(game.kind), gameFacts.offPathUnits > 0 {
                        let off = say("frag.offPath." + unit, ["x": offPathValue(game, gameFacts)])
                        evidenceFact = WeeklySentence.joined([evidenceFact, off], zh: "，", en: ", ")
                    }
                }
                parts.append(evidence(game, evidenceFact))
            }
            let roads = first.kind == ActivityKind.lineMatchGuidedStraight.rawValue
                || first.kind == ActivityKind.lineMatchGuidedBridge.rawValue
            items.append(WeeklyFamilyItem(id: "F4", text: say(roads ? "F4.roads" : "F4"), because: evidenceList(parts),
                                          kinds: pen.map(\.kind)))
            claims.claim(pen)
        }

        // F2 / F3: a 觀察・配對 / 比較・概念 quiz game is still learning.
        for (id, area) in [("F2", WeeklyArea.matching), ("F3", WeeklyArea.comparing)] {
            let games = stillLearning(.quiz).filter { $0.area == area && claims.isFree($0) }
            guard !games.isEmpty, items.count < full else { continue }
            var parts: [WeeklySentence] = []
            for game in games { parts.append(evidence(game, fact(game) ?? .empty)) }
            items.append(WeeklyFamilyItem(id: id, text: say(id), because: evidenceList(parts), kinds: games.map(\.kind)))
            claims.claim(games)
        }

        // F7: a quiz game often tapped before the question finished.
        for game in analysis.games where game.type == .quiz && claims.isFree(game) {
            guard let gameRow = self.row(game), fastRule(gameRow) else { continue }
            if items.count < full {
                let metrics = metricsPath(game)
                let because = evidenceList([say("ev.fast", ["game": .game(game.kind),
                                                            "f": .int(gameRow.fastWrong, path: metrics + ".fast_wrong"),
                                                            "w": .int(gameRow.wrongAttempts, path: metrics + ".wrong_attempts")])])
                items.append(WeeklyFamilyItem(id: "F7", text: say("F7"), because: because, kinds: [game.kind]))
                claims.claim([game])
            }
            break
        }

        var praise: WeeklySentence?
        if let object = winObject() {
            praise = say("F8", ["winObject": object.value])
        }
        var fallback: WeeklySentence?
        if items.isEmpty && daysPlayed > 0 { fallback = say("rec.none") }
        return (items, praise, fallback)
    }

    // MARK: §7.2 app items

    /// The quiz area with the lowest chance-adjusted rate, among ≥ 2 areas with ≥ 10 answered rounds
    /// with a chance.
    static func lowestArea(_ metrics: WeeklyWindowMetrics) -> WeeklyArea? {
        var best: (area: WeeklyArea, adjusted: Double)?
        var count = 0
        for area in quizAreas {
            let group = metrics.areas[area] ?? WeeklyGroupMetrics()
            guard group.expectedAnswered >= 10, let adjusted = group.adjusted else { continue }
            count += 1
            if let current = best, current.adjusted <= adjusted { continue }
            best = (area: area, adjusted: adjusted)
        }
        return count >= 2 ? best?.area : nil
    }

    /// The weight of `category` in a `category_mix` text such as "numbers:35,body:30".
    static func mixWeight(_ mix: String, _ category: String) -> Int? {
        for part in mix.split(separator: ",", omittingEmptySubsequences: false) {
            let pieces = part.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard let name = pieces.first, String(name) == category else { continue }
            return pieces.count == 2 ? Int(String(pieces[1])) : nil
        }
        return nil
    }

    /// Last week's tier of a W1 row (W2 rules on last week's estimate).
    func previousTier(_ row: WeeklyKindMetrics) -> WeeklyTier {
        let missing = model.previous.rounds.contains { $0.kind == row.kind && $0.type == .quiz && $0.chance == nil }
        return WeeklyScore(row, chanceMissing: missing).tier
    }

    func appItems() -> (items: [WeeklyAppItem], none: WeeklySentence?) {
        var items: [WeeklyAppItem] = []
        var claims = WeeklyClaims()
        let full = WeeklyReportText.appMaximum
        let seen = facts.settings

        // A5: fixed questions right ≥ 90 % over ≥ 10 rounds, unless this app version already generates them.
        var memorised: [WeeklyGame] = []
        for game in analysis.games where game.memorised && claims.isFree(game) {
            if let known = ActivityKind(rawValue: game.kind), QuestionGeneration.isGenerated(known) { continue }
            memorised.append(game)
        }
        if !memorised.isEmpty, items.count < full {
            let kinds = memorised.map(\.kind)
            let text = say(memorised.count == 1 ? "A5.one" : "A5",
                           ["games": .text(gameList(kinds)), "rate": .int(90, path: "rule.memorised_rate")])
            var ratios: [WeeklySentence] = []
            for game in memorised {
                let path = gamePath(game)
                ratios.append(say("ev.ratio", ["game": .game(game.kind), "k": .int(game.k, path: path + ".k"),
                                               "n": .int(game.n, path: path + ".n")]))
            }
            let because = say("A5.because", ["items": .text(WeeklySentence.joined(ratios, zh: "；", en: "; "))])
            let line = say("set.generated", ["kinds": .verbatim(kinds.joined(separator: ", "))])
            items.append(WeeklyAppItem(id: "A5", text: text, because: because, check: say("A5.check"), settings: [line],
                                       current: QuestionGeneration.fixed, suggested: "generated", kinds: kinds))
            claims.claim(memorised)
        }

        // A10: build more of a quiz area (lowest two weeks running, or ≥ 2 of its quiz games still learning).
        let lowestNow = Self.lowestArea(model.current), lowestBefore = Self.lowestArea(model.previous)
        for area in Self.quizAreas {
            let quizGames = analysis.games.filter { $0.area == area && $0.type == .quiz && claims.isFree($0) }
            let learning = stillLearning(.quiz).filter { $0.area == area }
            let lowest = lowestNow == area && lowestBefore == area
            guard !quizGames.isEmpty, lowest || learning.count >= 2, items.count < full else { continue }
            let name = WeeklyWords(area.zh, area.en).value
            let text = area == .numbers ? say("A10.numbers", ["area": name, "n": .int(3, path: "copy.A10.example")])
                : say("A10", ["area": name])
            let because: WeeklySentence
            if lowest {
                let now = model.current.areas[area] ?? WeeklyGroupMetrics()
                let before = model.previous.areas[area] ?? WeeklyGroupMetrics()
                let areaKey = "[" + area.rawValue + "]"
                because = say("A10.because.lowest", [
                    "area": name,
                    "p1": .percent(WeeklyFormat.percent(now.firstTry, of: now.answered),
                                   path: "metrics.current.areas" + areaKey + ".quiz_rate#pct"),
                    "c": .percent(WeeklyFormat.percent(now.chanceMean ?? 0),
                                  path: "metrics.current.areas" + areaKey + ".quiz_chance_mean#pct"),
                    "p0": .percent(WeeklyFormat.percent(before.firstTry, of: before.answered),
                                   path: "metrics.previous.areas" + areaKey + ".quiz_rate#pct")
                ])
            } else {
                because = say("A10.because.learning", [
                    "area": name,
                    "count": .int(learning.count, path: "analysis.ranking.still_learning.quiz[area=" + area.rawValue + "]#count"),
                    "games": .text(gameList(learning.map(\.kind)))
                ])
            }
            items.append(WeeklyAppItem(id: "A10", text: text, because: because, check: say("A10.check", ["area": name]),
                                       settings: [], current: nil, suggested: nil, kinds: quizGames.map(\.kind)))
            claims.claim(quizGames)
        }

        // A1: 數車仔 / 邊邊車多啲 still learning and 揀啱數 not played this week.
        let pickPlayed = analysis.games.contains {
            $0.kind == ActivityKind.tapCountPick.rawValue || $0.kind == ActivityKind.tapCountPickEnglish.rawValue
        }
        let counting = stillLearning(.quiz).filter {
            ($0.kind == ActivityKind.countVehicles.rawValue || $0.kind == ActivityKind.moreFewer.rawValue) && claims.isFree($0)
        }
        if let first = counting.first, !pickPlayed, items.count < full {
            let pick = WeeklySlotValue.game(ActivityKind.tapCountPick.rawValue)
            var parts: [WeeklySentence] = []
            for game in counting { parts.append(evidence(game, fact(game) ?? .empty)) }
            let because = say("A1.because", ["items": .text(WeeklySentence.joined(parts, zh: "；", en: "; ")), "pick": pick])
            let check = say("A1.check", ["game": .game(first.kind), "pick": pick,
                                         "min": .int(Self.minimumRounds, path: "rule.minimum_rounds")])
            let line = say("set.assignment", ["kind": .verbatim(ActivityKind.tapCountPick.rawValue),
                                              "stars": .words(zh: "★", en: "★"), "from": machine("off"), "to": machine("on")])
            items.append(WeeklyAppItem(id: "A1", text: say("A1", ["pick": pick]), because: because, check: check,
                                       settings: [line], current: "off", suggested: "on", kinds: counting.map(\.kind)))
            claims.claim(counting)
        }

        // A4: count-then-trace help-heavy or smooth < 50 % (≥ 5 rounds): more tracing help.
        for game in analysis.games where game.type == .practice && WeeklyPracticeFamily.of(kind: game.kind) == .tapTrace
            && claims.isFree(game) {
            guard game.n >= Self.minimumRounds, game.helpHeavy || 2 * game.k < game.n, items.count < full else { continue }
            let level = seen.guideLevel
            let more = WeeklyTextCatalog.guidance("more") ?? WeeklyWords("多啲", "More")
            var text: WeeklySentence?
            var line: WeeklySentence?
            var current: String?
            var suggested: String?
            if level != "more" {
                if let level, let label = WeeklyTextCatalog.guidance(level) {
                    text = say("A4", ["current": label.value, "suggested": more.value])
                    line = settingLine("TapCountSettings.guidance", level, "more")
                } else {
                    text = say("A4.to", ["suggested": more.value])
                    line = settingLine("TapCountSettings.guidance", to: "more")
                }
                current = level
                suggested = "more"
            } else if seen.traceScaffold == "outline", let from = WeeklyTextCatalog.scaffold("outline"),
                      let to = WeeklyTextCatalog.scaffold("dots") {
                text = say("A4.scaffold", ["current": from.value, "suggested": to.value])
                line = settingLine("TapCountSettings.traceScaffold", "outline", "dots")
                current = "outline"
                suggested = "dots"
            }
            guard let text, let line else { continue }
            var evidenceFact = fact(game) ?? .empty
            if let gameRow = self.row(game), gameRow.guideHelpsRounds > 0 {
                let helps = say("frag.helps", ["h": helpsValue(game, gameRow)])
                evidenceFact = WeeklySentence.joined([evidenceFact, helps], zh: "，", en: ", ")
            }
            items.append(WeeklyAppItem(id: "A4", text: text, because: evidenceList([evidence(game, evidenceFact)]),
                                       check: say("A4.check"), settings: [line], current: current, suggested: suggested,
                                       kinds: [game.kind]))
            claims.claim([game])
            break
        }

        // A6: guided roads smooth < 50 % with ≥ 2 off-path per road.
        for game in analysis.games where game.type == .practice && claims.isFree(game)
            && (game.kind == ActivityKind.lineMatchGuidedStraight.rawValue
                || game.kind == ActivityKind.lineMatchGuidedBridge.rawValue) {
            let gameFacts = rowFacts(game)
            guard game.n >= Self.minimumRounds, 2 * game.k < game.n, gameFacts.offPathUnits > 0,
                  gameFacts.offPath >= 2 * gameFacts.offPathUnits, items.count < full,
                  let gameRow = self.row(game) else { continue }
            var highStars: [Int] = []
            for star in [2, 3] where gameRow.stars.count >= star && gameRow.stars[star - 1].rounds > 0 {
                highStars.append(star)
            }
            let bridge = game.kind == ActivityKind.lineMatchGuidedBridge.rawValue && !highStars.isEmpty
            let tolerance = seen.lineTolerance
            let wide = WeeklyTextCatalog.tolerance("wide") ?? WeeklyWords("闊", "Wide")
            var lines: [WeeklySentence] = []
            var current: String?
            var suggested: String?
            if bridge {
                let stars = highStars.map { WeeklyFormat.stars($0) }.joined(separator: "/")
                lines.append(say("set.assignment", ["kind": .verbatim(ActivityKind.lineMatchGuidedBridge.rawValue),
                                                    "stars": .words(zh: stars, en: stars), "from": machine("on"),
                                                    "to": machine("off")]))
                current = "on"
                suggested = "off"
            }
            let toleranceLabel = tolerance.flatMap { WeeklyTextCatalog.tolerance($0) }
            let text: WeeklySentence
            if bridge && tolerance == "wide" {
                text = say("A6.bridge", ["wide": wide.value])
            } else if bridge, let tolerance, let label = toleranceLabel {
                text = say("A6.bridge.wide", ["current": label.value, "wide": wide.value])
                lines.append(settingLine("LineMatchSettings.tolerance", tolerance, "wide"))
            } else if bridge {
                text = say("A6.bridge.only")
            } else if let tolerance, let label = toleranceLabel, tolerance != "wide" {
                text = say("A6.wide", ["current": label.value, "wide": wide.value])
                lines.append(settingLine("LineMatchSettings.tolerance", tolerance, "wide"))
                current = tolerance
                suggested = "wide"
            } else {
                continue
            }
            let off = say("frag.offPath.road", ["x": offPathValue(game, gameFacts)])
            let evidenceFact = WeeklySentence.joined([fact(game) ?? .empty, off], zh: "，", en: ", ")
            items.append(WeeklyAppItem(id: "A6", text: text, because: evidenceList([evidence(game, evidenceFact)]),
                                       check: say("A6.check"), settings: lines, current: current, suggested: suggested,
                                       kinds: [game.kind]))
            claims.claim([game])
            break
        }

        // A7: 連一連 · 自己配 still learning, ≥ 60 % of ≥ 4 wrong lines in one category.
        for game in stillLearning(.quiz) where game.kind == ActivityKind.lineMatch.rawValue && claims.isFree(game) {
            let gameFacts = rowFacts(game)
            guard gameFacts.wrongLinesTotal >= 4, items.count < full else { continue }
            var best: (category: LineMatchCategory, lines: Int)?
            for category in LineMatchCategory.allCases {
                let lines = gameFacts.wrongLines[category.rawValue] ?? 0
                if let current = best, current.lines >= lines { continue }
                best = (category: category, lines: lines)
            }
            guard let top = best, 10 * top.lines >= 6 * gameFacts.wrongLinesTotal,
                  let weight = Self.mixWeight(seen.categoryMix ?? "", top.category.rawValue), weight > 0 else { continue }
            let lowered = max(0, weight - 10)
            let category = WeeklyWords(top.category.titleTraditionalChinese, top.category.titleEnglish).value
            let mixPath = "facts.settings.category_mix[" + top.category.rawValue + "]"
            let gameFactsPath = factsPath(game)
            let line = say("set.weight", ["setting": machine("LineMatchSettings.weight[" + top.category.rawValue + "]"),
                                          "from": .int(weight, path: mixPath), "to": .int(lowered, path: mixPath + "-10")])
            let because = say("A7.because", [
                "m": .int(top.lines, path: gameFactsPath + ".wrong_lines[" + top.category.rawValue + "]"),
                "w": .int(gameFacts.wrongLinesTotal, path: gameFactsPath + ".wrong_lines_total"), "category": category
            ])
            items.append(WeeklyAppItem(id: "A7", text: say("A7", ["game": .game(game.kind), "category": category,
                                                                  "step": .int(10, path: "rule.A7.step")]),
                                       because: because, check: say("A7.check", ["game": .game(game.kind)]),
                                       settings: [line], current: String(weight), suggested: String(lowered),
                                       kinds: [game.kind]))
            claims.claim([game])
            break
        }

        // A2: 點數 smooth < 60 % (recounts common): narrow the numbers.
        for game in analysis.games where game.type == .practice && WeeklyPracticeFamily.of(kind: game.kind) == .tapAll
            && claims.isFree(game) {
            guard game.n >= Self.minimumRounds, 10 * game.k < 6 * game.n, let range = seen.range, range > 5,
                  items.count < full else { continue }
            let voiceOff = seen.countVoice == false
            let from = WeeklySlotValue.range(range, path: "facts.settings.range")
            let to = WeeklySlotValue.range(5, path: "rule.A2.range")
            var lines = [say("set.range", ["setting": machine("TapCountSettings.range"), "from": from, "to": to])]
            if voiceOff { lines.append(settingLine("TapCountSettings.countVoice", "off", "on")) }
            let path = gamePath(game)
            let because = say("A2.because", ["game": .game(game.kind), "n": .int(game.n, path: path + ".n"),
                                             "r": .int(game.n - game.k, path: factsPath(game) + ".recount_rounds")])
            items.append(WeeklyAppItem(id: "A2", text: say(voiceOff ? "A2.voice" : "A2", ["from": from, "to": to]),
                                       because: because, check: say("A2.check"), settings: lines, current: String(range),
                                       suggested: "5", kinds: [game.kind]))
            claims.claim([game])
            break
        }

        // A3: 點數 smooth ≥ 90 % two weeks running at 1–5 or 1–7: widen the numbers.
        for game in analysis.games where game.type == .practice && WeeklyPracticeFamily.of(kind: game.kind) == .tapAll
            && claims.isFree(game) {
            let k0 = game.wow.k0, n0 = game.wow.n0
            guard game.n >= Self.minimumRounds, n0 >= Self.minimumRounds, 10 * game.k >= 9 * game.n, 10 * k0 >= 9 * n0,
                  let range = seen.range, range == 5 || range == 7, items.count < full else { continue }
            let next = range == 5 ? 7 : 10
            let from = WeeklySlotValue.range(range, path: "facts.settings.range")
            let to = WeeklySlotValue.range(next, path: "rule.A3.range")
            let path = gamePath(game)
            let because = say("A3.because", ["game": .game(game.kind), "k1": .int(game.k, path: path + ".k"),
                                             "n1": .int(game.n, path: path + ".n"), "k0": .int(k0, path: path + ".wow.k0"),
                                             "n0": .int(n0, path: path + ".wow.n0")])
            let line = say("set.range", ["setting": machine("TapCountSettings.range"), "from": from, "to": to])
            items.append(WeeklyAppItem(id: "A3", text: say("A3", ["from": from, "to": to]), because: because,
                                       check: say("A3.check", ["keep": .int(80, path: "rule.A3.keep")]), settings: [line],
                                       current: String(range), suggested: String(next), kinds: [game.kind]))
            claims.claim([game])
            break
        }

        // A4b: count-then-trace traced without help ≥ 80 % two weeks running: less tracing help.
        for game in analysis.games where game.type == .practice && WeeklyPracticeFamily.of(kind: game.kind) == .tapTrace
            && claims.isFree(game) {
            let key = WeeklyRowKey(game)
            guard let now = facts.rows[key], let before = facts.previousRows[key],
                  now.guideCleanKnown >= Self.minimumRounds, before.guideCleanKnown >= Self.minimumRounds,
                  10 * now.guideClean >= 8 * now.guideCleanKnown, 10 * before.guideClean >= 8 * before.guideCleanKnown,
                  items.count < full else { continue }
            let level = seen.guideLevel
            let less = WeeklyTextCatalog.guidance("less") ?? WeeklyWords("少啲", "Less")
            let text: WeeklySentence
            let line: WeeklySentence
            let current: String?
            let suggested: String
            if level != "less" {
                if let level, let label = WeeklyTextCatalog.guidance(level) {
                    text = say("A4b", ["current": label.value, "suggested": less.value])
                    line = settingLine("TapCountSettings.guidance", level, "less")
                } else {
                    text = say("A4b.to", ["suggested": less.value])
                    line = settingLine("TapCountSettings.guidance", to: "less")
                }
                current = level
                suggested = "less"
            } else if seen.traceScaffold == "dots", let from = WeeklyTextCatalog.scaffold("dots"),
                      let to = WeeklyTextCatalog.scaffold("outline") {
                text = say("A4b.scaffold", ["current": from.value, "suggested": to.value])
                line = settingLine("TapCountSettings.traceScaffold", "dots", "outline")
                current = "dots"
                suggested = "outline"
            } else {
                continue
            }
            let gameFactsPath = factsPath(game)
            let because = say("A4b.because", [
                "game": .game(game.kind), "k1": .int(now.guideClean, path: gameFactsPath + ".guide_clean"),
                "n1": .int(now.guideCleanKnown, path: gameFactsPath + ".guide_clean_known"),
                "k0": .int(before.guideClean, path: gameFactsPath + ".previous_guide_clean"),
                "n0": .int(before.guideCleanKnown, path: gameFactsPath + ".previous_guide_clean_known")
            ])
            items.append(WeeklyAppItem(id: "A4b", text: text, because: because,
                                       check: say("A4b.check", ["keep": .int(70, path: "rule.A4b.keep")]), settings: [line],
                                       current: current, suggested: suggested, kinds: [game.kind]))
            claims.claim([game])
            break
        }

        // A8: shapes often started away from the green dot, with the direction hint off.
        let shapeKinds = [ActivityKind.traceLines.rawValue, ActivityKind.traceShapesDotted.rawValue,
                          ActivityKind.traceShapesArrows.rawValue]
        for game in analysis.games where game.type == .practice && shapeKinds.contains(game.kind) && claims.isFree(game) {
            let gameFacts = rowFacts(game)
            guard gameFacts.wrongStartKnown >= Self.minimumRounds, wrongStartHigh(gameFacts), seen.directionHint == false,
                  items.count < full else { continue }
            let gameFactsPath = factsPath(game)
            let wrongStarts = say("frag.wrongStart", [
                "w": .int(gameFacts.wrongStart, path: gameFactsPath + ".wrong_start"),
                "n": .int(gameFacts.wrongStartKnown, path: gameFactsPath + ".wrong_start_known")
            ])
            items.append(WeeklyAppItem(id: "A8", text: say("A8"), because: evidenceList([evidence(game, wrongStarts)]),
                                       check: say("A8.check"),
                                       settings: [settingLine("ShapeTraceSettings.directionHint", "off", "on")],
                                       current: "off", suggested: "on", kinds: [game.kind]))
            claims.claim([game])
            break
        }

        // A9: 畫直線 smooth ≥ 90 % over ≥ 10 rounds in two weeks, slant lines off.
        for game in analysis.games where game.type == .practice && game.kind == ActivityKind.traceLines.rawValue
            && claims.isFree(game) {
            let k2 = game.k + game.wow.k0, n2 = game.n + game.wow.n0
            guard n2 >= 10, 10 * k2 >= 9 * n2, seen.slantLines == false, items.count < full else { continue }
            let gameFactsPath = factsPath(game)
            let because = say("A9.because", ["game": .game(game.kind), "n": .int(n2, path: gameFactsPath + ".two_weeks_n"),
                                             "k": .int(k2, path: gameFactsPath + ".two_weeks_k")])
            items.append(WeeklyAppItem(id: "A9", text: say("A9", ["age": .int(4, path: "copy.A9.age")]), because: because,
                                       check: say("A9.check", ["game": .game(game.kind), "keep": .int(80, path: "rule.A9.keep")]),
                                       settings: [settingLine("ShapeTraceSettings.slantLines", "off", "on")],
                                       current: "off", suggested: "on", kinds: [game.kind]))
            claims.claim([game])
            break
        }

        // A11: every ranked quiz game of an area going well, this week and last week.
        for area in Self.quizAreas {
            let now = analysis.games.filter { $0.area == area && $0.type == .quiz && $0.tier.isQualified }
            let before = model.previous.kinds.filter { $0.area == area && $0.type == .quiz && previousTier($0).isQualified }
            guard !now.isEmpty, !before.isEmpty, items.count < full,
                  !now.contains(where: { $0.tier != .goingWell }),
                  !before.contains(where: { previousTier($0) != .goingWell }),
                  !now.contains(where: { !claims.isFree($0) }) else { continue }
            let name = WeeklyWords(area.zh, area.en).value
            items.append(WeeklyAppItem(id: "A11", text: say("A11", ["area": name, "choices": .int(4, path: "copy.A11.choices")]),
                                       because: say("A11.because", ["area": name, "games": .text(gameList(now.map(\.kind)))]),
                                       check: say("A11.check"), settings: [], current: nil, suggested: nil,
                                       kinds: now.map(\.kind)))
            claims.claim(now)
        }

        // A12: across quiz games, ≥ 30 % of ≥ 3 wrong taps before the question finished.
        if quizWrongAttempts >= 3, 10 * quizFastWrong >= 3 * quizWrongAttempts, items.count < full {
            let because = say("A12.because", ["f": .int(quizFastWrong, path: "facts.quiz_fast_wrong"),
                                              "w": .int(quizWrongAttempts, path: "facts.quiz_wrong_attempts")])
            items.append(WeeklyAppItem(id: "A12", text: say("A12"), because: because, check: say("A12.check"), settings: [],
                                       current: nil, suggested: nil, kinds: []))
        }

        var fallback: WeeklySentence?
        if items.isEmpty && daysPlayed > 0 { fallback = say("app.none") }
        return (items, fallback)
    }

    // MARK: §7.3 questions

    func questions() -> [WeeklyQuestion] {
        var out: [WeeklyQuestion] = []
        if asksAboutVideo {
            let perDay = WeeklySlotValue.minutes(WeeklyFormat.minutes(ms: videoMs, per: daysPlayed),
                                                 path: "facts.video_minutes_per_day_played")
            let question: WeeklySentence
            if plays > 0 {
                question = say("Q1", ["h": perDay, "m": .int(WeeklyFormat.minutes(ms: videoMs, per: plays),
                                                             path: "facts.video_minutes_per_play")])
            } else {
                question = say("Q1.noPicks", ["h": perDay])
            }
            out.append(WeeklyQuestion(id: "Q1", question: question, note: say("Q1.note")))
        }
        let counted = model.current.totals.rounds
        if excludedTotal > 0, 5 * excludedTotal >= counted + excludedTotal {
            let question = say(excludedTotal == 1 ? "Q2.one" : "Q2", [
                "n": .int(excludedTotal, path: "metrics.current.excluded_rounds.total"), "name": .verbatim(childName)
            ])
            out.append(WeeklyQuestion(id: "Q2", question: question, note: nil))
        }
        return out
    }

    // MARK: Facts block

    func factsJSON() -> PerfValue {
        var games: [PerfValue] = []
        for row in model.current.kinds {
            let key = WeeklyRowKey(kind: row.kind, type: row.type)
            let now = facts.rows[key] ?? WeeklyRowFacts()
            let before = facts.previousRows[key] ?? WeeklyRowFacts()
            let game = gamesByKey[key]
            let n = game?.n ?? 0, k = game?.k ?? 0
            var o: [String: PerfValue] = [:]
            o["kind"] = .string(row.kind)
            o["type"] = .string(row.type.rawValue)
            o["off_path"] = .int(now.offPath)
            o["off_path_units"] = .int(now.offPathUnits)
            o["wrong_start"] = .int(now.wrongStart)
            o["wrong_start_known"] = .int(now.wrongStartKnown)
            o["guide_clean"] = .int(now.guideClean)
            o["guide_clean_known"] = .int(now.guideCleanKnown)
            o["previous_guide_clean"] = .int(before.guideClean)
            o["previous_guide_clean_known"] = .int(before.guideCleanKnown)
            o["wrong_lines"] = .object(now.wrongLines.mapValues { PerfValue.int($0) })
            o["wrong_lines_total"] = .int(now.wrongLinesTotal)
            o["two_weeks_n"] = .int(n + (game?.wow.n0 ?? 0))
            o["two_weeks_k"] = .int(k + (game?.wow.k0 ?? 0))
            let tapAll = row.type == .practice && WeeklyPracticeFamily.of(kind: row.kind) == .tapAll
            o["recount_rounds"] = .int(tapAll ? n - k : 0)
            games.append(.object(o))
        }
        let seen = facts.settings
        var settings: [String: PerfValue] = [:]
        settings["range"] = PerfValue.optionalInt(seen.range)
        settings["count_voice"] = PerfValue.optionalBool(seen.countVoice)
        settings["trace_scaffold"] = PerfValue.optionalString(seen.traceScaffold)
        settings["guide_level"] = PerfValue.optionalString(seen.guideLevel)
        settings["line_tolerance"] = PerfValue.optionalString(seen.lineTolerance)
        settings["category_mix"] = PerfValue.optionalString(seen.categoryMix)
        settings["direction_hint"] = PerfValue.optionalBool(seen.directionHint)
        settings["slant_lines"] = PerfValue.optionalBool(seen.slantLines)
        var videos: [PerfValue] = []
        for video in facts.videos {
            videos.append(.object(["video": .string(video.video), "watched_ms": .int(video.watchedMs),
                                   "minutes": .int(WeeklyFormat.minutes(ms: video.watchedMs)), "title": .string(video.title)]))
        }
        var withoutPlay: [PerfValue] = []
        for day in facts.coveredDays where !model.current.days[day].played { withoutPlay.append(.int(day)) }
        var o: [String: PerfValue] = [:]
        o["games"] = .array(games)
        o["settings"] = .object(settings)
        o["videos"] = .array(videos)
        o["numerals_learned"] = .array(facts.numeralsLearned.map { PerfValue.int($0) })
        o["rounds_change"] = .int(abs(analysis.comparison.rounds.current - analysis.comparison.rounds.previous))
        o["days_without_play"] = .array(withoutPlay)
        o["video_ms"] = .int(videoMs)
        o["plays"] = .int(plays)
        o["video_minutes_per_day_played"] = daysPlayed > 0
            ? PerfValue.int(WeeklyFormat.minutes(ms: videoMs, per: daysPlayed)) : PerfValue.null
        o["video_minutes_per_play"] = plays > 0
            ? PerfValue.int(WeeklyFormat.minutes(ms: videoMs, per: plays)) : PerfValue.null
        o["quiz_fast_wrong"] = .int(quizFastWrong)
        o["quiz_wrong_attempts"] = .int(quizWrongAttempts)
        return .object(o)
    }
}

// MARK: Canonical JSON (W1 `WeeklyJSON` rules)

extension WeeklyGameText {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["kind"] = .string(kind)
        o["type"] = .string(type.rawValue)
        o["placement"] = .string(placement.rawValue)
        o["fact"] = fact?.json ?? .null
        o["comment"] = .array(comment.map(\.json))
        o["short"] = .array(short.map(\.json))
        return .object(o)
    }
}

extension WeeklyRankingText {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["status"] = status?.json ?? .null
        o["top_split"] = topSplit?.json ?? .null
        o["still_learning_split"] = stillLearningSplit?.json ?? .null
        o["also_well"] = alsoWell?.json ?? .null
        o["also_learning"] = alsoLearning?.json ?? .null
        return .object(o)
    }
}

extension WeeklyFamilyItem {
    public var json: PerfValue {
        .object(["id": .string(id), "text": text.json, "because": because.json, "kinds": PerfValue.strings(kinds)])
    }
}

extension WeeklyAppItem {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["id"] = .string(id)
        o["text"] = text.json
        o["because"] = because.json
        o["check"] = check.json
        o["settings"] = .array(settings.map(\.json))
        o["current"] = PerfValue.optionalString(current)
        o["suggested"] = PerfValue.optionalString(suggested)
        o["kinds"] = PerfValue.strings(kinds)
        return .object(o)
    }
}

extension WeeklyQuestion {
    public var json: PerfValue {
        .object(["id": .string(id), "question": question.json, "note": note?.json ?? .null])
    }
}

extension WeeklyReportText {
    public var json: PerfValue {
        var o: [String: PerfValue] = [:]
        o["text"] = .int(Self.textVersion)
        o["analysis"] = .int(WeeklyAnalysis.analysisVersion)
        o["builder"] = .int(WeeklyModel.builderVersion)
        o["time_zone"] = .string(analysis.model.window.timeZone.identifier)
        o["week_start"] = .string(analysis.model.window.weekStartStamp)
        o["data_until"] = .string(PerfCodec.formatTimestamp(analysis.model.window.cutoff))
        o["child_name"] = .string(childName)
        o["empty"] = empty?.json ?? .null
        o["highlights"] = .array(highlights.map(\.json))
        o["wins"] = .array(wins.map(\.json))
        o["win_candidates"] = .array(winCandidates.map(\.json))
        o["games"] = .array(games.map(\.json))
        o["ranking"] = ranking.json
        o["videos"] = videos?.json ?? .null
        o["changes"] = .array(changes.map(\.json))
        var recommendations: [String: PerfValue] = [:]
        recommendations["family"] = .array(family.map(\.json))
        recommendations["praise"] = praise?.json ?? .null
        recommendations["family_none"] = familyNone?.json ?? .null
        recommendations["app"] = .array(app.map(\.json))
        recommendations["app_none"] = appNone?.json ?? .null
        recommendations["questions"] = .array(questions.map(\.json))
        o["recommendations"] = .object(recommendations)
        o["facts"] = facts
        return .object(o)
    }

    /// The canonical text the W3 golden fixtures compare (W1 `WeeklyJSON` rules).
    public func canonicalJSON() -> String {
        WeeklyJSON.encode(json)
    }
}
