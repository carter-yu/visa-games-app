# Phase 0 kiosk acceptance — v0.1.0

## Evidence and status

The native source builds on the development host using Swift 6.1.2 and the
macOS Command Line Tools. Automated checks exercise the state model, atomic
JSON persistence, invalid data, authentication result gating, expiry, and key
policy. They do not simulate AppKit, LocalAuthentication, or macOS shortcuts.

Target Mac mini + TV: **Pass (Reported)** on 2026-09-26 by Carter Yu. Evidence
label is Reported (Carter Yu), not Confirmed lab instrumentation. Phase 0 M0
acceptance is recorded as Reported on that date.

Target run context (Reported by Carter Yu, 2026-09-26):

- Path: `/Users/carteryu/my-ai-projects/visa-games-app` @ `chore/m0-status-reconcile` / `45ef1dc`
- Xcode 27.0 Build 27A266a; Swift 6.4; `xctest` present
- `sh scripts/test.sh` → PASS: 7 state, timer, authentication-boundary and persistence tests
- `sh scripts/bundle.sh` → Built `.build/Visa Games.app`
- `open ".build/Visa Games.app"` succeeded
- Wacom input usable in the app (Reported)
- Mac model: Not specified by tester
- Exact macOS marketing name: Not specified by tester
- TV model / display configuration: Not specified by tester
- Account name / restrictions: Not specified by tester
- Hot-corner inventory: Not specified by tester

On 2026-09-18, the user reported seeing the countdown and locked screen during
a manual run. Device/display configuration was not specified for that earlier
report.

Automated checks still do not simulate AppKit, LocalAuthentication, or macOS
shortcuts. Household managed-device caveats in the sections below still apply.
Use the bundled app, not a second command-line process, for any further target
observations.

## Manual acceptance record

N1–N9 Target observation cells below are **Pass (Reported)** per Carter Yu on
2026-09-26 (“N1-N9 all ok. i can use wacom in the app / merge and proceed”).
“Expected” remains implementation intent; Reported is not Confirmed lab
instrumentation. Rows beyond N1–N9 that Carter did not name stay as previously
recorded unless noted.

| Check | Procedure and expected result | Target observation |
| --- | --- | --- |
| N1 Setup | Fresh dedicated account: setup appears; only successful parent authentication permits finishing setup. | Pass (Reported) |
| N2 Native presentation | Finish setup: one owned screen-filling borderless window appears. | Pass (Reported) |
| N3 Chrome | Inspect all edges and corners: no traffic lights, title bar, toolbar, or browser. | Pass (Reported) |
| N4 Absolute expiry | Parent grants the test visa: one minute from grant time, including time spent in parent controls. | Pass (Reported); model checks also pass |
| N5 Active relaunch | Grant, quit through parent controls, relaunch before expiry: remaining time is preserved. | Pass (Reported); model checks also pass |
| N6 Expired relaunch | Relaunch after the stored timestamp: lock appears. | Pass (Reported); model checks also pass |
| N7 Parent boundary | Cancel/fail authentication: no access. Succeed: controls appear. Return preserves visa; expiry still applies. Parent access ends after two minutes, sleep, or loss of activation. | Pass (Reported); model gating also passes |
| N8 Version | Branding and v0.1.0 are visible at TV viewing distance. Since v0.9.0 the version shows in Parent controls, not on child screens (ADR 0007). | Pass (Reported) for v0.1.0; v0.9.0 placement pending Mac mini UAT |
| N9 Escape | Press Escape in setup, lock, and play: no exit or window change. | Pass (Reported); key policy also passes |
| N9 Cmd-Tab | Try app switching in each child state; presentation requests suppression. | Pass (Reported) |
| N9 Cmd-Q / Cmd-W | Try quit and close in each child state; app rejects them. Authenticated Quit works. | Pass (Reported); exit policy also passes |
| N9 Mission Control | Try keyboard, trackpad, Spaces, Show Desktop, and Stage Manager entry points. Record any exposure. | Pass (Reported); hot-corner inventory not specified by tester |
| N9 Hot corners | Exercise all configured hot corners, including screen lock and desktop. Record any exposure. | Pass (Reported); hot-corner inventory not specified by tester |
| N9 Menu bar / Dock | Move pointer and drag at all edges; try secondary displays. Record visibility and interaction. | Pass (Reported) |
| N9 Sleep/wake | Sleep beyond expiry, wake: lock. Sleep while parent controls are open: authentication required again. | Pass (Reported); expiry model also passes |
| N9 Relaunch | Crash/force terminate from a parent-controlled session, restart: parent access is never restored. | Pass (Reported); model also passes |
| Authentication surface | Verify the system prompt appears above the window; cancel returns safely; repeated taps create only one prompt. | Not tested |
| Storage failure | With app closed, back up then corrupt state; relaunch must lock with an error. Parent reset clears the visa. Repeat with unwritable storage. | Store decoding passes; GUI recovery not tested |
| Display change | Disconnect/reconnect TV and change resolution; window resizes to its screen. | Not tested |
| Parent corner (v0.9.0) | On lock and play, a tap on the faint bottom-right corner does nothing; a 3-second hold opens the macOS authentication prompt. A visible Parent button appears only in setup or after a storage error. The corner is not cut off by TV overscan. | Pending Mac mini UAT |
| Pen glow monitor (v0.9.0) | The pointer monitor only observes: Escape, Cmd-Q, Cmd-W and Cmd-Tab stay blocked in every child state; taps still reach buttons; the glow never blocks a tap. | Pending Mac mini UAT |
| Performance export (v0.20.0) | Parent controls → Advanced → 匯出表現 (CSV): Finder opens `~/Library/Application Support/VisaGames/stats/exports/…` above the kiosk window; Return to the app restores the kiosk; no Finder window is reachable from child screens. | Pending Mac mini UAT |

## Remaining OS and physical escape paths

This is an app-level kiosk, not a managed-device security boundary. Presentation
options and local event filtering are requests to macOS. Their actual effect
must be measured with the table above.

- Mission Control, Spaces, Stage Manager, hot corners, system shortcuts,
  Spotlight, Siri, accessibility shortcuts, notification/system overlays,
  screen locking, and external devices may provide OS-owned surfaces.
- A second display is not covered by another kiosk window. Use one TV/display;
  verify mirroring and display changes on the target.
- Force termination through other sessions, Activity Monitor, remote access,
  administrator tools, crashes, logout, reboot, power loss, and recovery/startup
  controls are outside the app's boundary. Launch-at-login is not configured by
  this app, and a stopped process cannot hide the desktop.
- Parent authentication uses the current macOS account's device-owner policy,
  including its password or enrolled biometrics. This is not a separate parent
  identity. Keep those credentials parent-only and do not enroll child biometrics.
  The authentication dialog itself is an explicit parent system surface and may
  use the macOS system language. It is not a child text-entry task.
- Authenticated parent mode deliberately restores normal macOS presentation.
  Supervise this interval. Parent access is memory-only and expires after two
  minutes, on sleep, or when the app loses activation.
- State is local, unencrypted JSON under the current user's Application Support
  directory. A user with filesystem access can edit/delete it. Changing the
  system clock can extend/shorten an absolute timestamp. Restrict both through
  account/device policy; this app supplies no tamper-proof clock or storage.

Household deployment requires a dedicated non-admin account, parent-controlled
credentials, appropriate device restrictions, login/startup configuration, and
removal/restriction of unrelated applications and remote access. Evaluate any
stronger managed-device guarantees separately. This implementation does not
configure or verify those policies.

For recovery during testing, use Parent → authenticate → Quit. If authentication
or the window fails, a parent must use an OS-controlled recovery route such as
another administrative session or restart. Verify recovery before household use.
