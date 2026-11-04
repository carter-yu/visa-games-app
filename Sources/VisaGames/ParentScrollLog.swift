import Foundation
import os
import VisaCore

/// All file I/O and date formatting stay off the UI thread. No settings or child data.
enum ParentScrollLog {
    private static let sink = Sink()

    static func write(_ message: String) {
        sink.write(message, date: Date(), uptime: ProcessInfo.processInfo.systemUptime)
    }

    /// Mutable writer/formatter/error state belongs exclusively to queue.
    private final class Sink: @unchecked Sendable {
        private let logger = Logger(subsystem: "family.visagames.mac", category: "parentScroll")
        private let queue = DispatchQueue(label: "family.visagames.mac.parentScroll", qos: .utility)
        private let file: ParentScrollLogFile
        private let formatter = ISO8601DateFormatter()
        private let processID = ProcessInfo.processInfo.processIdentifier
        private var lastFailure: TimeInterval = -.infinity

        init() {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            file = ParentScrollLogFile(url: base.appendingPathComponent("VisaGames/logs/parent-scroll.log"))
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }

        func write(_ message: String, date: Date, uptime: TimeInterval) {
            queue.async { [self] in
                let line = "\(formatter.string(from: date)) pid=\(processID) mono=\(String(format: "%.3f", uptime)) \(message)"
                logger.info("\(line, privacy: .public)")
                do {
                    try file.append(line)
                } catch {
                    // Never affect settings; report a failed destination at most once/minute.
                    if uptime - lastFailure >= 60 {
                        lastFailure = uptime
                        logger.error("parent-scroll file append failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }
}
