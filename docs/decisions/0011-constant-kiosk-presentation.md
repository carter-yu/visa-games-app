# ADR 0011 — Constant kiosk presentation (macOS 27 executor crash mitigation)

Status: Proposed. v0.21.5 / build 49 on `hotfix/presentation-constant-v0215` (from `main` @
v0.21.4 / 48). The same commit is to be cherry-picked onto `feat/question-gen-v022`. Mac mini
UAT on macOS 27 pending. This is a mitigation: it removes the most likely trigger. It is not a
proven root-cause fix.

## Context

macOS 27.0 (26A428). 0.21.4 and 0.22.x crash again and again in the Swift runtime executor
check (`swift_task_isCurrentExecutor` → `isMainExecutor` reads a bad executor, 0x220 / 0x7c8).
The frames are `ShellView.body` and, once, Apple's `MenuBarClientCore` from
`__CFRunLoopDoBlocks`. Most crashes happen right after leaving the parent page (parent → child).
ADR 0010 on `feat/question-gen-v022` covers the same check; its compiler flag did not stop it.

Up to v0.21.4, `AppDelegate.applyPresentation()` ran on every `model.changed`. On each child ↔
parent switch it changed `NSApp.presentationOptions` (Dock, menu bar, Apple menu, process
switching…), `window.level` (`.mainMenu + 1` ↔ `.normal`), `styleMask` (borderless ↔ titled),
`minSize` and the frame. All of this ran synchronously inside the model mutation. That means it
ran re-entrantly during SwiftUI updates, or inside the `unlock()` Task continuation. One switch
hit MenuBarClientCore, the window server and the SwiftUI hosting-view layout together. Those are
the components in the crash reports.

## Decision

1. **Set once at launch.** In `applicationDidFinishLaunching` the window is borderless, full
   screen and at level `.mainMenu + 1`, with `collectionBehavior = [.fullScreenDisallowsTiling]`.
   `NSApp.presentationOptions` gets the kiosk options (hide Dock and menu bar; disable Apple
   menu, process switching, Force Quit, session termination and hide). These never change while
   the app runs.
2. **Parent shows in the same window.** `ShellView` already renders `ParentSettingsView`.
   Entering or leaving parent changes no style mask, level, frame or presentation options.
   `applyPresentation()` and `parentWindowFrame` are gone.
3. **Quit.** `applicationShouldTerminate` allows quitting only when `session.allowsExit` (parent).
   The in-app 「離開程式」 button still terminates on the next main-loop turn.
   `applicationWillTerminate` resets `presentationOptions = []`. The key monitor is unchanged.
4. **No synchronous AppKit work from the model.** AppDelegate no longer assigns
   `model.changed` (the closure stays nil, so `changed?()` does nothing). Any future AppKit work
   hung on it must be coalesced and deferred with `DispatchQueue.main.async`, not a Swift `Task`.
   A screen-parameter change refits the window to full screen. That refit is coalesced and
   deferred the same way.
5. **No menu mutations.** The app has no `NSMenu` / `mainMenu` code (source guard).
6. **Debug soak hook.** Launch with `VISAGAMES_SOAK=1` (optional `VISAGAMES_SOAK_CYCLES`,
   default 50). An AppKit `Timer` (not a Task) switches parent ↔ child every 1.5 s. The parent
   switch calls `soakEnterParent()`, which runs the same code as the LAContext success branch but
   skips authentication. Each cycle logs `soak cycle i`, then `soak done`. The app stays running.
   Nothing in `Info.plist`, `scripts/` or the Desktop alias sets the variable. Run it from
   Terminal:

   ```sh
   VISAGAMES_SOAK=1 VISAGAMES_SOAK_CYCLES=50 "/Applications/Visa Games.app/Contents/MacOS/VisaGames"
   ```

   Soak cycles write `parent_enter` / `parent_leave` events to the performance records (reason
   `soak`). Use 「清除表現紀錄」 afterwards, or mark that session 「唔計呢段」.

## Consequences

- **Parent mode is a kiosk too.** While parent settings are open, the Dock, menu bar and
  Cmd-Tab stay disabled, and the window stays above other apps. To copy a YouTube link from
  Safari, copy it before opening parent settings, or quit with 「離開程式」 first.
- **Finder is expected to open behind the app** (not yet seen on the Mac mini). 「匯出表現 (CSV)」
  calls `activateFileViewerSelecting`, and the log-folder button calls `NSWorkspace.open`. Finder
  windows sit below the `.mainMenu + 1` window. The files are still written; the parent quits to
  see them. Not changed in this hotfix.
- No titled, resizable parent window any more (it was 960 × 800 by default).
- Child kiosk behaviour is unchanged: it used the same options, level and borderless window.

## OS escape paths

App-level controls are not a substitute for macOS device policy. The child path uses the same
presentation options, level and borderless window as before, so its escape paths are unchanged
(`docs/phase-0-kiosk-checklist.md`, "Remaining OS and physical escape paths"). One line there
changes: parent mode no longer restores normal macOS presentation.

## Tests

`KioskPresentationTests` (VisaCoreChecks source guards):

- `presentationOptions` is assigned only in `applicationDidFinishLaunching` and
  `applicationWillTerminate`.
- `window.level` is set once, at launch. There is no `styleMask =`, `minSize` or
  `applyPresentation`. `setFrame` runs only from launch and the deferred screen refit.
- The soak env var is read only in `KioskSoak`. Every soak entry point checks the gate first.
  The LAContext bypass is reachable only from the soak timer. `unlock()` still enters parent only
  after LAContext succeeds.
