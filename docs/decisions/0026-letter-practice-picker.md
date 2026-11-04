# ADR 0026: Parent letter practice picker

Date: 2026-11-04
Status: Source implementation; Mac validation pending

## Decision

Prepare the locked letter picker design D1–D15 for Visa Games 0.37.0 / build 73. One script-neutral `PracticePickerModel` and `ParentPracticeItemPicker` render ordered targets, capability and light state. The letter host owns the draft, validation, review controls and explicit Save. The selected set constrains future targets in both letter games; other ready letters may appear only as comparison cards. Review is off on first v2 Save and, when enabled, uses an explicit child-history pool at most once every four completed letter rounds.

The v2 key `VisaGames.tapLetterSettings.v2` is written only on parent Save. The v1 blob and learning history stay intact. A saved v2 value takes precedence. A corrupt v2 value requires an explicit parent repair choice; it never falls through to stale v1. A ticket with no eligible kind shows a protected unavailable state and the established three-second authenticated parent entry. An existing deal keeps its captured scope through completion; a new Save applies to the next new deal.

Each v2 deal records its selected and effective scope, review policy, revision, source, target and lane. Weekly reports read these historical fields and countable child target events. The report never reads today's settings to explain an old week. Legacy `this_week` arrays are canonicalised when comparing signatures. The letter games retain their stable report names and existing find-first scoring meaning.

ABC/Jolly/Letters and Sounds groups stay in a collapsed school-sequence preset browser; applying one replaces the draft and preserves its teaching order. Manual tile edits restore alphabetical first-pass order. `睇吓練習建議` is disabled with an explanation. The evidence-based P5 workflow and number/Hanzi adoption are later work.

## Rollback and validation limit

An older binary reads the preserved v1 settings, **not the latest v2 selection**. Reinstalling an old binary can therefore ask a different letter set until 0.37.0 is restored; no reverse migration is performed. This limitation belongs in family release notes.

The source was prepared on a Linux box without Swift. `sh scripts/test.sh`, `sh scripts/bundle.sh`, native layout, accessibility, PDF pagination and Mac mini/TV interaction require target Mac validation before release. No install was run here. App-level kiosk controls continue to depend on macOS device policy; the remaining OS escape paths are recorded in `docs/phase-0-kiosk-checklist.md`.
