# Phase 4 — M4 Gakken-style activity TYPES (original vehicles)

Phase 4 expands the child entry gate beyond the single two-picture question by adding a small **activity catalog** of preschool workbook **genres** (not IP). Art remains original long-vehicle silhouettes.

## Relationship to prior phases

- **M3** (PR #7) merged @ `5603845` / v0.5.1 — difficulty cards + two-picture + visa 10/20/30.
- **M4** adds find-the-same + count-to-N playable kinds, catalog rotation, sequencing stub.
- **D9** YouTube pack / reviewed audio and **D10** reporting remain open.

## Scope (this slice)

- ADR 0005: activity-type-only inspiration; no Gakken pages/art/titles/packaging.
- VisaCore: `ActivityKind`, `FindSameQuestion`, `CountQuestion`, `SequenceQuestion` stub, `ActivityCatalog`, evaluator overloads.
- VisaGames: `FindSameActivityView`, `CountActivityView`, `SequenceActivityStub` TODO; AppModel rotates kind after difficulty; ShellView switches gate.
- Tests: +5 activity checks (catalog rotation, find-same, count, stub, hints) → **12** activity total.
- Version **0.6.0** / build 16.
- Prompt archive + PROGRESS.

## Out of scope

- Copying Gakken / Play Smart content.
- Inventing D9 pack IDs or D10 reporting.
- Simplified Chinese.
- Merging without Carter Mac mini UAT.
- Full path-trace / maze / connect-the-dots / shape-sort UIs (listed as future genres).

## Slices

### P4-0 — Catalog + two new playable kinds + stub (this PR)

Land registry, find-same, count, sequence stub, UI, tests, docs, v0.6.0.

### P4-1 — Mac mini compile + child UAT

Pull tip, `sh scripts/test.sh`, `sh scripts/bundle.sh`, exercise all three playable kinds across repeated difficulty picks, confirm visa 10/20/30 unchanged.

### P4-2 — Storybook child UX + recognizable original vehicles (v0.7.0)

Warm sand depot shell, mission tickets, friendly faces on HK/NY/fire/metro/works vehicles (original IP), playable short→long convoy, visa stamp celebration, parent license footer (ADR 0006). Do not merge until Mac mini UAT.

### P4-3 — Workbook-mechanic pack (v0.8.0)

Six new playable ActivityKinds mapped from preschool workbook mechanics into Visa Depot
(half-match, shape cousin, capacity, more/fewer, shadow match, empty bay). Catalog rotates
10 kinds. Original heroes/props only; HK Trad + English. Do not merge until Mac mini UAT.
