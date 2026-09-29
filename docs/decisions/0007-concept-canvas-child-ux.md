# ADR 0007 — Concept-canvas child UX (UX rebuild)

Status: Accepted by Carter Yu (2026-09-29). UX Phase 1 implemented on `feat/ux-p1-canvas-depot`
(v0.9.0 / build 25); Mac mini + TV UAT pending. D9 / D10 remain open.

## Context

`docs/ux-rebuild-brief.md` and a private claude.ai concept canvas (seven 1280×720 boards:
Depot, Activity, Stamped, Watch, Time's up, Passport, Feedback) redesign the child path for a
child of about four who cannot read, points with a Wacom pen and watches a TV.

The Phase 0 audit (report only, no code) found, from source:

- Easy / Medium / Challenge only change visa minutes (10 / 20 / 30). The game is picked from a
  random round seed, every game has one fixed question, and each ticket is one question.
- The app consumed no hover or tablet-proximity events.
- Child screens showed a one-tap Parent button and the version number.
- PR #8 had already been squash-merged to `main` (`e77d8ee`, 2026-09-28).

Carter chose the canvas over the repo's existing look and approved downloading its fonts.

## Decisions

1. **The canvas is the source of truth for the child-facing look.** It supersedes ADR 0006's
   look (storybook sand world, illustrated hero PNGs, wooden-sign styling) board by board as
   screens are rebuilt; screens not yet rebuilt keep the ADR 0006 look. ADR 0006's IP rules
   still apply: original art only, no third-party likeness.
2. **Vector art as data.** Canvas SVG artwork is transcribed into VisaCore (`CanvasArt`,
   parsed by `SVGPathData`) and drawn with SwiftUI `Canvas`, so it stays sharp at TV size with
   no dependencies. The 10-minute ticket uses the canvas's yellow taxi.
3. **Fonts.** Baloo 2 (Latin) with Noto Sans HK (Traditional Chinese) as its cascade, bundled
   under SIL OFL 1.1 with licences (`Resources/Fonts/`). This replaces the brief's system
   rounded font, which remains the fallback if the files are missing.
4. **Stage.** Screens are authored in canvas coordinates (1280×720). Content scales to fit
   inside a 5% TV safe area; scenery fills the screen edge to edge (`DesignTokens.stageLayout`).
5. **Parent entry.** A faint bottom-right corner; only a 3-second hold starts the existing
   macOS parent authentication (unchanged). A visible Parent button remains only for setup and
   storage failures. The version moves from child screens to Parent controls
   (kiosk checklist N8 updated).
6. **Voice (interim).** Cantonese from the Mac's installed zh-HK system voice via
   `AVSpeechSynthesizer`, as ADR 0004's optional-system-speech clause allows. There is no
   Mandarin fallback: without a zh-HK voice the guide is silent and the log says so. Recorded
   clips keyed by `SpokenPrompt.key` replace it in UX Phase 5. D9 (reviewed content pack) stays open.
7. **Pen glow.** An observe-only event monitor feeds the glow: it follows the pen while the
   tablet reports hover, otherwise it appears on touch-down. Every event passes through
   unchanged. Proximity and first-hover log lines answer whether the target Wacom reports hover.
8. **Unchanged:** kiosk key blocking and presentation, parent authentication, allowlist
   playback, visa accounting, reward policy (D1–D7; 10 / 20 / 30 minutes), activity content.

## Open decisions (before UX Phases 2–5)

| Topic | Needed before |
| --- | --- |
| Auto-hint after 2 misses recorded as "assisted" (D7)? | UX Phase 2 |
| Visa clock starts at the correct answer (today) or on the 「出發！」 tap? | UX Phase 3 |
| Rounds per ticket (= stars)? Passport unlocks? Daily-cap ending? | UX Phase 4 |
| Whose voice records the Cantonese clips? | UX Phase 5 |
| Guide name and design (canvas placeholder 「印仔 Stampy」) | UX Phase 5 at the latest |

## Consequences

- New offline checks for tokens, stage fitting, SVG parsing, artwork, tickets, voice choice
  and pen-glow state.
- `DifficultyCardsView` is replaced by `DepotHomeView`. Activity and play screens keep their
  legacy look until UX Phases 2–3, but lose the Parent button and version.
- The fonts add about 12.6 MB to the repository and the app bundle.
