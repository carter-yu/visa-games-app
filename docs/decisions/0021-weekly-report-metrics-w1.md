# ADR 0021: Weekly report metrics (W1)

Date: 2026-10-25
Status: Draft PR, source implementation awaiting Mac verification

## Context

Carter approved the weekly 7-day report design on 2026-10-24 HKT (`visa-games-design/weekly-report/design.md`, decisions D1–D13 locked). Slice W1 is the VisaCore weekly index and metrics (§4.1–4.9, §12). Ranking, comments, HTML/PDF, the parent row and scheduling are later slices. ADR 0008's record schema, retention and countable rule are unchanged.

## Decision

`WeeklyWindow` is Monday 00:00 to Sunday 24:00 in `Asia/Hong_Kong` (D1). It uses a Gregorian, Monday-first, POSIX calendar and never the host zone or locale. `WeeklyMetricsBuilder.build(events:rollup:window:)` is pure. It reuses `PerfCodec.ordered`, `PerfFilter.excludedSessions` / `countable`, `PerfQuestionGeneration.isPracticeOnly` and `PerfMastery`. `WeeklyModel.canonicalJSON()` is the deterministic text that the golden fixture compares byte for byte.

Choices where the design left room:

- Each window is seen only up to its cut-off: `dataUntil` for the report week, the end of the week for earlier ones. A round counts only when its result is seen by then. A deal with no result is open at the cut-off, and not counted, unless the app moved on before the cut-off: a later launch started, or another non-playtest round was dealt in that launch. Then it is lost and counted as unfinished. A round dealt late on Sunday and finished after Monday 00:00 counts in no week. Exclusions are read from every record passed in, so a later 「唔計呢段」 or 「計返」 applies to a remake (§9.6).
- Per-round chance uses `game_dealt.chance` when it is in (0, 1], then the §4.3 rebuild, then the catalog. A quiz kind with an answered round that has no chance gets raw first-try only. It is left out of the lucky-guess share, the pooled prior and the estimate.
- A kind dealt both ways gets two rows (kind, type), so quiz and practice never mix. Before v0.24.1, guided roads were dealt under `lineMatch`; those rows use the road family and rule.
- "Done smoothly" is defined only for a solved round whose kind has a rule and whose result has every field the rule reads. The §4.5 thresholds are constants in `WeeklySmooth` (D9 recalibration). Of the secondary practice signals, only the mean `guide_helps` (help-heavy) is computed.
- Sessions and days played count counted rounds and plays (`video_start` except `after_parent`). Video minutes go to the day of `video_end`. A play without one uses its last `video_progress` and marks the day as estimated.
- A kind is new when it has a counted round in the window and no countable deal before the window, raw or rollup day with deals, after the last `stats_marker{cleared}` seen by the cut-off.
- The trend weeks are those of the 6 weeks before the report week that have any record. A week is partial when fewer than 7 of its days started before the cut-off and end after the earliest record.

The optional `game_dealt.chance` write is not part of this slice. The reader already prefers the field. Writing it would change what 0.34.0 records without a version change, and it would need an existing exact-field assertion to change.

## Consequences

No screen, record, setting or version changes: the slice is VisaCore code plus `VisaCoreChecks`. The fixture folder is excluded from the check target in `Package.swift`. W2 to W5 build on `WeeklyModel` and must keep the fixture in step (its README has the regeneration steps).

This source slice has no Mac mini or TV validation. The app-level kiosk remains subject to the macOS escape paths in `docs/phase-0-kiosk-checklist.md`; no kiosk boundary or device policy changed here.
