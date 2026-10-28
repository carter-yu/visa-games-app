import AppKit
import Foundation
import VisaCore

/// W5 每週報告 (weekly-report design §9.3–§9.5, §10, §11; ADR 0025): the 表現 row's week list, one PDF make at a
/// time, the Finder reveal and the `stats_marker{weekly_report}` line. Parent mode only: `AppModel` calls in from
/// parent actions and calls `cancel()` on every way out of parent mode, so nothing is revealed after auto-lock.
///
/// Reading the records, building the report and writing the files run on the recorder queue; the PDF is made by
/// `WeeklyReportPDFMaker` (an off-screen web view that is never in a window). No view code lives here, and
/// `ParentReviewView` only draws the `WeeklyReportPanel` value this publishes.
@MainActor
final class WeeklyReportCoordinator {
    /// What the row shows; every change is passed to `onChange` (`AppModel.weeklyPanel`).
    private(set) var panel = WeeklyReportPanel()
    var onChange: ((WeeklyReportPanel) -> Void)?
    /// Asked right before a Finder reveal: true only in parent mode.
    var canReveal: (() -> Bool)?

    private let recorder: PerformanceRecorder
    private let maker = WeeklyReportPDFMaker()
    /// Bumped by every make and by `cancel()`: a callback of an older make changes nothing.
    private var generation = 0
    private var listGeneration = 0
    /// The PDF made in this parent visit, for 「喺 Finder 顯示」.
    private var madeFile: URL?

    init(recorder: PerformanceRecorder) {
        self.recorder = recorder
    }

    /// Reads the weeks again (表現 opened, 更新, 唔計呢段 / 計返).
    func refreshWeeks() {
        listGeneration += 1
        let current = listGeneration
        recorder.weeklyReportWeeks { [weak self] list in
            guard let self, current == self.listGeneration else { return }
            self.update {
                $0.list = list
                $0.loaded = true
            }
        }
    }

    /// 製作 PDF for the week starting on `weekStart`: build (recorder queue) → PDF (WebKit) → files (recorder
    /// queue) → marker → Finder. `AppModel.weeklyMake` has checked parent mode and that no video plays.
    func make(weekStart: String, videoTitles: [String: String]) {
        guard !panel.job.isMaking, panel.list.weeks.contains(where: { $0.weekStart == weekStart }) else { return }
        generation += 1
        let current = generation
        madeFile = nil
        update { $0.job = .making(weekStart: weekStart) }
        VisaGamesLog.append("weekly report — make week=\(weekStart)")
        recorder.weeklyReportBuild(weekStart: weekStart, childName: panel.childName,
                                   videoTitles: videoTitles) { [weak self] build in
            guard let self, current == self.generation else { return }
            guard let build else {
                self.failed(weekStart, reason: "build")
                return
            }
            self.makePDF(build, generation: current)
        }
    }

    /// 喺 Finder 顯示, and the reveal after a make: the existing CSV-export pattern (no save panel).
    func reveal() {
        guard let url = madeFile, canReveal?() == true else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            madeFile = nil
            update { $0.job = .idle }
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Parent mode ended (Return, auto-lock, sleep, test visa), the records are being cleared, or the app quits:
    /// stop the make now (WebKit torn down) and forget this visit's result.
    func cancel() {
        if case .making(let week) = panel.job {
            VisaGamesLog.append("weekly report — cancelled week=\(week)")
        }
        generation += 1
        listGeneration += 1
        maker.cancel()
        madeFile = nil
        update { $0.job = .idle }
    }

    /// After 「清除表現紀錄」: cancel, and read the weeks again on the next 表現 open.
    func reset() {
        cancel()
        update { $0 = WeeklyReportPanel(childName: $0.childName) }
    }

    // MARK: Steps

    private func makePDF(_ build: WeeklyReportBuild, generation current: Int) {
        let started = Date()
        maker.make(html: build.html, pageCount: build.pageCount, metadata: build.metadata) { [weak self] result in
            guard let self, current == self.generation else { return }
            switch result {
            case .failure(let error):
                self.failed(build.window.weekStartStamp, reason: error.rawValue)
            case .success(let pdf):
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                VisaGamesLog.append("weekly report — pdf week=\(build.window.weekStartStamp) "
                                    + "pages=\(build.pageCount) bytes=\(pdf.count) in \(ms) ms")
                self.recorder.weeklyReportWrite(pdf: pdf, build: build) { [weak self] written in
                    self?.written(written, build: build, generation: current)
                }
            }
        }
    }

    private func written(_ result: Result<URL, Error>, build: WeeklyReportBuild, generation current: Int) {
        let week = build.window.weekStartStamp
        guard case .success(let url) = result else {
            if current == generation { failed(week, reason: "write") }
            return
        }
        // The file exists now, so its audit line is written even if parent mode ended during the write.
        recorder.marker(WeeklyReportMarker.what, build.markerFields)
        VisaGamesLog.append("weekly report — made \(build.pdfName) fp=\(build.fingerprint)")
        guard current == generation else { return }
        madeFile = url
        update { $0.job = .made(weekStart: week) }
        reveal()
    }

    private func failed(_ week: String, reason: String) {
        VisaGamesLog.append("weekly report — FAILED week=\(week) reason=\(reason)")
        update { $0.job = .failed(weekStart: week) }
    }

    private func update(_ change: (inout WeeklyReportPanel) -> Void) {
        var next = panel
        change(&next)
        guard next != panel else { return }
        panel = next
        onChange?(next)
    }
}
