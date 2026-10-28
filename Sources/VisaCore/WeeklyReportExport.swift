import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// Weekly report W5 (weekly-report design §9.2–§9.5, §10, §11; D2, D3 A, D7, D11): the pure half of the PDF slice.
// `WeeklyReportBuild` turns the records into one week's W3 text, W4 HTML, W1 model JSON, 數據指紋 and page count;
// `WeeklyReportFiles` names and writes the files under `stats/exports/weekly/`; `WeeklyReportPDFMetadata` and
// `WeeklyReportPDFGeometry` describe the PDF; `WeeklyReportMarker` is the `stats_marker{weekly_report}` payload.
// Foundation only, so every piece runs in the Linux checks. The macOS WebKit / PDFKit glue is
// `WeeklyReportPDFMaker.swift`. ADR 0025 records the choices made where the design left room.

/// Why a PDF could not be made. The parent sees one line for every case (`review.weekly.failed`); the log gets
/// the raw value.
public enum WeeklyReportPDFError: String, Error, Sendable, Equatable {
    /// A make is already running.
    case busy
    /// Empty HTML, or a page count outside 1…6.
    case invalidInput = "invalid_input"
    /// WebKit did not load the HTML: a load error, a refused navigation or a crashed web content process.
    case loadFailed = "load_failed"
    /// `createPDF` failed for a page.
    case pageFailed = "page_failed"
    /// The A4 redraw or its PDFKit check failed.
    case mergeFailed = "merge_failed"
    /// No result within `WeeklyReportPDFGeometry.timeoutSeconds`.
    case timedOut = "timed_out"
    /// Parent mode ended (auto-lock, Return, sleep, test visa), the records were cleared or the app quit.
    case cancelled
}

/// The PDF's page geometry, timeout and navigation rule (design §9.2, §9.5).
public enum WeeklyReportPDFGeometry {
    /// One W4 page section in CSS px (`section.page`): 210 × 297 mm at 96 px per inch.
    public static let pageWidth = 794
    public static let pageHeight = 1123
    /// ISO A4 in PostScript points.
    public static let a4Width = 595.28
    public static let a4Height = 841.89
    /// Hard limit for one make (load, every page and the merge). The design expects 1–3 s.
    public static let timeoutSeconds: Double = 20

    /// Page `index` (0 = page 1) of the laid-out HTML in CSS px. The sections are stacked with no gap
    /// (`body { margin: 0 }`, 1123 px each), and WebKit's PDF rectangles use the same document coordinates.
    public static func pageRect(_ index: Int) -> (x: Double, y: Double, width: Double, height: Double) {
        (x: 0, y: Double(index * pageHeight), width: Double(pageWidth), height: Double(pageHeight))
    }

    /// The uniform scale that fits a `width` × `height` pt page inside A4, and the offsets that centre it.
    /// For a 794 × 1123 pt WebKit page: scale 0.749679 (841.89 / 1123), 595.245 pt wide, 0.017 pt each side.
    public static func fit(width: Double, height: Double) -> (scale: Double, dx: Double, dy: Double) {
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return (scale: 1, dx: 0, dy: 0) }
        let scale = min(a4Width / width, a4Height / height)
        return (scale: scale, dx: (a4Width - width * scale) / 2, dy: (a4Height - height * scale) / 2)
    }

    /// The off-screen web view's whole navigation policy: only the main-frame `about:blank` document that
    /// `loadHTMLString(_:baseURL: nil)` creates. Links, other schemes and frames are cancelled.
    public static func allowsNavigation(url: String?, isMainFrame: Bool) -> Bool {
        isMainFrame && url == "about:blank"
    }
}

/// §9.5 PDF metadata: the report title with the week start, the app as author and creator. Never a user name,
/// a path or a session id.
public struct WeeklyReportPDFMetadata: Sendable, Equatable {
    public static let appName = "VisaGames"

    /// 「VisaGames 每週學習報告 2026-10-19」, the W4 `<title>` of a real report.
    public let title: String
    public let author: String
    public let creator: String

    public init(weekStart: String) {
        title = WeeklyReportLabels.text("doc.title", ["week": WeeklyReportLabels.same(weekStart)]).zh
        author = Self.appName
        creator = Self.appName
    }
}

/// One week's report, ready for the PDF maker: what `WeeklyReportBuild.make` reads off the records.
public struct WeeklyReportBuild: Sendable, Equatable {
    /// The report week, seen up to `dataUntil` (the making time, capped at Sunday 24:00).
    public let window: WeeklyWindow
    /// 「製作於」 in the footer.
    public let generatedAt: Date
    /// The W4 document (no sample watermark).
    public let html: String
    /// Six for a week with countable play, one without (W4).
    public let pageCount: Int
    /// The footer's 8 hex digits of 數據指紋 (§9.6).
    public let fingerprint: String
    /// D11: the W1 canonical model JSON (`WeeklyModel.canonicalJSON()`), kept beside the PDF.
    public let modelJSON: String
    public let metadata: WeeklyReportPDFMetadata

    /// The records the report reads: everything except its own `stats_marker{weekly_report}` lines, so making
    /// (or remaking) a report never changes a W1–W4 number, list, sentence or byte (ADR 0025).
    public static func reportEvents(_ events: [PerfEvent]) -> [PerfEvent] {
        events.filter { !($0.type == .statsMarker && $0.string("what") == WeeklyReportMarker.what) }
    }

    /// The report of the week starting on Monday `weekStart`, from the records as they are at `now`.
    /// Nil for a stamp that is not a Monday, or a week that has not started.
    public static func make(events: [PerfEvent], rollup: PerfRollup, weekStart: String, now: Date,
                            childName: String = WeeklyReportText.defaultChildName,
                            videoTitles: [String: String] = [:],
                            timeZone: TimeZone = WeeklyWindow.hongKong) -> WeeklyReportBuild? {
        guard let window = WeeklyWindow(weekStart: weekStart, dataUntil: now, timeZone: timeZone),
              window.weekStartStamp == weekStart, window.start <= now else { return nil }
        let text = WeeklyReportTextBuilder.build(events: reportEvents(events), rollup: rollup, window: window,
                                                 childName: childName, videoTitles: videoTitles)
        let html = WeeklyReportHTML.render(text, options: WeeklyReportHTMLOptions(generatedAt: now))
        let model = text.analysis.model
        return WeeklyReportBuild(
            window: window,
            generatedAt: now,
            html: html,
            pageCount: pages(in: html),
            fingerprint: String(WeeklyReportHTML.fingerprint(model).prefix(8)),
            modelJSON: model.canonicalJSON(),
            metadata: WeeklyReportPDFMetadata(weekStart: window.weekStartStamp)
        )
    }

    /// Page sections in a W4 document.
    public static func pages(in html: String) -> Int {
        html.components(separatedBy: "<section class=\"page").count - 1
    }

    public var pdfName: String {
        WeeklyReportFiles.pdfName(weekStart: window.weekStartStamp, weekEnd: window.weekEndStamp)
    }

    public var dataName: String {
        WeeklyReportFiles.dataName(weekStart: window.weekStartStamp)
    }

    /// The `stats_marker{weekly_report}` fields written after a successful make.
    public var markerFields: [String: PerfValue] {
        WeeklyReportMarker.fields(self)
    }
}

/// D11 / §9.5: `stats/exports/weekly/VisaGames-weekly-2026-10-19_to_10-25.pdf` and
/// `stats/exports/weekly/data/VisaGames-weekly-2026-10-19.json`. ASCII names that sort by date; remaking a week
/// replaces its files. 「清除表現紀錄」 deletes them with the rest of `stats/` (ADR 0008 §7).
public enum WeeklyReportFiles {
    public static let folderName = "weekly"
    public static let dataFolderName = "data"
    public static let namePrefix = "VisaGames-weekly-"

    public enum WriteError: Error, Sendable, Equatable {
        /// The temporary file could not be renamed over the target.
        case cannotReplace
    }

    /// "VisaGames-weekly-2026-10-19_to_10-25.pdf": the week start as yyyy-MM-dd, the week end as MM-dd.
    public static func pdfName(weekStart: String, weekEnd: String) -> String {
        namePrefix + weekStart + "_to_" + String(weekEnd.suffix(5)) + ".pdf"
    }

    /// "VisaGames-weekly-2026-10-19.json".
    public static func dataName(weekStart: String) -> String {
        namePrefix + weekStart + ".json"
    }

    /// `exports` is `PerfEventStore.exportsDirectory`.
    public static func folder(exports: URL) -> URL {
        exports.appendingPathComponent(folderName, isDirectory: true)
    }

    public static func pdfURL(exports: URL, window: WeeklyWindow) -> URL {
        folder(exports: exports)
            .appendingPathComponent(pdfName(weekStart: window.weekStartStamp, weekEnd: window.weekEndStamp))
    }

    public static func dataURL(exports: URL, window: WeeklyWindow) -> URL {
        folder(exports: exports).appendingPathComponent(dataFolderName, isDirectory: true)
            .appendingPathComponent(dataName(weekStart: window.weekStartStamp))
    }

    /// Atomic replace: the bytes go to a hidden temporary file in the target's own folder, which `rename(2)`
    /// then moves over the target. A reader sees the old file or the new one, never a part. On any error the
    /// temporary file is removed and the old file is left as it was.
    public static func replace(_ url: URL, with data: Data) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent("." + url.lastPathComponent + "." + UUID().uuidString + ".tmp")
        do {
            try data.write(to: temporary)
            guard rename(temporary.path, url.path) == 0 else { throw WriteError.cannotReplace }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// Writes the model JSON, then the PDF (the shared file last), and returns the PDF's location.
    @discardableResult
    public static func write(pdf: Data, build: WeeklyReportBuild, exports: URL) throws -> URL {
        try replace(dataURL(exports: exports, window: build.window), with: Data(build.modelJSON.utf8))
        let url = pdfURL(exports: exports, window: build.window)
        try replace(url, with: pdf)
        return url
    }
}

/// §10.2: the audit line written (parent actor, `PerformanceRecorder.marker`) after every successful make.
/// Four fields besides `what`; no name, path or session id.
public enum WeeklyReportMarker {
    public static let what = "weekly_report"

    public static func fields(_ build: WeeklyReportBuild) -> [String: PerfValue] {
        var fields: [String: PerfValue] = [:]
        fields["week"] = .string(build.window.weekStartStamp)
        fields["data_until"] = .string(PerfCodec.formatTimestamp(build.window.cutoff))
        fields["pages"] = .int(build.pageCount)
        fields["fingerprint"] = .string(build.fingerprint)
        return fields
    }
}
