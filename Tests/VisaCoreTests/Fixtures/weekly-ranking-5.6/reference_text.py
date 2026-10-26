#!/usr/bin/env python3
"""Independent reference for the W3 weekly report text (design weekly-report §6, §7; ADR 0023).

Takes the W1 metrics (`../weekly-2026-10-19/reference_model.py`) and the W2 analysis
(`reference_analysis.py`) of a stats folder, applies the W3 template and recommendation rules and
prints the text model in the canonical encoding of the W1 fixture README. Standard library only; no
code shared with the Swift side. Every rounding is done in integers (half up), as in Swift.

Usage:
  python3 reference_text.py <folder> <week_start YYYY-MM-DD> <data_until ISO-8601> [video-titles.json] \
      > expected-text.json
"""

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True  # leave no __pycache__ in the fixture folders
sys.path.insert(0, HERE)
import reference_analysis as w2  # noqa: E402

w1 = w2.w1

TEXT = 1
CHILD_NAME = "Cedric"
WIN_MAX = 3
FAMILY_MAX = 3
APP_MAX = 4
MIN_ROUNDS = 5
QUESTIONS_PAGE = 6

# ---------------------------------------------------------------- catalogue (app copy, Activity.swift)

TITLES = {
    "twoPictureChoose": ("邊架消防車", "Which fire truck"),
    "findTheSame": ("搵同一個", "Find the same"),
    "countVehicles": ("數車仔", "Count the vehicles"),
    "sequenceShortToLong": ("短到長車隊", "Short-to-long convoy"),
    "halfMatch": ("搵另一半", "Find the other half"),
    "shapeCousin": ("圓圓嘅", "Round like the sun"),
    "capacityCompare": ("邊架載多啲人", "Who carries more"),
    "moreFewer": ("邊邊車多啲", "Which lot has more"),
    "shadowMatch": ("邊個影子", "Match the shadow"),
    "emptyBay": ("空車位", "Empty parking bay"),
    "lineMatch": ("連一連 · 自己配", "Line Match · Free match"),
    "lineMatchGuidedStraight": ("連一連 · 沿路送", "Line Match · Straight road"),
    "lineMatchGuidedBridge": ("連一連 · 沿路過橋", "Line Match · Bridge road"),
    "traceLines": ("畫直線 · 熱身", "Lines · Warm-up"),
    "traceShapesDotted": ("畫形狀 · 跟虛線", "Shapes · Follow the dots"),
    "traceShapesArrows": ("畫形狀 · 跟箭嘴", "Shapes · Follow the arrows"),
    "traceShapesFree": ("畫形狀 · 自己畫", "Shapes · Draw it yourself"),
    "tapCountAll": ("一架一架數 · 點一點", "Tap & Count · Tap each one"),
    "tapCountTrace": ("一架一架數 · 數完畫", "Tap & Count · Count, then trace"),
    "tapCountPick": ("一架一架數 · 揀啱數", "Tap & Count · Pick just enough"),
    "tapCountAllEnglish": ("一架一架數（英文）· 點一點", "Tap & Count in English · Tap each one"),
    "tapCountTraceEnglish": ("一架一架數（英文）· 數完畫", "Tap & Count in English · Count & draw"),
    "tapCountPickEnglish": ("一架一架數（英文）· 揀啱數", "Tap & Count in English · Just right"),
    "tapLetterAll": ("英文字母 ABC · 翻字卡", "Letters ABC · Find & flip"),
    "tapLetterWrite": ("英文字母 ABC · 搵完寫", "Letters ABC · Find & write"),
}

AREA_NAMES = {
    "numbers": ("數字・數量", "Numbers & quantity"),
    "matching": ("觀察・配對", "Looking & matching"),
    "comparing": ("比較・概念", "Comparing & concepts"),
    "pen": ("手眼・畫線", "Pen control & tracing"),
    "letters": ("字母", "Letters"),
    "other": ("其他", "Other"),
}
QUIZ_AREAS = ["numbers", "matching", "comparing", "letters"]

# perf-review-design §8.5 approved tag strings (only tags that `answer_attempt.tags` can carry).
TAGS = {
    "same_shape": ("同款唔同色", "same shape, different colour"),
    "same_color": ("同色唔同款", "same colour, different shape"),
    "under_by_1": ("少數咗一架", "counted one too few"),
    "over_by_1": ("多數咗一架", "counted one too many"),
    "longest_first": ("由長排到短", "ordered long to short"),
    "screen_order": ("跟位置撳", "tapped in screen order"),
    "warm_color": ("揀咗顏色似嘅", "picked by colour"),
    "smaller": ("揀咗細嘅", "picked the smaller one"),
    "fewer": ("揀咗少啲嗰邊", "picked the side with fewer"),
    "vehicle_attraction": ("撳咗有車嘅位", "tapped a bay with a vehicle"),
}

DAY_ZH = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
DAY_EN = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

TOLERANCE = {"narrow": ("窄", "Narrow"), "standard": ("標準", "Standard"), "wide": ("闊", "Wide"),
             "follow_lineMatch": ("跟連一連", "Same as Line Match"),
             "follow_shape_trace": ("跟畫形狀", "Same as Shapes")}
GUIDANCE = {"more": ("多啲", "More"), "standard": ("標準", "Standard"), "less": ("少啲", "Less")}
SCAFFOLD = {"dots": ("虛線路", "dotted lane"), "outline": ("淡框 + 箭嘴", "outline + arrows")}
CATEGORY = {"numbers": ("數字", "Numbers"), "body": ("身體部位", "Body parts"), "animals": ("小動物", "Animals"),
            "zodiac": ("十二生肖", "Zodiac")}
CATEGORY_ORDER = ["numbers", "body", "animals", "zodiac"]

# any.settings {setting}: config `what` (and deal or result fields) -> (zh, en, value labels or None).
CONFIG_NAMES = {
    "lineMatch_tolerance": ("連一連寬容度", "Line Match tolerance", TOLERANCE),
    "lineMatch_category_weight": ("連一連類別比例", "Line Match category mix", None),
    "lineMatch_category_mix": ("連一連類別比例", "Line Match category mix", None),
    "shapeTrace_tolerance": ("畫形狀寬容度", "Shapes tolerance", TOLERANCE),
    "shapeTrace_shape_weight": ("畫形狀比例", "Shape mix", None),
    "shapeTrace_shape_mix": ("畫形狀比例", "Shape mix", None),
    "shapeTrace_direction_hint": ("方向提示", "Direction hint", None),
    "shapeTrace_corner_stop": ("轉角停一停", "Corner stop", None),
    "shapeTrace_slant_lines": ("畫直線加斜線", "Slant line in Lines", None),
    "shapeTrace_dot_style": ("虛線款式", "Dot style", None),
    "tapCount_range": ("數字範圍", "Numbers range", None),
    "tapCount_count_voice": ("點車讀數", "Count aloud", None),
    "tapCount_english": ("加英文", "English word", None),
    "tapCount_badge_style": ("數字牌", "Badges", None),
    "tapCount_trace_scaffold": ("描數字", "Trace guide", None),
    "tapCount_guidance": ("描數字提示", "Tracing help", GUIDANCE),
    "tapCount_stroke_order": ("筆順動畫", "Stroke order", None),
    "tapCount_tolerance": ("一架一架數寬容度", "Tap & Count tolerance", TOLERANCE),
}
FIELD_NAMES = {
    "gen": ("題目來源", "Question source", {"fixed_v0": ("同一題", "Same question"),
                                          "variants_v1": ("多款題目", "Varied questions")}),
    "level": ("難度", "Level", None),
    "shape_trace_level": ("難度", "Level", None),
    "trace_scaffold": ("描數字", "Trace guide", SCAFFOLD),
    "range": ("數字範圍", "Numbers range", None),
    "count_voice": ("點車讀數", "Count aloud", None),
    "english": ("加英文", "English word", None),
    "direction_coaching": ("方向提示", "Direction hint", None),
    "stop_coaching": ("轉角停一停", "Corner stop", None),
    "slant_enabled": ("畫直線加斜線", "Slant line in Lines", None),
    "dot_style": ("虛線款式", "Dot style", None),
    "category_mix": ("連一連類別比例", "Line Match category mix", None),
    "shape_mix": ("畫形狀比例", "Shape mix", None),
    "guide_level": ("描數字提示", "Tracing help", GUIDANCE),
}
LINE_KINDS = ["lineMatch", "lineMatchGuidedStraight", "lineMatchGuidedBridge"]
SHAPE_KINDS = ["traceLines", "traceShapesDotted", "traceShapesArrows", "traceShapesFree"]
TAP_KINDS = ["tapCountAll", "tapCountTrace", "tapCountPick", "tapCountAllEnglish", "tapCountTraceEnglish",
             "tapCountPickEnglish"]
TOLERANCE_NAMES = {"line": ("連一連寬容度", "Line Match tolerance"), "shape": ("畫形狀寬容度", "Shapes tolerance"),
                   "tap": ("一架一架數寬容度", "Tap & Count tolerance")}
GENERATED = {"countVehicles", "findTheSame", "lineMatchGuidedStraight", "lineMatchGuidedBridge", "lineMatch",
             "traceLines", "traceShapesDotted", "traceShapesArrows", "traceShapesFree", "tapCountAll",
             "tapCountTrace", "tapCountPick", "tapCountAllEnglish", "tapCountTraceEnglish", "tapCountPickEnglish",
             "tapLetterAll", "tapLetterWrite"}

# F8 {winObject}: what the child looked at in the game of the win.
WIN_OBJECT = {
    "twoPictureChoose": ("啲車", "the vehicles"), "findTheSame": ("啲車", "the vehicles"),
    "countVehicles": ("啲車", "the vehicles"), "sequenceShortToLong": ("個車隊", "the convoy"),
    "halfMatch": ("兩邊", "both halves"), "shapeCousin": ("啲形狀", "the shapes"),
    "capacityCompare": ("啲車", "the vehicles"), "moreFewer": ("兩個停車場", "both car parks"),
    "shadowMatch": ("影子", "the shadow"), "emptyBay": ("啲車位", "the parking bays"),
    "lineMatch": ("啲圖同字", "the pictures and words"), "lineMatchGuidedStraight": ("條路", "the road"),
    "lineMatchGuidedBridge": ("條路", "the road"), "traceLines": ("條線", "the lines"),
    "traceShapesDotted": ("啲形狀", "the shapes"), "traceShapesArrows": ("啲形狀", "the shapes"),
    "traceShapesFree": ("啲形狀", "the shapes"), "tapCountAll": ("啲車", "the vehicles"),
    "tapCountTrace": ("個數字", "the numbers"), "tapCountPick": ("啲車", "the vehicles"),
    "tapCountAllEnglish": ("啲車", "the vehicles"), "tapCountTraceEnglish": ("個數字", "the numbers"),
    "tapCountPickEnglish": ("啲車", "the vehicles"), "tapLetterAll": ("啲字母", "the letters"),
    "tapLetterWrite": ("啲字母", "the letters"),
}
WIN_OBJECT_NUMERALS = ("啲數字", "the numbers")
WIN_OBJECT_QUESTIONS = ("題目", "each question")

# ---------------------------------------------------------------- the template registry

# id -> (zh, en, [slot names]). Placeholders are {name}; a slot may be used in one language only.
TEMPLATES = {
    # fragments
    "frag.quiz": ("{n} 局入面 {k} 局一次答啱", "{k} of {n} right first time", ["n", "k"]),
    "frag.quiz.all": ("{n} 局全部一次答啱", "right first time in all {n}", ["n"]),
    "frag.practice": ("{n} 局入面 {k} 局做得順", "smooth in {k} of {n}", ["n", "k"]),
    "frag.practice.all": ("{n} 局全部做得順", "smooth in all {n}", ["n"]),
    "frag.offPath.road": ("平均每條路出界 {x} 次", "off the road {x} times per road", ["x"]),
    "frag.offPath.shape": ("平均每個形狀出界 {x} 次", "off the path {x} times per shape", ["x"]),
    "frag.offPath.line": ("平均每條線出界 {x} 次", "off the path {x} times per line", ["x"]),
    "frag.helps": ("描數字平均每次要提示 {h} 次", "needed about {h} hints per numeral", ["h"]),
    "frag.wrongStart": ("{w}/{n} 次唔係由綠色起點開始", "started away from the green start in {w} of {n}",
                        ["w", "n"]),
    "trend.same": ("（上星期 {p0}%，差唔多）", " (last week {p0}%, about the same)", ["p0"]),
    "trend.up": ("（上星期 {p0}%，明顯進步）", " (last week {p0}%, clearly up)", ["p0"]),
    "trend.down": ("（上星期 {p0}%，明顯少咗）", " (last week {p0}%, clearly down)", ["p0"]),
    "trend.unsure": ("（上星期 {p0}%，變化未夠肯定）", " (last week {p0}%, change not clear yet)", ["p0"]),
    "vs.more": ("，比上星期多 {d} 局", ", {d} more than last week", ["d"]),
    "vs.fewer": ("，比上星期少 {d} 局", ", {d} fewer than last week", ["d"]),
    "vs.same": ("，同上星期一樣", ", same as last week", []),
    "noPlay": ("（{days}冇玩）", " (none on {days})", ["days"]),
    "soFar.quizAll": ("，全部一次答啱", ", all right first time", []),
    "soFar.practiceAll": ("，全部做得順", ", all smooth", []),
    "soFar.new": ("（第一個星期玩）", " (first week)", []),
    "pointer.video": ("睇片時間第 {page} 頁有個問題想問你哋。", " Page {page} has a question about video time.",
                      ["page"]),
    "list.item": ("「{game}」（{k}/{n}）", "\"{game}\" ({k}/{n})", ["game", "k", "n"]),
    "video.item": ("「{title}」（{time}）", "\"{title}\" ({time})", ["title", "time"]),
    "setting.change": ("{name}：{old} → {new}", "{name}: {old} → {new}", ["name", "old", "new"]),
    "setting.value": ("{name}：{new}", "{name}: {new}", ["name", "new"]),
    "setting.name": ("{name}", "{name}", ["name"]),
    "setting.on": ("開咗「{game}」{stars}", "turned on {stars} for \"{game}\"", ["game", "stars"]),
    "setting.off": ("熄咗「{game}」{stars}", "turned off {stars} for \"{game}\"", ["game", "stars"]),
    "ev.game": ("「{game}」{fact}", "\"{game}\" {fact}", ["game", "fact"]),
    "ev.fuel": ("「{game}」有 {z} 次油用晒", "\"{game}\" ran out of fuel {z} times", ["game", "z"]),
    "ev.fast": ("「{game}」好多次未聽完題目就撳（{f}/{w} 次）",
                "\"{game}\" often tapped before the question finished ({f} of {w})", ["game", "f", "w"]),
    "ev.ratio": ("「{game}」{k}/{n}", "\"{game}\" {k}/{n}", ["game", "k", "n"]),
    "ev.list": ("{items}。", "{items}.", ["items"]),
    # page 1 (§6.4)
    "wr.empty": ("今個星期未有紀錄。", "No play recorded this week.", []),
    "hl.volume": ("今個星期有 {days} 日玩{noPlayDays}，總共 {rounds} 局：答題 {quiz} 局、練習 {practice} 局{vsLast}。",
                  "Played on {days} days{noPlayDays}: {rounds} rounds in all, {quiz} quiz and {practice} practice{vsLast}.",
                  ["days", "noPlayDays", "rounds", "quiz", "practice", "vsLast"]),
    "hl.volume.oneDay": ("今個星期有 {days} 日玩{noPlayDays}，總共 {rounds} 局：答題 {quiz} 局、練習 {practice} 局{vsLast}。",
                         "Played on {days} day{noPlayDays}: {rounds} rounds in all, {quiz} quiz and {practice} practice{vsLast}.",
                         ["days", "noPlayDays", "rounds", "quiz", "practice", "vsLast"]),
    "hl.rates": ("答題遊戲第一次答啱 {p}%{pTrend}；練習遊戲做得順 {s}%{sTrend}。",
                 "Quiz games right first time {p}%{pTrend}; practice games done smoothly {s}%{sTrend}.",
                 ["p", "pTrend", "s", "sTrend"]),
    "hl.rates.quiz": ("答題遊戲第一次答啱 {p}%{pTrend}。", "Quiz games right first time {p}%{pTrend}.", ["p", "pTrend"]),
    "hl.rates.practice": ("練習遊戲做得順 {s}%{sTrend}。", "Practice games done smoothly {s}%{sTrend}.", ["s", "sTrend"]),
    "hl.games": ("最穩陣係「{top1}」（{top1Fact}）；「{bot1}」仲學緊，{bot1Fact}。",
                 "Steadiest: \"{top1}\" ({top1Fact}); still learning \"{bot1}\": {bot1Fact}.",
                 ["top1", "top1Fact", "bot1", "bot1Fact"]),
    "hl.games.top": ("最穩陣係「{top1}」（{top1Fact}）。", "Steadiest: \"{top1}\" ({top1Fact}).", ["top1", "top1Fact"]),
    "hl.games.bottom": ("「{bot1}」仲學緊，{bot1Fact}。", "Still learning \"{bot1}\": {bot1Fact}.", ["bot1", "bot1Fact"]),
    "hl.games.none": ("每個遊戲都玩得唔多，下星期再睇排名。",
                      "Each game had only a few rounds; we'll look at rankings next week.", []),
    "hl.time": ("遊戲大約 {g}，睇片大約 {v}，賺到簽證 {visa}。{videoPointer}",
                "About {g} of games and {v} of videos; {visa} of visa earned.{videoPointer}",
                ["g", "v", "visa", "videoPointer"]),
    "videos.top": ("睇得最多嘅片：{items}。", "Most-watched videos: {items}.", ["items"]),
    # wins (§6.5)
    "win.newGame": ("第一次玩「{game}」。", "First time playing \"{game}\".", ["game"]),
    "win.numeral": ("識咗自己描數字 {list}（唔使提示）。", "Can now trace {list} without help.", ["list"]),
    "win.streak": ("「{game}」連續 {n} 次一次答啱。", "\"{game}\": right first time {n} times in a row.", ["game", "n"]),
    "win.rise": ("「{game}」比上星期順咗：{k0}/{n0} → {k1}/{n1}。",
                 "\"{game}\" went better than last week: {k0}/{n0} → {k1}/{n1}.", ["game", "k0", "n0", "k1", "n1"]),
    "win.firstSmooth": ("第一次順順利利完成「{game}」。", "First smooth round of \"{game}\".", ["game"]),
    "win.firstTry": ("第一次一次答啱「{game}」。", "First right-first-time on \"{game}\".", ["game"]),
    "win.cleanDay": ("{day}答題全部一次答啱（{n} 局）。", "{day}: every quiz round right first time ({n}).", ["day", "n"]),
    "win.noFuelOut": ("成個星期冇一次油用晒。", "Never ran out of fuel all week.", []),
    # game comments (§6.6)
    "top.ft": ("{n} 次入面 {k} 次一次答啱（亂估都有大約 {c}%），好穩陣。",
               "Right first time in {k} of {n} (guessing alone gives about {c}%) — very steady.", ["n", "k", "c"]),
    "top.ft.short": ("亂估都有大約 {c}%，佢明顯高好多，好穩陣。",
                     "Guessing alone gives about {c}% — well above that, very steady.", ["c"]),
    "top.all": ("{n} 次全部一次答啱。", "Right first time in all {n} rounds.", ["n"]),
    "top.memorised": ("次次都係同一條題目，可能已經記住咗，可以加新題目。",
                      "Same question every time — it may be memorised; new versions would help.", []),
    "top.smooth": ("{n} 次入面 {k} 次做得好順。", "Smooth in {k} of {n} rounds.", ["n", "k"]),
    "top.smooth.all": ("{n} 次全部做得好順。", "Smooth in all {n} rounds.", ["n"]),
    "top.smooth.short": ("平均每個形狀出界 {x} 次，好少出界。", "{x} off-path per shape on average — rarely off the path.",
                         ["x"]),
    "top.smooth.short.line": ("平均每條線出界 {x} 次，好少出界。",
                              "{x} off-path per line on average — rarely off the path.", ["x"]),
    "top.smooth.plain": ("做得好順。", "Going smoothly.", []),
    "bot.ft": ("呢個遊戲對佢仲有啲難：{n} 次入面 {k} 次一次答啱。", "This one is still tricky: right first time in {k} of {n}.",
               ["n", "k"]),
    "bot.ft.short": ("呢個遊戲對佢仲有啲難，可以多啲練習。", "This one is still tricky — room to practise.", []),
    "bot.tag": ("錯嘅時候多數係「{tag}」（{m}/{w} 次）。", "When wrong, usually \"{tag}\" ({m} of {w}).", ["tag", "m", "w"]),
    "bot.fuel": ("有 {z} 次油用晒，建議大人陪玩一次。", "Ran out of fuel {z} times — try playing it together once.", ["z"]),
    "bot.stars": ("★★★ 題目難啲（{k3}/{n3}），★／★★ 就順好多（{k12}/{n12}）。",
                  "★★★ questions are harder ({k3}/{n3}); ★/★★ go much better ({k12}/{n12}).",
                  ["k3", "n3", "k12", "n12"]),
    "bot.fast": ("好多次未聽完題目就撳（{f}/{w} 次）。", "Often tapped before the question finished ({f} of {w}).", ["f", "w"]),
    "bot.offPath": ("平均每條路出界 {x} 次。", "Off the road {x} times per road on average.", ["x"]),
    "bot.offPath.shape": ("平均每個形狀出界 {x} 次。", "Off the path {x} times per shape on average.", ["x"]),
    "bot.offPath.line": ("平均每條線出界 {x} 次。", "Off the path {x} times per line on average.", ["x"]),
    "bot.wrongStart": ("{w}/{n} 次唔係由綠色起點開始。", "Started away from the green start in {w} of {n}.", ["w", "n"]),
    "bot.helps": ("描數字平均每次要提示 {h} 次。", "Needed about {h} hints per numeral.", ["h"]),
    "any.settings": ("今個星期改咗設定（{setting}），同上星期比要小心。",
                     "Settings changed this week ({setting}); compare with last week carefully.", ["setting"]),
    "insuff.n": ("玩咗 {n} 次{soFar}，再玩 {r} 局就排名。", "Played {n}×{soFar}; {r} more to rank.", ["n", "soFar", "r"]),
    "insuff.zero": ("再玩 {r} 局就排名。", "{r} more to rank.", ["r"]),
    "insuff.oneDay": ("{n} 局都喺同一日玩，下星期再睇。", "All {n} rounds on one day — we'll look again next week.", ["n"]),
    "insuff.noMethod": ("未有評分方法。", "No scoring method yet.", []),
    # page 4 (§3, §5.3)
    "rank.notRanked": ("今個星期玩得太少，未排名。", "Too little play this week to rank the games.", []),
    "rank.allLearning": ("今個星期每個遊戲都仲學緊，慢慢嚟。", "Every game is still being learned this week — no rush.", []),
    "rank.split": ("答題 {quiz} 個、練習 {practice} 個", "{quiz} quiz, {practice} practice", ["quiz", "practice"]),
    "rank.alsoWell": ("其他都做得好：{items}", "Also going well: {items}", ["items"]),
    "rank.alsoLearning": ("其他仲學緊：{items}", "Also still learning: {items}", ["items"]),
    # page 5 (§3)
    "changes.none": ("今個星期冇改設定", "No settings changed this week", []),
    # family items (§7.1)
    "F1": ("一齊數嘢：落街數巴士、食飯數碗筷，每數一樣用手指點一下，最後講「總共幾多個」。",
           "Count things together: buses outside, bowls at dinner. Touch each one, then say how many altogether.", []),
    "F2": ("玩「搵相同」：拎兩三架玩具車，問「邊架同呢架一樣？」，再講出邊度唔同。",
           "Play \"find the same\" with two or three toy cars, then talk about what is different.", []),
    "F3": ("用玩具車排隊「由短到長」；問「邊個位空咗？」「邊架載得多啲人？」",
           "Line up toy cars short to long; ask \"which spot is empty?\", \"which carries more people?\"", []),
    "F4": ("用粗蠟筆喺大張紙畫直線同圓圈，由綠點開始畫到紅點。",
           "With a fat crayon on big paper, draw lines and circles from a green dot to a red dot.", []),
    "F4.roads": ("用粗蠟筆喺大張紙畫直線同彎路，由綠點開始畫到紅點，慢慢跟住條路行。",
                 "With a fat crayon on big paper, draw straight and curvy roads from a green dot to a red dot, slowly.", []),
    "F5": ("喺白板或者沙度一齊寫數字，邊寫邊講口訣；由佢已經識嘅 {learned} 開始。",
           "Write numbers together on a whiteboard or in sand, saying the rhyme; start with {learned}, already learned.",
           ["learned"]),
    "F5.plain": ("喺白板或者沙度一齊寫數字，邊寫邊講口訣。", "Write numbers together on a whiteboard or in sand, saying the rhyme.",
                 []),
    "F6": ("陪佢玩一次「{game}」，大人講出自己點諗。", "Play \"{game}\" together once and think aloud.", ["game"]),
    "F7": ("陪佢玩一兩局，提醒佢「聽完先撳」。", "Play a round or two together: \"listen first, then tap\".", []),
    "F8": ("見到佢做得好，讚佢做嘅過程：「你好細心咁睇{winObject}！」，唔使講「你好聰明」。",
           "When something goes well, praise the effort: \"You looked at {winObject} so carefully!\" rather than \"you're clever\".",
           ["winObject"]),
    "rec.none": ("今個星期冇特別建議，照舊就得。", "No special suggestions this week — carry on as usual.", []),
    # app items (§7.2)
    "A1": ("開「{pick}」★（要先試玩）：練「數出 N 架」。", "Turn on \"{pick}\" ★ (playtest it first) to practise \"pick N cars\".",
           ["pick"]),
    "A1.because": ("{items}；「{pick}」今個星期未玩過。", "{items}; \"{pick}\" was not played this week.", ["items", "pick"]),
    "A1.check": ("「{game}」第一次答啱率；「{pick}」玩夠 {min} 局", "\"{game}\" right first time; \"{pick}\" played {min}+ rounds",
                 ["game", "pick", "min"]),
    "A2": ("數字範圍收窄：「數字範圍」由「{from}」改做「{to}」；「點車讀數」保持開。",
           "Smaller numbers: set Numbers from {from} to {to}; keep counting aloud on.", ["from", "to"]),
    "A2.voice": ("數字範圍收窄：「數字範圍」由「{from}」改做「{to}」；「點車讀數」改返開。",
                 "Smaller numbers: set Numbers from {from} to {to}; turn counting aloud back on.", ["from", "to"]),
    "A2.because": ("「{game}」{n} 局入面有 {r} 局要重新數。", "\"{game}\" needed a recount in {r} of {n} rounds.",
                   ["game", "n", "r"]),
    "A2.check": ("點數做得順嘅比例", "tap-to-count smooth rate", []),
    "A3": ("數字範圍加大：「數字範圍」由「{from}」改做「{to}」。", "Bigger numbers: set Numbers from {from} to {to}.", ["from", "to"]),
    "A3.because": ("「{game}」連續兩個星期都做得順：今個星期 {k1}/{n1}，上星期 {k0}/{n0}。",
                   "\"{game}\" smooth two weeks running: {k1}/{n1} this week, {k0}/{n0} last week.",
                   ["game", "k1", "n1", "k0", "n0"]),
    "A3.check": ("做得順保持 {keep}% 以上", "smooth stays at {keep}% or more", ["keep"]),
    "A4": ("描數字提示加多：「描數字提示」由「{current}」改做「{suggested}」。",
           "More tracing help: set \"Tracing help\" from {current} to {suggested}.", ["current", "suggested"]),
    "A4.to": ("描數字提示加多：「描數字提示」改做「{suggested}」。", "More tracing help: set \"Tracing help\" to {suggested}.",
              ["suggested"]),
    "A4.scaffold": ("描數字提示加多：「描數字」由「{current}」改做「{suggested}」。",
                    "More tracing help: set the trace guide from \"{current}\" to \"{suggested}\".", ["current", "suggested"]),
    "A4.check": ("每次要幾多提示、識咗幾多個數字", "hints per numeral; numerals learned", []),
    "A4b": ("提示減少：「描數字提示」由「{current}」改做「{suggested}」。",
            "Less tracing help: set \"Tracing help\" from {current} to {suggested}.", ["current", "suggested"]),
    "A4b.to": ("提示減少：「描數字提示」改做「{suggested}」。", "Less tracing help: set \"Tracing help\" to {suggested}.",
               ["suggested"]),
    "A4b.scaffold": ("提示減少：「描數字」由「{current}」改做「{suggested}」。",
                     "Less tracing help: set the trace guide from \"{current}\" to \"{suggested}\".", ["current", "suggested"]),
    "A4b.because": ("「{game}」唔使提示嘅局數：今個星期 {k1}/{n1}，上星期 {k0}/{n0}。",
                    "\"{game}\" traced without help: {k1}/{n1} this week, {k0}/{n0} last week.",
                    ["game", "k1", "n1", "k0", "n0"]),
    "A4b.check": ("做得順保持 {keep}% 以上", "smooth stays at {keep}% or more", ["keep"]),
    "A5": ("加題目變化：{games}次次都係同一條題目，答啱九成以上，可能已經記住。",
           "Add question variants: {games} always show the same question and are right over {rate}% of the time.",
           ["games", "rate"]),
    "A5.one": ("加題目變化：{games}次次都係同一條題目，答啱九成以上，可能已經記住。",
               "Add question variants: {games} always shows the same question and is right over {rate}% of the time.",
               ["games", "rate"]),
    "A5.because": ("{items}（第一次答啱／局數）。", "{items} (right first time / rounds).", ["items"]),
    "A5.check": ("新題目出咗之後嘅第一次答啱率", "right first time on the new versions", []),
    "A6.bridge": ("「沿路過橋」暫時只開 ★，等「沿路送」做得順先加返；寬容度已經係「{wide}」，唔使再改。",
                  "Keep \"Bridge road\" at ★ only for now and let \"Straight road\" lead; tolerance is already {wide}.",
                  ["wide"]),
    "A6.bridge.wide": ("「沿路過橋」暫時只開 ★，等「沿路送」做得順先加返；或者將「連一連寬容度」由「{current}」改做「{wide}」。",
                       "Keep \"Bridge road\" at ★ only for now and let \"Straight road\" lead; or set Line Match tolerance from {current} to {wide}.",
                       ["current", "wide"]),
    "A6.bridge.only": ("「沿路過橋」暫時只開 ★，等「沿路送」做得順先加返。",
                       "Keep \"Bridge road\" at ★ only for now and let \"Straight road\" lead.", []),
    "A6.wide": ("將「連一連寬容度」由「{current}」改做「{wide}」。", "Set Line Match tolerance from {current} to {wide}.",
                ["current", "wide"]),
    "A6.check": ("沿路連線做得順嘅比例、每條路出界幾多次", "road matching smooth rate; times off the road per road", []),
    "A7": ("「{game}」少啲出「{category}」題目：比例減 {step}。",
           "Fewer \"{category}\" questions in \"{game}\": lower its weight by {step}.", ["game", "category", "step"]),
    "A7.because": ("錯嘅線有 {m}/{w} 條係「{category}」題目。", "{m} of {w} wrong lines were \"{category}\" questions.",
                   ["m", "w", "category"]),
    "A7.check": ("「{game}」第一次答啱率", "\"{game}\" right first time", ["game"]),
    "A8": ("開「方向提示」：畫形狀時只可以跟箭嘴方向畫。", "Turn on \"Direction hint\": shapes are drawn in the arrow direction only.",
           []),
    "A8.check": ("唔係由起點開始嘅比例", "share of rounds started away from the start", []),
    "A9": ("可以試斜線：開「畫直線加斜線」（設計建議大約 {age} 歲半）。",
           "Try slant lines: turn on \"Slant line in Lines\" (the design suggests about age {age}½).", ["age"]),
    "A9.because": ("「{game}」兩個星期 {n} 局入面 {k} 局做得順。", "\"{game}\" smooth in {k} of {n} over two weeks.",
                   ["game", "n", "k"]),
    "A9.check": ("「{game}」做得順保持 {keep}% 以上", "\"{game}\" smooth stays at {keep}% or more", ["game", "keep"]),
    "A10.numbers": ("多做一款「{area}」遊戲：數字 ↔ 數量配對，或者「邊個係 {n}？」",
                    "Add another \"{area}\" game: numeral ↔ quantity matching, or \"Which one is {n}?\"", ["area", "n"]),
    "A10": ("多做一款「{area}」遊戲。", "Add another \"{area}\" game.", ["area"]),
    "A10.because.lowest": ("「{area}」連續兩個星期係最低嘅答題類別：今個星期 {p1}%（亂估都有大約 {c}%），上星期 {p0}%。",
                           "\"{area}\" was the lowest quiz area two weeks running: {p1}% this week (guessing gives about {c}%), {p0}% last week.",
                           ["area", "p1", "c", "p0"]),
    "A10.because.learning": ("「{area}」有 {count} 個答題遊戲仲學緊：{games}。",
                             "{count} \"{area}\" quiz games are still learning: {games}.", ["area", "count", "games"]),
    "A10.check": ("「{area}」嘅第一次答啱率（兩個星期）", "right first time in \"{area}\" over two weeks", ["area"]),
    "A11": ("「{area}」可以加難度：★★★ 題目／{choices} 個選擇。", "\"{area}\" can get harder: ★★★ questions or {choices} choices.",
            ["area", "choices"]),
    "A11.because": ("「{area}」嘅遊戲連續兩個星期都做得好：{games}。",
                    "Every ranked \"{area}\" game went well two weeks running: {games}.", ["area", "games"]),
    "A11.check": ("繼續做得好", "stays going well", []),
    "A12": ("試吓題目講完先解鎖選擇（UX 實驗）。",
            "Try unlocking the choices only after the question has been read out (UX experiment).", []),
    "A12.because": ("答錯嘅時候，有 {f}/{w} 次係未聽完題目就撳。", "{f} of {w} wrong taps came before the question finished.",
                    ["f", "w"]),
    "A12.check": ("未聽完就撳嘅比例", "share of taps before the question finished", []),
    "app.none": ("今個星期冇需要改嘅設定。", "No settings need changing this week.", []),
    # setting lines (engineering text, the same in both languages)
    "set.value": ("{setting}: {from} → {to}", "{setting}: {from} → {to}", ["setting", "from", "to"]),
    "set.range": ("{setting}: {from} → {to}", "{setting}: {from} → {to}", ["setting", "from", "to"]),
    "set.weight": ("{setting}: {from} → {to}", "{setting}: {from} → {to}", ["setting", "from", "to"]),
    "set.to": ("{setting} → {to}", "{setting} → {to}", ["setting", "to"]),
    "set.assignment": ("assignment {kind} {stars}: {from} → {to}", "assignment {kind} {stars}: {from} → {to}",
                       ["kind", "stars", "from", "to"]),
    "set.generated": ("QuestionGeneration.generatedKinds: add {kinds} (Codex task)",
                      "QuestionGeneration.generatedKinds: add {kinds} (Codex task)", ["kinds"]),
    # questions (§7.3)
    "Q1": ("今個星期有玩嘅日子平均每日睇片大約 {h}（每次揀片之後平均播 {m} 分鐘）。呢個係咪你哋預期？有冇時候電視自己播緊、冇人睇住？",
           "On days with play, videos ran about {h} a day (about {m} min per pick). Is that what you expect? Is the TV sometimes left playing with nobody watching?",
           ["h", "m"]),
    "Q1.noPicks": ("今個星期有玩嘅日子平均每日睇片大約 {h}。呢個係咪你哋預期？有冇時候電視自己播緊、冇人睇住？",
                   "On days with play, videos ran about {h} a day. Is that what you expect? Is the TV sometimes left playing with nobody watching?",
                   ["h"]),
    "Q1.note": ("App 只知道片播咗幾耐，唔知道有冇人睇住。",
                "The app only knows how long videos played, not whether anyone was watching.", []),
    "Q2": ("今個星期有 {n} 局冇計（家長試玩／測試）。如果有啲其實係 {name} 玩嘅，可以喺「表現 › 最近玩過」撳「計返」。",
           "{n} rounds were not counted (parent testing). If some were actually {name}'s, use 表現 › 最近玩過 › 計返.",
           ["n", "name"]),
    "Q2.one": ("今個星期有 {n} 局冇計（家長試玩／測試）。如果有啲其實係 {name} 玩嘅，可以喺「表現 › 最近玩過」撳「計返」。",
               "{n} round was not counted (parent testing). If it was actually {name}'s, use 表現 › 最近玩過 › 計返.",
               ["n", "name"]),
}

# Digits that are copy or rule constants, not metrics (path -> allowed values).
CONSTANTS = {
    "copy.page.questions": ["6"], "copy.A10.example": ["3"], "copy.A9.age": ["4"], "copy.A11.choices": ["4"],
    "copy.range.start": ["1"], "rule.memorised_rate": ["90"], "rule.minimum_rounds": ["5"], "rule.A3.keep": ["80"],
    "rule.A4b.keep": ["70"], "rule.A9.keep": ["80"], "rule.A7.step": ["10"], "rule.A2.range": ["5"],
    "rule.A3.range": ["7", "10"],
}

# ---------------------------------------------------------------- formatter (integers, half up)


def pct(k, n):
    """Whole percent of k / n, half up."""
    return (200 * k + n) // (2 * n)


def half_up(x):
    f = math.floor(x)
    return f + 1 if x - f >= 0.5 else f


def pct_of(x):
    return half_up(x * 100)


def tenths(num, den):
    """num / den to one decimal place (in tenths), half up."""
    return (20 * num + den) // (2 * den)


def minutes_of_ms(ms):
    return (ms + 30_000) // 60_000


def S(sid="", zh="", en="", tr=None, vb=None):
    return {"id": sid, "zh": zh, "en": en, "traceable": list(tr or []), "verbatim": list(vb or [])}


def v_int(value, path):
    return ("int", value, path)


def v_dec(t, path):
    return ("dec", t, path)


def v_min(minutes, path):
    return ("min", minutes, path)


def v_game(kind):
    return ("game", kind)


def v_fixed(zh, en):
    return ("fixed", zh, en)


def v_text(sentence):
    return ("text", sentence)


def v_verbatim(text):
    return ("verbatim", text)


def v_range(top, path):
    return ("range", top, path)


def render_value(v):
    """(zh, en, traceable, verbatim) of one slot value."""
    tag = v[0]
    if tag == "int":
        text = str(v[1])
        return text, text, [{"path": v[2], "value": text}], []
    if tag == "dec":
        t = v[1]
        text = "%d.%d" % (t // 10, t % 10)
        return text, text, [{"path": v[2], "value": text}], []
    if tag == "min":
        h, m = divmod(v[1], 60)
        if h:
            return ("%d 小時 %d 分" % (h, m), "%d h %02d min" % (h, m),
                    [{"path": v[2] + "#h", "value": str(h)}, {"path": v[2] + "#m", "value": str(m)}], [])
        return "%d 分鐘" % m, "%d min" % m, [{"path": v[2] + "#m", "value": str(m)}], []
    if tag == "game":
        kind = v[1]
        if kind in TITLES:
            zh, en = TITLES[kind]
            return zh, en, [], []
        return kind, kind, [], [kind]
    if tag == "fixed":
        return v[1], v[2], [], []
    if tag == "text":
        s = v[1]
        return s["zh"], s["en"], list(s["traceable"]), list(s["verbatim"])
    if tag == "verbatim":
        return v[1], v[1], [], [v[1]]
    if tag == "range":
        text = "1–%d" % v[1]
        return text, text, [{"path": "copy.range.start", "value": "1"}, {"path": v[2], "value": str(v[1])}], []
    raise ValueError(tag)


def render(tid, **values):
    zh_t, en_t, slots = TEMPLATES[tid]
    assert set(values) == set(slots), (tid, sorted(values), slots)
    parts = {}
    tr, vb = [], []
    for name in slots:
        zh, en, t, b = render_value(values[name])
        parts[name] = (zh, en)
        tr += t
        vb += b
    return S(tid, fill(zh_t, parts, 0), fill(en_t, parts, 1), tr, vb)


def fill(template, parts, lang):
    """One pass over the template, so text inside a value is never read as a placeholder."""
    out, i = [], 0
    while i < len(template):
        ch = template[i]
        if ch == "{":
            j = template.index("}", i)
            out.append(parts[template[i + 1:j]][lang])
            i = j + 1
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def join(parts, zh_sep, en_sep):
    return S("", zh_sep.join(p["zh"] for p in parts), en_sep.join(p["en"] for p in parts),
             [t for p in parts for t in p["traceable"]], [b for p in parts for b in p["verbatim"]])


def join_and(parts, zh_sep="、", zh_last=None):
    """EN 'a, b and c'; ZH joined by zh_sep (zh_last before the last item when given)."""
    if len(parts) <= 1:
        return join(parts, zh_sep, ", ")
    head = parts[:-1]
    zh = zh_sep.join(p["zh"] for p in head) + (zh_last if zh_last is not None else zh_sep) + parts[-1]["zh"]
    en = ", ".join(p["en"] for p in head) + " and " + parts[-1]["en"]
    return S("", zh, en, [t for p in parts for t in p["traceable"]], [b for p in parts for b in p["verbatim"]])


def numerals(values, path, zh_last=None):
    parts = [S("", str(n), str(n), [{"path": "%s[%d]" % (path, i), "value": str(n)}]) for i, n in enumerate(values)]
    return join_and(parts, "、", zh_last)


def game_list(kinds):
    """「a」、「b」 / "a" and "b"."""
    parts = []
    for kind in kinds:
        zh, en, _, vb = render_value(v_game(kind))
        parts.append(S("", "「%s」" % zh, "\"%s\"" % en, [], vb))
    return join_and(parts)


def stars_text(star):
    return "★" * star


def seconds_text(seconds):
    """§6.2: one decimal under 10 s, whole seconds from 10 s (both half up)."""
    if seconds < 10:
        t = half_up(seconds * 10)
        if t < 100:
            return "%d.%d" % (t // 10, t % 10)
        return "10"
    return str(half_up(seconds))


# ---------------------------------------------------------------- facts W1 / W2 do not keep


def game_key(kind, type_):
    return "%s/%s" % (kind, type_)


def row_facts(index, metrics):
    """Per (kind, type) row of one window: off-path, wrong starts, guide_clean, line-match wrong lines."""
    out = {}
    window = metrics["window"]
    for r in metrics["rounds"]:
        f = out.setdefault((r["kind"], r["type"]), {"off": 0, "units": 0, "ws": 0, "ws_n": 0, "gc": 0, "gc_n": 0,
                                                   "lines": {}, "lines_total": 0})
        res = index.result(r["round"], window.cutoff) if r["round"] else None
        if r["type"] == "practice" and res is not None and r["outcome"] == "solved":
            off = w1.int_value(res.get("off_path_count"))
            unit_key = "roads_total" if w1.FAMILY_OF.get(r["kind"]) == "roads" else "shapes_total"
            units = w1.int_value(res.get(unit_key))
            if off is not None and units is not None and w1.FAMILY_OF.get(r["kind"]) in ("lines", "shapes", "roads"):
                f["off"] += off
                f["units"] += units
            ws = w1.int_value(res.get("wrong_start"))
            if ws is not None:
                f["ws_n"] += 1
                if ws > 0:
                    f["ws"] += 1
            clean = w1.flag(res.get("guide_clean"))
            if clean is not None:
                f["gc_n"] += 1
                if clean:
                    f["gc"] += 1
        if r["type"] == "quiz" and r["kind"] == "lineMatch" and r["round"]:
            dealt = None
            for d in index.dealt:
                if d.round == r["round"] and d.countable:
                    dealt = d.event
                    break
            category = w1.string_value(dealt.get("category")) if dealt is not None else None
            for attempt in index.wrong.get(r["round"], []):
                if attempt.ts > window.cutoff:
                    continue
                count = len(w1.string_array(attempt.get("wrong_lines")))
                f["lines_total"] += count
                if category is not None and count > 0:
                    f["lines"][category] = f["lines"].get(category, 0) + count
    return out


def current_settings(index, window):
    """The last value of each setting in this week's countable deals (record order)."""
    s = {}
    for d in index.dealt:
        e = d.event
        if not d.countable or not window.contains(e.ts):
            continue
        kind = d.kind
        if kind in TAP_KINDS:
            rng = w1.int_value(e.get("range"))
            if rng is not None:
                s["range"] = rng
            voice = e.get("count_voice")
            if isinstance(voice, bool):
                s["count_voice"] = voice
            scaffold = w1.string_value(e.get("trace_scaffold"))
            if scaffold is not None:
                s["trace_scaffold"] = scaffold
            res = index.result(d.round, window.cutoff)
            if res is not None:
                level = w1.string_value(res.get("guide_level"))
                if level is not None:
                    s["guide_level"] = level
        if kind in LINE_KINDS:
            tol = w1.string_value(e.get("tolerance"))
            if tol is not None:
                s["line_tolerance"] = tol
            mix = w1.string_value(e.get("category_mix"))
            if mix is not None:
                s["category_mix"] = mix
        if kind in SHAPE_KINDS:
            hint = e.get("direction_coaching")
            if isinstance(hint, bool):
                s["direction_hint"] = hint
            slant = e.get("slant_enabled")
            if isinstance(slant, bool):
                s["slant_lines"] = slant
    return s


def mix_weight(mix, category):
    for part in mix.split(","):
        name, _, value = part.partition(":")
        if name == category:
            try:
                return int(value)
            except ValueError:
                return None
    return None


def video_ms(index, window):
    """Watched ms per video id, as W1 counts video minutes (ends in the week, missing ends from progress)."""
    play_video = {}
    for start in index.video_starts:
        play = w1.string_value(start.get("play"))
        video = w1.string_value(start.get("video"))
        if play and video is not None and play not in play_video:
            play_video[play] = video
    totals = {}
    for start in index.video_starts:
        if not window.contains(start.ts) or window.day_index(start.ts) is None:
            continue
        play = w1.string_value(start.get("play"))
        if not play or any(t <= window.cutoff for t in index.ended.get(play, [])):
            continue
        last = None
        for p in index.progress.get(play, []):
            if p.ts <= window.cutoff:
                last = p
        video = w1.string_value(start.get("video"))
        if video is not None:
            totals[video] = totals.get(video, 0) + w1.watched_ms(last.get("watched_s") if last is not None else None)
    for end in index.video_ends:
        if not window.contains(end.ts) or window.day_index(end.ts) is None:
            continue
        video = w1.string_value(end.get("video"))
        if video is None:
            video = play_video.get(w1.string_value(end.get("play")) or "")
        if video is not None:
            totals[video] = totals.get(video, 0) + w1.watched_ms(end.get("watched_s"))
    ranked = sorted(totals.items(), key=lambda kv: (-kv[1], kv[0].encode("utf-8")))
    return [(video, ms) for video, ms in ranked if minutes_of_ms(ms) >= 1][:3]


def score_tier(row, rounds):
    """W2 §5.1 / §5.2 tier of one W1 row (used for last week's tiers)."""
    if row["type"] == "quiz":
        n, has_method = row["answered"], not any(r["kind"] == row["kind"] and r["type"] == "quiz" and r["chance"] is None
                                                 for r in rounds)
    else:
        n, has_method = row["smooth_defined"], row["family"] is not None
    if not has_method:
        return "no_method"
    if n < MIN_ROUNDS or row["estimate"] is None:
        return "insufficient"
    help_heavy = row["helps_rounds"] > 0 and row["helps_total"] >= w1.HELP_HEAVY_MEAN * row["helps_rounds"]
    return w2.tier_of(row["type"], row["estimate"], row["zeroed"], help_heavy)


# ---------------------------------------------------------------- building blocks


def fact(game):
    n, k = game["n"], game["k"]
    if n < 1:
        return None
    path = "analysis.games[%s]" % game_key(game["kind"], game["type"])
    if game["type"] == "quiz":
        if k == n:
            return render("frag.quiz.all", n=v_int(n, path + ".n"))
        return render("frag.quiz", n=v_int(n, path + ".n"), k=v_int(k, path + ".k"))
    if k == n:
        return render("frag.practice.all", n=v_int(n, path + ".n"))
    return render("frag.practice", n=v_int(n, path + ".n"), k=v_int(k, path + ".k"))


def off_path_unit(kind):
    family = w1.FAMILY_OF.get(kind)
    if family == "roads":
        return "road"
    if family == "lines":
        return "line"
    if family == "shapes":
        return "shape"
    return None


def off_path_tenths(f):
    if f is None or f["units"] <= 0:
        return None
    return tenths(f["off"], f["units"])


def wrong_start_high(f):
    return f is not None and f["ws_n"] >= 1 and 10 * f["ws"] >= 4 * f["ws_n"]


def fast_rule(row):
    return row["wrong"] >= 3 and 10 * row["fast"] >= 3 * row["wrong"]


def label(table, value):
    if value in table:
        return table[value]
    return None


def setting_text(game, analysis):
    """any.settings {setting}: the first ⚙ reason that has words."""
    for reason in game["settings"]:
        if reason["reason"] == "config":
            what = reason["what"]
            if what == "assignment":
                star = reason["star"] if reason["star"] is not None else 1
                tid = "setting.on" if reason["value"] == "true" else "setting.off"
                return render(tid, game=v_game(game["kind"]), stars=v_fixed(stars_text(star), stars_text(star)))
            if what not in CONFIG_NAMES:
                continue
            zh, en, labels = CONFIG_NAMES[what]
            new = reason["value"]
            old = None
            for c in analysis["changes"]["config"]:
                if c["what"] == what and c["date"] == reason["date"] and c["new"] == new:
                    old = c["old"]
                    break
            name = v_fixed(zh, en)
            if labels is not None and new in labels:
                if old is not None and old in labels:
                    return render("setting.change", name=name, old=v_fixed(*labels[old]), new=v_fixed(*labels[new]))
                return render("setting.value", name=name, new=v_fixed(*labels[new]))
            return render("setting.name", name=name)
        if reason["reason"] == "signature":
            field = reason["field"]
            if field == "tolerance":
                group = "line" if game["kind"] in LINE_KINDS else "shape" if game["kind"] in SHAPE_KINDS else \
                    "tap" if game["kind"] in TAP_KINDS else None
                if group is None:
                    continue
                zh, en = TOLERANCE_NAMES[group]
                labels = TOLERANCE
            elif field in FIELD_NAMES:
                zh, en, labels = FIELD_NAMES[field]
            else:
                continue
            name = v_fixed(zh, en)
            if labels is not None and reason["old"] in labels and reason["new"] in labels:
                return render("setting.change", name=name, old=v_fixed(*labels[reason["old"]]),
                              new=v_fixed(*labels[reason["new"]]))
            return render("setting.name", name=name)
        if reason["reason"] == "stars":
            return render("setting.name", name=v_fixed("★★★ 題目比例", "share of ★★★ rounds"))
    return None


def any_settings(game, analysis):
    s = setting_text(game, analysis)
    return None if s is None else render("any.settings", setting=v_text(s))


# ---------------------------------------------------------------- §6.6 game comments


def comments(game, row, f, analysis):
    """(comment, short) for one game: long forms and page-4 forms. First matching template wins."""
    kind, type_ = game["kind"], game["type"]
    key = game_key(kind, type_)
    gpath = "analysis.games[%s]" % key
    mpath = "metrics.current.kinds[%s]" % key
    fpath = "facts.games[%s]" % key
    n, k = game["n"], game["k"]
    placement = game["placement"]
    settings = any_settings(game, analysis) if game["settings"] else None
    unit = off_path_unit(kind) if type_ == "practice" else None
    has_off = unit is not None and f is not None and f["units"] > 0

    def off_value():
        return v_dec(tenths(f["off"], f["units"]), fpath + ".off_path/off_path_units#1dp")

    if placement in ("top", "also_well"):
        if type_ == "quiz":
            c = v_int(pct_of(game["chance"]), gpath + ".chance#pct")
            if k == n:
                main = render("top.all", n=v_int(n, gpath + ".n"))
            else:
                main = render("top.ft", n=v_int(n, gpath + ".n"), k=v_int(k, gpath + ".k"), c=c)
            short_main = render("top.ft.short", c=c)
            extra = render("top.memorised") if game["memorised"] else settings
        else:
            if k == n:
                main = render("top.smooth.all", n=v_int(n, gpath + ".n"))
            else:
                main = render("top.smooth", n=v_int(n, gpath + ".n"), k=v_int(k, gpath + ".k"))
            if unit in ("shape", "line") and has_off and f["off"] < f["units"]:
                tid = "top.smooth.short" if unit == "shape" else "top.smooth.short.line"
                short_main = render(tid, x=off_value())
            else:
                short_main = render("top.smooth.plain")
            extra = settings
        tail = [extra] if extra is not None else []
        return [main] + tail, [short_main] + tail
    if placement in ("still_learning", "also_learning"):
        if type_ == "quiz":
            main = render("bot.ft", n=v_int(n, gpath + ".n"), k=v_int(k, gpath + ".k"))
            tag = row["top_tag"] if row["top_tag"] in TAGS else None
            tag_s = None
            if tag is not None:
                tag_s = render("bot.tag", tag=v_fixed(*TAGS[tag]), m=v_int(row["top_tag_count"], mpath + ".top_wrong_tag_count"),
                               w=v_int(row["wrong"], mpath + ".wrong_attempts"))
            fuel_s = render("bot.fuel", z=v_int(game["zeroed"], gpath + ".zeroed")) if game["zeroed"] >= 2 else None
            stars_s = None
            if game["star_rule"] is not None:
                sr = game["star_rule"]
                stars_s = render("bot.stars", k3=v_int(sr["k3"], gpath + ".star_rule.k3"),
                                 n3=v_int(sr["n3"], gpath + ".star_rule.n3"), k12=v_int(sr["k12"], gpath + ".star_rule.k12"),
                                 n12=v_int(sr["n12"], gpath + ".star_rule.n12"))
            fast_s = None
            if fast_rule(row):
                fast_s = render("bot.fast", f=v_int(row["fast"], mpath + ".fast_wrong"),
                                w=v_int(row["wrong"], mpath + ".wrong_attempts"))
            extra = next((s for s in (tag_s, fuel_s, stars_s, fast_s, settings) if s is not None), None)
            blocked = tag_s is not None or fuel_s is not None or settings is not None
            tail = [extra] if extra is not None else []
            short = ([] if blocked else [render("bot.ft.short")]) + tail
            return [main] + tail, short
        helps_rounds = row["helps_rounds"]
        if w1.FAMILY_OF.get(kind) == "tapTrace" and helps_rounds > 0:
            main = render("bot.helps", h=v_dec(tenths(row["helps_total"], helps_rounds), mpath + ".guide_helps_mean#1dp"))
        elif has_off and f["off"] >= f["units"]:
            tid = {"road": "bot.offPath", "shape": "bot.offPath.shape", "line": "bot.offPath.line"}[unit]
            main = render(tid, x=off_value())
        else:
            main = render("bot.ft.short")
        if f is not None and wrong_start_high(f):
            extra = render("bot.wrongStart", w=v_int(f["ws"], fpath + ".wrong_start"),
                           n=v_int(f["ws_n"], fpath + ".wrong_start_known"))
        else:
            extra = settings
        tail = [extra] if extra is not None else []
        return [main] + tail, [main] + tail
    entry = next(e for e in analysis["ranking"]["insufficient"] if e["kind"] == kind and e["type"] == type_)
    ipath = "analysis.ranking.insufficient[%s]" % key
    if entry["reason"] == "no_method":
        main = render("insuff.noMethod")
    elif entry["reason"] == "one_day":
        main = render("insuff.oneDay", n=v_int(entry["n"], ipath + ".n"))
    elif entry["n"] >= 1:
        if type_ == "quiz" and entry["k"] == entry["n"]:
            so_far = render("soFar.quizAll")
        elif type_ == "practice" and entry["k"] == entry["n"]:
            so_far = render("soFar.practiceAll")
        elif game["new"]:
            so_far = render("soFar.new")
        else:
            so_far = S()
        main = render("insuff.n", n=v_int(entry["n"], ipath + ".n"), soFar=v_text(so_far),
                      r=v_int(entry["more"], ipath + ".more"))
    else:
        main = render("insuff.zero", r=v_int(entry["more"], ipath + ".more"))
    return [main], [main]


# ---------------------------------------------------------------- the text model


class Context:
    pass


def build_context(events, apps, rollup, window, titles, child_name):
    c = Context()
    c.window = window
    c.titles = titles
    c.child_name = child_name
    excluded = w1.excluded_sessions(events)
    c.index = w1.Index(events, excluded, rollup)
    c.cur = w1.metrics(c.index, window)
    c.prev = w1.metrics(c.index, window.shifted(-1))
    c.analysis = w2.analyse(events, apps, rollup, window)
    c.facts = row_facts(c.index, c.cur)
    c.prev_facts = row_facts(c.index, c.prev)
    c.settings = current_settings(c.index, window)
    c.videos = video_ms(c.index, window)
    wf = w2.win_facts(c.index, rollup, window)
    c.learned = sorted(wf["learned"] | wf["learned_week"])
    c.rows = {(r["kind"], r["type"]): r for r in c.cur["rows"]}
    c.prev_rows = {(r["kind"], r["type"]): r for r in c.prev["rows"]}
    c.games = c.analysis["games"]
    c.game = {(g["kind"], g["type"]): g for g in c.games}
    first = c.index.first_event
    c.covered = [i for i in range(7) if first is not None and window.day_starts[i] < window.cutoff
                 and window.day_starts[i + 1] > first]
    totals_days = c.cur["days"]
    c.days_played = sum(1 for d in totals_days if d["counts"]["rounds"] > 0 or d["plays"] > 0)
    c.prev_days_played = sum(1 for d in c.prev["days"] if d["counts"]["rounds"] > 0 or d["plays"] > 0)
    c.game_ms = sum(d["quiz_ms"] + d["practice_ms"] for d in totals_days)
    c.video_ms = sum(d["video_ms"] for d in totals_days)
    c.visa_min = sum(d["visa_min"] for d in totals_days)
    c.plays = sum(d["plays"] for d in totals_days)
    c.excluded_total = sum(c.cur["excluded"].values())
    c.quiz_fast = sum(r["fast"] for r in c.cur["rows"] if r["type"] == "quiz")
    c.quiz_wrong = sum(r["wrong"] for r in c.cur["rows"] if r["type"] == "quiz")
    c.q1 = c.days_played > 0 and c.video_ms >= 90 * 60_000 * c.days_played
    return c


def rate_trend(comparison, path):
    change = comparison["change"]
    if change is None:
        return S()
    tid = {"same": "trend.same", "up": "trend.up", "down": "trend.down", "unsure": "trend.unsure"}[change]
    return render(tid, p0=v_int(pct(comparison["k0"], comparison["n0"]), path))


def highlights(c):
    a = c.analysis
    t = c.cur["totals"]
    out = []
    if c.days_played > 0:
        no_play = [i for i in c.covered if not (c.cur["days"][i]["counts"]["rounds"] > 0 or c.cur["days"][i]["plays"] > 0)]
        if no_play:
            days = S("", "、".join(DAY_ZH[i] for i in no_play), ", ".join(DAY_EN[i] for i in no_play))
            no_play_s = render("noPlay", days=v_text(days))
        else:
            no_play_s = S()
        if a["comparison"]["baseline"]:
            vs = S()
        else:
            diff = a["comparison"]["rounds"]["current"] - a["comparison"]["rounds"]["previous"]
            if diff > 0:
                vs = render("vs.more", d=v_int(diff, "facts.rounds_change"))
            elif diff < 0:
                vs = render("vs.fewer", d=v_int(-diff, "facts.rounds_change"))
            else:
                vs = render("vs.same")
        tid = "hl.volume.oneDay" if c.days_played == 1 else "hl.volume"
        out.append(render(tid, days=v_int(c.days_played, "metrics.current.totals.days_played"), noPlayDays=v_text(no_play_s),
                          rounds=v_int(t["rounds"], "metrics.current.totals.rounds"),
                          quiz=v_int(t["quiz_rounds"], "metrics.current.totals.quiz_rounds"),
                          practice=v_int(t["practice_rounds"], "metrics.current.totals.practice_rounds"), vsLast=v_text(vs)))
    quiz, practice = a["comparison"]["quiz"], a["comparison"]["practice"]
    has_q, has_p = quiz["n1"] >= MIN_ROUNDS, practice["n1"] >= MIN_ROUNDS
    if has_q or has_p:
        p = v_int(pct(quiz["k1"], quiz["n1"]), "metrics.current.totals.quiz_rate#pct") if has_q else None
        s = v_int(pct(practice["k1"], practice["n1"]), "metrics.current.totals.practice_rate#pct") if has_p else None
        p_trend = rate_trend(quiz, "metrics.previous.totals.quiz_rate#pct") if has_q else None
        s_trend = rate_trend(practice, "metrics.previous.totals.practice_rate#pct") if has_p else None
        if has_q and has_p:
            out.append(render("hl.rates", p=p, pTrend=v_text(p_trend), s=s, sTrend=v_text(s_trend)))
        elif has_q:
            out.append(render("hl.rates.quiz", p=p, pTrend=v_text(p_trend)))
        else:
            out.append(render("hl.rates.practice", s=s, sTrend=v_text(s_trend)))
    r = a["ranking"]
    if not r["ranked"]:
        if c.days_played > 0:
            out.append(render("hl.games.none"))
    else:
        top = (r["top"]["quiz"] + r["top"]["practice"])[:1]
        bottom = (r["still_learning"]["quiz"] + r["still_learning"]["practice"])[:1]
        top_kind = top[0] if top else None
        bottom_kind = bottom[0] if bottom else None
        top_game = None
        if top_kind is not None:
            top_game = c.game[(top_kind, "quiz")] if top_kind in r["top"]["quiz"] else c.game[(top_kind, "practice")]
        bottom_game = None
        if bottom_kind is not None:
            bottom_game = c.game[(bottom_kind, "quiz")] if bottom_kind in r["still_learning"]["quiz"] \
                else c.game[(bottom_kind, "practice")]
        if top_game and bottom_game:
            out.append(render("hl.games", top1=v_game(top_game["kind"]), top1Fact=v_text(fact(top_game)),
                              bot1=v_game(bottom_game["kind"]), bot1Fact=v_text(fact(bottom_game))))
        elif top_game:
            out.append(render("hl.games.top", top1=v_game(top_game["kind"]), top1Fact=v_text(fact(top_game))))
        elif bottom_game:
            out.append(render("hl.games.bottom", bot1=v_game(bottom_game["kind"]), bot1Fact=v_text(fact(bottom_game))))
    if c.days_played > 0 and (c.game_ms > 0 or c.video_ms > 0 or c.visa_min > 0):
        pointer = render("pointer.video", page=v_int(QUESTIONS_PAGE, "copy.page.questions")) if c.q1 else S()
        out.append(render("hl.time", g=v_min(minutes_of_ms(c.game_ms), "metrics.current.totals.game_min"),
                          v=v_min(minutes_of_ms(c.video_ms), "metrics.current.totals.video_min"),
                          visa=v_min(c.visa_min, "metrics.current.totals.visa_min"), videoPointer=v_text(pointer)))
    return out


def win_sentence(i, win):
    path = "analysis.win_candidates[%d]" % i
    wid = win["id"]
    if wid == "win.newGame":
        return render(wid, game=v_game(win["kind"]))
    if wid == "win.numeral":
        return render(wid, list=v_text(numerals(win["numerals"], path + ".numerals")))
    if wid == "win.streak":
        return render(wid, game=v_game(win["kind"]), n=v_int(win["run"], path + ".run"))
    if wid == "win.rise":
        return render(wid, game=v_game(win["kind"]), k0=v_int(win["k0"], path + ".k0"), n0=v_int(win["n0"], path + ".n0"),
                      k1=v_int(win["k1"], path + ".k1"), n1=v_int(win["n1"], path + ".n1"))
    if wid in ("win.firstSmooth", "win.firstTry"):
        return render(wid, game=v_game(win["kind"]))
    if wid == "win.cleanDay":
        return render(wid, day=v_fixed(DAY_ZH[win["day"]], DAY_EN[win["day"]]), n=v_int(win["rounds"], path + ".rounds"))
    if wid == "win.noFuelOut":
        return render(wid)
    raise ValueError(wid)


def ranking_lines(c):
    r = c.analysis["ranking"]
    out = {"status": None, "top_split": None, "still_learning_split": None, "also_well": None, "also_learning": None}
    if not r["ranked"]:
        if c.games:
            out["status"] = render("rank.notRanked")
        return out
    if not r["top"]["quiz"] and not r["top"]["practice"]:
        out["status"] = render("rank.allLearning")
    for name, key in (("top_split", "top"), ("still_learning_split", "still_learning")):
        lists = r[key]
        if lists["quiz"] or lists["practice"]:
            out[name] = render("rank.split", quiz=v_int(len(lists["quiz"]), "analysis.ranking.%s.quiz#count" % key),
                               practice=v_int(len(lists["practice"]), "analysis.ranking.%s.practice#count" % key))
    for name, key, tid in (("also_well", "also_well", "rank.alsoWell"), ("also_learning", "also_learning",
                                                                         "rank.alsoLearning")):
        items = []
        for type_ in ("quiz", "practice"):
            for kind in r[key][type_]:
                g = c.game[(kind, type_)]
                gpath = "analysis.games[%s]" % game_key(kind, type_)
                items.append(render("list.item", game=v_game(kind), k=v_int(g["k"], gpath + ".k"),
                                    n=v_int(g["n"], gpath + ".n")))
        if items:
            out[name] = render(tid, items=v_text(join(items, "、", ", ")))
    return out


def videos_sentence(c):
    if not c.videos or c.days_played <= 0:
        return None
    items = []
    for i, (video, ms) in enumerate(c.videos):
        title = c.titles.get(video, video)
        items.append(render("video.item", title=v_verbatim(title),
                            time=v_min(minutes_of_ms(ms), "facts.videos[%d].minutes" % i)))
    return render("videos.top", items=v_text(join(items, "、", ", ")))


def changes_lines(c):
    ch = c.analysis["changes"]
    if not ch["config"] and not ch["assignment"] and c.days_played > 0:
        return [render("changes.none")]
    return []


# ---------------------------------------------------------------- §7 recommendations


def still_learning(c, type_=None):
    r = c.analysis["ranking"]["still_learning"]
    out = []
    for t in ("quiz", "practice"):
        if type_ is not None and t != type_:
            continue
        for kind in r[t]:
            out.append(c.game[(kind, t)])
    return out


def ev_game_fact(g):
    return render("ev.game", game=v_game(g["kind"]), fact=v_text(fact(g)))


def ev_list(parts):
    return render("ev.list", items=v_text(join(parts, "；", "; ")))


def kinds_of(games):
    return [g["kind"] for g in games]


def family_items(c):
    items, claimed = [], set()

    def free(g):
        return (g["kind"], g["type"]) not in claimed

    def claim(games):
        for g in games:
            claimed.add((g["kind"], g["type"]))

    def add(fid, text, because, games):
        if len(items) < FAMILY_MAX:
            items.append({"id": fid, "text": text, "because": because, "kinds": kinds_of(games)})
            claim(games)

    # F6: fuel-outs ≥ 2 in a game (the most fuel-outs, then row order).
    fuel = [g for g in c.games if g["type"] == "quiz" and g["zeroed"] >= 2 and free(g)]
    if fuel:
        g = sorted(fuel, key=lambda g: -g["zeroed"])[0]
        gpath = "analysis.games[%s]" % game_key(g["kind"], g["type"])
        add("F6", render("F6", game=v_game(g["kind"])),
            ev_list([render("ev.fuel", game=v_game(g["kind"]), z=v_int(g["zeroed"], gpath + ".zeroed"))]), [g])
    # F1: a 數字・數量 quiz game is still learning.
    games = [g for g in still_learning(c, "quiz") if g["area"] == "numbers" and free(g)]
    if games:
        add("F1", render("F1"), ev_list([ev_game_fact(g) for g in games]), games)
    # F5: count-then-trace still learning or help-heavy.
    games = [g for g in c.games if g["type"] == "practice" and w1.FAMILY_OF.get(g["kind"]) == "tapTrace" and free(g)
             and (g["placement"] == "still_learning" or (g["help_heavy"] and g["n"] >= MIN_ROUNDS))]
    if games:
        parts = []
        for g in games:
            row = c.rows[(g["kind"], g["type"])]
            mpath = "metrics.current.kinds[%s]" % game_key(g["kind"], g["type"])
            if row["helps_rounds"] > 0:
                fact_s = render("frag.helps", h=v_dec(tenths(row["helps_total"], row["helps_rounds"]),
                                                     mpath + ".guide_helps_mean#1dp"))
            else:
                fact_s = fact(g) or S()
            parts.append(render("ev.game", game=v_game(g["kind"]), fact=v_text(fact_s)))
        if c.learned:
            text = render("F5", learned=v_text(numerals(c.learned, "facts.numerals_learned", " 同 ")))
        else:
            text = render("F5.plain")
        add("F5", text, ev_list(parts), games)
    # F4: a 手眼・畫線 practice game is still learning, or starts away from the green dot often.
    games = []
    for g in c.games:
        if g["type"] != "practice" or g["area"] != "pen" or not free(g):
            continue
        f = c.facts.get((g["kind"], g["type"]))
        often = f is not None and f["ws_n"] >= MIN_ROUNDS and wrong_start_high(f)
        if g["placement"] == "still_learning" or often:
            games.append(g)
    if games:
        parts = []
        for g in games:
            f = c.facts.get((g["kind"], g["type"]))
            key = game_key(g["kind"], g["type"])
            fpath = "facts.games[%s]" % key
            if g["placement"] != "still_learning":
                fact_s = render("frag.wrongStart", w=v_int(f["ws"], fpath + ".wrong_start"),
                                n=v_int(f["ws_n"], fpath + ".wrong_start_known"))
            else:
                fact_s = fact(g) or S()
                unit = off_path_unit(g["kind"])
                if unit is not None and f is not None and f["units"] > 0:
                    off = render("frag.offPath." + unit, x=v_dec(tenths(f["off"], f["units"]),
                                                                 fpath + ".off_path/off_path_units#1dp"))
                    fact_s = join([fact_s, off], "，", ", ")
            parts.append(render("ev.game", game=v_game(g["kind"]), fact=v_text(fact_s)))
        roads = games[0]["kind"] in ("lineMatchGuidedStraight", "lineMatchGuidedBridge")
        add("F4", render("F4.roads" if roads else "F4"), ev_list(parts), games)
    # F2 / F3: a 觀察・配對 / 比較・概念 quiz game is still learning.
    for fid, area in (("F2", "matching"), ("F3", "comparing")):
        games = [g for g in still_learning(c, "quiz") if g["area"] == area and free(g)]
        if games:
            add(fid, render(fid), ev_list([ev_game_fact(g) for g in games]), games)
    # F7: a quiz game is often tapped before the question finished.
    for g in c.games:
        if g["type"] != "quiz" or not free(g):
            continue
        row = c.rows[(g["kind"], g["type"])]
        if fast_rule(row):
            mpath = "metrics.current.kinds[%s]" % game_key(g["kind"], g["type"])
            add("F7", render("F7"), ev_list([render("ev.fast", game=v_game(g["kind"]),
                                                    f=v_int(row["fast"], mpath + ".fast_wrong"),
                                                    w=v_int(row["wrong"], mpath + ".wrong_attempts"))]), [g])
            break
    praise = None
    shown = c.analysis["wins"]
    if shown:
        praise = render("F8", winObject=v_fixed(*win_object(shown)))
    none = render("rec.none") if not items and c.days_played > 0 else None
    return items, praise, none


def win_object(shown):
    quiz_wins = []
    for win in shown:
        if win["id"] in ("win.streak", "win.firstTry", "win.cleanDay", "win.noFuelOut") or \
                (win["id"] == "win.rise" and win["type"] == "quiz"):
            quiz_wins.append(win)
    win = quiz_wins[0] if quiz_wins else shown[0]
    if win["id"] == "win.numeral":
        return WIN_OBJECT_NUMERALS
    if win["id"] in ("win.cleanDay", "win.noFuelOut"):
        return WIN_OBJECT_QUESTIONS
    return WIN_OBJECT.get(win["kind"], WIN_OBJECT_QUESTIONS)


def app_items(c):
    a = c.analysis
    items, claimed = [], set()
    s = c.settings

    def free(g):
        return (g["kind"], g["type"]) not in claimed

    def add(item, games):
        if len(items) < APP_MAX:
            item["kinds"] = kinds_of(games)
            items.append(item)
            for g in games:
                claimed.add((g["kind"], g["type"]))

    def item(aid, text, because, check, settings=(), current=None, suggested=None):
        return {"id": aid, "text": text, "because": because, "check": check, "settings": list(settings),
                "current": current, "suggested": suggested}

    def set_value(setting, old, new):
        return render("set.value", setting=v_fixed(setting, setting), **{"from": v_fixed(old, old), "to": v_fixed(new, new)})

    def set_to(setting, new):
        return render("set.to", setting=v_fixed(setting, setting), to=v_fixed(new, new))

    def ranked_rows(area, type_="quiz"):
        return [g for g in c.games if g["area"] == area and g["type"] == type_]

    # A5: fixed questions right ≥ 90 % over ≥ 10 rounds (W2 memorised), unless the app already generates them.
    games = [g for g in c.games if g["memorised"] and free(g) and g["kind"] not in GENERATED]
    if games:
        tid = "A5.one" if len(games) == 1 else "A5"
        text = render(tid, games=v_text(game_list(kinds_of(games))), rate=v_int(90, "rule.memorised_rate"))
        ratios = []
        for g in games:
            gpath = "analysis.games[%s]" % game_key(g["kind"], g["type"])
            ratios.append(render("ev.ratio", game=v_game(g["kind"]), k=v_int(g["k"], gpath + ".k"),
                                 n=v_int(g["n"], gpath + ".n")))
        kinds = ", ".join(kinds_of(games))
        add(item("A5", text, render("A5.because", items=v_text(join(ratios, "；", "; "))), render("A5.check"),
                 [render("set.generated", kinds=v_verbatim(kinds))], "fixed_v0", "generated"), games)
    # A10: build more of a quiz area.
    lowest_now = lowest_area(c.cur)
    lowest_before = lowest_area(c.prev)
    for area in QUIZ_AREAS:
        quiz_games = [g for g in c.games if g["area"] == area and g["type"] == "quiz" and free(g)]
        learning = [g for g in still_learning(c, "quiz") if g["area"] == area]
        lowest = lowest_now == area and lowest_before == area
        if not quiz_games or not (lowest or len(learning) >= 2):
            continue
        name = v_fixed(*AREA_NAMES[area])
        if area == "numbers":
            text = render("A10.numbers", area=name, n=v_int(3, "copy.A10.example"))
        else:
            text = render("A10", area=name)
        if lowest:
            now, before = c.cur["areas"][area], c.prev["areas"][area]
            because = render("A10.because.lowest", area=name,
                             p1=v_int(pct(now["first_try"], now["answered"]), "metrics.current.areas[%s].quiz_rate#pct" % area),
                             c=v_int(pct_of(now["expected"] / now["expected_answered"]),
                                     "metrics.current.areas[%s].quiz_chance_mean#pct" % area),
                             p0=v_int(pct(before["first_try"], before["answered"]),
                                      "metrics.previous.areas[%s].quiz_rate#pct" % area))
        else:
            because = render("A10.because.learning", area=name,
                             count=v_int(len(learning), "analysis.ranking.still_learning.quiz[area=%s]#count" % area),
                             games=v_text(game_list(kinds_of(learning))))
        add(item("A10", text, because, render("A10.check", area=name)), quiz_games)
    # A1: count games still learning and 揀啱數 not played this week.
    pick_played = any(g["kind"] in ("tapCountPick", "tapCountPickEnglish") for g in c.games)
    games = [g for g in still_learning(c, "quiz") if g["kind"] in ("countVehicles", "moreFewer") and free(g)]
    if games and not pick_played:
        pick = v_game("tapCountPick")
        add(item("A1", render("A1", pick=pick),
                 render("A1.because", items=v_text(join([ev_game_fact(g) for g in games], "；", "; ")), pick=pick),
                 render("A1.check", game=v_game(games[0]["kind"]), pick=pick, min=v_int(MIN_ROUNDS, "rule.minimum_rounds")),
                 [render("set.assignment", kind=v_verbatim("tapCountPick"), stars=v_fixed("★", "★"),
                         **{"from": v_fixed("off", "off"), "to": v_fixed("on", "on")})], "off", "on"), games)
    # A4: count-then-trace help-heavy or smooth < 50 %.
    for g in c.games:
        if g["type"] != "practice" or w1.FAMILY_OF.get(g["kind"]) != "tapTrace" or not free(g):
            continue
        if g["n"] < MIN_ROUNDS or not (g["help_heavy"] or 2 * g["k"] < g["n"]):
            continue
        text = setting = current = suggested = None
        level = s.get("guide_level")
        scaffold = s.get("trace_scaffold")
        if level != "more":
            if level in GUIDANCE:
                text = render("A4", current=v_fixed(*GUIDANCE[level]), suggested=v_fixed(*GUIDANCE["more"]))
                setting = set_value("TapCountSettings.guidance", level, "more")
            else:
                text = render("A4.to", suggested=v_fixed(*GUIDANCE["more"]))
                setting = set_to("TapCountSettings.guidance", "more")
            current, suggested = level, "more"
        elif scaffold == "outline":
            text = render("A4.scaffold", current=v_fixed(*SCAFFOLD["outline"]), suggested=v_fixed(*SCAFFOLD["dots"]))
            setting = set_value("TapCountSettings.traceScaffold", "outline", "dots")
            current, suggested = "outline", "dots"
        if text is None:
            continue
        row = c.rows[(g["kind"], g["type"])]
        fact_s = fact(g) or S()
        if row["helps_rounds"] > 0:
            mpath = "metrics.current.kinds[%s]" % game_key(g["kind"], g["type"])
            helps = render("frag.helps", h=v_dec(tenths(row["helps_total"], row["helps_rounds"]), mpath + ".guide_helps_mean#1dp"))
            fact_s = join([fact_s, helps], "，", ", ")
        because = ev_list([render("ev.game", game=v_game(g["kind"]), fact=v_text(fact_s))])
        add(item("A4", text, because, render("A4.check"), [setting], current, suggested), [g])
        break
    # A6: guided roads smooth < 50 % with ≥ 2 off-path per road.
    for g in c.games:
        if g["type"] != "practice" or g["kind"] not in ("lineMatchGuidedStraight", "lineMatchGuidedBridge") or not free(g):
            continue
        f = c.facts.get((g["kind"], g["type"]))
        if g["n"] < MIN_ROUNDS or 2 * g["k"] >= g["n"] or f is None or f["units"] <= 0 or f["off"] < 2 * f["units"]:
            continue
        row = c.rows[(g["kind"], g["type"])]
        high_stars = [star for star in (2, 3) if row["stars"][star - 1]["rounds"] > 0]
        bridge = g["kind"] == "lineMatchGuidedBridge" and bool(high_stars)
        tol = s.get("line_tolerance")
        wide = v_fixed(*TOLERANCE["wide"])
        lines = []
        current = suggested = None
        if bridge:
            stars = "/".join(stars_text(star) for star in high_stars)
            lines.append(render("set.assignment", kind=v_verbatim("lineMatchGuidedBridge"), stars=v_fixed(stars, stars),
                                **{"from": v_fixed("on", "on"), "to": v_fixed("off", "off")}))
            current, suggested = "on", "off"
        if bridge and tol == "wide":
            text = render("A6.bridge", wide=wide)
        elif bridge and tol in TOLERANCE:
            text = render("A6.bridge.wide", current=v_fixed(*TOLERANCE[tol]), wide=wide)
            lines.append(set_value("LineMatchSettings.tolerance", tol, "wide"))
        elif bridge:
            text = render("A6.bridge.only")
        elif tol in TOLERANCE and tol != "wide":
            text = render("A6.wide", current=v_fixed(*TOLERANCE[tol]), wide=wide)
            lines.append(set_value("LineMatchSettings.tolerance", tol, "wide"))
            current, suggested = tol, "wide"
        else:
            continue
        key = game_key(g["kind"], g["type"])
        off = render("frag.offPath.road", x=v_dec(tenths(f["off"], f["units"]),
                                                  "facts.games[%s].off_path/off_path_units#1dp" % key))
        because = ev_list([render("ev.game", game=v_game(g["kind"]), fact=v_text(join([fact(g), off], "，", ", ")))])
        add(item("A6", text, because, render("A6.check"), lines, current, suggested), [g])
        break
    # A7: 連一連 · 自己配 still learning with wrong lines in one category.
    for g in still_learning(c, "quiz"):
        if g["kind"] != "lineMatch" or not free(g):
            continue
        f = c.facts.get((g["kind"], g["type"]))
        if f is None or f["lines_total"] < 4:
            continue
        best = None
        for category in CATEGORY_ORDER:
            m = f["lines"].get(category, 0)
            if best is None or m > best[1]:
                best = (category, m)
        if best is None or 10 * best[1] < 6 * f["lines_total"]:
            continue
        weight = mix_weight(s.get("category_mix", ""), best[0])
        if weight is None or weight <= 0:
            continue
        lowered = max(0, weight - 10)
        cat = v_fixed(*CATEGORY[best[0]])
        key = game_key(g["kind"], g["type"])
        setting = render("set.weight", setting=v_fixed("LineMatchSettings.weight[%s]" % best[0], "LineMatchSettings.weight[%s]" % best[0]),
                         **{"from": v_int(weight, "facts.settings.category_mix[%s]" % best[0]),
                            "to": v_int(lowered, "facts.settings.category_mix[%s]-10" % best[0])})
        add(item("A7", render("A7", game=v_game(g["kind"]), category=cat, step=v_int(10, "rule.A7.step")),
                 render("A7.because", m=v_int(best[1], "facts.games[%s].wrong_lines[%s]" % (key, best[0])),
                        w=v_int(f["lines_total"], "facts.games[%s].wrong_lines_total" % key), category=cat),
                 render("A7.check", game=v_game(g["kind"])), [setting], str(weight), str(lowered)), [g])
        break
    # A2: 點數 smooth < 60 % (recounts common): narrow the numbers.
    for g in c.games:
        if g["type"] != "practice" or w1.FAMILY_OF.get(g["kind"]) != "tapAll" or not free(g):
            continue
        if g["n"] < MIN_ROUNDS or 10 * g["k"] >= 6 * g["n"]:
            continue
        rng = s.get("range")
        if rng is None or rng <= 5:
            continue
        voice_off = s.get("count_voice") is False
        tid = "A2.voice" if voice_off else "A2"
        text = render(tid, **{"from": v_range(rng, "facts.settings.range"), "to": v_range(5, "rule.A2.range")})
        lines = [render("set.range", setting=v_fixed("TapCountSettings.range", "TapCountSettings.range"),
                        **{"from": v_range(rng, "facts.settings.range"), "to": v_range(5, "rule.A2.range")})]
        if voice_off:
            lines.append(set_value("TapCountSettings.countVoice", "off", "on"))
        key = game_key(g["kind"], g["type"])
        because = render("A2.because", game=v_game(g["kind"]), n=v_int(g["n"], "analysis.games[%s].n" % key),
                         r=v_int(g["n"] - g["k"], "facts.games[%s].recount_rounds" % key))
        add(item("A2", text, because, render("A2.check"), lines, str(rng), "5"), [g])
        break
    # A3: 點數 smooth ≥ 90 % two weeks running at 1–5 or 1–7: widen the numbers.
    for g in c.games:
        if g["type"] != "practice" or w1.FAMILY_OF.get(g["kind"]) != "tapAll" or not free(g):
            continue
        k0, n0 = g["wow"]["k0"], g["wow"]["n0"]
        if g["n"] < MIN_ROUNDS or n0 < MIN_ROUNDS or 10 * g["k"] < 9 * g["n"] or 10 * k0 < 9 * n0:
            continue
        rng = s.get("range")
        if rng not in (5, 7):
            continue
        nxt = 7 if rng == 5 else 10
        key = game_key(g["kind"], g["type"])
        gpath = "analysis.games[%s]" % key
        text = render("A3", **{"from": v_range(rng, "facts.settings.range"), "to": v_range(nxt, "rule.A3.range")})
        setting = render("set.range", setting=v_fixed("TapCountSettings.range", "TapCountSettings.range"),
                         **{"from": v_range(rng, "facts.settings.range"), "to": v_range(nxt, "rule.A3.range")})
        because = render("A3.because", game=v_game(g["kind"]), k1=v_int(g["k"], gpath + ".k"), n1=v_int(g["n"], gpath + ".n"),
                         k0=v_int(k0, gpath + ".wow.k0"), n0=v_int(n0, gpath + ".wow.n0"))
        add(item("A3", text, because, render("A3.check", keep=v_int(80, "rule.A3.keep")), [setting], str(rng),
                 str(nxt)), [g])
        break
    # A4b: count-then-trace traced without help ≥ 80 % two weeks running.
    for g in c.games:
        if g["type"] != "practice" or w1.FAMILY_OF.get(g["kind"]) != "tapTrace" or not free(g):
            continue
        f = c.facts.get((g["kind"], g["type"]))
        p = c.prev_facts.get((g["kind"], g["type"]))
        if f is None or p is None or f["gc_n"] < MIN_ROUNDS or p["gc_n"] < MIN_ROUNDS:
            continue
        if 10 * f["gc"] < 8 * f["gc_n"] or 10 * p["gc"] < 8 * p["gc_n"]:
            continue
        level = s.get("guide_level")
        scaffold = s.get("trace_scaffold")
        if level != "less":
            if level in GUIDANCE:
                text = render("A4b", current=v_fixed(*GUIDANCE[level]), suggested=v_fixed(*GUIDANCE["less"]))
                setting = set_value("TapCountSettings.guidance", level, "less")
            else:
                text = render("A4b.to", suggested=v_fixed(*GUIDANCE["less"]))
                setting = set_to("TapCountSettings.guidance", "less")
            current, suggested = level, "less"
        elif scaffold == "dots":
            text = render("A4b.scaffold", current=v_fixed(*SCAFFOLD["dots"]), suggested=v_fixed(*SCAFFOLD["outline"]))
            setting = set_value("TapCountSettings.traceScaffold", "dots", "outline")
            current, suggested = "dots", "outline"
        else:
            continue
        key = game_key(g["kind"], g["type"])
        because = render("A4b.because", game=v_game(g["kind"]), k1=v_int(f["gc"], "facts.games[%s].guide_clean" % key),
                         n1=v_int(f["gc_n"], "facts.games[%s].guide_clean_known" % key),
                         k0=v_int(p["gc"], "facts.games[%s].previous_guide_clean" % key),
                         n0=v_int(p["gc_n"], "facts.games[%s].previous_guide_clean_known" % key))
        add(item("A4b", text, because, render("A4b.check", keep=v_int(70, "rule.A4b.keep")), [setting], current,
                 suggested), [g])
        break
    # A8: shapes often started away from the green dot with the direction hint off.
    for g in c.games:
        if g["type"] != "practice" or g["kind"] not in ("traceLines", "traceShapesDotted", "traceShapesArrows") or not free(g):
            continue
        f = c.facts.get((g["kind"], g["type"]))
        if f is None or f["ws_n"] < MIN_ROUNDS or not wrong_start_high(f) or s.get("direction_hint") is not False:
            continue
        key = game_key(g["kind"], g["type"])
        because = ev_list([render("ev.game", game=v_game(g["kind"]),
                                  fact=v_text(render("frag.wrongStart", w=v_int(f["ws"], "facts.games[%s].wrong_start" % key),
                                                     n=v_int(f["ws_n"], "facts.games[%s].wrong_start_known" % key))))])
        add(item("A8", render("A8"), because, render("A8.check"),
                 [set_value("ShapeTraceSettings.directionHint", "off", "on")], "off", "on"), [g])
        break
    # A9: 畫直線 smooth ≥ 90 % over ≥ 10 rounds in two weeks, slant lines off.
    for g in c.games:
        if g["type"] != "practice" or g["kind"] != "traceLines" or not free(g):
            continue
        k2, n2 = g["k"] + g["wow"]["k0"], g["n"] + g["wow"]["n0"]
        if n2 < 10 or 10 * k2 < 9 * n2 or s.get("slant_lines") is not False:
            continue
        key = game_key(g["kind"], g["type"])
        because = render("A9.because", game=v_game(g["kind"]), n=v_int(n2, "facts.games[%s].two_weeks_n" % key),
                         k=v_int(k2, "facts.games[%s].two_weeks_k" % key))
        add(item("A9", render("A9", age=v_int(4, "copy.A9.age")), because,
                 render("A9.check", game=v_game(g["kind"]), keep=v_int(80, "rule.A9.keep")),
                 [set_value("ShapeTraceSettings.slantLines", "off", "on")], "off", "on"), [g])
        break
    # A11: every ranked quiz game of an area going well two weeks running.
    for area in QUIZ_AREAS:
        now = [g for g in c.games if g["area"] == area and g["type"] == "quiz"
               and g["tier"] in ("going_well", "learning", "needs_practice")]
        before = [r for r in c.prev["rows"] if r["area"] == area and r["type"] == "quiz"
                  and score_tier(r, c.prev["rounds"]) in ("going_well", "learning", "needs_practice")]
        if not now or not before:
            continue
        if any(g["tier"] != "going_well" for g in now) or any(score_tier(r, c.prev["rounds"]) != "going_well" for r in before):
            continue
        if any(not free(g) for g in now):
            continue
        name = v_fixed(*AREA_NAMES[area])
        add(item("A11", render("A11", area=name, choices=v_int(4, "copy.A11.choices")),
                 render("A11.because", area=name, games=v_text(game_list(kinds_of(now)))), render("A11.check")), now)
    # A12: across quiz games, ≥ 30 % of wrong taps before the question finished.
    if c.quiz_wrong >= 3 and 10 * c.quiz_fast >= 3 * c.quiz_wrong:
        add(item("A12", render("A12"), render("A12.because", f=v_int(c.quiz_fast, "facts.quiz_fast_wrong"),
                                              w=v_int(c.quiz_wrong, "facts.quiz_wrong_attempts")),
                 render("A12.check")), [])
    none = render("app.none") if not items and c.days_played > 0 else None
    return items, none


def lowest_area(m):
    """The quiz area with the lowest chance-adjusted rate (≥ 10 rounds with a chance), among ≥ 2 such areas."""
    best, count = None, 0
    for area in QUIZ_AREAS:
        g = m["areas"][area]
        adj = w1.adjusted(g["expected_first_try"], g["expected_answered"], g["expected"])
        if g["expected_answered"] < 10 or adj is None:
            continue
        count += 1
        if best is None or adj < best[1]:
            best = (area, adj)
    return best[0] if best is not None and count >= 2 else None


def per_day_minutes(c):
    """Video minutes per day played (half up), or None without a day played."""
    if c.days_played <= 0:
        return None
    return (2 * c.video_ms + c.days_played * 60_000) // (2 * c.days_played * 60_000)


def per_play_minutes(c):
    """Video minutes per play (half up), or None without a play."""
    if c.plays <= 0:
        return None
    return (2 * c.video_ms + c.plays * 60_000) // (2 * c.plays * 60_000)


def questions(c):
    out = []
    if c.q1:
        h = v_min(per_day_minutes(c), "facts.video_minutes_per_day_played")
        if c.plays > 0:
            q = render("Q1", h=h, m=v_int(per_play_minutes(c), "facts.video_minutes_per_play"))
        else:
            q = render("Q1.noPicks", h=h)
        out.append({"id": "Q1", "question": q, "note": render("Q1.note")})
    counted = c.cur["totals"]["rounds"]
    if c.excluded_total > 0 and 5 * c.excluded_total >= counted + c.excluded_total:
        tid = "Q2.one" if c.excluded_total == 1 else "Q2"
        out.append({"id": "Q2", "question": render(tid, n=v_int(c.excluded_total, "metrics.current.excluded_rounds.total"),
                                                   name=v_verbatim(c.child_name)), "note": None})
    return out


# ---------------------------------------------------------------- facts block and the model


def facts_json(c):
    games = []
    for row in c.cur["rows"]:
        key = (row["kind"], row["type"])
        f = c.facts.get(key)
        p = c.prev_facts.get(key)
        g = c.game[key]
        entry = {"kind": row["kind"], "type": row["type"], "off_path": f["off"], "off_path_units": f["units"],
                 "wrong_start": f["ws"], "wrong_start_known": f["ws_n"], "guide_clean": f["gc"],
                 "guide_clean_known": f["gc_n"],
                 "previous_guide_clean": p["gc"] if p is not None else 0,
                 "previous_guide_clean_known": p["gc_n"] if p is not None else 0,
                 "wrong_lines": dict(f["lines"]), "wrong_lines_total": f["lines_total"],
                 "two_weeks_n": g["n"] + g["wow"]["n0"], "two_weeks_k": g["k"] + g["wow"]["k0"],
                 "recount_rounds": g["n"] - g["k"] if w1.FAMILY_OF.get(row["kind"]) == "tapAll" and row["type"] == "practice"
                 else 0}
        games.append(entry)
    settings = {}
    for name in ("range", "count_voice", "trace_scaffold", "guide_level", "line_tolerance", "category_mix",
                 "direction_hint", "slant_lines"):
        settings[name] = c.settings.get(name)
    videos = [{"video": video, "watched_ms": ms, "minutes": minutes_of_ms(ms), "title": c.titles.get(video, video)}
              for video, ms in c.videos]
    rounds = c.analysis["comparison"]["rounds"]
    return {
        "games": games,
        "settings": settings,
        "videos": videos,
        "numerals_learned": list(c.learned),
        "rounds_change": abs(rounds["current"] - rounds["previous"]),
        "days_without_play": [i for i in c.covered if not (c.cur["days"][i]["counts"]["rounds"] > 0
                                                           or c.cur["days"][i]["plays"] > 0)],
        "video_ms": c.video_ms,
        "plays": c.plays,
        "video_minutes_per_day_played": per_day_minutes(c),
        "video_minutes_per_play": per_play_minutes(c),
        "quiz_fast_wrong": c.quiz_fast,
        "quiz_wrong_attempts": c.quiz_wrong,
    }


def build(events, apps, rollup, window, titles, child_name=CHILD_NAME):
    c = build_context(events, apps, rollup, window, titles, child_name)
    a = c.analysis
    countable = c.days_played > 0
    games = []
    for g in c.games:
        row = c.rows[(g["kind"], g["type"])]
        long_, short = comments(g, row, c.facts.get((g["kind"], g["type"])), a)
        games.append({"kind": g["kind"], "type": g["type"], "placement": g["placement"], "fact": fact(g),
                      "comment": long_, "short": short})
    family, praise, family_none = family_items(c) if countable else ([], None, None)
    app, app_none = app_items(c) if countable else ([], None)
    candidates = [win_sentence(i, w) for i, w in enumerate(a["win_candidates"])]
    return {
        "text": TEXT,
        "analysis": a["analysis"],
        "builder": a["builder"],
        "time_zone": a["time_zone"],
        "week_start": a["week_start"],
        "data_until": a["data_until"],
        "child_name": child_name,
        "empty": None if countable else render("wr.empty"),
        "highlights": highlights(c),
        "wins": candidates[:WIN_MAX],
        "win_candidates": candidates,
        "games": games,
        "ranking": ranking_lines(c),
        "videos": videos_sentence(c),
        "changes": changes_lines(c),
        "recommendations": {"family": family, "praise": praise, "family_none": family_none, "app": app,
                            "app_none": app_none, "questions": questions(c)},
        "facts": facts_json(c),
    }


def main():
    if len(sys.argv) not in (4, 5):
        raise SystemExit(__doc__)
    folder, week_start, data_until = sys.argv[1:4]
    titles = {}
    if len(sys.argv) == 5:
        with open(sys.argv[4], encoding="utf-8") as f:
            titles = json.load(f)
    events, apps, skipped = w2.read_folder(folder)
    rollup_path = os.path.join(folder, "rollup-v1.json")
    rollup = {}
    if os.path.exists(rollup_path):
        with open(rollup_path, encoding="utf-8") as f:
            rollup = json.load(f)
    cutoff = w1.parse_ts(data_until)
    if cutoff is None:
        raise SystemExit("data_until must look like 2026-10-25T13:00:00.000Z")
    model = build(events, apps, rollup, w1.Window.containing(week_start, cutoff), titles)
    sys.stderr.write("%d events, %d skipped lines\n" % (len(events), skipped))
    sys.stdout.write(w1.encode(model) + "\n")


if __name__ == "__main__":
    main()
