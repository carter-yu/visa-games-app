import Foundation

/// v0.21.5 (ADR 0011): macOS 27 crashed in the Swift runtime executor check right after leaving
/// the parent page, while AppDelegate toggled presentation options, window level, style mask and
/// frame inside the model mutation. Kiosk presentation is now set once at launch. Source guards;
/// the app target has no unit tests.
final class KioskPresentationTests {
    private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

    private func source(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Every Swift file under Sources/, plus shipped launch inputs (Info.plist, scripts/).
    private func shippedTexts() throws -> [(name: String, text: String)] {
        var result: [(name: String, text: String)] = []
        for folder in ["Sources/VisaGames", "Sources/VisaCore"] {
            let directory = root.appendingPathComponent(folder)
            for name in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            where name.hasSuffix(".swift") {
                result.append((name: "\(folder)/\(name)", text: try source("\(folder)/\(name)")))
            }
        }
        result.append((name: "Resources/Info.plist", text: try source("Resources/Info.plist")))
        let scripts = root.appendingPathComponent("scripts")
        for name in try FileManager.default.contentsOfDirectory(atPath: scripts.path).sorted() {
            let data = try Data(contentsOf: scripts.appendingPathComponent(name))
            result.append((name: "scripts/\(name)", text: String(decoding: data, as: UTF8.self)))
        }
        return result
    }

    private static func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// Body of the first `header` (e.g. "func unlock(") up to its matching closing brace.
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

    private static func startsWithGuard(_ body: String, _ condition: String) -> Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("guard \(condition)")
    }

    func testPresentationOptionsSetOnlyAtLaunchAndTerminate() throws {
        let app = try source("Sources/VisaGames/AppDelegate.swift")
        let total = try shippedTexts().reduce(0) { $0 + Self.count("presentationOptions =", in: $1.text) }
        expectEqual(total, 2, "presentationOptions assigned only at launch and terminate")
        let launch = Self.body(of: "func applicationDidFinishLaunching(", in: app)
        let terminate = Self.body(of: "func applicationWillTerminate(", in: app)
        expectEqual(Self.count("NSApp.presentationOptions = Self.kioskPresentationOptions", in: launch), 1)
        expectEqual(Self.count("NSApp.presentationOptions = []", in: terminate), 1)
        guard let options = app.range(of: "private static let kioskPresentationOptions"),
              let end = app.range(of: "]", range: options.upperBound..<app.endIndex) else {
            expectTrue(false, "kioskPresentationOptions not found")
            return
        }
        let declared = app[options.upperBound..<end.upperBound]
        for option in [".hideDock", ".hideMenuBar", ".disableAppleMenu", ".disableProcessSwitching",
                       ".disableForceQuit", ".disableSessionTermination", ".disableHideApplication"] {
            expectTrue(declared.contains(option), "kiosk option \(option)")
        }
    }

    func testWindowChromeIsConstantAfterLaunch() throws {
        let texts = try shippedTexts()
        func total(_ needle: String) -> Int { texts.reduce(0) { $0 + Self.count(needle, in: $1.text) } }
        let app = try source("Sources/VisaGames/AppDelegate.swift")
        let launch = Self.body(of: "func applicationDidFinishLaunching(", in: app)
        expectEqual(total("window.level ="), 1)
        expectEqual(total(".level = .normal"), 0)
        expectTrue(launch.contains("window.level = .mainMenu + 1"))
        expectEqual(total("styleMask ="), 0, "style mask only in the launch initializer")
        expectEqual(total("styleMask:"), 1)
        expectTrue(launch.contains("styleMask: [.borderless]"))
        expectEqual(total("collectionBehavior ="), 1)
        expectTrue(launch.contains("window.collectionBehavior = [.fullScreenDisallowsTiling]"))
        for gone in ["applyPresentation", "parentWindowFrame", "isChildPresentation", "minSize",
                     "deminiaturize", "model.changed ="] {
            expectEqual(total(gone), 0, "\(gone) is gone (constant presentation)")
        }
        // The only resize: launch and the coalesced, deferred screen-change refit.
        expectEqual(total("setFrame("), 1)
        expectTrue(Self.body(of: "private func fitWindowToScreen(", in: app).contains("window.setFrame(screen.frame"))
        expectEqual(Self.count("fitWindowToScreen()", in: app), 3)
        expectEqual(Self.count("fitWindowToScreen()", in: launch), 1)
        let screenChanged = Self.body(of: "@objc private func screenChanged(", in: app)
        expectTrue(screenChanged.contains("guard !screenRefitPending else { return }"))
        expectTrue(screenChanged.contains("DispatchQueue.main.async"))
        expectTrue(screenChanged.contains("self.fitWindowToScreen()"))
        expectFalse(screenChanged.contains("Task"))
        // Quit from parent still works; no main-menu mutations anywhere.
        let shouldTerminate = Self.body(of: "func applicationShouldTerminate(", in: app)
        expectTrue(shouldTerminate.contains("guard model.session.allowsExit else { return .terminateCancel }"))
        expectTrue(shouldTerminate.contains("return .terminateNow"))
        let quit = Self.body(of: "func quitFromParent(", in: app)
        expectTrue(quit.contains("NSApp.terminate(nil)"))
        expectEqual(total("NSMenu"), 0)
        expectEqual(total("mainMenu ="), 0)
    }

    func testSoakHookIsGatedOnEnvironmentAndOnlyBypassesAuthThere() throws {
        let texts = try shippedTexts()
        func total(_ needle: String) -> Int { texts.reduce(0) { $0 + Self.count(needle, in: $1.text) } }
        let app = try source("Sources/VisaGames/AppDelegate.swift")
        // The env var is read in one place; no shipped launch path sets it.
        let gate = Self.body(of: "enum KioskSoak", in: app)
        expectEqual(total("\"VISAGAMES_SOAK\""), 1)
        expectEqual(total("\"VISAGAMES_SOAK_CYCLES\""), 1)
        expectTrue(gate.contains("environment[\"VISAGAMES_SOAK\"] == \"1\""))
        expectTrue(gate.contains("environment[\"VISAGAMES_SOAK_CYCLES\"]"))
        expectTrue(gate.contains("return 50"))
        for file in texts where !file.name.hasSuffix(".swift") {
            expectFalse(file.text.contains("VISAGAMES_SOAK"), "\(file.name) must not set the soak env var")
        }
        let plist = try source("Resources/Info.plist")
        expectFalse(plist.contains("LSEnvironment"))
        // Every soak entry point checks the gate first.
        expectEqual(total("KioskSoak.isEnabled"), 3)
        let start = Self.body(of: "private func startSoakIfRequested(", in: app)
        let step = Self.body(of: "@objc private func soakStep(", in: app)
        let soakEnter = Self.body(of: "func soakEnterParent(", in: app)
        expectTrue(Self.startsWithGuard(start, "KioskSoak.isEnabled else { return }"))
        expectTrue(Self.startsWithGuard(step, "KioskSoak.isEnabled"))
        expectTrue(Self.startsWithGuard(soakEnter, "KioskSoak.isEnabled else { return }"))
        expectEqual(total("startSoakIfRequested()"), 2)
        expectTrue(Self.body(of: "func applicationDidFinishLaunching(", in: app).contains("startSoakIfRequested()"))
        // AppKit timer, not a Task; 1.5 s; logs each cycle and the end.
        expectTrue(start.contains("Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(soakStep)"))
        expectFalse(start.contains("Task"))
        expectFalse(step.contains("Task"))
        expectTrue(step.contains("VisaGamesLog.append(\"soak cycle \\(soakCycle)\")"))
        expectTrue(step.contains("VisaGamesLog.append(\"soak done\")"))
        expectTrue(step.contains("model.returnToChild(reason: \"soak\")"))
        // The LAContext bypass is reachable only from the soak step.
        expectEqual(total("soakEnterParent("), 2)
        expectTrue(step.contains("model.soakEnterParent()"))
        expectFalse(soakEnter.contains("LAContext"))
        expectFalse(soakEnter.contains("evaluatePolicy"))
        // unlock() keeps LAContext and only enters parent after `success`.
        expectEqual(total("enterParentAfterAuthentication()"), 3)
        expectEqual(total("enterParent(authenticated: true"), 1)
        expectTrue(app.contains("private func enterParentAfterAuthentication()"))
        expectTrue(Self.body(of: "private func enterParentAfterAuthentication(", in: app)
            .contains("update { $0.enterParent(authenticated: true, now: Date()) }"))
        let unlock = Self.body(of: "func unlock(", in: app)
        expectTrue(unlock.contains("let context = LAContext()"))
        expectTrue(unlock.contains("evaluatePolicy(.deviceOwnerAuthentication"))
        guard let success = unlock.range(of: "guard success else"),
              let enter = unlock.range(of: "enterParentAfterAuthentication()") else {
            expectTrue(false, "unlock success branch not found")
            return
        }
        expectTrue(success.upperBound < enter.lowerBound)
        expectFalse(unlock.contains("KioskSoak"))
        expectEqual(total("soakTimer?.invalidate()"), 2)
        expectTrue(Self.body(of: "private func prepareForTerminate(", in: app).contains("soakTimer?.invalidate()"))
    }
}
