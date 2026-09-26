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
