#!/usr/bin/env python3
"""Independent reference for the W4 weekly report HTML (design weekly-report §3, §8, §9; ADR 0024).

Reads the W1, W2 and W3 goldens of a fixture folder (`expected-metrics.json`, `expected-analysis.json`,
`expected-text.json`) and prints the report HTML that `WeeklyReportHTML.render` must produce byte for
byte. Standard library only; the W3 word tables come from `reference_text.py`, nothing from the Swift
side. Every coordinate and layout estimate is computed in integer tenths of a CSS px. The only
floating-point inputs (the chance means printed as whole percents) are refused when they sit near a
rounding tie, because the JSON keeps 6 decimals and Swift keeps the full double.

Usage:
  python3 reference_html.py <folder> <generated_at ISO-8601> [--sample] > expected-report.html
"""

import json
import math
import os
import sys
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # leave no __pycache__ in the fixture folders
sys.path.insert(0, HERE)
import reference_text as w3  # noqa: E402

w1 = w3.w1

REPORT_VERSION = 1
MIN_ROUNDS = 5
STILL_LEARNING_DAYS = 2
SAME_POINTS = 20
GAME_MINUTES_CAP = 10
CHANGES_PAGE = 5
# Caps (design §3, §13 item 10; ADR 0024).
MATRIX_MAX_ROWS = 22
MATRIX_KEEP_ROWS = 21
MATRIX_GLOSSARY_LINES = 24
FOLD_NAMES_MAX = 6
NEW_NAMES_MAX = 1
CLEAR_MAX = 3
GEAR_NAMES_MAX = 3
VERSIONS_LISTED = 2
CHANGE_LINES_MAX = 2
INSUFFICIENT_ROWS_MAX = 6
UTC = timezone.utc
HKT = timezone(timedelta(hours=8))

# ---------------------------------------------------------------- palette (WeeklyReportPalette)

# Series slots 1-3 of the validated reference palette (design §8; validate_palette.js, light, #ffffff).
QUIZ, VIDEO, PRACTICE = "#2a78d6", "#eb6834", "#1baf7a"
INK, INK2, MUTED = "#0b0b0b", "#52514e", "#898781"
GRID, BASE_LINE, BAND = "#e1e0d9", "#c3c2b7", "#e1e0d9"
SURFACE = "#ffffff"
QUIZ_TINT, PRACTICE_TINT = "#e5effa", "#e4f5ef"
BRAND, PAPER, TICKET, METRO = "#2f4b8f", "#fff6df", "#fff4c7", "#ddebff"
STAMP, PANEL, BADGE_GREY = "#b8312f", "#f6f5f1", "#f1f0ec"
BADGE_QUIZ_LINE, BADGE_PRACTICE_LINE, BADGE_NEW, BADGE_NEW_LINE = "#9ec5f4", "#8fd8bd", "#fde3d7", "#f3b39a"

# ---------------------------------------------------------------- the W4 label table (WeeklyReportLabels)

L = {
    # running head and foot
    "head.title": ("VisaGames 每週學習報告", "Weekly report"),
    "head.family": ("家長版，只供家人參考", "For parents, family use only"),
    "sample": ("示例數據", "EXAMPLE DATA"),
    "foot.provenance": ("VisaGames 週報 v{report} · builder {builder} · 資料截至 {until} · 製作於 {made} · App {apps} · 數據指紋 {fp}",
                        "VisaGames weekly report v{report} · builder {builder} · data up to {until} · made {made} · "
                        "app {apps} · data fingerprint {fp}"),
    "foot.counted": ("只計 {name} 自己玩", "Counts {name}'s own play only"),
    "foot.page": ("第 {n} 頁，共 {total} 頁", "Page {n} of {total}"),
    "doc.title": ("VisaGames 每週學習報告 {week}", "VisaGames weekly report {week}"),
    "doc.sample": ("（示例數據）", " (example data)"),
    # dates
    "date.md": ("{m}月{d}日", "{d} {mon}"),
    "date.mdw": ("{m}月{d}日（{w}）", "{wd} {d} {mon}"),
    "date.span": ("{m}月{d0}–{d1}日", "{d0}–{d1} {mon}"),
    "range.month": ("{y}年{m}月{d0}–{d1}日", "{d0}–{d1} {mon} {y}"),
    "range.year": ("{y}年{m0}月{d0}日–{m1}月{d1}日", "{d0} {mon0} – {d1} {mon1} {y}"),
    "range.other": ("{y0}年{m0}月{d0}日–{y1}年{m1}月{d1}日", "{d0} {mon0} {y0} – {d1} {mon1} {y1}"),
    # page 1
    "p1.title": ("每週學習報告", "Weekly learning report"),
    "p1.until": ("資料截至 {date} {time}", "data up to {date}, {time} HKT"),
    "p1.whole": ("成個星期", "the whole week"),
    "p1.highlights": ("本週重點", "Highlights"),
    "tile.days": ("有玩嘅日子", "Days played"),
    "tile.rounds": ("遊戲局數", "Rounds played"),
    "tile.quiz": ("答題遊戲：第一次答啱", "Quiz games: right first time"),
    "tile.practice": ("練習遊戲：做得順", "Practice games: done smoothly"),
    "tile.game": ("遊戲時間", "Game time"),
    "tile.video": ("睇片時間", "Video time"),
    "unit.ofDays": (" / {n} 日", " / {n} days"),
    "unit.hours": (" 小時 ", " h "),
    "unit.minutes": (" 分", " min"),
    "unit.minutesOnly": (" 分鐘", " min"),
    "unit.approx": ("約 ", "about "),
    "cmp.days": ("上星期 {n} 日", "Last week: {n} days"),
    "cmp.daysOne": ("上星期 {n} 日", "Last week: {n} day"),
    "cmp.rounds": ("上星期 {n} 局", "Last week: {n} rounds"),
    "cmp.roundsOne": ("上星期 {n} 局", "Last week: {n} round"),
    "cmp.rate": ("上星期 {p}%", "Last week {p}%"),
    "cmp.noQuiz": ("上星期冇答題遊戲", "Last week: no quiz games"),
    "cmp.noPractice": ("上星期冇練習遊戲", "Last week: no practice games"),
    "cmp.time": ("上星期 {t}", "Last week {t}"),
    "cmp.guess": ("亂估都有約 {c}%", "guessing ≈ {c}%"),
    "cmp.perRound": ("每局平均 {x} 分鐘", "{x} min per round"),
    "cmp.visa": ("賺到簽證 {t}", "visa earned {t}"),
    "cmp.notEnough": ("數據唔夠（{n} 局）", "Not enough data ({n} rounds)"),
    "cmp.notEnoughOne": ("數據唔夠（{n} 局）", "Not enough data ({n} round)"),
    "change.same": ("差唔多", "about the same"),
    "change.up": ("↑ 明顯進步", "↑ clearly up"),
    "change.down": ("↓ 明顯少咗", "↓ clearly down"),
    "change.unsure": ("變化未夠肯定", "change not clear yet"),
    "change.more": ("↑ 明顯多咗", "↑ clearly more"),
    "change.fewer": ("↓ 明顯少咗", "↓ clearly fewer"),
    "change.less": ("↓ 明顯少咗", "↓ clearly less"),
    "wr.baseline": ("今個星期係第一個有紀錄嘅星期，未有上星期可以比較。",
                    "This is the first week with records, so there is no last week to compare with."),
    "wr.partialPrev": ("上星期只有 {n} 日有紀錄，比較只可以做參考。",
                       "Last week has records on only {n} days, so comparisons are only a rough guide."),
    "wr.partialPrevOne": ("上星期只有 {n} 日有紀錄，比較只可以做參考。",
                          "Last week has records on only {n} day, so comparisons are only a rough guide."),
    "p1.wins": ("本週亮點", "Wins this week"),
    "p1.next": ("下星期可以試吓", "Try next week"),
    "p1.counted": ("只計 {name} 自己玩：家長試玩、測試簽證、測試模式都唔計。",
                   "Counts {name}'s own play only; parent playtests, test visas and test mode are excluded."),
    "p1.excluded": ("今個星期有 {n} 局唔計。", "{n} rounds were not counted this week."),
    "p1.excludedOne": ("今個星期有 {n} 局唔計。", "{n} round was not counted this week."),
    "p1.changes": ("今個星期 app 更新咗 {u} 次、改咗 {s} 個設定，詳情喺第 {page} 頁。",
                   "App updates this week: {u}; setting changes: {s} (page {page})."),
    "p1.updates": ("今個星期 app 更新咗 {u} 次，詳情喺第 {page} 頁。", "App updates this week: {u} (page {page})."),
    "p1.settings": ("今個星期改咗 {s} 個設定，詳情喺第 {page} 頁。", "Setting changes this week: {s} (page {page})."),
    "wr.privacy": ("呢份報告喺屋企部 Mac 度製作，冇上網。分享之前諗清楚收件人。",
                   "Made on the home Mac, offline. Think about who receives it before sharing."),
    # page 2
    "p2.title": ("每日明細", "Day by day"),
    "p2.chart": ("每日遊戲同睇片時間（分鐘）", "Minutes per day: games (quiz + practice) and videos"),
    "c1.empty": ("今個星期未有遊戲或睇片紀錄。", "No game or video time recorded this week."),
    "legend.quizGames": ("答題遊戲", "Quiz games"),
    "legend.practiceGames": ("練習遊戲", "Practice games"),
    "legend.videos": ("睇片", "Videos"),
    "axis.minutes": ("分鐘", "min"),
    "day.noPlay": ("冇玩", "No play"),
    "day.notYet": ("未到", "Not yet"),
    "day.noRecords": ("未有紀錄", "No records"),
    "day.upTo": ("截至 {time}", "to {time}"),
    "th.date": ("日期", "Date"),
    "th.sessions": ("玩咗幾次", "Sessions"),
    "th.rounds": ("局數", "Rounds (quiz / practice)"),
    "th.quiz": ("答題：第一次答啱", "Quiz: right first time"),
    "th.practice": ("練習：做得順", "Practice: smooth"),
    "th.games": ("遊戲（分鐘）", "Games (min)"),
    "th.videos": ("睇片（分鐘）", "Videos (min)"),
    "th.visa": ("賺到簽證（分鐘）", "Visa earned (min)"),
    "th.note": ("備註", "Note"),
    "row.total": ("合計", "Week"),
    "note.newGame": ("第一次玩「{game}」", "first time: {game}"),
    "note.moreNew": ("同另外 {n} 個新遊戲", "+{n} more new"),
    "p2.tickets": ("揀車票：★ {a} 次 · ★★ {b} 次 · ★★★ {c} 次（星愈多，簽證愈長；部分遊戲星愈多題目愈難）。",
                   "Tickets chosen: ★ {a} · ★★ {b} · ★★★ {c} (more stars = longer visa; for some games, harder questions)."),
    "p2.time": ("遊戲時間 = 每局由出題到完成（唔計家長時間，每局最多計 {cap} 分鐘）。睇片時間 = 片真正播咗嘅時間。",
                "Game time = from question shown to finished (parent time excluded, at most {cap} min per round). "
                "Video time = time a video actually played."),
    "p2.cutoff": ("{day}只計到 {time}。", "{day} counts up to {time}."),
    "p2.approx": ("「約」= 片未播完就停咗（例如停電），用最後記錄到嘅時間。",
                  "「約」 = a video stopped without an end record (e.g. a power cut); the last recorded time is used."),
    "p2.pointer": ("睇片時間第 {page} 頁有個問題想問你哋。", "Page {page} has a question about video time."),
    # page 3
    "p3.title": ("玩咗乜、做成點", "Which games, and how they went"),
    "p3.cells": ("每格：答題遊戲 = 第一次答啱／答咗幾多局；練習遊戲 = 做得順／玩咗幾多局。空格 = 嗰日冇玩；「—」= 冇可以計嘅結果。",
                 "Each cell: quiz games = right first time / rounds; practice games = done smoothly / rounds. "
                 "Blank = not played; \"—\" = nothing to score."),
    "p3.badges": ("「同一題」= 呢個遊戲次次都係同一條題目；「新」= 今個星期第一次玩；「⚙ 設定改咗」= 今個星期改過設定。",
                  "\"同一題\" = always the same question; \"新 New\" = first played this week; \"⚙\" = settings changed this week."),
    "th.game": ("遊戲", "Game"),
    "th.week": ("合計", "Week"),
    "th.tickets": ("★ · ★★ · ★★★", "tickets"),
    "badge.quiz": ("答題", "Quiz"),
    "badge.practice": ("練習", "Practice"),
    "badge.new": ("新", "New"),
    "badge.fixed": ("同一題", "Same question"),
    "badge.settings": ("⚙ 設定改咗", "⚙ settings changed"),
    "m1.fold": ("其他 {n} 個遊戲（共 {m} 局）：{names}", "{n} other games ({m} rounds): {names}"),
    "none.games": ("今個星期冇玩遊戲。", "No games were played this week."),
    "gloss.title": ("點樣睇呢份報告", "How to read this report"),
    # page 4
    "p4.title": ("做得好嘅同仲學緊嘅", "Going well, and still learning"),
    "p4.top": ("今個星期做得最好", "Going well this week"),
    "p4.bottom": ("仲學緊、可以多啲練習", "Still learning — room to practise"),
    "wr.bottom.none": ("今個星期冇遊戲喺「仲學緊」名單。", "No game is on the still-learning list this week."),
    "p4.insufficient": ("數據唔夠（未排名）", "Not enough data yet (not ranked)"),
    "p4.days": ("{n} 日", "days"),
    "p4.daysOne": ("{n} 日", "day"),
    "p4.method": ("點樣排：要玩夠 {min} 局先排名（「仲學緊」仲要玩過 {days} 日）。答題遊戲睇「第一次答啱」（扣除亂估），練習遊戲睇「做得順」；"
                  "兩張名單按合資格嘅答題、練習遊戲數目分位，用保守估計，玩得少唔會被誤判。",
                  "How we rank: {min} rounds to be ranked (and {days} days to be listed as still learning). Quiz games: right first "
                  "time, lucky guesses removed; practice games: done smoothly. Places are shared by how many quiz and practice "
                  "games qualified, using cautious estimates, so a little play is never misjudged."),
    # page 5
    "p5.title": ("同上星期比較", "Compared with last week"),
    "c3.title": ("每星期局數", "Rounds per week"),
    "c4.title": ("每星期表現", "Quiz right first time · practice smooth"),
    "legend.quiz": ("答題", "Quiz"),
    "legend.practice": ("練習", "Practice"),
    "week.this": ("今個星期", "this week"),
    "week.partial": ("部分", "partial"),
    "c4.note": ("少過 {min} 局嘅星期唔畫點", "weeks with < {min} rounds of a type are not plotted"),
    "c2a.title": ("答題遊戲（按類別）：第一次答啱", "Quiz games by area: right first time"),
    "c2b.title": ("練習遊戲（按種類）：做得順", "Practice games by type: done smoothly"),
    "legend.thisWeek": ("今個星期", "This week"),
    "legend.lastWeek": ("上星期", "Last week"),
    "legend.guess": ("亂估都有嘅水平", "Lucky-guess level"),
    "c2.value": ("{p}%（{n} 局）", "{p}% ({n} rounds)"),
    "c2.last": (" · 上星期 {p}%", " · last week {p}%"),
    "c2.guess": ("亂估都有約 {c}%", "guessing ≈ {c}%"),
    "c2.notEnough": ("數據唔夠（{n} 局）", "Not enough data ({n} rounds)"),
    "c2.notEnoughOne": ("數據唔夠（{n} 局）", "Not enough data ({n} round)"),
    "c2.noQuiz": ("今個星期同上星期都冇答題遊戲。", "No quiz games this week or last week."),
    "c2.noPractice": ("今個星期同上星期都冇練習遊戲。", "No practice games this week or last week."),
    "family.lines": ("畫直線", "Lines"),
    "family.shapes": ("畫形狀", "Shapes"),
    "family.roads": ("沿路連線", "Road matching"),
    "family.tapAll": ("點數", "Tap to count"),
    "family.tapTrace": ("數完畫數字", "Count, then trace"),
    "p5.clear": ("明顯變化", "Clear changes"),
    "clear.up": ("↑「{game}」{metric}：{k0}/{n0} → {k1}/{n1}（明顯進步）", "↑ \"{game}\" {metric}: {k0}/{n0} → {k1}/{n1} (clearly up)"),
    "clear.down": ("↓「{game}」{metric}：{k0}/{n0} → {k1}/{n1}（明顯少咗）",
                   "↓ \"{game}\" {metric}: {k0}/{n0} → {k1}/{n1} (clearly down)"),
    "clear.more": ("仲有 {n} 個遊戲都有明顯變化。", "{n} more games changed clearly."),
    "clear.moreOne": ("仲有 {n} 個遊戲都有明顯變化。", "{n} more game changed clearly."),
    "metric.quiz": ("第一次答啱", "right first time"),
    "metric.practice": ("做得順", "smooth"),
    "clear.others": ("其他遊戲同上星期差唔多，或者局數太少未比較到。", "Other games are about the same, or have too few rounds to compare."),
    "clear.none": ("冇遊戲有明顯變化：同上星期差唔多，或者局數太少未比較到。",
                   "No game changed clearly: about the same as last week, or too few rounds to compare."),
    "clear.gear": ("⚙ {games}今個星期改咗設定，所以唔同上星期比。", "⚙ {games}: settings changed this week, so not compared."),
    "list.more": ("同另外 {n} 個遊戲", "and {n} more"),
    "p5.app": ("今個星期 app 有咩改動", "What changed in the app"),
    "ver.one": ("用咗 app 版本 {v}。", "App version used: {v}."),
    "ver.list": ("用過 {n} 個 app 版本：{list}。", "{n} app versions used: {list}."),
    "ver.many": ("用過 {n} 個 app 版本，由 {first} 到 {last}。", "{n} app versions used, from {first} to {last}."),
    "ver.item": ("{v}（{days}）", "{v} ({days})"),
    "set.change": ("{date}{name}：{old} → {new}{affects}。", "{date}: {name} {old} → {new}{affects}."),
    "set.new": ("{date}{name}改做 {new}{affects}。", "{date}: {name} set to {new}{affects}."),
    "set.plain": ("{date}改咗{name}{affects}。", "{date}: {name} changed{affects}."),
    "set.affects": ("（影響 {n} 個遊戲）", " (affects {n} games)"),
    "assign.on": ("{date}開咗「{game}」{stars}。", "{date}: turned on {stars} for \"{game}\"."),
    "assign.off": ("{date}熄咗「{game}」{stars}。", "{date}: turned off {stars} for \"{game}\"."),
    "gen.change": ("「{game}」題目來源：{old} → {new}。", "\"{game}\" question source: {old} → {new}."),
    "changes.more": ("仲有 {n} 項改動冇列出。", "{n} more changes not listed."),
    "changes.moreOne": ("仲有 {n} 項改動冇列出。", "{n} more change not listed."),
    "mix.both": ("遊戲組合：練習遊戲佔 {p}%（上星期 {p0}%）。", "Game mix: practice games were {p}% of rounds (last week {p0}%)."),
    "mix.now": ("遊戲組合：練習遊戲佔 {p}%。", "Game mix: practice games were {p}% of rounds."),
    "excl.list": ("冇計：{items}。", "Not counted: {items}."),
    "excl.parent_playtest": ("家長試玩 {n} 局", "parent playtest {n}"),
    "excl.parent_uat": ("測試模式 {n} 局", "test mode {n}"),
    "excl.parent_test_visa": ("測試簽證 {n} 局", "test visa {n}"),
    "excl.excluded_session": ("「唔計呢段」{n} 局", "sessions marked not to count {n}"),
    "excl.other": ("{reason} {n} 局", "{reason} {n}"),
    "excl.open": ("製作報告時仲玩緊 {n} 局", "in progress when the report was made {n}"),
    # page 6
    "p6.title": ("結論同下一步", "Conclusion and next steps"),
    "p6.family": ("屋企人可以做", "Family can do"),
    "p6.because": ("因為：{because}", "Because: {because}"),
    "p6.app": ("App 改動（建議，Carter 決定）", "App changes (backlog — Carter decides)"),
    "p6.decide": ("Carter 決定", "Carter decides"),
    "p6.why": ("因為：{because}　下星期睇：{check}", "Because: {because} Check next week: {check}."),
    "p6.questions": ("想問你哋", "Questions for you"),
}

# Weekday names (0 = Monday) and English month abbreviations.
WEEKDAY_SHORT = [("一", "Mon"), ("二", "Tue"), ("三", "Wed"), ("四", "Thu"), ("五", "Fri"), ("六", "Sat"), ("日", "Sun")]
MONTHS_EN = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

# "How to read this report" (design §3 page 3; the approved mockup's copy, first-try line corrected).
GLOSSARY = [
    ("答題遊戲", "有啱有錯嘅遊戲，例如「數車仔」。", "Quiz games: games with a right answer."),
    ("練習遊戲", "畫線、點數、沿路連線，冇錯可言。", "Practice games: tracing, tap-to-count, road matching; nothing is wrong."),
    ("第一次答啱", "第一下就揀啱，冇揀錯。", "Right first time: the first answer was right, with no wrong tap."),
    ("亂估都有", "例如兩揀一，亂撳都有一半機會啱。", "Lucky-guess level: with 2 choices, random taps are right half the time."),
    ("做得順", "例如由起點開始、冇行錯方向、出界唔多。", "Done smoothly: e.g. started at the start, right direction, rarely off the path."),
    ("數據唔夠", "今個星期玩少過 {min} 局，唔排名。", "Not enough data: fewer than {min} rounds this week; not ranked."),
    ("差唔多／明顯", "相差少過 {points} 個百分點就係「差唔多」；局數少要差更多先算明顯。",
     "About the same / clear: under {points} points is about the same; with few rounds a bigger gap is needed."),
    ("報告同「表現」頁", "報告只睇今個星期；app「表現」頁睇近期所有紀錄，所以標籤可以唔同。",
     "Report vs 表現 screen: the report looks at this week only, the screen at all recent play, so labels can differ."),
]

AREA_ORDER = ["numbers", "matching", "comparing", "pen", "letters", "other"]
FAMILY_ORDER = ["lines", "shapes", "roads", "tapAll", "tapTrace"]
EXCLUDED_ORDER = ["parent_playtest", "parent_uat", "parent_test_visa", "excluded_session"]

# ---------------------------------------------------------------- text helpers


def label(lid, **values):
    """(zh, en) of label `lid` with its {slots} filled in one pass (the W3 fill rule)."""
    zh, en = L[lid]
    parts = {k: (v[0], v[1]) if isinstance(v, tuple) else (str(v), str(v)) for k, v in values.items()}
    return w3.fill(zh, parts, 0), w3.fill(en, parts, 1)


def esc(text):
    out = []
    for ch in text:
        if ch == "&":
            out.append("&amp;")
        elif ch == "<":
            out.append("&lt;")
        elif ch == ">":
            out.append("&gt;")
        elif ch == '"':
            out.append("&quot;")
        elif ch == "'":
            out.append("&#39;")
        else:
            out.append(ch)
    return "".join(out)


def game_name(kind):
    if kind in w3.TITLES:
        return w3.TITLES[kind]
    return kind, kind


def scale(value, num, den):
    """value * num / den rounded half up, in integers (all >= 0, den > 0)."""
    return (2 * value * num + den) // (2 * den)


def t(v):
    """Tenths of a px as SVG text: 123 -> "12.3", 120 -> "12"."""
    neg = v < 0
    a = -v if neg else v
    s = str(a // 10)
    if a % 10:
        s += "." + str(a % 10)
    return ("-" if neg else "") + s


def minutes_text(minutes):
    zh, en, _, _ = w3.render_value(("min", minutes, "x"))
    return zh, en


def ms_minutes(ms):
    return w3.minutes_of_ms(ms)


def ms_of(minutes_value):
    """The W1 JSON writes ms / 60 000 with 6 decimals; the integer milliseconds come back exactly."""
    return int(round(minutes_value * 60000))


def percent_of(x, what):
    """WeeklyFormat.percent(Double): half up of x * 100; refuses a value near a tie (6 decimals vs full)."""
    v = x * 100
    if abs(v - math.floor(v) - 0.5) < 0.01:
        raise SystemExit("%s = %r sits near a percent rounding tie; change the fixture" % (what, x))
    return w3.pct_of(x) if x > 0 else 0


# Text widths in thousandths of an em (WeeklyReportHTML.emWidth): layout and budgets only.
NARROW = set("iljftr.,:;'|!I()[]{} ")
WIDE = set("mwMW%@")


def em(text):
    total = 0
    for ch in text:
        c = ord(ch)
        if ch == " ":
            total += 280
        elif 48 <= c <= 57:
            total += 560
        elif ch in WIDE:
            total += 860
        elif ch in NARROW:
            total += 320
        elif 65 <= c <= 90:
            total += 680
        elif c < 128:
            total += 540
        else:
            total += 1000
    return total


def text_width(text, size):
    """Width in tenths of a px of `text` at font size `size` (tenths of a px), rounded up."""
    return (em(text) * size + 999) // 1000


# ---------------------------------------------------------------- dates and times (Asia/Hong_Kong)


def ymd(stamp):
    return int(stamp[0:4]), int(stamp[5:7]), int(stamp[8:10])


def hkt(ms):
    return (datetime(1970, 1, 1, tzinfo=UTC) + timedelta(milliseconds=ms)).astimezone(HKT)


def clock(ms):
    return hkt(ms).strftime("%H:%M")


def stamp_of(ms):
    return hkt(ms).strftime("%Y-%m-%d")


def day_start_ms(stamp):
    y, m, d = ymd(stamp)
    return int((datetime(y, m, d, tzinfo=HKT) - datetime(1970, 1, 1, tzinfo=UTC)).total_seconds()) * 1000


def add_days(stamp, days):
    y, m, d = ymd(stamp)
    return (datetime(y, m, d) + timedelta(days=days)).strftime("%Y-%m-%d")


def date_md(stamp):
    y, m, d = ymd(stamp)
    return label("date.md", m=m, d=d, mon=MONTHS_EN[m - 1])


def date_mdw(stamp, weekday):
    y, m, d = ymd(stamp)
    zh, en = WEEKDAY_SHORT[weekday]
    return label("date.mdw", m=m, d=d, w=zh, wd=en, mon=MONTHS_EN[m - 1])


def date_range(first, last):
    y0, m0, d0 = ymd(first)
    y1, m1, d1 = ymd(last)
    if y0 != y1:
        return label("range.other", y0=y0, m0=m0, d0=d0, y1=y1, m1=m1, d1=d1, mon0=MONTHS_EN[m0 - 1],
                     mon1=MONTHS_EN[m1 - 1])
    if m0 != m1:
        return label("range.year", y=y0, m0=m0, d0=d0, m1=m1, d1=d1, mon0=MONTHS_EN[m0 - 1], mon1=MONTHS_EN[m1 - 1])
    return label("range.month", y=y0, m=m0, d0=d0, d1=d1, mon=MONTHS_EN[m0 - 1])


def day_span(stamps, first, last):
    """「10月19–21日」 / "19–21 Oct" for days first..last of the week."""
    if first == last:
        return date_md(stamps[first])
    y0, m0, d0 = ymd(stamps[first])
    y1, m1, d1 = ymd(stamps[last])
    if m0 == m1:
        return label("date.span", m=m0, d0=d0, d1=d1, mon=MONTHS_EN[m0 - 1])
    a, b = date_md(stamps[first]), date_md(stamps[last])
    return a[0] + "–" + b[0], a[1] + " – " + b[1]


def week_label(stamp, short):
    """C3 / C4 x-axis: "10/12–18", "10/26–11/1", or "10/12" when there are more than 4 weeks."""
    y0, m0, d0 = ymd(stamp)
    if short:
        return "%d/%d" % (m0, d0)
    y1, m1, d1 = ymd(add_days(stamp, 6))
    if m0 == m1:
        return "%d/%d–%d" % (m0, d0, d1)
    return "%d/%d–%d/%d" % (m0, d0, m1, d1)


# ---------------------------------------------------------------- context


class Ctx:
    pass


def load(folder):
    def read(name):
        with open(os.path.join(folder, name), encoding="utf-8") as f:
            return json.load(f)
    return read("expected-metrics.json"), read("expected-analysis.json"), read("expected-text.json")


def fingerprint(metrics):
    """FNV-1a 64 over the canonical W1 JSON of this week and last week (16 hex digits)."""
    text = w1.encode({"current": metrics["current"], "previous": metrics["previous"]}) + "\n"
    h = 14695981039346656037
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return "%016x" % h


def context(metrics, analysis, text, generated_ms, sample):
    c = Ctx()
    c.m, c.a, c.text = metrics, analysis, text
    c.cur = metrics["current"]
    c.sample = sample
    c.generated_ms = generated_ms
    c.stamps = [d["date"] for d in c.cur["days"]]
    c.cutoff = w1.parse_ts(metrics["data_until"])
    c.end = day_start_ms(add_days(c.stamps[0], 7))
    starts = [day_start_ms(s) for s in c.stamps] + [c.end]
    c.started = sum(1 for i in range(7) if starts[i] < c.cutoff)
    c.first_covered = c.started - c.cur["covered_days"]
    # The day the cut-off falls strictly inside (a week in progress), else None.
    c.cut_day = None
    for i in range(7):
        if starts[i] < c.cutoff < starts[i + 1]:
            c.cut_day = i
    # The day of the cut-off instant for 「資料截至」 (None for the whole week).
    c.until_day = None
    for i in range(7):
        if starts[i] <= c.cutoff < starts[i + 1]:
            c.until_day = i
    c.cut_clock = clock(c.cutoff)
    c.name = text["child_name"]
    c.empty = text["empty"] is not None
    c.games = analysis["games"]
    c.game_at = {(g["kind"], g["type"]): g for g in c.games}
    c.text_at = {(g["kind"], g["type"]): g for g in text["games"]}
    c.rows = c.cur["kinds"]
    c.comparison = analysis["comparison"]
    c.baseline = c.comparison["baseline"]
    c.changes = analysis["changes"]
    c.questions = text["recommendations"]["questions"]
    c.asks_video = any(q["id"] == "Q1" for q in c.questions)
    c.fp = fingerprint(metrics)[:8]
    c.day = []
    for i, d in enumerate(c.cur["days"]):
        e = {"i": i, "rounds": d["rounds"], "quiz_rounds": d["quiz_rounds"], "practice_rounds": d["practice_rounds"],
             "qa": d["quiz_answered"], "qk": d["quiz_first_try"], "pn": d["practice_smooth_defined"],
             "pk": d["practice_smooth"], "qms": ms_of(d["quiz_min"]), "pms": ms_of(d["practice_min"]),
             "vms": ms_of(d["video_min"]), "estimated": d["video_estimated"], "plays": d["plays"],
             "visa": d["visa_min"], "sessions": d["sessions"], "new": d["new_kinds"]}
        e["played"] = d["rounds"] > 0 or d["plays"] > 0
        e["future"] = i >= c.started
        e["before"] = i < c.first_covered
        c.day.append(e)
    tt = c.cur["totals"]
    c.total = {"rounds": tt["rounds"], "quiz_rounds": tt["quiz_rounds"], "practice_rounds": tt["practice_rounds"],
               "qa": tt["quiz_answered"], "qk": tt["quiz_first_try"], "pn": tt["practice_smooth_defined"],
               "pk": tt["practice_smooth"], "game_ms": ms_of(tt["quiz_min"]) + ms_of(tt["practice_min"]),
               "vms": ms_of(tt["video_min"]), "estimated": tt["video_estimated"], "visa": tt["visa_min"],
               "sessions": tt["sessions"], "chance": tt["quiz_chance_mean"]}
    assert c.total["game_ms"] == sum(e["qms"] + e["pms"] for e in c.day)
    assert c.total["vms"] == sum(e["vms"] for e in c.day)
    return c


# ---------------------------------------------------------------- SVG pieces


def svg_open(w, h):
    """Inline SVG in HTML needs no namespace attribute (and the report has no URL at all)."""
    return '<svg viewBox="0 0 %d %d" role="img">\n' % (w, h)


def stext(x, y, text, size, fill, anchor="start", bold=False):
    return '<text x="%s" y="%s" font-size="%s" fill="%s" text-anchor="%s"%s>%s</text>\n' % (
        t(x), t(y), t(size), fill, anchor, ' font-weight="700"' if bold else "", esc(text))


def line(x1, y1, x2, y2, color, width):
    return '<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="%s"/>\n' % (
        t(x1), t(y1), t(x2), t(y2), color, t(width))


def rect(x, y, w, h, fill, extra=""):
    return '<rect x="%s" y="%s" width="%s" height="%s" fill="%s"%s/>\n' % (t(x), t(y), t(w), t(h), fill, extra)


def column(x, top, w, base, fill, extra=""):
    """Column with a 4 px rounded data end (top) and a square base."""
    r = min(40, base - top, w // 2)
    return ('<path d="M%s %s V%s Q%s %s %s %s H%s Q%s %s %s %s V%s Z" fill="%s"%s/>\n' % (
        t(x), t(base), t(top + r), t(x), t(top), t(x + r), t(top), t(x + w - r), t(x + w), t(top), t(x + w),
        t(top + r), t(base), fill, extra))


def hbar(x0, yc, length, h, fill):
    """Horizontal bar: square at the baseline (left), 4 px rounded data end (right)."""
    r = min(40, length, h // 2)
    y0, y1 = yc - h // 2, yc + h // 2
    x1 = x0 + length
    return ('<path d="M%s %s H%s Q%s %s %s %s V%s Q%s %s %s %s H%s Z" fill="%s"/>\n' % (
        t(x0), t(y0), t(x1 - r), t(x1), t(y0), t(x1), t(y0 + r), t(y1 - r), t(x1), t(y1), t(x1 - r), t(y1), t(x0), fill))


def diamond(x, yc):
    """Hollow last-week marker, 10 px wide, centred on (x, yc)."""
    return '<path d="M%s %s l5 5 l-5 5 l-5 -5 Z" fill="%s" stroke="%s" stroke-width="1.5"/>\n' % (
        t(x), t(yc - 50), SURFACE, INK2)


def legend(items, x, y):
    """items: (marker, zh, en); marker is a series colour, "diamond" or "band". Text baseline at y."""
    out = []
    for marker, zh, en in items:
        if marker == "diamond":
            out.append(diamond(x + 50, y - 50))
            sw = 120
        elif marker == "band":
            out.append(rect(x, y - 90, 160, 100, BAND))
            sw = 200
        else:
            out.append(rect(x, y - 80, 90, 90, marker, ' rx="2"'))
            sw = 130
        out.append(stext(x + sw, y, zh, 95, INK, bold=True))
        zx = x + sw + text_width(zh, 95) + 40
        out.append(stext(zx, y, en, 85, INK2))
        x = zx + text_width(en, 85) + 180
    return "".join(out)


def nice_step(maximum, steps, intervals):
    for s in steps:
        if (maximum + s - 1) // s <= intervals:
            return s
    s = steps[-1]
    while (maximum + s - 1) // s > intervals:
        s *= 2
    return s


C1_STEPS = [5, 10, 15, 20, 30, 60, 90, 120, 180, 240, 300, 360]
C3_STEPS = [5, 10, 20, 25, 50, 100, 200, 250, 500, 1000]

# ---------------------------------------------------------------- C1 minutes per day (page 2)


def chart_c1(c):
    max_ms = 0
    for e in c.day:
        max_ms = max(max_ms, e["qms"] + e["pms"], e["vms"])
    if max_ms == 0:
        return None
    W, H = 688, 240
    left, right, top, base = 460, 6830, 360, 1860
    plot = base - top
    max_min = (max_ms + 59999) // 60000
    step = nice_step(max_min, C1_STEPS, 5)
    vmax = step * ((max_min + step - 1) // step)
    out = [svg_open(W, H)]
    out.append(legend([(QUIZ,) + L["legend.quizGames"], (PRACTICE,) + L["legend.practiceGames"],
                       (VIDEO,) + L["legend.videos"]], left, 140))
    tick = 0
    while tick <= vmax:
        y = base - scale(tick, plot, vmax)
        out.append(line(left, y, right, y, BASE_LINE if tick == 0 else GRID, 10 if tick == 0 else 8))
        out.append(stext(left - 60, y + 35, str(tick), 90, MUTED, "end"))
        tick += step
    out.append(stext(left - 60, top - 100, L["axis.minutes"][0] + " " + L["axis.minutes"][1], 85, MUTED, "end"))
    slot = (right - left) // 7
    full = vmax * 60000
    for e in c.day:
        i = e["i"]
        cx = left + i * slot + slot // 2
        y_, m_, d_ = ymd(c.stamps[i])
        out.append(stext(cx, base + 150, w3.DAY_ZH[i], 95, INK, "middle", True))
        out.append(stext(cx, base + 270, "%s %d" % (w3.DAY_EN[i], d_), 85, MUTED, "middle"))
        quiet = e["future"] or e["before"] or not e["played"]
        if quiet:
            lid = "day.notYet" if e["future"] else ("day.noRecords" if e["before"] else "day.noPlay")
            out.append(stext(cx, base - 80, L[lid][0] + " " + L[lid][1], 90, MUTED, "middle"))
        if c.cut_day == i:
            zh, en = label("day.upTo", time=c.cut_clock)
            out.append(stext(cx, base + 390, zh + " / " + en, 80, MUTED, "middle"))
        if quiet:
            continue
        hq = scale(e["qms"], plot, full)
        hp = scale(e["pms"], plot, full)
        hv = scale(e["vms"], plot, full)
        gx = cx - 230
        if hq > 0:
            if hp > 0:
                out.append(rect(gx, base - hq, 200, hq, QUIZ))
            else:
                out.append(column(gx, base - hq, 200, base, QUIZ))
        if hp > 0:
            bottom = base - hq - (20 if hq > 0 else 0)
            out.append(column(gx, bottom - hp, 200, bottom, PRACTICE))
        if hv > 0:
            out.append(column(cx + 30, base - hv, 200, base, VIDEO))
    out.append("</svg>\n")
    return "".join(out)


# ---------------------------------------------------------------- C2a / C2b by area and family (page 5)


def chart_hbars(rows, color, guess):
    """rows: dicts zh, en, k1, n1, k0, n0, chance (a whole percent, or None)."""
    W = 688
    n = len(rows)
    H = 44 + 24 * n
    x0, track = 1860, 3300
    top, row_h = 280, 240
    out = [svg_open(W, H)]
    items = [(color,) + L["legend.thisWeek"], ("diamond",) + L["legend.lastWeek"]]
    if guess:
        items.append(("band",) + L["legend.guess"])
    out.append(legend(items, 0, 130))
    gy0, gy1 = top - 40, top + row_h * n - 40
    for tick in (0, 25, 50, 75, 100):
        x = x0 + scale(tick, track, 100)
        out.append(line(x, gy0, x, gy1, BASE_LINE if tick == 0 else GRID, 10 if tick == 0 else 8))
        out.append(stext(x, gy1 + 120, "%d%%" % tick, 85, MUTED, "middle"))
    for i, r in enumerate(rows):
        yc = top + i * row_h + 80
        out.append(stext(0, yc - 10, r["zh"], 100, INK, bold=True))
        out.append(stext(0, yc + 90, r["en"], 85, MUTED))
        if r["n1"] < MIN_ROUNDS:
            zh, en = label("c2.notEnoughOne" if r["n1"] == 1 else "c2.notEnough", n=r["n1"])
            out.append(stext(x0 + 40, yc + 40, zh + " " + en, 90, MUTED))
            continue
        chance = r["chance"] if guess else None
        if chance:
            out.append(rect(x0, yc - 90, scale(chance, track, 100), 180, BAND))
        length = scale(r["k1"], track, r["n1"])
        if length > 0:
            out.append(hbar(x0, yc, length, 120, color))
        reach = length
        last = r["n0"] >= MIN_ROUNDS
        if last:
            px = x0 + scale(r["k0"], track, r["n0"])
            out.append(diamond(px, yc))
            reach = max(reach, px - x0 + 50)
        lx = x0 + reach + 100
        value = label("c2.value", p=w3.pct(r["k1"], r["n1"]), n=r["n1"])[0]
        if last:
            value += label("c2.last", p=w3.pct(r["k0"], r["n0"]))[0]
        out.append(stext(lx, yc + 40, value, 95, INK))
        if chance is not None:
            zh, en = label("c2.guess", c=chance)
            out.append(stext(lx, yc + 120, zh + " · " + en, 80, MUTED))
    out.append("</svg>\n")
    return "".join(out)


def area_rows(c):
    rows = []
    groups = {g["area"]: g for g in c.cur["areas"]}
    comp = {a["area"]: a for a in c.comparison["areas"]}
    for area in AREA_ORDER:
        if area == "pen":
            continue
        cmp_ = comp[area]
        if cmp_["n1"] == 0 and cmp_["n0"] == 0:
            continue
        zh, en = w3.AREA_NAMES[area]
        mean = groups[area]["quiz_chance_mean"]
        chance = None if mean is None else percent_of(mean, "chance of " + area)
        rows.append({"zh": zh, "en": en, "k1": cmp_["k1"], "n1": cmp_["n1"], "k0": cmp_["k0"], "n0": cmp_["n0"],
                     "chance": chance})
    return rows


def family_rows(c):
    rows = []
    comp = {f["family"]: f for f in c.comparison["families"]}
    for family in FAMILY_ORDER:
        cmp_ = comp[family]
        if cmp_["n1"] == 0 and cmp_["n0"] == 0:
            continue
        zh, en = L["family." + family]
        rows.append({"zh": zh, "en": en, "k1": cmp_["k1"], "n1": cmp_["n1"], "k0": cmp_["k0"], "n0": cmp_["n0"],
                     "chance": None})
    return rows


# ---------------------------------------------------------------- C3 / C4 per week (page 5)


def week_x(left, right, i, count):
    return left + scale(2 * i + 1, right - left, 2 * count)


def week_axis(weeks, left, right, base):
    """Week labels; the current week (bold) and partial weeks get a line in each language below."""
    out = []
    short = len(weeks) > 4
    for i, wk in enumerate(weeks):
        cx = week_x(left, right, i, len(weeks))
        out.append(stext(cx, base + 140, week_label(wk["week_start"], short), 90, INK, "middle", wk["current"]))
        if wk["current"]:
            lid = "week.this"
        elif wk["partial"]:
            lid = "week.partial"
        else:
            continue
        out.append(stext(cx, base + 250, L[lid][0], 80, MUTED, "middle"))
        out.append(stext(cx, base + 350, L[lid][1], 80, MUTED, "middle"))
    return out


def chart_c3(weeks):
    W, H = 330, 182
    left, right, top, base = 340, 3220, 280, 1300
    plot = base - top
    totals = [wk["quiz_rounds"] + wk["practice_rounds"] for wk in weeks]
    highest = max(totals)
    step = nice_step(highest, C3_STEPS, 4)
    vmax = step * max(1, (highest + step - 1) // step)
    out = [svg_open(W, H)]
    out.append(legend([(QUIZ,) + L["legend.quiz"], (PRACTICE,) + L["legend.practice"]], left, 130))
    tick = 0
    while tick <= vmax:
        y = base - scale(tick, plot, vmax)
        out.append(line(left, y, right, y, BASE_LINE if tick == 0 else GRID, 10 if tick == 0 else 8))
        out.append(stext(left - 50, y + 35, str(tick), 85, MUTED, "end"))
        tick += step
    for i, wk in enumerate(weeks):
        cx = week_x(left, right, i, len(weeks))
        bx = cx - 120
        hq = scale(wk["quiz_rounds"], plot, vmax)
        hp = scale(wk["practice_rounds"], plot, vmax)
        if wk["partial"]:
            fill_q, extra_q = SURFACE, ' stroke="%s" stroke-width="1.5"' % QUIZ
            fill_p, extra_p = SURFACE, ' stroke="%s" stroke-width="1.5"' % PRACTICE
        else:
            fill_q, extra_q, fill_p, extra_p = QUIZ, "", PRACTICE, ""
        if hq > 0:
            if hp > 0:
                out.append(rect(bx, base - hq, 240, hq, fill_q, extra_q))
            else:
                out.append(column(bx, base - hq, 240, base, fill_q, extra_q))
        top_y = base - hq
        if hp > 0:
            bottom = base - hq - (20 if hq > 0 else 0)
            out.append(column(bx, bottom - hp, 240, bottom, fill_p, extra_p))
            top_y = bottom - hp
        out.append(stext(cx, top_y - 50, str(totals[i]), 95, INK, "middle", True))
    out += week_axis(weeks, left, right, base)
    out.append("</svg>\n")
    return "".join(out)


def chart_c4(weeks):
    W, H = 330, 182
    left, right, top, base = 340, 2900, 280, 1300
    plot = base - top
    out = [svg_open(W, H)]
    out.append(legend([(QUIZ,) + L["legend.quiz"], (PRACTICE,) + L["legend.practice"]], left, 130))
    for tick in (0, 25, 50, 75, 100):
        y = base - scale(tick, plot, 100)
        out.append(line(left, y, right, y, BASE_LINE if tick == 0 else GRID, 10 if tick == 0 else 8))
        out.append(stext(left - 50, y + 35, "%d%%" % tick, 85, MUTED, "end"))
    ends = []
    for color, nk, kk, lid in ((QUIZ, "quiz_answered", "quiz_first_try", "legend.quiz"),
                               (PRACTICE, "practice_smooth_defined", "practice_smooth", "legend.practice")):
        pts = []
        for i, wk in enumerate(weeks):
            if wk[nk] >= MIN_ROUNDS:
                pts.append((i, week_x(left, right, i, len(weeks)), base - scale(wk[kk], plot, wk[nk]),
                            w3.pct(wk[kk], wk[nk]), wk["partial"]))
        start = 0
        while start < len(pts):
            end = start
            while end + 1 < len(pts) and pts[end + 1][0] == pts[end][0] + 1:
                end += 1
            if end > start:
                coords = " ".join("%s,%s" % (t(p[1]), t(p[2])) for p in pts[start:end + 1])
                out.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="2" stroke-linejoin="round" '
                           'stroke-linecap="round"/>\n' % (coords, color))
            start = end + 1
        for p in pts:
            out.append('<circle cx="%s" cy="%s" r="6" fill="%s"/>\n' % (t(p[1]), t(p[2]), SURFACE))
            if p[4]:
                out.append('<circle cx="%s" cy="%s" r="4" fill="%s" stroke="%s" stroke-width="2"/>\n' % (
                    t(p[1]), t(p[2]), SURFACE, color))
            else:
                out.append('<circle cx="%s" cy="%s" r="4" fill="%s"/>\n' % (t(p[1]), t(p[2]), color))
        if pts:
            ends.append((pts[-1], L[lid][0]))
    # End labels: the higher end point is labelled above, the lower one below.
    if len(ends) == 2:
        quiz_below = ends[1][0][2] < ends[0][0][2]
        offsets = [120, -40] if quiz_below else [-40, 120]
    else:
        offsets = [-40]
    for (p, name), dy in zip(ends, offsets):
        out.append(stext(p[1] + 90, p[2] + dy, "%s %d%%" % (name, p[3]), 90, INK, "start", True))
    out += week_axis(weeks, left, right, base)
    zh, en = label("c4.note", min=MIN_ROUNDS)
    out.append(stext(left, 1790, zh + " · " + en, 76, MUTED))
    out.append("</svg>\n")
    return "".join(out)


# ---------------------------------------------------------------- layout estimate (WeeklyReportLayout)

# Content box of a page: 1123 - 72 - 57 = 994 px. Layout variants are chosen while the estimate stays
# within 960 px (a 34 px margin for line-break and font differences). Tenths of a px throughout.
CONTENT_BUDGET = 9600
SLACK = 92  # percent of a box's width a wrapped line is assumed to fill


def lines(text, font, width):
    """Wrapped lines of `text` at font `font` (tenths px) in a box `width` px wide (0 for empty text)."""
    if text == "":
        return 0
    usable = width * SLACK // 10
    return max(1, (text_width(text, font) + usable - 1) // usable)


def badges_width(g):
    """Badges are inline blocks: text at 8 px plus 12.3 px of padding, border and margin each."""
    total = 0
    for text in badge_texts(g):
        total += text_width(text, 80) + 123
    return total


def lines_after(prefix_width, text, font, width):
    """Lines of `text` set after an inline prefix `prefix_width` tenths px wide."""
    usable = width * SLACK // 10
    return max(1, (prefix_width + text_width(text, font) + usable - 1) // usable)


# Style metrics: (font size, line height) in tenths of a px, mirrored in the CSS below.
S_ROW_NM, S_ROW_NM_EN = (120, 150), (92, 120)
S_FACT, S_FACT_EN, S_FACT_STARS = (112, 145), (90, 120), (88, 115)
S_CM, S_CM_EN = (109, 144), (89, 116)
S_STATUS, S_STATUS_EN = (115, 158), (93, 121)
S_ALSO, S_ALSO_EN = (104, 145), (90, 120)
S_ITEM_NM, S_ITEM_NM_EN, S_ITEM_CM, S_ITEM_CM_EN = (107, 134), (88, 134), (99, 129), (85, 110)
S_METHOD, S_METHOD_EN = (99, 138), (88, 114)
D_ROW_NM, D_ROW_NM_EN = (110, 135), (86, 110)
D_FACT, D_FACT_EN, D_FACT_STARS = (102, 130), (84, 110), (82, 105)
D_CM, D_CM_EN = (100, 130), (82, 106)
D_ALSO, D_ALSO_EN = (96, 130), (84, 110)
S_T, S_T_EN, S_WHY, S_WHY_EN, S_PARAM = (120, 160), (96, 125), (100, 135), (90, 120), (93, 125)
D_T, D_T_EN, D_WHY, D_WHY_EN, D_PARAM = (110, 145), (90, 115), (94, 125), (84, 110), (86, 115)
S_GLOSS, S_GLOSS_EN, D_GLOSS, D_GLOSS_EN = (100, 135), (88, 115), (94, 125), (82, 105)
S_PRIVACY, S_PRIVACY_EN = (96, 130), (88, 115)
H2_BLOCK, H3_BLOCK, RANK_HEAD, SEC_GAP = 290, 230, 270, 110


def bi_lines(zh, en, zs, es, width):
    return lines(zh, zs[0], width) * zs[1] + lines(en, es[0], width) * es[1]


def est_sentences(sentences, zs, es, width):
    return sum(bi_lines(s["zh"], s["en"], zs, es, width) for s in sentences)


def est_rank_row(c, g, gt, dense):
    nm, nm_en = (D_ROW_NM, D_ROW_NM_EN) if dense else (S_ROW_NM, S_ROW_NM_EN)
    fs, fs_en, fs_st = (D_FACT, D_FACT_EN, D_FACT_STARS) if dense else (S_FACT, S_FACT_EN, S_FACT_STARS)
    cs, cs_en = (D_CM, D_CM_EN) if dense else (S_CM, S_CM_EN)
    zh, en = game_name(g["kind"])
    name_h = lines_after(badges_width(g), zh, nm[0], 196) * nm[1] + lines(en, nm_en[0], 196) * nm_en[1]
    fact_h = lines(fact_tail(g), fs_st[0], 155) * fs_st[1]
    if gt["fact"] is not None:
        fact_h += bi_lines(gt["fact"]["zh"], gt["fact"]["en"], fs, fs_en, 155)
    cm_h = est_sentences(gt["short"], cs, cs_en, 315)
    return max(name_h, fact_h, cm_h) + (40 if dense else 80) + 7


def est_also(s, dense):
    if s is None:
        return 0
    zs, es = (D_ALSO, D_ALSO_EN) if dense else (S_ALSO, S_ALSO_EN)
    return 60 + bi_lines(s["zh"], s["en"], zs, es, 688)


def est_insufficient(c, entries, mode):
    """mode: "rows" (name | comment) or "cols" (two columns of name over comment)."""
    if not entries:
        return 0
    h = RANK_HEAD
    if mode == "rows":
        for entry in entries:
            g = c.game_at[(entry["kind"], entry["type"])]
            gt = c.text_at[(entry["kind"], entry["type"])]
            zh, en = game_name(g["kind"])
            name_h = lines_after(badges_width(g), zh, S_ROW_NM[0], 196) * S_ROW_NM[1] + \
                lines(en, S_ROW_NM_EN[0], 196) * S_ROW_NM_EN[1]
            h += max(name_h, est_sentences(gt["short"], S_CM, S_CM_EN, 481)) + 87
        return h + 100
    heights = []
    for entry in entries:
        g = c.game_at[(entry["kind"], entry["type"])]
        gt = c.text_at[(entry["kind"], entry["type"])]
        zh, en = game_name(g["kind"])
        name_w = badges_width(g) + text_width(zh, S_ITEM_NM[0]) + text_width(" " + en, S_ITEM_NM_EN[0])
        usable = 334 * SLACK // 10
        name_h = max(1, (name_w + usable - 1) // usable) * S_ITEM_NM[1]
        heights.append(name_h + est_sentences(gt["short"], S_ITEM_CM, S_ITEM_CM_EN, 334) + 67)
    for i in range(0, len(heights), 2):
        h += max(heights[i:i + 2])
    return h + 100


def est_method():
    zh, en = label("p4.method", min=MIN_ROUNDS, days=STILL_LEARNING_DAYS)
    return 80 + 140 + lines(zh, S_METHOD[0], 664) * S_METHOD[1] + lines(en, S_METHOD_EN[0], 664) * S_METHOD_EN[1] + 40


def est_page4(c, dense, mode, method):
    ranking, rt = c.a["ranking"], c.text["ranking"]
    h = H2_BLOCK
    if not c.rows or not ranking["ranked"]:
        status = rt["status"] if c.rows else {"zh": L["none.games"][0], "en": L["none.games"][1]}
        h += 80 + bi_lines(status["zh"], status["en"], S_STATUS, S_STATUS_EN, 688)
    else:
        for key, also in (("top", rt["also_well"]), ("still_learning", rt["also_learning"])):
            h += RANK_HEAD
            if key == "top" and rt["status"] is not None:
                h += 80 + bi_lines(rt["status"]["zh"], rt["status"]["en"], S_STATUS, S_STATUS_EN, 688)
            if key == "still_learning" and not (ranking[key]["quiz"] or ranking[key]["practice"]):
                h += 80 + bi_lines(L["wr.bottom.none"][0], L["wr.bottom.none"][1], S_STATUS, S_STATUS_EN, 688)
            for type_ in ("quiz", "practice"):
                for kind in ranking[key][type_]:
                    h += est_rank_row(c, c.game_at[(kind, type_)], c.text_at[(kind, type_)], dense)
            h += est_also(also, dense) + (60 if dense else 100)
    h += est_insufficient(c, ranking["insufficient"], mode)
    if method and c.rows:
        h += est_method()
    return h


def page4_variant(c):
    """(dense, insufficient mode, method shown): the first variant whose estimate fits."""
    entries = c.a["ranking"]["insufficient"]
    first_mode = "rows" if len(entries) <= INSUFFICIENT_ROWS_MAX else "cols"
    variants = [(False, first_mode, True), (False, "cols", True), (True, "cols", True), (True, "cols", False)]
    for v in variants:
        if est_page4(c, v[0], v[1], v[2]) <= CONTENT_BUDGET:
            return v
    return variants[-1]


def est_rec(text_zh, text_en, why_zh, why_en, params, dense, extra_zh=0):
    t_, t_en, w_, w_en, p_ = (D_T, D_T_EN, D_WHY, D_WHY_EN, D_PARAM) if dense else (S_T, S_T_EN, S_WHY, S_WHY_EN, S_PARAM)
    h = (60 if dense else 100) + 7
    h += lines_after(extra_zh, text_zh, t_[0], 688) * t_[1] + lines(text_en, t_en[0], 688) * t_en[1]
    if why_zh:
        h += 20 + lines(why_zh, w_[0], 688) * w_[1] + lines(why_en, w_en[0], 688) * w_en[1]
    for p in params:
        h += 20 + lines(p, p_[0], 688) * p_[1]
    return h


def glossary_entries():
    out = []
    for term, zh, en in GLOSSARY:
        zh_text = w3.fill(zh, {"min": (str(MIN_ROUNDS),) * 2, "points": (str(SAME_POINTS),) * 2}, 0)
        en_text = w3.fill(en, {"min": (str(MIN_ROUNDS),) * 2, "points": (str(SAME_POINTS),) * 2}, 1)
        out.append((term, zh_text, en_text))
    return out


def est_glossary(dense):
    gs, gs_en = (D_GLOSS, D_GLOSS_EN) if dense else (S_GLOSS, S_GLOSS_EN)
    h = (80 + 60 if dense else 100 + 70) + 11 + H3_BLOCK + 40
    entries = glossary_entries()
    for i in range(0, len(entries), 2):
        row = 0
        for term, zh, en in entries[i:i + 2]:
            row = max(row, lines(term + "：" + zh, gs[0], 332) * gs[1] + lines(en, gs_en[0], 332) * gs_en[1])
        h += row + (20 if dense else 30)
    return h


def est_page6(c, dense, glossary_here):
    rec = c.text["recommendations"]
    h = H2_BLOCK + H3_BLOCK
    for item in rec["family"]:
        zh, en = label("p6.because", because=(item["because"]["zh"], item["because"]["en"]))
        h += est_rec(item["text"]["zh"], item["text"]["en"], zh, en, [], dense)
    for s in (rec["praise"], rec["family_none"]):
        if s is not None:
            h += est_rec(s["zh"], s["en"], "", "", [], dense)
    h += (70 if dense else SEC_GAP) + H3_BLOCK
    tag = text_width(L["p6.decide"][0], 85) + 130
    for item in rec["app"]:
        zh, en = label("p6.why", because=(item["because"]["zh"], item["because"]["en"]),
                       check=(item["check"]["zh"], item["check"]["en"]))
        h += est_rec(item["text"]["zh"], item["text"]["en"], zh, en, [s["en"] for s in item["settings"]], dense, tag)
    if rec["app_none"] is not None:
        h += est_rec(rec["app_none"]["zh"], rec["app_none"]["en"], "", "", [], dense)
    if rec["questions"]:
        h += (70 if dense else SEC_GAP) + H3_BLOCK
        for q in rec["questions"]:
            note = q["note"]
            h += est_rec(q["question"]["zh"], q["question"]["en"], note["zh"] if note else "",
                         note["en"] if note else "", [], dense)
    if not glossary_here:
        h += est_glossary(dense)
    zh, en = L["wr.privacy"]
    h += 110 + 8 + 80 + lines(zh, S_PRIVACY[0], 688) * S_PRIVACY[1] + lines(en, S_PRIVACY_EN[0], 688) * S_PRIVACY_EN[1]
    return h


def page6_dense(c, glossary_here):
    return est_page6(c, False, glossary_here) > CONTENT_BUDGET


# ---------------------------------------------------------------- HTML pieces


def pair(zh, en, cls="pair"):
    return '<p class="%s"><span class="zh">%s</span><span class="en">%s</span></p>\n' % (cls, esc(zh), esc(en))


def sentence_pair(s):
    return pair(s["zh"], s["en"])


def bi(zh, en):
    """ZH text then the EN line (inside a block element)."""
    return '%s<span class="en">%s</span>' % (esc(zh), esc(en))


def heading(tag, lid):
    zh, en = L[lid]
    return '<%s>%s<span class="en">%s</span></%s>\n' % (tag, esc(zh), esc(en), tag)


def runhead(c):
    week = date_range(c.stamps[0], c.stamps[6])[0]
    out = '<div class="runhead"><div class="rh-left"><b>%s</b> %s · %s · %s %s</div>' % (
        esc(L["head.title"][0]), esc(L["head.title"][1]), esc(week), esc(L["head.family"][0]), esc(L["head.family"][1]))
    if c.sample:
        out += '<div class="rh-tag">%s %s</div>' % (esc(L["sample"][0]), esc(L["sample"][1]))
    return out + "</div>\n"


def stamp_clock(ms):
    return "%s %s HKT" % (stamp_of(ms), clock(ms))


def app_versions(c):
    versions = c.changes["versions"]
    if not versions:
        return "—"
    if len(versions) == 1:
        return "v" + versions[0]["app"]
    return "v" + versions[0]["app"] + "–v" + versions[-1]["app"]


def runfoot(c, n, total):
    prov = label("foot.provenance", report=REPORT_VERSION, builder=c.m["builder"], until=stamp_clock(c.cutoff),
                 made=stamp_clock(c.generated_ms), apps=app_versions(c), fp=c.fp)[0]
    counted = label("foot.counted", name=c.name)
    second = counted[0] + " · " + counted[1]
    if c.sample:
        second += " · " + L["sample"][0] + " " + L["sample"][1]
    page = label("foot.page", n=n, total=total)
    return '<div class="runfoot"><div class="prov">%s<br>%s</div><div class="pageno">%s · %s</div></div>\n' % (
        esc(prov), esc(second), esc(page[0]), esc(page[1]))


def badge_texts(g):
    out = [L["badge.quiz"][0] if g["type"] == "quiz" else L["badge.practice"][0]]
    if g["new"]:
        out.append(L["badge.new"][0] + " " + L["badge.new"][1])
    if g["type"] == "quiz" and g["fixed_question"]:
        out.append(L["badge.fixed"][0])
    if g["settings"]:
        out.append(L["badge.settings"][0])
    return out


def badges(g):
    classes = ["q" if g["type"] == "quiz" else "p"]
    if g["new"]:
        classes.append("new")
    if g["type"] == "quiz" and g["fixed_question"]:
        classes.append("fixed")
    if g["settings"]:
        classes.append("cfg")
    return "".join('<span class="badge %s">%s</span>' % (cls, esc(text)) for cls, text in zip(classes, badge_texts(g)))


def change_words(change, kind):
    """kind: "rate", "count" or "minutes"."""
    if change is None:
        return None
    if kind == "rate":
        return L["change." + change]
    if change == "up":
        return L["change.more"]
    return L["change.less"] if kind == "minutes" else L["change.fewer"]


def join_parts(parts):
    return " · ".join(p[0] for p in parts), " · ".join(p[1] for p in parts)


def minutes_value(minutes, approx):
    h, m = divmod(minutes, 60)
    out = ""
    if approx:
        out += "<small>%s</small>" % esc(L["unit.approx"][0])
    if h:
        out += "%d<small>%s</small>%d<small>%s</small>" % (h, esc(L["unit.hours"][0]), m, esc(L["unit.minutes"][0]))
    else:
        out += "%d<small>%s</small>" % (m, esc(L["unit.minutesOnly"][0]))
    return out


def tile(swatch, lid, value, parts, na=False):
    zh, en = L[lid]
    sw = '<span class="sw %s"></span>' % swatch if swatch else ""
    out = '<div class="tile"><div class="lbl">%s%s</div>' % (sw, bi(zh, en))
    out += '<div class="val%s">%s</div>' % (" na" if na else "", value)
    czh, cen = join_parts(parts)
    return out + '<div class="cmp">%s</div></div>\n' % bi(czh, cen)


def rate_tile(c, swatch, lid, comparison, no_last_lid, guess):
    k1, n1, k0, n0 = comparison["k1"], comparison["n1"], comparison["k0"], comparison["n0"]
    if n1 < MIN_ROUNDS:
        return tile(swatch, lid, "—", [label("cmp.notEnoughOne" if n1 == 1 else "cmp.notEnough", n=n1)], na=True)
    parts = []
    if not c.baseline:
        if n0 > 0:
            parts.append(label("cmp.rate", p=w3.pct(k0, n0)))
            words = change_words(comparison["change"], "rate")
            if words:
                parts.append(words)
        else:
            parts.append(L[no_last_lid])
    if guess is not None:
        parts.append(label("cmp.guess", c=percent_of(guess, "total chance")))
    return tile(swatch, lid, "%d%%" % w3.pct(k1, n1), parts)


def count_tile(c, lid, value, comparison, last_lid, kind):
    parts = []
    if not c.baseline:
        if kind == "minutes":
            prev = minutes_text(ms_minutes(ms_of(comparison["previous"])))
            parts.append(label(last_lid, t=prev))
        else:
            one = "One" if comparison["previous"] == 1 else ""  # "Last week: 1 day"
            parts.append(label(last_lid + one, n=comparison["previous"]))
        words = change_words(comparison["change"], kind)
        if words:
            parts.append(words)
    return parts


def page1(c):
    out = []
    cover_zh, cover_en = date_range(c.stamps[0], c.stamps[6])
    if c.until_day is not None:
        dzh, den = date_md(c.stamps[c.until_day])
        until = label("p1.until", date=(dzh, w3.DAY_EN[c.until_day] + " " + den), time=c.cut_clock)
    else:
        until = L["p1.whole"]
    meta_zh = cover_zh + " · " + until[0] + " · " + c.name
    meta_en = cover_en + " · " + until[1] + " · " + c.name
    out.append('<div class="cover"><h1>%s<span class="en">%s</span></h1><div class="meta">%s</div></div>\n' % (
        esc(L["p1.title"][0]), esc(L["p1.title"][1]), bi(meta_zh, meta_en)))
    text = c.text
    out.append('<div class="highlights">\n' + heading("h3", "p1.highlights"))
    if c.empty:
        out.append(sentence_pair(text["empty"]))
    for s in text["highlights"]:
        out.append(sentence_pair(s))
    if text["videos"] is not None:
        out.append(sentence_pair(text["videos"]))
    out.append("</div>\n")
    if not c.empty:
        comp = c.comparison
        days = comp["days_played"]
        out.append('<div class="tiles">\n')
        value = "%d<small>%s</small>" % (days["current"], esc(label("unit.ofDays", n=c.cur["covered_days"])[0]))
        out.append(tile("", "tile.days", value, count_tile(c, "tile.days", None, days, "cmp.days", "count")))
        rounds = comp["rounds"]
        out.append(tile("", "tile.rounds", str(rounds["current"]),
                        count_tile(c, "tile.rounds", None, rounds, "cmp.rounds", "count")))
        out.append(rate_tile(c, "q", "tile.quiz", comp["quiz"], "cmp.noQuiz", c.total["chance"]))
        out.append(rate_tile(c, "p", "tile.practice", comp["practice"], "cmp.noPractice", None))
        parts = count_tile(c, "tile.game", None, comp["game_min"], "cmp.time", "minutes")
        if c.total["rounds"] > 0:
            x = w3.tenths(c.total["game_ms"], c.total["rounds"] * 60000)
            parts.append(label("cmp.perRound", x="%d.%d" % (x // 10, x % 10)))
        out.append(tile("", "tile.game", minutes_value(ms_minutes(c.total["game_ms"]), False), parts))
        parts = count_tile(c, "tile.video", None, comp["video_min"], "cmp.time", "minutes")
        parts.append(label("cmp.visa", t=minutes_text(c.total["visa"])))
        out.append(tile("v", "tile.video", minutes_value(ms_minutes(c.total["vms"]), c.total["estimated"]), parts))
        out.append("</div>\n")
        prev_days = comp["previous_covered_days"]
        if c.baseline:
            out.append(pair(*L["wr.baseline"], cls="pair tilenote"))
        elif prev_days < 4:
            out.append(pair(*label("wr.partialPrevOne" if prev_days == 1 else "wr.partialPrev", n=prev_days),
                            cls="pair tilenote"))
        wins = text["wins"]
        rec = text["recommendations"]
        next_items = [item["text"] for item in rec["family"][:2]]
        if not next_items and rec["family_none"] is not None:
            next_items.append(rec["family_none"])
        out.append('<div class="%s">\n' % ("twocol" if wins else "onecol"))
        if wins:
            out.append('<div class="box wins">' + heading("h3", "p1.wins") + '<ul class="items">\n')
            for s in wins:
                out.append("<li>%s</li>\n" % bi(s["zh"], s["en"]))
            out.append("</ul></div>\n")
        out.append('<div class="box next">' + heading("h3", "p1.next") + '<ul class="items dots">\n')
        for s in next_items:
            out.append("<li>%s</li>\n" % bi(s["zh"], s["en"]))
        out.append("</ul></div>\n</div>\n")
    note_zh, note_en = label("p1.counted", name=c.name)
    excluded = c.cur["excluded_rounds"]["total"]
    if excluded > 0:
        zh, en = label("p1.excludedOne" if excluded == 1 else "p1.excluded", n=excluded)
        note_zh += zh
        note_en += " " + en
    if not c.empty:
        updates = max(0, len(c.changes["versions"]) - 1)
        settings = len(c.changes["config"]) + len(c.changes["assignment"])
        ch = None
        if updates > 0 and settings > 0:
            ch = label("p1.changes", u=updates, s=settings, page=CHANGES_PAGE)
        elif updates > 0:
            ch = label("p1.updates", u=updates, page=CHANGES_PAGE)
        elif settings > 0:
            ch = label("p1.settings", s=settings, page=CHANGES_PAGE)
        if ch is not None:
            note_zh += ch[0]
            note_en += " " + ch[1]
    out.append('<p class="note">%s</p>\n' % bi(note_zh, note_en))
    if c.empty:
        out.append('<p class="privacy">%s</p>\n' % bi(*L["wr.privacy"]))
    return "".join(out)


def day_note(c, e):
    zh_parts, en_parts = [], []
    new = e["new"]
    for kind in new[:NEW_NAMES_MAX]:
        zh, en = label("note.newGame", game=game_name(kind))
        zh_parts.append(zh)
        en_parts.append(en)
    if len(new) > NEW_NAMES_MAX:
        zh, en = label("note.moreNew", n=len(new) - NEW_NAMES_MAX)
        zh_parts.append(zh)
        en_parts.append(en)
    if c.cut_day == e["i"]:
        zh, en = label("day.upTo", time=c.cut_clock)
        zh_parts.append(zh)
        en_parts.append(en)
    return "；".join(zh_parts), "; ".join(en_parts)


def ratio_cell(k, n):
    if n == 0:
        return '<td class="muted">—</td>'
    return '<td>%d/%d<span class="en">%d%%</span></td>' % (k, n, w3.pct(k, n))


def note_cell(zh, en, cls):
    if zh == "":
        return '<td class="%s"></td>' % cls
    return '<td class="%s">%s</td>' % (cls, bi(zh, en))


def video_cell(ms, approx):
    minutes = ms_minutes(ms)
    if approx:
        return "<td>%s%d</td>" % (esc(L["unit.approx"][0]), minutes)
    return "<td>%d</td>" % minutes


def page2(c):
    out = [heading("h2", "p2.title")]
    out.append('<div class="charttitle">%s</div>\n' % bi(*L["p2.chart"]))
    svg = chart_c1(c)
    if svg is None:
        out.append('<p class="chartnote">%s</p>\n' % bi(*L["c1.empty"]))
    else:
        out.append('<div class="chart">\n' + svg + "</div>\n")
    out.append('<table class="daily">\n<colgroup><col style="width:96px"><col style="width:52px"><col style="width:64px">'
               '<col style="width:76px"><col style="width:68px"><col style="width:54px"><col style="width:54px">'
               '<col style="width:62px"><col></colgroup>\n<tr>')
    for lid in ("th.date", "th.sessions", "th.rounds", "th.quiz", "th.practice", "th.games", "th.videos", "th.visa",
                "th.note"):
        cls = ' class="l"' if lid in ("th.date", "th.note") else ""
        out.append("<th%s>%s</th>" % (cls, bi(*L[lid])))
    out.append("</tr>\n")
    for e in c.day:
        dzh, den = date_mdw(c.stamps[e["i"]], e["i"])
        first = '<td class="l">%s</td>' % bi(dzh, den)
        nzh, nen = day_note(c, e)
        if e["future"] or e["before"] or not e["played"]:
            lid = "day.notYet" if e["future"] else ("day.noRecords" if e["before"] else "day.noPlay")
            out.append('<tr>%s<td class="muted l" colspan="7">%s · %s</td>%s</tr>\n' % (
                first, esc(L[lid][0]), esc(L[lid][1]), note_cell(nzh, nen, "l note-cell")))
            continue
        out.append('<tr>%s<td>%d</td><td>%d<span class="en">%d / %d</span></td>%s%s<td>%d</td>%s<td>%d</td>%s</tr>\n' % (
            first, e["sessions"], e["rounds"], e["quiz_rounds"], e["practice_rounds"], ratio_cell(e["qk"], e["qa"]),
            ratio_cell(e["pk"], e["pn"]), ms_minutes(e["qms"] + e["pms"]), video_cell(e["vms"], e["estimated"]),
            e["visa"], note_cell(nzh, nen, "l note-cell")))
    tt = c.total
    out.append('<tr class="total"><td class="l">%s</td><td>%d</td><td>%d<span class="en">%d / %d</span></td>%s%s'
               '<td>%d</td>%s<td>%d</td><td class="l"></td></tr>\n</table>\n' % (
                   bi(*L["row.total"]), tt["sessions"], tt["rounds"], tt["quiz_rounds"], tt["practice_rounds"],
                   ratio_cell(tt["qk"], tt["qa"]), ratio_cell(tt["pk"], tt["pn"]), ms_minutes(tt["game_ms"]),
                   video_cell(tt["vms"], tt["estimated"]), tt["visa"]))
    stars = c.cur["stars"]
    out.append('<p class="note">%s</p>\n' % bi(*label("p2.tickets", a=stars[0], b=stars[1], c=stars[2])))
    zh, en = label("p2.time", cap=GAME_MINUTES_CAP)
    if c.cut_day is not None:
        czh, cen = label("p2.cutoff", day=(w3.DAY_ZH[c.cut_day], w3.DAY_EN[c.cut_day]), time=c.cut_clock)
        zh += czh
        en += " " + cen
    if tt["estimated"]:
        zh += L["p2.approx"][0]
        en += " " + L["p2.approx"][1]
    if c.asks_video:
        pzh, pen = label("p2.pointer", page=w3.QUESTIONS_PAGE)
        zh += pzh
        en += " " + pen
    out.append('<p class="note">%s</p>\n' % bi(zh, en))
    return "".join(out)


def matrix_rows(c):
    """W1 rows grouped by area (design order), quiz before practice, catalog order inside."""
    ordered = []
    for area in AREA_ORDER:
        for type_ in ("quiz", "practice"):
            for row in c.rows:
                if row["area"] == area and row["type"] == type_:
                    ordered.append(row)
    return ordered


def matrix_layout(c):
    """(rows shown, rows folded, glossary on page 3)."""
    ordered = matrix_rows(c)
    folded = []
    if len(ordered) > MATRIX_MAX_ROWS:
        rank = sorted(range(len(ordered)), key=lambda i: (-ordered[i]["rounds"], i))
        keep = set(rank[:MATRIX_KEEP_ROWS])
        folded = [ordered[i] for i in range(len(ordered)) if i not in keep]
        ordered = [ordered[i] for i in range(len(ordered)) if i in keep]
    areas = []
    for row in ordered:
        if row["area"] not in areas:
            areas.append(row["area"])
    glossary_here = not folded and len(ordered) + len(areas) <= MATRIX_GLOSSARY_LINES
    return ordered, folded, glossary_here


def cell(row, day):
    counts = None
    for d in row["days"]:
        if d["day"] == day:
            counts = d
    if counts is None:
        return "<td></td>"
    if row["type"] == "quiz":
        k, n, cls = counts["first_try"], counts["answered"], "q"
    else:
        k, n, cls = counts["smooth"], counts["smooth_defined"], "p"
    if n == 0:
        return '<td class="na">—</td>'
    return '<td class="%s">%d/%d</td>' % (cls, k, n)


def glossary():
    out = ['<div class="howto">\n' + heading("h3", "gloss.title") + '<div class="gloss">\n']
    for term, zh, en in glossary_entries():
        out.append("<div><b>%s</b>：%s</div>\n" % (esc(term), bi(zh, en)))
    return "".join(out) + "</div></div>\n"


def names_list(kinds, limit):
    """Plain names joined by 「、」 / ", ", at most `limit`, then 「同另外 n 個遊戲」."""
    zh = "、".join(game_name(k)[0] for k in kinds[:limit])
    en = ", ".join(game_name(k)[1] for k in kinds[:limit])
    if len(kinds) > limit:
        more = label("list.more", n=len(kinds) - limit)
        zh += more[0]
        en += " " + more[1]
    return zh, en


def page3(c, layout):
    ordered, folded, glossary_here = layout
    out = [heading("h2", "p3.title"), pair(*L["p3.cells"], cls="pair key"), pair(*L["p3.badges"], cls="pair key")]
    if not c.rows:
        out.append('<p class="status">%s</p>\n' % bi(*L["none.games"]))
    else:
        out.append('<table class="matrix">\n<colgroup><col style="width:288px">' + '<col style="width:42px">' * 7 +
                   '<col style="width:46px"><col style="width:60px"></colgroup>\n<tr>')
        out.append('<th class="name">%s</th>' % bi(*L["th.game"]))
        for i in range(7):
            d_ = ymd(c.stamps[i])[2]
            out.append("<th>%s</th>" % bi(WEEKDAY_SHORT[i][0], "%s %d" % (WEEKDAY_SHORT[i][1], d_)))
        out.append("<th>%s</th><th>%s</th></tr>\n" % (bi(*L["th.week"]), bi(*L["th.tickets"])))
        area = None
        for row in ordered:
            if row["area"] != area:
                area = row["area"]
                out.append('<tr class="area"><td colspan="10">%s</td></tr>\n' % bi(*w3.AREA_NAMES[area]))
            g = c.game_at[(row["kind"], row["type"])]
            cells = "".join(cell(row, d) for d in range(7))
            if g["n"] > 0:
                total = '<td class="tot">%d/%d</td>' % (g["k"], g["n"])
            else:
                total = '<td class="tot na">—</td>'
            stars = [s["rounds"] for s in row["stars"]]
            out.append('<tr><td class="name">%s%s</td>%s%s<td class="stars">%d · %d · %d</td></tr>\n' % (
                badges(g), bi(*game_name(row["kind"])), cells, total, stars[0], stars[1], stars[2]))
        if folded:
            rounds = sum(r["rounds"] for r in folded)
            names = names_list([r["kind"] for r in folded], FOLD_NAMES_MAX)
            out.append('<tr class="fold"><td colspan="10">%s</td></tr>\n' % bi(
                *label("m1.fold", n=len(folded), m=rounds, names=names)))
        out.append("</table>\n")
    if glossary_here:
        out.append(glossary())
    return "".join(out)


def star_mix(counts):
    parts = []
    for i, n in enumerate(counts):
        if n > 0:
            parts.append("★" * (i + 1) + str(n))
    return " ".join(parts)


def fact_tail(g):
    days = label("p4.daysOne" if g["days_played"] == 1 else "p4.days", n=g["days_played"])
    mix = star_mix(g["stars"])
    tail = days[0] + " " + days[1]
    return mix + " · " + tail if mix else tail


def fact_block(g, gt):
    tail = '<span class="stars">%s</span>' % esc(fact_tail(g))
    if gt["fact"] is None:
        return '<div class="fact">%s</div>' % tail
    return '<div class="fact">%s%s</div>' % (bi(gt["fact"]["zh"], gt["fact"]["en"]), tail)


def comment_block(sentences):
    return '<div class="cm">%s</div>' % "".join(bi(s["zh"], s["en"]) for s in sentences)


def rank_rows(c, lists):
    out = []
    for type_ in ("quiz", "practice"):
        for kind in lists[type_]:
            g = c.game_at[(kind, type_)]
            gt = c.text_at[(kind, type_)]
            out.append('<div class="row"><div class="nm">%s%s</div>%s%s</div>\n' % (
                badges(g), bi(*game_name(kind)), fact_block(g, gt), comment_block(gt["short"])))
    return "".join(out)


def rank_head(lid, split):
    zh, en = L[lid]
    out = '<div class="head"><h3>%s<span class="en">%s</span></h3>' % (esc(zh), esc(en))
    if split is not None:
        out += '<span class="split">%s · %s</span>' % (esc(split["zh"]), esc(split["en"]))
    return out + "</div>\n"


def status_line(zh, en):
    return '<p class="status">%s</p>\n' % bi(zh, en)


def page4(c, variant):
    dense, mode, method = variant
    ranking, rt = c.a["ranking"], c.text["ranking"]
    out = [heading("h2", "p4.title")]
    if not c.rows:
        out.append(status_line(*L["none.games"]))
    elif not ranking["ranked"]:
        out.append(status_line(rt["status"]["zh"], rt["status"]["en"]))
    else:
        out.append('<div class="rank">\n' + rank_head("p4.top", rt["top_split"]))
        if rt["status"] is not None:
            out.append(status_line(rt["status"]["zh"], rt["status"]["en"]))
        out.append(rank_rows(c, ranking["top"]))
        if rt["also_well"] is not None:
            out.append('<p class="also">%s</p>\n' % bi(rt["also_well"]["zh"], rt["also_well"]["en"]))
        out.append("</div>\n")
        out.append('<div class="rank">\n' + rank_head("p4.bottom", rt["still_learning_split"]))
        if not ranking["still_learning"]["quiz"] and not ranking["still_learning"]["practice"]:
            out.append(status_line(*L["wr.bottom.none"]))
        out.append(rank_rows(c, ranking["still_learning"]))
        if rt["also_learning"] is not None:
            out.append('<p class="also">%s</p>\n' % bi(rt["also_learning"]["zh"], rt["also_learning"]["en"]))
        out.append("</div>\n")
    entries = ranking["insufficient"]
    if entries:
        out.append('<div class="rank insuff">\n' + rank_head("p4.insufficient", None))
        if mode == "cols":
            out.append('<div class="cols">\n')
        for entry in entries:
            g = c.game_at[(entry["kind"], entry["type"])]
            gt = c.text_at[(entry["kind"], entry["type"])]
            cls = "item" if mode == "cols" else "row"
            out.append('<div class="%s"><div class="nm">%s%s</div>%s</div>\n' % (
                cls, badges(g), bi(*game_name(entry["kind"])), comment_block(gt["short"])))
        if mode == "cols":
            out.append("</div>\n")
        out.append("</div>\n")
    if method and c.rows:
        out.append('<div class="method">%s</div>\n' % bi(*label("p4.method", min=MIN_ROUNDS, days=STILL_LEARNING_DAYS)))
    return "".join(out)


def li(zh, en):
    return "<li>%s</li>\n" % bi(zh, en)


def quoted_names(kinds, limit):
    """「a」、「b」同另外 n 個遊戲 / "a", "b" and n more (or "a" and "b")."""
    shown = kinds[:limit]
    zh = "、".join("「%s」" % game_name(k)[0] for k in shown)
    items = ["\"%s\"" % game_name(k)[1] for k in shown]
    if len(kinds) > limit:
        more = label("list.more", n=len(kinds) - limit)
        return zh + more[0], ", ".join(items) + " " + more[1]
    if len(items) > 1:
        return zh, ", ".join(items[:-1]) + " and " + items[-1]
    return zh, items[0]


def value_label(labels, value):
    if value is None:
        return None
    if labels is not None and value in labels:
        return labels[value]
    return value, value


def date_for(c, stamp):
    """「10月21日（三）」 for a day of the week; the plain date otherwise."""
    if stamp in c.stamps:
        return date_mdw(stamp, c.stamps.index(stamp))
    return date_md(stamp)


def setting_line(c, s):
    name = w3.CONFIG_NAMES.get(s["what"])
    if name is None:
        nzh, nen, labels = s["what"], s["what"], None
    else:
        nzh, nen, labels = name
    date = date_for(c, s["date"])
    affects = label("set.affects", n=len(s["kinds"])) if s["kinds"] else ("", "")
    new = value_label(labels, s["new"])
    old = value_label(labels, s["old"])
    if new is not None and old is not None:
        return label("set.change", date=date, name=(nzh, nen), old=old, new=new, affects=affects)
    if new is not None:
        return label("set.new", date=date, name=(nzh, nen), new=new, affects=affects)
    return label("set.plain", date=date, name=(nzh, nen), affects=affects)


def page5(c):
    out = [heading("h2", "p5.title")]
    weeks = c.m["weeks"]
    if len(weeks) < 2:
        out.append('<p class="chartnote">%s</p>\n' % bi(*L["wr.baseline"]))
    else:
        out.append('<div class="grid2"><div><div class="charttitle">%s</div>\n<div class="chart">\n%s</div></div>'
                   '<div><div class="charttitle">%s</div>\n<div class="chart">\n%s</div></div></div>\n' % (
                       bi(*L["c3.title"]), chart_c3(weeks), bi(*L["c4.title"]), chart_c4(weeks)))
    out.append('<div class="charttitle">%s</div>\n' % bi(*L["c2a.title"]))
    rows = area_rows(c)
    if rows:
        out.append('<div class="chart">\n' + chart_hbars(rows, QUIZ, True) + "</div>\n")
    else:
        out.append('<p class="chartnote">%s</p>\n' % bi(*L["c2.noQuiz"]))
    out.append('<div class="charttitle">%s</div>\n' % bi(*L["c2b.title"]))
    rows = family_rows(c)
    if rows:
        out.append('<div class="chart">\n' + chart_hbars(rows, PRACTICE, False) + "</div>\n")
    else:
        out.append('<p class="chartnote">%s</p>\n' % bi(*L["c2.noPractice"]))
    out.append('<div class="grid2"><div class="panel">' + heading("h3", "p5.clear") + '<ul class="items dots">\n')
    if c.baseline:
        out.append(li(*L["wr.baseline"]))
    else:
        clear = c.comparison["clear_changes"]
        for ch in clear[:CLEAR_MAX]:
            wow = c.game_at[(ch["kind"], ch["type"])]["wow"]
            metric = L["metric.quiz"] if ch["type"] == "quiz" else L["metric.practice"]
            out.append(li(*label("clear.up" if ch["change"] == "up" else "clear.down", game=game_name(ch["kind"]),
                                 metric=metric, k0=wow["k0"], n0=wow["n0"], k1=wow["k1"], n1=wow["n1"])))
        if len(clear) > CLEAR_MAX:
            more = len(clear) - CLEAR_MAX
            out.append(li(*label("clear.moreOne" if more == 1 else "clear.more", n=more)))
        out.append(li(*(L["clear.others"] if clear else L["clear.none"])))
        gear = [g["kind"] for g in c.games if g["settings"]]
        if gear:
            out.append(li(*label("clear.gear", games=quoted_names(gear, GEAR_NAMES_MAX))))
    out.append('</ul></div>\n<div class="panel">' + heading("h3", "p5.app") + '<ul class="items dots">\n')
    ch = c.changes
    versions = ch["versions"]
    if len(versions) == 1:
        out.append(li(*label("ver.one", v="v" + versions[0]["app"])))
    elif 1 < len(versions) <= VERSIONS_LISTED:
        items_zh, items_en = [], []
        for v in versions:
            zh, en = label("ver.item", v="v" + v["app"], days=day_span(c.stamps, v["first_day"], v["last_day"]))
            items_zh.append(zh)
            items_en.append(en)
        out.append(li(*label("ver.list", n=len(versions),
                             list=("、".join(items_zh), ", ".join(items_en[:-1]) + " and " + items_en[-1]))))
    elif len(versions) > VERSIONS_LISTED:
        out.append(li(*label("ver.many", n=len(versions), first="v" + versions[0]["app"], last="v" + versions[-1]["app"])))
    for s in c.text["changes"]:
        out.append(li(s["zh"], s["en"]))
    lines_ = [setting_line(c, s) for s in ch["config"]]
    for asg in ch["assignment"]:
        date = date_for(c, asg["date"])
        lines_.append(label("assign.on" if asg["on"] else "assign.off", date=date, game=game_name(asg["kind"]),
                            stars="★" * asg["star"]))
    gen_labels = w3.FIELD_NAMES["gen"][2]
    for gen in ch["gen"]:
        lines_.append(label("gen.change", game=game_name(gen["kind"]), old=value_label(gen_labels, gen["old"]),
                            new=value_label(gen_labels, gen["new"])))
    for zh, en in lines_[:CHANGE_LINES_MAX]:
        out.append(li(zh, en))
    if len(lines_) > CHANGE_LINES_MAX:
        more = len(lines_) - CHANGE_LINES_MAX
        out.append(li(*label("changes.moreOne" if more == 1 else "changes.more", n=more)))
    mix = ch["mix"]
    now = mix["quiz_rounds"]["current"] + mix["practice_rounds"]["current"]
    before = mix["quiz_rounds"]["previous"] + mix["practice_rounds"]["previous"]
    if now > 0:
        p = w3.pct(mix["practice_rounds"]["current"], now)
        if not c.baseline and before > 0:
            out.append(li(*label("mix.both", p=p, p0=w3.pct(mix["practice_rounds"]["previous"], before))))
        else:
            out.append(li(*label("mix.now", p=p)))
    excl = ch["excluded_rounds"]
    by_reason = excl["by_reason"]
    others = sorted((r for r in by_reason if r not in EXCLUDED_ORDER), key=lambda r: r.encode("utf-8"))
    items_zh, items_en = [], []
    for reason in EXCLUDED_ORDER + others:
        n = by_reason.get(reason, 0)
        if n <= 0:
            continue
        if reason in EXCLUDED_ORDER:
            zh, en = label("excl." + reason, n=n)
        else:
            zh, en = label("excl.other", reason=reason, n=n)
        items_zh.append(zh)
        items_en.append(en)
    if excl["open_at_cutoff"] > 0:
        zh, en = label("excl.open", n=excl["open_at_cutoff"])
        items_zh.append(zh)
        items_en.append(en)
    if items_zh:
        out.append(li(*label("excl.list", items=("、".join(items_zh), ", ".join(items_en)))))
    out.append("</ul></div></div>\n")
    return "".join(out)


def rec_block(text_zh, text_en, why=None, params=(), decide=False):
    out = '<div class="rec"><div class="t">%s' % esc(text_zh)
    if decide:
        out += '<span class="decide">%s</span>' % esc(L["p6.decide"][0])
    out += '<span class="en">%s</span></div>' % esc(text_en)
    if why is not None:
        out += '<div class="why">%s</div>' % bi(why[0], why[1])
    for p in params:
        out += '<div class="param">%s</div>' % esc(p)
    return out + "</div>\n"


def page6(c, glossary_here):
    rec = c.text["recommendations"]
    out = [heading("h2", "p6.title"), heading("h3", "p6.family")]
    for item in rec["family"]:
        why = label("p6.because", because=(item["because"]["zh"], item["because"]["en"]))
        out.append(rec_block(item["text"]["zh"], item["text"]["en"], why))
    for s in (rec["praise"], rec["family_none"]):
        if s is not None:
            out.append(rec_block(s["zh"], s["en"]))
    out.append('<div class="sec">\n' + heading("h3", "p6.app"))
    for item in rec["app"]:
        why = label("p6.why", because=(item["because"]["zh"], item["because"]["en"]),
                    check=(item["check"]["zh"], item["check"]["en"]))
        out.append(rec_block(item["text"]["zh"], item["text"]["en"], why, [s["en"] for s in item["settings"]], True))
    if rec["app_none"] is not None:
        out.append(rec_block(rec["app_none"]["zh"], rec["app_none"]["en"]))
    out.append("</div>\n")
    if rec["questions"]:
        out.append('<div class="sec">\n' + heading("h3", "p6.questions"))
        for q in rec["questions"]:
            note = q["note"]
            out.append(rec_block(q["question"]["zh"], q["question"]["en"], (note["zh"], note["en"]) if note else None))
        out.append("</div>\n")
    if not glossary_here:
        out.append(glossary())
    out.append('<p class="privacy">%s</p>\n' % bi(*L["wr.privacy"]))
    return "".join(out)


# ---------------------------------------------------------------- CSS (ported from mockups/report.css)


def css():
    return CSS_TEMPLATE % {
        "quiz": QUIZ, "video": VIDEO, "practice": PRACTICE, "ink": INK, "ink2": INK2, "muted": MUTED, "grid": GRID,
        "base": BASE_LINE, "surface": SURFACE, "quizTint": QUIZ_TINT, "practiceTint": PRACTICE_TINT, "brand": BRAND,
        "paper": PAPER, "ticket": TICKET, "metro": METRO, "stamp": STAMP, "panel": PANEL, "badgeGrey": BADGE_GREY,
        "badgeQuizLine": BADGE_QUIZ_LINE, "badgePracticeLine": BADGE_PRACTICE_LINE, "badgeNew": BADGE_NEW,
        "badgeNewLine": BADGE_NEW_LINE,
    }


CSS_TEMPLATE = """@page { size: A4; margin: 0; }
html { font-family: "PingFang HK", "Noto Sans CJK HK", sans-serif; color: %(ink)s; font-size: 12px; line-height: 1.38; -webkit-text-size-adjust: none; overflow-wrap: break-word; }
body { margin: 0; background: %(surface)s; }
p { margin: 0; }
section.page { position: relative; box-sizing: border-box; width: 794px; height: 1123px; overflow: hidden; padding: 72px 53px 57px 53px; background: %(surface)s; break-after: page; page-break-after: always; }
section.page:last-of-type { break-after: auto; page-break-after: auto; }
@media print { section.page { width: 210mm; height: 297mm; } }
.runhead { position: absolute; left: 53px; right: 53px; top: 0; height: 62px; box-sizing: border-box; display: flex; justify-content: space-between; align-items: flex-end; border-bottom: 0.8px solid %(grid)s; padding-bottom: 4px; }
.runhead .rh-left { font-size: 9.6px; color: %(ink2)s; white-space: nowrap; }
.runhead .rh-left b { color: %(brand)s; font-weight: 700; }
.runhead .rh-tag { font-size: 9.3px; font-weight: 700; color: %(stamp)s; border: 1px solid %(stamp)s; border-radius: 7px; padding: 0 7px; white-space: nowrap; }
.runfoot { position: absolute; left: 53px; right: 53px; top: 1073px; display: flex; justify-content: space-between; align-items: flex-start; font-size: 8.3px; color: %(muted)s; line-height: 1.35; }
.runfoot .pageno { font-size: 8.8px; white-space: nowrap; margin-left: 12px; }
.wm { position: absolute; top: 446px; left: -45px; width: 794px; text-align: center; transform: rotate(-32deg); font-size: 53px; font-weight: 700; color: %(stamp)s; opacity: 0.1; letter-spacing: 2.7px; white-space: nowrap; }
.en { color: %(ink2)s; font-size: 9.9px; line-height: 1.3; }
.zh { font-size: 12px; }
.pair { margin: 0 0 6px 0; }
.pair .en { display: block; margin-top: 1px; }
h1 { font-size: 26.7px; line-height: 35px; margin: 0; color: %(brand)s; font-weight: 700; letter-spacing: 0.7px; }
h1 .en { font-size: 14px; color: %(ink2)s; font-weight: 400; letter-spacing: 0; margin-left: 8px; }
h2 { font-size: 17px; line-height: 23px; margin: 0 0 6px 0; color: %(brand)s; font-weight: 700; }
h2 .en { font-size: 11.5px; color: %(ink2)s; font-weight: 400; margin-left: 6px; }
h3 { font-size: 13px; line-height: 18px; margin: 0 0 5px 0; font-weight: 700; }
h3 .en { font-size: 10px; color: %(ink2)s; font-weight: 400; margin-left: 5px; }
.cover { border-left: 8px solid %(brand)s; padding: 2px 0 2px 15px; margin-bottom: 14px; }
.cover .meta { margin-top: 6px; font-size: 12px; color: %(ink2)s; }
.cover .meta .en { display: block; font-size: 9.9px; }
.highlights { background: %(paper)s; border-radius: 11px; padding: 13px 17px 7px 17px; margin-bottom: 14px; }
.highlights .pair { margin-bottom: 8px; }
.highlights .zh { font-size: 13px; }
.highlights .en { font-size: 10.4px; }
.tiles { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; margin-bottom: 14px; }
.tile { border: 0.8px solid %(grid)s; border-radius: 10px; padding: 9px 11px 8px 11px; }
.tile .lbl { font-size: 10.7px; color: %(ink2)s; line-height: 1.25; }
.tile .lbl .en { display: block; font-size: 8.8px; color: %(muted)s; }
.tile .val { font-size: 22.7px; font-weight: 700; margin: 2px 0 1px 0; line-height: 1.15; white-space: nowrap; }
.tile .val small { font-size: 12px; font-weight: 400; color: %(ink2)s; }
.tile .val.na { color: %(muted)s; }
.tile .cmp { font-size: 9.9px; color: %(ink2)s; line-height: 1.3; }
.tile .cmp .en { font-size: 8.7px; color: %(muted)s; display: block; }
.sw { display: inline-block; width: 8px; height: 8px; border-radius: 2px; margin-right: 5px; vertical-align: 1px; }
.sw.q { background: %(quiz)s; }
.sw.p { background: %(practice)s; }
.sw.v { background: %(video)s; }
.pair.key { margin-bottom: 4px; }
.key .zh { font-size: 10.7px; }
.key .en { font-size: 9px; }
.tilenote { margin: -6px 0 12px 0; }
.tilenote .zh { font-size: 10.7px; color: %(ink2)s; }
.tilenote .en { font-size: 9px; color: %(muted)s; }
.twocol { display: grid; grid-template-columns: 1fr 1fr; gap: 19px; }
.box { border-radius: 10px; padding: 11px 14px 4px 14px; }
.box.wins { background: %(ticket)s; }
.box.next { background: %(metro)s; }
ul.items { list-style: none; padding: 0; margin: 0; }
ul.items li { margin: 0 0 7px 0; padding-left: 16px; position: relative; }
ul.items li::before { content: "✓"; position: absolute; left: 0; top: 0; color: %(brand)s; font-weight: 700; font-size: 11.3px; }
ul.items.dots li::before { content: "•"; font-size: 13.3px; top: -2px; }
ul.items li .en { display: block; }
.note { font-size: 9.9px; color: %(ink2)s; margin-top: 11px; line-height: 1.4; }
.note .en { display: block; font-size: 9px; color: %(muted)s; }
.chart { margin: 0 0 6px 0; }
.chart svg { display: block; width: 100%%; height: auto; }
.charttitle { font-size: 12.3px; font-weight: 700; margin-bottom: 4px; }
.charttitle .en { font-size: 9.6px; font-weight: 400; margin-left: 5px; }
.chartnote { font-size: 10.7px; color: %(ink2)s; border: 0.8px solid %(grid)s; border-radius: 10px; padding: 9px 12px; margin: 0 0 10px 0; }
.chartnote .en { display: block; font-size: 9px; color: %(muted)s; }
table { border-collapse: collapse; width: 100%%; table-layout: fixed; }
table.daily { font-size: 10.7px; margin-top: 4px; }
table.daily th { font-size: 9.3px; font-weight: 700; color: %(ink2)s; text-align: right; padding: 4px 4px 5px 4px; border-bottom: 1px solid %(base)s; vertical-align: bottom; line-height: 1.25; }
table.daily th .en { display: block; font-weight: 400; font-size: 8.3px; color: %(muted)s; }
table.daily th.l, table.daily td.l { text-align: left; }
table.daily td { padding: 5px 4px; border-bottom: 0.7px solid %(grid)s; text-align: right; font-variant-numeric: tabular-nums; vertical-align: top; }
table.daily td .en { display: block; font-size: 8.5px; color: %(muted)s; }
table.daily tr.total td { font-weight: 700; border-top: 1px solid %(base)s; border-bottom: none; }
table.daily td.muted { color: %(muted)s; }
table.daily td.note-cell { font-size: 9.6px; }
table.matrix { font-size: 10.1px; }
table.matrix th { font-size: 9px; color: %(ink2)s; font-weight: 700; padding: 2px 2px 3px 2px; border-bottom: 1px solid %(base)s; text-align: center; line-height: 1.2; vertical-align: bottom; }
table.matrix th .en { display: block; font-weight: 400; font-size: 8px; color: %(muted)s; }
table.matrix th.name { text-align: left; }
table.matrix td { padding: 2px 2px; border-bottom: 0.7px solid %(grid)s; text-align: center; font-variant-numeric: tabular-nums; vertical-align: middle; }
table.matrix td.name { text-align: left; padding-left: 3px; line-height: 1.15; }
table.matrix td.name .en { display: block; font-size: 8.1px; color: %(muted)s; }
table.matrix td.q { background: %(quizTint)s; }
table.matrix td.p { background: %(practiceTint)s; }
table.matrix td.na { color: %(muted)s; }
table.matrix td.tot { font-weight: 700; }
table.matrix td.stars { color: %(ink2)s; font-size: 9px; }
table.matrix tr.area td { background: %(panel)s; font-size: 9.3px; font-weight: 700; color: %(ink2)s; padding: 3px 3px; text-align: left; }
table.matrix tr.area td .en { font-weight: 400; color: %(muted)s; margin-left: 4px; font-size: 8.3px; }
table.matrix tr.fold td { text-align: left; color: %(ink2)s; font-size: 9.3px; padding: 4px 3px; }
table.matrix tr.fold td .en { display: block; font-size: 8.1px; color: %(muted)s; }
.badge { display: inline-block; font-size: 8px; font-weight: 700; border-radius: 4px; padding: 0 4px; margin-right: 3px; vertical-align: 1px; line-height: 1.35; color: %(ink)s; white-space: nowrap; }
.badge.q { background: %(quizTint)s; border: 0.7px solid %(badgeQuizLine)s; }
.badge.p { background: %(practiceTint)s; border: 0.7px solid %(badgePracticeLine)s; }
.badge.new { background: %(badgeNew)s; border: 0.7px solid %(badgeNewLine)s; }
.badge.fixed { background: %(badgeGrey)s; border: 0.7px solid %(base)s; color: %(ink2)s; font-weight: 400; }
.badge.cfg { background: %(badgeGrey)s; border: 0.7px solid %(base)s; color: %(ink2)s; }
.rank { margin-bottom: 10px; }
.rank .head { display: flex; justify-content: space-between; align-items: baseline; border-bottom: 1.2px solid %(brand)s; padding-bottom: 3px; margin-bottom: 4px; }
.rank .head h3 { margin: 0; color: %(brand)s; }
.rank .head .split { font-size: 9.9px; color: %(ink2)s; white-space: nowrap; }
.row { display: grid; grid-template-columns: 196px 155px 1fr; gap: 11px; padding: 4px 0; border-bottom: 0.7px solid %(grid)s; }
.row .nm { font-size: 12px; line-height: 15px; font-weight: 700; }
.row .nm .en { display: block; font-weight: 400; font-size: 9.2px; line-height: 12px; }
.fact { font-size: 11.2px; line-height: 14.5px; }
.fact .en { display: block; font-size: 9px; line-height: 12px; }
.fact .stars { display: block; font-size: 8.8px; line-height: 11.5px; color: %(muted)s; }
.cm { font-size: 10.9px; line-height: 14.4px; }
.cm .en { display: block; font-size: 8.9px; line-height: 11.6px; }
.status { font-size: 11.5px; line-height: 15.8px; margin: 2px 0 6px 0; }
.status .en { display: block; font-size: 9.3px; line-height: 12.1px; }
.also { font-size: 10.4px; line-height: 14.5px; margin: 6px 0 0 0; }
.also .en { display: block; font-size: 9px; line-height: 12px; color: %(ink2)s; }
.insuff .row { grid-template-columns: 196px 1fr; }
.insuff .cols { display: grid; grid-template-columns: 1fr 1fr; column-gap: 19px; }
.insuff .item { padding: 3px 0; border-bottom: 0.7px solid %(grid)s; }
.insuff .item .nm { font-size: 10.7px; line-height: 13.4px; font-weight: 700; }
.insuff .item .nm .en { display: inline; font-weight: 400; font-size: 8.8px; line-height: 13.4px; margin-left: 4px; }
.insuff .item .cm { font-size: 9.9px; line-height: 12.9px; }
.insuff .item .cm .en { font-size: 8.5px; line-height: 11px; }
.method { background: %(panel)s; border-radius: 9px; padding: 8px 12px 6px 12px; font-size: 9.9px; line-height: 13.8px; margin-top: 8px; }
.method .en { display: block; font-size: 8.8px; line-height: 11.4px; color: %(ink2)s; margin-bottom: 4px; }
.dense .rank { margin-bottom: 6px; }
.dense .row { padding: 2px 0; }
.dense .row .nm { font-size: 11px; line-height: 13.5px; }
.dense .row .nm .en { font-size: 8.6px; line-height: 11px; }
.dense .fact { font-size: 10.2px; line-height: 13px; }
.dense .fact .en { font-size: 8.4px; line-height: 11px; }
.dense .fact .stars { font-size: 8.2px; line-height: 10.5px; }
.dense .cm { font-size: 10px; line-height: 13px; }
.dense .cm .en { font-size: 8.2px; line-height: 10.6px; }
.dense .also { font-size: 9.6px; line-height: 13px; }
.dense .also .en { font-size: 8.4px; line-height: 11px; }
.grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 19px; }
.panel { border: 0.8px solid %(grid)s; border-radius: 10px; padding: 10px 13px 3px 13px; margin-top: 8px; }
.panel ul.items li { margin-bottom: 6px; }
.rec { padding: 5px 0; border-bottom: 0.7px solid %(grid)s; }
.rec .t { font-size: 12px; line-height: 16px; font-weight: 700; }
.rec .t .en { display: block; font-weight: 400; font-size: 9.6px; line-height: 12.5px; color: %(ink2)s; }
.rec .why { font-size: 10px; line-height: 13.5px; color: %(ink2)s; margin-top: 2px; }
.rec .why .en { display: block; font-size: 9px; line-height: 12px; color: %(muted)s; }
.rec .param { font-size: 9.3px; line-height: 12.5px; color: %(muted)s; margin-top: 2px; font-family: Menlo, "Noto Sans Mono CJK HK", monospace; }
.rec .decide { font-size: 8.5px; font-weight: 700; color: %(brand)s; border: 0.8px solid %(brand)s; border-radius: 4px; padding: 0 4px; margin-left: 5px; vertical-align: 1px; white-space: nowrap; }
.sec { margin-top: 11px; }
.howto { margin-top: 10px; border-top: 1.1px solid %(brand)s; padding-top: 7px; }
.gloss { display: grid; grid-template-columns: 1fr 1fr; gap: 3px 23px; font-size: 10px; line-height: 13.5px; margin-top: 4px; }
.gloss b { font-weight: 700; }
.gloss .en { display: block; font-size: 8.8px; line-height: 11.5px; color: %(ink2)s; }
.dense .rec { padding: 3px 0; }
.dense .rec .t { font-size: 11px; line-height: 14.5px; }
.dense .rec .t .en { font-size: 9px; line-height: 11.5px; }
.dense .rec .why { font-size: 9.4px; line-height: 12.5px; }
.dense .rec .why .en { font-size: 8.4px; line-height: 11px; }
.dense .rec .param { font-size: 8.6px; line-height: 11.5px; }
.dense .sec { margin-top: 7px; }
.dense .howto { margin-top: 8px; padding-top: 6px; }
.dense .gloss { gap: 2px 23px; font-size: 9.4px; line-height: 12.5px; }
.dense .gloss .en { font-size: 8.2px; line-height: 10.5px; }
.privacy { margin-top: 11px; font-size: 9.6px; line-height: 13px; color: %(ink2)s; border-top: 0.8px solid %(grid)s; padding-top: 8px; }
.privacy .en { display: block; font-size: 8.8px; line-height: 11.5px; color: %(muted)s; }
"""


# ---------------------------------------------------------------- the document


def render(metrics, analysis, text, generated_ms, sample):
    c = context(metrics, analysis, text, generated_ms, sample)
    layout = matrix_layout(c)
    pages = [("", page1(c))]
    if not c.empty:
        variant4 = page4_variant(c)
        dense6 = page6_dense(c, layout[2])
        pages += [("", page2(c)), ("", page3(c, layout)), (" dense" if variant4[0] else "", page4(c, variant4)),
                  ("", page5(c)), (" dense" if dense6 else "", page6(c, layout[2]))]
    title = label("doc.title", week=c.stamps[0])[0]
    if sample:
        title += L["doc.sample"][0]
    out = ['<!DOCTYPE html>\n<html lang="zh-Hant-HK">\n<head>\n<meta charset="utf-8">\n<title>%s</title>\n'
           '<meta name="author" content="VisaGames">\n<style>\n%s</style>\n</head>\n<body>\n' % (esc(title), css())]
    for n, (extra, body) in enumerate(pages, 1):
        out.append('<section class="page%s" id="p%d">\n' % (extra, n))
        if sample:
            out.append('<div class="wm">%s %s</div>\n' % (esc(L["sample"][0]), esc(L["sample"][1])))
        out.append(runhead(c))
        out.append(body)
        out.append(runfoot(c, n, len(pages)))
        out.append("</section>\n")
    out.append("</body>\n</html>\n")
    return "".join(out)


def main():
    args = [a for a in sys.argv[1:] if a != "--sample"]
    if len(args) != 2:
        raise SystemExit(__doc__)
    folder, generated_at = args
    generated_ms = w1.parse_ts(generated_at)
    if generated_ms is None:
        raise SystemExit("generated_at must look like 2026-10-25T13:00:00.000Z")
    metrics, analysis, text = load(folder)
    sys.stdout.write(render(metrics, analysis, text, generated_ms, "--sample" in sys.argv[1:]))


if __name__ == "__main__":
    main()
