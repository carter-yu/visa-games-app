# PR #1 — M0 status reconcile

> **Reconstruction notice:** This file is **reconstructed** from parent chat + `PROGRESS.md` / checklist updates. It is **not** a verbatim copy of a live-archived filesystem original. Sanitize and treat as engineering intent, not a chat dump.

| Field | Value |
| --- | --- |
| Date | 2026-09-26 (HK) |
| Branch | `chore/m0-status-reconcile` |
| PR | https://github.com/carter-yu/visa-games-app/pull/1 (MERGED → main ~`7c18c65`) |
| Model | Workshop Codex; first status-slice historically credited to gpt-6-astra |
| Goal | Docs-only Phase 0 / M0 status reconcile on the Linux workshop host; later a second docs commit recording Carter Reported N1–N9 Pass + Wacom usable + Mac mini toolchain green |

## Constraints
- Facts only in `PROGRESS.md` and `docs/phase-0-kiosk-checklist.md`. Do not invent Phase 1 timer/reward policy.
- Do **not** mark Confirmed lab instrumentation — evidence label is **Reported (Carter Yu)** when recording acceptance.
- No Swift source, version, or app-behavior changes.
- Codex must **not** merge; parent merges via `gh` after review.
- Language lock: engineering English + HK Traditional Chinese UI only (never Simplified Chinese).
- Linux workshop: `swift: not found` — do not claim test/build green on this host.

## Mac mini diagnostic context (for the acceptance slice)
- Earlier Phase 0 development saw **Command Line Tools–only** tooling where `swift test` / XCTest were unavailable; offline entry became `sh scripts/test.sh`.
- Acceptance recording expects the target Mac mini after **full Xcode** install: Xcode 27.0 Build 27A266a; Swift 6.4; `xctest` present.
- Target path (Reported): `/Users/carteryu/my-ai-projects/visa-games-app` @ `chore/m0-status-reconcile` / `45ef1dc` for the first docs tip before the acceptance commit.

## Acceptance (two docs commits on the same branch)
1. **Reconcile (Linux):** Record that Phase 0 remains active; N1–N9 / Wacom / sleep-wake / target observations unverified; ADR 0001 only; no D1–D10; Linux `scripts/test.sh` exit 127; next task is target-device checklist evidence.
2. **Reported acceptance (after parent chat):** Parent said roughly “N1-N9 all ok. i can use wacom in the app / merge and proceed”. Update checklist N1–N9 to Pass (Reported), note toolchain green + Wacom usable, keep Mac model / TV / hot-corner inventory as Not specified where unstated. Still do not invent Phase 1.

## Essential prompt text (sanitized, reconstructed)

### Slice A — Linux workshop reconcile
> On branch `chore/m0-status-reconcile`, perform a **documentation-only** Phase 0 / M0 status reconcile from the Linux workshop. Starting tip ~`824e4d1`. Working tree should stay free of Swift/app edits.
>
> Facts to record in `PROGRESS.md`:
> - Phase 0 remains the active phase; acceptance incomplete.
> - Target Mac mini + TV checklist has **no** recorded target observations yet; Wacom, system authentication, sleep/wake, and N1–N9 remain unverified on the target.
> - Earlier countdown/lock report does not identify device configuration.
> - `docs/project-plan.md` absent; ADR 0001 is the only ADR; no D1–D10 decisions recorded. Approve no proposed policy.
> - Verification blocker: `sh scripts/test.sh` → exit 127, `swift: not found`. Claim no current Swift test/build success. Do not touch the app shell; do not run macOS bundling claims on Linux.
> - Smallest permitted follow-up: target-device Phase 0 evidence collection. Child tasks and media stay gated by N1–N9.
> - Exact next task: on Mac mini run `sh scripts/test.sh` and `sh scripts/bundle.sh`, then record tester, macOS/TV/Wacom/account configuration and actual outcomes in `docs/phase-0-kiosk-checklist.md`.
>
> Constraints: facts only; do not invent Phase 1; no Simplified Chinese; open a docs PR; **do not merge**.

### Slice B — Carter Reported N1–N9 + toolchain (same PR branch)
> Parent explicit decision (chat): “N1-N9 all ok. i can use wacom in the app / merge and proceed”. Evidence label: **Reported (Carter Yu)**, **not** Confirmed lab instrumentation. This overrides the standing “do not mark N1–N9 complete” line **for this documentation slice only**.
>
> On the same `chore/m0-status-reconcile` branch, docs-only:
> - Record Mac mini toolchain green (full Xcode, not CLT-only): Xcode 27.0 Build 27A266a; Swift 6.4; `xctest` present.
> - `sh scripts/test.sh` → PASS (7 state/timer/auth/persistence checks); `sh scripts/bundle.sh` → Built `.build/Visa Games.app`; `open` succeeded; Wacom usable in the app (Reported).
> - Update `docs/phase-0-kiosk-checklist.md` N1–N9 rows to Pass (Reported). Rows Carter did not name stay as previously recorded / Not specified (Mac model, exact macOS marketing name, TV model, account name, hot-corner inventory).
> - No Swift sources, version number, or app behavior changes. Do **not** invent Phase 1 timer or reward policy.
> - Next task after parent merges via `gh`: open/update phase file / D decisions before child tasks or media — still do not invent Phase 1 policy.
>
> Push the second docs commit; leave merge to the parent.

## Mac mini test notes (for the Reported slice)
```sh
cd /Users/carteryu/my-ai-projects/visa-games-app
git checkout chore/m0-status-reconcile
sh scripts/test.sh
# Expect: PASS (7 session / state / auth / persistence checks)
sh scripts/bundle.sh
open ".build/Visa Games.app"
# Manually exercise N1–N9 + Wacom; record Pass (Reported) only for what was actually observed
```
