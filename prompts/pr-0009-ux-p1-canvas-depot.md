# Prompt archive — PR #9 UX Phase 1: concept-canvas foundation + Depot (v0.9.0)

- Date: 2026-09-29 (HK)
- Branch: `feat/ux-p1-canvas-depot` (from `main` @ `e77d8ee`)
- Model: Claude Code (Claude Opus 5.5)
- Repo: carter-yu/visa-games-app
- Inputs: `docs/ux-rebuild-brief.md` (handoff from a claude.ai design session) and Carter's private concept canvas (7 boards)

## Instructions (essential, in order)

1. "Read docs/ux-rebuild-brief.md, AGENTS.md, PROGRESS.md and the ADRs in docs/. Do Phase 0 only: audit the current child-facing UI against the brief, answer the two 'unverified' questions in section 1, and propose a file-by-file plan for Phase 1. Ask me which branch to base on. Do not change any code until I approve."
2. Development happens on a MacBook; production is a Mac mini connected to a TV and a Wacom tablet.
3. "I prefer the concept canvas … rebuild the repo to this canvas." Asked for the phase plan and when the app gets close to the canvas.
4. "Use main. Go-ahead for Phase 1." Font download approved: Baloo 2 + Noto Sans HK from google/fonts (SIL OFL 1.1).

## Constraints carried from the brief and repo

- UI text: Hong Kong Traditional Chinese + English only; never Simplified Chinese.
- Original art only; no Tayo, Tomica, Thomas or Gakken likeness.
- Do not change kiosk escape-path blocking, parent authentication, allowlist playback, visa accounting or reward policy without an explicit decision.
- Small reviewable PRs; tests first; run `sh scripts/test.sh`; update PROGRESS.md with facts.

## Delivered

- Phase 0 audit answers (see PROGRESS.md and ADR 0007).
- Canvas design system, vector art, Depot home (board 1), Cantonese system-voice bubble, 3-second parent corner, pen glow, fonts, ADR 0007, phase file, checklist updates, v0.9.0 / 25.
