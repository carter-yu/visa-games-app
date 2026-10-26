# Weekly ranking golden fixture (W2, design §5.6)

Synthetic records only: made-up rounds and plays, no real child data. The folder is laid out like
`~/Library/Application Support/VisaGames/stats/`: one `events-YYYY-MM-DD.jsonl` per Hong Kong day
(sorted-key JSON lines, as `PerfCodec.encodeLine` writes them). There is no rollup file, so
`loadRollup()` returns an empty rollup.

The report week is the synthetic week of the design's sample report (`visa-games-design/weekly-report`
§5.6 and `mockups/make_sample.py`): `make_fixture.py` copies the sample's per-kind schedule, failures,
stars, practice extras and random draws, so the W1 metrics of these records give the §5.6 table.

| Request | Value |
| --- | --- |
| week | `2026-10-19` (Monday) to `2026-10-25` (Sunday), `Asia/Hong_Kong` |
| `dataUntil` | `2026-10-25T13:00:00.000Z` = Sunday 21:00 HKT |
| previous week | `2026-10-12` to `2026-10-18` (7 days played; the sample's `PREV` n / k per kind) |

## Checks that read this folder

- `testWorkedExample56ReproducedExactly` (`WeeklyRankingTests.swift`): the §5.6 values to 3 decimals —
  priors m̄_w 0.598 / p̄_w 0.737, each row's n, k, chance, m (lo – hi) and tier, the 3 + 2 going-well
  split and members, the 3 + 2 still-learning members, 「其他都做得好」 / 「其他仲學緊」 and the 數據唔夠 rows.
- `testWeeklyAnalysisGoldenFixtures`: `WeeklyAnalysis.canonicalJSON()` against `expected-analysis.json`
  byte for byte (the same check reads `../weekly-2026-10-19/expected-analysis.json`). On a mismatch it
  reports the first differing line and writes the Swift output to
  `$TMPDIR/weekly-ranking-5.6-analysis-actual.json`.
- `testNoGameInBothLists` also checks the page-4 places of this week.

The checks find the folder next to their source file (`#filePath`) and fall back to
`Tests/VisaCoreTests/Fixtures/...` under the working directory. `Package.swift` excludes `Fixtures`
from the `VisaCoreChecks` target.

## What the records cover

| Case | Where |
| --- | --- |
| §5.6 week | 154 counted rounds: 97 quiz (11 kinds), 57 practice (9 kinds); no child play on Wednesday |
| the 數據唔夠 rows | 圓圓嘅 4/4, 邊架消防車 2/2, 數完畫（英文）1/3 |
| settings change | Wednesday 17:00 `config_change` `lineMatch_tolerance` → `wide`; the earlier value `standard` comes from a `config_change` on 2026-10-09. 連一連 deals carry `tolerance` standard before Wednesday and wide after |
| star assignment | Thursday 07:40 `config_change` `assignment` 數完畫（英文）★ on (after two playtests) |
| versions | `0.31.0` Monday–Wednesday, `0.31.1` from Thursday (`0.30.0` the week before) |
| not counted | 5 `parent_uat` rounds (Tuesday 22:30) and 6 `parent_playtest` rounds (Wednesday, Thursday) |
| new kind | 數完畫（英文）has no earlier round |
| numerals | 數完畫 rounds with `guide_learned_before == 1` for 3 and 5 this week, none the week before |
| videos | plays every day played; 120 minutes a day the week before |

## Expected output (from the sample model)

Going well 3 quiz + 2 practice (邊個影子, 搵另一半, 短到長車隊 | 畫直線 · 熱身, 畫形狀 · 跟虛線); still learning
3 + 2 (數車仔, 邊邊車多啲, 連一連 · 自己配 | 一架一架數 · 數完畫, 連一連 · 沿路過橋); wins 「第一次玩 數完畫（英文）」,
numerals 3 and 5, 邊個影子 9 in a row; clear changes 畫形狀 · 跟虛線 and 畫形狀 · 跟箭嘴 (6/9 → 7/8, 3/6 → 7/9); ⚙ on
the three 連一連 cards (tolerance) and 數完畫（英文）(assignment); memorised flag on 搵另一半 and 邊架載多啲人.

## Canonical encoding

The W1 rules (`../weekly-2026-10-19/README.md`, "Canonical encoding"): keys sorted by UTF-8 bytes,
two-space indent, every non-integer number with exactly 6 decimals, `null` for missing values. Order:
games in W1 row order (catalog order, quiz before practice); kind lists split into `quiz` and `practice`
(答題 first); the 數據唔夠 list by type, then reason (`too_few`, `one_day`, `no_method`), then more rounds,
then catalog order; areas and families in W1 order; clear changes in row order; wins in §6.5 priority
order; versions by first appearance; settings, assignments and the ⚙ `config` reasons in record order.
Ids are English: tiers `going_well`, `learning`, `needs_practice`, `insufficient`, `no_method`; places
`top`, `still_learning`, `also_well`, `also_learning`, `insufficient`; changes `up`, `down`, `same`,
`unsure` (`null` = not shown); wins `win.newGame` … `win.noFuelOut`.

## Regenerating

```sh
cd Tests/VisaCoreTests/Fixtures/weekly-ranking-5.6
python3 make_fixture.py
python3 reference_analysis.py . 2026-10-19 2026-10-25T13:00:00.000Z > expected-analysis.json
cd ../weekly-2026-10-19
python3 ../weekly-ranking-5.6/reference_analysis.py . 2026-10-19 2026-10-25T13:00:00.000Z > expected-analysis.json
```

`make_fixture.py` writes the records deterministically and asserts the §5.6 n / k per kind, the
previous week's n / k and that no ★★★ share moves by 30 points. `reference_analysis.py` is an
independent Python reading of design §4.10, §5, §6.5 and the page-5 changes (ADR 0022). It takes the
W1 metrics from `../weekly-2026-10-19/reference_model.py` and shares no code with Swift. Change the
records or the rules on both sides together, then regenerate and review the diff.

## W3 text (design §6, §7; ADR 0023)

`expected-text.json` is `WeeklyReportText.canonicalJSON()` for the same request, with the child's name
Cedric (D7) and the synthetic video titles of `video-titles.json` (D8 B; made-up labels for the fixture's
video ids, one with digits to exercise the verbatim rule). It holds every sentence (Chinese, English,
traced numbers, verbatim spans) and the W3 facts block. `reference_text.py` is an independent Python
reading of the W3 templates and rules on top of `reference_analysis.py`; it shares no code with Swift.

Checks that read it (`WeeklyTextTests.swift`):

- `testWeeklyTextGoldenFixtures`: byte for byte (the same check reads `../weekly-2026-10-19/expected-text.json`);
  on a mismatch it writes the Swift output to `$TMPDIR/weekly-ranking-5.6-text-actual.json`.
- `testSampleSentences67ReproducedExactly`: the ten design §6.7 sentences, Chinese and English, from this week.
- `testEveryNumberTraceable`, `testNoBannedWords`, `testReportStringsTraditionalOnly` and
  `testTemplateSelectionDeterministic` scan its sentences too.

Regenerate after the records or the rules change (the W1 fixture's text uses the same script):

```sh
cd Tests/VisaCoreTests/Fixtures/weekly-ranking-5.6
python3 reference_text.py . 2026-10-19 2026-10-25T13:00:00.000Z video-titles.json > expected-text.json
cd ../weekly-2026-10-19
python3 ../weekly-ranking-5.6/reference_text.py . 2026-10-19 2026-10-25T13:00:00.000Z video-titles.json > expected-text.json
```

## W4 report HTML (design §3, §8, §9; ADR 0024)

`expected-report.html` is `WeeklyReportHTML.render` of this week's W3 text with `generatedAt`
`2026-10-25T13:00:00.000Z` and the sample watermark on (this is the design's sample week, so it wears
「示例數據 EXAMPLE DATA」 like `mockups/sample-report.html`; real reports have it off). Six A4 page
sections; every chart is inline SVG; no script, URL, font file or image.

`reference_html.py` is an independent Python reading of design §3, §8, §9 and ADR 0024. It reads a
folder's `expected-metrics.json`, `expected-analysis.json` and `expected-text.json` (the W3 word tables
come from `reference_text.py`) and shares no code with Swift; the Swift label table, stylesheet and
palette were generated from its tables. Every coordinate and layout estimate is an integer in tenths
of a px; chance means printed as whole percents are refused when they sit near a rounding tie.
`expected-metrics.json` (new in W4) is the W1 model of this folder, made with
`../weekly-2026-10-19/reference_model.py`, so the reference can read the day table, the matrix and the
week charts.

Checks that read it (`WeeklyReportHTMLTests.swift`):

- `testHTMLGolden`: first `WeeklyModel`, `WeeklyAnalysis` and `WeeklyReportText` against the three JSON
  goldens, then the HTML byte for byte (the same check reads `../weekly-2026-10-19/expected-report.html`).
  On a mismatch it reports the first differing line and byte offset and writes the Swift output to
  `$TMPDIR/weekly-ranking-5.6-report-actual.html` (or `-metrics-`, `-analysis-`, `-text-actual.json`).
- `testPageCountSix`, `testNoTextOverflowBudget`, `testHTMLPaletteTokens`, `testHTMLSelfContained`,
  `testHTMLWellFormed`, `testW3StringsPresent` and `testHTMLTraditionalOnlyAndNoBannedWords` scan it with
  the W1 fixture's report and nine synthetic weeks built in the test file.

Regenerate after the records, the W1–W3 goldens or the layout change:

```sh
cd Tests/VisaCoreTests/Fixtures/weekly-ranking-5.6
python3 ../weekly-2026-10-19/reference_model.py . 2026-10-19 2026-10-25T13:00:00.000Z > expected-metrics.json
python3 reference_html.py . 2026-10-25T13:00:00.000Z --sample > expected-report.html
cd ../weekly-2026-10-19
python3 ../weekly-ranking-5.6/reference_html.py . 2026-10-25T13:00:00.000Z > expected-report.html
```
