# 0013 — Guided line match (連一連 · 引導)

Status: accepted (v0.24.0)

## Context
Free line match (ADR 0012) is too open for a ~4-year-old at the easiest tiers.

## Decision
- ★ and ★★ line-match questions become guided; ★★★ keeps free matching.
- Left = word or numeral card, right = picture or counted objects; each pair has its own coloured road.
- ★: 2 straight, wide, same-row roads. ★★: 3 narrower curved roads with exactly one crossing (bridge).
- After each road: speak the word in Cantonese, then English (en-GB preferred). No Mandarin fallback; with no Cantonese voice the cue is silent and only the bubble shows.
- Going off the road is never a miss; a hint appears after 2 s.
- The round auto-completes when every road is done; no 完成 / 擦晒 buttons.
- Guided rounds are practice only: no visa penalty.
- Off by default; a parent enables it after a playtest.
- Categories: counts → numeral, body parts → word, animals → word.

## Consequences
Design: new-games-design.md "Guided level（引導連線）", mockups 07a–07c.
