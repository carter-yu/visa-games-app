# Weekly metrics golden fixture (W1)

Synthetic records only: made-up rounds and plays, no real child data. The folder is laid out like
`~/Library/Application Support/VisaGames/stats/`: one `events-YYYY-MM-DD.jsonl` per Hong Kong day
(sorted-key JSON lines, as `PerfCodec.encodeLine` writes them) plus `rollup-v1.json`.

`testWeeklyGoldenFixtureByteForByte` (`WeeklyMetricsTests.swift`) reads this folder with
`PerfEventStore(directory:)` / `loadRollup()`, builds `WeeklyMetricsBuilder.build` for the request
below, and compares `WeeklyModel.canonicalJSON()` with `expected-metrics.json` byte for byte. On a
mismatch it reports the first differing line and writes the Swift output to
`$TMPDIR/weekly-2026-10-19-actual.json`.

| Request | Value |
| --- | --- |
| week | `2026-10-19` (Monday) to `2026-10-25` (Sunday), `Asia/Hong_Kong` |
| `dataUntil` | `2026-10-25T13:00:00.000Z` = Sunday 21:00 HKT (D1 ready time) |
| previous week | `2026-10-12` to `2026-10-18`, seen to its end |
| trend weeks | the 6 weeks before, only those with any record: `2026-10-05` (partial) and `2026-10-12` |

The check finds this folder next to its own source file (`#filePath`), and falls back to
`Tests/VisaCoreTests/Fixtures/...` under the working directory (`scripts/test.sh` runs from the
repository root). `Package.swift` excludes `Fixtures` from the `VisaCoreChecks` target, so the
JSON, JSONL and Python files are never treated as sources or resources.

## What the records cover

| Case | Where |
| --- | --- |
| `parent_uat` | Tue 10-20 (家長測試中 on): 2 rounds and 1 play, not counted; Tue 10-13: 1 round |
| `parent_playtest` | Wed 10-21 `tapCountTraceEnglish` playtest; Thu 10-15 `traceShapesDotted` playtest |
| excluded, then re-included session | `s-1022b` (Thu 10-22, 3 rounds): `stats_exclude` 19:30, `stats_include` Sun 22:00 — after the cut-off, but exclusions are read as of making the report, so it counts |
| excluded session kept out | `s-1024x` (Sat 10-24): 2 rounds and 1 play |
| round crossing midnight HKT | `moreFewer` dealt Wed 23:58:30, solved Thu 00:01:10: counted on Wednesday. `sequenceShortToLong` dealt Sun 10-11 23:59, solved Mon 00:01: after that week's cut-off, so in no week |
| Sunday 23:59:59 vs Monday 00:00 | `video_end` at Sun 10-18 23:59:59.000 (previous week, Sunday); `game_dealt` at Mon 10-19 00:00:00.000 (this week, Monday) |
| version change | 0.33.1 until Wed; 0.34.0 from Thu 10-22 (those deals also carry `game_dealt.chance`) |
| config change | Wed 10-21 `config_change` `lineMatch_tolerance` → `wide` (parent; no metric changes) |
| practice extras with / without `guide_clean` | `tapCountTrace` 10-08 (v0.29: trace fields only), 10-15 and 10-19 (`guide_clean` 1); `tapCountTraceEnglish` 10-22 (`guide_clean` 0 and 1); `traceShapesFree` with `ink_outside_ratio` null (undefined) |
| unknown event kind | a `future_event` line (Sun 11:00); unknown game kinds `mysteryQuiz` (quiz, no chance) and `mysteryTrace` (guided, practice, no family) |
| missing `video_end` | Fri 10-23 17:30 play: 3 `video_progress` lines, then a power cut; the file ends with a torn line (skipped by the reader). Minutes use the last progress (179.4 s); Friday is marked estimated |
| more | crash mid-round Sat 10:20 + relaunch 10:31 (`no_result`, unfinished); round open at the cut-off (Sun 20:58 → 21:02); rounds after the cut-off; a 15-minute walk-away (capped at 10); a pre-v0.24.1 guided road under `lineMatch` (10-12); a `parent_test_visa` play; an `after_parent` reload; rollup days that make `halfMatch`, `capacityCompare` and `lineMatch` not new |

## Canonical encoding (both sides must produce these bytes)

1. UTF-8, `\n` line ends, exactly one newline at the end of the file.
2. Objects: keys sorted by UTF-8 bytes (all keys are ASCII snake_case), one member per line,
   two spaces of indent per level, `"key": value`, commas at line ends. Arrays: one element per
   line. Empty object `{}`, empty array `[]`.
3. Integers in plain decimal. Every non-integer field (rates, minutes, chances, estimates, priors)
   is written with exactly 6 decimals — POSIX `%.6f`, correctly rounded from the binary value,
   even when integral (`1.000000`); `-0.000000` is written `0.000000`. Missing values are `null`.
4. Strings escape only `"`, `\`, `\n`, `\r`, `\t`, `\b`, `\f` and other control characters
   (`\u00xx`, lowercase hex). `/` and non-ASCII characters are written as they are.
5. Order: days Monday → Sunday; kinds by `ActivityCatalog.playableKinds` (unknown kinds after,
   by UTF-8), the quiz row before the practice row; areas `numbers, matching, comparing, pen,
   letters, other`; families `lines, shapes, roads, tapAll, tapTrace`; rounds in record order
   (`PerfCodec.ordered`); weeks oldest first, the current week last.
6. Floating sums are added in the same order on both sides (rounds in record order within a kind,
   kind rows in order within a group). Minutes are summed as integer milliseconds and divided once.
   The reference never uses Python's `sum()` on floats (compensated since Python 3.12) and refuses
   any value within 1e-6 of a 6-decimal rounding tie.

## Regenerating

```sh
cd Tests/VisaCoreTests/Fixtures/weekly-2026-10-19
python3 make_fixture.py
python3 reference_model.py . 2026-10-19 2026-10-25T13:00:00.000Z > expected-metrics.json
```

`make_fixture.py` writes the records deterministically; `reference_model.py` is an independent
Python reading of design §4.1–4.9 (no code shared with Swift; the estimator is the
`MasteryEstimator.swift` formula, cross-checked against `mockups/weekly_model.py`). Change the
records or the rules on both sides together, then regenerate and review the diff.
