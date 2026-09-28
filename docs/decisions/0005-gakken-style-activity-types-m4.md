# ADR 0005 — Gakken-inspired activity TYPES expansion (M4)

Status: Proposed implementation for Phase 4 (M4) scaffold — parent Mac mini UAT pending; **D9 / D10 remain open**

## Context

PR #7 (M3) merged to main @ `5603845` (v0.5.1). Carter Confirmed UAT good, then asked for more games by referencing preschool wipe-clean workbook **activity types** (Gakken Play Smart Ages 2–4 public product description: tracing lines/letters/numbers/shapes, matching, mazes, puzzles, search-and-find, counting). This ADR records that inspiration is **genre / activity-type only**.

## Explicit IP boundary

- **In scope:** activity genres suitable for a 3–5yo Wacom/touch kiosk (matching / two-picture choose, find-the-same, count-to-N, sequencing stub, later maze-lite / path-trace lite / connect-the-dots lite / shape sort).
- **Out of scope:** copying workbook pages, art, characters, titles, packaging, logos, or any Gakken / Play Smart trademarked materials.
- **Art:** original in-repo long-vehicle silhouettes and high-contrast engineering colors only. **No Tomica / Takara / Thomas**.
- **Language:** Hong Kong Traditional Chinese + English UI only — **never Simplified Chinese**.

## Decisions (this slice)

1. Introduce `ActivityKind` + `ActivityCatalog` in VisaCore. Playable kinds rotate deterministically from the round UUID seed after difficulty pick. Same `ChildDifficulty` → `Session.startPlayVisa` path (10 / 20 / 30 Confirmed).
2. Keep existing two-picture crane-vs-bus as one playable kind.
3. Land fully playable **find-the-same** and **count-to-N** with pure evaluators + tests + large-target SwiftUI gates.
4. Register **sequence short→long** as a stub (`SequenceQuestion.isPlayable == false`) with clear TODOs — not presented as a child round yet.
5. Keep `EntryActivityView` / VisaCore clean; do not invent D9 YouTube pack; D6/D10 stay as previously documented.
6. Version **0.6.0** (MINOR — multiple family-visible activity kinds).

## Activity-type list (genres only; research summary)

From public Play Smart wipe-clean / preschool workbook descriptions (tracing, letters, numbers, shapes, matching, mazes, puzzles, search-and-find, counting, sorting) — mapped to kiosk-safe originals:

| Genre | M4 status |
|-------|-----------|
| Two-picture / matching choose | Playable (existing) |
| Find-the-same | Playable (new) |
| Count-to-N | Playable (new) |
| Sequencing (short→long) | Stub / TODO |
| Path tracing lite | Future |
| Maze-lite | Future |
| Shape / vehicle sort | Future |
| Connect-the-dots lite | Future |

## Consequences

- Lock flow: difficulty cards → rotated activity gate → success → same visa / reward unlock.
- Offline activity checks expand (expect **12** activity assertions in VisaCoreChecks).
- Mac mini UAT required before merge; Linux workshop may lack Swift.

## v0.8.0 addendum (2026-09-29)

Expanded playable catalog with six additional genres mapped from workbook **mechanics only**
into Visa Depot: half-match, shape cousin, capacity compare, more/fewer lots, shadow match,
empty bay. Sequencing remains playable (from v0.7). Art stays original hero PNGs + soft props.
No workbook characters/pages copied. Offline activity checks → **18**. Version **0.8.0**.
