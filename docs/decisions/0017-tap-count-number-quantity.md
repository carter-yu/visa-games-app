# 0017 — 一架一架數 / Tap & Count: number and quantity 1–10 (★ 點一點 · ★★ 數完畫 · ★★★ 揀啱數)

Status: proposed (v0.28.0 / 61). Builds on ADR 0014 / 0015 (the shape-trace engine) and keeps
ADR 0003 (no sign-in), 0010 (no `assumeIsolated` / `unowned` / KVO hops) and 0011 (no
presentation, window style, level, frame or menu changes).

## Context
Carter asked for a 1–10 number and quantity game with three ★ levels and a Cantonese + English
voice (「3、three」). The design (`visa-games-design/number-quantity/design.md`, D1–D18, mockups
01–10) was approved with every default on 2026-10-18: Q1 one numeral per round, Q2 ★★★ takes
over-taps and judges only at OK, Q4 Learning Without Tears strokes (9 in one stroke), Q6 the
macOS Cantonese voice (Sinji) plus an English voice, swappable for recorded clips; Q3, Q5,
Q7–Q13 use the design's bold defaults.

## Decision
- **Three new `ActivityKind`s**, each with its own parent card, all in `defaultOffKinds`, all
  gated by the D11 playtest log (`requiresPlaytestBeforeStars`):
  - `tapCountAll` 點一點 (pinned to L1): tap every vehicle; badges in tap order; Stampy counts
    「一、二、三」; the last tap lights the pale numeral 「四架！」. Nothing to get wrong.
  - `tapCountTrace` 數完畫 (L2): the same count, then the set parks in a strip and the numeral
    becomes a trace board on the shape-trace engine (forward-only paint car, the parent's
    tolerance).
  - `tapCountPick` 揀啱數 (L3): a 2×5 yard with N > T vehicles (N = 10 when T = 10). Tap = pick,
    tap again = unpick, 擦晒 clears all picks, OK judges once after a recount. k ≠ T is one miss
    with the existing policy (halve pending, 10 s Think Pause). Right = the numeral trace.
  ★ / ★★ are practice (`match_mode guided`); ★★★ is mastery evidence (`submit`, chance 1/N).
- **Numerals.** Own centre-line glyphs 0–10 (`NumeralGlyphs`, SVG path data). 4, 5 and 10 have
  two strokes; the rest one (9 is one stroke: loop, up, down). The engine gains cubic segments,
  named corners and cusp windows; at a cusp (the middle of 3) the car waits like a corner and the
  pen may snap across the cusp inside the corridor.
- **Deals.** A pure function of (seed, kind, settings, recent targets, avoided item / scene):
  T in the parent's range with 1 and 2 at half weight and the last 3 targets avoided; scene
  changes every round; ★ / ★★ one model in several colours (1–5 in a row, 6–10 in the ten-frame
  cells); ★★★ mixes models in the yard at random bays.
- **Voice.** `SystemSpeechPrompt.speakQueued` queues each number after the last so fast taps are
  all said. A bundled clip `Resources/Voice/<key>.m4a` (and `<key>.en.m4a`) wins over the system
  voice; without either the game is silent. Nothing waits on speech, and a missing voice never
  throws or blocks.
- **Think Pause.** The tap-count board shows the existing pause as a tray card (mockup 06:
  「停一停，想一想！」, 「油少咗半！再諗諗～」, 「15 → 7 分鐘」) and dims everything except the yard and the sign
  (`ThinkPauseOverlay(placement: .tray)`). The countdown, the halving and the pause length are
  unchanged. After the 2nd miss the pause ends with the demo count (rings the first T vehicles);
  the success is then assisted.
- **Layout.** Stage 1280×720. Nothing is drawn or tappable in the parent corner (x ≥ 1060,
  y ≥ 560): 擦晒 at (24, 548), OK at (800, 548)–(1040, 708), legends end at x 1040.
- **Settings.** 「數字設定」 (UserDefaults, shared by the 3 cards): range 1–5 / 1–7 / 1–10, count
  voice, English word, ★★★ badges (1 2 3 / ✓), trace scaffold (虛線路 / 淡框 + 箭嘴), tolerance
  (follow 畫形狀 or own). A failed write never reaches the child.
- **Art.** Ported from the Opus mockups: `docs/art-tap-count-source.svg` copies the mockup defs
  (vehicles, lit layers, glows, markers, buttons, icons) and the Opus scene kit (row / yard /
  strip backdrops per scene, bay posts, empty-bay markers). `scripts/svg_to_tapcountart.py`
  inlines `<use>`, bakes transforms, turns radial gradients into glows and writes
  `TapCountArt.swift`. Text from the mockups is set by the app (CanvasText) so it stays
  translatable. No raster art and no Pillow were used.

## Not in v0.28.0
- Taxi, MTR, rocket and ferry scenes (design §12 N4); only the five mockup scenes ship.
- 叮 / 嘟 sound effects (the marks show; no audio asset yet) and recorded clips (keys reserved).
- The 「表現」 trend panel for Give-N stats (fields are recorded).
- A named-model ★★★ card (「3 架消防車」, Q7 B).

## Consequences
- Tests cover the count invariants (★★★ N > T except T = 10; T ≤ 10; recent targets avoided),
  judging (over / under / exact, eraser, demo, monotonic boards), stroke data for 1–10 (stroke
  counts, starts, corners, every numeral traceable end to end), the default-off flag and the
  playtest gate, perf facts, HK Traditional / ASCII English copy, and source guards (host case,
  no `assumeIsolated` / `unowned` / `presentationOptions` / `styleMask` in the board view, the
  tray Think Pause, settings save, kiosk checklist row).
- The kiosk checklist gains the row 「一架一架數 tap & count (v0.28.0)」.
