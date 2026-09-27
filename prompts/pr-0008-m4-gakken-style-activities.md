# Prompt archive — PR #8 M4 Gakken-style activity TYPES

- Date: 2026-09-27 (HK)
- Branch: `feat/m4-gakken-style-activities`
- Model: workshop executor (gpt-6-sol class)
- Repo: carter-yu/visa-games-app
- Base: main @ `5603845` after merge of PR #7 (v0.5.1)

## Goal

After merging PR #7, research public Play Smart wipe-clean workbook **activity types only** (no IP theft), then implement a first expansion: activity protocol/registry + at least two new playable kinds (find-the-same, count-to-N) alongside existing two-picture, plus a sequencing stub. Unlock the same ChildDifficulty → Session.startPlayVisa path (10/20/30). Original long-vehicle silhouettes; HK Traditional Chinese + English; never Simplified Chinese. Version prefer 0.6.0. Do not invent D9 YouTube pack; D6/D10 stay open. Do not merge the new PR.

## Constraints

- Workshop Codex on box → branch+PR; Mac mini UAT only
- No Gakken pages/art/characters/titles/packaging
- No Tomica/Takara/Thomas
- Keep EntryActivity / VisaCore clean
- Tests for new activity logic; Linux may lack Swift — note Mac UAT
- PROGRESS.md + prompts archive + ADR/phase note

## Acceptance (this slice)

- New PR open with tip SHA + v0.6.0
- 3 playable kinds via catalog rotation; sequence stub documented
- Offline checks include expanded activity suite
- Mac mini UAT checklist for Carter
