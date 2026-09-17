# Phase 0 — Native shell and kiosk boundary

Goal: prove that Visa Games can run as a native macOS child-mode shell before porting the game tasks.

## Scope

Build the smallest macOS app that demonstrates:

- native app launch;
- a single owned main window;
- child mode in borderless/fullscreen presentation;
- visible Visa Games branding and version;
- parent unlock entry point;
- local persistence of a minimal state;
- absolute visa expiry timer model;
- relaunch behavior;
- documented escape-path test results on the target Mac mini.

## Out of scope

- tracing task;
- connect task;
- YouTube integration;
- skins;
- cloud sync;
- accounts/auth server;
- LLM teacher;
- remote admin.

## Initial state model

Keep it tiny:

- `setup`
- `lock`
- `parent`
- `play`

`play` contains `endsAt` and optional media placeholder metadata.

On launch, hydrate persisted state. If `endsAt <= now`, return to `lock`.

## Acceptance tests

N1. First launch reaches setup/parent configuration.

N2. After setup, child mode can enter a native fullscreen/borderless presentation owned by the app.

N3. Ordinary app title-bar controls are not exposed in child mode.

N4. Visa time uses an absolute `endsAt` timestamp.

N5. Relaunch during active visa preserves remaining time.

N6. Relaunch after expiry returns to lock.

N7. Parent unlock returns access to parent controls without corrupting child state.

N8. App has a visible version marker.

N9. A manual kiosk test checklist records what happens with Escape, Cmd-Tab, Cmd-Q, Mission Control, hot corners, menu bar, Dock, sleep/wake, and relaunch on the target Mac.

## Stop condition

Do not port child game tasks until N1-N9 are green and the remaining OS-level escape paths are understood.
