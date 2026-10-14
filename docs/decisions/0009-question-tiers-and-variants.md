# ADR 0009 — Stars are the question tier; seeded question variants (S0)

Status: Accepted by Carter Yu (2026-10-13 20:54 HKT: D1 option A, D2 A+, D3 D, D7 B).
v0.22.0 / build 49 ships slice S0 on `feat/question-gen-v022`.

Design: `new-games/new-games-design.md` (box `/workspace/visa-games-design/`), §1.1, §1.4, §1.5, §7, §8.

## Context

Every `ActivityKind` dealt one fixed question (`ActivityCatalog.xxxQuestion()` took no
arguments). countVehicles was always "3 fire trucks, pick 2 / 3 / 4"; findTheSame was always
"red taxi among fire truck / red taxi / yellow taxi". A child can learn the answer or its slot,
so first-try data from those two kinds says little. `MissionGameAssignment` said "stars are visa
length, not a harder question".

## Decisions

1. **D1 A — ★ is also the question tier.** ★ = L1 入門, ★★ = L2 學緊, ★★★ = L3 挑戰
   (`ActivityLevel(ChildDifficulty)`). Visa length per star is unchanged (5 / 10 / 15 min).
   Amends the "stars are visa length only" note in ADR 0005 / `MissionGameAssignment`.
   Applies to generated kinds only (`QuestionGeneration.generatedKinds`); other kinds still
   deal their fixed item on every star.
2. **Pure, seeded generators.** A question is a function of `(round seed, level,
   avoidingItem)`: FNV-1a → SplitMix64 (`QuestionRNG`) with our own unbiased bounded draw, never
   the global random source. The recorder can rebuild what the child saw. The same kind never
   deals the same `itemID` twice in a row (last item kept in memory only).
3. **countVehicles (test version, no scaffold).** L1 n 1–3 one row; L2 n 2–6 two rows; L3 n 4–10
   scattered on a 5 × 3 jittered grid (vehicles never touch). One hero per question, named in the
   prompt and hint. Numerals n−1 / n / n+1, shifted at 1 and 10 (6 and 9 never together).
   `CountQuestion.isWellFormed` now allows up to 10.
4. **findTheSame.** Hero PNGs only (no recolouring). L1: distractors share neither paint nor body
   family with the target. L2: each distractor shares exactly one (同色唔同款 / 同款唔同色).
   L3: same vehicle; each distractor differs in one detail — facing (mirrored) or a vector
   sticker (star / flag). Exactly one option matches. The yellow taxi / yellow toy car pair is a
   lookalike and never shares a question. Item counts: L1 131, L2 47, L3 180.
5. **Stats stay separable (D9 groundwork).** `game_dealt` gains `gen` (`fixed_v0` |
   `variants_v1`) and `level`; `item` is the generator `itemID`. Lines without `gen` read as
   `fixed_v0`. Wrong-option tags come from the dealt question (`diff:color`, `diff:type`,
   `diff:facing`, `diff:decor:<name>`, `same_*`; count `under_by_1` / `over_by_1` /
   `off_by_2plus` / `numeral_confusion:*`). Rollup keys for generated rounds add the generation
   (`kind|stars|variants_v1`); older readers split on `|` and still read them, so the rollup
   schema stays 2. CSVs gain `question_gen` (+ `level` in rounds). A one-time
   `stats_marker{what: variants_v1, auto: true}` is written at the first launch of this build.
   Review screens are unchanged (the D9 default view is a later slice).
6. **Unchanged rules.** Option shuffle per deal seed, wrong answer halves pending fuel + 10 s
   Think Pause, auto hint after 2 misses, failed saves never block the child. No new interaction
   type, no new game, no text input, no new window. No new OS escape path.

## Consequences

- Parent playtest of a generated kind walks L1 → L2 → L3 on each 試玩 (memory only); the cover
  shows the tier. Playtest questions are separate copies from the child round.
- Mastery stays one estimate per kind; chance stays 1/3 for both kinds (three options).
