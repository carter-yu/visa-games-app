import AppKit
import Combine
import LocalAuthentication
import SwiftUI
import VisaCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var session: Session
    @Published private(set) var now = Date()
    @Published private(set) var message: String?
    @Published private(set) var authenticating = false
    private let store: SnapshotStore
    private var storageFailed = false
    private var authentication: LAContext?
    private var parentDeadline: Date?
    var changed: (() -> Void)?

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = SnapshotStore(url: directory.appendingPathComponent("VisaGames/state.json"))
        do {
            session = Session(snapshot: try store.load(), now: Date())
        } catch {
            session = Session(snapshot: Snapshot(configured: true), now: Date())
            storageFailed = true
            message = "儲存資料有問題，請家長處理。 / Storage needs parent attention."
        }
    }

    func update(_ action: (inout Session) -> Void) {
        var next = session
        action(&next)
        if next.snapshot != session.snapshot {
            do { try store.save(next.snapshot) }
            catch {
                storageFailed = true
                message = "未能儲存，請家長處理。 / Could not save. Ask a parent."
                session = Session(snapshot: Snapshot(configured: true), now: Date())
                changed?()
                return
            }
        }
        session = next
        changed?()
    }

    func tick() {
        now = Date()
        let current = now
        update { $0.tick(now: current) }
        if let parentDeadline, current >= parentDeadline { returnToChild() }
    }

    func unlock() {
        guard !authenticating, session.mode != .parent else { return }
        let context = LAContext()
        context.localizedCancelTitle = "取消 / Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            message = "請先設定 Mac 登入密碼。 / Configure Mac authentication first."
            return
        }
        authentication = context
        authenticating = true
        Task { @MainActor in
            let success = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                localizedReason: "開啟家長設定 / Open parent controls")) == true
            guard authentication === context else { return }
            authenticating = false
            authentication = nil
            guard success else {
                message = "未能確認家長身份。 / Parent authentication cancelled or failed."
                return
            }
            parentDeadline = Date().addingTimeInterval(120)
            if !storageFailed { message = nil }
            update { $0.enterParent(authenticated: true, now: Date()) }
        }
    }

    func returnToChild() {
        authentication?.invalidate()
        authentication = nil
        authenticating = false
        parentDeadline = nil
        update { $0.leaveParent(now: Date()) }
    }

    func setup() {
        guard !storageFailed else { return }
        update { $0.completeSetup() }
    }

    func grant() {
        guard !storageFailed else { return }
        update { $0.grant(seconds: 60, now: Date()) }
    }

    func resetStorage() {
        guard session.mode == .parent else { return }
        do {
            let fresh = Snapshot(configured: true)
            try store.save(fresh)
            storageFailed = false
            message = nil
            session = Session(snapshot: fresh, now: Date())
            changed?()
        } catch { message = "仍未能儲存。 / Storage is still unavailable." }
    }
}

final class KioskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private var window: KioskWindow!
    private var timer: Timer?
    private var keyMonitor: Any?
    private var isChildPresentation: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = KioskWindow(contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Visa Games / 簽證遊戲"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenDisallowsTiling]
        window.contentView = NSHostingView(rootView: ShellView(model: model))
        model.changed = { [weak self] in self?.applyPresentation() }
        applyPresentation()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.model.session.blocksKey(isEscape: event.keyCode == 53,
                                            hasCommand: event.modifierFlags.contains(.command)) { return nil }
            return event
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.tick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func applyPresentation() {
        let child = !model.session.allowsExit
        guard child != isChildPresentation else { return }
        isChildPresentation = child
        NSApp.presentationOptions = child ? [.hideDock, .hideMenuBar, .disableAppleMenu,
            .disableProcessSwitching, .disableForceQuit, .disableSessionTermination, .disableHideApplication] : []
        window.level = child ? .mainMenu + 1 : .normal
    }

    @objc private func willSleep() { model.returnToChild() }
    @objc private func didWake() { model.tick() }
    @objc private func screenChanged() {
        if let screen = window.screen ?? NSScreen.main { window.setFrame(screen.frame, display: true) }
    }
    func applicationDidResignActive(_ notification: Notification) {
        if model.session.mode == .parent { model.returnToChild() }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.session.allowsExit ? .terminateNow : .terminateCancel
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { NSApp.presentationOptions = [] }
}

struct ShellView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 28) {
            Text("Visa Games / 簽證遊戲").font(.largeTitle.bold())
            Text("先做再玩 / Do first, then play").font(.title2)
            Spacer()
            switch model.session.mode {
            case .setup:
                Text("請家長設定 / Parent setup required").font(.title)
            case .lock:
                Text("用筆畫 / Draw with your pen").font(.system(size: 44, weight: .bold))
                Text("準備好未？ / Ready?")
                Text("遊戲稍後加入 / Activities are coming later")
            case .play:
                Text("簽證時間 / Visa time").font(.title)
                Text("\(model.session.remaining(at: model.now)) 秒 / seconds")
                    .font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                Text("播放位置預覽 / Playback placeholder")
            case .parent:
                Text("家長設定 / Parent controls").font(.title)
                Text("兩分鐘後自動鎖定 / Locks automatically after two minutes")
                if !model.session.snapshot.configured {
                    Button("完成設定 / Finish setup", action: model.setup)
                } else {
                    Button("測試一分鐘簽證 / Test 1-minute visa", action: model.grant)
                }
                Button("返回 / Return", action: model.returnToChild)
                if model.message != nil {
                    Button("清除簽證及重設儲存 / Clear visa and reset storage", action: model.resetStorage)
                }
                Button("離開程式 / Quit app") { NSApp.terminate(nil) }
            }
            if let message = model.message { Text(message).foregroundStyle(.orange) }
            Spacer()
            if model.session.mode != .parent {
                Button("家長 / Parent", action: model.unlock).disabled(model.authenticating)
            }
            Text("v0.1.0 · Phase 0").font(.footnote)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(Color(red: 0.06, green: 0.12, blue: 0.20))
    }
}
