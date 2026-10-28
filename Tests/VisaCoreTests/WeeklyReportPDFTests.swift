import Foundation
import VisaCore

/// Weekly report W5 (weekly-report design §9.2–§9.5, §10, §11, §12 W5; ADR 0025): the Linux-testable half of the PDF
/// slice — file names and atomic writes, the 表現 row's weeks and Sunday 21:00 line, the PDF metadata and geometry, the
/// `stats_marker{weekly_report}` payload (and that it changes no W1–W4 output), the row's strings and states — plus
/// source guards on the macOS PDF maker, the clear dialog, the version and the app wiring. The real WebKit / PDFKit
/// checks are `WeeklyReportPDFMacTests` (macOS only).
final class WeeklyReportPDFTests {
    private var seq = 0

    private static let fixtureNames = ["weekly-ranking-5.6", "weekly-2026-10-19"]
    /// Monday 2026-10-19, 00:00 HKT.
    private static let monday = PerfCodec.parseTimestamp("2026-10-18T16:00:00.000Z")!
    /// Sunday 2026-10-25, 21:00 HKT: when the fixtures were made.
    private static let madeAt = PerfCodec.parseTimestamp("2026-10-25T13:00:00.000Z")!
    /// Wednesday 2026-10-21, 18:00 HKT (10:00 UTC).
    private static let wednesday = PerfCodec.parseTimestamp("2026-10-21T10:00:00.000Z")!

    /// §6.3 banned phrases and English whole words (as in `WeeklyTextTests` and `WeeklyReportHTMLTests`).
    private static let bannedPhrases = ["最差", "好差", "差勁", "做得差", "太慢", "好慢", "蠢", "懶", "失敗", "唔叻", "輸咗", "弱"]
    private static let bannedWords: Set<String> = ["worst", "bad", "fail", "failure", "poor", "slow", "lazy", "weak",
                                                   "behind"]

    // MARK: Records

    private static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        monday.addingTimeInterval(Double(((day * 24 + hour) * 60 + minute) * 60))
    }

    private func ev(_ type: PerfEventType, _ fields: [String: PerfValue], at date: Date, actor: PerfActor = .child,
                    session: String = "s1") -> PerfEvent {
        seq += 1
        return PerfEvent(type: type, timestamp: date, tz: "+08:00", mono: Double(seq), launch: "L1", seq: seq,
                         app: "0.35.0", actor: actor, mode: actor == .child ? "lock" : "parent", session: session,
                         fields: fields)
    }

    /// A 邊個影子 round dealt at `date`, solved right first time 30 s later.
    private func round(at date: Date, actor: PerfActor = .child, session: String = "s1") -> [PerfEvent] {
        seq += 1
        let id = "w5-\(seq)"
        let dealt: [String: PerfValue] = ["round": .string(id), "kind": .string("shadowMatch"), "stars": .int(1)]
        let result: [String: PerfValue] = [
            "round": .string(id), "kind": .string("shadowMatch"), "outcome": .string("solved"), "answers": .int(1),
            "first_try": .bool(true), "misses": .int(0), "hint_used": .bool(false), "assisted": .bool(false),
            "total_ms": .int(30_000), "active_ms": .int(4_000), "earned_min": .int(5)
        ]
        return [ev(.gameDealt, dealt, at: date, actor: actor, session: session),
                ev(.roundResult, result, at: date.addingTimeInterval(30), actor: actor, session: session)]
    }

    /// A picker play of `v1`, watched for 5 minutes.
    private func play(at date: Date) -> [PerfEvent] {
        seq += 1
        let id = "w5p\(seq)"
        let start: [String: PerfValue] = ["play": .string(id), "video": .string("v1"), "source": .string("picker")]
        let end: [String: PerfValue] = ["play": .string(id), "video": .string("v1"), "watched_s": .double(300)]
        return [ev(.videoStart, start, at: date), ev(.videoEnd, end, at: date.addingTimeInterval(300))]
    }

    /// `stats_marker{weekly_report}` as the recorder writes it.
    private func reportMarker(at date: Date) -> PerfEvent {
        ev(.statsMarker, Self.markerFields(week: "2026-10-12"), at: date, actor: .parent, session: "p")
    }

    private static func markerFields(week: String) -> [String: PerfValue] {
        ["what": .string(WeeklyReportMarker.what), "week": .string(week),
         "data_until": .string("2026-10-19T00:00:00.000Z"), "pages": .int(6), "fingerprint": .string("0123abcd")]
    }

    // MARK: Fixtures and scanners

    private struct Fixture {
        let events: [PerfEvent]
        let rollup: PerfRollup
        let titles: [String: String]
        let metrics: String
        let analysis: String
        let text: String
        let html: String
    }

    /// The fixtures sit beside this file; `#filePath` finds them from any working directory.
    private static func fixtureFolder(_ name: String) -> URL {
        let beside = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true).appendingPathComponent(name, isDirectory: true)
        if FileManager.default.fileExists(atPath: beside.path) { return beside }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/VisaCoreTests/Fixtures/\(name)", isDirectory: true)
    }

    private static func repoRoot() -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) { return root }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(path), encoding: .utf8)
    }

    /// A fixture week's records and its W1–W4 goldens (made on Sunday 2026-10-25 at 21:00 HKT).
    private static func fixture(_ name: String) throws -> Fixture {
        let folder = fixtureFolder(name)
        let store = PerfEventStore(directory: folder)
        let read = store.read()
        guard !read.events.isEmpty else { preconditionFailure("weekly fixture \(name) not found at \(folder.path)") }
        let titleData = try Data(contentsOf: folder.appendingPathComponent("video-titles.json"))
        let titles = try JSONDecoder().decode([String: String].self, from: titleData)
        func golden(_ file: String) throws -> String {
            try String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
        }
        return Fixture(events: read.events, rollup: store.loadRollup(), titles: titles,
                       metrics: try golden("expected-metrics.json"), analysis: try golden("expected-analysis.json"),
                       text: try golden("expected-text.json"), html: try golden("expected-report.html"))
    }

    /// Body of the first `header` up to its matching closing brace.
    private static func body(of header: String, in text: String) -> String {
        guard let start = text.range(of: header),
              let open = text.range(of: "{", range: start.upperBound..<text.endIndex) else { return "" }
        var depth = 0
        var index = open.lowerBound
        while index < text.endIndex {
            let character = text[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 { return String(text[open.upperBound..<index]) }
            }
            index = text.index(after: index)
        }
        return ""
    }

    private static func startsWith(_ body: String, _ prefix: String) -> Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(prefix)
    }

    private static func bannedHits(_ text: String) -> [String] {
        var hits = bannedPhrases.filter { text.contains($0) }
        var word = ""
        for scalar in (text + " ").unicodeScalars {
            let letter = (scalar.value >= 65 && scalar.value <= 90) || (scalar.value >= 97 && scalar.value <= 122)
            if letter {
                word.unicodeScalars.append(scalar)
            } else {
                if bannedWords.contains(word.lowercased()) { hits.append(word) }
                word = ""
            }
        }
        return hits
    }

    /// `Fixtures/traditional-check/simplified-only.txt`: one character per entry, `#` lines are comments.
    private static func simplifiedOnly() throws -> Set<Character> {
        let url = fixtureFolder("traditional-check").appendingPathComponent("simplified-only.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        var characters: Set<Character> = []
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            for character in line where !character.isWhitespace { characters.insert(character) }
        }
        return characters
    }

    // MARK: §9.5 file names (D11)

    func testWeeklyFileNamesAndPaths() {
        expectEqual(WeeklyReportFiles.pdfName(weekStart: "2026-10-19", weekEnd: "2026-10-25"),
                    "VisaGames-weekly-2026-10-19_to_10-25.pdf")
        expectEqual(WeeklyReportFiles.dataName(weekStart: "2026-10-19"), "VisaGames-weekly-2026-10-19.json")
        // Any day picks its Monday-to-Sunday week (WeeklyWindow); the end may fall in the next month or year.
        let cases: [(day: String, name: String)] = [
            ("2026-10-21", "VisaGames-weekly-2026-10-19_to_10-25.pdf"),
            ("2026-10-25", "VisaGames-weekly-2026-10-19_to_10-25.pdf"),
            ("2026-10-01", "VisaGames-weekly-2026-09-28_to_10-04.pdf"),
            ("2026-12-31", "VisaGames-weekly-2026-12-28_to_01-03.pdf"),
            ("2027-01-03", "VisaGames-weekly-2026-12-28_to_01-03.pdf"),
            ("2024-02-29", "VisaGames-weekly-2024-02-26_to_03-03.pdf")
        ]
        let exports = URL(fileURLWithPath: "/tmp/visagames-w5/stats/exports", isDirectory: true)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        for item in cases {
            guard let window = WeeklyWindow(weekStart: item.day) else {
                expectTrue(false, "\(item.day) did not parse")
                continue
            }
            let name = WeeklyReportFiles.pdfName(weekStart: window.weekStartStamp, weekEnd: window.weekEndStamp)
            expectEqual(name, item.name, item.day)
            expectTrue(name.unicodeScalars.allSatisfy { allowed.contains($0) }, "ASCII file name \(name)")
            expectEqual(WeeklyReportFiles.pdfURL(exports: exports, window: window).path,
                        "/tmp/visagames-w5/stats/exports/weekly/" + item.name)
            expectEqual(WeeklyReportFiles.dataURL(exports: exports, window: window).path,
                        "/tmp/visagames-w5/stats/exports/weekly/data/VisaGames-weekly-" + window.weekStartStamp + ".json")
        }
        // Hong Kong days, not UTC: Monday 00:30 HKT is still Sunday in UTC.
        let next = WeeklyWindow(containing: PerfCodec.parseTimestamp("2026-10-25T16:30:00.000Z")!)
        expectEqual(WeeklyReportFiles.pdfName(weekStart: next.weekStartStamp, weekEnd: next.weekEndStamp),
                    "VisaGames-weekly-2026-10-26_to_11-01.pdf")
        let same = WeeklyWindow(containing: PerfCodec.parseTimestamp("2026-10-25T15:59:59.000Z")!)
        expectEqual(same.weekStartStamp, "2026-10-19")
        // The names sort by week.
        let shuffled = ["2026-12-28", "2024-02-26", "2026-09-28", "2026-10-19"].compactMap { stamp -> String? in
            guard let window = WeeklyWindow(weekStart: stamp) else { return nil }
            return WeeklyReportFiles.pdfName(weekStart: window.weekStartStamp, weekEnd: window.weekEndStamp)
        }
        expectEqual(shuffled.sorted(), ["VisaGames-weekly-2024-02-26_to_03-03.pdf", "VisaGames-weekly-2026-09-28_to_10-04.pdf",
                                        "VisaGames-weekly-2026-10-19_to_10-25.pdf", "VisaGames-weekly-2026-12-28_to_01-03.pdf"])
        print("  weekly report pdf: \(cases.count + 2) week file names (month and year ends, HKT days, ASCII)")
    }

    // MARK: Atomic replace; 清除表現紀錄 deletes, 清除簽證及重設儲存 keeps (ADR 0008 §7)

    func testWeeklyFilesReplaceAtomicallyAndClearWithRecords() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("visagames-w5-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let store = PerfEventStore(directory: root.appendingPathComponent("stats", isDirectory: true))
        let snapshots = SnapshotStore(url: root.appendingPathComponent("state.json"))
        try snapshots.save(Snapshot(configured: true))
        seq = 0
        try store.append(round(at: Self.at(0, 10)) + round(at: Self.at(1, 10)))
        guard let build = WeeklyReportBuild.make(events: store.read().events, rollup: store.loadRollup(),
                                                 weekStart: "2026-10-19", now: Self.wednesday) else {
            expectTrue(false, "the week did not build")
            return
        }
        let folder = WeeklyReportFiles.folder(exports: store.exportsDirectory)
        expectTrue(folder.path.hasPrefix(store.directory.path + "/"), "the weekly folder is inside stats/")
        let pdfName = "VisaGames-weekly-2026-10-19_to_10-25.pdf"
        let url = try WeeklyReportFiles.write(pdf: Data("first".utf8), build: build, exports: store.exportsDirectory)
        expectEqual(url, WeeklyReportFiles.pdfURL(exports: store.exportsDirectory, window: build.window))
        expectEqual(url.lastPathComponent, pdfName)
        expectEqual(try Data(contentsOf: url), Data("first".utf8))
        let dataURL = WeeklyReportFiles.dataURL(exports: store.exportsDirectory, window: build.window)
        expectEqual(try String(contentsOf: dataURL, encoding: .utf8), build.modelJSON)
        // Remaking the week replaces both files; no temporary file is left.
        try WeeklyReportFiles.write(pdf: Data("second".utf8), build: build, exports: store.exportsDirectory)
        expectEqual(try Data(contentsOf: url), Data("second".utf8))
        expectEqual(try fm.contentsOfDirectory(atPath: folder.path).sorted(), [pdfName, "data"])
        expectEqual(try fm.contentsOfDirectory(atPath: dataURL.deletingLastPathComponent().path),
                    ["VisaGames-weekly-2026-10-19.json"])
        // A replace that cannot rename (the target is a folder) throws, keeps the target, leaves no temporary file.
        let blocked = folder.appendingPathComponent("blocked.pdf", isDirectory: true)
        try fm.createDirectory(at: blocked, withIntermediateDirectories: true)
        expectThrowsError(try WeeklyReportFiles.replace(blocked, with: Data("x".utf8)))
        var isFolder: ObjCBool = false
        expectTrue(fm.fileExists(atPath: blocked.path, isDirectory: &isFolder) && isFolder.boolValue)
        expectEqual(try fm.contentsOfDirectory(atPath: folder.path).sorted(), ["blocked.pdf", pdfName, "data"].sorted())
        // 清除簽證及重設儲存 writes a fresh state.json only: the weekly files stay.
        try snapshots.save(Snapshot(configured: true))
        expectTrue(fm.fileExists(atPath: url.path))
        // 清除表現紀錄 empties stats/, the weekly folder with it; state.json is untouched.
        try store.clear()
        expectFalse(fm.fileExists(atPath: folder.path))
        expectFalse(fm.fileExists(atPath: dataURL.path))
        expectEqual(try snapshots.load(), Snapshot(configured: true))
        print("  weekly report pdf: atomic replace (remake, failed rename), cleared with stats/, kept by the visa reset")
    }

    // MARK: §9.3 / §9.4 week list

    func testWeeklyWeekListOffersThisWeekAndPlayedWeeks() {
        seq = 0
        var events: [PerfEvent] = []
        events += round(at: Self.at(1, 10))                                            // 10-19: this week
        events += round(at: Self.at(-4, 10))                                           // 10-12: played
        events += round(at: Self.at(-13, 10), actor: .parentPlaytest, session: "pt")   // 10-05: playtest only…
        events.append(reportMarker(at: Self.at(-13, 21)))                              // …and a weekly_report line
        events += play(at: Self.at(-20, 18))                                           // 09-28: videos only
        events += round(at: Self.at(-26, 10), session: "sx")                           // 09-21: 唔計呢段
        events.append(ev(.statsExclude, ["target_session": .string("sx")], at: Self.at(-26, 12), actor: .parent,
                         session: "p"))
        for week in 5...10 { events += round(at: Self.at(-7 * week + 2, 10)) }        // 09-14 … 08-10: played
        let list = WeeklyReportSchedule.weeks(events: events, now: Self.wednesday)
        expectEqual(list.map(\.weekStart), ["2026-10-19", "2026-10-12", "2026-09-28", "2026-09-14", "2026-09-07",
                                            "2026-08-31", "2026-08-24", "2026-08-17"])
        expectEqual(list.count, WeeklyReportSchedule.maximumWeeks)
        expectEqual(WeeklyReportSchedule.maximumWeeks, 8)
        expectTrue(list[0].isCurrent && list[0].isDraft && !list[0].isComplete)
        for week in list.dropFirst() {
            expectTrue(week.isComplete && !week.isDraft && !week.isCurrent, week.weekStart)
        }
        expectEqual(list[0].id, "2026-10-19")
        expectEqual(list[0].weekEnd, "2026-10-25")
        expectEqual(list[0].label, WeeklyWords("10月19日至10月25日", "Oct 19 – Oct 25"))
        expectEqual(list[2].label, WeeklyWords("9月28日至10月4日", "Sep 28 – Oct 4"))
        // Fewer rows when asked; the same weeks in any record order.
        expectEqual(WeeklyReportSchedule.weeks(events: events, now: Self.wednesday, maximum: 3).map(\.weekStart),
                    ["2026-10-19", "2026-10-12", "2026-09-28"])
        expectEqual(WeeklyReportSchedule.weeks(events: Array(events.reversed()), now: Self.wednesday), list)
        // No records: this week only (its report is the one-page 「今個星期未有紀錄」).
        expectEqual(WeeklyReportSchedule.weeks(events: [], now: Self.wednesday).map(\.weekStart), ["2026-10-19"])
        // Monday 00:00 HKT starts a new week and completes the last one; Sunday 23:59:59 is still this week.
        let nextMonday = Self.at(7, 0)
        let after = WeeklyReportSchedule.weeks(events: events, now: nextMonday)
        expectEqual(after.map(\.weekStart), ["2026-10-26", "2026-10-19", "2026-10-12", "2026-09-28", "2026-09-14",
                                             "2026-09-07", "2026-08-31", "2026-08-24"])
        expectTrue(after[0].isCurrent && after[0].isDraft)
        expectTrue(after[1].isComplete && !after[1].isCurrent)
        let before = WeeklyReportSchedule.weeks(events: events, now: nextMonday.addingTimeInterval(-1))
        expectEqual(before.first?.weekStart, "2026-10-19")
        expectTrue(before.first?.isDraft == true)
        print("  weekly report pdf: week list — this week, \(list.count - 1) earlier weeks with play (cap \(WeeklyReportSchedule.maximumWeeks)), "
              + "playtest-only, 唔計呢段 and marker-only weeks left out")
    }

    // MARK: §9.3 ready line (D1)

    func testWeeklyReadyLineFromSunday2100() {
        guard let window = WeeklyWindow(weekStart: "2026-10-19") else {
            expectTrue(false, "week stamp did not parse")
            return
        }
        expectEqual(PerfCodec.formatTimestamp(WeeklyReportSchedule.readyTime(of: window)), "2026-10-25T13:00:00.000Z")
        expectEqual(WeeklyReportSchedule.readyHour, 21)
        let line = "今個星期嘅報告可以製作喇 / This week's report is ready to make"
        let cases: [(iso: String, ready: Bool)] = [
            ("2026-10-25T12:59:59.000Z", false),  // Sunday 20:59:59 HKT
            ("2026-10-25T13:00:00.000Z", true),   // Sunday 21:00:00
            ("2026-10-25T15:59:59.999Z", true),   // Sunday 23:59:59.999
            ("2026-10-25T16:00:00.000Z", false),  // Monday 00:00: last week is complete, no line
            ("2026-10-24T13:00:00.000Z", false),  // Saturday 21:00
            ("2026-10-19T13:00:00.000Z", false)   // Monday 21:00
        ]
        for item in cases {
            guard let now = PerfCodec.parseTimestamp(item.iso) else {
                expectTrue(false, item.iso)
                continue
            }
            expectEqual(WeeklyReportSchedule.isReady(now: now), item.ready, item.iso)
            let list = WeeklyReportSchedule.list(events: [], now: now)
            expectEqual(list.ready, item.ready, item.iso)
            expectEqual(WeeklyReportPanel(list: list, loaded: true).banner, item.ready ? line : nil, item.iso)
        }
        // Hong Kong time, never the host zone: at Sunday 21:00 HKT it is Sunday 13:00 in UTC.
        expectFalse(WeeklyReportSchedule.isReady(now: Self.madeAt, timeZone: TimeZone(identifier: "UTC")!))
        // Not read yet: no line.
        expectNil(WeeklyReportPanel(list: WeeklyReportWeekList(weeks: [], ready: true), loaded: false).banner)
        print("  weekly report pdf: ready line from Sunday 21:00:00 HKT to the end of Sunday (\(cases.count) moments)")
    }

    // MARK: §9.5 metadata, the A4 geometry and the navigation rule

    func testWeeklyPDFMetadataGeometryAndPolicy() {
        let metadata = WeeklyReportPDFMetadata(weekStart: "2026-10-19")
        expectEqual(metadata.title, "VisaGames 每週學習報告 2026-10-19")
        expectEqual(metadata.author, "VisaGames")
        expectEqual(metadata.creator, "VisaGames")
        for value in [metadata.title, metadata.author, metadata.creator] {
            for needle in ["/", "Users", "Cedric", "session", ".pdf", "@"] {
                expectFalse(value.contains(needle), "\(value) holds \(needle)")
            }
        }
        // The title is the report's own <title> (a real report: no sample suffix).
        seq = 0
        let build = WeeklyReportBuild.make(events: round(at: Self.at(0, 10)), rollup: PerfRollup(),
                                           weekStart: "2026-10-19", now: Self.wednesday)
        expectTrue(build?.html.contains("<title>VisaGames 每週學習報告 2026-10-19</title>") == true)
        expectEqual(build?.metadata, metadata)

        // 794 × 1123 px sections stacked with no gap; A4 in points; one uniform scale, centred.
        expectEqual(WeeklyReportPDFGeometry.pageWidth, 794)
        expectEqual(WeeklyReportPDFGeometry.pageHeight, 1123)
        expectEqual(WeeklyReportPDFGeometry.a4Width, 595.28, accuracy: 1e-9)
        expectEqual(WeeklyReportPDFGeometry.a4Height, 841.89, accuracy: 1e-9)
        expectEqual(WeeklyReportPDFGeometry.timeoutSeconds, 20, accuracy: 0)
        let first = WeeklyReportPDFGeometry.pageRect(0)
        expectTrue(first.x == 0 && first.y == 0 && first.width == 794 && first.height == 1123)
        expectEqual(WeeklyReportPDFGeometry.pageRect(5).y, 5_615, accuracy: 0)
        let fit = WeeklyReportPDFGeometry.fit(width: 794, height: 1123)
        expectEqual(fit.scale, 0.7496794, accuracy: 1e-6)
        expectEqual(1123 * fit.scale, 841.89, accuracy: 1e-9)
        expectEqual(794 * fit.scale + 2 * fit.dx, 595.28, accuracy: 1e-9)
        expectEqual(fit.dx, 0.0172663, accuracy: 1e-6)
        expectEqual(fit.dy, 0, accuracy: 1e-9)
        let a4 = WeeklyReportPDFGeometry.fit(width: 595.28, height: 841.89)
        expectEqual(a4.scale, 1, accuracy: 1e-12)
        expectEqual(a4.dx, 0, accuracy: 1e-9)
        expectEqual(a4.dy, 0, accuracy: 1e-9)
        let wide = WeeklyReportPDFGeometry.fit(width: 1123, height: 794)
        expectEqual(1123 * wide.scale, 595.28, accuracy: 1e-9)
        expectEqual(794 * wide.scale + 2 * wide.dy, 841.89, accuracy: 1e-9)
        let none = WeeklyReportPDFGeometry.fit(width: 0, height: 1123)
        expectTrue(none.scale == 1 && none.dx == 0 && none.dy == 0)

        // Navigation: only the main-frame about:blank document of loadHTMLString(_:baseURL: nil).
        expectTrue(WeeklyReportPDFGeometry.allowsNavigation(url: "about:blank", isMainFrame: true))
        expectFalse(WeeklyReportPDFGeometry.allowsNavigation(url: "about:blank", isMainFrame: false))
        let refused: [String?] = [nil, "about:blank#top", "about:srcdoc", "https://www.youtube.com/", "http://example.com/",
                                  "file:///Users/parent/report.html", "data:text/html,x", "javascript:void(0)"]
        for url in refused {
            expectFalse(WeeklyReportPDFGeometry.allowsNavigation(url: url, isMainFrame: true), url ?? "nil")
        }
        print("  weekly report pdf: metadata (title, author, creator), A4 fit scale 0.749679, navigation about:blank only")
    }

    // MARK: §10.2 stats_marker{weekly_report}

    func testWeeklyMarkerPayload() throws {
        seq = 0
        let events = round(at: Self.at(0, 10)) + round(at: Self.at(1, 10)) + round(at: Self.at(-6, 10))
        guard let current = WeeklyReportBuild.make(events: events, rollup: PerfRollup(), weekStart: "2026-10-19",
                                                   now: Self.wednesday),
              let last = WeeklyReportBuild.make(events: events, rollup: PerfRollup(), weekStart: "2026-10-12",
                                                now: Self.wednesday) else {
            expectTrue(false, "the weeks did not build")
            return
        }
        expectEqual(WeeklyReportMarker.what, "weekly_report")
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdef")
        for (build, until) in [(current, "2026-10-21T10:00:00.000Z"), (last, "2026-10-18T16:00:00.000Z")] {
            let fields = build.markerFields
            // Week start, dataUntil, pages and 8 hex of 數據指紋: nothing else.
            expectEqual(fields.keys.sorted(), ["data_until", "fingerprint", "pages", "week"])
            expectEqual(fields["week"]?.stringValue, build.window.weekStartStamp)
            expectEqual(fields["data_until"]?.stringValue, until)
            expectEqual(fields["pages"]?.intValue, 6)
            let hex = fields["fingerprint"]?.stringValue ?? ""
            expectEqual(hex.count, 8)
            expectTrue(hex.unicodeScalars.allSatisfy { hexDigits.contains($0) }, hex)
            let model = WeeklyMetricsBuilder.build(events: events, rollup: PerfRollup(), window: build.window)
            expectEqual(hex, String(WeeklyReportHTML.fingerprint(model).prefix(8)))
            expectTrue(build.html.contains("數據指紋 " + hex), "the footer prints the same fingerprint")
            // The line as the recorder writes it (`marker(what, fields)`): it round-trips and holds no name or path.
            var line = fields
            line["what"] = .string(WeeklyReportMarker.what)
            let event = PerfEvent(type: .statsMarker, timestamp: Self.wednesday, tz: "+08:00", mono: 1, launch: "L1",
                                  seq: 99, app: "0.35.0", actor: .parent, mode: "parent", session: "p", fields: line)
            let text = try PerfCodec.encodeLine(event)
            guard case .event(let decoded) = PerfCodec.decodeLine(Substring(text)) else {
                expectTrue(false, "marker line did not decode: \(text)")
                continue
            }
            expectEqual(decoded.type, .statsMarker)
            expectEqual(decoded.string("what"), "weekly_report")
            expectEqual(decoded.fields.count, 5)
            for needle in ["Cedric", ".pdf", ".json", "/", "exports", "weekly-"] {
                expectFalse(text.contains(needle), "marker line holds \(needle): \(text)")
            }
        }
        // The report reads every record except its own markers (cleared / variants_v1 / reset_storage stay).
        let others = ["cleared", "variants_v1", "reset_storage"].map {
            ev(.statsMarker, ["what": .string($0)], at: Self.at(2, 9), actor: .parent, session: "p")
        }
        let mixed = events + others + [reportMarker(at: Self.at(2, 9)), reportMarker(at: Self.at(-1, 21))]
        let kept = WeeklyReportBuild.reportEvents(mixed)
        expectEqual(kept, events + others)
        expectEqual(kept.count, mixed.count - 2)
        print("  weekly report pdf: marker payload week / data_until / pages / fingerprint, round-trips, no name or path")
    }

    // MARK: §10.2 / ADR 0025: the marker changes no W1–W4 output

    /// Markers as the running app writes them: parent actor, the launch and version of the latest record at or before
    /// the moment, on a day that already has records — last week's report made on Monday 21:00 and this week's on
    /// Sunday 20:00, both inside the report window.
    private static func appMarkers(_ events: [PerfEvent]) -> [PerfEvent] {
        let ordered = PerfCodec.ordered(events)
        let zone = WeeklyWindow.hongKong
        var out: [PerfEvent] = []
        for (offset, iso) in ["2026-10-19T13:00:00.000Z", "2026-10-25T12:00:00.000Z"].enumerated() {
            guard let when = PerfCodec.parseTimestamp(iso), let last = ordered.last(where: { $0.timestamp <= when }),
                  PerfClock.dayStamp(last.timestamp, timeZone: zone) == PerfClock.dayStamp(when, timeZone: zone) else {
                continue
            }
            let seq = (ordered.filter { $0.launch == last.launch }.map(\.seq).max() ?? 0) + 1 + offset
            out.append(PerfEvent(type: .statsMarker, timestamp: when, tz: "+08:00", mono: last.mono + 60,
                                 launch: last.launch, seq: seq, app: last.app, actor: .parent, mode: "parent",
                                 session: "w5-parent",
                                 fields: markerFields(week: offset == 0 ? "2026-10-12" : "2026-10-19")))
        }
        return out
    }

    /// Markers anywhere: an unseen launch and app version, long before the first record, in an otherwise empty
    /// trend week, last week, this week and after the cut-off.
    private static func strayMarkers() -> [PerfEvent] {
        let moments = ["2026-01-05T02:00:00.000Z", "2026-09-16T04:00:00.000Z", "2026-10-14T04:00:00.000Z",
                       "2026-10-21T04:00:00.000Z", "2026-10-25T14:00:00.000Z"]
        var out: [PerfEvent] = []
        for (offset, iso) in moments.enumerated() {
            guard let when = PerfCodec.parseTimestamp(iso) else { continue }
            out.append(PerfEvent(type: .statsMarker, timestamp: when, tz: "+08:00", mono: Double(offset),
                                 launch: "L-w5-\(offset)", seq: 1, app: "9.9.9", actor: .parent, mode: "parent",
                                 session: "w5-parent", fields: markerFields(week: "2026-10-19")))
        }
        return out
    }

    private static func expectGoldens(_ label: String, _ events: [PerfEvent], _ fixture: Fixture, window: WeeklyWindow,
                                      options: WeeklyReportHTMLOptions) {
        let model = WeeklyMetricsBuilder.build(events: events, rollup: fixture.rollup, window: window)
        expectTrue(model.canonicalJSON() == fixture.metrics, "\(label): the W1 model JSON changed")
        let analysis = WeeklyAnalysisBuilder.build(events: events, rollup: fixture.rollup, window: window)
        expectTrue(analysis.canonicalJSON() == fixture.analysis, "\(label): the W2 analysis JSON changed")
        let text = WeeklyReportTextBuilder.build(events: events, rollup: fixture.rollup, window: window,
                                                 videoTitles: fixture.titles)
        expectTrue(text.canonicalJSON() == fixture.text, "\(label): the W3 text JSON changed")
        expectTrue(WeeklyReportHTML.render(text, options: options) == fixture.html, "\(label): the W4 HTML changed")
    }

    func testWeeklyMarkerLeavesW1ToW4Unchanged() throws {
        for name in Self.fixtureNames {
            let fixture = try Self.fixture(name)
            guard let window = WeeklyWindow(weekStart: "2026-10-19", dataUntil: Self.madeAt) else {
                expectTrue(false, "week stamp did not parse")
                continue
            }
            let options = WeeklyReportHTMLOptions(generatedAt: Self.madeAt, sampleWatermark: name == "weekly-ranking-5.6")
            // As the app writes them, W1–W4 read past them: the goldens hold byte for byte, without any filter.
            let app = Self.appMarkers(fixture.events)
            expectEqual(app.count, 2, name)
            Self.expectGoldens(name + " with app markers", fixture.events + app, fixture, window: window, options: options)
            // Anywhere else, the report path drops them first (`WeeklyReportBuild.reportEvents`), so the bytes hold too.
            let stray = fixture.events + Self.strayMarkers()
            let kept = WeeklyReportBuild.reportEvents(stray)
            expectEqual(kept, fixture.events, name)
            Self.expectGoldens(name + " with stray markers", kept, fixture, window: window, options: options)
            // Unfiltered, the stray ones would show (app 9.9.9 on page 5, a September trend week): the filter is
            // what keeps the report the same.
            let raw = WeeklyAnalysisBuilder.build(events: stray, rollup: fixture.rollup, window: window)
            expectFalse(raw.canonicalJSON() == fixture.analysis, "\(name): stray markers should show without the filter")
            // The production build path: the W1 golden as the D11 JSON, the footer's 數據指紋, and for the W1 fixture
            // (no sample watermark) the W4 golden itself.
            guard let build = WeeklyReportBuild.make(events: stray + app, rollup: fixture.rollup, weekStart: "2026-10-19",
                                                     now: Self.madeAt, videoTitles: fixture.titles) else {
                expectTrue(false, "\(name) did not build")
                continue
            }
            expectTrue(build.modelJSON == fixture.metrics, "\(name): the D11 model JSON is the W1 golden")
            expectEqual(build.pageCount, 6, name)
            expectTrue(fixture.html.contains("數據指紋 " + build.fingerprint), "\(name): fingerprint")
            if name == "weekly-2026-10-19" {
                expectTrue(build.html == fixture.html, "\(name): the build's HTML is the W4 golden")
            }
            print("  weekly report pdf: \(name) W1–W4 goldens unchanged with \(app.count) app markers "
                  + "and \(stray.count - fixture.events.count) stray markers")
        }
    }

    // MARK: The build (events → W3 text → W4 HTML, page count, cut-off, D11 JSON)

    func testWeeklyBuildPagesCutoffAndModelJSON() {
        seq = 0
        let events = round(at: Self.at(1, 10)) + round(at: Self.at(1, 11))
            + round(at: Self.at(-5, 10), actor: .parentPlaytest, session: "pt")
        guard let draft = WeeklyReportBuild.make(events: events, rollup: PerfRollup(), weekStart: "2026-10-19",
                                                 now: Self.wednesday),
              let quiet = WeeklyReportBuild.make(events: events, rollup: PerfRollup(), weekStart: "2026-10-12",
                                                 now: Self.wednesday) else {
            expectTrue(false, "the weeks did not build")
            return
        }
        // This week, still running: data up to the making time; six pages.
        expectEqual(draft.window.cutoff, Self.wednesday)
        expectEqual(draft.generatedAt, Self.wednesday)
        expectEqual(draft.pageCount, 6)
        expectEqual(WeeklyReportBuild.pages(in: draft.html), 6)
        expectTrue(draft.html.contains("資料截至 2026-10-21 18:00 HKT · 製作於 2026-10-21 18:00 HKT"))
        expectFalse(draft.html.contains("示例數據"), "real reports have no sample watermark")
        expectEqual(draft.pdfName, "VisaGames-weekly-2026-10-19_to_10-25.pdf")
        expectEqual(draft.dataName, "VisaGames-weekly-2026-10-19.json")
        expectTrue(draft.modelJSON
                   == WeeklyMetricsBuilder.build(events: events, rollup: PerfRollup(), window: draft.window).canonicalJSON())
        // Last week, over: the whole week; only parent playtest rounds, so one page.
        expectEqual(quiet.window.cutoff, quiet.window.end)
        expectEqual(quiet.pageCount, 1)
        expectTrue(quiet.html.contains("今個星期未有紀錄。"))
        expectTrue(quiet.html.contains("第 1 頁，共 1 頁"))
        // The same inputs give the same build.
        expectEqual(WeeklyReportBuild.make(events: events, rollup: PerfRollup(), weekStart: "2026-10-19",
                                           now: Self.wednesday), draft)
        // Not a Monday, not started, not a date: nothing to make.
        for stamp in ["2026-10-21", "2026-10-26", "2026-13-01", "garbage", ""] {
            expectNil(WeeklyReportBuild.make(events: events, rollup: PerfRollup(), weekStart: stamp, now: Self.wednesday))
        }
        // D7: Cedric by default; another name is printed as given (the nickname setting is W5b).
        expectTrue(draft.html.contains("只計 Cedric 自己玩"))
        let named = WeeklyReportBuild.make(events: events, rollup: PerfRollup(), weekStart: "2026-10-19",
                                           now: Self.wednesday, childName: "Mei")
        expectTrue(named?.html.contains("只計 Mei 自己玩") == true)
        expectEqual(WeeklyReportBuild.pages(in: "<section class=\"page\" id=\"p1\"></section><section class=\"page dense\">"), 2)
        print("  weekly report pdf: build 6 pages (draft, cut-off = making time), 1 page without countable play")
    }

    // MARK: §9.4 row states

    func testWeeklyRowStates() {
        let current = WeeklyReportWeek(window: WeeklyWindow(containing: Self.wednesday, dataUntil: Self.wednesday),
                                       now: Self.wednesday)
        guard let lastWindow = WeeklyWindow(weekStart: "2026-10-12") else {
            expectTrue(false, "week stamp did not parse")
            return
        }
        let last = WeeklyReportWeek(window: lastWindow, now: Self.wednesday)
        let list = WeeklyReportWeekList(weeks: [current, last], ready: false)
        let make = "製作 PDF / Make PDF"
        // Before the first read: the loading line only.
        let loading = WeeklyReportPanel(list: list, loaded: false)
        expectEqual(loading.loadingLine, "計緊… / Loading…")
        expectTrue(loading.rows.isEmpty)
        expectNil(loading.banner)
        // Read: one row per week; the draft note on this week only.
        var panel = WeeklyReportPanel(list: list, loaded: true)
        expectNil(panel.loadingLine)
        expectEqual(panel.title, WeeklyWords("每週報告", "Weekly report"))
        expectEqual(panel.rows.map(\.weekStart), ["2026-10-19", "2026-10-12"])
        expectEqual(panel.rows[0].draft, "星期未完（資料截至而家） / Week in progress (data up to now)")
        expectNil(panel.rows[1].draft)
        expectEqual(panel.rows[0].label, WeeklyWords("10月19日至10月25日", "Oct 19 – Oct 25"))
        for row in panel.rows {
            expectEqual(row.makeTitle, make)
            expectTrue(row.canMake && !row.isMaking)
            expectNil(row.finderTitle)
            expectTrue(row.status.isEmpty)
        }
        expectEqual(panel.shareNote, "入面有 Cedric 嘅紀錄，只分享俾屋企人。 / Contains Cedric's records — share with family only.")
        // Making last week: that row says 製作緊…; no row can start another make.
        panel.job = .making(weekStart: "2026-10-12")
        expectEqual(panel.rows[1].makeTitle, "製作緊… / Making…")
        expectTrue(panel.rows[1].isMaking && !panel.rows[1].canMake)
        expectEqual(panel.rows[0].makeTitle, make)
        expectFalse(panel.rows[0].canMake)
        // Made: the done line, the Finder hint and 喺 Finder 顯示 on that row only.
        panel.job = .made(weekStart: "2026-10-12")
        expectEqual(panel.rows[1].status, ["已製作，資料夾已開啟。 / Made. The folder is open.",
                                           "見唔到 Finder？佢喺 Visa Games 後面打開，撳「離開程式」就見到。 / "
                                           + "No Finder window? It opens underneath Visa Games; use Quit to see it."])
        expectEqual(panel.rows[1].finderTitle, "喺 Finder 顯示 / Show in Finder")
        expectTrue(panel.rows[1].canMake)
        expectTrue(panel.rows[0].status.isEmpty)
        expectNil(panel.rows[0].finderTitle)
        // Failed: the §9.4 line on that row; a new make can start.
        panel.job = .failed(weekStart: "2026-10-19")
        expectEqual(panel.rows[0].status, ["製作唔到報告，請再試。（唔影響小朋友玩） / "
                                           + "Couldn't make the report. Please try again. (Play is not affected.)"])
        expectTrue(panel.rows[0].canMake)
        expectNil(panel.rows[0].finderTitle)
        // The value drives `.equatable()`: another state is another value.
        expectFalse(panel == WeeklyReportPanel(list: list, loaded: true))
        expectEqual(panel, WeeklyReportPanel(list: list, loaded: true, job: .failed(weekStart: "2026-10-19")))
        expectEqual(WeeklyReportPanel().childName, WeeklyReportText.defaultChildName)
        expectEqual(WeeklyReportText.defaultChildName, "Cedric")
        print("  weekly report pdf: row states — loading, draft, making (all buttons off), made (Finder), failed")
    }

    // MARK: §9.4 copy verbatim, Traditional only, no banned words

    func testWeeklyRowLabelsAreDesignCopyAndTraditionalOnly() throws {
        let design: [(id: String, zh: String, en: String)] = [
            ("review.weekly.title", "每週報告", "Weekly report"),
            ("review.weekly.ready", "今個星期嘅報告可以製作喇", "This week's report is ready to make"),
            ("review.weekly.draft", "星期未完（資料截至而家）", "Week in progress (data up to now)"),
            ("review.weekly.make", "製作 PDF", "Make PDF"),
            ("review.weekly.making", "製作緊…", "Making…"),
            ("review.weekly.done", "已製作，資料夾已開啟。", "Made. The folder is open."),
            ("review.weekly.show", "喺 Finder 顯示", "Show in Finder"),
            ("review.weekly.failed", "製作唔到報告，請再試。（唔影響小朋友玩）",
             "Couldn't make the report. Please try again. (Play is not affected.)")
        ]
        for item in design {
            expectEqual(WeeklyReportUILabels.table[item.id], WeeklyWords(item.zh, item.en), item.id)
        }
        // The week label keeps the design's Chinese pattern; the share note is the design's line with Cedric (D7).
        expectEqual(WeeklyReportUILabels.table["review.weekly.week"]?.zh, "{m}月{d}日至{m2}月{d2}日")
        expectEqual(WeeklyReportUILabels.weekLabel(weekStart: "2026-12-28", weekEnd: "2027-01-03"),
                    WeeklyWords("12月28日至1月3日", "Dec 28 – Jan 3"))
        expectEqual(WeeklyReportUILabels.shareNote(childName: WeeklyReportText.defaultChildName),
                    WeeklyWords("入面有 Cedric 嘅紀錄，只分享俾屋企人。", "Contains Cedric's records — share with family only."))
        // §11: the clear dialog's new sentence.
        expectEqual(WeeklyReportUILabels.clearNote,
                    WeeklyWords("已經分享出去嘅週報唔會被刪除。", "Reports you have already shared are not deleted."))
        expectEqual(WeeklyReportUILabels.table.count, 13)
        expectEqual(WeeklyReportUILabels.text("no.such.label"), WeeklyWords("", ""))

        // Every entry, and every line a panel can show, is Traditional Chinese only with no banned word.
        let simplified = try Self.simplifiedOnly()
        expectTrue(simplified.count > 2_000, "OpenCC list size \(simplified.count)")
        var scanned = 0
        func check(_ text: String, _ label: String) {
            let found = text.filter { simplified.contains($0) }
            expectTrue(found.isEmpty, "\(label): Simplified \(found)")
            expectTrue(isTraditionalChineseOnly(text) && perfTraditionalOnly(text), "\(label) is Traditional only")
            expectTrue(Self.bannedHits(text).isEmpty, "\(label): banned \(Self.bannedHits(text))")
            scanned += 1
        }
        for (id, words) in WeeklyReportUILabels.table {
            expectFalse(words.zh.isEmpty || words.en.isEmpty, id)
            check(words.zh, id)
            check(words.en, id)
        }
        let weeks = [WeeklyReportWeek(window: WeeklyWindow(containing: Self.wednesday, dataUntil: Self.wednesday),
                                      now: Self.wednesday)]
        let list = WeeklyReportWeekList(weeks: weeks, ready: true)
        let jobs: [WeeklyReportJob] = [.idle, .making(weekStart: "2026-10-19"), .made(weekStart: "2026-10-19"),
                                       .failed(weekStart: "2026-10-19")]
        for (loaded, job) in [(false, WeeklyReportJob.idle)] + jobs.map({ (true, $0) }) {
            let panel = WeeklyReportPanel(list: list, loaded: loaded, job: job)
            var lines = [panel.title.zh, panel.title.en, panel.shareNote]
            lines += [panel.banner, panel.loadingLine].compactMap { $0 }
            for row in panel.rows {
                lines += [row.label.zh, row.label.en, row.makeTitle] + row.status
                lines += [row.draft, row.finderTitle].compactMap { $0 }
            }
            for line in lines { check(line, "panel line") }
        }
        // The W5 sources: no OpenCC Simplified character in the new files; the changed parent files keep the D10 scan.
        for path in ["Sources/VisaCore/WeeklyReportExport.swift", "Sources/VisaCore/WeeklyReportRow.swift",
                     "Sources/VisaCore/WeeklyReportPDFMaker.swift", "Sources/VisaGames/WeeklyReportCoordinator.swift"] {
            let text = try Self.source(path)
            let found = text.filter { simplified.contains($0) }
            expectTrue(found.isEmpty, "\(path): Simplified \(found)")
        }
        for path in ["Sources/VisaGames/ParentReviewView.swift", "Sources/VisaGames/ParentSettingsView.swift",
                     "Sources/VisaGames/PerformanceRecorder.swift", "Sources/VisaGames/AppDelegate.swift"] {
            let text = try Self.source(path)
            expectTrue(isTraditionalChineseOnly(text) && perfTraditionalOnly(text), "\(path) is Traditional only")
        }
        print("  weekly report pdf: \(WeeklyReportUILabels.table.count) row labels (§9.4 verbatim), \(scanned) strings "
              + "Traditional only, no banned words")
    }

    // MARK: §11 clear sentence, 0.35.0 / 71

    func testClearSentenceAndVersionSourceGuards() throws {
        let settings = try Self.source("Sources/VisaGames/ParentSettingsView.swift")
        let app = try Self.source("Sources/VisaGames/AppDelegate.swift")
        let plist = try Self.source("Resources/Info.plist")
        // §11: the 「清除表現紀錄」 confirmation gains the sentence (both languages, from the W5 table).
        guard let block = settings.range(of: "private struct ParentPerformanceRecordsBlock: View {"),
              let confirm = settings.range(of: "Text(\"清除所有表現紀錄？簽證同准許影片唔會變。\" + WeeklyReportUILabels.clearNote.zh",
                                           range: block.upperBound..<settings.endIndex) else {
            expectTrue(false, "the clear confirmation does not carry the W5 sentence")
            return
        }
        let tail = settings[confirm.upperBound...].prefix(160)
        expectTrue(tail.contains("+ \" / Clear all performance records? \" + WeeklyReportUILabels.clearNote.en)"))
        expectTrue(settings.contains("model.perfClear()"))
        expectEqual(WeeklyReportUILabels.clearNote.zh, "已經分享出去嘅週報唔會被刪除。")
        // 清除表現紀錄 stops a make before the folder goes; 清除簽證及重設儲存 never touches stats/ or the weekly files.
        let clear = Self.body(of: "func perfClear(", in: app)
        guard let reset = clear.range(of: "weeklyReport.reset()"), let wipe = clear.range(of: "perf.clearAll") else {
            expectTrue(false, "perfClear does not reset the weekly report before clearing")
            return
        }
        expectTrue(reset.lowerBound < wipe.lowerBound)
        let storage = Self.body(of: "func resetStorage(", in: app)
        expectFalse(storage.isEmpty)
        for needle in ["weeklyReport", "clearAll", "WeeklyReportFiles", "store.clear()"] {
            expectFalse(storage.contains(needle), "resetStorage must not use \(needle)")
        }
        expectTrue(storage.contains("perf.marker(\"reset_storage\")"))
        // Version: Info.plist == the parent footer == 0.35.0 / build 71 (this slice changes the app).
        func plistValue(_ key: String) -> String? {
            guard let keyRange = plist.range(of: "<key>\(key)</key><string>"),
                  let end = plist.range(of: "</string>", range: keyRange.upperBound..<plist.endIndex) else { return nil }
            return String(plist[keyRange.upperBound..<end.lowerBound])
        }
        expectEqual(plistValue("CFBundleShortVersionString"), "0.35.0")
        expectEqual(plistValue("CFBundleVersion"), "71")
        expectTrue(settings.contains("static let versionLabel = \"Visa Games v0.35.0\""))
        print("  weekly report pdf: clear dialog sentence, clear order, visa reset untouched, version 0.35.0 / 71")
    }

    // MARK: The macOS PDF maker and the app wiring (source guards; the WebKit run is `WeeklyReportPDFMacTests`)

    func testPDFMakerAndCoordinatorSourceGuards() throws {
        let maker = try Self.source("Sources/VisaCore/WeeklyReportPDFMaker.swift")
        // macOS only, so VisaCore and `VisaCoreChecks` still build Foundation-only on Linux.
        expectTrue(maker.hasPrefix("#if os(macOS) && canImport(WebKit) && canImport(PDFKit) && canImport(AppKit)\n"))
        expectTrue(maker.hasSuffix("#endif\n"))
        for path in ["Sources/VisaCore/WeeklyReportExport.swift", "Sources/VisaCore/WeeklyReportRow.swift"] {
            let pure = try Self.source(path)
            for needle in ["import WebKit", "import PDFKit", "import AppKit", "import SwiftUI", "Date()", "TimeZone.current",
                           "Locale.current", "Calendar.current", "autoupdatingCurrent"] {
                expectFalse(pure.contains(needle), "\(path) must not use \(needle)")
            }
        }
        // No script, no network, one document; vectors redrawn into A4; torn down on every path.
        for needle in ["allowsContentJavaScript = false", "loadHTMLString(html, baseURL: nil)",
                       "WeeklyReportPDFGeometry.allowsNavigation(", "decisionHandler(allowed ? .allow : .cancel)",
                       ".nonPersistent()", "createPDF(configuration:", "webViewWebContentProcessDidTerminate",
                       "WeeklyReportPDFGeometry.timeoutSeconds", "Task.detached", "stopLoading()",
                       "navigationDelegate = nil", "webView = nil", "drawPDFPage(", "kCGPDFContextTitle",
                       "kCGPDFContextAuthor", "kCGPDFContextCreator", "PDFDocument(data:"] {
            expectTrue(maker.contains(needle), "the maker must use \(needle)")
        }
        for needle in ["allowsContentJavaScript = true", "javaScriptEnabled", "evaluateJavaScript", "callAsyncJavaScript",
                       "WKUserScript", "addUserScript", "WKScriptMessageHandler", "URLRequest", "loadFileURL", "http",
                       "uiDelegate", "NSWindow", "NSPanel", "addSubview", "contentView", "makeKeyAndOrderFront",
                       "orderFront", "makeFirstResponder", "becomeFirstResponder", "NSSavePanel", "NSOpenPanel",
                       "NSSharingServicePicker", "runModal", "printOperation", "NSPrintOperation", "pageZoom",
                       "takeSnapshot", "DispatchQueue.main.sync", "semaphore", "Thread.sleep", "usleep",
                       "assumeIsolated", "unowned"] {
            expectFalse(maker.contains(needle), "the maker must not use \(needle)")
        }
        // Web views exist only where they did, plus the maker; only the coordinator makes PDFs.
        let root = Self.repoRoot()
        for folder in ["Sources/VisaGames", "Sources/VisaCore"] {
            let names = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(folder).path)
            for name in names.sorted() where name.hasSuffix(".swift") {
                let text = try Self.source(folder + "/" + name)
                if text.contains("WKWebView(") {
                    expectTrue(["ScopedPlayerView.swift", "ParentYouTubeBrowserView.swift",
                                "WeeklyReportPDFMaker.swift"].contains(name), "\(name) makes a web view")
                }
                if text.contains("WeeklyReportPDFMaker(") {
                    expectEqual(name, "WeeklyReportCoordinator.swift")
                }
            }
        }
        // The coordinator: Finder reveal as the CSV export does, only when parent mode allows it; no panel, no share
        // sheet (W6), no schedule or nickname (W5b).
        let coordinator = try Self.source("Sources/VisaGames/WeeklyReportCoordinator.swift")
        for needle in ["@MainActor\nfinal class WeeklyReportCoordinator", "private let maker = WeeklyReportPDFMaker()",
                       "maker.cancel()", "NSWorkspace.shared.activateFileViewerSelecting([url])",
                       "recorder.marker(WeeklyReportMarker.what, build.markerFields)", "recorder.weeklyReportWeeks",
                       "recorder.weeklyReportBuild(", "recorder.weeklyReportWrite("] {
            expectTrue(coordinator.contains(needle), "the coordinator must use \(needle)")
        }
        expectTrue(Self.startsWith(Self.body(of: "func reveal()", in: coordinator),
                                   "guard let url = madeFile, canReveal?() == true else { return }"))
        for needle in ["NSSharingServicePicker", "NSSavePanel", "NSOpenPanel", "runModal", "NSWindow", "orderFront",
                       "makeKey", "WKWebView", "Timer", "asyncAfter", "UserDefaults", "nickname", "autoMake",
                       "FileManager.default.remove", "assumeIsolated", "unowned", "SwiftUI"] {
            expectFalse(coordinator.contains(needle), "the coordinator must not use \(needle)")
        }
        // AppModel: parent mode only, never while a video plays, and every way out of parent mode stops a make.
        let app = try Self.source("Sources/VisaGames/AppDelegate.swift")
        expectTrue(Self.startsWith(Self.body(of: "func weeklyMake(", in: app),
                                   "guard session.mode == .parent, activePlayVideoID == nil else { return }"))
        expectTrue(Self.startsWith(Self.body(of: "func weeklyShowInFinder(", in: app),
                                   "guard session.mode == .parent else { return }"))
        for header in ["func returnToChild(", "func grant(", "func prepareForTerminate("] {
            expectTrue(Self.body(of: header, in: app).contains("weeklyReport.cancel()"), "\(header) stops a weekly make")
        }
        expectTrue(app.contains("weeklyReport.canReveal = { [weak self] in self?.session.mode == .parent }"))
        expectTrue(Self.body(of: "func perfRefreshReview(", in: app).contains("weeklyReport.refreshWeeks()"))
        for needle in ["autoMake", "nickname", "NSSharingServicePicker"] {
            expectFalse(app.contains(needle), "AppDelegate must not use \(needle) (W5b / W6)")
        }
        // The recorder: one marker helper for every `what`; the weekly reading, build and writes on its queue.
        let recorder = try Self.source("Sources/VisaGames/PerformanceRecorder.swift")
        expectTrue(recorder.contains("func marker(_ what: String, _ extra: [String: PerfValue] = [:]) {"))
        for header in ["func weeklyReportWeeks(", "func weeklyReportBuild(", "func weeklyReportWrite("] {
            expectTrue(Self.body(of: header, in: recorder).contains("queue.async {"), "\(header) runs on the recorder queue")
        }
        print("  weekly report pdf: maker guards (macOS only, JS off, about:blank only, no window, teardown), "
              + "coordinator and AppModel wiring")
    }
}
