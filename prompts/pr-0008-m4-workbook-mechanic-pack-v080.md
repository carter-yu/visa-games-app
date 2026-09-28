# Prompt archive — PR #8 M4 workbook-mechanic pack v0.8.0

- Date: 2026-09-29 (HK)
- Branch: `feat/m4-gakken-style-activities`
- Model: workshop executor (gpt-6-sol plumbing + astra-style UX/copy)
- Repo: carter-yu/visa-games-app
- Base tip: `e69649f` (v0.7.4 full PNG fleet)

## Goal

Map preschool workbook **activity MECHANICS only** (from Carter's 6 uploaded pages) into Visa Depot vehicle world using existing hero PNGs + props. Add 4–6 solid new `ActivityKind`s, rotate with existing catalog, keep visa 10/20/30 + stamp + YouTube shuffle + D8 + IP disclaimer. Original prompts Traditional Chinese + English; never Simplified. Bump **0.8.0**. Tests for new logic. Do **not** merge PR #8.

## Constraints

- Inspiration only — no copy of workbook characters (squirrels, bears, fruit), art, layout, or Gakken/Play Smart IP
- No Tomica / Thomas / Tayo likenesses
- Prefer existing `Resources/Vehicles/*.png` + `Resources/Props/*.png`
- Linux may lack Swift — Mac mini UAT owns compile/test/visual

## Delivered kinds

| Kind | Mechanic | Depot mapping |
|------|----------|---------------|
| halfMatch | Find other half | Left half fire → right-half options |
| shapeCousin | Shape like clock/round | Sun → round tanker among cone/toolbox |
| capacityCompare | Who carries more | Bus vs taxi |
| moreFewer | More of group A/B | Two parking lots 2 vs 4 |
| shadowMatch | Silhouette → color | Metro shadow → colored heroes |
| emptyBay | Whose plate/bay empty | Three bays, one empty |

## Acceptance

- Tip SHA on PR #8 with v0.8.0 / build 24
- Offline activity checks **18**; playableKinds **10**
- Mac mini UAT checklist in PROGRESS; PR unmerged
