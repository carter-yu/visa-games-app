# 0018 — 筆順動畫 / Stroke-order animation (digits first)

Status: proposed (v0.31.0 / 66). Builds on ADR 0017 (一架一架數) and the v0.30.0 guidance engine.
Keeps ADR 0003 (no sign-in), 0010 (no `assumeIsolated` / `unowned` / KVO hops) and 0011 (no
presentation, window style, level, frame or menu changes).

## Context
Carter approved every Opus default in `visa-games-design/stroke-order/design.md` (D1–D15,
mockups 01–04) on 2026-10-19. One stroke-order model is meant for digits, Latin letters and
Traditional Chinese characters. This ADR covers the build steps S0–S2 (digits 1–10). Letters and
characters (S3–S4) are still design-only.

## Decision
- **One glyph model.** `StrokeGlyph` (strokes = `TracePath`s, turns, script) and
  `StrokeOrderTimeline` (lead, draw, pause at turns, lift, hold) live in
  `VisaCore/StrokeOrder.swift`. Digits adapt `NumeralGlyphs` directly, so there is no second copy
  of the paths: the pen writes exactly the strokes the trace board asks for.
- **Doses (D7).** 教 teach (the rhyme beat seconds), 提 remind (420 u/s), 一閃 glance (700 u/s, no
  pauses). They are pure functions of time, so tests check the D7 totals.
- **★ 點一點.** When the numeral lights up, the smiley pen writes it once on the plate, silently,
  0.2 s after 「N架！」. A dose of 提 drops to 一閃 once the numeral is 識咗. A tap on the plate
  finishes the writing at once, or replays it afterwards (at most 2 times). The round finishes
  0.8 s after the pen is done (never earlier than v0.30's 2.4 s). A tap is never a miss.
- **★★ / ★★★ trace.** While a numeral is being learned, the v0.30 demo car plays as before. Once
  it is 識咗 at 標準, the pen glances over the road silently, at most 3 times, then never again. One
  refresh glance comes after 7 or more days without tracing that numeral. The car and the pen never
  play in the same round. The glance reuses the demo slot in `TapCountGuideRun`, so the first
  touch ends it and paints nothing. A glance is not help. A stall refills the 3 glances.
  多啲 = the car every time; 少啲 = none.
- **Parent.** 數字設定 → 筆順動畫 教 / 提 / 熄, saved in `TapCountSettings.strokeOrder`
  (missing = 提, so v0.30 data loads unchanged). Glance state lives in
  `VisaGames.strokeOrderProgress.v1` (best effort; a failed save never reaches the child).
  Playtests never use up glances.
- **Reduce Motion (D9).** The pen does not glide: each chunk (split at turns, or quarters for 1)
  appears whole and fades in over 0.2 s.
- **Logs.** ★ results gain `stroke_reveal`, `stroke_replays` and `stroke_skips`. Trace results
  gain `stroke_glance`, and `guide_demo` can now read `glance` or `glance_skipped`.
- **Art.** The pen and start dot come verbatim from mockup 01 and are generated into
  `TapCountArt` (`guidePen` with the nib tinted to the reveal colour, `guideStartDot`).

## Consequences
- No new child-facing words. The pen is silent, and ★★ keeps its normal prompt.
- Missing glyph data falls back to the v0.30 behaviour (2.4 s reveal, no glance).
- S3–S4 (letters, 水 and other characters) can add `StrokeGlyph`s without touching the timeline,
  the ★ plate or the glance slot.
