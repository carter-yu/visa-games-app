import Foundation
import VisaCore

/// v0.22.1 (ADR 0010): the Swift 6 runtime actor-isolation check at the top of the ZStack
/// builder in `ShellView.body` crashed inside the runtime (main thread, SwiftUI transaction).
/// v0.22.2: depot hang fix — no precomputed content, skip ParentCornerLayer on depot, revert
/// selector Timer. Source guards; the app target has no unit tests.
final class ActorIsolationTests {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func appSources() throws -> [(name: String, text: String)] {
        let directory = root.appendingPathComponent("Sources/VisaGames")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        return try names.map { name in
            (name: name, text: try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8))
        }
    }

    private static func identifier(in text: Substring, from start: Substring.Index) -> (String, Substring.Index) {
        let end = text[start...].firstIndex { !($0.isLetter || $0.isNumber || $0 == "_") } ?? text.endIndex
        return (String(text[start..<end]), end)
    }

    func testPackageDisablesDynamicActorIsolationForTheAppTargetOnly() throws {
        let package = try source("Package.swift")
        expectTrue(package.hasPrefix("// swift-tools-version: 6.0"))
        expectFalse(package.contains("swiftLanguageMode"), "app stays in Swift 6 language mode")
        guard let flag = package.range(of: ".unsafeFlags([\"-Xfrontend\", \"-disable-dynamic-actor-isolation\"])") else {
            expectTrue(false, "Package.swift lacks -disable-dynamic-actor-isolation")
            return
        }
        let before = package[package.startIndex..<flag.lowerBound]
        guard let name = before.range(of: "name: \"", options: .backwards) else {
            expectTrue(false, "no target name before the flag")
            return
        }
        expectTrue(before[name.upperBound...].hasPrefix("VisaGames\""))
        expectEqual(package.components(separatedBy: "unsafeFlags").count, 2)
    }

    func testAppSourcesHaveNoUnownedOrAssumeIsolated() throws {
        let files = try appSources()
        expectTrue(files.count > 20)
        for file in files {
            expectFalse(file.text.contains("unowned"), "unowned in \(file.name)")
            expectFalse(file.text.contains("assumeIsolated"), "assumeIsolated in \(file.name)")
        }
    }

    func testShellViewPassesExplicitClosuresNotModelMethodReferences() throws {
        let app = try source("Sources/VisaGames/AppDelegate.swift")
        guard let modelStart = app.range(of: "final class AppModel: ObservableObject {"),
              let modelEnd = app.range(of: "final class KioskWindow", range: modelStart.upperBound..<app.endIndex),
              let shellStart = app.range(of: "struct ShellView: View {") else {
            expectTrue(false, "AppModel / ShellView not found")
            return
        }
        let modelText = app[modelStart.upperBound..<modelEnd.lowerBound]
        var methods: Set<String> = []
        var cursor = modelText.startIndex
        while let hit = modelText.range(of: "func ", range: cursor..<modelText.endIndex) {
            let (name, _) = Self.identifier(in: modelText, from: hit.upperBound)
            if !name.isEmpty { methods.insert(name) }
            cursor = hit.upperBound
        }
        expectTrue(methods.contains("unlock"))
        expectTrue(methods.contains("dismissProviderBlocked"))
        expectTrue(methods.contains("useEntryHint"))

        let shell = app[shellStart.upperBound...]
        var references = 0
        cursor = shell.startIndex
        while let hit = shell.range(of: "model.", range: cursor..<shell.endIndex) {
            let (name, end) = Self.identifier(in: shell, from: hit.upperBound)
            if methods.contains(name) {
                references += 1
                let next: Character = end < shell.endIndex ? shell[end] : " "
                expectTrue(next == "(", "unapplied model.\(name) in ShellView")
            }
            cursor = hit.upperBound
        }
        expectTrue(references > 30)
        // v0.22.2: depot skips ParentCornerLayer; childOrLegacy is inlined in the ZStack.
        expectTrue(shell.contains("let onDepot = model.session.mode == .lock && !model.taskRoundOpen"))
        expectTrue(shell.contains("let showsParentCorner = childMode && !watching && !onDepot"))
        expectTrue(shell.contains("childOrLegacy"))
        expectFalse(shell.contains("let content = childOrLegacy"))
    }

    func testRecorderContextTimerAndRecorderStayOnMain() throws {
        let app = try source("Sources/VisaGames/AppDelegate.swift")
        expectTrue(app.contains("perf.contextProvider = { [weak self] in"))
        expectTrue(app.contains("guard let self else { return PerfRecorderContext(mode: .lock, isPlaytest: false) }"))
        // v0.22.2: selector Timer reverted after depot hang; ticks hop via Task { @MainActor }.
        expectFalse(app.contains("selector: #selector(timerFired(_:))"))
        expectTrue(app.contains("self?.model.tick()"))
        expectTrue(app.contains("@MainActor\nfinal class AppModel"))
        let recorder = try source("Sources/VisaGames/PerformanceRecorder.swift")
        expectTrue(recorder.contains("@MainActor\nfinal class PerformanceRecorder"))
        expectEqual(recorder.components(separatedBy: "nonisolated").count - 1, 2)
        expectTrue(recorder.contains("nonisolated let store: PerfEventStore"))
    }

    func testParentCornerLayerDoesNotHostFullScreenCanvasStage() throws {
        let corner = try source("Sources/VisaGames/ParentCornerEntry.swift")
        expectFalse(corner.contains("CanvasStage"), "ParentCornerLayer must not use CanvasStage (full-screen hit target)")
        expectTrue(corner.contains("allowsHitTesting(false)"))
        expectTrue(corner.contains("ParentCornerEntry(onUnlock: onUnlock)"))
    }
}
