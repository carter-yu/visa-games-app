# visa-games-app

Visa Games（簽證遊戲） — native macOS kiosk edition.

Ritual: **先做再玩**.

**Built by OpenAI GPT-6 Astra LLM through Codex, under the direction of
[Carter Yu](https://github.com/carter-yu).**

Implementation credit: **OpenAI GPT-6 Astra LLM**. Product direction and manual
verification: **Carter Yu**.

This repository is the successor to `carter-yu/visa-games`. The old project proved the family ritual in a browser: finish a pen-first task, earn visa minutes, then watch an approved video. This repo rebuilds the delivery layer as a native macOS app for a dedicated Mac mini + TV.

## Why a new repo

The browser prototype proved the product, but browser fullscreen is not a security boundary. Browser chrome, fullscreen escape affordances, external navigation, and embedded-player UI can create child escape paths.

This repo keeps the product rules and strips away browser-era assumptions.

## Product invariants

- Visa Games / 簽證遊戲.
- Ritual: 先做再玩.
- Child path uses pen + finger only.
- Zero child text inputs.
- Hong Kong Cantonese + English UI.
- Never Simplified Chinese in the UI.
- Approved-content-only playback.
- Visa time is based on an absolute expiry timestamp, not a fragile decrementing counter.
- Parent controls are separated from the child path.
- No unrestricted browser surface is exposed to the child.

## Native target

Initial target: **macOS, Swift, SwiftUI/AppKit where needed**.

The app should own its window, enter kiosk presentation mode, suppress ordinary app chrome, restore its state after relaunch, and make child escape paths explicit and testable.

A native app alone still cannot promise an unbreakable managed-device kiosk on an unmanaged Mac. For the final household deployment, pair the app with a dedicated macOS user plus OS-level restrictions. See `docs/decisions/0001-native-kiosk-boundary.md`.

## Repository status

Phase 0 implementation is v0.1.0. Native build and offline model checks are
available; target Mac mini kiosk acceptance remains pending. See
[`docs/phase-0-kiosk-checklist.md`](docs/phase-0-kiosk-checklist.md).

## Build and run

Requires macOS 13+ and Swift 6 Command Line Tools (or Xcode). No package downloads
or third-party dependencies are needed.

```sh
sh scripts/test.sh
sh scripts/bundle.sh
open ".build/Visa Games.app"
```

The test command runs a dependency-free executable because Command Line Tools
alone do not include XCTest. `swift test` is not the test entry point. The bundle
uses local ad-hoc signing; distribution signing and notarization are not set up.

On first launch choose Parent, authenticate with the Mac account's credentials,
and finish setup. Parent controls offer a one-minute test visa, return, and quit.
The child view has no text fields or media integration. Visa state is written
atomically to `~/Library/Application Support/VisaGames/state.json`; parent unlock
is never persisted. An unreadable state locks the app until a parent repairs or
explicitly resets storage. Keep the account password and biometrics parent-only.

Read the kiosk checklist before launching: the app enters borderless kiosk
presentation immediately and ordinary child-mode quit is intentionally blocked.

## Previous repo

Source product prototype: `https://github.com/carter-yu/visa-games`

Do not mechanically port the old UI. Reuse product rules and validated state-machine ideas; redesign delivery around native macOS constraints.
