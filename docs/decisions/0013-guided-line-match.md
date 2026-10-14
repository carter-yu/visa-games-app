# 0013 — Guided line match (連一連 · 引導)

Status: accepted (v0.24.0); amended v0.24.1 (three ActivityKinds)

## Context
Free line match (ADR 0012) is too open for a ~4-year-old at the easiest tiers.
Parents also need to assign visa stars per difficulty independently, so they can
disable the easiest practice after a week and demote harder cards (Carter
2026-10-15).

## Decision
- **v0.24.1:** three separate `ActivityKind`s, each with its own parent card and
  star toggles (all in `defaultOffKinds`):
  - `lineMatchGuidedStraight` — 連一連 · 沿路送 — 2 straight wide same-row roads
    (former ★ guided geometry; practice only).
  - `lineMatchGuidedBridge` — 連一連 · 沿路過橋 — 3 narrower curved roads with
    exactly one bridge (former ★★ guided; practice only).
  - `lineMatch` — 連一連 · 自己配 — free matching (former ★★★ behaviour; judged
    on 完成).
- Shared `LineMatchSettings` (tolerance + category weights) under the three cards.
  The single 「引導連線」 parent toggle is removed; each kind *is* its mode.
- Guided kinds pin deal geometry (straight = L1 roads, bridge = L2 roads)
  regardless of which visa star the parent enabled; free match uses the mission
  star's `ActivityLevel`.
- After each guided road: speak the word in Cantonese, then English (en-GB
  preferred). No Mandarin fallback; with no Cantonese voice the cue is silent
  and only the bubble shows.
- Going off the road is never a miss; a hint appears after 2 s.
- Guided rounds auto-complete when every road is done; no 完成 / 擦晒.
- Guided rounds are practice only: no visa penalty, no mastery evidence.
- Categories: counts → numeral, body parts → word, animals → word (zodiac at
  bridge / free ★★+).

## Consequences
Design: new-games-design.md "Guided level（引導連線）", mockups 07a–07c.
Parents demote difficulty by turning stars off / on per card — no code change.
