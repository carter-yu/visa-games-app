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
| Performance export (v0.20.0) | Parent controls → Advanced → 匯出表現 (CSV): files are written to `~/Library/Application Support/VisaGames/stats/exports/…`. Since v0.21.5 (ADR 0011) Finder opens behind the kiosk window; quit with 「離開程式」 to see it. No Finder window is reachable from child screens. | Pending Mac mini UAT |
| Constant presentation (v0.21.5) | Open and leave parent controls repeatedly (and the `VISAGAMES_SOAK=1` soak, ADR 0011): the window stays borderless and full screen, Dock and menu bar stay hidden in parent mode, no crash. 「離開程式」 quits and restores the Dock / menu bar. | Pending Mac mini UAT (macOS 27) |
| 連一連 pen drag (v0.23.0) | On a 連一連 board, drag a line with the Wacom pen and with a finger: from a green dot to a red dot, then off every screen edge and corner (Dock, hot corners, Mission Control) and into the bottom-right parent corner. Expected: the line follows, letting go off a dot springs it back (no miss); no Dock, menu bar, Mission Control or other OS surface appears; holding still in the corner for 3 s only opens the parent prompt (an explicit parent surface, not an escape). Pen side button (right click) on the board opens no context menu. Record whether Wacom drags arrive as `leftMouseDragged` and whether finger drags work (D8). | Pending Mac mini UAT |
| 畫線畫形 pen trace (v0.25.0) | On 畫直線 and 畫形狀 boards, trace with the Wacom pen and with a finger: follow a lane, leave it, lift the pen, start at the red ring, then drag off every screen edge and corner and into the bottom-right parent corner. Expected: the vehicle waits off the lane (no miss), 「停！」 shows at corners, nothing is drawn in the parent corner, no Dock / menu bar / Mission Control or other OS surface appears, and the pen side button opens no context menu. Each shape completes by itself (no 完成 / 擦晒). | Pending Mac mini UAT |
| 畫形狀 ★★ / ★★★ and 擦晒 (v0.26.0) | On 跟箭嘴 and 自己畫, draw with the Wacom pen and with a finger. On 自己畫, tap 擦晒 quickly several times, then press and hold it, and drag from it off the screen edge and into the bottom-right parent corner. Expected: 擦晒 clears only the shape being drawn (finished shapes stay), quick repeat taps do nothing for 3 s, the 4th press shows the nudge and the 6th hides the button until that shape is done, nothing is drawn in the parent corner, and no OS surface or context menu appears. | Pending Mac mini UAT |
| 家長 YouTube 搵片 (v0.27.1) | In parent controls press 「喺 YouTube 搵片」. Watch the top-bar countdown; search, open a video, press back / forward / 首頁 / reload, A− / A+, click YouTube's Sign in and a link that opens a new window, then add a video (confirm card over the finder, Return adds) and press 「完成，返去清單」 while a video plays. Expected: the window stays borderless and full screen with no Dock or menu bar; the finder stays open after adding with a toast; Sign in, other sites and new-window links are refused with a note; audio stops on the confirm card and on close; the list scrolls to and flashes the new card; Return / auto-lock closes the finder; nothing about it is reachable from child screens. | Pending Mac mini UAT |
| 一架一架數 tap & count (v0.28.0) | Turn on 點一點 / 數完畫 / 揀啱數 after a parent 試玩. Tap every vehicle with a finger and with the Wacom pen (fast taps, a double tap, a tap between bays, a tap on a counted vehicle), then trace the numeral; on 揀啱數 pick too many, press OK, wait out the Think Pause, use 擦晒 six times, and press a grey OK. Also tap and drag into the bottom-right parent corner on every stage. Expected: each tap is counted once (「一、二、三」), a double tap or re-tap never counts twice, nothing is drawn or tappable in the parent corner, a wrong OK halves the fuel with the 10 s Think Pause card in the tray, the 2nd miss rings the demo count, no Dock / menu bar / Mission Control or other OS surface appears, and with no Cantonese voice installed the game stays silent but keeps working. | Pending Mac mini UAT |
| Tap & Count English versions (v0.29.0) | Turn on the three English cards (Tap each / Count & draw / Just right) after a parent 試玩 of each; their Cantonese cards stay off. Play each once, including a wrong OK on Just right. Then repeat with no English system voice available. Expected: the same game as 一架一架數 (same vehicles, taps, OK, Clear, Think Pause, trace); every word on screen and spoken is English (en-GB voice), no Chinese anywhere on the child screens of these cards; with no English voice the round is silent but keeps working; no Dock / menu bar / Mission Control or other OS surface appears. | Pending Mac mini UAT |
| 描數字提示 tracing guidance (v0.30.0) | In 數字設定 leave 描數字提示 on 標準. Play 數完畫 and 揀啱數 (Cantonese and English cards) for 8, 5 and 4: watch the demo car once, then on the next round touch the board during the demo; hold the pen still for 3 s mid-stroke; leave the board alone for 25 s; trace an 8 cleanly twice. Repeat with 多啲 and 少啲, with Reduce Motion on, and with no Cantonese / English voice installed. Expected: the demo plays with its rhyme and the first touch stops it at once (the car wiggles, nothing is painted, no lock); headlights show only the next 3 dots; the crossing / turn sign and line come just before it; a 2 s stall shows the ring and a short ghost run; 20 s idle replays the demo (at most twice); two-stroke numerals fade stroke ② until the car hops to it; after 2 clean traces 標準 stops playing the demo for that numeral; tracing is never marked wrong and fuel never changes; with Reduce Motion nothing glides (the car jumps beat to beat); with no voice it stays silent and keeps working; no Dock / menu bar / Mission Control or other OS surface appears. | Pending Mac mini UAT |

## Remaining OS and physical escape paths

This is an app-level kiosk, not a managed-device security boundary. Presentation
options and local event filtering are requests to macOS. Their actual effect
must be measured with the table above.

- Mission Control, Spaces, Stage Manager, hot corners, system shortcuts,
  Spotlight, Siri, accessibility shortcuts, notification/system overlays,
  screen locking, and external devices may provide OS-owned surfaces.
- Wacom ExpressKeys, Touch Ring and pen side buttons can be mapped to any key or
  app in the Wacom driver. The app cannot block them; disable or neutralise them in
  the Wacom Tablet preferences on the Mac mini (design §8.5, v0.23.0 連一連).
- A pen or finger drag that ends at a screen edge can still reach OS edge features
  (hot corners, Dock reveal) wherever macOS ignores the presentation options.
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
- Since v0.21.5 (ADR 0011) authenticated parent mode keeps the kiosk presentation (no Dock,
  menu bar or app switching). Leaving needs 「離開程式」.
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
