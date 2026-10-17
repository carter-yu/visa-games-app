# 0015 — Shape trace phase 2 (畫形狀 · 跟箭嘴 ★★ / 畫形狀 · 自己畫 ★★★)

Status: proposed (v0.26.0 / 58). Builds on ADR 0014.

## Context
Carter passed UAT on phase 1 (PR #24, v0.25.0) and asked for phase 2 on
2026-10-17: the Arrows and Free cards, the clock as a circle, the snowman head,
build-a-car, and ◁ / ▽ from ★★, all per design defaults D1–D13. Phase 1's rules
still apply.

## Decision
- **Two new `ActivityKind`s**, each with its own parent card, both in
  `defaultOffKinds`, and both gated by the D11 playtest log:
  - `traceShapesArrows`: 畫形狀 · 跟箭嘴, pinned to scaffold level L2.
  - `traceShapesFree`: 畫形狀 · 自己畫, pinned to scaffold level L3.
  `game_dealt` keeps `match_mode guided`, so both cards are practice only.
  `round_result` adds `shape_trace_level`.
- **Featured group.** The parent's mix weights (circle 45 / square 35 /
  triangle 20) pick the round's group, recorded as `ShapeTraceQuestion.featured`.
  One round in three is a 砌車仔 garage round. Otherwise the group gets its own
  scene:
  - **circle → snow town:** five subsets of 太陽 / 雪人身 / 雪人頭 / 時鐘.
    The clock and the head are now shapes; when a slot is not drawn, it is
    scenery.
  - **square → castle hall:** three windows in 口 order.
  - **triangle → castle keep:** three closed ▲ roofs. The strokes are 撇, then
    捺, then the base from left to right.
- **砌車仔 (mockup 05).** Strokes in order: body 口, back wheel o, front
  wheel o, then the topper. The topper is a ◁ flag (one stroke), a ▲ sail, or a
  ▽ cone (top edge, then both sides down to the tip). The pole and hitch are
  ready-made. ◁, ▽ and the closed ▲ appear only on ★★ / ★★★; ★ keeps ∧.
  The tray shows 「今日砌」 on ★★, and a finished car says 「砌好喇！嘟嘟，出發！」.
- **★★ look.**
  - Faint 8u grey outlines, no lanes and no dots.
  - The green start arrow and red end, numbered strokes on the current shape,
    and shape-order badges on later shapes.
  - Faint ink chevrons. The paint car follows the pen.
  - The link card (人 / 口 / o) appears outside the garage.
- **★★★ look.**
  - No outline. Grey corner dots (four compass points on a circle), the green
    start arrow, and a red end dot.
  - The child's own crayon ink (16u deep blue). The judged corridor is still the
    stroke centre line × tolerance, so the vehicle model is unchanged.
  - A yellow dot waits where the pen lifted. After each shape, the paint car
    drives once along the child's ink; this lap is skipped under Reduce Motion.
  - A 「照住畫」 model card shows the stroke order.
  - The ink is logged as `ink_outside_ratio` / `ink_outside` (per shape).
- **擦晒 (Free only, mockup 06 button).** It clears only the current shape: its
  ink, its strokes and its progress. Finished shapes never change. Presses have
  a 3 s cooldown. The 4th press says 「唔使擦都得，慢慢畫就得㗎！」, and the 6th
  hides the button until that shape is drawn. Presses are logged as `erasers` /
  `eraser_locked`. `isMonotonicSuccessor` accepts a board after an erase only
  when the erase count went up and the shape index did not drop.
- **Layout.** Nothing is in the parent corner (x ≥ 1060, y ≥ 560).
  - Tray positions: 擦晒 (24, 548), the free status (500, 580), and the model
    card (824, 566, 216 × 128), which ends left of the corner.
  - Shapes on these cards may sit closer than two lanes, down to 36u (pole to
    body is 40u, body to wheels is 50u), because only the active stroke is judged.
- **Art.** Ported from the Opus mockups. `docs/art-shape-trace-source.svg`
  gains:
  - `castle-keep` (06);
  - `garage` (05), with the rotated wrenches and icons baked into plain paths;
  - `eraser-button` (06), drawn without its text;
  - `corner-dot` and `corner-end`.
  `ShapeTraceArt.swift` is regenerated (26 artworks). Small done-looks are
  vector drawing code in the mockups' palette. No raster art and no Pillow were
  used.
- **Deals.** 99 enumerated items per card: snow 45, keep 27, hall 9, garage 18.
  IDs are `traceShapes.L2.…` / `traceShapes.L3.…`. That is fewer than the
  design's "300+"; more scenes would add more.

## Not in phase 2
- The rocket car.
- The 消防局 / 巴士總站 / 貨櫃碼頭 scenes.
- The car drive-off animation (voice and bubble only).
- `traceRoads`.
- The 「表現」 trend tables for ink / eraser stats.
- Mastery or stars evidence from tracing.

## Consequences
- The tests now cover:
  - L2 / L3 well-formedness and that shapes never touch;
  - stroke order for ▲ / ◁ / ▽;
  - featured weights within ±2.5 %, and a garage share of about ⅓;
  - the eraser rules and monotonic commits;
  - Traditional-only copy.
- The source guard still forbids the literal 擦晒 in the board view. The label
  comes from `ShapeTraceCopy` and shows only when `eraserVisible` is true.
