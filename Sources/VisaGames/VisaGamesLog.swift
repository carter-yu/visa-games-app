import AppKit
import Foundation

/// App-wide Visa Games diagnostics for Mac mini UAT (no secrets).
/// Mirrors to `~/Library/Logs/VisaGames/` and, when discoverable, the repo `logs/` folder.
/// File name: `visa-games-YYYYMMDD.log` (ScopedPlayer keeps its own `scoped-player-*.log`).
enum VisaGamesLog {
    private static let queue = DispatchQueue(label: "family.visagames.app-log")

    static var activeLogDirectory: URL {
        ScopedPlayerLog.activeLogDirectory
    }

    static func append(_ message: String) {
        let stamp = timestamp(Date())
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
                    fputs("VisaGamesLog write failed: \(error.localizedDescription)\n", stderr)
                }
            }
        }
    }

    static func openActiveDirectory() {
        ScopedPlayerLog.openActiveDirectory()
    }

    private static func logFileURLs() -> [URL] {
        let day = dayStamp(Date())
        let name = "visa-games-\(day).log"
        var dirs: [URL] = [ScopedPlayerLog.libraryLogDirectory()]
        if let env = ProcessInfo.processInfo.environment["VISA_GAMES_LOG_DIR"], !env.isEmpty {
            let envURL = URL(fileURLWithPath: env, isDirectory: true)
            if !dirs.contains(envURL) { dirs.append(envURL) }
        }
        if let repo = ScopedPlayerLog.discoverRepoLogsDirectory(), !dirs.contains(repo) {
            dirs.append(repo)
        }
        return dirs.map { $0.appendingPathComponent(name, isDirectory: false) }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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
