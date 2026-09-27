import AppKit
import Foundation

/// Lightweight ScopedPlayer diagnostics for Mac mini UAT (no secrets).
/// Always mirrors to `~/Library/Logs/VisaGames/` and, when discoverable, the repo `logs/` folder.
enum ScopedPlayerLog {
    private static let queue = DispatchQueue(label: "family.visagames.scoped-player-log")
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Primary folder for the parent "Open logs folder" button: repo `logs/` when found, else Library.
    static var activeLogDirectory: URL {
        if let repo = discoverRepoLogsDirectory() {
            return repo
        }
        return libraryLogDirectory()
    }

    static func libraryLogDirectory() -> URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Logs/VisaGames", isDirectory: true)
    }

    static func append(_ message: String) {
        let stamp = isoFormatter.string(from: Date())
        let line = "\(stamp) \(message)\n"
        let destinations = logFileURLs()
        queue.async {
            let data = Data(line.utf8)
            let fm = FileManager.default
            for fileURL in destinations {
                let dir = fileURL.deletingLastPathComponent()
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    if !fm.fileExists(atPath: fileURL.path) {
                        fm.createFile(atPath: fileURL.path, contents: nil)
                    }
                    let handle = try FileHandle(forWritingTo: fileURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    // Best-effort diagnostics only — never disrupt playback.
                    fputs("ScopedPlayerLog write failed: \(error.localizedDescription)\n", stderr)
                }
            }
        }
    }

    static func openActiveDirectory() {
        let dir = activeLogDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private static func logFileURLs() -> [URL] {
        let day = dayStamp(Date())
        let name = "scoped-player-\(day).log"
        var dirs: [URL] = [libraryLogDirectory()]
        if let env = ProcessInfo.processInfo.environment["VISA_GAMES_LOG_DIR"], !env.isEmpty {
            let envURL = URL(fileURLWithPath: env, isDirectory: true)
            if !dirs.contains(envURL) { dirs.append(envURL) }
        }
        if let repo = discoverRepoLogsDirectory(), !dirs.contains(repo) {
            dirs.append(repo)
        }
        return dirs.map { $0.appendingPathComponent(name, isDirectory: false) }
    }

    /// Walk upward from cwd and the .app bundle looking for `logs/README.md`.
    static func discoverRepoLogsDirectory(
        fileManager: FileManager = .default,
        cwd: URL? = nil,
        bundleURL: URL? = nil
    ) -> URL? {
        var starts: [URL] = []
        if let cwd {
            starts.append(cwd)
        } else {
            starts.append(URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true))
        }
        if let bundleURL {
            starts.append(bundleURL)
        } else {
            starts.append(Bundle.main.bundleURL)
        }
        var seen = Set<String>()
        for start in starts {
            var current = start.standardizedFileURL
            for _ in 0..<12 {
                let key = current.path
                if seen.contains(key) { break }
                seen.insert(key)
                let readme = current.appendingPathComponent("logs/README.md", isDirectory: false)
                if fileManager.fileExists(atPath: readme.path) {
                    return current.appendingPathComponent("logs", isDirectory: true)
                }
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
        }
        return nil
    }

    private static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}
