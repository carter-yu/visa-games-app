# ADR 0022: Weekly report ranking, week over week and wins (W2)

Date: 2026-10-25
Status: Draft PR, source implementation awaiting Mac verification

## Context

Slice W2 of the weekly report (`visa-games-design/weekly-report/design.md` §12) covers the weekly tiers, the 數據唔夠 list and the proportional going-well / still-learning slots (§5.1–5.5). It also covers week over week with the ⚙ marker (§4.10), the wins catalogue as ids and parameters (§6.5) and the page-5 "what changed in the app" data. Acceptance is the §5.6 worked example to 3 decimals. W1 (ADR 0021, PR #36, `992a7b3`) is the input. D1–D13 stay locked; in particular D4 A (proportional slots) and D5 A (≥ 5 rounds, still learning on ≥ 2 days). Comment text, highlights, recommendations, HTML/PDF and the parent row are W3–W5.

## Decision

`WeeklyAnalysisBuilder.build(events:rollup:window:)` is pure. It returns `WeeklyAnalysis`: the W1 `WeeklyModel` plus `games`, `ranking`, `comparison`, `winCandidates` / `wins` and `changes`. `WeeklyAnalysis.canonicalJSON()` uses the W1 `WeeklyJSON` rules and English ids. W1 gains one internal entry point, `WeeklyMetricsBuilder.build(ordered:index:window:)`, so W2 reads the same index; W1 behaviour and `expected-metrics.json` are unchanged. The rules are pure functions on value types: `WeeklyRanking.rank`, `.tier`, `.largestRemainder`, `WeeklyComparison.rateChange` / `.countChange`, `WeeklyStarRule.evaluate` and `WeeklyWin.candidates`.

The §5.6 week is rebuilt as records in `Tests/VisaCoreTests/Fixtures/weekly-ranking-5.6/`. The generator copies the sample's schedule and random draws from `mockups/make_sample.py`. The W1 fixture also gets an `expected-analysis.json` for the paths §5.6 does not reach. Both goldens come from `reference_analysis.py`, which takes its metrics from the W1 reference.

Choices where the design left room:

**Ranking (§5)**

- **n and k.** A quiz row counts answered rounds and right-first-time rounds. A practice row counts smooth-defined and smooth rounds.
- **No method.** A quiz row is `no_method` (「未有評分方法」) when any of its rounds has no chance (an unknown kind without `game_dealt.chance`), even with ≥ 5 answered rounds. A practice row is `no_method` without a family.
- **Estimates of unranked rows.** W1's estimate stays in the data; the tier says it is not ranked.
- **Tier (§5.2).** The rule is applied as written, without an epsilon. Fuel-outs are this week's zeroed rounds. Help-heavy is W1's mean `guide_helps` ≥ 2.
- **Top list members.** Top candidates are every qualified row whose tier is not needs-practice (the §5.3 formula), so a `learning` row can fill a spare going-well slot.
- **Proportional slots.** Largest remainder is computed in integers on the qualified counts |Q| : |P| for both lists. Equal remainders go to quiz, matching `weekly_model.py`. Spare slots spill to the other type.
- **Ordering.** "More rounds" means more n, as in `weekly_model.py`. Raw rates are compared exactly by cross-multiplication. Catalog order comes last, with unknown kinds at the end by UTF-8.
- **「其他都做得好」 / 「其他仲學緊」.** Both are grouped by type (答題 first), each type in its list's own order. `weekly_model.py` sorts these across types, but §5.3 does not claim a cross-type order. The members are identical to the sample.
- **All on one day.** A qualified row in neither list, not going well and played on fewer than 2 days goes to the 數據唔夠 list as `one_day` (§5.3, template `insuff.oneDay`). It does not go to 「其他仲學緊」, where `weekly_model.py` would put it. A going-well row played on one day can still be in the top list or 「其他都做得好」.
- **數據唔夠 order.** Quiz rows come first. Then reasons in the order `too_few`, `one_day`, `no_method`, then more n, then catalog order. This matches the design's §5.6 text order.
- **Fewer than 2 qualified games.** The lists are still computed by §5.3 (T = 1 when E = 1). `ranked = false` tells W3/W4 to print 「今個星期玩得太少，未排名。」.
- **Star rule (§5.4).** The top star is ★★★; the lower stars are ★ and ★★ together. The rule applies to quiz rows only, because the design names the right-first-time rate. ★★★ needs ≥ 3 answered rounds and the lower stars ≥ 1. The 30 points are compared in integers. The output is k3/n3/k12/n12.
- **Fixed questions (§5.5).** 「同一題」 is set when the row's dominant `gen` this week is `fixed_v0` (a missing `gen` reads as fixed). It is not taken from the static `generatedKinds` list. The memorised flag needs a fixed quiz row with answered ≥ 10 and 10k ≥ 9n.

**Week over week (§4.10)**

- **Rates.** A rate needs ≥ 5 rounds in both weeks, else `null`. |Δ| < 0.20 is `same`, tested as 5|d| < n1·n0. |Δ| ≥ SE is tested as d²·m ≥ k(m − k)·n1·n0, with Doubles of integer products (exact for realistic sizes; the reference does the same). |Δ| = SE counts as clear, as in `weekly_model.py`. Rates are compared per row, in total, per area (the quiz part) and per practice family.
- **Counts and minutes.** 「明顯」 (`up` / `down`) needs ≥ 4 days played in both weeks (a counted round or play) and 4|Δ| ≥ last week's value. Last week 0 with this week > 0 counts as a rise. Otherwise the value is `null`; counts have no `same` word. The rule covers days played, rounds, game and video minutes, and quiz / practice rounds in the mix.
- **⚙ config window.** A `config_change` counts from the start of last week to the cut-off, because a change made last week also makes the two weeks hard to compare. The page-5 list shows only this week's changes.
- **⚙ families.** `lineMatch_` covers the three 連一連 cards, `shapeTrace_` the four 畫線畫形 cards and `tapCount_` the six 一架一架數 cards. `assignment` applies to its own kind at any star. An unknown prefix is listed but marks nothing.
- **Dominant deal signature.** The signature is taken over each window's countable deals, including a deal still open at the cut-off. The most common value wins; a tie goes to the value used last. A field a deal did not write is not counted. A field is compared only when both weeks have a value, so a field added by an update is not a change. Values are compared as text; `gen` reads missing as `fixed_v0`. `res.guide_level` comes from results seen by the cut-off.
- **`level`.** `level` is compared only when some deal in either week has a level other than its star. Where the level is the mission star (countVehicles, findTheSame, free lineMatch), the ★★★ rule speaks for difficulty. Without this, any wobble in the star mix would put ⚙ on those kinds. Pinned levels (guided roads, shape trace, tap count) are compared.
- **★★★ share.** The share of counted rounds at ★★★ is checked for every row, not only generated kinds. A move of ≥ 30 points (in integers) is a change; both weeks need rounds.
- **⚙ rows.** A ⚙ row keeps its change in the data. It never feeds the clear-change list or `win.rise`. Clear changes are kinds only, in row order; the area, family and total changes are data for W3.

**Wins (§6.5)**

- **Evaluation.** Rules run in priority order. Per-kind rules give one win per kind in row order: new game, rise, first smooth and first try. The other rules give one win each: the numerals in ascending order, the longest streak (ties go to row order), and the clean day with the most quiz rounds (ties go to the earliest day). The first 3 are shown; the JSON also keeps all candidates.
- **Streak.** It runs over answered quiz rounds in record order; an unanswered round does not break it.
- **Clean day.** It needs every quiz round of the day right first time; an unanswered quiz round breaks it.
- **No fuel-out.** It counts zeroed quiz rounds.
- **History.** "First-ever" history is the countable raw rounds after the last `stats_marker{cleared}`, with results seen before the report week starts. A round finished after Monday 00:00 is not history, which is consistent with "counts in no week". Quiz history also adds rollup days (answered, first try; guided keys skipped). The rollup keeps no smooth or numeral facts, so first smooth and numerals use raw records only (90 days).
- **First try.** It needs ≥ 3 answered rounds before the first right-first-time round: history plus this week's earlier rounds.
- **Numerals.** A numeral comes from the result, else from the deal.

**Changes panel (page 5, §9.6 `changes`)**

- **Versions.** These are the distinct envelope `app` values of any record in the window, with first and last day.
- **Settings.** These are this week's settings changes; assignments are listed separately. `old` is the value of the last earlier `config_change` with the same `what`, or `null` when none was recorded. Old values are not inferred from deal fields; the ⚙ signature reasons give the deal-level old → new.
- **Assignments.** Each is a net change per (kind, star) this week. A toggle flips the star, so an even number of toggles cancels.
- **Generations.** These are rows whose dominant `gen` moved.
- **Mix.** Quiz and practice rounds are compared with the counts rule, and the ★ mix of both weeks is kept.
- **Excluded.** These are W1's excluded rounds by reason, plus the rounds open at the cut-off.

## Consequences

The slice is VisaCore code and `VisaCoreChecks` only. No screen, record, setting or version changes, so the version stays 0.34.0 / 70. The nine W2 checks are registered in `VisaCoreChecks`, with the PASS banner updated. W3 renders text from these ids and parameters; any sentence needs only the numbers already in `WeeklyAnalysis`.

Swift was not compiled or run here (Linux box, no toolchain). The reference and the goldens were generated in Python; the Mac mini `sh scripts/test.sh` result is pending. The app-level kiosk remains subject to the macOS escape paths in `docs/phase-0-kiosk-checklist.md`; no kiosk boundary or device policy changed.
