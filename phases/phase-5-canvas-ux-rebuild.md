# Phase 5 — M5 concept-canvas UX rebuild

Rebuild the child path to the concept canvas (ADR 0007, `docs/ux-rebuild-brief.md`) in five UX
phases. Each UX phase is one PR that ends with Mac mini + TV UAT before the next starts.

| UX phase | Scope | Canvas boards | Needs from Carter first |
| --- | --- | --- | --- |
| 1 Foundation + Depot | Tokens, fonts, TV stage scaling, chunky buttons, vector art, Depot home, Stampy voice bubble, 3-second parent corner, pen glow | 1 (no passport button yet) | — |
| 2 Voice + Activities | Spoken prompts on entry, bubble replay; all 10 games rebuilt to board 2 (stimulus panel + 3 text-free cards); wiggle / hop / hint glow + sounds; vector art for the remaining vehicles. Sketch the 9 other games and the no-video screen on the canvas first. | 2, 7 | Auto-hint → "assisted"? |
| 3 Stamp, Watch, Time's up | Passport-spread stamp + 「出發！」; dark watch screen with road timer and 「仲有 N 分鐘」; 1-minute warning; dusk park-and-sleep scene | 3, 4, 5 | Visa clock start |
| 4 Passport + rules | Saved stamp history, passport screen, stamp badge, unlocks, rounds (progress cones), daily-cap ending | 6 | Rounds, unlocks, daily cap |
| 5 Finish | Recorded Cantonese clips, remove unused PNGs and legacy views, one observed session with the child | — | Whose voice |

## Out of scope

- Kiosk escape-path changes, parent authentication, allowlist playback, visa accounting.
- Reward policy changes without an explicit decision.
- Simplified Chinese; third-party character likeness.

## UX Phase 1 exit evidence

- `sh scripts/test.sh` PASS with the canvas, voice and pen-spark checks.
- `sh scripts/bundle.sh` bundles the fonts.
- Mac mini + TV UAT per the checklist in `PROGRESS.md` (v0.9.0 entry).
