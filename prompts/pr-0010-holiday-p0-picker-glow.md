# Holiday P0 — Parent-on-garage + almost-home glow + Video Preview Picker (v0.11.0)

Repo: `/workspace/visa-games-app` on branch `feat/ux-p2-p3-activity-watch` @ `f06ae06` (PR #10).
Continue on this branch (preferred). Push to origin; update PR #10. **Do NOT merge to main.**

Linux box: **NO Swift compile**. Do not claim local build/test pass. Tests run on Mac mini later.

## Language lock (HARD)
- UI copy: Hong Kong Traditional Chinese + English only. NEVER Simplified Chinese.
- Commits/docs/prompts: English.
- No Tomica/Thomas/Tayo likenesses.

## Three REQUIRED features

### 1) Parent control layered ON the garage house (Watch only)
- Today: faint `ParentCornerLayer` at canvas (1220,664) globally for child modes; `RoadTimerStrip` has `GarageGlyph` at trailing edge — Carter mistook house for Home.
- Change: On `WatchPlaybackView` / `RoadTimerStrip`, place the 3-second `ParentCornerEntry` **on top of** the garage glyph (ZStack, parent hit target above the house art) so parents can find it.
- Keep 3s long-press only (`DesignTokens.parentHoldSeconds`); tap does nothing. macOS auth path unchanged (`model.unlock`).
- On WatchPlaybackView only: hide/disable the distant faint `ParentCornerLayer` to avoid two corners. Other child screens (Depot, Activity, Stamp, TimesUp, EmptyAllowlist, VideoPicker): keep parent corner usable via global `ParentCornerLayer` and/or embedded entry — do not remove parent exit from non-watch screens.
- Pass `onParentUnlock` into `WatchPlaybackView` → `RoadTimerStrip`. Garage glyph + ParentCornerEntry stacked; enlarge hit target slightly if needed (still looks like garage, not a Parent button).

### 2) Last 1 minute red glow on road timer
- When `progress.almostHome` is true (already ≤60s remaining per `ChildUXProgress`), add a clear red glow / pulse on the `RoadTimerStrip` (road bar + optionally garage) so a ~4yo notices time is almost up.
- Match canvas kid style (`DesignTokens.Palette.tomato` / `stampRed`); soft pulse via opacity animation; respect Reduce Motion if already used elsewhere (static brighter glow OK).
- No scary red X. Keep existing 「仲有 N 分鐘」 and almost-home voice.

### 3) After successful game → Preview list to pick allowlisted video
- Today: `applyEntrySuccess` auto `playAllowlisted(nextShuffled…)` then Stamp → Go → Watch.
- New flow: Activity success → StampSuccess → Go → **VideoPickerView** (if allowlist non-empty) → WatchPlaybackView; if empty keep EmptyAllowlistView; if exactly 1 video, still show the one card so the kid feels choice.
- Stop auto-preselecting shuffle in `applyEntrySuccess` (remove the `playAllowlisted(nextShuffled…)` call). Shuffle helper may remain for later.
- Shell routing in `ShellView.childOrLegacy` after stamp Go (`!awaitingDeparture`, play mode):
  1. empty allowlist → `EmptyAllowlistView`
  2. allowlist non-empty AND `activePlayVideoID == nil` → new `VideoPickerView`
  3. else with ticket → `WatchPlaybackView`
- Selecting a card calls existing `playAllowlisted(id:)` (allowlist gate unchanged).
- Large TV targets, Traditional Chinese prompts e.g. 「揀片睇！」 / "Pick a video!", optional guideVoice via new `SpokenPrompt.pickVideo` (add carefully to `allUXLines`).
- Thumbnails: use `ApprovedVideo.thumbnailURL` / existing `AsyncImage` pattern like parent `AllowlistThumbnail` if present; placeholder vehicle art (`ticket.artwork` or `CanvasArt`) if missing/failed. No new network dependency that blocks offline (AsyncImage failure → placeholder).
- Logs via `VisaGamesLog`: picker open / pick.

## Holiday P0 extras
- Bump CFBundleShortVersionString / build to **0.11.0 / 27** in `Resources/Info.plist` + parent footer `Visa Games v0.11.0`.
- Update PROGRESS.md top entry for the three locks.
- Update ADR 0007 §5 parent entry: on Watch, parent is 3s hold on garage glyph (Carter 2026-09-30); faint corner remains elsewhere.
- Offline tests: almostHome already tested; add SpokenPrompt.pickVideo to traditional check; bump PASS banner count if adding a check; keep suite green conceptually.
- Archive this prompt (already at this path).

## Out of scope
Passport unlocks, rounds=stars, daily-cap ending, recorded Cantonese audio (D9), merging main, inventing D6/D10.

## Implementation hints
- Key files: `StampWatchTimesUpViews.swift`, `ParentCornerEntry.swift`, `AppDelegate.swift` (`applyEntrySuccess`, `ShellView`, `confirmDeparture`), `CantoneseVoice.swift`, `ChildUXProgress.swift`, `ApprovedVideo.swift`, `DepotHomeView.swift` (style reference), `ChildUXProgressTests.swift`, `SessionTests.swift` PASS banner, ADR `docs/decisions/0007-concept-canvas-child-ux.md`.
- New view can live in `StampWatchTimesUpViews.swift` or `VideoPickerView.swift` under Sources/VisaGames (Package.swift uses directory sources — no manifest edit needed for new files).
- Style: match CanvasStage / CanvasText / ChunkyButtonStyle / metrics.u / canvasPlaced patterns.
- Accessibility labels bilingual HK Trad + English.

## Commit & push
- One or more English commits with CHANGE notes covering the three features + version bump.
- `git push -u origin HEAD` to update PR #10.
- Do not merge.

## Report when done
Tip SHA, version/build, files changed, one-paragraph flow diagram, blockers, Mac mini UAT checklist.
