# Phase 0 kiosk acceptance — v0.1.0

## Evidence and status

The native source builds on the development host using Swift 6.1.2 and the
macOS Command Line Tools. Automated checks exercise the state model, atomic
JSON persistence, invalid data, authentication result gating, expiry, and key
policy. They do not simulate AppKit, LocalAuthentication, or macOS shortcuts.

Target Mac mini + TV: **not tested**. No target-device observations have been
recorded. Phase 0 acceptance is pending; do not begin child tasks or media work.

On 2026-09-18, the user reported seeing the countdown and locked screen during
a manual run. Device/display configuration was not specified, so this does not
establish target Mac mini acceptance or completion of the checklist below.

Record date, tester, Mac model, macOS version, display configuration, keyboard,
pen/touch hardware, hot corners, and account restrictions before running this
checklist. Use the bundled app, not a second command-line process.

## Manual acceptance record

Every row below is pending on the target device. “Expected” is implementation
intent, not an observed result.

| Check | Procedure and expected result | Target observation |
| --- | --- | --- |
| N1 Setup | Fresh dedicated account: setup appears; only successful parent authentication permits finishing setup. | Not tested |
| N2 Native presentation | Finish setup: one owned screen-filling borderless window appears. | Not tested |
| N3 Chrome | Inspect all edges and corners: no traffic lights, title bar, toolbar, or browser. | Not tested |
| N4 Absolute expiry | Parent grants the test visa: one minute from grant time, including time spent in parent controls. | Model checks pass; GUI not tested |
| N5 Active relaunch | Grant, quit through parent controls, relaunch before expiry: remaining time is preserved. | Model checks pass; GUI not tested |
| N6 Expired relaunch | Relaunch after the stored timestamp: lock appears. | Model checks pass; GUI not tested |
| N7 Parent boundary | Cancel/fail authentication: no access. Succeed: controls appear. Return preserves visa; expiry still applies. Parent access ends after two minutes, sleep, or loss of activation. | Model gating passes; system authentication not tested |
| N8 Version | Branding and v0.1.0 are visible at TV viewing distance. | Not tested |
| N9 Escape | Press Escape in setup, lock, and play: no exit or window change. | Key policy passes; OS not tested |
| N9 Cmd-Tab | Try app switching in each child state; presentation requests suppression. | Not tested |
| N9 Cmd-Q / Cmd-W | Try quit and close in each child state; app rejects them. Authenticated Quit works. | Exit policy passes; OS not tested |
| N9 Mission Control | Try keyboard, trackpad, Spaces, Show Desktop, and Stage Manager entry points. Record any exposure. | Not tested |
| N9 Hot corners | Exercise all configured hot corners, including screen lock and desktop. Record any exposure. | Not tested |
| N9 Menu bar / Dock | Move pointer and drag at all edges; try secondary displays. Record visibility and interaction. | Not tested |
| N9 Sleep/wake | Sleep beyond expiry, wake: lock. Sleep while parent controls are open: authentication required again. | Expiry model passes; OS not tested |
| N9 Relaunch | Crash/force terminate from a parent-controlled session, restart: parent access is never restored. | Model passes; OS not tested |
| Authentication surface | Verify the system prompt appears above the window; cancel returns safely; repeated taps create only one prompt. | Not tested |
| Storage failure | With app closed, back up then corrupt state; relaunch must lock with an error. Parent reset clears the visa. Repeat with unwritable storage. | Store decoding passes; GUI recovery not tested |
| Display change | Disconnect/reconnect TV and change resolution; window resizes to its screen. | Not tested |

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
