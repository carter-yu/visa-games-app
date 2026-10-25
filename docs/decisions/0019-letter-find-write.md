# ADR 0019 — English letter family: Find & write

Status: Proposed. v0.33.0 / build 68 on `feat/letter-tap-L3-tapLetterWrite-ui`, based on main `e936b57`. Mac mini build and household UAT are pending.

## Decision

- `tapLetterWrite` is the separate, default-off ★★ card. The child finds both letter cards and flips their words before the board transitions to writing the same lowercase letter. A completed trace precedes the stamp and visa handoff.
- Finding retains the existing per-card wrong-answer rule. Writing uses `ShapeTraceBoard` practice events only: an off-path move, wrong start, reversal, lift, or repeated stroke is never submitted to `WrongAnswerPolicy` and never deducts visa minutes.
- LWT is the default letter formation. The parent ball-stick formation toggle is outside this slice and is not wired into the board.
- The child board and speech use English only. The parent card title, help, and suggested ★★ badge use Hong Kong Traditional Chinese and English. The app adds no browser or navigation surface. OS escape paths remain documented in `docs/phase-0-kiosk-checklist.md`.

## Verification

The source includes a find-to-write phase test and version assertions. Native Swift compilation, Mac mini input, TV display, and household UAT remain pending.

## 2026-10-25 parity addendum

- Find & flip and Find & write now show the shared Latin smiley-pen stroke reveal on the letter plaque after the two cards are found. The existing parent tap-count stroke-order setting supplies the dosage; missing glyph data or Off uses a 2.4-second fallback. Stamp or writing starts only after the reveal and flash.
- Find & write uses the Latin stroke timeline for the full car demo and the learned-letter pen glance. The car uses tap-count guide artwork and retains the English mnemonic. A first touch still dismisses either guide without painting or judging a wrong answer.
- Plaque tap replay is not included in this hotfix. The existing plaque button remains a prompt replay.
