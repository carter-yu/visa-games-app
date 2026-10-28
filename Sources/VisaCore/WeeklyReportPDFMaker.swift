#if os(macOS) && canImport(WebKit) && canImport(PDFKit) && canImport(AppKit)
import AppKit
import CoreGraphics
import Foundation
import PDFKit
import WebKit

// Weekly report W5 (weekly-report design §9.2, §9.5; D2): the W4 HTML → an A4 PDF, on the Mac only. This file is
// compiled for macOS alone, so VisaCore stays Foundation-only on Linux and `VisaCoreChecks` can run the real WebKit
// path on the Mac mini (ADR 0025). The pure pieces it uses (geometry, navigation rule, metadata, errors) are in
// `WeeklyReportExport.swift` and run in the Linux checks.

/// Makes the weekly report PDF in an off-screen `WKWebView`.
///
/// - The web view is never added to a window or a view, so nothing can appear over the kiosk and it never takes
///   focus. It lives from `make` to the end of the job only.
/// - Page scripts are off, the website data store is non-persistent, and the navigation policy allows only the
///   main-frame `about:blank` document that `loadHTMLString(_:baseURL: nil)` creates. The W4 HTML holds no URL
///   (`testHTMLSelfContained`), so nothing is fetched.
/// - One `createPDF` per 794 × 1123 px page section. CoreGraphics redraws each page, as vectors with its text, into
///   an A4 media box (595.28 × 841.89 pt) off the main actor; PDFKit checks the pages before the data is returned.
/// - WebKit runs in its own process. A load error, a page error, a crashed web content process, a merge error and
///   the hard timeout all end the job with an error, never a crash. The web view is stopped, its delegate cleared
///   and released in every outcome, cancellation included.
@MainActor
public final class WeeklyReportPDFMaker: NSObject, WKNavigationDelegate {
    public typealias Completion = @MainActor (Result<Data, WeeklyReportPDFError>) -> Void

    private struct Job {
        let token: Int
        let pageCount: Int
        let metadata: WeeklyReportPDFMetadata
        let completion: Completion
        var loaded = false
        var pages: [Data] = []
    }

    /// Seconds from `make` to `.timedOut`.
    public let timeout: TimeInterval
    private var webView: WKWebView?
    private var job: Job?
    private var token = 0
    private var timeoutTask: Task<Void, Never>?

    public init(timeout: TimeInterval = WeeklyReportPDFGeometry.timeoutSeconds) {
        self.timeout = timeout
        super.init()
    }

    public var isMaking: Bool { job != nil }

    /// True between `make` and the end of the job's WebKit part; the checks read it to see the teardown.
    public var hasWebView: Bool { webView != nil }

    /// Starts one make. `completion` runs exactly once, on the main actor: the PDF, or why there is none.
    public func make(html: String, pageCount: Int, metadata: WeeklyReportPDFMetadata,
                     completion: @escaping Completion) {
        guard job == nil else {
            completion(.failure(.busy))
            return
        }
        guard !html.isEmpty, pageCount >= 1, pageCount <= WeeklyReportHTML.pageCount else {
            completion(.failure(.invalidInput))
            return
        }
        token += 1
        let current = token
        job = Job(token: current, pageCount: pageCount, metadata: metadata, completion: completion)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = preferences
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        // As tall as every page, so each page rectangle lies inside the view's bounds.
        let frame = NSRect(x: 0, y: 0, width: WeeklyReportPDFGeometry.pageWidth,
                           height: WeeklyReportPDFGeometry.pageHeight * pageCount)
        let view = WKWebView(frame: frame, configuration: configuration)
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = false
        view.allowsMagnification = false
        webView = view
        startTimeout(current)
        view.loadHTMLString(html, baseURL: nil)
    }

    /// Ends a running make with `.cancelled` and tears WebKit down (parent mode ended, records cleared, app quit).
    public func cancel() {
        guard let active = job else { return }
        finish(active.token, .failure(.cancelled))
    }

    // MARK: WKNavigationDelegate

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        let allowed = webView === self.webView
            && WeeklyReportPDFGeometry.allowsNavigation(url: navigationAction.request.url?.absoluteString,
                                                         isMainFrame: isMainFrame)
        decisionHandler(allowed ? .allow : .cancel)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, var active = job, !active.loaded else { return }
        active.loaded = true
        job = active
        renderPage(0, token: active.token)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        stop(webView, .loadFailed)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: Error) {
        stop(webView, .loadFailed)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        stop(webView, .loadFailed)
    }

    // MARK: Pages, merge, end

    private func renderPage(_ index: Int, token current: Int) {
        guard let view = webView, let active = job, active.token == current else { return }
        let rect = WeeklyReportPDFGeometry.pageRect(index)
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        view.createPDF(configuration: configuration) { [weak self] result in
            self?.pageMade(index, result, token: current)
        }
    }

    private func pageMade(_ index: Int, _ result: Result<Data, Error>, token current: Int) {
        guard var active = job, active.token == current else { return }
        guard case .success(let data) = result, !data.isEmpty else {
            finish(current, .failure(.pageFailed))
            return
        }
        active.pages.append(data)
        job = active
        if active.pages.count < active.pageCount {
            renderPage(index + 1, token: current)
        } else {
            merge(active)
        }
    }

    /// WebKit is done: release it, then redraw the pages into A4 off the main actor.
    private func merge(_ active: Job) {
        let pages = active.pages
        let metadata = active.metadata
        let expected = active.pageCount
        let current = active.token
        tearDownWebView()
        Task { @MainActor [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                WeeklyReportPDFDocument.merge(pages: pages, metadata: metadata, expectedPages: expected)
            }.value
            self?.merged(outcome, token: current)
        }
    }

    private func merged(_ result: Result<Data, WeeklyReportPDFError>, token current: Int) {
        guard let active = job, active.token == current else { return }
        guard case .success(let data) = result else {
            finish(current, result)
            return
        }
        let checked = WeeklyReportPDFDocument.check(data, expectedPages: active.pageCount)
        finish(current, checked ? .success(data) : .failure(.mergeFailed))
    }

    private func startTimeout(_ current: Int) {
        timeoutTask?.cancel()
        let seconds = timeout.isFinite ? min(max(timeout, 0), 3_600) : WeeklyReportPDFGeometry.timeoutSeconds
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.finish(current, .failure(.timedOut))
        }
    }

    private func stop(_ view: WKWebView, _ error: WeeklyReportPDFError) {
        guard view === webView, let active = job else { return }
        finish(active.token, .failure(error))
    }

    /// The only way a job ends: once per token; later WebKit callbacks find no job and do nothing.
    private func finish(_ current: Int, _ result: Result<Data, WeeklyReportPDFError>) {
        guard let active = job, active.token == current else { return }
        job = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        tearDownWebView()
        active.completion(result)
    }

    private func tearDownWebView() {
        guard let view = webView else { return }
        webView = nil
        view.stopLoading()
        view.navigationDelegate = nil
    }
}

/// The A4 redraw (CoreGraphics, no actor) and its PDFKit check.
enum WeeklyReportPDFDocument {
    /// Each WebKit page (794 × 1123 pt) is drawn as vectors, text included, at scale 0.749679 into its own
    /// 595.28 × 841.89 pt page of one new PDF, whose Info dictionary holds the §9.5 title, author and creator.
    static func merge(pages: [Data], metadata: WeeklyReportPDFMetadata,
                      expectedPages: Int) -> Result<Data, WeeklyReportPDFError> {
        guard !pages.isEmpty, pages.count == expectedPages else { return .failure(.mergeFailed) }
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { return .failure(.mergeFailed) }
        var mediaBox = CGRect(x: 0, y: 0, width: WeeklyReportPDFGeometry.a4Width,
                              height: WeeklyReportPDFGeometry.a4Height)
        let info: [String: Any] = [
            kCGPDFContextTitle as String: metadata.title,
            kCGPDFContextAuthor as String: metadata.author,
            kCGPDFContextCreator as String: metadata.creator
        ]
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary) else {
            return .failure(.mergeFailed)
        }
        var complete = true
        for data in pages {
            guard let provider = CGDataProvider(data: data as CFData), let source = CGPDFDocument(provider),
                  source.numberOfPages >= 1, let page = source.page(at: 1) else {
                complete = false
                break
            }
            let box = page.getBoxRect(.mediaBox)
            let fit = WeeklyReportPDFGeometry.fit(width: Double(box.width), height: Double(box.height))
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: CGFloat(fit.dx), y: CGFloat(fit.dy))
            context.scaleBy(x: CGFloat(fit.scale), y: CGFloat(fit.scale))
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        guard complete, output.length > 0 else { return .failure(.mergeFailed) }
        return .success(Data(referencing: output))
    }

    /// PDFKit reads the merged file back: `expectedPages` pages, each with an A4 media box (±0.5 pt).
    @MainActor
    static func check(_ data: Data, expectedPages: Int) -> Bool {
        guard let document = PDFDocument(data: data), document.pageCount == expectedPages else { return false }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { return false }
            let box = page.bounds(for: .mediaBox)
            if abs(Double(box.width) - WeeklyReportPDFGeometry.a4Width) > 0.5
                || abs(Double(box.height) - WeeklyReportPDFGeometry.a4Height) > 0.5 {
                return false
            }
        }
        return true
    }
}
#endif
