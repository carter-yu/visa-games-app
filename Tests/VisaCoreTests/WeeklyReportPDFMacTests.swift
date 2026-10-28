#if os(macOS) && canImport(WebKit) && canImport(PDFKit) && canImport(AppKit)
import AppKit
import CoreGraphics
import Foundation
import PDFKit
import VisaCore
import WebKit

/// Weekly report W5, macOS only (weekly-report design §9.2, §9.5, §12 W5; ADR 0025): the real PDF path — the production
/// `WeeklyReportPDFMaker` (off-screen WKWebView → one `createPDF` per page → A4) read back with PDFKit — its failure
/// paths, and WebKit's own per-page overflow measurement of the W4 pages (deferred from W4, ADR 0024).
///
/// The runner's `main` is `@MainActor` and synchronous. Each check starts WebKit work, then spins the main run loop until
/// the completion arrives or a deadline passes, so a check can neither hang nor deadlock: a missing answer fails with a
/// message. Without a window-server session (`CGSessionCopyCurrentDictionary()` is nil, as in a plain SSH login) WebKit is
/// never touched and the checks print a loud SKIP; in a GUI session every WebKit failure fails the run.
@MainActor
final class WeeklyReportPDFMacTests {
    /// Why the checks did not run (no window server), or nil when they ran.
    let skipReason: String?
    private(set) var ran = 0

    /// Sunday 2026-10-25, 21:00 HKT: when the fixtures were made.
    private static let madeAt = PerfCodec.parseTimestamp("2026-10-25T13:00:00.000Z")!
    /// The page headings of a six-page report, pages 2–6 (page 1 is the cover).
    private static let headings = ["每日明細", "玩咗乜、做成點", "做得好嘅同仲學緊嘅", "同上星期比較", "結論同下一步"]

    init() {
        let reason = Self.windowServerProblem()
        skipReason = reason
        if let reason {
            print("  SKIP weekly report pdf (macOS): no WebKit rendering available — \(reason). The 4 macOS PDF "
                  + "checks did NOT run; run sh scripts/test.sh in Terminal inside the Mac's own login session.")
        } else {
            // A command-line process: no Dock icon, no menu bar, no window. WebKit only needs AppKit set up.
            NSApplication.shared.setActivationPolicy(.prohibited)
        }
    }

    /// Nil in a window-server (Aqua) session; otherwise why WebKit cannot render here. SSH is reported, not decisive.
    static func windowServerProblem() -> String? {
        let ssh = ProcessInfo.processInfo.environment["SSH_CONNECTION"] != nil
        if CGSessionCopyCurrentDictionary() == nil {
            return "no window-server session (CGSessionCopyCurrentDictionary() is nil"
                + (ssh ? "; SSH_CONNECTION is set)" : ")")
        }
        if ssh {
            print("  weekly report pdf (macOS): SSH_CONNECTION is set but a window-server session exists, so the checks run")
        }
        return nil
    }

    // MARK: Run loop, results and fixtures

    /// Spins the main run loop until `done()` or `seconds` pass. False on timeout.
    private func spin(_ seconds: Double, until done: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !done() {
            if Date() >= deadline { return false }
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return true
    }

    private static func failure(_ result: Result<Data, WeeklyReportPDFError>?) -> WeeklyReportPDFError? {
        guard case .failure(let error)? = result else { return nil }
        return error
    }

    /// One make with `maker`, waited for on the run loop (60 s limit for the check; the maker's own limit is 20 s).
    private func make(_ build: WeeklyReportBuild, with maker: WeeklyReportPDFMaker,
                      label: String) -> (data: Data, seconds: Double) {
        let box = ResultBox()
        let started = Date()
        maker.make(html: build.html, pageCount: build.pageCount, metadata: build.metadata) { result in
            box.result = result
        }
        expectTrue(spin(60) { box.result != nil }, "\(label): the PDF maker gave no answer within 60 s")
        expectFalse(maker.isMaking || maker.hasWebView, "\(label): WebKit was not torn down")
        switch box.result {
        case .success(let data)?:
            return (data: data, seconds: Date().timeIntervalSince(started))
        case .failure(let error)?:
            preconditionFailure("\(label): no WebKit rendering available — the PDF maker failed with \(error.rawValue)")
        case nil:
            preconditionFailure("\(label): the PDF maker gave no answer")
        }
    }

    private static func fixtureFolder(_ name: String) -> URL {
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: beside.path) { return beside }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/VisaCoreTests/Fixtures/\(name)", isDirectory: true)
    }

    /// A fixture week as the app builds it (no sample watermark), made on Sunday 21:00 with the folder's titles.
    private static func fixtureBuild(_ name: String) throws -> WeeklyReportBuild {
        let folder = fixtureFolder(name)
        let store = PerfEventStore(directory: folder)
        let read = store.read()
        let titleData = try Data(contentsOf: folder.appendingPathComponent("video-titles.json"))
        let titles = try JSONDecoder().decode([String: String].self, from: titleData)
        guard !read.events.isEmpty,
              let build = WeeklyReportBuild.make(events: read.events, rollup: store.loadRollup(), weekStart: "2026-10-19",
                                                 now: madeAt, videoTitles: titles) else {
            preconditionFailure("weekly fixture \(name) did not build")
        }
        return build
    }

    /// Parent playtest rounds only: no countable play, so the one-page report.
    private static func playtestOnlyWeek() -> WeeklyReportBuild {
        let monday = PerfCodec.parseTimestamp("2026-10-18T16:00:00.000Z")!
        var events: [PerfEvent] = []
        for index in 0..<2 {
            let id = "pt\(index)"
            let dealtAt = monday.addingTimeInterval(Double(10 * 3600 + index * 60))
            events.append(PerfEvent(type: .gameDealt, timestamp: dealtAt, tz: "+08:00", mono: Double(2 * index),
                                    launch: "L1", seq: 2 * index + 1, app: "0.35.0", actor: .parentPlaytest,
                                    mode: "parent", session: "pt",
                                    fields: ["round": .string(id), "kind": .string("shadowMatch"), "stars": .int(0)]))
            events.append(PerfEvent(type: .roundResult, timestamp: dealtAt.addingTimeInterval(30), tz: "+08:00",
                                    mono: Double(2 * index + 1), launch: "L1", seq: 2 * index + 2, app: "0.35.0",
                                    actor: .parentPlaytest, mode: "parent", session: "pt",
                                    fields: ["round": .string(id), "kind": .string("shadowMatch"),
                                             "outcome": .string("solved"), "answers": .int(1), "first_try": .bool(true)]))
        }
        guard let build = WeeklyReportBuild.make(events: events, rollup: PerfRollup(), weekStart: "2026-10-19",
                                                 now: madeAt) else {
            preconditionFailure("the playtest-only week did not build")
        }
        return build
    }

    private static func document(_ data: Data, _ label: String) -> PDFDocument {
        guard let document = PDFDocument(data: data) else { preconditionFailure("\(label): PDFKit cannot read the PDF") }
        return document
    }

    private static func expectA4(_ document: PDFDocument, _ label: String) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else {
                expectTrue(false, "\(label): page \(index + 1) missing")
                continue
            }
            let box = page.bounds(for: .mediaBox)
            expectTrue(abs(Double(box.width) - WeeklyReportPDFGeometry.a4Width) <= 0.5
                       && abs(Double(box.height) - WeeklyReportPDFGeometry.a4Height) <= 0.5,
                       "\(label): page \(index + 1) is \(box.width) × \(box.height) pt, not A4 595.28 × 841.89")
        }
    }

    /// PDF text extraction places spaces and line breaks by layout: compare without them.
    private static func squeezed(_ text: String) -> String {
        text.filter { !$0.isWhitespace }
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    // MARK: testPDFIsA4SixPages (design §12 W5)

    func testPDFIsA4SixPages() throws {
        guard skipReason == nil else { return }
        let sample = try Self.fixtureBuild("weekly-ranking-5.6")
        expectEqual(sample.pageCount, 6)
        let made = make(sample, with: WeeklyReportPDFMaker(), label: "§5.6 sample week")
        let document = Self.document(made.data, "§5.6 sample week")
        expectEqual(document.pageCount, 6, "the §5.6 week has six pages")
        Self.expectA4(document, "§5.6 sample week")
        // §9.5 metadata: the title with the week start; the app as author and creator; no user name or path.
        let attributes = document.documentAttributes ?? [:]
        expectEqual(attributes[PDFDocumentAttribute.titleAttribute] as? String, "VisaGames 每週學習報告 2026-10-19")
        expectEqual(attributes[PDFDocumentAttribute.authorAttribute] as? String, "VisaGames")
        expectEqual(attributes[PDFDocumentAttribute.creatorAttribute] as? String, "VisaGames")
        let people = [NSUserName(), NSFullUserName(), NSHomeDirectory(), "/Users/"].filter { $0.count >= 3 }
        for key in [PDFDocumentAttribute.titleAttribute, PDFDocumentAttribute.authorAttribute,
                    PDFDocumentAttribute.creatorAttribute, PDFDocumentAttribute.subjectAttribute,
                    PDFDocumentAttribute.keywordsAttribute] {
            guard let value = attributes[key] as? String else { continue }
            for needle in people {
                expectFalse(value.contains(needle), "PDF \(key.rawValue) holds \(needle)")
            }
        }
        // A week without countable play: one A4 page.
        let quiet = Self.playtestOnlyWeek()
        expectEqual(quiet.pageCount, 1)
        let one = make(quiet, with: WeeklyReportPDFMaker(), label: "week without countable play")
        let single = Self.document(one.data, "week without countable play")
        expectEqual(single.pageCount, 1, "a week without countable play has one page")
        Self.expectA4(single, "week without countable play")
        print("  weekly report pdf (macOS): §5.6 week 6 × A4 595.28 × 841.89 pt, \(made.data.count) bytes in "
              + "\(Self.oneDecimal(made.seconds)) s; empty week 1 × A4 in \(Self.oneDecimal(one.seconds)) s; "
              + "Title / Author / Creator per §9.5")
        ran += 1
    }

    // MARK: testPDFTextContainsKeyStrings (design §12 W5)

    func testPDFTextContainsKeyStrings() throws {
        guard skipReason == nil else { return }
        let sample = try Self.fixtureBuild("weekly-ranking-5.6")
        let made = make(sample, with: WeeklyReportPDFMaker(), label: "§5.6 sample week")
        let document = Self.document(made.data, "§5.6 sample week")
        // Text, not pictures: PDFKit reads the words back.
        let text = Self.squeezed(document.string ?? "")
        for needle in ["每週學習報告", "Weekly learning report", "Cedric", "邊個影子", "本週重點", "第 1 頁，共 6 頁",
                       "第 6 頁，共 6 頁", "Page 6 of 6", "數據指紋 " + sample.fingerprint, "想問你哋"] {
            expectTrue(text.contains(Self.squeezed(needle)), "the PDF text is missing \(needle)")
        }
        // Every page carries its own words in order: its page line and, from page 2, its heading.
        for index in 0..<document.pageCount {
            let page = Self.squeezed(document.page(at: index)?.string ?? "")
            expectTrue(page.contains(Self.squeezed("第 \(index + 1) 頁，共 6 頁")), "page \(index + 1) text")
            if index >= 1 && index - 1 < Self.headings.count {
                expectTrue(page.contains(Self.headings[index - 1]), "page \(index + 1) heading \(Self.headings[index - 1])")
            }
        }
        print("  weekly report pdf (macOS): text selectable on all 6 pages (title, Cedric, game names, page lines, "
              + "fingerprint \(sample.fingerprint))")
        ran += 1
    }

    // MARK: Failure paths: refused input, busy, cancel (auto-lock), hard timeout; never a window

    func testPDFMakerFailsCleanly() throws {
        guard skipReason == nil else { return }
        let windows = NSApplication.shared.windows.count
        let build = try Self.fixtureBuild("weekly-2026-10-19")
        let maker = WeeklyReportPDFMaker()
        // Bad input: answered at once, nothing started.
        let bad = ResultBox()
        maker.make(html: "", pageCount: 6, metadata: build.metadata) { bad.result = $0 }
        expectEqual(Self.failure(bad.result), .invalidInput)
        bad.result = nil
        maker.make(html: build.html, pageCount: 0, metadata: build.metadata) { bad.result = $0 }
        expectEqual(Self.failure(bad.result), .invalidInput)
        expectFalse(maker.isMaking || maker.hasWebView)
        // One make at a time; cancel (what leaving parent mode does) ends it at once and tears WebKit down.
        let first = ResultBox()
        maker.make(html: build.html, pageCount: build.pageCount, metadata: build.metadata) { first.result = $0 }
        expectTrue(maker.isMaking && maker.hasWebView)
        let second = ResultBox()
        maker.make(html: build.html, pageCount: build.pageCount, metadata: build.metadata) { second.result = $0 }
        expectEqual(Self.failure(second.result), .busy)
        expectEqual(NSApplication.shared.windows.count, windows, "the off-screen web view is in no window")
        maker.cancel()
        expectEqual(Self.failure(first.result), .cancelled)
        expectFalse(maker.isMaking || maker.hasWebView)
        // Late WebKit callbacks of the cancelled make change nothing.
        _ = spin(1) { false }
        expectEqual(Self.failure(first.result), .cancelled)
        // The hard timeout: a 1 ms limit fires before WebKit can finish, with the same teardown.
        let hurried = WeeklyReportPDFMaker(timeout: 0.001)
        let late = ResultBox()
        hurried.make(html: build.html, pageCount: build.pageCount, metadata: build.metadata) { late.result = $0 }
        expectTrue(spin(10) { late.result != nil }, "the timeout did not fire within 10 s")
        expectEqual(Self.failure(late.result), .timedOut)
        expectFalse(hurried.isMaking || hurried.hasWebView)
        // The first maker still works after a cancel; still no window.
        let again = make(build, with: maker, label: "make after cancel")
        expectEqual(Self.document(again.data, "make after cancel").pageCount, build.pageCount)
        expectEqual(NSApplication.shared.windows.count, windows, "no window after the makes")
        print("  weekly report pdf (macOS): invalid input, busy, cancel and the timeout end cleanly; WebKit torn down; "
              + "no window")
        ran += 1
    }

    // MARK: WebKit page measurement (ADR 0024 hand-off)

    /// Measures every `section.page`: the bottom of its in-flow content (running head, foot and watermark aside)
    /// against the content box (1123 − 57 px padding = 1066 px), and any box clipped by the page or wider than the
    /// page, any text wider than its box, any text taller than a box that clips or has a fixed height (the running head
    /// and foot), and any chart label outside its chart. Glyphs a few px over a tight line box in a block that does not
    /// clip (the page-1 title and tile values) are not findings. Test-only script.
    private static let pageScript = #"""
        (function () {
          function r1(x) { return Math.round(x * 10) / 10; }
          function name(el) {
            var tag = el.tagName.toLowerCase();
            var cls = el.getAttribute('class');
            if (cls) { tag += '.' + cls.trim().split(/\s+/).join('.'); }
            var words = (el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 28);
            return tag + ' "' + words + '"';
          }
          var out = [];
          var pages = document.querySelectorAll('section.page');
          for (var i = 0; i < pages.length; i++) {
            var page = pages[i];
            var box = page.getBoundingClientRect();
            var limit = box.height - parseFloat(getComputedStyle(page).paddingBottom);
            var bottom = 0, clipped = [], wide = [], text = [], svg = [];
            var all = page.querySelectorAll('*');
            for (var j = 0; j < all.length; j++) {
              var el = all[j];
              if (el.closest('.wm')) { continue; }
              var r = el.getBoundingClientRect();
              if (r.width === 0 && r.height === 0) { continue; }
              var top = r.top - box.top, bot = r.bottom - box.top;
              var left = r.left - box.left, right = r.right - box.left;
              if (!el.closest('.runhead, .runfoot') && bot > bottom) { bottom = bot; }
              if (bot > box.height + 0.5 || top < -0.5) { clipped.push(name(el) + ' ' + r1(top) + '..' + r1(bot)); }
              if (right > box.width + 0.5 || left < -0.5) { wide.push(name(el) + ' ' + r1(left) + '..' + r1(right)); }
              if (!(el instanceof SVGElement) && getComputedStyle(el).display !== 'inline') {
                if (el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 1) {
                  text.push(name(el) + ' width ' + el.scrollWidth + '>' + el.clientWidth);
                }
                var clips = getComputedStyle(el).overflowY !== 'visible' || el.matches('.runhead, .runfoot');
                if (clips && el.clientHeight > 0 && el.scrollHeight > el.clientHeight + 1) {
                  text.push(name(el) + ' height ' + el.scrollHeight + '>' + el.clientHeight);
                }
              }
            }
            var charts = page.querySelectorAll('svg');
            for (var k = 0; k < charts.length; k++) {
              var sr = charts[k].getBoundingClientRect();
              var labels = charts[k].querySelectorAll('text');
              for (var m = 0; m < labels.length; m++) {
                var tr = labels[m].getBoundingClientRect();
                if (tr.left < sr.left - 0.5 || tr.right > sr.right + 0.5 || tr.top < sr.top - 0.5 || tr.bottom > sr.bottom + 0.5) {
                  svg.push(name(labels[m]));
                }
              }
            }
            out.push({ page: i + 1, bottom: r1(bottom), limit: r1(limit), height: r1(box.height), width: r1(box.width),
                       clipped: clipped, wide: wide, text: text, svg: svg });
          }
          return JSON.stringify(out);
        })()
        """#

    private func measure(_ html: String, pages: Int, label: String) -> [PageMeasure] {
        let meter = WebKitPageMeter()
        defer { meter.tearDown() }
        meter.load(html, pages: pages)
        expectTrue(spin(30) { meter.loaded || meter.failed }, "\(label): WebKit did not load the report within 30 s")
        expectFalse(meter.failed, "\(label): no WebKit rendering available — the report did not load")
        meter.measure(Self.pageScript)
        expectTrue(spin(30) { meter.evaluated }, "\(label): the page measurement gave no answer within 30 s")
        guard let json = meter.measured,
              let measures = try? JSONDecoder().decode([PageMeasure].self, from: Data(json.utf8)) else {
            preconditionFailure("\(label): the page measurement returned nothing readable")
        }
        return measures
    }

    func testWebKitPageOverflow() throws {
        guard skipReason == nil else { return }
        let reports = try WeeklyReportHTMLTests().reportsForPDF()
        expectEqual(reports.count, 12, "both fixtures and the ten synthetic weeks")
        var problems: [String] = []
        var tallest = (bottom: 0.0, place: "")
        var measured = 0
        for report in reports {
            let count = WeeklyReportBuild.pages(in: report.html)
            let measures = measure(report.html, pages: count, label: report.name)
            if measures.count != count { problems.append("\(report.name): \(measures.count) of \(count) pages measured") }
            var line = "  WebKit page fit \(report.name):"
            for page in measures {
                line += " p\(page.page) \(Self.oneDecimal(page.bottom))"
                let place = "\(report.name) p\(page.page)"
                if abs(page.height - Double(WeeklyReportPDFGeometry.pageHeight)) > 0.5
                    || abs(page.width - Double(WeeklyReportPDFGeometry.pageWidth)) > 0.5 {
                    problems.append("\(place): page box \(page.width) × \(page.height) px")
                }
                if page.bottom > page.limit + 0.5 {
                    problems.append("\(place): content ends at \(Self.oneDecimal(page.bottom)) px, "
                                    + "past the \(Self.oneDecimal(page.limit)) px content box")
                }
                for item in page.clipped.prefix(3) { problems.append("\(place) clipped: \(item)") }
                for item in page.wide.prefix(3) { problems.append("\(place) wider than the page: \(item)") }
                for item in page.text.prefix(3) { problems.append("\(place) text overflow: \(item)") }
                for item in page.svg.prefix(3) { problems.append("\(place) chart label outside its chart: \(item)") }
                if page.bottom > tallest.bottom { tallest = (bottom: page.bottom, place: place) }
                measured += 1
            }
            print(line + " (content box \(Self.oneDecimal(measures.first?.limit ?? 0)) px of 1123)")
        }
        print("  WebKit page fit: \(measured) pages of \(reports.count) reports; the tallest content ends at "
              + "\(Self.oneDecimal(tallest.bottom)) px (\(tallest.place)); \(problems.count) problems")
        expectTrue(problems.isEmpty, "WebKit page overflow: " + problems.prefix(12).joined(separator: "; "))
        ran += 1
    }
}

/// A result slot for one completion, read by the run-loop spin.
@MainActor
private final class ResultBox {
    var result: Result<Data, WeeklyReportPDFError>?
}

/// One page's numbers from `pageScript`.
private struct PageMeasure: Decodable {
    let page: Int
    let bottom: Double
    let limit: Double
    let height: Double
    let width: Double
    let clipped: [String]
    let wide: [String]
    let text: [String]
    let svg: [String]
}

/// Test-only web view for the page measurement. Unlike the production maker it allows scripts (only the check's own
/// measurement runs); it uses the same width, data store and navigation rule, and is never in a window.
@MainActor
private final class WebKitPageMeter: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private(set) var loaded = false
    private(set) var failed = false
    private(set) var evaluated = false
    private(set) var measured: String?

    func load(_ html: String, pages: Int) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        let frame = NSRect(x: 0, y: 0, width: WeeklyReportPDFGeometry.pageWidth,
                           height: WeeklyReportPDFGeometry.pageHeight * max(pages, 1))
        let view = WKWebView(frame: frame, configuration: configuration)
        view.navigationDelegate = self
        webView = view
        loaded = false
        failed = false
        view.loadHTMLString(html, baseURL: nil)
    }

    func measure(_ script: String) {
        evaluated = false
        measured = nil
        guard let view = webView else {
            evaluated = true
            return
        }
        view.evaluateJavaScript(script) { [weak self] value, _ in
            self?.measured = value as? String
            self?.evaluated = true
        }
    }

    func tearDown() {
        guard let view = webView else { return }
        webView = nil
        view.stopLoading()
        view.navigationDelegate = nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        let allowed = WeeklyReportPDFGeometry.allowsNavigation(url: navigationAction.request.url?.absoluteString,
                                                               isMainFrame: isMainFrame)
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed = true
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failed = true
    }
}
#endif
