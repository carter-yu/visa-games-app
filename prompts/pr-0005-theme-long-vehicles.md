# PR #5 — Theme long-vehicles + kid yellow polish

| Field | Value |
| --- | --- |
| Date | 2026-09-26 original slice; 2026-09-27 rebase + yellow polish (HK) |
| Branch | `feat/theme-long-vehicles` |
| PR | https://github.com/carter-yu/visa-games-app/pull/5 (OPEN) |
| Model | Codex / sol preferred (`codex -m gpt-6-sol`); Linux workshop implement carefully when Swift unavailable |
| Goal | Long-vehicle watermark + park-in success + parent palettes; then rebase onto main after PR #4 and polish yellow accents for ~age-4 attractiveness |

## Constraints (both slices)
- Original silhouettes only (crane / tanker / bus / dino flatbed / logistics). **No** Tomica / Takara / Thomas trademarks, logos, faces, or names in UI.
- HK Traditional Chinese + English only; never Simplified Chinese.
- Theme preference via UserDefaults — do **not** touch Snapshot / RewardLedger / invent reward policy.
- Yellow as **accents** (buttons, vehicle highlights, success sparkles, soft sun/road stripes) — **not** full-screen bedroom-yellow walls. Pair with calming soft blues/greens for large backgrounds.
- Rounder shapes, larger TV-readable type, friendlier spacing.
- Watermark parade: slightly more playful bob, still low distraction on lock/play only.
- Park-in success: more delightful for age 4 (bigger truck, soft bounce, brief yellow sparkles), still ~1–2s.
- Parent theme switcher: each palette includes a warm yellow accent; add default **陽光黃 / Sunny Yellow** accent-forward palette; Engineering Orange warmer; Logistics and Bus Blue keep identity + yellow highlights.
- SemVer honest: original slice MINOR → 0.2.0; polish PATCH → 0.2.1.
- **Do not merge.** Push to `feat/theme-long-vehicles` (force-with-lease only if rebase requires it, and explain).
- Preserve tests; extend theme tests if new palette IDs.
- One slice, bias to action; language lock engineering English + HK Trad UI.

## Acceptance
- Rebased onto latest main after PR #4 (`46f77b9`); TestRunner keeps 7 session + 8 reward-ledger + 7 reward-persistence + theme checks (6 after yellow polish).
- PROGRESS facts updated; PR #5 description updated; no merge.
- Linux: no Swift compile/UAT claimed.

## Mac mini test notes
```sh
cd /Users/carteryu/my-ai-projects/visa-games-app
git fetch origin && git checkout feat/theme-long-vehicles && git pull --ff-only
# if local still on pre-rebase tip:
#   git reset --hard origin/feat/theme-long-vehicles
sh scripts/test.sh
# Expect: PASS: 7 session + 8 reward-ledger + 7 reward-persistence + 6 theme-preference checks
sh scripts/bundle.sh
open ".build/Visa Games.app"
```
Visual: Sunny Yellow default; yellow accents without yellow walls; parade bob; park-in bounce+sparkles; four palettes persist; footer **v0.2.1**; kiosk Escape/Cmd-Q / parent LA regression.

## Essential prompt text — original theme slice (sanitized)

> Overnight theme slice on `feat/theme-long-vehicles`: (1) lock/play watermark parade of five original long-vehicle silhouettes; (2) ~1–2s success park-in demo on lock; (3) parent-only theme switcher with Engineering Orange / Logistics White-Red / Bus Blue via UserDefaults. No trademark art. HK Trad + English only. Do not touch Snapshot/RewardLedger. Version 0.2.0. No merge. Linux has no Swift — Mac mini morning checklist.

## Essential prompt text — kid-yellow polish delta (sanitized)

> Parent Carter Yu: technical PASS on both PRs. PR #4 MERGED to main @ ~46f77b9. PR #5 still OPEN — rebase/update onto latest main, then polish UI for ~4-year-old attractiveness with MORE YELLOW used as accents (not full-screen overstimulation). Cheerful yellow accents for mood/focus/curiosity on buttons, vehicle accents, success flash, soft sun/road stripes; calming soft blues/greens for large backgrounds; rounder shapes, larger TV type, friendlier spacing; keep original long-vehicle silhouettes; no Tomica/Takara/Thomas marks. Update the 3 palettes so each includes a warm yellow accent; add/rename default 陽光黃／Sunny Yellow OR warm Engineering Orange; Logistics and Bus Blue keep identity but add yellow highlights. Watermark parade slightly more playful (subtle bounce/bob). Park-in success more delightful (bigger truck, soft bounce, brief yellow sparkles) still ~1–2s. Version PATCH 0.2.1 honestly. Do NOT merge. Push force-with-lease only if rebase requires it and explain. Update PR #5 and PROGRESS. Preserve/extend theme tests. Prefer codex -m gpt-6-sol else implement carefully. Append: one slice, bias to action, no merge main, no invent reward policy, language lock engineering English + HK Trad UI. Report: SHA, visual changes, Mac mini retest commands.
