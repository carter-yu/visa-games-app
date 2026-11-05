# ADR 0026: Parent letter practice picker

Date: 2026-11-04
Status: Source implementation; Mac validation pending

## Decision

Prepare the locked letter picker design D1–D15 for Visa Games 0.37.0 / build 73. One script-neutral `PracticePickerModel` and `ParentPracticeItemPicker` render ordered targets, capability and light state. The letter host owns the draft, validation, review controls and explicit Save. The selected set constrains future targets in both letter games; other ready letters may appear only as comparison cards. Review is off on first v2 Save and, when enabled, uses an explicit child-history pool at most once every four completed letter rounds.

The v2 key `VisaGames.tapLetterSettings.v2` is written only on parent Save. The v1 blob and learning history stay intact. A saved v2 value takes precedence. A corrupt v2 value requires an explicit parent repair choice; it never falls through to stale v1. A ticket with no eligible kind shows a protected unavailable state and the established three-second authenticated parent entry. An existing deal keeps its captured scope through completion; a new Save applies to the next new deal.

Each v2 deal records its selected and effective scope, review policy, revision, source, target and lane. Weekly reports read these historical fields and countable child target events. The report never reads today's settings to explain an old week. Legacy `this_week` arrays are canonicalised when comparing signatures. The letter games retain their stable report names and existing find-first scoring meaning.

ABC/Jolly/Letters and Sounds groups stay in a collapsed school-sequence preset browser; applying one replaces the draft and preserves its teaching order. Manual tile edits restore alphabetical first-pass order. `睇吓練習建議` is disabled with an explanation. The evidence-based P5 workflow and number/Hanzi adoption are later work.

## Build 78: first-Save rule made explicit

`VisaGames.tapLetterSettings.v1` was never written by any build (it had no parent writer), so
on real installs `load()` returns `.fresh`, not `.legacy`. Builds 73–77 treated `.fresh` as an
active v2 selection (abcde, review off) without a Save, silently dropping the v1 review round.
From build 78 only `.saved` is active (`LetterSelectionLoad.activeSelection`). `.fresh`,
`.legacy` and `.repairV1` keep the v1 generator and its settings (default abcde, review every
4) until the parent's first Save. The editor still proposes review off for that Save and
says so: 「未儲存之前，小朋友照用舊設定（每 4 局溫 1 局）…」, with status
「未儲存 · 而家用緊舊設定」.

## Build 79: picker UI aligned with the app and design (UX review of 78)

Presentation only; behaviour is unchanged from build 78.

- Every control in the picker panel uses the parent page's chunky styles: `ParentSmallButton`,
  count-card choice buttons (`ParentChoiceButton`) and a 開 / 熄 pill for the mirror guard
  (`ParentOnOffRow`). There are no stock macOS buttons or toggles.
- 按學校次序 and 更多字母設定 use the v0.20.1 進階 pattern (`ParentDisclosureButton`): a
  full-width button with a chevron and 打開 / 收埋. A macOS `DisclosureGroup` only opens from
  its small chevron, so pen or finger taps on the words did nothing.
- Tiles are nine columns × 84 pt (fills the 820 pt card width) in four states: lit (lamp + ✓),
  dim (hollow lamp), locked (dashed outline + lock), and 已揀・暫停 / Selected · unavailable
  (warning outline, tap to remove). The legend reuses the tiles' marks and the specified copy.
- 睇吓練習建議 is the disabled fourth preset. Presets carry an English sub-line
  (`PracticePickerPreset.subtitle`) plus any 未開放 letters.
- The header shows 「已揀 N 個 / N selected」 with the 3–5 hint. The pinned save bar adds
  English status words, 「未儲存嘅改動唔會套用。」, and keeps to the 940 pt content column.
- The child 「呢張遊戲票暫時玩唔到」 board scales like `ProviderBlockedView` and adds English.

## Build 80: remaining minors and nits (Carter, 2026-11-05 18:58 HKT)

Copy and layout only; behaviour is unchanged from build 79.

- **Toggle wording is 開／關** (Carter's choice). One source, `ParentToggleCopy`, feeds the
  letter, shape-trace and count cards (`開 On` / `關 Off`). The stroke-order "off" option
  and the letter, review and VPN copy now say 關 instead of 熄. Fix round 1 also changed
  the weekly report, report HTML and CSV notes: review and mirror-guard "off" values are 關,
  assignment sentences say 關咗「…」, and the CSV note says 關片. The Python reference
  generators changed with them. Regenerating every text/HTML golden reproduces the
  committed files byte for byte, because the fixture weeks never switch anything off.
- **Presets** follow mockup 01. A list-style preset shows only its ready letters (`f g h`),
  then its group and count (`ABC group · 5 letters`, `Jolly Phonics 1 · 6 letters`), then
  any not-ready letters (`i、j 未開放 · not ready`). This is
  `PracticePickerModel.label(forPreset:)`. Preset IDs, item lists and the apply step are
  unchanged.
- **Save feedback is bilingual.** Every block reason, storage error and save notice has an
  English line (`LetterPickerMessage`), as does the 搵完寫 star banner. Which reason applies
  is unchanged.
- **Loading keeps the card's height.** The loading state draws the full card structure from
  the saved settings. Since fix round 1, capability warnings use always-reserved slots
  (`ParentPickerNotes`, the summary status row from `LetterSelectionSummary`); see
  `docs/parent-scroll-diagnostics.md`.
- **Letters without glyph paths** (i j l m n p q r s t v w x y z) show the letter in the app's
  rounded font on parent tiles and chips (`ParentLetterSymbol`). Child boards and readiness
  are unchanged.
- **睇吓練習建議** says it isn't in this build. It no longer implies that more practice
  records will turn it on.

## Rollback and validation limit

An older binary reads the preserved v1 settings, **not the latest v2 selection**. Reinstalling an old binary can therefore ask a different letter set until 0.37.0 is restored; no reverse migration is performed. This limitation belongs in family release notes.

The source was prepared on a Linux box without Swift. `sh scripts/test.sh`, `sh scripts/bundle.sh`, native layout, accessibility, PDF pagination and Mac mini/TV interaction require target Mac validation before release. No install was run here. App-level kiosk controls continue to depend on macOS device policy; the remaining OS escape paths are recorded in `docs/phase-0-kiosk-checklist.md`.
