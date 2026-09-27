# Progress

- 2026-09-27: PR #8 PATCH **v0.6.2** — parent allowlist paste-URL auto-fills title + preview (oEmbed); duration explained. Do not merge; Mac mini UAT pending.
  - Carter ask: extract title + preview from YouTube; explain Duration / why default 120; can duration come from YouTube? Clarification (Mac mini): happy path = paste URL/id only → Add; title/duration not required.
  - Auto-fetch: `YouTubeOEmbed.requestURL` + `parse` (no API key). Parent Add calls oEmbed; stores title into existing `titleEnglish` / `titleCantonese` (CJK → Cantonese field as raw evidence; no invented translation). Preview remains derived `img.youtube.com/vi/{id}/hqdefault.jpg` (oEmbed thumbnail_url also parsed for completeness). Fetching status: 「正在取得片名… / Fetching title…」. Failure still allows add with id + optional Advanced + thumb-from-id.
  - UX: one primary URL/id field + Add; Title/Duration demoted under DisclosureGroup 「進階（可選） / Advanced (optional)」. Duration is **D4 budget-fit** (not live player length); default **120** scaffold when parent only pasted id (upsert needs > 0). oEmbed does **not** return duration — no fragile watch-page scrape in M4; YouTube Data API key left as future; manual Advanced override kept.
  - Tests: +1 scoped-playback (`testYouTubeOEmbedURLAndParseFixture`, fixture JSON only) → expect PASS banner **10+10+7+6+9+12**.
  - Version: Info.plist **0.6.2 / 18**, footer **v0.6.2**. Prompt: `prompts/pr-0008-m4-parent-allowlist-oembed-title.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here. D8 scoped playback unchanged. M4 not claimed complete.
  - Exact next task: Mac mini — fetch tip of `feat/m4-gakken-style-activities`, `sh scripts/test.sh` (expect 10+10+7+6+9+12), `sh scripts/bundle.sh`, Parent → Allowlist → paste URL only → Add → title+thumb appear; offline oEmbed fail still adds; Advanced optional; footer v0.6.2. Do not merge until Carter OK.


- 2026-09-27: PR #8 PATCH **v0.6.1** — parent allowlist shows YouTube-style preview thumbnail beside Title + ID. Do not merge; Mac mini UAT pending.
  - Carter (Mac mini): add the preview image to the allowed video — parent allowlist rows should show a YouTube-style preview/thumbnail next to Title + ID.
  - Approach (offline-friendly): derive `https://img.youtube.com/vi/{VIDEO_ID}/hqdefault.jpg` from the allowlisted id (`YouTubeEmbedURL.thumbnailURL` + `ApprovedVideo.thumbnailURL`). Nothing extra persisted — Codable allowlist JSON stays backward compatible. No custom image paste required.
  - Parent UI: `AllowlistVideoThumbnail` (SwiftUI `AsyncImage`) beside Title + ID; network failure / invalid id → play-rectangle placeholder (no crash). Still thumbnail CDN only; D8 scoped embed playback unchanged.
  - Tests: +1 scoped-playback (`testYouTubeThumbnailURLDerivedFromID`) → expect PASS banner **10+10+7+6+8+12**.
  - Version: Info.plist **0.6.1 / 17**, footer **v0.6.1**. Prompt: `prompts/pr-0008-m4-parent-allowlist-preview-thumbnail.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here. M4 not claimed complete.
  - Exact next task: Mac mini — fetch tip of `feat/m4-gakken-style-activities`, `sh scripts/test.sh` (expect 10+10+7+6+8+12), `sh scripts/bundle.sh`, Parent → Allowlist → rows show thumb + Title + ID; offline/placeholder if CDN fails; Play/Remove/Preview still work; footer v0.6.1. Do not merge until Carter OK.


- 2026-09-27: PR #8 MINOR **v0.6.0** — M4 Gakken-style activity TYPES (original vehicles). Do not merge; Mac mini UAT pending.
  - Base: main @ `5603845` after merge of PR #7 (v0.5.1). Carter Confirmed M3 UAT good; asked for more games referencing Play Smart wipe-clean **activity genres only**.
  - Research (public product description): tracing lines/letters/numbers/shapes, matching, mazes, puzzles, search-and-find, counting/sorting → kiosk genres: two-picture choose, find-the-same, count-to-N, sequencing, maze-lite, path-trace lite, shape sort, connect-the-dots lite. **No Gakken pages/art/titles/packaging copied.** ADR 0005 + `phases/phase-4-gakken-style-activities.md`.
  - VisaCore: `ActivityKind`, `FindSameQuestion`, `CountQuestion`, `SequenceQuestion` stub (`isPlayable == false`), `ActivityCatalog` rotation by round seed, evaluator overloads. Playable: two-picture (existing crane-vs-bus), find-same (tanker target), count (3 logistics trucks → tap 2/3/4).
  - VisaGames: `FindSameActivityView`, `CountActivityView`, `SequenceActivityStub` TODO; AppModel picks kind after difficulty; ShellView switches gate; same D1/D7 + `startPlayVisa` 10/20/30 path. Parent note updated. Footer **v0.6.0**.
  - Tests: +5 activity checks → expect PASS banner **10+10+7+6+7+12**. Prompt: `prompts/pr-0008-m4-gakken-style-activities.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here.
  - Exact next task: Mac mini — fetch tip, `sh scripts/test.sh`, `sh scripts/bundle.sh`, footer v0.6.0, pick Easy/Medium/Challenge repeatedly until all three games appear (兩圖 / 搵相同 / 數車), wrong/retry/hint, visa 10/20/30, allowlist play, Parent Reset still works. Do not merge until Carter OK. D9/D10 remain open.


- 2026-09-27: PR #7 PATCH **v0.5.1** — parent allowlist shows YouTube Title + ID. Do not merge; Mac mini UAT pending.
  - Carter Confirmed (HK Cantonese): allowlist page should show a YouTube Title beside the ID so parents can track what was added.
  - Parent add form gains `parentVideoTitleDraft` + bilingual 「YouTube 標題 / YouTube Title」 field. Upsert writes into existing `ApprovedVideo.titleCantonese` (if draft has CJK) or `titleEnglish` otherwise; empty title leaves both nil. No YouTube network title fetch.
  - Allowlist rows show primary `parentListTitle` (title or 「(未命名 / Untitled)」) and secondary monospaced video id — id is never hidden when a title exists. Title draft clears on successful add.
  - Model: `ApprovedVideo.hasParentTitle` / `parentListTitle`. Existing `testApprovedVideoParentLabelAndUpsert` extended for untitled list semantics. Expect same PASS banner counts (7 scoped-playback).
  - Version: Info.plist **0.5.1 / 15**, footer **v0.5.1**. Prompt: `prompts/pr-0007-m3-parent-allowlist-youtube-title.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here.
  - Exact next task: Mac mini — pull tip, `sh scripts/test.sh`, `sh scripts/bundle.sh`, Parent → Allowlist → add with title (Title+ID), add without title (Untitled+ID), remove/preview still work, footer v0.5.1. Do not merge until Carter OK. M3 not marked complete.

- 2026-09-27: PR #7 MINOR **v0.5.0** — child difficulty cards → task → visa → scoped playback. Mac mini UAT pending; no merge.
  - Evidence: Carter Confirmed in this task the visa-games reference child flow and **10 / 20 / 30 minutes** (600 / 1200 / 1800 seconds); practical D6 closed for this scaffold. D9 IDs/audio and D10 remain open.
  - Added pure ChildDifficulty mapping and configured lock-only Session.startPlayVisa; parent grant remains parent-only. AppModel keeps round selection/UUID in memory, persists D1 + round-unique D7 reward + visa atomically in existing schema 2, and clears task/hint/retry/video on expiry. Lock cards are independent of the durable D1 completion flag.
  - Play shows visa countdown and existing scoped player through PlaybackPolicy, or bilingual parent-add-video guidance. Existing 1200-second viewing cap remains: Challenge requests 1800 but banks at most 1200, with a 1800-second visa. Existing provider viewing-time accounting is still a follow-up; this slice does not claim full budget metering.
  - Tests added before implementation for mapping, repeated successful rounds despite D1, duplicate rejection, assisted recording/cap, child visa boundaries and expiry; extended persistence check for child visa relaunch. Expected Mac runner: 10 session + 10 reward-ledger + 7 reward-persistence + 6 theme-preference + 7 scoped-playback + 7 activity checks.
  - Version: Info.plist **0.5.0 / 14**, footer **v0.5.0**. Prompt archive: `prompts/pr-0007-m3-difficulty-cards-child-flow.md`. ADR 0004 and Phase 3 updated. Existing OS escape paths remain documented in the Phase 0 kiosk checklist.
  - Linux verification: test and bundle each exited 127 (`swift: not found`); no Swift compile/test/native UAT pass claimed. Plist version assertions, shell syntax, and `git diff --check` passed.
  - Exact next task: Mac mini UAT — run test + bundle, open → 3 cards → pick → two pictures → success → YouTube if allowlisted. Check 10/20/30, wrong/retry, hint/assisted, no-allowlist message, expiry → cards → another success without Reset, parent emergency controls, and existing escape-path checklist. M3 is not marked complete.

- 2026-09-27: PR #7 PATCH **v0.4.3** — restore visible two-picture entry gate (ScrollView collapse regression). Do not merge; Mac mini re-UAT pending.
  - Root cause (Carter confirmed): on **v0.4.1** crane/bus targets visible; after pull to **v0.4.2** (`7bdd592`) they vanished while title + Parent + version remained. `entryGateScroll` wrapped `EntryActivityView` in `ScrollView { … }.frame(maxWidth: .infinity, maxHeight: .infinity)` inside a parent `VStack`; unbounded-height ScrollView often collapses to ~0 flexible height, so the two large silhouettes disappear.
  - Fix: remove collapsing ScrollView; restore **direct** `EntryActivityView` in lock/play via `entryGateContent` (0.4.1 proven path) plus `.frame(minHeight: 480)` so the gate cannot shrink away. Keep good 0.4.2 work: Spacer suppression / compact title when showing entry; Reset always persists incomplete ledger; confirmation under Reset; VisaGamesLog; seedTest without `completeEntry`.
  - Tests: no new unit tests (layout-only). Expect same PASS banner as 0.4.2: 8 session + **10** reward-ledger + 7 reward-persistence + 6 theme-preference + 7 scoped-playback + 7 activity.
  - Version: Info.plist + shell footer **0.4.3** (CFBundleVersion 13). Prompt: `prompts/pr-0007-m3-entry-gate-scrollview-collapse.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here.
  - Exact next task: Mac mini — fetch tip, `sh scripts/test.sh` (expect 8+10+7+6+7+7), `sh scripts/bundle.sh`, confirm footer **v0.4.3**, Parent → Reset entry if needed → Return → two large crane/bus silhouettes again on lock/play. Do not merge until Carter OK.


- 2026-09-27: PR #7 PATCH **v0.4.2** — lock entry gate visible + parent Reset persists nil reward + VisaGamesLog. Do not merge; Mac mini re-UAT pending.
  - Root cause (code evidence): (1) **Layout** — `ShellView` had `Spacer()` above and below the mode switch; large `EntryActivityView` (two ~280×220 targets) was compressed/clipped so lock looked like title + 先做再玩 + Parent + version only (「冇 game」). Completed-entry short text still fit (earlier 「入口活動完成」 screenshot). (2) **Reset no-op** — `resetEntryActivityForChildUAT` used `guard let reward else { return }`, so nil reward never persisted and left inconsistent state. (3) **No entry/reset logs** — only ScopedPlayer logs existed, so Reset produced no new lines.
  - Fix: suppress competing Spacers when showing entry gate; wrap `EntryActivityView` in `ScrollView` + `layoutPriority(1)`; compact play-mode visa strip while entry incomplete; parade/success `allowsHitTesting(false)`. Reset always ensures ledger with `entryActivityCompleted=false` (create 60/1200 if nil) and persists; immediate `playbackMessage` under Reset button; `objectWillChange.send()`. Added `VisaGamesLog` → `visa-games-YYYYMMDD.log` (Library + repo `logs/`).
  - Tests: +1 reward-ledger (`testNilRewardMeansEntryIncompleteAndFreshLedgerPersistsFlagFalse`). Expect PASS: 8 session + **10** reward-ledger + 7 reward-persistence + 6 theme-preference + 7 scoped-playback + 7 activity.
  - Version: Info.plist + shell footer **0.4.2** (CFBundleVersion 12). Prompt: `prompts/pr-0007-m3-entry-gate-layout-reset-logs.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here.
  - Exact next task: Mac mini — fetch tip, `sh scripts/test.sh` (expect 8+10+7+6+7+7), `sh scripts/bundle.sh`, Parent → Reset entry (see confirmation) → Return → two large silhouettes on lock/play; open logs folder and confirm `visa-games-*.log` lines. Do not merge until Carter OK.


- 2026-09-27: PR #7 PATCH **v0.4.1** — parent Test viewing budget / Preview no longer completes entry activity (child UAT unblock). Do not merge; Mac mini re-UAT pending.
  - Bug (Carter screenshot): `seedTestViewingBudget()` called `completeEntryActivity`, so lock showed 「入口活動完成 / Entry activity done」 and hid the two-picture game.
  - Fix: seed grants ~60s only via `applyCompletion(id: "parent-test-budget", .unassisted)` when budget ≤ 0; creates RewardLedger(60/1200) if no reward state; **leaves `entryActivityCompleted == false`**. Added `RewardLedger.resetEntryActivityForParentUAT()` + parent button 「重設入口活動（兒童 UAT）/ Reset entry activity (child UAT)」 (clears entry flag + UI hint/retry; keeps viewing seconds).
  - Tests: +1 reward-ledger check (`testResetEntryActivityForParentUATClearsFlagOnly`). Expect PASS: 8 session + **9** reward-ledger + 7 reward-persistence + 6 theme-preference + 7 scoped-playback + 7 activity.
  - Version: Info.plist + shell footer **0.4.1** (CFBundleVersion 11). Prompt: `prompts/pr-0007-m3-parent-test-budget-entry-gate.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here.
  - Exact next task: Mac mini — fetch/pull branch tip, `sh scripts/test.sh` (expect 8+9+7+6+7+7), `sh scripts/bundle.sh`, Parent → Reset entry activity if needed → Return → confirm two-picture on lock; Parent Preview must not hide entry game. Do not merge until Carter OK.

- 2026-09-27: M3 first learning loop scaffold on `feat/m3-first-learning-loop` as **v0.4.0** (MINOR — family-visible two-picture entry gate); Do not merge; Mac mini verification pending.
  - Base: `origin/main` @ `53e5f29` (PR #6 M2 merged; Carter: play works; UI polish deferred). ADR 0002 D1–D5/D7 Confirmed; D8 Confirmed; **D6/D9/D10 still open**.
  - Docs: `docs/decisions/0004-first-learning-loop-m3.md`; `phases/phase-3-first-learning-loop.md`. States scaffold vs open D9 (pack/audio), D6, D10. No unverified YouTube IDs hardcoded as approved pack.
  - VisaCore: `Activity.swift` — `TwoPictureQuestion`, `ActivityOption`, `ActivityEvaluator`, `FirstEntryActivity` (crane vs articulated bus silhouette asset IDs), `ActivityAudioPrompting` + `StubActivityAudioPrompt` (scaffold only; not “audio done”).
  - VisaGames: lock-mode “activities coming later” replaced with large-target `EntryActivityView`; play mode gates video until entry completion (先做再玩). Success → `completeEntryActivity` + `applyCompletion` (stable completion ID, assisted if hint used, zero extra seconds). Wrong → gentle retry. SuccessParkAnimation reused. Parent note: entry game live; YouTube pack still D9.
  - Tests: `ActivityTests` (7) wired into VisaCoreChecks. Expect PASS: 8+8+7+6+7+**7**.
  - Version: Info.plist + shell footer **0.4.0** (CFBundleVersion 10). Prompt archive `prompts/pr-0007-m3-first-learning-loop.md`.
  - Linux workshop: `swift: not found` expected. No Swift compile/test/bundle claimed here. Mac mini must run test + bundle + Wacom UAT before merge.
  - Exact next task: Mac mini — fetch branch, `sh scripts/test.sh` (expect 8+8+7+6+7+7), `sh scripts/bundle.sh`, child entry UAT, parent visa+allowlist after entry; confirm D9 still open. Do not invent pack IDs.

- 2026-09-17: Created `visa-games-app` bootstrap plan as a native macOS successor to `visa-games`.
  - Product invariants preserved: Visa Games / 簽證遊戲, 先做再玩, pen + finger child path, Cantonese + English UI, no Simplified Chinese, parent-controlled approved content, absolute visa expiry timestamp.
  - Architecture reset: Swift + SwiftUI/AppKit target; browser fullscreen is no longer treated as the kiosk boundary.
  - ADR 0001 defines the app-vs-OS security boundary.
  - Phase 0 is intentionally limited to native shell, persistence, timer, parent boundary, and escape-path testing.
  - No child game tasks or media provider integration yet.

- 2026-09-18: Implemented Phase 0 native shell v0.1.0; target-device acceptance remains pending.
  - Added a dependency-free Swift package with a SwiftUI view hosted in one borderless AppKit window, child presentation options, local key filtering, and a parent-only quit action.
  - Added setup/lock/parent/play state, absolute `endsAt` expiry, atomic versioned JSON persistence, relaunch normalization, and fail-closed storage error handling with authenticated reset.
  - Parent controls use macOS device-owner authentication; parent access is not persisted and closes on a two-minute deadline, sleep, or loss of app activation.
  - Added visible bilingual branding and v0.1.0, a parent-only one-minute visa test, and a playback placeholder. No game tasks, browser, or media integration were added.
  - Initial `swift test` could not run because the installed Command Line Tools lack XCTest. The offline test entry point is now `sh scripts/test.sh`, using a dependency-free Swift executable.
  - Verified debug build and seven offline checks for setup/authentication gating, grants, expiry, relaunch, parent round trips, invalid data, persistence, and escape-key/exit policy. The new key-policy check failed to compile before implementation and passed afterward.
  - Verified release build, plist syntax, shell script syntax, and local ad-hoc signature of `.build/Visa Games.app` on the development host (Swift 6.1.2, arm64 macOS).
  - Added build/run instructions and `docs/phase-0-kiosk-checklist.md`, including OS escape paths and an explicit pending target Mac mini + TV acceptance record. Native GUI, system authentication, sleep/wake, and OS shortcut behavior have not been manually verified.
  - N1–N9 are not yet all green. Phase 0 remains the current phase; child tasks and media work must wait for target-device verification.

- 2026-09-18: User reported seeing the countdown and locked screen during a manual run and approved committing and pushing the implementation.
  - Device/display configuration was not specified. Relaunch behavior and the full target-device escape-path checklist remain unverified manually.

- 2026-09-18: Changed the GitHub repository to public at the user's request and added prominent README implementation credit to OpenAI GPT-6 Astra LLM through Codex, with product direction and manual verification credited to Carter Yu.
  - Debug build and all seven offline checks passed. This documentation update does not change app behavior or the v0.1.0 version.

- 2026-09-26: Reconciled Phase 0 / M0 status on the Linux workshop host.
  - Starting commit: `824e4d1`; branch: `chore/m0-status-reconcile`; working tree was clean before this documentation-only update.
  - Phase 0 remains active and acceptance is incomplete. The target Mac mini + TV checklist has no recorded target observations; Wacom input, system authentication, sleep/wake, and N1–N9 acceptance remain unverified on the target. The earlier countdown/lock report does not identify its device configuration.
  - `docs/project-plan.md` is absent. ADR 0001 is the only recorded ADR; no D1–D10 decisions are recorded. This update approves no proposed policy and changes no app behavior, dependencies, UI, or v0.1.0 version.
  - Verification blocker: `sh scripts/test.sh` exited 127 with `swift: not found` on Linux. No current Swift test or build success is claimed. The app shell was not touched; macOS bundling was not run on this host.
  - The smallest permitted follow-up is target-device Phase 0 evidence collection. Child tasks and media integration remain gated by the active phase's N1–N9 stop condition.
  - Exact next task: run `sh scripts/test.sh` and `sh scripts/bundle.sh` on the target Mac mini, then record the tester, macOS/TV/Wacom/account configuration and actual outcomes in `docs/phase-0-kiosk-checklist.md`, including parent authentication, sleep/wake, relaunch, and OS escape paths. Completion is blocked on access to that target configuration and its observations.

- 2026-09-26: Mac mini toolchain green + Carter Reported N1–N9 Pass + Wacom usable; Phase 0 M0 acceptance recorded as Reported.
  - Parent explicit decision (2026-09-26 chat): “N1-N9 all ok. i can use wacom in the app / merge and proceed”. Evidence label: Reported (Carter Yu), not Confirmed lab instrumentation. This overrides the standing line that said not to mark N1–N9 complete for this documentation slice only.
  - Target path: `/Users/carteryu/my-ai-projects/visa-games-app` @ `chore/m0-status-reconcile` / `45ef1dc`. Xcode 27.0 Build 27A266a; Swift 6.4; `xctest` present. `sh scripts/test.sh` → PASS (7 state, timer, authentication-boundary and persistence tests). `sh scripts/bundle.sh` → Built `.build/Visa Games.app`. `open ".build/Visa Games.app"` succeeded. Wacom input usable in the app (Reported).
  - Mac model, exact macOS marketing name, TV model, account name, and hot-corner inventory: Not specified by tester. Automated checks still do not simulate AppKit/LA; household managed-device caveats remain in `docs/phase-0-kiosk-checklist.md`.
  - Documentation-only update on branch `chore/m0-status-reconcile`. No Swift sources, version number, or app behavior changed. Do not invent Phase 1 timer or reward policy.
  - Exact next task: After this Reported M0 acceptance docs land and parent merges via `gh`, open or update the phase file / D decisions needed before child tasks or media work; child tasks and media remain gated until those Phase 1 decisions exist — do not invent Phase 1 policy.

- 2026-09-27: Phase 1 M1 durable gating/rewards starting policy confirmed by Carter Yu.
  - M0 is recorded as Reported at main commit `7c18c65`.
  - D1–D5 and D7 are Confirmed in `docs/decisions/0002-reward-gating-d1-d7.md`; D6, D8, D9, and D10 remain open.
  - Added `phases/phase-1-gating-rewards.md` with the M1 scope, stop condition, P1-0 through P1-4 slices, and exit evidence.
  - Next task: P1-1 reward model + tests. Do not add YouTube or mark M2/media integration done.

- 2026-09-27: P1-1 in-memory reward model + VisaCoreChecks tests (Linux workshop; Swift not available here).
  - Branch: `feat/p1-1-reward-model`. Added `Sources/VisaCore/RewardLedger.swift` (`RewardPolicy`, `RewardLedger`, `SuccessKind`, `SuccessRecord`, `RewardApplyOutcome`) and `Tests/VisaCoreTests/RewardLedgerTests.swift`; wired eight reward checks into `VisaCoreChecks` via `SessionTests.swift` TestRunner. `Session.swift` / `Snapshot.endsAt` left unchanged.
  - Implements ADR 0002 Confirmed D1 (entry activity unlocks parent-configured initial allowance), D2 (answering does not spend viewing budget), D3 (exactly-once per completion ID, parent-set cap, no next-day carryover via injected Calendar day), D7 (language replay unpenalized; assisted vs unassisted recorded separately). Viewing budget kept separate from absolute session deadline. No YouTube/media/UI; no schemaVersion/persistence change (P1-2); D6 not invented; M1 / Mac mini UAT not marked complete.
  - Verification blocker on this host: `swift: not found`. Mac mini must run `sh scripts/test.sh` (expects PASS: 7 session checks + 8 reward-ledger checks).
  - Exact next task: P1-2 durable gating and session accounting — persist reward/allowance state atomically with the existing local state boundary, keep answering time separate from viewing budget, enforce absolute session deadline independently, normalize stale/expired state on relaunch/wake/clock changes, and add failure-path tests for invalid/duplicated/capped/partially written state.

- 2026-09-27: P1-2 durable reward persistence with Snapshot (Linux workshop; Swift not available here).
  - Branch: `feat/p1-2-reward-persistence`. Bumped `Snapshot.schemaVersion` 1 → 2 with in-memory v1→v2 migration (preserves `configured`/`endsAt`; does not invent reward/allowance). Added `RewardState` and `RewardLedger` export/import + `normalizeAfterLoad` (day-boundary clear without new allowance or policy reset). `SnapshotStore` validates reward fields and fails closed on unsupported schema, corrupt JSON, negative/non-finite values, empty completion IDs, and partial payloads. Absolute `endsAt` remains independent of viewing budget; answering remains a no-op on budget.
  - Tests: `Tests/VisaCoreTests/RewardPersistenceTests.swift` adds seven checks (round-trip, duplicate-after-relaunch, day-carryover-after-reload, endsAt independence, v1 migration, invalid/partial fail-closed, answering-after-reload). Existing 7 session + 8 reward-ledger checks retained.
  - No UI / YouTube / AppKit / skin changes. D6 not invented. M1 / Mac mini UAT not marked complete.
  - Verification blocker on this host: `swift: not found`. Mac mini must run `sh scripts/test.sh` (expects PASS: 7 session + 8 reward-ledger + 7 reward-persistence checks).
  - Exact next task: P1-3 budget-aware approved-video boundary (parent-approved videos with duration/budget-fit; stop at budget boundary; ADR 0002 pause/buffering/ad/seek/sleep/timezone via deterministic playback seam; no provider integration).

- 2026-09-27: Implemented the theme-long-vehicles overnight slice on `feat/theme-long-vehicles` as v0.2.0 source; Mac mini verification is pending.
  - Added three Foundation-only `ThemePack` palettes and a `ThemePreferenceStore` using `VisaGames.themePaletteID` in UserDefaults. The authenticated parent view selects the palette; `Snapshot`, `RewardLedger`, and visa/session semantics were not changed.
  - Added five original SwiftUI vehicle silhouettes in a slow, low-opacity lock/play parade. A lock-mode demo tap calls `AppModel.triggerSuccessFeedback()` and shows a short park-in animation; no activity engine or reward grant was connected by this visual slice.
  - Added five theme-preference checks to the offline runner alongside the existing seven session, eight reward-ledger, and seven reward-persistence checks. Updated the bundle version to 0.2.0. `git diff --check`, plist parsing, and shell syntax checks passed on the Linux workshop host.
  - This Linux workshop has no Swift: `sh scripts/test.sh` and `sh scripts/bundle.sh` both exited 127 with `swift: not found`. No Swift compile, test pass, native launch, or visual UAT is claimed here. M1 completion is not claimed.
  - Existing macOS OS-level escape paths remain as documented in `docs/phase-0-kiosk-checklist.md`; app presentation and key filtering do not replace device policy.
  - Exact next task: morning Mac mini checklist — run `sh scripts/test.sh` and confirm 7 + 8 + 7 + 5 checks; run `sh scripts/bundle.sh` and launch the app; visually check all three parent-only palettes persist across relaunch, the five silhouettes move subtly only in lock/play, and the lock demo parks then clears in about two seconds. Recheck parent authentication, Escape/Cmd shortcuts, display edges, and system OS escape paths on the target setup; record actual outcomes before any M1 claim.

- 2026-09-27: Rebased `feat/theme-long-vehicles` onto main after PR #4 merge (`46f77b9`) and polished yellow-accent UI for ~age-4 attractiveness as v0.2.1 (PATCH); Mac mini verification still pending. Do not merge.
  - Resolved rebase conflicts in `PROGRESS.md` and `SessionTests.swift` TestRunner by keeping P1-2 reward-persistence checks and theme checks together (expect PASS: 7 + 8 + 7 + 6).
  - Added default palette `sunnyYellow` (陽光黃 / Sunny Yellow). All four palettes now carry a dedicated warm `yellow` highlight channel; Engineering Orange warmed; Logistics White-Red and Bus Blue keep identity with yellow button/sparkle highlights. Large backgrounds stay calming soft blue/green — yellow is accents only (buttons, vehicle stripe, soft sun/road stripes, success sparkles), not full-screen walls.
  - Watermark parade: subtle bob/bounce plus small yellow accent stripes on silhouettes; still low opacity / child lock+play only. Park-in success: larger truck (~320pt), soft spring bounce, brief yellow sparkle dots; clear still ~1.8s via `triggerSuccessFeedback`. Rounder / larger TV-readable type and friendlier spacing in `ShellView`.
  - Theme preference tests extended (default → sunnyYellow; allCases count 4; bilingual labels; new yellow-accent invariant). Silhouettes unchanged (crane/tanker/bus/dino flatbed/logistics); no Tomica/Takara/Thomas trademarks, logos, faces, or names. HK Traditional Chinese + English only. Snapshot / RewardLedger / reward policy untouched.
  - Verification blocker on this host: `swift: not found`. No Swift compile, test pass, native launch, or visual UAT claimed here. M1 completion not claimed.
  - Exact next task: Mac mini — `git fetch && git checkout feat/theme-long-vehicles && git pull` (or reset to pushed SHA), `sh scripts/test.sh` (expect 7+8+7+6), `sh scripts/bundle.sh`, launch app; visually check Sunny Yellow default + three other palettes, yellow accents without bedroom-yellow walls, playful parade bob, delightful park-in; record outcomes. Do not merge until parent UAT.

- 2026-09-27: Added top-level `prompts/` archive on `feat/theme-long-vehicles` for English Codex/manager prompts used per PR (README + pr-0001…0005). Sanitized; no secrets; engineering English; no Simplified Chinese. Does not change app behavior.

- 2026-09-27: M2 scoped player scaffold (D8) on `feat/m2-scoped-player-scaffold` as **v0.3.0** (MINOR — family-visible ScopedPlayerView stub); Do not merge; Mac mini verification pending.
  - Base: `origin/main` @ `cfc05d4` (PR #5 theme merged). Parent Confirmed D8 (1+4): child path may only use a scoped official YouTube (or approved) embed with allowlist IDs; no arbitrary navigation, URL bar, or unrestricted search; stop on budget/session expiry.
  - Docs: `docs/decisions/0003-youtube-containment-d8.md`; `phases/phase-2-scoped-playback.md`; ADR 0002 open-decisions line updated (D8 → ADR 0003; D6/D9/D10 still open). M1 reward model exists; **P1-3 / P1-4 may still be open** — M1 is not claimed fully closed.
  - VisaCore: `ApprovedVideo` / `VideoAllowlist` / `VideoAllowlistStore` (UserDefaults scaffold), `YouTubeEmbedURL` (nocookie embed construction + arbitrary-URL reject), `PlaybackPolicy` + `FakePlaybackEngine`, `Session.replaceRewardState`.
  - VisaGames: `ScopedPlayerView` (WKWebView, main-frame embed-only, link clicks cancelled, popups denied); parent-only allowlist text fields + add/remove/play; play-mode scoped surface; parent “Test viewing budget” seeds RewardLedger entry/test completion for demos.
  - Tests: 4 scoped-playback checks wired into VisaCoreChecks (allowlist unknown ID; budget/session stop; D8 non-embed reject; upsert/label). Expect PASS: 7+8+7+6+4.
  - Version: Info.plist + shell footer **0.3.0** (CFBundleVersion 4). Prompt archive `prompts/pr-0006-m2-scoped-player-scaffold.md`.
  - Linux workshop: `swift: not found` (no claim from Linux). **Mac mini toolchain green** on tip `cb871e7`: `sh scripts/test.sh` → PASS (7+8+7+6+4); `sh scripts/bundle.sh` → Built `.build/Visa Games.app` with no WK delegate warning after MainActor decisionHandler fix. Manual parent UAT / residual YouTube chrome observation still pending — do not merge until parent UAT.
  - Exact next task: Parent visual UAT on Mac mini (allowlist add → test viewing budget → 1-min visa → play allowlisted; confirm no child URL field; note residual WK/YouTube chrome); then parent merge decision.

- 2026-09-27: PR #6 Parent window and YouTube paste UX source updated to v0.3.1 (PATCH); Mac mini re-UAT pending.
  - Parent mode now uses a titled, resizable, minimizable window with scrollable controls. Returning to child restores borderless full-screen presentation; screen changes resize only the child presentation. Switching to another app no longer ends Parent mode; the existing two-minute deadline and sleep handling remain.
  - Parent allowlist entry extracts an 11-character ID from a bare ID or known YouTube watch, share, and embed URLs. D8 embed construction and child navigation policy remain separate. Added one scoped-playback check with accepted/rejected paste cases; expected offline output is 7+8+7+6+5 checks.
  - Info.plist is 0.3.1 / build 5; shell footer is v0.3.1. Prompt archived in `prompts/pr-0006-m2-parent-window-url-extract.md`.
  - Linux workshop: `sh scripts/test.sh` and `sh scripts/bundle.sh` exited 127 (`swift: not found`). No new Swift compile, test pass, native launch, or Mac mini PASS is claimed. PR #6 remains open; M1 P1-3/P1-4 and M2 target-device evidence remain open. Existing OS escape paths remain documented in `docs/phase-0-kiosk-checklist.md`.

- 2026-09-27: PR #6 parent preview visa fix prepared as v0.3.2 (PATCH); Mac mini re-UAT pending.
  - Added `Session.extendVisaKeepingParent(seconds:now:)`, limited to configured Parent mode and the existing 3600-second grant ceiling. Parent preview now uses the existing test-budget seeding path when needed, ensures a 600-second visa deadline when absent or expired, and refreshes the Parent deadline after a successful start. `Session.grant` still enters play mode.
  - Parent unlock deadline and the matching bilingual UI copy are now ten minutes. The existing Parent `ScopedPlayerView` was already conditional on `activePlayVideoID`; no player view change was needed.
  - Added one offline session check for unconfigured/child rejection, the visa deadline in Parent mode, and the unchanged grant transition. Expected banner: 8 session + 8 reward-ledger + 7 reward-persistence + 6 theme-preference + 5 scoped-playback checks. Info.plist is 0.3.2 / build 6; shell footer is v0.3.2. Prompt archived in `prompts/pr-0006-m2-parent-preview-visa.md`.
  - Linux workshop: `sh scripts/test.sh` and `sh scripts/bundle.sh` each exited 127 (`swift: not found`). `git diff --check`, plist parsing, and shell syntax checks passed. No Swift compile, test pass, native launch, or Mac mini PASS is claimed. PR #6 remains open; M1 P1-3/P1-4 and M2 target-device evidence remain open. OS escape paths remain documented in `docs/phase-0-kiosk-checklist.md`.

- 2026-09-27: PR #6 Link-blocked UAT fix prepared as **v0.3.3** (PATCH); Mac mini re-UAT pending.
  - Mac mini Reported offline green @ `327d6dd` (PASS 8+8+7+6+5; bundle OK) but real Preview play failed with 「已阻擋連結。 / Link blocked (D8).」 — WK policy cancelled YouTube official embed redirects / in-player chrome and stopped playback.
  - VisaCore: `isAllowedEmbedMainFrameURL(_:videoID:)`, `isBenignBlankURL`, `isClearEscapeURL`, and a tight host allowlist for `/embed/<exact-id>` on nocookie + youtube.com / m.youtube.com. Construction still uses nocookie `make(videoID:)`.
  - ScopedPlayerView: allow main-frame official embed family + about:blank; quiet-cancel linkActivated / popup / non-https subframe noise; call `onNavigationRejected` only for real main-frame escapes. ADR 0003 note: same-id embed redirects permitted; watch/search still denied.
  - Added one scoped-playback check for main-frame allow/reject cases. Expected banner: 8+8+7+6+**6**. Info.plist 0.3.3 / build 7; shell footer v0.3.3. Prompt archive `prompts/pr-0006-m2-embed-navigation-relax.md`. Added tracked `logs/README.md` (gitignore `logs/*` except README) for Mac mini UAT notes — no secret dumps.
  - Linux workshop: `swift: not found` expected. **Mac mini toolchain green** @ `7b505b4`: `sh scripts/test.sh` → PASS **8+8+7+6+7**; `sh scripts/bundle.sh` → Built `.build/Visa Games.app` (Info.plist 0.3.4 / build 8). Visual Error 153 / Preview play UAT still pending — do not merge until Carter OK.

- 2026-09-27: PR #6 YouTube Error 153 embed Referer fix + ScopedPlayer logs prepared as **v0.3.4** (PATCH); Mac mini re-UAT pending.
  - Mac mini Reported offline green @ `08c304c` (PASS 8+8+7+6+6; bundle OK) but Preview play showed **Error 153 — Video player configuration error** (likely missing/invalid Referer on bare WK `URLRequest` to youtube-nocookie).
  - VisaCore: `embedHTMLString(videoID:)`, `embedHTMLBaseURL()`, `isAllowedEmbedShellMainFrameURL` (nocookie host-root only). Construction still nocookie `/embed/<id>`; shell is not a general browse grant. `isClearEscapeURL` treats shell as non-escape.
  - ScopedPlayerView: `loadHTMLString` iframe + `referrerpolicy="strict-origin-when-cross-origin"` + meta referrer + baseURL nocookie `/`; `mediaTypesRequiringUserActionForPlayback = []`. Navigation allow shell or `/embed/<id>`; stop only on real escapes. Lightweight nav/fail/finish logs.
  - ScopedPlayerLog: always `~/Library/Logs/VisaGames/scoped-player-YYYYMMDD.log`; also repo `logs/` when `logs/README.md` found walking up from cwd/bundle; optional `VISA_GAMES_LOG_DIR`. Parent button 「開啟日誌資料夾 / Open logs folder」. Updated `logs/README.md` + ADR 0003 Error 153 note.
  - Added one scoped-playback check for HTML shell / referrerpolicy / shell allowlist. Expected banner: 8+8+7+6+**7**. Info.plist 0.3.4 / build 8; shell footer v0.3.4. Prompt archive `prompts/pr-0006-m2-error153-embed-referrer-logs.md`.
  - Linux workshop: `swift: not found` expected. **Mac mini toolchain green** @ `7b505b4`: `sh scripts/test.sh` → PASS **8+8+7+6+7**; `sh scripts/bundle.sh` → Built `.build/Visa Games.app` (Info.plist 0.3.4 / build 8). Visual Error 153 / Preview play UAT still pending — do not merge until Carter OK.

- 2026-09-27: PR #6 Carter Mac mini UAT reported **play works; Error 153 fixed**. v0.3.5 (PATCH) enlarges the ScopedPlayerView surfaces: Parent preview 420–720 pt, Play mode 480–900 pt, and the default Parent window height is 800 pt so the preview has room to grow. The existing HTML shell already uses margin/padding-free `html, body` plus a 100% width/height iframe, so no CSS behavior change was needed.
  - Log review for the reported run: `load mode=htmlString` and the nocookie embed for `zvdtlrMeR3U` succeeded; `wk didFinish` completed; repeated `popup deny url=www.youtube.com/watch` is expected D8 provider chrome; no Error 153 or `navigationRejected` teardown was present. The remaining small-player issue was UI layout, not WK policy.
  - Info.plist is 0.3.5 / build 9; shell footer is v0.3.5. Prompt archive: `prompts/pr-0006-m2-player-size.md`. Mac mini re-UAT is still required for the enlarged layout; PR #6 remains open and must not be merged here.
