# ADR 0010 — No compiler-inserted runtime actor-isolation checks in the app target

Status: Proposed for v0.22.1 / build 50 on `feat/question-gen-v022` (2026-10-14). Needs a
Mac mini build to confirm the toolchain accepts the flag.

## Context

Same crash site three times, with a different bad address each time:

| Build | Signal | Frame |
| --- | --- | --- |
| v0.11.6 / 33 | EXC_BAD_ACCESS 0x1e | `closure #1 in ShellView.body.getter`, `NSHostingView.layout` (parent quit) |
| v0.17.0 / 39 | SIGBUS | `ShellView` layout |
| v0.22.0 / 49 | EXC_BAD_ACCESS KERN_INVALID_ADDRESS 0x220 | `swift_getObjectType` ← `swift_task_isMainExecutorImpl` ← `SerialExecutorRef::isMainExecutor` ← `swift_task_isCurrentExecutorWithFlagsImpl` ← `closure #1 in ShellView.body.getter` ← `ZStack.init`, from the `NSHostingView.beginTransaction` run-loop observer, main thread |

Package is `swift-tools-version: 6.0`, so the app builds in Swift 6 language mode. In that mode
the compiler adds SE-0423 dynamic actor-isolation checks. The `ZStack` content closure in
`ShellView.body` is inferred `@MainActor`. SwiftUI takes it as a pre-concurrency closure, so the
compiler puts a `swift_task_isCurrentExecutor` call at the top of the closure. The same applies to
every `@MainActor` closure handed to a SwiftUI / AppKit API, and to `@objc` thunks.

The crash is inside that check, not in our code: the thread is the main thread (the check would
pass), and the runtime reads an executor identity that is not a valid object (0x1e, 0x220) and
dereferences it. The addresses change between builds, which fits stale or invalid executor
state, not a fixed null field. This is our inference; we do not have the runtime source for the
macOS 27 Swift runtime, and the `.ips` does not show where the bad identity came from. Either
way the check protects nothing here: we are already on main.

`ShellView.body` is the root of every SwiftUI transaction, so it is the first closure checked
and the one that takes the crash. v0.12.0 swapped one method reference for a closure in
`ShellView.body` (PROGRESS slice C). That did not stop the crash, because a plain closure gets
the same check.

## Options

1. **Source changes only** (compute values up front, explicit closures, no `assumeIsolated`).
   Good practice. Does not remove the check: any `@MainActor` builder closure still gets one.
   Moving the content into another view only moves the crash.
2. **`.swiftLanguageMode(.v5)` for the app target.** Removes the checks (they come with Swift 6
   mode). Also turns every Swift 6 concurrency error in the app into a warning or nothing, so
   real off-main mutations of `AppModel` would build again.
3. **`.unsafeFlags(["-Xfrontend", "-disable-dynamic-actor-isolation"])` for the app target.**
   Removes only the SE-0423 runtime checks. All Swift 6 compile-time isolation errors stay.
   SwiftPM rejects unsafe flags only in packages used as a dependency. VisaGames is the root
   package and is built with `swift build` by `scripts/bundle.sh`, so the flag is allowed.

## Decision

Option 3, plus the option 1 hardening.

- `Package.swift`: the `VisaGames` executable target gets
  `.unsafeFlags(["-Xfrontend", "-disable-dynamic-actor-isolation"])`. `VisaCore` and
  `VisaCoreChecks` are unchanged (no UI, no SwiftUI closures).
- `ShellView.body` reads `childMode`, `showsParentCorner` and `childOrLegacy` before the `ZStack`
  builder runs. Every action passed from `ShellView` is an explicit closure
  (`{ model.unlock() }`), not an unapplied method reference (`model.unlock`).
- `AppModel.perf.contextProvider` captures `[weak self]` and returns a lock / not-playtest context
  if the model is gone. The app sources have no `unowned` and no `MainActor.assumeIsolated`.
- The 0.5 s tick is a selector `Timer` on the main run loop (`timerFired(_:)`), not a block
  timer that starts a `Task { @MainActor }` job every tick. The tick now runs straight from the
  run loop, with no Swift job in between.

Why not option 2: the compile-time Swift 6 checks are what keep `AppModel` mutations on the
main actor. The runtime checks only turn a violation the compiler could not see (an Objective-C
callback on the wrong thread) into a crash. Every app callback we have (WebKit delegates, NSEvent
monitors, Timer, NSWorkspace notifications, LAContext async) already runs on main.

Off-main audit for v0.22 (facts, from the source):
- `QuestionGenerator`, `CountVehiclesGenerator`, `FindTheSameGenerator`, `HeroVehicle`,
  `PerformanceQuestionFacts` are pure `VisaCore` value code; they touch no app state.
- `stats_marker{variants_v1}` is emitted from `PerformanceRecorder.launch` inside
  `AppModel.init` on main; only the `PerfEvent` value and the `Sendable` `PerfEventStore` go to the
  recorder queue.
- Playtest tier cycling (`playtestNextLevel`, `playtestLevel`) is set in `startPlaytest` on the
  `@MainActor` model.
- `PerformanceRecorder` is `@MainActor`; only `store` (a `Sendable` struct) and `init` are
  `nonisolated`. Queue blocks use `store` and `VisaGamesLog`, and hop back with
  `Task { @MainActor }` for results.

## Fallback

If the Mac mini toolchain rejects `-disable-dynamic-actor-isolation` (unknown frontend argument),
use option 2 (`swiftSettings: [.swiftLanguageMode(.v5)]` on the app target only), update this
ADR and the source guard, and keep the option 1 hardening.

## Tests

`ActorIsolationTests` (4 source guards in `VisaCoreChecks`): the flag is on the app target only
and there is no `swiftLanguageMode`; no `unowned` / `assumeIsolated` in `Sources/VisaGames`;
no unapplied `model.<AppModel method>` in `ShellView`; weak recorder context, selector timer,
and a `@MainActor` recorder with exactly two `nonisolated` members.

## Not covered

A runtime crash cannot be reproduced offline. Confirm on the Mac mini: build, launch, play
lock → stamp → picker → watch → Time's up, and parent enter / leave / quit. Keep collecting
`.ips` files. If a crash still shows up in `swift_task_isCurrentExecutor*`, the remaining call
site is a hand-written check (none in the app today) or a check inside SwiftUI itself.

## Follow-up (v0.22.2 / hang at depot)

0.22.1 hung at the Visa Depot ticket screen. A `sample` of the hung process showed the
main thread almost entirely idle in the run loop (not busy in generators, not in
`timerFired`, not in `ShellView`). That points to taps not reaching the ticket buttons,
not a livelock.

Changes kept from this ADR: `-disable-dynamic-actor-isolation` stays on the app target.

Changes reverted / adjusted after the hang:

- The 0.5 s **selector Timer** was reverted to `Timer` + `Task { @MainActor in … }` (same
  as pre-0.22.1). The selector rewrite was unnecessary for the crash and is a suspect for
  the hang; prefer the known-good tick path.
- `ShellView.body` no longer precomputes `let content = childOrLegacy`.
- `ParentCornerLayer` no longer uses a full-screen `CanvasStage`. DepotHomeView already
  has its own `ParentCornerEntry`; ShellView skips the overlay on the depot so a second
  GeometryReader cannot swallow ticket taps.
