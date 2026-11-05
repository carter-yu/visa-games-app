import Foundation
import Darwin
import os
import VisaCore

/// All file I/O and date formatting stay off the UI thread. No settings or child data.
enum ParentScrollLog {
    private static let sink = Sink()

    static func write(_ message: String) {
        sink.write(message, date: Date(), uptime: ProcessInfo.processInfo.systemUptime)
    }

    /// Addresses were collected synchronously on the UI thread, at the observed
    /// change. Resolve those addresses here, never the logging queue's own stack.
    static func writeStack(id: UUID, label: String, jump: ParentScrollStackSample,
                           heights: [ParentScrollStackSample]) {
        sink.writeStack(id: id, label: label, jump: jump, heights: heights, date: Date())
    }

    /// Mutable writer/formatter/error state belongs exclusively to queue.
    private final class Sink: @unchecked Sendable {
        private let logger = Logger(subsystem: "family.visagames.mac", category: "parentScroll")
        private let queue = DispatchQueue(label: "family.visagames.mac.parentScroll", qos: .utility)
        private let file: ParentScrollLogFile
        private let formatter = ISO8601DateFormatter()
        private let processID = ProcessInfo.processInfo.processIdentifier
        private var lastFailure: TimeInterval = -.infinity
        private let stackLock = NSLock()
        private var stackPending = false // Access only while holding stackLock.

        init() {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            file = ParentScrollLogFile(url: base.appendingPathComponent("VisaGames/logs/parent-scroll.log"))
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }

        func write(_ message: String, date: Date, uptime: TimeInterval) {
            queue.async { [self] in
                append(message, date: date, uptime: uptime)
            }
        }

        func writeStack(id: UUID, label: String, jump: ParentScrollStackSample,
                        heights: [ParentScrollStackSample], date: Date) {
            stackLock.lock()
            let accepted = !stackPending
            if accepted { stackPending = true }
            stackLock.unlock()
            guard accepted else {
                write("STACK id=\(id) OMITTED reason=writerBusy", date: date, uptime: jump.time)
                return
            }
            queue.async { [self] in
                defer {
                    stackLock.lock()
                    stackPending = false
                    stackLock.unlock()
                }
                let prefix = "STACK id=\(id)"
                // One queue job keeps the block contiguous (rotation can split it
                // across .1 and the current file). Every line carries the block ID.
                append("\(prefix) BEGIN \(label) heightSamples=\(heights.count)", date: date, uptime: jump.time)
                writeSample(jump, name: "jump", prefix: prefix, date: date, jumpTime: jump.time)
                for (index, sample) in heights.enumerated() {
                    writeSample(sample, name: "height[\(index)]", prefix: prefix,
                                date: date, jumpTime: jump.time)
                }
                append("\(prefix) END", date: date, uptime: jump.time)
            }
        }

        private func writeSample(_ sample: ParentScrollStackSample, name: String,
                                 prefix: String, date: Date, jumpTime: TimeInterval) {
            append("\(prefix) sample=\(name) capturedMono=\(String(format: "%.6f", sample.time)) ageMs=\(String(format: "%.1f", (jumpTime - sample.time) * 1_000)) frames=\(sample.addresses.count) \(sample.detail)",
                   date: date, uptime: jumpTime)
            guard !sample.addresses.isEmpty else { return }
            var pointers = sample.addresses.map { UnsafeMutableRawPointer(bitPattern: $0) }
            let symbols = pointers.withUnsafeMutableBufferPointer {
                backtrace_symbols($0.baseAddress, Int32($0.count))
            }
            defer { if let symbols { free(symbols) } }
            for (index, address) in sample.addresses.enumerated() {
                let symbol = symbols.flatMap { $0[index] }.map { String(cString: $0) } ?? "unresolved"
                append("\(prefix) sample=\(name) frame=\(index) address=0x\(String(address, radix: 16)) \(String(symbol.prefix(1_024)))",
                       date: date, uptime: jumpTime)
            }
        }

        private func append(_ message: String, date: Date, uptime: TimeInterval) {
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
