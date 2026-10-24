# ADR 0018 — English letter family: Find & flip

Status: Proposed. v0.31.0 / build 66 on `feat/letter-tap-L2-tapLetterAll-ui`, stacked on L1 `1acfe45`. Mac mini L2 build and household UAT are pending.

## Context

The L1 scheduler and word bank can deal a guarded two-target, ten-card letter board. This slice makes its ★ card playable without adding the ★★ writing board or a parent letter editor. The design is locked in `visa-games-design/letter-tap/design.md` sections 3, 4 and Appendix A.

## Decision

1. `tapLetterAll` is a separate, default-off parent card. It needs one completed parent playtest before a star can be enabled. Its suggested level is ★; ticket stars continue to set visa length.
2. Child copy and speech are English only. The word bank's Cantonese gloss is not exposed to the child. System speech uses the installed English voice, preferring en-GB; no installed English voice means silence with the screen bubble intact.
3. Cards and the target plaque use centre-line house glyphs from `LatinGlyphs`. The guarded starter board can include `f`; the display has a hand-drawn `f` path while the trace catalog remains the L0 subset. Word cards show a picture and a house-glyph initial. Each approved a–e image ID maps to a specific native pictogram; unknown IDs show a safe placeholder.
4. Taps are judged immediately. Each correct target flips to a word card; each wrong card costs one miss and the existing `WrongAnswerPolicy` halves pending minutes after feedback, then starts the existing ten-second Think Pause. The pause card stays in the tray and the letter board remains visible. There is no OK or erase button.
5. The app model owns the existing reward and pause clocks. A pure board model owns found, known-wrong, assisted, and double-tap state. Word deck and letter progress stores save best effort when a child round ends; save failure cannot block the child.
6. The existing performance recorder receives the generated deal, judged card taps, and round result. Per-retap and double-tap event tags are deferred because the current recorder treats each answer attempt as a scored choice. No new analytics backend is added.

## Consequences and verification

The L2 source needs Mac mini Swift compilation and child UAT. The Linux workshop has no `swift` executable, so no native PASS is claimed here. App-level kiosk controls still rely on macOS device policy for OS and physical escape paths; the remaining paths are listed in `docs/phase-0-kiosk-checklist.md`. This board adds no browser or navigation surface.
