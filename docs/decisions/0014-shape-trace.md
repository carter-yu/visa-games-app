# 0014 — Shape trace phase 1 (畫直線 · 熱身 / 畫形狀 · 跟虛線)

Status: accepted (v0.25.0 / 57); phase 2 in ADR 0015

## Context
Carter approved the 畫線畫形 design with every Opus default, D1–D13
(2026-10-17, 「全部跟 Opus 建議，可以開始做」). Phase 1 ships the two easiest
cards. 描線 was a placeholder on the unbuilt list, and `traceLines` replaces it.

## Decision
- Two new `ActivityKind`s, each with its own parent card and star toggles. Both
  are in `defaultOffKinds`:
  - `traceLines`: 畫直線 · 熱身. Fire-station scene with 3 strokes:
    across → down → across (or a slant when 斜線 is on).
  - `traceShapesDotted`: 畫形狀 · 跟虛線. One shape family per round:
    circle 45 % / square 35 % / ★ triangle 20 % (D2).
- **Order (D1):** lines, then circle, then square, then triangle.
- **Square = 口 in 3 strokes (D3):** stroke ① 丨 (left side), stroke ② 𠃍
  (top, then right side), stroke ③ 一 (bottom).
- **Circle (D4):** starts at 12 o'clock and goes anticlockwise.
- **★ triangle = ∧ only (D5):** two strokes from the apex, no base.
- **Auto-complete (D6):** each shape finishes by itself. No 完成 button, and
  no 擦晒 (擦晒 belongs to the future Free card only).
- **Direction hint on (D7):** a green start arrow and a red end ring. Starting
  at the end says 「跟住箭嘴方向畫啊！」 and then lets the child trace backwards
  (logged as `reverse_direction`, never a miss).
- **Practice only (D8):** every round is `match_mode guided`. There is no visa
  penalty and no mastery evidence (`isPracticeOnly` covers both kinds).
- **Stars after a parent playtest (D11):** a new card's star buttons stay grey
  until the parent has finished one 試玩 round of that card. Tapping a grey star
  shows 「試玩一次先開 / Playtest once before turning on a star」. The log is
  `ParentPlaytestLog` (`VisaGames.playtestedKinds.v1`), and the card shows
  「已試玩 10/17」 or 「未試玩」. Older kinds are unaffected.
- **Vehicle follows the pen (D9):** the vehicle (fire engine, crane hook, paint
  car, taxi) only moves forwards along the path, up to 60u per sample and up to
  150u ahead of the pen. Lifting the pen or leaving the lane makes it wait.
  Going off the lane is never wrong. A hint ring appears after 2 s, and after
  8 s with no progress a ghost demo shows the way once per stroke.
- **「停！」 coaching (D10):** the vehicle stops at every corner until the pen
  turns, and the child hears 「停！轉彎！」. Overshooting a corner by more than 24u,
  or cutting it, is logged but never judged. A line ends with 「停！」 at the red ring.
- **Voice (D12):** Cantonese first, then English (en-GB preferred), through
  `speakWordCue(_:then:)`. There is no Mandarin fallback. With no Cantonese
  voice the cue is silent and only the bubble shows.
- **Copy:** Hong Kong Traditional Chinese only. A test rejects common
  Simplified characters, and English copy must be ASCII.
- **Shared settings** (`ShapeTraceSettings`, `VisaGames.shapeTraceSettings.v1`)
  live under 家長 → 遊戲 → 畫形狀設定 and cover both cards:
  - tolerance 窄 / 標準 / 闊 / 跟連一連 (lane × 1.0 / 1.5 / 2.2);
  - shape weights (step 5, the last shape cannot be 0);
  - direction hint, corner stop, slant lines and dot style.
  Every change is logged as a `config_change`.
- **Layout:** the workspace is y 118–540. Nothing is drawn in the parent corner
  (x ≥ 1060, y ≥ 560). The link card (o / 口 / 人) sits at (790, 566, 250 × 128).
- **Art:** ported from the Opus mockups. `docs/art-shape-trace-source.svg` is
  the curated source, and `scripts/svg_to_shapetraceart.py` (built on
  `svg_to_canvasart.py`) generates `ShapeTraceArt.swift`. No art was drawn by hand.
- **Deals:** 54 enumerated items per card, deterministic per seed, ids
  `traceLines.fireStation.…` and `traceShapes.L1.<scene>.…`. `game_dealt` records
  `gen variants_v1`, `shape_mix`, `tolerance`, `direction_hint`, `corner_stop`
  and `dot_style`. `round_result` adds lifts, off-path, wrong-start, reverse,
  corner overshoot / cut and ghost counts.

## Not in phase 1
The Arrows and Free cards (擦晒 lives on the Free card), the clock as a circle,
the snowman head as a shape, build-a-car, and mastery / stars evidence from
tracing.

## Consequences
- Lanes stay at least lane + 12u apart at every tolerance. At 闊 the two spire
  corridors can overlap near their feet, so the engine judges only against the
  active stroke and never against a neighbour.
- The kiosk tests read every entry in `scripts/` as a file. For that reason the
  art source lives in `docs/`, and the generator turns off `__pycache__`.
