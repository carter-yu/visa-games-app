# Parent settings scroll investigation — 0.37.0 / 80

## Builds 79–80: UX/copy only — the build-78 experiment is unchanged (2026-11-05)

Builds 79 and 80 restyle the letter picker panel and the child ticket-unavailable board.
They change no scroll, clock, hook, loading or save behaviour, so the build-78 hypotheses and
the decision table below apply unchanged. When UAT runs, verify
`VIEW … appear … version=0.37.0 build=80` (or the build actually installed).

Layout facts for reading an 80 log:

- **Loading keeps the card's height (build 80).** While the letter cards load off the main
  thread, the card draws its whole loaded structure: the picker's preset, disclosure, legend,
  tile and note blocks (fixed heights), then the footnote, summary, review, more-settings and
  footer sections. These come from the saved settings the draft will start from, dimmed and
  inactive. Since fix round 1 the warnings that only the loaded capabilities can show also
  have reserved space. The grid's 已揀・暫停 and 未開放 notes share two always-present slots.
  The summary's warnings (已揀・暫停, find-only, nothing to write, and the 搵完寫 recovery
  button) share one fixed status row. So `DRAFT ready` should **not** change
  `documentHeight` for default or unavailable selections (e.g. a legacy f–j week with i/j
  not ready). Expected height changes come only from parent actions: 按學校次序, 更多字母設定,
  a preset preview, turning review on or off, and edits that cross a 13-letter chip row.
  (Build 79 grew once at `DRAFT ready` in every case.)
- Opening 按學校次序 or 更多字母設定 (full-width buttons, not disclosure groups) changes
  height in the same turn as `PICKER schoolDisclosure …` or `VIEW … disclosure more=…`.

## Build 78: eager-grid experiment — HYPOTHESIS, not a proven fix (2026-11-05)

Build 77 was never installed; the Mac mini still has 76. Build 78 is the first build since
75 that changes parent layout. **The snap is not claimed fixed.** It tests two hypotheses
from the build-76 evidence (`parent-scroll-76-2352.log`, Games lines 388–391, 461–464,
518–521):

- Within one `mono` timestamp, each Games reversal is `GEOMETRY reason=document` (height
  +57/+52/+50 pt) → `OFFSET reason=document` (up ~240–300 pt) → `JUMP` (down 2,445–2,583 pt).
  The destinations are fractional (3600.724…, 3613.485…, 3909.457…) and their fractions carry
  into the next whole-number wheel steps, so the destination was computed, not input-driven.
- The document height changes during pure scrolling with no draft, picker, focus or scroll
  command (7651 → 7614 → 7605 → 7695 → … → 7907 → 7872 → 7924 → 7880 → 7930).

**HYPOTHESIS 1 (tested by this build):** the two adaptive `LazyVGrid`s above the letter card
(theme chips in `quickActions`, game cards in `gamesSection`) re-estimate their height as
rows leave or enter the render window. SwiftUI then corrects the offset against an estimated
anchor far above the viewport. Build 78 replaces both with eager chunked HStack rows
(`ParentEagerRows`, same pattern as the letter tiles in `ParentPracticeItemPicker`). The
column maths (`VisaCore/ParentGridColumns`) reproduce the adaptive grids at the kiosk width:
852 pt cards → games 3 × 272 pt, themes 4 × 204 pt (offline check). The width is a constant
(full-screen kiosk ≥ 1280 pt, page capped at 940 pt), so nothing in the document measures
itself. The Videos tab's allowlist `LazyVGrid` is unchanged.

**HYPOTHESIS 2 (amplifier, also changed):** every 0.5 s tick republished `now` and an
unchanged `session` (76 log: `TICK … PUBLISH session from=parent to=parent
snapshotChanged=false`, then `VIEW … body count` +1 for the page and the letter card).
`now` is no longer `@Published`; `tick()` redraws on every tick only in child modes, during a
parent playtest and while the parent finder is open (all read `now`). On the plain settings
page it redraws only during the 2.5 s 加咗 card flash and when the 🧪 testing badge's minute
or on/off state changes. `update()` no longer reassigns an unchanged session.

**How UAT decides (build 78 log, Games tab, scroll down past the letter card several times):**

| Observation | Meaning |
| --- | --- |
| No `JUMP` while scrolling down on 遊戲, and `GEOMETRY … documentHeight` constant while only scrolling | Consistent with Hypothesis 1. Not proof: repeat across sessions/inputs (wheel, trackpad, Wacom). |
| `documentHeight` still changes with no `DRAFT`/`PICKER`/disclosure line | Hypothesis 1 is wrong or incomplete: something else in the document still resizes. Turn the stack hooks on (below) and capture. |
| `JUMP` still appears with stable height | Height estimation is not the trigger. Use the stack hooks. |
| `TICK begin publish=none` on the settings page, and `VIEW … body count` no longer rising every 0.5 s | Hypothesis 2 change is active. |

Verify the build first: `VIEW … appear … version=0.37.0 build=78`.

### Build 78: native stack hooks are now OFF by default

`ParentScrollHooks` installs no Objective-C method wrapper unless the app's defaults domain
opts in. The plain observe-only log (notifications, local event monitor, `GEOMETRY`/`OFFSET`/
`JUMP`/`TICK`/`VIEW`/`DRAFT`, height stacks via `Thread.callStackReturnAddresses`) stays on.

```sh
defaults write family.visagames.mac ParentScrollStackHooks -bool true    # then relaunch
defaults delete family.visagames.mac ParentScrollStackHooks              # then relaunch
```

The flag is read once per launch (`HOOK disabled …` is logged once when off). Only a boolean
`true` enables it. Object arguments of the wrapped `reflectScrolledClipView:` and
`mouseDown:` are now optional, so a nil from Objective-C cannot trap. With hooks off, the
`SCROLLER` begin/end records and `path=[…]` are absent. A left press that began in the
vertical scroller counts as scroller interaction while the button stays down
(`ParentScrollerPress`, polled with `NSEvent.pressedMouseButtons` at each sample), because
AppKit's knob-tracking loop hides drag/up events from the local monitor.

### Build 78: letter Save evidence

Each 儲存 tap now writes one `DRAFT save … load=<fresh|legacy|repairV1|saved|corruptV2>
hasChanges=…` line and one `DRAFT save result=<notReady|blocked|saved|invalid|storeError|error>`
line. A stored Save also writes `DRAFT save stored key=VisaGames.tapLetterSettings.v2
v2KeyPresent=… readback=… revision=…`. Opening the card logs `DRAFT open … load=…` and,
when the off-main resources arrive, `DRAFT ready … elapsedMs=… canSave=… reason=…`. No
`DRAFT save` line after a tap means the button never fired (disabled or not hit).

## DIAG2: caller capture, 2026-11-05 (build 77, never installed)

Carter selected caller-stack diagnostics at 06:45 HKT. Build **0.37.0 / 77**
adds observation only; layout, buttons, focus, timers and scroll policy stay as
before. The existing build-77 metadata edits and build-76 evidence excerpts are
preserved below. No implementation root cause or successful scroll fix is claimed.

Carter also confirmed that build-76 Videos markers at source lines **173, 175,
177 and 179** were his own scrollbar drags. They are genuine user movement.
The three Games reversals remain unexplained by upward input; DIAG2 is intended
to identify the native caller rather than select another speculative fix.

### Capture boundaries and limits

`ParentScrollHooks.swift` installs typed Objective-C IMP wrappers for the
existing parent clip/scroll view, including their concrete runtime overrides:

- `NSClipView.setBoundsOrigin:`, `setBounds:`, `constrainBoundsRect:` and
  `scrollToPoint:`. The last selector is Swift's `scroll(to:)`, not a second API.
- `NSScrollView.reflectScrolledClipView:`.
- The current vertical `NSScroller.mouseDown:` to bracket its entire native
  tracking loop, including drag/up events omitted by local event monitors.

Each wrapper invokes the saved native implementation exactly once with the
original receiver, selector and arguments, and returns its original result.
There is no new scroll command, replacement view, gesture handler or focus
request. Wrappers remain installed for process lifetime, but callbacks and raw
stack capture run only for the attached parent's exact objects on the main
thread. Child/other views and calls off the main thread pass straight through.
Detach clears callbacks; a replaced vertical scroller's concrete method is
checked before dispatching a monitored mouse-down. Installation is capped at
96 methods, active method paths at 16 entries, with recursion guards around
observer callbacks and sampling. Unchanged hook boundaries compare geometry
without formatting records or collecting stacks.

Synchronous clip-bounds/document notifications remain enabled. This also
captures private SwiftUI correction paths that post notifications while avoiding
the wrapped public entry points. No private SwiftUI method name is assumed or
modified. Document-height changes retain raw `Thread.callStackReturnAddresses`
when observed, not formatted symbols. A stack captured in a synchronous
`document:NSViewFrameDidChangeNotification` callback can retain the setter's
call chain. A `hook:...`, `bounds` or `update` observation may first notice a
height changed earlier; its stack proves the observation site, not necessarily
the height setter. Read `reason` and `path` before attributing a caller.

The history holds at most **8 height events from the preceding 2 seconds**,
with at most **96 raw frames each** and **20 height-stack captures per rolling
second**. Above that budget, the latest height/time/source is retained with
`rateLimited=true` and no frames; successive omissions coalesce. Do not present
an older captured stack as the immediate height-change caller in that case.
Unexplained jumps produce at most **one stack block per second**; additional
`JUMP` lines say `stack=rateLimited`. One stack block may be pending on the
writer queue; another receives `STACK ... OMITTED reason=writerBusy` instead of
retaining another large stack payload. Ordinary existing event logs keep their
previous throttling. These are diagnostic limits, not scrolling limits.

The classifier now accepts upward wheel/trackpad input within 350 ms, a
mouse-down/drag inside the vertical scroller within 350 ms, or an active native
scroller tracking call. Tracking remains active until that call returns, even
when the pointer leaves the scroller or the drag lasts longer than 350 ms.
Its return starts a final 350 ms grace period. A newer downward wheel cancels
older scroller grace. Ordinary content clicks do not excuse a jump. `INPUT`
mouse-down/drag records include `scroller=true/false`, and `SCROLLER` records
mark native tracking begin/end. This changes diagnostic classification only.

### Reading STACK blocks

The destination remains
`~/Library/Application Support/VisaGames/logs/parent-scroll.log` and its `.1`
rotation, plus unified log subsystem `family.visagames.mac`, category
`parentScroll`. Both destinations receive the same stack records. On a `JUMP`,
find `stackID=<UUID>` and then every `STACK id=<UUID>` line. A block contains:

| Field/record | Meaning |
| --- | --- |
| `BEGIN parent=... tab=... scroll=... heightSamples=N` | Identity of the parent and native scroll view; number of recent height samples. |
| `sample=jump capturedMono=... ageMs=0.0 frames=N from=... to=... delta=... reason=... path=[...]` | Stack collected synchronously where the large decrease was observed, and the active native hook path. |
| `sample=height[i] capturedMono=... ageMs=... frames=N from=... to=... rateLimited=... source=...` | Height changes oldest to newest; the highest index is the latest retained height event. Its source includes parent/tab/scroll, observation reason and active hook path. |
| `sample=... frame=i address=0x... <symbol>` | Zero-based frame, raw address and `backtrace_symbols` image/symbol/offset text, or `unresolved`. Frame 0 is nearest the capture; increasing indexes move toward older callers. |
| `END` | End of this block. Every line repeats its UUID. |

The block's ordinary timestamp/`mono` refers to the jump, including for older
height samples. Use **`capturedMono` and `ageMs`** to order the actual captured
stacks. Symbol lookup runs on the serial utility logging queue only when a
jump requests a block; it resolves saved addresses, never that queue's own
current stack. The first frames will include diagnostics/notification code.
Read beyond them for AppKit/SwiftUI/application callers, then compare the latest
height stack with the jump stack and the `JUMP` input context. Symbols may be
stripped, unresolved or mangled, and 96 frames may truncate deeper callers.
Neither a missing symbol nor temporal adjacency proves a particular grid or
timer caused the change. Keep the matching build if further symbolication is
needed. [Apple backtrace manual](https://github.com/apple-oss-distributions/Libc/blob/main/gen/backtrace.3)

Build and reproduce on the Mac mini with `bash scripts/test.sh` and
`bash scripts/bundle.sh`, verifying `VIEW ... appear` logs **version=0.37.0 build=77**.
Capture Games with wheel/trackpad and Wacom, then intentionally drag the Videos
scrollbar to verify `SCROLLER` begin/end and the absence of false `JUMP` markers.
Keep both files immediately afterward: rotation can split a block between them.

```sh
tail -F "$HOME/Library/Application Support/VisaGames/logs/parent-scroll.log"
rg -n 'JUMP|STACK|SCROLLER|HOOK' "$HOME/Library/Application Support/VisaGames/logs/parent-scroll.log.1" "$HOME/Library/Application Support/VisaGames/logs/parent-scroll.log"
```

If `.1` does not exist, omit it. A `JUMP` with `stack=rateLimited`, a `STACK`
with `OMITTED`, a rate-limited height entry or a missing notification is an
explicit evidence gap. Do not infer a caller from it. `HOOK installed` lists
installed methods; a path can still be empty for notification-only observations.

DIAG2 changes are isolated to `ParentScrollHooks.swift`, `ParentScrollProbe.swift`,
`ParentScrollLog.swift`, the VisaCore classifier and new `ParentScrollStackHistory.swift`,
their tests/runner, and this document/`PROGRESS.md`. The existing build-77 plist
and two version-test edits remain. The full `scripts/test.sh` suite passes on
the portable Linux Swift toolchain, including **22 parent-scroll checks**:
the original 10, six classifier checks (including the confirmed Videos and
Games sequences), and six bounded stack-history checks. This does not compile
the AppKit UI. Swift 5 language-mode syntax checks also pass for the app
diagnostic files. `scripts/bundle.sh` on Linux fails with `no such module
'AppKit'`; native hook execution, macOS compilation and overhead remain to be
verified on the Mac mini.

## Build 76 source audit and original collection notes

Build 76 adds diagnostics only. It does not claim to fix the snap to the top,
change scroll positioning, disable controls or focus, or replace SwiftUI's
ScrollView. The available evidence does not identify a root cause strongly enough
to justify a third speculative layout change.

The source audit below refers to **baseline commit `798acc8` line numbers**. New
instrumentation moves those lines; the named functions remain the lookup points.
Paths beginning with `Sources/VisaGames/` are abbreviated in the tables.

## Evidence and history

Carter reported that 0.37.0 / 75 jumps to the top when scrolling farther down
Games after reaching the English letter settings card. The supplied photo shows
the letter rows, saved selection `a b c d e`, and the pointer in the blank right
gutter. A still photo cannot establish which input events occurred during the
jump or whether the native scroll view was replaced.

The supplied unified log contains 904 lines for pid 21954, spanning
2026-11-04 22:32:24.547715–22:33:55.056965 HKT. There are 126 bare
`(AppKit) sendAction:` activities: 64 between 22:33:21.687774 and
22:33:25.486662, then 62 between 22:33:36.128873 and 22:33:39.110123.
The peak is 32 in one second. These entries contain no action selector, sender,
control identity, location, focus, draft or scroll geometry. The supplied
material has no parent-scroll instrumentation with which to correlate them.

`sendAction:` does not establish that letter buttons were clicked. Native
scroller tracking can send actions continuously: Apple documents target-action
dispatch for `NSScroller.trackKnob(with:)`. Buttons and other controls can also
send actions. The application's explicit `NSApp.sendAction` call is restricted
to parent Command editing shortcuts (`AppDelegate.swift:3383`); no app wheel or
tablet handler calls it. [Apple NSScroller documentation](https://developer.apple.com/documentation/appkit/nsscroller)

The relevant history was checked with `git log -p 87ec364^..798acc8`,
`git show b467d6d`, and searches for `ScrollViewReader`, `LazyVGrid`, focus and
scroll changes:

| Change | What it actually changed | What it does not establish |
| --- | --- | --- |
| `b467d6d`, v0.21.3 / 47 | Moved header, notices, quick actions and tabs inside one outer ScrollView; pinned Return/Quit above it. | This was a reachability/viewport fix, not measured evidence for the current snap. The one-scroll structure remains. |
| v0.24–v0.37 additions | Added line, shape, numeral and letter settings below the Games grid; added explicit finder/card navigation and the weekly report. | A larger document is a possible trigger, not proof of an identity or offset bug. |
| `87ec364`, 0.37.0 / 74 | Made letter tiles eager rows, cached picker data, and pinned letter actions; the bar still depended on an open draft. | It did not measure the native document, clip bounds or focus during a jump. |
| `a06aad6`, 0.37.0 / 75 | Made the bar persistent while Games is selected, moved draft lifetime to the parent page, removed letter-card appear/disappear hooks and its outer fixedSize. | The assumed draft/bar feedback mechanism was not demonstrated, and Carter still reproduced the bug. |
| `798acc8`, 0.37.0 / 75 | Reused larger parent action buttons and set the bar height to 116 points. | Styling did not provide a root-cause test. |

## Hierarchy and competing explanations

Confidence below means confidence that the mechanism merits investigation from
the available evidence, not a measured probability. None is confirmed.

| Rank | Hypothesis and confidence | Baseline source evidence and limits |
| --- | --- | --- |
| 1 | Layout/offset correction during repeated model invalidation — medium | `ParentSettingsView.swift:37–66` contains the shared ScrollView. Games still has an adaptive lazy game grid at `:177–193`, above four settings cards at `:195–230`. `AppDelegate.swift:444–455` ticks every 0.5 seconds and publishes `now`; `update` republishes `session` at `:404`. Body reevaluation alone does not prove native view recreation or a height change. Measure clip offset and document height together. |
| 2 | Native focus restoration scrolls an earlier control into view — medium-low | Settings and letter tiles use ordinary Buttons (`ParentSettingsView.swift:149`; `ParentPracticeItemPicker.swift:103`). There is no explicit FocusState, focused/focusable modifier or makeFirstResponder call in this hierarchy. Platform focus behavior remains possible; capture focus requests and actual responder identity/geometry. |
| 3 | Pen/mouse events activate controls and change draft/layout — low-medium | Tile action `ParentPracticeItemPicker.swift:103–105` reaches the binding at `ParentTapLetterSettingsView.swift:219–221` and draft publication at `:75–80`. Summary/review content can change height at `:256–305`; preset preview/disclosure content is conditional at `ParentPracticeItemPicker.swift:28–54`. There is no wheel handler, onTapGesture or app-generated tablet-to-click conversion in these controls. The bare sendAction log cannot distinguish a scroller from a button. |
| 4 | Parent subtree or NSScrollView recreation — low | Parent state has stable structural placement (`ParentSettingsView.swift:16–18`); the ScrollView has no changing id. `ShellView` selects ParentSettings by `session.mode == .parent` (`AppDelegate.swift:3571–3573`). One NSHostingView is assigned at launch (`:3371`). Framework-level recreation is still measurable, so compare native identities and the parent UUID. |
| 5 | An explicit scrollTo route fires — low | The three routes are finder flash (`ParentSettingsView.swift:61–64`, also switches to Videos), the writing-game link (`:229`, action at `ParentTapLetterSettingsView.swift:271`), and opening Advanced (`ParentSettingsView.swift:653–658`). None runs from ordinary scrolling. The writing link requires no selected writable letters, unlike the saved `abcde` in the photo. |
| 6 | Relock/re-authentication or window refit — very low | Unlock is rejected while already in parent mode (`AppDelegate.swift:482–483`). Expiry returns to the child (`:460`), which would remove settings and require authentication to return. The supplied log records successful authentication at 22:33:06.738 HKT, about 15 seconds before the first action burst, far short of the 600-second deadline. Window fitting runs at launch or a screen-change notification (`:3430–3446`), not on each tick. |

Apple documents that hiding a current first-responder view can transfer focus
to the next valid key view. AppKit also exposes scrolling a region into the
nearest ancestor clip view. This makes focus a plausible mechanism; it does not
show that either operation happened during this reproduction.
[Apple view hierarchy guide](https://developer-mdn.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaViewsGuide/WorkingWithAViewHierarchy/WorkingWithAViewHierarchy.html),
[Apple scrollToVisible documentation](https://developer.apple.com/documentation/appkit/nsview/scrolltovisible(_:))

Additional exclusions and boundaries from the audit:

- The window stays borderless and uses constant kiosk presentation in parent
  and child modes. There is no periodic kiosk window replacement or focus
  watchdog in the launch/tick path. Sleep explicitly returns to the child;
  wake calls `tick` (`AppDelegate.swift:3428–3429`).
- ShellView gives parent settings precedence over child overlays. Its parent
  corner and pen overlay are child-only (`AppDelegate.swift:3552–3561`). The
  child CanvasStage GeometryReader/PreferenceKey paths do not wrap parent
  settings. The existing pen monitor observes events and returns them unchanged.
- ParentSettingsView, the letter card and picker have no TimelineView,
  onReceive, GeometryReader, PreferenceKey or AnyView loop. The only explicit
  FocusState in the parent-related views belongs to the separate YouTube finder
  search field. The normal Games page does not open that overlay on scrolling.
- The 0.5-second timer reaches idle/playtest checks, storage retry, session
  normalization and performance ticking. It is a real source of model
  publication, but periodic publication is not itself a reset operation.
  The new tick/publication records make temporal correlation possible.
- All explicit settings IDs are stable game kinds, video IDs or the constant
  Advanced anchor (`ParentSettingsView.swift:191`, `:373`, `:648`). Letter rows
  use row indexes and stable item IDs (`ParentPracticeItemPicker.swift:60–64`).
- The page owns draft open/clear (`ParentSettingsView.swift:79–83`, `:110–114`).
  Merely scrolling the letter card away no longer clears it. The save bar has a
  fixed 116-point height for the entire Games selection
  (`ParentTapLetterSettingsView.swift:170`). This weakens the previous
  draft/bar-removal hypothesis without proving the replacement hypothesis.

Code inspection cannot establish that the bug is Games-only. Every tab uses
the same window, ScrollView, model observation and native focus machinery.
Games adds a particularly long document, a remaining lazy game grid, the letter
draft and pinned bar. Videos also has an adaptive lazy grid
(`ParentSettingsView.swift:359`) and dynamic preview/notices. Review's children
use `.equatable()` (`:125–139`) but share the outer scroll. The probe covers all
three tabs so the next reproduction can distinguish shared and Games-specific
behavior.

## Permanent diagnostics

The log is written both to `os.Logger` with subsystem
`family.visagames.mac`, category `parentScroll`, and to:

```text
~/Library/Application Support/VisaGames/logs/parent-scroll.log
~/Library/Application Support/VisaGames/logs/parent-scroll.log.1
```

The current file rotates at 1 MiB and keeps one previous file. Lines are bounded;
file I/O and timestamp formatting use a serial utility queue, with no per-line
fsync. Diagnostics are best effort and a failed file write does not change
settings. Keep both files soon after reproduction so later activity does not
rotate away the evidence. ISO timestamps are UTC; `mono` is process system
uptime, useful for ordering and timing within one run.

The probe is a non-interactive background inside the existing scroll document.
It locates the enclosing NSScrollView, observes NSClipView bounds and document
frame/bounds notifications, and never sets a scroll offset, frame, first
responder, control value or view identity. Its local NSEvent monitor returns
the original event unchanged. It records event type, numeric mouse subtype and
location, plus wheel delta/phase/momentum needed to interpret direction. It records no typed text,
pressure, tablet device identifiers or document/control contents.

The probe enables ordinary AppKit bounds/frame notifications. Teardown removes
its observers and local event monitor but leaves those notification flags enabled
so it cannot disable notifications needed by another observer.

| Record | What to compare around a jump |
| --- | --- |
| `VIEW` | ParentSettingsView and letter-card lifetime UUIDs, body counts, appear/disappear. Repeated body evaluations with the same UUID are not proof of destruction. |
| `TAB`, `DRAFT` | Tab transitions, draft open/clear/edit operations. A draft clear during unchanged Games selection needs an explanation. |
| `ATTACH`, `DETACH` | Native scroll, clip, document, host and window identities. Compare IDs; reattachment alone need not mean a new scroll view. |
| `GEOMETRY` | Document frame/bounds, viewport size and flipped coordinates. A height collapse can clamp the valid scroll range. |
| `OFFSET` | Top-relative offset and raw clip origin. Normal movement is throttled to about ten records per second; changes over 200 points are always recorded. |
| `FOCUS`, `FOCUS_REQUEST`, `FOCUS_RESULT` | Observed responder class/identity/geometry, window focus requests and their results. FOCUS is emitted when identity changes; scrolling a responder's geometry alone does not flood the log. The override calls the existing superclass behavior exactly once. |
| `INPUT` | Wheel, tablet, mouse down/up/drag and key-event metadata, throttled by event type to about ten records per second. No key characters are recorded. |
| `TICK`, `PUBLISH` | Timer-driven state activity and relevant model publication near the jump. Correlation alone does not establish causation. |
| `SCROLL_TO` | Explicit application navigation, distinguishing requested movement from unexplained native movement. |
| `WINDOW` | Key/resign-key, resize and move notifications. |
| `JUMP` | An unexplained single-change decrease over 200 points, with geometry, responder and the preceding ten bounded context entries. |

The jump detector observes every received bounds change even when ordinary
offset logging is throttled. A decrease **strictly greater than 200 points** is
flagged unless the most recent nonzero wheel delta is positive, requests upward
movement in AppKit's delivered coordinates, and occurred within **350 ms** over
the observed scroll viewport. A later downward wheel supersedes an earlier
upward wheel; a zero-delta phase-ending event does not. Natural scrolling is not
inverted a second time. There is no offset suppression or correction.

`JUMP` is an investigation marker, not a verdict. Intentional scroller dragging,
keyboard navigation, focus navigation or explicit scrollTo can also produce a
large decrease without an upward wheel; their context explains those cases.
A sequence of smaller decreases may never cross the per-change threshold.
Focus can also move internally within SwiftUI while the native firstResponder
stays the same; stable native focus identity does not exclude that mechanism.
The bounded context is the last ten records/events, not a guaranteed time span.

## Build 76 collection procedure (historical)

Both `bash scripts/test.sh` and `bash scripts/bundle.sh` were attempted on the
Linux editing host and stopped at `swift: command not found` (exit 127). Native
compilation, app launch and device reproduction remain pending. Run the checks and bundle
on the Mac mini, then launch the 0.37.0 / 76 build:

```sh
bash scripts/test.sh
bash scripts/bundle.sh
```

The source checks passed: `git diff --check`, plist/footer/build-assertion
consistency, the existing draft-lifecycle source match, and registration of all
ten new detector/rotation checks. These static checks do not establish Swift
compilation, test execution, native probe attachment or runtime overhead.

Observe the file live in a separate Terminal window; `-F` follows rotation:

```sh
tail -F "$HOME/Library/Application Support/VisaGames/logs/parent-scroll.log"
```

Alternatively, stream the unified logger, including its info level:

```sh
log stream --style compact --level info --predicate 'subsystem == "family.visagames.mac" AND category == "parentScroll"'
```

1. Note the build, macOS version, display resolution/scaling and approximate
   local time. Enter Parent settings, select Games, scroll to the letter card
   and farther down without intentionally changing a setting. Note whether the
   pointer was over a tile, blank gutter or scrollbar.
2. Repeat separately with mouse wheel, trackpad and Wacom pen. Record whether
   pen scrolling uses a configured wheel gesture, scrollbar dragging or another
   driver gesture. Compare staying idle at the same offset with actively
   scrolling. Do not infer the input type from sendAction bursts.
3. Repeat scrolling in Videos and Review, within their available document
   lengths. A tab switch intentionally changes content; record it separately
   from a snap within an unchanged tab.
4. Keep `parent-scroll.log` and `.1` immediately after the reproduction, with
   the observed time and input method. Search for JUMP and read the neighboring
   records, including any preceding detach/attach, height change, focus request,
   draft edit, explicit scrollTo or timer publication.

```sh
rg -n -C 15 'JUMP' "$HOME/Library/Application Support/VisaGames/logs/parent-scroll.log" "$HOME/Library/Application Support/VisaGames/logs/parent-scroll.log.1"
```

If `.1` has not been created yet, search only the current file. If no JUMP is
present, retain the records around the reported time: disappearance, recreation
or multiple smaller offset changes may still explain the observed return to
the top. A log that only says the probe is awaiting `enclosingScrollView` does
not contain usable scroll measurements and should be reported as such.

These diagnostics make no changes to authentication, child navigation or kiosk
policy. Existing OS escape-path limits remain documented in the kiosk checklist.

## Files in build 76

- `Sources/VisaCore/ParentScrollDiagnostics.swift`: Foundation-only jump detector
  and bounded rotating file writer.
- `Sources/VisaGames/ParentScrollLog.swift` and `ParentScrollProbe.swift`: unified
  and file logging, view traces, native scroll/focus/geometry observations, and
  local input monitoring.
- `Sources/VisaGames/AppDelegate.swift`, `ParentSettingsView.swift`,
  `ParentTapLetterSettingsView.swift`, and `ParentPracticeItemPicker.swift`:
  shell, timer, focus, tab, draft, lifecycle and control-action integration.
- `Tests/VisaCoreTests/ParentScrollDiagnosticsTests.swift` and
  `SessionTests.swift`: detector/rotation checks and executable-harness
  registration.
- `Tests/VisaCoreTests/LetterPickerTests.swift`, `PerformanceRecordTests.swift`
  and `WeeklyReportPDFTests.swift`: existing lifecycle/version source assertions
  updated for this build and instrumentation.
- `Resources/Info.plist`: marketing version 0.37.0, build 76.
- `PROGRESS.md`, `logs/README.md` and this report: factual verification status,
  log discovery and reproduction guidance.


## Build 76 runtime evidence: 2026-11-04 23:50–23:52 HKT

This section adds measured evidence to the earlier source audit. It does not
claim a FIX1 success. The precise operation that moved the clip view remains
unrecorded in build 76; DIAG2 above adds caller capture for the next run.

The evidence is `parent-scroll-76-2352.log`, supplied at
`/workspace/visa-games-sessions/scroll/parent-scroll-76-2352.log`: 1,154 lines,
pid 24568, version 0.37.0 / build 76. All line references in this section refer
to that file, rather than Swift source. UTC timestamps in the raw records are
eight hours behind the HKT times in this heading.

Source SHA-256: `e8bf40df7ccffa5cd400b7b337b67b1c9a584020dc9594f225f8abaeabe0a656`.

Seven `JUMP` records comprise two different sequences:

| Source line | Tab | Recorded offset change, points | Evidence classification and confidence |
| --- | --- | --- | --- |
| 173 | Videos | 2548 → 2316 (−232) | Genuine user scrollbar movement, confirmed by Carter on 2026-11-05; preceding mouse down is in the scrollbar strip. |
| 175 | Videos | 1881 → 1582.7066 (−298.2934) | Same user scrollbar drag, confirmed by Carter. |
| 177 | Videos | 1583 → 1336 (−247) | Same user scrollbar drag, confirmed by Carter. |
| 179 | Videos | 898 → 644 (−254) | Same confirmed user drag, subsequently reaching zero at line 182. |
| 390 | Games | 6046 → 3600.7241 (−2445.2759) | High confidence anomalous reversal during recorded downward wheel input. An app/framework scroll adjustment associated with layout is strongly supported; its exact caller is unproven. |
| 463 | Games | 6181.7241 → 3613.4854 (−2568.2387) | Same Games failure pattern, with stable identities and a growing document. |
| 520 | Games | 6492.4854 → 3909.4577 (−2583.0277) | Same Games failure pattern. The final position remains stable through 125 further ticks. |

The table rounds values for readability; the raw lines below preserve every
value and the complete ten-entry contexts.

The Videos mouse down at line 166 has type 1, subtype 0 and x=1916.9766, beyond
the 1905-point clip width in the 1920-wide document/window arrangement. This is
consistent with the right scrollbar. The offset then decreases continuously
until zero, without another logged wheel input. Missing drag/up records do not
exclude dragging: Apple's local-event-monitor contract explicitly excludes
events consumed by nested control-tracking loops. The pause in normal ticks
between lines 160 and 183 also fits tracking, although the actual hit-tested
control was not recorded. Consequently these four markers cannot prove the
same defect occurs in Videos.
[Apple local event monitor documentation](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:))

The Games reversals have different evidence. Their contexts contain recent
negative wheel deltas at x=1522.8867, inside the viewport and away from the right
scrollbar. Throughout the surrounding record, negative deltas normally increase
the top-relative offset. Each reversal follows a small document-height increase
in the same logged millisecond: 7850→7907, 7872→7924 and 7880→7930. The viewport
remains 1905×884. This does not match clamping after a document-height collapse.
None of the three Games events reaches offset zero; the capture proves large
upward reversals, not a literal return to zero in Games.

One ATTACH at line 5 retains the same scroll, clip, document, hosting view and
window identities until DETACH at line 1151. Parent and letter-card UUIDs also
remain stable. The file contains one initial FOCUS at line 6, no FOCUS_REQUEST or
FOCUS_RESULT, no SCROLL_TO, and no draft edit: the draft opens at line 204 and
clears on teardown at 1153. No logged tab transition, re-authentication or
parent-mode exit accompanies the Games reversals. Native focus changes and
explicit application navigation are therefore unsupported as causes in this
capture; internal SwiftUI behavior within a stable responder is not observable
from those records alone.

The preceding tick ends are 406 ms, 336 ms and 265 ms before the Games JUMPs.
After line 520 and its matching OFFSET at 521, the file contains **125 further
TICK begin/end pairs** (first at 522/524, last at 1142/1144), continuing session
publications and view body evaluations. There is no further GEOMETRY, OFFSET or
JUMP before the quit-button input at 1147–1148 and teardown. This shows that
periodic publications alone did not move the offset during that idle interval;
it does not exclude an interaction between publication and active scrolling.

The strongest remaining hypothesis is a scroll-position adjustment during
framework layout/anchoring. The surviving Games LazyVGrid is a candidate, not
an identified caller: only total document geometry was measured, not individual
section geometry or the stack requesting the bounds change. The shared theme
grid is also lazy. Changing a grid, suppressing ticks or overriding scroll
positions would require acknowledging that distinction. No precise
implementation root cause or FIX1 success is claimed by this evidence section.
The log identifies wheel events, not whether a mouse, trackpad or Wacom driver
produced them.

Initial parent lifetime, version, native identities and responder. Source lines **1–8**; the fenced text is copied verbatim, without line-number prefixes.

```text
2026-11-04T15:50:49.682Z pid=24568 mono=1842796.795 PARENT enter authenticated
2026-11-04T15:50:49.685Z pid=24568 mono=1842796.798 PUBLISH session from=lock to=parent snapshotChanged=false
2026-11-04T15:50:49.707Z pid=24568 mono=1842796.820 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=1 tab=videos mode=parent draft=false
2026-11-04T15:50:50.136Z pid=24568 mono=1842797.248 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 appear tab=videos version=0.37.0 build=76
2026-11-04T15:50:50.365Z pid=24568 mono=1842797.477 ATTACH parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) clip=ObjectIdentifier(0x00000078b8a51b00) document=DocumentView@ObjectIdentifier(0x00000078b8b2d900) window=ObjectIdentifier(0x00000078b8f64a00) host=NSHostingView<ShellView>@ObjectIdentifier(0x00000078b9124000)
2026-11-04T15:50:50.365Z pid=24568 mono=1842797.477 FOCUS parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) responder=KioskWindow@ObjectIdentifier(0x00000078b8f64a00)
2026-11-04T15:50:50.365Z pid=24568 mono=1842797.477 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) reason=attach documentHeight=8421.0 documentFrame={{0, 0}, {1920, 8421}} documentBounds={{0, 0}, {1920, 8421}} viewport={1905, 1000} flipped=true
2026-11-04T15:50:50.365Z pid=24568 mono=1842797.477 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) y=0.0 rawY=0.0 previous=0.0 reason=attach
```

Complete Videos context, including all four JUMP records and the preceding scrollbar-area mouse down. Source lines **160–185**; the fenced text is copied verbatim, without line-number prefixes.

```text
2026-11-04T15:50:57.251Z pid=24568 mono=1842804.364 TICK begin publish=now parentRemaining=592.931303024292 playtest=false browser=false
2026-11-04T15:50:57.251Z pid=24568 mono=1842804.364 PUBLISH session from=parent to=parent snapshotChanged=false
2026-11-04T15:50:57.251Z pid=24568 mono=1842804.364 TICK end mode=parent
2026-11-04T15:50:57.254Z pid=24568 mono=1842804.367 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=16 tab=videos mode=parent draft=false
2026-11-04T15:50:57.283Z pid=24568 mono=1842804.396 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=9591.0 documentFrame={{0, 0}, {1905, 9591}} documentBounds={{0, 0}, {1905, 9591}} viewport={1905, 1000} flipped=true
2026-11-04T15:50:57.287Z pid=24568 mono=1842804.400 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=9592.0 documentFrame={{0, 0}, {1905, 9592}} documentBounds={{0, 0}, {1905, 9592}} viewport={1905, 1000} flipped=true
2026-11-04T15:50:57.477Z pid=24568 mono=1842804.590 INPUT parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) type=NSEventType(rawValue: 1) subtype=0 location={1916.9765625, 662.72265625}
2026-11-04T15:50:57.488Z pid=24568 mono=1842804.601 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) y=2896.0 rawY=2896.0 previous=2902.0 reason=bounds
2026-11-04T15:50:57.598Z pid=24568 mono=1842804.710 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) y=2829.0 rawY=2829.0 previous=2838.0 reason=bounds
2026-11-04T15:50:57.692Z pid=24568 mono=1842804.805 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=9537.0 documentFrame={{0, 0}, {1905, 9537}} documentBounds={{0, 0}, {1905, 9537}} viewport={1905, 1000} flipped=true
2026-11-04T15:50:57.696Z pid=24568 mono=1842804.809 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=9535.0 documentFrame={{0, 0}, {1905, 9535}} documentBounds={{0, 0}, {1905, 9535}} viewport={1905, 1000} flipped=true
2026-11-04T15:50:57.700Z pid=24568 mono=1842804.813 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=9533.0 documentFrame={{0, 0}, {1905, 9533}} documentBounds={{0, 0}, {1905, 9533}} viewport={1905, 1000} flipped=true
2026-11-04T15:50:57.717Z pid=24568 mono=1842804.829 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=9580.0 documentFrame={{0, 0}, {1905, 9580}} documentBounds={{0, 0}, {1905, 9580}} viewport={1905, 1000} flipped=true
2026-11-04T15:50:57.721Z pid=24568 mono=1842804.834 JUMP parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) from=2548.0 to=2316.0 delta=-232.0 reason=bounds documentHeight=9580.0 documentFrame={{0, 0}, {1905, 9580}} documentBounds={{0, 0}, {1905, 9580}} viewport={1905, 1000} flipped=true responder=KioskWindow@ObjectIdentifier(0x00000078b8f64a00) context=[1842804.792 offset=2548.0 | 1842804.794 offset=2548.0 | 1842804.805 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=9537.0 documentFrame={{0, 0}, {1905, 9537}} documentBounds={{0, 0}, {1905, 9537}} viewport={1905, 1000} flipped=true | 1842804.805 offset=2548.0 | 1842804.809 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=9535.0 documentFrame={{0, 0}, {1905, 9535}} documentBounds={{0, 0}, {1905, 9535}} viewport={1905, 1000} flipped=true | 1842804.809 offset=2548.0 | 1842804.813 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=9533.0 documentFrame={{0, 0}, {1905, 9533}} documentBounds={{0, 0}, {1905, 9533}} viewport={1905, 1000} flipped=true | 1842804.812 offset=2548.0 | 1842804.829 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=9580.0 documentFrame={{0, 0}, {1905, 9580}} documentBounds={{0, 0}, {1905, 9580}} viewport={1905, 1000} flipped=true | 1842804.829 offset=2548.0]
2026-11-04T15:50:57.721Z pid=24568 mono=1842804.834 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) y=2316.0 rawY=2316.0 previous=2548.0 reason=bounds
2026-11-04T15:50:57.816Z pid=24568 mono=1842804.928 JUMP parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) from=1881.0 to=1582.7065757174983 delta=-298.29342428250175 reason=bounds documentHeight=9580.0 documentFrame={{0, 0}, {1905, 9580}} documentBounds={{0, 0}, {1905, 9580}} viewport={1905, 1000} flipped=true responder=KioskWindow@ObjectIdentifier(0x00000078b8f64a00) context=[1842804.829 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=9580.0 documentFrame={{0, 0}, {1905, 9580}} documentBounds={{0, 0}, {1905, 9580}} viewport={1905, 1000} flipped=true | 1842804.829 offset=2548.0 | 1842804.834 offset=2316.0 | 1842804.859 offset=2148.8433655968347 | 1842804.859 offset=2149.0 | 1842804.860 offset=2149.0 | 1842804.880 offset=1998.0 | 1842804.894 offset=1880.7268031878166 | 1842804.894 offset=1881.0 | 1842804.895 offset=1881.0]
2026-11-04T15:50:57.816Z pid=24568 mono=1842804.928 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) y=1582.7065757174983 rawY=1582.7065757174983 previous=1881.0 reason=bounds
2026-11-04T15:50:57.848Z pid=24568 mono=1842804.960 JUMP parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) from=1583.0 to=1336.0 delta=-247.0 reason=bounds documentHeight=9580.0 documentFrame={{0, 0}, {1905, 9580}} documentBounds={{0, 0}, {1905, 9580}} viewport={1905, 1000} flipped=true responder=KioskWindow@ObjectIdentifier(0x00000078b8f64a00) context=[1842804.859 offset=2148.8433655968347 | 1842804.859 offset=2149.0 | 1842804.860 offset=2149.0 | 1842804.880 offset=1998.0 | 1842804.894 offset=1880.7268031878166 | 1842804.894 offset=1881.0 | 1842804.895 offset=1881.0 | 1842804.928 offset=1582.7065757174983 | 1842804.928 offset=1583.0 | 1842804.931 offset=1583.0]
2026-11-04T15:50:57.848Z pid=24568 mono=1842804.960 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) y=1336.0 rawY=1336.0 previous=1583.0 reason=bounds
2026-11-04T15:50:57.961Z pid=24568 mono=1842805.074 JUMP parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) from=898.0 to=644.0 delta=-254.0 reason=bounds documentHeight=9580.0 documentFrame={{0, 0}, {1905, 9580}} documentBounds={{0, 0}, {1905, 9580}} viewport={1905, 1000} flipped=true responder=KioskWindow@ObjectIdentifier(0x00000078b8f64a00) context=[1842804.968 offset=1316.0 | 1842804.977 offset=1307.0 | 1842804.997 offset=1245.6865519749144 | 1842804.997 offset=1246.0 | 1842804.999 offset=1246.0 | 1842805.033 offset=1134.0 | 1842805.036 offset=1047.0 | 1842805.052 offset=897.5815868263473 | 1842805.052 offset=898.0 | 1842805.054 offset=898.0]
2026-11-04T15:50:57.961Z pid=24568 mono=1842805.074 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) y=644.0 rawY=644.0 previous=898.0 reason=bounds
2026-11-04T15:50:58.066Z pid=24568 mono=1842805.179 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) y=317.0 rawY=317.0 previous=355.0 reason=bounds
2026-11-04T15:50:58.228Z pid=24568 mono=1842805.341 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=videos scroll=ObjectIdentifier(0x00000078b8a5b000) y=0.0 rawY=0.0 previous=67.0 reason=bounds
2026-11-04T15:50:58.616Z pid=24568 mono=1842805.728 TICK begin publish=now parentRemaining=592.4311439990997 playtest=false browser=false
2026-11-04T15:50:58.616Z pid=24568 mono=1842805.729 PUBLISH session from=parent to=parent snapshotChanged=false
2026-11-04T15:50:58.616Z pid=24568 mono=1842805.729 TICK end mode=parent
```

The explicit tab transition and draft open precede the Games reproduction. Source lines **203–204**; the fenced text is copied verbatim, without line-number prefixes.

```text
2026-11-04T15:51:00.094Z pid=24568 mono=1842807.207 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 TAB from=videos to=games reason=button
2026-11-04T15:51:00.097Z pid=24568 mono=1842807.209 DRAFT open state=79308AB1-05D3-41EB-9FF5-808E644EAC3A
```

Last recorded document height before the first Games reversal. Source lines **351–351**; the fenced text is copied verbatim, without line-number prefixes.

```text
2026-11-04T15:51:12.288Z pid=24568 mono=1842819.400 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=7850.0 documentFrame={{0, 0}, {1905, 7850}} documentBounds={{0, 0}, {1905, 7850}} viewport={1905, 884} flipped=true
```

Complete first Games reversal context, including downward wheel input, document growth and the next tick. Source lines **381–396**; the fenced text is copied verbatim, without line-number prefixes.

```text
2026-11-04T15:51:14.251Z pid=24568 mono=1842821.364 TICK begin publish=now parentRemaining=575.9008129835129 playtest=false browser=false
2026-11-04T15:51:14.251Z pid=24568 mono=1842821.364 PUBLISH session from=parent to=parent snapshotChanged=false
2026-11-04T15:51:14.251Z pid=24568 mono=1842821.364 TICK end mode=parent
2026-11-04T15:51:14.251Z pid=24568 mono=1842821.364 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=40 tab=games mode=parent draft=true
2026-11-04T15:51:14.257Z pid=24568 mono=1842821.370 VIEW name=ParentTapLetterSettingsView instance=C06463AA-D107-453F-B58A-E1A1BD5C54C9 body count=20 draft=true showMore=false
2026-11-04T15:51:14.541Z pid=24568 mono=1842821.654 INPUT parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) type=NSEventType(rawValue: 22) location={1522.88671875, 621.68359375} deltaY=-0.100006103515625 phase=0 momentum=0
2026-11-04T15:51:14.565Z pid=24568 mono=1842821.677 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) y=5805.0 rawY=5805.0 previous=5804.0 reason=bounds
2026-11-04T15:51:14.657Z pid=24568 mono=1842821.770 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=7907.0 documentFrame={{0, 0}, {1905, 7907}} documentBounds={{0, 0}, {1905, 7907}} viewport={1905, 884} flipped=true
2026-11-04T15:51:14.657Z pid=24568 mono=1842821.770 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) y=6046.0 rawY=6046.0 previous=5805.0 reason=document
2026-11-04T15:51:14.657Z pid=24568 mono=1842821.770 JUMP parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) from=6046.0 to=3600.7240740740735 delta=-2445.2759259259265 reason=bounds documentHeight=7907.0 documentFrame={{0, 0}, {1905, 7907}} documentBounds={{0, 0}, {1905, 7907}} viewport={1905, 884} flipped=true responder=KioskWindow@ObjectIdentifier(0x00000078b8f64a00) context=[1842821.364 TICK end mode=parent | 1842821.364 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=40 tab=games mode=parent draft=true | 1842821.370 VIEW name=ParentTapLetterSettingsView instance=C06463AA-D107-453F-B58A-E1A1BD5C54C9 body count=20 draft=true showMore=false | 1842821.654 wheel deltaY=-0.100006103515625 | 1842821.654 INPUT parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) type=NSEventType(rawValue: 22) location={1522.88671875, 621.68359375} deltaY=-0.100006103515625 phase=0 momentum=0 | 1842821.677 offset=5805.0 | 1842821.708 wheel deltaY=-10.83447265625 | 1842821.727 wheel deltaY=-13.296295166015625 | 1842821.770 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=7907.0 documentFrame={{0, 0}, {1905, 7907}} documentBounds={{0, 0}, {1905, 7907}} viewport={1905, 884} flipped=true | 1842821.770 offset=6046.0]
2026-11-04T15:51:14.657Z pid=24568 mono=1842821.770 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) y=3600.7240740740735 rawY=3600.7240740740735 previous=6046.0 reason=bounds
2026-11-04T15:51:14.751Z pid=24568 mono=1842821.864 TICK begin publish=now parentRemaining=575.4314119815826 playtest=false browser=false
2026-11-04T15:51:14.751Z pid=24568 mono=1842821.864 PUBLISH session from=parent to=parent snapshotChanged=false
2026-11-04T15:51:14.751Z pid=24568 mono=1842821.864 TICK end mode=parent
2026-11-04T15:51:14.752Z pid=24568 mono=1842821.864 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=41 tab=games mode=parent draft=true
2026-11-04T15:51:14.759Z pid=24568 mono=1842821.872 VIEW name=ParentTapLetterSettingsView instance=C06463AA-D107-453F-B58A-E1A1BD5C54C9 body count=21 draft=true showMore=false
```

Last recorded document height before the second Games reversal. Source lines **439–439**; the fenced text is copied verbatim, without line-number prefixes.

```text
2026-11-04T15:51:17.792Z pid=24568 mono=1842824.905 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=7872.0 documentFrame={{0, 0}, {1905, 7872}} documentBounds={{0, 0}, {1905, 7872}} viewport={1905, 884} flipped=true
```

Complete second Games reversal context. Source lines **455–471**; the fenced text is copied verbatim, without line-number prefixes.

```text
2026-11-04T15:51:18.783Z pid=24568 mono=1842825.896 TICK begin publish=now parentRemaining=571.431429028511 playtest=false browser=false
2026-11-04T15:51:18.783Z pid=24568 mono=1842825.896 PUBLISH session from=parent to=parent snapshotChanged=false
2026-11-04T15:51:18.783Z pid=24568 mono=1842825.896 TICK end mode=parent
2026-11-04T15:51:18.783Z pid=24568 mono=1842825.896 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=49 tab=games mode=parent draft=true
2026-11-04T15:51:18.789Z pid=24568 mono=1842825.902 VIEW name=ParentTapLetterSettingsView instance=C06463AA-D107-453F-B58A-E1A1BD5C54C9 body count=29 draft=true showMore=false
2026-11-04T15:51:19.049Z pid=24568 mono=1842826.162 INPUT parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) type=NSEventType(rawValue: 22) location={1522.88671875, 621.68359375} deltaY=-0.100006103515625 phase=0 momentum=0
2026-11-04T15:51:19.119Z pid=24568 mono=1842826.232 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=7924.0 documentFrame={{0, 0}, {1905, 7924}} documentBounds={{0, 0}, {1905, 7924}} viewport={1905, 884} flipped=true
2026-11-04T15:51:19.119Z pid=24568 mono=1842826.232 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) y=6181.7240740740735 rawY=6181.7240740740735 previous=6050.7240740740735 reason=document
2026-11-04T15:51:19.119Z pid=24568 mono=1842826.232 JUMP parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) from=6181.7240740740735 to=3613.485363372487 delta=-2568.2387107015866 reason=bounds documentHeight=7924.0 documentFrame={{0, 0}, {1905, 7924}} documentBounds={{0, 0}, {1905, 7924}} viewport={1905, 884} flipped=true responder=KioskWindow@ObjectIdentifier(0x00000078b8f64a00) context=[1842825.896 PUBLISH session from=parent to=parent snapshotChanged=false | 1842825.896 TICK end mode=parent | 1842825.896 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=49 tab=games mode=parent draft=true | 1842825.902 VIEW name=ParentTapLetterSettingsView instance=C06463AA-D107-453F-B58A-E1A1BD5C54C9 body count=29 draft=true showMore=false | 1842826.162 wheel deltaY=-0.100006103515625 | 1842826.162 INPUT parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) type=NSEventType(rawValue: 22) location={1522.88671875, 621.68359375} deltaY=-0.100006103515625 phase=0 momentum=0 | 1842826.170 wheel deltaY=-2.1683807373046875 | 1842826.176 wheel deltaY=-10.899185180664062 | 1842826.232 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=7924.0 documentFrame={{0, 0}, {1905, 7924}} documentBounds={{0, 0}, {1905, 7924}} viewport={1905, 884} flipped=true | 1842826.232 offset=6181.7240740740735]
2026-11-04T15:51:19.119Z pid=24568 mono=1842826.232 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) y=3613.485363372487 rawY=3613.485363372487 previous=6181.7240740740735 reason=bounds
2026-11-04T15:51:19.159Z pid=24568 mono=1842826.272 INPUT parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) type=NSEventType(rawValue: 22) location={1522.88671875, 621.68359375} deltaY=-30.726043701171875 phase=0 momentum=0
2026-11-04T15:51:19.193Z pid=24568 mono=1842826.306 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) y=3920.485363372487 rawY=3920.485363372487 previous=3613.485363372487 reason=bounds
2026-11-04T15:51:19.251Z pid=24568 mono=1842826.364 TICK begin publish=now parentRemaining=570.8995720148087 playtest=false browser=false
2026-11-04T15:51:19.251Z pid=24568 mono=1842826.364 PUBLISH session from=parent to=parent snapshotChanged=false
2026-11-04T15:51:19.251Z pid=24568 mono=1842826.364 TICK end mode=parent
2026-11-04T15:51:19.251Z pid=24568 mono=1842826.364 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=50 tab=games mode=parent draft=true
2026-11-04T15:51:19.259Z pid=24568 mono=1842826.372 VIEW name=ParentTapLetterSettingsView instance=C06463AA-D107-453F-B58A-E1A1BD5C54C9 body count=30 draft=true showMore=false
```

Last recorded document height before the third Games reversal. Source lines **483–483**; the fenced text is copied verbatim, without line-number prefixes.

```text
2026-11-04T15:51:20.139Z pid=24568 mono=1842827.252 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=7880.0 documentFrame={{0, 0}, {1905, 7880}} documentBounds={{0, 0}, {1905, 7880}} viewport={1905, 884} flipped=true
```

Complete third Games reversal context and the first subsequent idle tick. Source lines **511–526**; the fenced text is copied verbatim, without line-number prefixes.

```text
2026-11-04T15:51:21.751Z pid=24568 mono=1842828.864 TICK begin publish=now parentRemaining=568.4314509630203 playtest=false browser=false
2026-11-04T15:51:21.751Z pid=24568 mono=1842828.864 PUBLISH session from=parent to=parent snapshotChanged=false
2026-11-04T15:51:21.751Z pid=24568 mono=1842828.864 TICK end mode=parent
2026-11-04T15:51:21.752Z pid=24568 mono=1842828.865 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=55 tab=games mode=parent draft=true
2026-11-04T15:51:21.759Z pid=24568 mono=1842828.872 VIEW name=ParentTapLetterSettingsView instance=C06463AA-D107-453F-B58A-E1A1BD5C54C9 body count=35 draft=true showMore=false
2026-11-04T15:51:21.908Z pid=24568 mono=1842829.021 INPUT parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) type=NSEventType(rawValue: 22) location={1522.88671875, 621.68359375} deltaY=-0.100006103515625 phase=0 momentum=0
2026-11-04T15:51:21.939Z pid=24568 mono=1842829.052 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) y=6084.485363372487 rawY=6084.485363372487 previous=6083.485363372487 reason=bounds
2026-11-04T15:51:22.016Z pid=24568 mono=1842829.129 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=7930.0 documentFrame={{0, 0}, {1905, 7930}} documentBounds={{0, 0}, {1905, 7930}} viewport={1905, 884} flipped=true
2026-11-04T15:51:22.016Z pid=24568 mono=1842829.129 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) y=6492.485363372487 rawY=6492.485363372487 previous=6084.485363372487 reason=document
2026-11-04T15:51:22.016Z pid=24568 mono=1842829.129 JUMP parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) from=6492.485363372487 to=3909.4576737347948 delta=-2583.027689637692 reason=bounds documentHeight=7930.0 documentFrame={{0, 0}, {1905, 7930}} documentBounds={{0, 0}, {1905, 7930}} viewport={1905, 884} flipped=true responder=KioskWindow@ObjectIdentifier(0x00000078b8f64a00) context=[1842828.864 TICK end mode=parent | 1842828.865 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=55 tab=games mode=parent draft=true | 1842828.872 VIEW name=ParentTapLetterSettingsView instance=C06463AA-D107-453F-B58A-E1A1BD5C54C9 body count=35 draft=true showMore=false | 1842829.021 wheel deltaY=-0.100006103515625 | 1842829.021 INPUT parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) type=NSEventType(rawValue: 22) location={1522.88671875, 621.68359375} deltaY=-0.100006103515625 phase=0 momentum=0 | 1842829.052 offset=6084.485363372487 | 1842829.075 wheel deltaY=-25.325271606445312 | 1842829.092 wheel deltaY=-15.512100219726562 | 1842829.129 GEOMETRY parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) reason=document documentHeight=7930.0 documentFrame={{0, 0}, {1905, 7930}} documentBounds={{0, 0}, {1905, 7930}} viewport={1905, 884} flipped=true | 1842829.129 offset=6492.485363372487]
2026-11-04T15:51:22.016Z pid=24568 mono=1842829.129 OFFSET parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) y=3909.4576737347948 rawY=3909.4576737347948 previous=6492.485363372487 reason=bounds
2026-11-04T15:51:22.251Z pid=24568 mono=1842829.364 TICK begin publish=now parentRemaining=567.9313399791718 playtest=false browser=false
2026-11-04T15:51:22.252Z pid=24568 mono=1842829.364 PUBLISH session from=parent to=parent snapshotChanged=false
2026-11-04T15:51:22.252Z pid=24568 mono=1842829.364 TICK end mode=parent
2026-11-04T15:51:22.256Z pid=24568 mono=1842829.369 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=56 tab=games mode=parent draft=true
2026-11-04T15:51:22.273Z pid=24568 mono=1842829.386 VIEW name=ParentTapLetterSettingsView instance=C06463AA-D107-453F-B58A-E1A1BD5C54C9 body count=36 draft=true showMore=false
```

The final idle tick, quit-button input and teardown preserve the post-jump offset until the parent view disappears. Source lines **1142–1154**; the fenced text is copied verbatim, without line-number prefixes.

```text
2026-11-04T15:52:24.251Z pid=24568 mono=1842891.364 TICK begin publish=now parentRemaining=505.93244898319244 playtest=false browser=false
2026-11-04T15:52:24.252Z pid=24568 mono=1842891.365 PUBLISH session from=parent to=parent snapshotChanged=false
2026-11-04T15:52:24.252Z pid=24568 mono=1842891.365 TICK end mode=parent
2026-11-04T15:52:24.256Z pid=24568 mono=1842891.369 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=180 tab=games mode=parent draft=true
2026-11-04T15:52:24.275Z pid=24568 mono=1842891.388 VIEW name=ParentTapLetterSettingsView instance=C06463AA-D107-453F-B58A-E1A1BD5C54C9 body count=160 draft=true showMore=false
2026-11-04T15:52:24.357Z pid=24568 mono=1842891.470 INPUT parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) type=NSEventType(rawValue: 1) subtype=0 location={1816.51953125, 1034.0703125}
2026-11-04T15:52:24.465Z pid=24568 mono=1842891.578 INPUT parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) type=NSEventType(rawValue: 2) subtype=0 location={1816.51953125, 1034.0703125}
2026-11-04T15:52:24.474Z pid=24568 mono=1842891.587 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 body count=181 tab=games mode=parent draft=true
2026-11-04T15:52:24.481Z pid=24568 mono=1842891.594 VIEW name=ParentTapLetterSettingsView instance=C06463AA-D107-453F-B58A-E1A1BD5C54C9 body count=161 draft=true showMore=false
2026-11-04T15:52:24.547Z pid=24568 mono=1842891.660 DETACH parent=3B5F7B97-B135-40C2-BE21-67FD36809C28 tab=games scroll=ObjectIdentifier(0x00000078b8a5b000) lastOffset=3909.4576737347948
2026-11-04T15:52:24.591Z pid=24568 mono=1842891.704 VIEW name=ParentSettingsView instance=3B5F7B97-B135-40C2-BE21-67FD36809C28 disappear tab=games
2026-11-04T15:52:24.591Z pid=24568 mono=1842891.704 DRAFT clear state=79308AB1-05D3-41EB-9FF5-808E644EAC3A
2026-11-04T15:52:24.591Z pid=24568 mono=1842891.704 VIEW name=ParentTapLetterSettingsView instance=C06463AA-D107-453F-B58A-E1A1BD5C54C9 disappear
```
