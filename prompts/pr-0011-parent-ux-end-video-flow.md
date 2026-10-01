# Prompt — Parent UX + end-of-video flow (v0.12.0)

You are Claude Code Opus implementing Visa Games on branch `feat/parent-ux-end-video-flow`
(already checked out from `main` @ 511a9b6 / v0.11.6 merge of PR #10).

USE MAXIMUM EFFORT. Do NOT thrift tokens. Prefer one long focused implementation pass.
用盡token要做好.

## Read first (required)
1. `AGENTS.md`, latest `PROGRESS.md` entry (v0.11.6)
2. `docs/ground-rules.md`, `docs/ux-rebuild-brief.md` (parent notes + tokens §3)
3. `docs/decisions/0002-reward-gating-d1-d7.md`, `0003-youtube-containment-d8.md`, `0007-concept-canvas-child-ux.md`
4. Key sources:
   - `Sources/VisaGames/ScopedPlayerView.swift` + `Sources/VisaCore/YouTubeEmbedURL.swift` (embed HTML)
   - `Sources/VisaGames/AppDelegate.swift` (AppModel: activePlayVideoID, tick, stopScopedPlayback, playAllowlisted, parent mode UI in `modeContent` `.parent`)
   - `Sources/VisaGames/StampWatchTimesUpViews.swift` (`WatchPlaybackView`, `TimesUpView`)
   - `Sources/VisaGames/VideoPickerView.swift`
   - `Sources/VisaCore/ChildUXProgress.swift` (`PlayStageRoute`)
   - `Sources/VisaCore/PlaybackPolicy.swift`
   - Design tokens: `DesignTokens`, `DesignSystem`, `DepotHomeView` style (ink outline, chunky, CanvasFont)
5. Existing tests: `Tests/VisaCoreTests/ScopedPlaybackTests.swift`, `ChildUXProgressTests.swift`

## Language
- UI strings: Hong Kong Traditional Chinese + English. NEVER Simplified Chinese.
- Commits / PROGRESS / code comments: English.

## Locked decisions
- Do NOT invent passport unlocks / D6 D9 D10.
- Do NOT change reward minutes 10/20/30, kiosk escape, parent auth mechanism, D8 containment.
- Do NOT merge. Do NOT invent policy.
- OUT OF SCOPE: Parent "pick any designed game to review" — note as **deferred** in PROGRESS only.
- Version: bump to **v0.12.0 / build 34** (MINOR — end-of-video flow + parent UX rebuild).
  Update `Resources/Info.plist` (`CFBundleShortVersionString` / `CFBundleVersion`) and parent footer `Visa Games v0.12.0`.
- Linux box: often NO Swift. Write correct Swift anyway. Do not claim compile pass if `swift` missing.
  Still add/adjust VisaCoreChecks tests for pure-logic pieces.

---

## Slice A — End-of-video flow (REQUIRED)

### Bug (Carter UAT)
Kid finished a long game (~20 min visa), picked a ~5 min allowlisted video. After the video **ended**, UI stayed stuck on the YouTube end/recommendations card while the road timer still showed time left (e.g. 「仲有 12 分鐘」). Child could not pick another video; not taken to Time's up either.

### Desired behavior
When the current allowlisted video **ends** (playback complete / YouTube player ended state from ScopedPlayer):

1. If **visa session still active AND viewing budget remaining > 0**:
   - Clear `activePlayVideoID`
   - Return to **VideoPickerView** (same visa session) so the child can pick another allowlisted video.
   - Do NOT leave the child on the YouTube end screen.

2. If **no time left** — visa expired OR viewing budget is 0 (including mid-video when tick stops for `.budgetExhausted` / `.sessionExpired`):
   - Leave watch UI; go to existing **TimesUp** board (taxi/garage home), not stuck on YT end screen.
   - Prefer reusing the existing TimesUp path (`showTimesUp` / visa-ended seam). When budget hits 0 mid-play while visa clock still has seconds, end the play visa cleanly so TimesUp shows (do not leave the child on picker with a dead budget and a ticking road that cannot start another video).

3. Detect video end **reliably** in `ScopedPlayerView` / WKWebView for the YouTube embed, and wire to AppModel.

### Implementation guidance (Slice A)
- Upgrade embed HTML (`YouTubeEmbedURL.embedHTMLString`) to use the **YouTube IFrame API** (`enablejsapi=1`, API script) so we get `onStateChange` with ended = `0`.
- Bridge to Swift via `WKScriptMessageHandler` (e.g. name `visaPlayer`) posting `{ "event": "ended", "videoID": "..." }`.
- Add `onPlaybackEnded: (() -> Void)?` (or similar) on `ScopedPlayerView`; call on main thread once per load (debounce duplicates).
- Keep D8 containment: no general browser; still only allowlisted embed id; do not loosen navigation rules.
- `AppModel.handleScopedPlaybackEnded()` (name as you like):
  - Guard: only act if `activePlayVideoID` is set and mode is `.play` (parent preview may simply stop/clear).
  - Compute remaining viewing budget + whether session `endsAt` is still in the future.
  - Branch as Desired behavior above.
  - Log via `VisaGamesLog` (HK Trad short + English).
- Wire `WatchPlaybackView` → `ScopedPlayerView` with the new callback into AppModel.
- When tick already stops for budget/session expiry: ensure TimesUp (not YT end card). Today `stopScopedPlayback` only clears ID → picker; change that path for `.budgetExhausted` / `.sessionExpired` in **child play mode** to end visa → TimesUp. Keep navigation-reject behavior sensible (clear play / message; do not invent new policy).
- Pure-logic tests if feasible without UI:
  - e.g. a small helper / decision enum: `VideoEndRouting` / `afterVideoEnded(budgetRemaining:sessionActive:)` → `.picker` vs `.timesUp`
  - Extend `ChildUXProgressTests` or new tests; keep offline.

---

## Slice B — Parent settings + allowlist cards (REQUIRED, same PR)

Rebuild parent mode UI (`modeContent` case `.parent` in AppDelegate, or extract `ParentSettingsView.swift` if cleaner):

Goals:
- **Less text**, canvas-aligned style (reuse tokens/fonts/vectors vibe from child: ink, rounded chunky controls, DesignTokens palette — parent can stay SwiftUI Form/ScrollView; do not require full CanvasStage).
- **Card allowlist**: each video as a card with **thumbnail + title + duration + delete**. Keep Play/Preview on card or as secondary action.
- **Paste URL preview**: when parent pastes URL/ID in the draft field, show thumbnail (+ title if already known / after fetch) **before** add where practical. Reuse oEmbed fetch path; do not break existing addAllowlistedVideo.
- **Fold legalese / UAT into Advanced** (DisclosureGroup or similar):
  - Move `ParentLicenseFooter`, long status blurbs, "Reset entry activity (child UAT)", "Open logs folder", storage reset, quit — into Advanced (or keep Quit/Return visible at bottom — Return must stay easy to find).
  - Keep primary surface short: title, version footer, theme, test 1-min visa, test viewing budget, allowlist paste+cards, Return.
- **Keep working**: unlock auth (unchanged), add/remove allowlist, reset entry (advanced), theme picker, test 1-min visa, test viewing budget, version footer **v0.12.0**.

Do not remove capabilities; only reorganize + restyle.

---

## Engineering / process
1. Implement Slice A + Slice B fully in this branch.
2. Update `PROGRESS.md` top entry with facts: tip intent, Mac mini UAT checklist, note deferred "parent pick any designed game to review".
3. Archive this prompt is already at `prompts/pr-0011-parent-ux-end-video-flow.md`.
4. Commits: coherent English messages (e.g. feat(player): end-of-video → picker or TimesUp; feat(parent): card allowlist UX; chore: v0.12.0 / 34).
5. Run `sh scripts/test.sh` if Swift exists; else note exit 127. `git diff --check`.
6. `git push -u origin feat/parent-ux-end-video-flow`
7. Open PR to **main** with `gh pr create`. Title like:
   `Parent UX + end-of-video → picker/TimesUp (v0.12.0)`
   Body: summarize Slice A + B; UAT needed on Mac mini; do not merge until PASS; list deferred items.
8. Do NOT merge. Do NOT deploy kiosk yourself.

## Deliverables in your final message
- Tip SHA, PR URL, version/build
- Flow summary (ended → picker vs TimesUp)
- What landed vs deferred
- Test status (Linux)
- Mac mini UAT checklist commands

---

## Slice C — Quit crash fix (ALREADY STARTED on branch — KEEP / COMPLETE)

Carter UAT crash (v0.11.6 / 33), Mac mini 2026-10-01 ~08:42 HKT:
- IPS: `~/Library/Logs/DiagnosticReports/VisaGames-2026-10-01-084331.ips`
- EXC_BAD_ACCESS SIGSEGV KERN_INVALID_ADDRESS **0x1e**, main thread
- Stack: `objc_opt_class` → `swift_task_isMainExecutorImpl` → **`closure #1 in ShellView.body.getter`** → `NSHostingView.layout`
- Same pattern as older IPS 2026-09-27 (v0.3.4)
- Log: parent mode 00:42:05Z while ScopedPlayer still live (`c1wAbDZ7pgc`), reset entry, then crash ~00:42:35 (quit from parent; no terminate log historically). Relaunch at 00:42:40.

**Already patched on this branch (do not revert):**
- `AppModel.prepareForTerminate()` + `AppDelegate.prepareForTerminate()` — invalidate timer, remove event monitors, clear observers, clear `activePlayVideoID` / voice / `changed`, set `window.contentView = nil` before further layout
- `ScopedPlayerView.dismantleNSView` + Coordinator.detach
- ShellView.body: local lets + `{ model.unlock() }` instead of method reference

You may refine if needed (e.g. log line, safer WK teardown when adding IFrame API script handlers). Mention Slice C in PROGRESS + PR body. UAT: parent → 離開程式 must exit cleanly with log `terminate —` and no Problem Report.
