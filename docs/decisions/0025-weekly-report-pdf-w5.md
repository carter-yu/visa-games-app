# ADR 0025: Weekly report PDF and the 表現 row (W5)

Date: 2026-10-28
Status: Draft PR, source implementation awaiting Mac verification

## Context

Slice W5 of the weekly report (`visa-games-design/weekly-report/design.md` §12) makes the PDF on the Mac mini. The W4 HTML (ADR 0024, on main via #39, `6823ad3`) is loaded into an off-screen WKWebView and becomes an A4 PDF. The PDF is written under `stats/exports/weekly/` and shown in Finder from a new 每週報告 block in the parent 表現 screen. The slice also adds the `stats_marker{weekly_report}` line and the clear-dialog sentence (§9.2–§9.5, §10, §11). D1, D2, D3 A, D7 and D11 are locked.

W5b and W6 are later slices and are not built here:

- W5b: D12 B (auto-make at Sunday 21:00 when the app is idle in lock) and the D7 nickname setting.
- W6: D3 B (an in-app 「分享…」) and the D6 B rewrite.

## Decision

New VisaCore files, Foundation-only and run in the Linux checks:

- `WeeklyReportExport.swift`:
  - `WeeklyReportBuild`: one week's W3 text, W4 HTML, W1 model JSON, 數據指紋 and page count, built from the records.
  - `WeeklyReportFiles`: file names, paths and the atomic replace.
  - `WeeklyReportPDFMetadata` and `WeeklyReportPDFGeometry` (page rectangles, the A4 fit, the timeout, the navigation rule).
  - `WeeklyReportMarker` (the payload) and `WeeklyReportPDFError`.
- `WeeklyReportRow.swift`:
  - `WeeklyReportSchedule`: the week list and the Sunday 21:00 rule.
  - `WeeklyReportWeek` / `WeeklyReportWeekList`.
  - `WeeklyReportUILabels`: every row string and the clear sentence.
  - `WeeklyReportJob`, `WeeklyReportRow` and `WeeklyReportPanel`: the row state as one `Equatable` value.

New VisaCore file for macOS only: `WeeklyReportPDFMaker.swift`, the WebKit / CoreGraphics / PDFKit glue. The whole file is inside `#if os(macOS) && canImport(WebKit) && canImport(PDFKit) && canImport(AppKit)`.

App changes:

- `WeeklyReportCoordinator.swift`: a small `@MainActor` coordinator. It holds one maker, a generation counter and the Finder reveal.
- `PerformanceRecorder`:
  - three queue jobs: the week list, the build and the file writes;
  - `marker(_:_:)`, the existing marker helper, gains an optional payload.
- `AppModel`:
  - entry points `weeklyMake` and `weeklyShowInFinder`;
  - the published `weeklyPanel`;
  - a cancel on every way out of parent mode.
- `ParentWeeklyReportView` in `ParentReviewView.swift`, placed above the review in the 表現 section of `ParentSettingsView`.
- The clear confirmation gains the §11 sentence.
- Version 0.35.0 / build 71: the parent footer `versionLabel`, `Resources/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`) and the version check. The scripts read the version from the plist; no other file holds the current version.

W1–W4 code and goldens are unchanged. The W4 check file gains one accessor, `reportsForPDF()`, so the macOS check can measure the same 12 reports.

Choices where the design left room:

**PDF (§9.2, §9.5)**

- **A4 scaling: a scaled CoreGraphics redraw.** WebKit makes one PDF page per 794 × 1123 px section (`createPDF(configuration:)` with `rect` set, in document coordinates). Each page is then drawn into its own A4 page of one new PDF: 595.28 × 841.89 pt, scale 0.749679 (841.89 / 1123), centred 0.017 pt from each side. `CGContext.drawPDFPage` replays the page's content stream, so text and vectors stay text and vectors; nothing is rasterised. PDFKit then reads the result back and checks the page count and A4 boxes before anything is written. The alternatives were rejected:
  - `pageZoom = 0.75` gives 595.5 × 842.25 pt pages, not A4. Page offsets become fractional (842.25 pt), and how WebKit rounds them is not documented.
  - Setting the page boundsrect crops the page; it does not scale it.
- **Fallback.** If PDFKit cannot read the text back after the redraw, the fallback is `pageZoom = 0.75` with 595.28 × 841.89 pt page rectangles. The same applies if the redraw turns out to be what puts radical code points in the text layer (next bullet).
- **Text layer: Kangxi radicals (Mac mini run at `631aa99`).**
  - What the run showed: `testPDFIsA4SixPages` passed: six A4 pages and §9.5 metadata, and one page without countable play. `testPDFTextContainsKeyStrings` then found 每週學習報告, "Weekly learning report" and "Cedric" in PDFKit's text, but not 邊個影子.
  - What explains it: the PDF draws every character, and its text layer stores each one as a code point. macOS's PDF writer gets glyphs, not text, from WebKit; it finds a code point for each glyph by looking the glyph up in the font. PingFang draws an ideograph and its Kangxi radical twin with one glyph, for example 子 U+5B50 and ⼦ U+2F26. The lookup can then return the radical, so PDFKit reads 「邊個影⼦」.
  - The evidence: 邊個影子 is the first needle with such a character, and the three that passed have none. In the §5.6 report 36 distinct characters have a twin (一 二 人 子 日 月 比 頁 …), 427 of the 2,968 CJK characters. The same behaviour is widely reported for Safari's and Pages' PDF exports on macOS.
  - What it means: no text is lost. The page shows the right glyph, the text is selectable, and every Kangxi radical has a Unicode compatibility mapping to its ideograph. Copying or searching the shared PDF can still give the radical code point for those characters.
  - The check: it now compares PDFKit's text and every needle under NFKC (compatibility normalization) with whitespace dropped. NFKC folds all 214 Kangxi radicals and the CJK compatibility ideographs back to the unified ideographs, and it is applied to both sides. No needle was removed.
  - Diagnostics: a missing needle prints the raw extracted text around where it should be, with any radical or compatibility code points listed. Every run prints the radical count of the A4 PDF, of its page 1, and of WebKit's own page 1 made in a test-only web view before any redraw. If WebKit's page has none and the A4 page has them, the redraw is the cause, and the maker moves to the `pageZoom` fallback.
  - Not done in W5: the maker does not rewrite the PDF's ToUnicode maps to restore the unified code points. That needs a PDF object rewriter that cannot be tested on the box; it is a later fix if Carter wants copy and search to return 子 rather than ⼦.
- **Kept output (opt-in).** With `VISA_W5_PDF_OUT=<folder>`, the macOS checks write `sample-ranking-5.6.pdf` and `weekly-2026-10-19.pdf`, and each PDF's text per page as `.txt`, before their assertions. Unset, nothing is written.
- **Pages.** The page count is the number of `<section class="page` in the W4 document: six with countable play, one without. The web view frame is 794 × (1123 × pages), so every page rectangle lies inside its bounds.
- **Metadata.** The new PDF's Info dictionary holds:
  - Title 「VisaGames 每週學習報告 2026-10-19」 (W4's `doc.title` with the week start);
  - Author 「VisaGames」 and Creator 「VisaGames」.
  Quartz writes Producer ("macOS … Quartz PDFContext") and the dates. No user name, path or session id.
- **No script, no network, one document.**
  - Page scripts are off (`allowsContentJavaScript = false`), and the website data store is non-persistent.
  - Media need a user action, and there is no UI delegate, so no new window can open.
  - The navigation policy allows only the main-frame `about:blank` that `loadHTMLString(_:baseURL: nil)` creates; everything else is cancelled.
  - The W4 HTML has no URL, script, font file or image (`testHTMLSelfContained`).
- **Off-screen.** The web view is never added to a window or view, so it cannot appear over the kiosk or take focus.
  - It exists only from `make` to the end of the job.
  - Every outcome ends in one place (`finish`): navigation stopped, delegate cleared, reference dropped. Later WebKit callbacks find no job and do nothing.
- **Failures.** Every failure ends with one parent line, 「製作唔到報告，請再試。（唔影響小朋友玩）」. The log gets the reason:
  - `busy`, `invalid_input`;
  - `load_failed` (a load error, a refused navigation or a crashed web content process);
  - `page_failed`, `merge_failed`;
  - `timed_out` (20 s from the start: load, every page and the merge);
  - `cancelled`.
  Nothing throws into the app and nothing blocks the main actor: WebKit work is asynchronous, and the redraw runs in a detached task. The PDFKit read-back is short, on the main actor.
- **Cancel.** `AppModel` cancels the make on every way out of parent mode:
  - `returnToChild` (Return, the 10-minute auto-lock, sleep, the debug soak);
  - the test visa, which leaves parent mode without `returnToChild`;
  - 「清除表現紀錄」 and quitting.
  A cancelled make writes nothing and reveals nothing; the log gets `weekly report — cancelled`. A make that has already handed its PDF to the file write still finishes the write and its marker, but the Finder reveal also needs `canReveal` (parent mode).
- **Not on the auto-lock timer.** 製作 PDF does not restart the 10-minute auto-lock. A make takes seconds; the cancel path covers an auto-lock that falls inside one.

**Where the PDF maker lives**

- **No rule against it.** `docs/ground-rules.md` has no "VisaCore is Foundation-only" rule. VisaCore has been Foundation-only by practice, and the W4 check bans WebKit / AppKit imports in the six W4 renderer files only.
- **Why VisaCore.** `sh scripts/test.sh` runs only `VisaCoreChecks`, which depends only on VisaCore. The macOS checks must reach the maker, so it lives in VisaCore behind the platform guard. On Linux the file compiles to nothing, VisaCore stays Foundation-only, and `swift build --product VisaCoreChecks` stays valid.
- **Why not a new target.** A new SwiftPM target would need a `Package.swift` change. `ActorIsolationTests` asserts the exact `VisaGames` target line, and the new target would need the same `#if` guards for Linux. That is more change for the same result.
- **Imports.** The pure files import Foundation (and libc for `rename`) only, which a check asserts.

**Building off the main actor**

- `WeeklyReportText`, `WeeklyReportBuild` and the events are `Sendable`. The build (read, W1–W3, W4 render, model JSON, fingerprint) therefore runs on the recorder's serial queue after any queued writes, so a just-tapped 唔計呢段 counts. Only WebKit runs on the main actor, and it is asynchronous.
- The week list is read on the same queue, when 表現 opens, on 更新 and after 唔計呢段 / 計返: the same triggers as the review, never from a view body.

**Week list (§9.3, §9.4)**

- **Which weeks.** This week always, with data up to the read and the draft note. Then each earlier week with countable play, newest first.
  - "Countable play" is W1's 「有玩嘅日子」 rule (a counted round or play, seen to the end of the week). It is the same rule that makes a report six pages, so a listed earlier week never renders as the one-page 「今個星期未有紀錄」.
  - Parent-only weeks, 唔計呢段 weeks and weeks with only a marker are left out.
- **Cap: 8 rows in all** (this week + 7). 8 weeks are 56 days, so each listed week and its previous week sit inside the 90-day raw retention. The search looks back at most 26 weeks and never before the first raw record. Older PDFs stay in the folder.
- **Labels.**
  - The week label is 「10月19日至10月25日」 / "Oct 19 – Oct 25", with no year. It reads `WeeklyWindow`'s Hong Kong day stamps and fills the design's 「{m}月{d}日至{m2}月{d2}日」 pattern.
  - `isComplete` and `isDraft` are relative to the moment of the read. Making a row always uses the time of the tap: a draft row tapped after Monday 00:00 gives the complete week, with the same file name.

**Ready line (§9.3, D1)**

- **When it shows.** 「今個星期嘅報告可以製作喇」 shows from Sunday 21:00:00 HKT to the end of Sunday, as of the last read (opening 表現 or 更新). It is not re-evaluated on the 0.5 s tick: the 表現 view is `.equatable()` for layout safety. If the screen stays open across 21:00, 更新 shows the line.
- **Making before 21:00.** This week's report can be made at any time as a draft: D1 "on demand with data up to that moment", and the design's own 星期未完 copy. The ready line marks when the week is ready; it does not gate the button. Last week's report can be made at any time.

**Marker (§10.2)**

- **Fields.** `stats_marker{what: "weekly_report", week, data_until, pages, fingerprint}`:
  - the week start, the cut-off (ISO UTC), the page count and the footer's 8 hex digits;
  - nothing else: no name, path or file name.
  The parent actor writes it through the same `marker(_:_:)` helper as `cleared` / `reset_storage`, once the files are written. The line lands in the raw day file.
- **CSV.** The CSV export lists no markers. The design's "visible in the CSV export" is not made true here; that would be a separate export change.
- **W1–W4 must not change.**
  - W1–W4 read only `cleared` and `variants_v1` markers by name, but some steps read every record: W2's page-5 versions read every record's `app`; W1's first record and trend weeks look at any record.
  - A marker on a day that already has records, from the running launch and version, changes nothing. A check holds this byte for byte on both fixtures' four goldens, and the Python references agree.
  - A marker elsewhere would show: an otherwise empty week would become a trend week, and an unseen version would appear on page 5.
  - So `WeeklyReportBuild.reportEvents` drops the report's own markers before W1. Making or remaking a report never changes a number, list, sentence or byte, also checked with stray markers.

**Files (§9.5, D11)**

- **Names.**
  - PDF: `stats/exports/weekly/VisaGames-weekly-2026-10-19_to_10-25.pdf` (ASCII, Hong Kong days, the week end as `MM-dd`, so a week can end in the next month or year).
  - Model: `stats/exports/weekly/data/VisaGames-weekly-2026-10-19.json`.
- **Atomic replace.** Each file is written to a hidden temporary file in its own folder, then `rename(2)`d over the target. Remaking a week replaces both files, and a failed write leaves the old file and no temporary one. The JSON is written first, so the shared PDF is the last file to change.
- **D11 JSON.** It is `WeeklyModel.canonicalJSON()`, the W1 golden format. It holds round ids but no session or launch ids. It stays local in `data/`; the PDF is the file to share.
- **Clear.** 「清除表現紀錄」 deletes all of `stats/`, `exports/weekly/` included (ADR 0008 §7). `perfClear` resets the coordinator before the clear is queued, so no weekly write lands after it. 「清除簽證及重設儲存」 does not touch `stats/`.

**表現 row (§9.4)**

- **Where.** A separate `Equatable` block above the review panel in the 表現 section, with `.equatable()` at the call site. It is built from the same file's `ReviewText` / `ReviewChipButton` and the 最近玩過 row frame, with the same panel style.
- **Contents.**
  - the title and the ready line;
  - one row per week: the dates, the draft note and 製作 PDF (製作緊… and off while any make runs);
  - after a make: 已製作，資料夾已開啟。, the Finder hint and 喺 Finder 顯示; a failure line on failure;
  - the share note.
- **Strings.** Status and button lines read 「中文 / English」, like the CSV export's status line. The §9.4 strings are verbatim.
- **Video.** A make is refused while a video plays (`weeklyMake` guards `activePlayVideoID == nil`). Switching to 表現 already stops a 試播 preview.
- **Finder.** The reveal uses the CSV export's call, `activateFileViewerSelecting`: no save panel, no share sheet. Since ADR 0011 the Finder window opens under the kiosk window, so the done state adds a hint: quit with 「離開程式」 to see it.
- **Child's name.** D7 Cedric comes from the existing constant `WeeklyReportText.defaultChildName`. W5b adds the parent-set nickname.

**Checks**

- **Linux.** 12 checks in `WeeklyReportPDFTests.swift`. `testReviewViewLayoutSafetySourceGuard` is extended to the new block: banned symbols, `.equatable()` twice at the call site, model-only actions, and the §9.4 strings.
- **macOS.** 4 checks in `WeeklyReportPDFMacTests.swift`, run last in `sh scripts/test.sh` under the same platform guard:
  - `testPDFIsA4SixPages`: the §5.6 week and the W1 fixture's week, each 6 × A4, plus the one-page week;
  - `testPDFTextContainsKeyStrings`: compared under NFKC;
  - `testPDFMakerFailsCleanly`;
  - `testWebKitPageOverflow`.
- **Run loop.** The runner's `main` is now `@MainActor` (a no-op for the existing synchronous checks). Each macOS check starts WebKit work and spins `RunLoop.main` until the completion or a deadline (60 s per make, 30 s per load), so a check can neither hang nor deadlock. No `assumeIsolated`, no semaphore.
- **No window server: a loud SKIP.**
  - The checks first call `CGSessionCopyCurrentDictionary()`. When it is nil (a plain SSH login), WebKit and AppKit are never touched, the line `SKIP weekly report pdf (macOS): no WebKit rendering available — …` is printed, and the PASS banner ends with `+ 0 weekly-report-pdf-macos (SKIPPED: no window server)`.
  - `SSH_CONNECTION` is printed but decides nothing.
  - In a window-server session every WebKit failure fails the run.
  - Why a SKIP: without a session AppKit itself can abort the process, which would hide the other 300+ checks. A visible SKIP is honest.
- **Measurement.** `testWebKitPageOverflow` loads every page of both fixtures and the ten synthetic weeks into a test-only web view; page scripts are allowed there only, and the production maker keeps them off. One script measures, per page:
  - the bottom of the in-flow content against the 1066 px content box (1123 − 57 px padding), with the running head, foot and sample watermark aside;
  - boxes clipped by or wider than the page;
  - text wider than its box, or taller than a box that clips or has a fixed height (the running head and foot);
  - chart labels outside their chart.
  It prints one line per report and fails on any finding: the WebKit hand-off of ADR 0024. Glyphs that stand a few px over a tight line box in a block that does not clip are not findings: in Chrome, the page-1 title (37 > 35 px) and the tile values (29 > 26 px) do this on every report, and nothing is hidden.
- **Chrome approximation on the box.** The same script, run in headless Chrome over the same 12 reports (67 pages), finds nothing. The tallest content ends at 1026.5 of 1066 px (§5.6 week, page 3), the figure W4 reported. These are Chrome numbers; the Mac mini check gives WebKit's.

**Copy written for gaps (Carter to review)**

- `review.weekly.loading` 「計緊…」 / "Loading…" (the review's own 計緊…, while the weeks are read).
- `review.weekly.finderHint` 「見唔到 Finder？佢喺 Visa Games 後面打開，撳「離開程式」就見到。」 / "No Finder window? It opens underneath Visa Games; use Quit to see it." The English avoids "behind", which is on the §6.3 banned-word list.
- `clear.sharedReports` holds §11's sentence verbatim: 「已經分享出去嘅週報唔會被刪除。」 / "Reports you have already shared are not deleted."
- The English week label "Oct 19 – Oct 25" fills §9.4's "{Mon d} – {Mon d2}".
- The share note keeps §9.4's wording, with the name filled from the D7 constant.

## Consequences

- **Version.** The app changes, so the version is 0.35.0 / build 71 (MINOR: a new parent capability; no persistence change).
- **Records.** The only new record is `stats_marker{weekly_report}`, through the existing marker helper. No new event type, setting or UserDefaults key.
- **Kiosk.** No kiosk boundary changes. The off-screen web view is never in a window, and nothing new is reachable from child screens. One OS path is recorded in `docs/phase-0-kiosk-checklist.md`, together with a W5 UAT row: like the CSV export, 製作 PDF and 喺 Finder 顯示 make Finder the active app, under the kiosk window, until the screen is touched again.
- **Not verified here.** Swift was not compiled or run (Linux box, no toolchain). On this box:
  - the pure expectations were replayed in Python;
  - the "marker changes no W1–W4 output" claim was replayed with the fixtures' Python references;
  - headless Chrome printed and measured the pages (an approximation; WebKit is the target).
  The Mac mini `sh scripts/test.sh`, the bundle and Carter's UAT are pending.

## What Carter should check on the Mac mini UAT

1. **Checks.** Run `sh scripts/test.sh` in Terminal inside the Mac's own login session, not a plain SSH login. Expect PASS with `+ 12 weekly-report-pdf … + 4 weekly-report-pdf-macos checks`. Keep the `WebKit page fit` lines for the PR comment; they are the per-page numbers.
2. **The row.** Bundle, install, open 家長 → 表現. The 每週報告 block sits above 遊戲表現 / 影片表現 on the TV:
   - the title;
   - this week with 星期未完（資料截至而家）, then earlier weeks;
   - the share note with Cedric;
   - the same look as the 最近玩過 rows.
3. **Make last week's PDF.**
   - The button reads 製作緊… and is off, then 已製作，資料夾已開啟。, the Finder hint and 喺 Finder 顯示 appear.
   - Quit with 「離開程式」: Finder shows `VisaGames-weekly-YYYY-MM-DD_to_MM-DD.pdf` in `~/Library/Application Support/VisaGames/stats/exports/weekly/`, with `data/VisaGames-weekly-YYYY-MM-DD.json` beside it.
4. **pdfinfo.** Pages 6, page size 595.28 x 841.89 pts (A4), Title 「VisaGames 每週學習報告 YYYY-MM-DD」, Author and Creator VisaGames, no user name. `pdftotext` shows the Chinese and English text; some characters may come out as Kangxi radicals (⼦ for 子, see "Text layer" above). To read the PDFs the checks make, run `VISA_W5_PDF_OUT=/tmp/w5 sh scripts/test.sh`.
5. **Phone.** AirDrop the PDF to the iPhone and read it in Files at 2× zoom: six pages, text selectable, nothing cut at the page edges.
6. **Ready line.** On Sunday after 21:00, open 表現 (or tap 更新): 今個星期嘅報告可以製作喇 shows. It does not show before 21:00 or on Monday.
7. **Auto-lock during making.** Start a make with a few seconds left on the auto-lock countdown, or put the Mac to sleep while it says 製作緊…. Expect:
   - the lock screen, with no Finder, window, panel or sheet over the kiosk;
   - `weekly report — cancelled` in the log;
   - no 已製作 line on the next parent visit.
8. **Remake.** Make the same week again: the file is replaced, with the same name and no extra file.
9. **Clear dialog.** 「清除表現紀錄」 shows 「…簽證同准許影片唔會變。已經分享出去嘅週報唔會被刪除。 / Clear all performance records? Reports you have already shared are not deleted.」. After 確定清除, `stats/exports/weekly/` is gone. 「清除簽證及重設儲存」 leaves it.
10. **Marker line.** Today's `stats/events-*.jsonl` has the `stats_marker` line with `what` weekly_report, `week`, `data_until`, `pages` and `fingerprint`, and no name or path.
