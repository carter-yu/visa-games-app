# ADR 0023: Weekly report text (W3)

Date: 2026-10-26
Status: Draft PR, source implementation awaiting Mac verification

## Context

Slice W3 of the weekly report (`visa-games-design/weekly-report/design.md` §12) turns the W1 metrics (ADR 0021) and the W2 analysis (ADR 0022, PR #37, `9f1087b`) into the report's sentences: the §6 templates, the page-1 highlights, the wins text, the game comments with their page-4 `.short` forms, the §7 recommendations and the §7.3 questions, in Hong Kong Traditional Chinese and English. Acceptance is the ten §6.7 sample sentences rendered from the §5.6 fixture. D6 B (deterministic templates; no LLM rewrite before W6), D7 (the child's name is Cedric) and D8 B (top 3 video titles by watched minutes) are locked. HTML/SVG (W4), the PDF and the 表現 row (W5), the nickname setting (W5b) and the rewrite (W6) are later slices.

## Decision

`WeeklyReportTextBuilder.build(events:rollup:window:childName:videoTitles:)` is pure. It reads the same index as W1 and W2, calls the unchanged W2 `analyse`, collects the few facts W1 and W2 do not keep (`WeeklyTextFacts`) and returns `WeeklyReportText`. `canonicalJSON()` uses the W1 `WeeklyJSON` rules. W1 and W2 code and goldens are unchanged.

Every sentence comes from one template in `WeeklyTemplates` (154 entries): an id, typed slots, the Chinese and English text and the precondition in words. Selection is code in `WeeklyReportText`: the first matching template in a fixed order wins. All numbers go through one formatter (`WeeklyFormat`), are rounded half up in integers and are recorded per sentence as `(path, value)`. Rendering problems (unknown id, missing or mistyped slot) are collected on the sentence, never a crash; the checks require none.

The goldens come from `Tests/VisaCoreTests/Fixtures/weekly-ranking-5.6/reference_text.py`, an independent Python reading of these rules on top of the W1 and W2 references. All ten §6.7 sentences come out of the §5.6 fixture exactly, in both languages; the fixture records were not changed.

Choices where the design left room:

**Model, numbers and checks**

- **Text JSON.** Every sentence is `{id, zh, en, traceable, verbatim}`. A `facts` block holds the W3-only facts (off-path, wrong starts, `guide_clean`, 連一連 wrong lines per category, this week's setting values, video minutes, numerals learned and a few derived counts), so every `facts.` path resolves.
- **Traceable paths.** `metrics.` points into the W1 JSON, `analysis.` into the W2 JSON and `facts.` into the facts block. Suffixes say how a value was printed: `#pct` whole percent, `#1dp` one decimal, `#h` / `#m` hours and minutes, `#count` number of entries. The value is the number as printed, without leading zeros.
- **Copy and rule digits.** Digits that are copy or rule constants have `copy.` / `rule.` paths with fixed allowed values (`WeeklyTextCatalog.constants`): page 6 in the video pointer, 「邊個係 3？」, 「4 歲半」, 「4 個選擇」, the 1 of 「1–N」, 90 %, 5 rounds, 80 % / 70 %, the step of 10 and the ranges 5 / 7 / 10.
- **Verbatim.** Video titles, the child's name, ids of unknown game kinds and kind ids in setting lines are inserted unchanged. They are listed per sentence, and the number, banned-word and Traditional-only checks skip them (§11: titles are shown as recorded).
- **Rounding.** Percent of k / n and tenths are computed in integers, half up. A chance percent is the half-up rounding of the stored double. Minutes are rounded from milliseconds. The formatter prints 「2 小時 7 分」 / 「45 分鐘」, and "2 h 07 min" / "45 min" (the mockup's English). Seconds are formatted with one decimal under 10 s and as whole seconds from 10 s; no W3 sentence prints seconds.
- **Quotes.** English uses straight quotes, as in §6.7, not the mockup's curly quotes.
- **Traditional-only list.** `Tests/VisaCoreTests/Fixtures/traditional-check/simplified-only.txt` holds 2,708 characters, made by `make_simplified_list.py` with `opencc-python-reimplemented` 0.1.7. The rule is the one in `mockups/check_traditional.py`: s2hk changes the character and t2s keeps it, over U+3400–4DBF, U+4E00–9FFF and U+F900–FAFF. 吓 and 晒 are left out. HK glyph variants are not listed, so game titles keep the app's 搵. The list has no compatibility ideographs, so Swift's canonical `Character` equality matches code points. `check_traditional.py` finds no Simplified characters in the new files; it reports only the allowed 搵 variant.

**Page 1 (§6.4)**

- **hl.volume.** {quiz} and {practice} are counted quiz and practice rounds, so they add up to {rounds}. {noPlayDays} lists the covered days (W1 coverage) without a counted round or play. {vsLast} uses the mockup's words 「，比上星期多／少 N 局」 / 「，同上星期一樣」. It is left out when W2 finds no earlier record (`baseline`). No 「明顯」 word is used on counts here; the design gives none. `hl.volume.oneDay` only fixes the English singular.
- **hl.rates.** Shown when answered quiz rounds ≥ 5 or smooth-defined practice rounds ≥ 5. When only one side has 5, `hl.rates.quiz` / `hl.rates.practice` drop the other clause. The trend fragment follows the W2 total rate change (`null` prints none). The English trend words come from the mockup.
- **hl.games.** top1 and bot1 are the first entries of the going-well and still-learning lists, 答題 first (W2 order). The facts use the mockup's 「N 局全部一次答啱」 / 「N 局入面 K 局一次答啱」 forms. The fallback `hl.games.none` (English written) is used when W2 says not ranked, as page 4 does. `hl.games.top` / `hl.games.bottom` drop a clause when one list is empty.
- **hl.time and the video pointer.** The video pointer 「睇片時間第 6 頁…」 is added only when Q1 is asked.
- **Empty week.** With no countable play, `wr.empty` 「今個星期未有紀錄。」 replaces everything else (§3; English written). The questions are still built.
- **D8 B videos.** `videos.top` (copy written; the design has none) lists up to 3 videos by watched time this week, counted like W1's video minutes per video id: a `video_end` in the week, else the play's last `video_progress`. Each needs at least one rounded minute; ties go to the video id. Titles come from the caller's id → label map (the app's `parentLabel`), else the id.

**Wins (§6.5)**

- **All candidates.** A sentence is rendered for every W2 candidate; the first 3 are shown. §6.7 sample 8 is the fifth candidate.
- **Numerals.** Lists print as 「3、5」 / "3 and 5".

**Game comments (§6.6)**

- **Forms.** Each game gets long forms (`comment`) and page-4 forms (`short`), at most 1 main + 1 extra, by its W2 place: going well (top, also well), still learning (still learning, also learning) or 數據唔夠.
- **Extra order.** First match wins in table order. Still-learning quiz: `bot.tag`, `bot.fuel`, `bot.stars`, `bot.fast`, `any.settings`. Going-well quiz: `top.memorised`, `any.settings`. Still-learning practice: `bot.wrongStart`, `any.settings`.
- **Dropping bot.ft.short.** The page-4 main `bot.ft.short` is dropped when a tag, ⚙ or fuel extra applies (its precondition).
- **bot.tag.** Used only when W1's top tag has an approved name (perf-review §8.5). W1's choice of top tag is kept (ties go to UTF-8 order, ADR 0021). In the §5.6 week, 空車位's top tag `occupied` has no approved name, so it gets no `bot.tag`.
- **Main templates.** `top.all` comes before `top.ft` (k == n). `top.smooth.all` is the derived practice counterpart. {detail} (`top.smooth`) and {learnedNote} (`bot.helps`) have no copy and are left out; §6.7 sample 5 has no note.
- **top.smooth.short.** Shapes and lines only, and only with less than 1 off-path per shape or line, compared exactly. Otherwise the mockup's 「做得好順。」 / "Going smoothly." (`top.smooth.plain`). Ids: `top.smooth.short` (shapes) and `top.smooth.short.line`.
- **bot.offPath.** Needs at least 1 off-path per road, shape or line, compared exactly. Off-path = Σ `off_path_count` / Σ `roads_total` or `shapes_total` over solved rounds that wrote both. The design's road form keeps the id `bot.offPath`; the shape and line forms reuse the design's unit words. The `per_shape` {hardest} clause is deferred: there are no shape-name strings for it, and the fixtures have no `per_shape` rows.
- **Other practice mains.** `bot.helps` is used for count-then-trace with `guide_helps` data. Other still-learning practice rows use `bot.ft.short` (the mockup does the same).
- **Rules.** `bot.wrongStart`: `wrong_start` > 0 in ≥ 40 % of the solved rounds that wrote it. `bot.fast`: ≥ 3 wrong taps, ≥ 30 % of them fast.
- **any.settings {setting}.** The first ⚙ reason that has words:
  - a `config_change` with a known `what`: name, then old → new. The old value comes from W2's page-5 settings list (the earlier `config_change` value), with the app's labels (`LineMatchTolerance` 窄 / 標準 / 闊, 描數字提示 多啲 / 標準 / 少啲, …);
  - a deal-signature field by name, with labels where they exist;
  - a star assignment: 「開咗「game」★」 / "turned on ★ for "game"";
  - a ★★★ share move: its name only.
  連一連 tolerance is named 「連一連寬容度」 / "Line Match tolerance" as in §6.7 (the settings screen says 畫線寬容度).
- **數據唔夠.**
  - `insuff.n` uses W2's n (§5.1). With n = 0, `insuff.zero` prints the design sentence without its 「玩咗 n 次」 clause.
  - {soFar} is 「，全部一次答啱」 (quiz, k = n), 「，全部做得順」 (the derived practice counterpart), 「（第一個星期玩）」 for a new game (mockup), else nothing.
  - `insuff.oneDay` and `insuff.noMethod` (English written) cover W2's other reasons.
  - 數據唔夠 rows get no extra: they are not compared or ranked.

**Pages 4 and 5**

- **Built.** Only lines the design gives copy for: 「今個星期玩得太少，未排名。」, 「今個星期每個遊戲都仲學緊，慢慢嚟。」, the list splits 「答題 3 個、練習 2 個」, the 「其他都做得好：…」 / 「其他仲學緊：…」 lines (game and k/n, as the mockup) and 「今個星期冇改設定」. English for these was written.
- **Not built.** The mockup's page-5 change sentences and the ids without copy (`wr.baseline`, `wr.partialPrev`, `wr.bottom.none`) are not built.

**Recommendations (§7)**

- **Still learning.** A trigger's "still learning" means the game is on page 4's still-learning list.
- **Claims.** Each section has its own claims. A game claimed by an earlier item cannot feed a later one. An item is added (and claims) only while the section has room: 3 family items, F8 extra; 4 app items.
- **Family items.**
  - F6: a quiz game with ≥ 2 fuel-outs (most fuel-outs, then game order). One item.
  - F1, F2, F3: all unclaimed still-learning quiz games of the area, listed as evidence.
  - F5: count-then-trace still learning, or help-heavy over ≥ 5 rounds. {learned} is every numeral learned before or during the week (W2's numeral facts), as 「3 同 5」 / "3 and 5". With none learned, `F5.plain` drops that clause.
  - F4: a 手眼・畫線 practice game still learning, or starting away from the green dot in ≥ 40 % of ≥ 5 rounds. The design cell is split into a shapes form and a roads form, chosen by the first such game. The roads English starts "With a fat crayon on big paper," as the mockup does.
  - F7: the first quiz game with the `bot.fast` rule.
  - F8: added when a win is shown. {winObject} comes from a per-kind table (new copy: 影子 / the shadow, 條路 / the road, …), from the first shown quiz win (streak, first try, clean day, no fuel-out, quiz rise), else the first shown win.
  - Evidence (因為) sentences are built from the same fact fragments, as the mockup does.
- **Help-heavy.** Help-heavy (W1) counts for F5 and A4 only with n ≥ 5, so a 數據唔夠 game never gets advice from 1–4 rounds.
- **Current values.** "Current value" is the last value in this week's countable records: `range`, `count_voice` and `trace_scaffold` of tap-count deals; `guide_level` of their results; 連一連 `tolerance` and `category_mix`; shape-trace `direction_coaching` and `slant_enabled`. A suggestion equal to it is skipped. When nothing is recorded, the guidance line reads "→ suggested" (`A4.to`, `A4b.to`), and A6 does not suggest the tolerance.
- **App items.**
  - A5: one item lists every memorised fixed kind, skipping kinds already in `QuestionGeneration.generatedKinds` (for those the suggestion equals the current state). `A5.one` is the English singular.
  - A10: quiz areas only (數字・數量, 觀察・配對, 比較・概念, 字母). It fires when the area is the lowest chance-adjusted quiz area both weeks, among ≥ 2 areas with ≥ 10 answered rounds with a chance, or when ≥ 2 of its quiz games are still learning. It claims the area's quiz games, so the practice games stay free for A2–A4b. Only 數字・數量 has candidate copy (the design's example); other areas print 「多做一款「{area}」遊戲。」.
  - A1 is skipped when A10 has claimed 數車仔 / 邊邊車多啲. That is the §5.6 case; the mockup merged A1 into its A10 text instead.
  - A4: count-then-trace with ≥ 5 rounds, help-heavy or smooth < 50 %. Guidance → 多啲 first; with guidance already 多啲, trace guide outline → dots.
  - A4b: ≥ 5 rounds with `guide_clean` in each week and ≥ 80 % in each. Guidance → 少啲, or trace guide dots → outline.
  - A6: the 「只開 ★」 part only for 連一連 · 沿路過橋 dealt at ★★ / ★★★ this week. The tolerance part only when the recorded tolerance is not 闊. With 闊 already, the text says so, as the mockup does.
  - A7: wrong lines from `answer_attempt.wrong_lines` per `game_dealt.category` (≥ 60 % of ≥ 4). The weight comes from the last `category_mix` and is lowered by 10, not below 0; skipped at 0.
  - A2: 點數 with ≥ 5 rounds and smooth < 60 % (recounts are what make a round not smooth), with range above 1–5. The 「點車讀數」 clause follows the recorded value.
  - A3: ≥ 90 % in both weeks (≥ 5 rounds each) at 1–5 or 1–7 → the next step.
  - A8: wrong start in ≥ 40 % of ≥ 5 rounds with the direction hint recorded off.
  - A9: ≥ 90 % over ≥ 10 畫直線 rounds in the two weeks together, slant lines recorded off.
  - A11: every qualified quiz game of the area going well this week and last week (W2 tier rules on last week's estimates).
  - A12: across quiz games, ≥ 30 % of ≥ 3 wrong taps before the question finished.
  - Setting lines (`set.*`) are engineering text, the same in both languages. The "check next week" phrases were written from the design's metric names.
- **Questions.** Q1 uses the design's copy: {h} is video minutes per day played, {m} per counted play (`Q1.noPicks` without plays), and the note is always added. Q2: excluded rounds ≥ 20 % of counted plus excluded rounds. Q2 prints the child's name where the design says 小朋友 / your child (D7). The English reads "If some were actually {name}'s"; `Q2.one` is the English singular.
- **Child's name.** It is an input, default Cedric; a blank name falls back to Cedric. It is printed verbatim.

**Copy written for gaps (Carter to review)**

- English for: `hl.games.none`, `wr.empty`, `insuff.noMethod`, `rank.notRanked`, `rank.allLearning`, `changes.none`, `rec.none` and `app.none`.
- Chinese and English for: `videos.top`, `top.smooth.all`, `soFar.practiceAll`, `insuff.zero`, the F8 objects, the any.settings names, the evidence and check sentences, and the A-item texts the design gives only as setting changes (A2, A3, A4b, A7, A8, A9, A11).

## Consequences

The slice is VisaCore code, `VisaCoreChecks`, fixtures and docs only. No screen, record, setting or version changes, so the version stays 0.34.0 / 70.

Eight checks are registered in `VisaCoreChecks`, with the PASS banner updated: `testWeeklyTextFormatter`, `testEveryNumberTraceable`, `testNoBannedWords`, `testReportStringsTraditionalOnly`, `testTemplateSelectionDeterministic`, `testSampleSentences67ReproducedExactly`, `testWeeklyTextGoldenFixtures` and `testRecommendationRulesAndClaims`.

W4 renders this model; it adds no sentence of its own except static layout copy.

Swift was not compiled or run here (Linux box, no toolchain). The goldens and the synthetic-week expectations were produced with the Python reference; the Mac mini `sh scripts/test.sh` result is pending. The app-level kiosk remains subject to the macOS escape paths in `docs/phase-0-kiosk-checklist.md`; no kiosk boundary or device policy changed.
