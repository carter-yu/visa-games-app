# Progress

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
