# Parent settings scroll investigation — 0.37.0 / 76

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

## Collecting the next reproduction on the Mac mini

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

## Files in this change

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
