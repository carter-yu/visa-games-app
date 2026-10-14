# ADR 0012 — 連一連 / Line Match (`lineMatch`, slice S5)

Status: Proposed. v0.23.0 / build 54 on `feat/line-match-v023` (stacked on v0.22.4 / 53).
Release build reported OK on the Mac mini. `sh scripts/test.sh` and the TV playtest are still
pending.

Design: `new-games/new-games-design.md` §1.2, §1.5, §1.6, §1.7, §6, §8.4–8.6, §10 (D1 A,
D2 A+, D3 D, D7 B, D12 A+). Mockups `new-games/opus/05a–05i`, `icons-sheet.svg`.

## Context

The child asked for school-style matching: draw a line from a picture to its word, or from a
group of objects to its number. It is the first multi-step game and the first child drag. Carter
locked the rules on 2026-10-13/14: judge only at 完成 (D3), off-path is never a miss and the
tolerance is parent-adjustable (D2), new games start off (D7), and the four categories are
dealt by weight (D12).

## Decisions

1. **Kind and D7.** `ActivityKind.lineMatch` is playable. It is the only member of
   `ActivityCatalog.defaultOffKinds`, so it is on **no star** until a parent turns one on in
   家長 → 遊戲:
   - `MissionGameAssignment.defaults` and `normalized()` give unseen kinds their
     `defaultStars(for:)`. That is all three stars for older kinds and none for `lineMatch`.
     A v0.22 store therefore loads with 連一連 off.
   - An empty or corrupt star pool falls back to `defaultOnKinds`, never to `lineMatch`.
   - 試玩 always works and cycles ★ → ★★ → ★★★ like S0.
2. **Generator (`LineMatchGenerator`, VisaCore).** Pure function of (seed, level,
   avoidingItem, settings).
   - **Category:** weighted draw from `QuestionRNG`. ★ never deals the zodiac; its share goes to
     the other three.
   - **Items:** one pick from the pre-enumerated list of valid sets:
     - Words: confusion-safe combinations (B1/B2, A1–A6). ★ uses only the starter pictures.
     - Numbers: ★ 2 numbers 1–5, ≥ 2 apart; ★★ 3 numbers 1–7 with at least one pair 1 apart;
       ★★★ 4 numbers 1–10. 6 and 9 are never together (N1).
   - **Right column:** a derangement, so no pair sits straight across. That is 12 seeded
     shuffles, then a rotation.
   - **Termination:** no unbounded loops. `avoidingItem` rerolls at most 8 times
     (`QuestionGeneration.maxRerolls`).
   - **Item id:** `lineMatch.L2.numbers.minifire.5-3-6` / `lineMatch.L3.zodiac.tiger-pig-…`.
3. **Board (`LineMatchBoard`, VisaCore).** A pure state machine. The app owns the clock and the
   wrong-answer policy.
   - **Lines:** one line per green dot and one per red dot. Drawing into a red dot that already
     has a line moves that line. Redrawing a row replaces its line.
   - **Retract:** letting go off a dot springs the line back (`incomplete_stroke`). Starting on
     the right side gives 「由綠點開始啊」 (`wrong_direction`). Neither is a miss.
   - **完成:** only lit when every row has a line. A grey 完成 answers 「仲有未連嘅」 with no
     penalty. Each judged 完成 is **one** `handleEvaluation` / `playtestHandle` call, so any
     wrong line costs one miss: halve + 10 s Think Pause, auto-hint after 2 misses, depot at 0.
     Right lines lock green. Wrong lines are cleared, and orange rings show through the pause
     plus 1.5 s.
   - **擦晒:** clears unjudged lines only, never the locked green ones. 3 s cooldown with a ring
     countdown. The 4th use says 「試吓撳完成啦！」 and 完成 pulses (glows only under Reduce
     Motion). The 6th use hides it until the next judged 完成. After that, each further use hides
     it again. Never a penalty.
   - **Think Pause:** cancels a live drag. Both buttons are disabled during the pause.
4. **Tolerance (§1.7).** 窄 / 標準 / 闊 = 40 / 60 / 90u hit radius around each dot, default 標準.
   The card itself is always a drop target. Drawn dots (22u) and the layout do not change.
5. **Layout (`LineMatchLayout`, 1280 × 720u).**
   - ★ "wide" (mockups 05a / 05g): 240 × 140 cards. 擦晒 200 × 160 at (24, 548). 完成 240 × 160 at
     (840, 548), with its right edge at 1080.
   - ★★ / ★★★ "side" (mockups 05e / 05h / 05i): 120u-high cards. 擦晒 160 × 160 bottom-left.
     完成 160 × 160 top-right at (1096, 130).
   - Every card is ≥ 80u from both buttons. Nothing sits in the parent corner keep-out
     (1196, 640, 84 × 80). The widest drop zone never reaches it. A VisaCore test checks all of
     this.
6. **Input (§8.4).** One SwiftUI `DragGesture(minimumDistance: 0)` on a full-stage clear layer
   in `LineMatchBoardView`. The live line and the mini truck are view `@State` in stage units.
   The model only hears begin / end / cancel (system cancel is detected via `@GestureState`
   reset). No `Task`, timer or model publish per drag event. No text input, context menu, link
   or navigation.
7. **Art.** `scripts/svg_to_canvasart.py` converts the Opus icons (`icons-sheet.svg` / 05*.svg)
   into `Sources/VisaCore/LineMatchArt.swift` (generated).
   - It covers 24 picture / count icons plus the mini truck.
   - `CanvasArtElement` gains an optional `clip` and `CanvasArtStyle` gains `dashPhase`. Both
     are drawn by `VectorArtRenderer`.
8. **Stats.**
   - **`game_dealt`:** `gen: variants_v1`, `level`, `item`, `slots` (right column), `category`,
     `pairs`, `items`, `object`, `tolerance`, `category_mix`. Chance = 1 / pairs!.
   - **`answer_attempt`:** one per judged 完成, `choice: submit`. Tags come from the wrong lines:
     `wrong_target`, `category:<c>`, `pair:<left>><right>`, `confusion:<group>`,
     `count_off_by_1` / `count_off_by_2plus`, `numeral_confusion:6-9`, `object:<o>`.
     Fields: `submit`, `wrong_lines`, `right_lines`, `locked`, `eraser_uses`,
     `pre_submit_changes`, `tolerance`, and `repeat_wrong`. `repeat_wrong` is true only when a
     line judged wrong before is wrong again.
   - **`round_result`:** adds `eraser_uses`, `eraser_locked`, `submit_attempts`,
     `pre_submit_changes`, `incomplete_strokes`, `wrong_direction`, `joins`, `tolerance`.
   - **`config_change`:** `lineMatch_tolerance` / `lineMatch_category_weight` /
     `lineMatch_category_mix`.
   - Old records decode unchanged. No new `stats_marker`.
9. **Parent settings.**
   - Stored in UserDefaults `VisaGames.lineMatchSettings.v1`, not the reward snapshot. Missing
     or corrupt → defaults.
   - The tolerance picker and per-category weight steppers (0–100 in steps of 5, with the
     resulting share shown) live under the Games list. The last category cannot go to 0, and
     還原預設 restores 35 / 30 / 20 / 15.
   - Save failure never blocks the child: the settings write is UserDefaults only, and the board
     never checks `storageFailed`.

## Deviations from the design (shipped this way on purpose)

- **Category mix:** ± steppers on relative weights, with the share shown. The design asked for
  four sliders that re-normalise to 100%.
- **★★ word boards** use the 05e side layout (120u-high cards, 完成 top-right) instead of
  mockups 05b–05d / 05f (220 × 104 cards, 完成 in the bottom bar). The design also requires
  every card to be ≥ 120u high.
- **完成 size and place:**
  - At ★★ / ★★★ 完成 is 160 × 160 top-right (as in the mockups), not ≥ 220 × 160 bottom-right.
  - At ★ it sits in the bottom bar ending at x 1080.
  - Neither touches the parent corner.
- **Card sizes:** word picture cards at ★★ / ★★★ are 140 × 120 (mockup 05e), under the design
  text's 200 × 120. Number cards at ★★ are 240 wide (mockup 05h: 220).
- **Motor slips** (`incomplete_stroke`, `wrong_direction`) are counted in `round_result` only.
  They are not logged as `answer_attempt` `motor_only` events. Review and mastery see only
  judged 完成.
- **Hints:**
  - After 2 misses the hint is yellow rings on the first unlocked pair's dots, yellow card
    borders and the hint line.
  - There is no per-object 一、二、三 counting animation for numbers, and no flashing.
  - A grey 完成 gives the line and voice but does not shake.
- **Drop on a taken red dot** moves the other row's line (not specified in the design).
- **Tolerance scope:** per game only (`lineMatch` is the only drag game). There is no global
  setting, and no "suggest narrower" prompt in Review. Review does not yet split by tolerance or
  category; the fields are recorded for later.
- **★ fallback:** if only the zodiac has weight, ★ deals the default numbers / body / animals
  mix.
- **No shared `PenStrokeCapture` / `.workspace` layout** yet. The drag lives in
  `LineMatchBoardView`. Extract it when 揸車畫路 lands.
- **Field name:** `pairs`, not `pair_count`.

## Consequences

- One more drag surface on the child path. Its OS edges are listed in
  `docs/phase-0-kiosk-checklist.md` (連一連 pen drag row, Wacom ExpressKeys). App-level controls
  do not replace macOS device policy.
- Until a parent enables a star, children never see 連一連, so a release is low risk.
- Gesture cancel relies on SwiftUI resetting `@GestureState` after `onEnded`. If drags never
  join on the Mac mini, check that first.
