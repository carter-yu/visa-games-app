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
    @Published private(set) var themePaletteID: ThemePaletteID
    @Published private(set) var successFeedbackID: Int? = nil
    @Published private(set) var allowlist = VideoAllowlist()
    /// Parent-only draft for the allowlist text field (never shown on child path).
    @Published var parentVideoIDDraft = ""
    @Published var parentVideoDurationDraft = "120"
    @Published private(set) var activePlayVideoID: String?
    @Published private(set) var playbackMessage: String?
    private let store: SnapshotStore
    private let themeStore = ThemePreferenceStore()
    private let allowlistStore = VideoAllowlistStore()
    private var nextFeedbackID = 0
    private var storageFailed = false
    private var authentication: LAContext?
    private var parentDeadline: Date?
    private let parentAccessSeconds: TimeInterval = 600
    var changed: (() -> Void)?

    init() {
        themePaletteID = ThemePreferenceStore().load()
        allowlist = VideoAllowlistStore().load()
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
        if let id = activePlayVideoID {
            let decision = PlaybackPolicy().evaluateContinue(
                remainingViewingBudgetSeconds: remainingViewingBudget(at: current),
                sessionEndsAt: session.snapshot.endsAt,
                now: current
            )
            if !decision.allowed, let reason = decision.stopReason {
                stopScopedPlayback(reason: reason)
                _ = id
            }
        }
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
            parentDeadline = Date().addingTimeInterval(parentAccessSeconds)
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
        // Drop parent preview if we are no longer in play with a valid policy.
        if session.mode != .play {
            activePlayVideoID = nil
        } else if let id = activePlayVideoID {
            let decision = PlaybackPolicy().evaluateStart(
                videoID: id,
                allowlist: allowlist,
                remainingViewingBudgetSeconds: remainingViewingBudget(at: Date()),
                sessionEndsAt: session.snapshot.endsAt,
                now: Date()
            )
            if !decision.allowed { activePlayVideoID = nil }
        }
    }

    func setup() {
        guard !storageFailed else { return }
        update { $0.completeSetup() }
    }

    func grant() {
        guard !storageFailed else { return }
        update { $0.grant(seconds: 60, now: Date()) }
    }

    func selectTheme(_ palette: ThemePaletteID) {
        guard session.mode == .parent else { return }
        themeStore.save(palette)
        themePaletteID = palette
    }

    func triggerSuccessFeedback() {
        guard session.mode == .lock || session.mode == .play, !storageFailed else { return }
        nextFeedbackID += 1
        let id = nextFeedbackID
        successFeedbackID = id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if successFeedbackID == id { successFeedbackID = nil }
        }
    }

    private var budgetCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    func remainingViewingBudget(at date: Date) -> TimeInterval {
        guard let state = session.snapshot.reward else { return 0 }
        var ledger = RewardLedger(state: state)
        ledger.normalizeAfterLoad(now: date, calendar: budgetCalendar)
        return ledger.availableViewingSeconds(now: date, calendar: budgetCalendar)
    }

    func addAllowlistedVideo() {
        guard session.mode == .parent else { return }
        guard let id = YouTubeEmbedURL.extractVideoID(from: parentVideoIDDraft) else {
            playbackMessage = "影片編號無效。 / Invalid video ID."
            return
        }
        let duration = TimeInterval(parentVideoDurationDraft.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        var next = allowlist
        let ok = next.upsert(ApprovedVideo(id: id, durationSeconds: duration > 0 ? duration : 120))
        guard ok else {
            playbackMessage = "影片編號無效。 / Invalid video ID."
            return
        }
        allowlist = next
        allowlistStore.save(next)
        parentVideoIDDraft = ""
        playbackMessage = "已加入准許清單。 / Added to allowlist."
    }

    func removeAllowlistedVideo(id: String) {
        guard session.mode == .parent else { return }
        var next = allowlist
        next.remove(id: id)
        allowlist = next
        allowlistStore.save(next)
        if activePlayVideoID == id {
            activePlayVideoID = nil
        }
    }

    /// Parent-only scaffold: ensure a small viewing budget exists for play-stub demos.
    /// Uses RewardLedger entry unlock or a one-off test completion; does not invent D6.
    func seedTestViewingBudget() {
        guard session.mode == .parent, !storageFailed else { return }
        let now = Date()
        let calendar = budgetCalendar
        update { session in
            var ledger: RewardLedger
            if let state = session.snapshot.reward {
                ledger = RewardLedger(state: state)
                ledger.normalizeAfterLoad(now: now, calendar: calendar)
            } else {
                ledger = RewardLedger(policy: RewardPolicy(
                    initialAllowanceSeconds: 60,
                    rewardCapSeconds: 1_200
                ))
            }
            if !ledger.entryActivityCompleted {
                _ = ledger.completeEntryActivity(now: now, calendar: calendar)
            } else if ledger.availableViewingSeconds(now: now, calendar: calendar) <= 0 {
                _ = ledger.applyCompletion(
                    id: "parent-test-budget",
                    rewardSeconds: 60,
                    kind: .unassisted,
                    now: now,
                    calendar: calendar
                )
            }
            session.replaceRewardState(ledger.exportState())
        }
        playbackMessage = "測試觀看時間已準備。 / Test viewing budget ready."
    }

    func playAllowlisted(id: String) {
        guard !storageFailed else { return }
        guard session.mode == .parent || session.mode == .play else { return }
        let now = Date()
        let isParentPreview = session.mode == .parent
        if isParentPreview {
            if remainingViewingBudget(at: now) <= 0 {
                seedTestViewingBudget()
                guard !storageFailed else { return }
            }
            if session.snapshot.endsAt.map({ $0 <= now }) ?? true {
                update { $0.extendVisaKeepingParent(seconds: 600, now: now) }
                guard !storageFailed else { return }
            }
        }
        let decision = PlaybackPolicy().evaluateStart(
            videoID: id,
            allowlist: allowlist,
            remainingViewingBudgetSeconds: remainingViewingBudget(at: now),
            sessionEndsAt: session.snapshot.endsAt,
            now: now
        )
        guard decision.allowed else {
            activePlayVideoID = nil
            switch decision.stopReason {
            case .notAllowlisted: playbackMessage = "不在准許清單。 / Not allowlisted."
            case .invalidVideoID: playbackMessage = "影片編號無效。 / Invalid video ID."
            case .budgetExhausted: playbackMessage = "觀看時間用完。 / Viewing budget empty."
            case .sessionExpired: playbackMessage = "簽證已到期。 / Visa expired."
            case .navigationRejected: playbackMessage = "禁止導向。 / Navigation blocked."
            case .none: playbackMessage = "未能播放。 / Cannot play."
            }
            return
        }
        activePlayVideoID = id
        playbackMessage = nil
        if isParentPreview { parentDeadline = Date().addingTimeInterval(parentAccessSeconds) }
    }

    func stopScopedPlayback(reason: PlaybackStopReason) {
        activePlayVideoID = nil
        switch reason {
        case .budgetExhausted: playbackMessage = "觀看時間用完，已停止。 / Stopped: budget empty."
        case .sessionExpired: playbackMessage = "簽證到期，已停止。 / Stopped: visa expired."
        case .navigationRejected: playbackMessage = "已阻擋連結。 / Link blocked (D8)."
        default: playbackMessage = "已停止播放。 / Playback stopped."
        }
    }

    func resetStorage() {
        guard session.mode == .parent else { return }
        do {
            let fresh = Snapshot(configured: true)
            try store.save(fresh)
            storageFailed = false
            message = nil
            activePlayVideoID = nil
            playbackMessage = nil
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
    private var parentWindowFrame: NSRect?

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
        NSApp.presentationOptions = child ? [.hideDock, .hideMenuBar, .disableAppleMenu,
            .disableProcessSwitching, .disableForceQuit, .disableSessionTermination, .disableHideApplication] : []
        window.level = child ? .mainMenu + 1 : .normal
        if child {
            if isChildPresentation == false { parentWindowFrame = window.frame }
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.styleMask = [.borderless]
            window.minSize = .zero
            if let screen = window.screen ?? NSScreen.main {
                window.setFrame(screen.frame, display: true)
            }
        } else {
            window.styleMask = [.titled, .miniaturizable, .resizable]
            window.minSize = NSSize(width: 640, height: 480)
            let visible = (window.screen ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
            let preferred = parentWindowFrame?.size ?? NSSize(width: 960, height: 700)
            let size = NSSize(width: min(preferred.width, visible.width),
                              height: min(preferred.height, visible.height))
            let frame = NSRect(x: visible.midX - size.width / 2,
                               y: visible.midY - size.height / 2,
                               width: size.width, height: size.height)
            window.setFrame(frame, display: true)
        }
        isChildPresentation = child
    }

    @objc private func willSleep() { model.returnToChild() }
    @objc private func didWake() { model.tick() }
    @objc private func screenChanged() {
        if !model.session.allowsExit, let screen = window.screen ?? NSScreen.main {
            window.setFrame(screen.frame, display: true)
        }
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
        let theme = ThemePack.forID(model.themePaletteID)
        let accent = Color(rgb: theme.accent)
        let yellow = Color(rgb: theme.yellow)
        ZStack {
            Color(rgb: theme.background).ignoresSafeArea()
            SoftSunRoadAccent(yellow: yellow, accent: accent)
            if model.session.mode == .lock || model.session.mode == .play {
                VehicleParade(color: Color(rgb: theme.watermark), yellow: yellow)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 12)
            }
            VStack(spacing: 32) {
            Text("Visa Games / 簽證遊戲")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("先做再玩 / Do first, then play")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
            Spacer()
            switch model.session.mode {
            case .setup:
                Text("請家長設定 / Parent setup required")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
            case .lock:
                Text("用筆畫 / Draw with your pen")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                Text("準備好未？ / Ready?")
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                Text("遊戲稍後加入 / Activities are coming later")
                    .font(.system(size: 24, design: .rounded))
                Button("泊車示範 / Park-in demo", action: model.triggerSuccessFeedback)
                    .tint(yellow)
            case .play:
                Text("簽證時間 / Visa time")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("\(model.session.remaining(at: model.now)) 秒 / seconds")
                    .font(.system(size: 72, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(yellow)
                Text(String(format: "觀看剩餘 %.0f 秒 / Viewing left %.0f s",
                             model.remainingViewingBudget(at: model.now),
                             model.remainingViewingBudget(at: model.now)))
                    .font(.system(size: 22, design: .rounded))
                if let videoID = model.activePlayVideoID {
                    ScopedPlayerView(videoID: videoID) {
                        model.stopScopedPlayback(reason: .navigationRejected)
                    }
                    .frame(minHeight: 280, maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if let first = model.allowlist.videos.first {
                    ScopedPlayerPlaceholder(
                        message: "準備准許影片 / Ready for allowlisted video",
                        yellow: yellow
                    )
                    Button("播放准許影片 / Play allowlisted") {
                        model.playAllowlisted(id: first.id)
                    }
                    .tint(yellow)
                } else {
                    ScopedPlayerPlaceholder(
                        message: "未有准許影片，請家長加入。 / No allowlisted video yet.",
                        yellow: yellow
                    )
                }
            case .parent:
                ScrollView {
                    VStack(spacing: 20) {
                    Text("家長設定 / Parent controls")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text("十分鐘後自動鎖定 / Locks automatically after ten minutes")
                        .font(.system(size: 22, design: .rounded))
                    Picker("主題 / Theme", selection: Binding(
                        get: { model.themePaletteID },
                        set: { model.selectTheme($0) }
                    )) {
                        ForEach(ThemePaletteID.allCases, id: \.self) { palette in
                            Text(ThemePack.forID(palette).parentLabel).tag(palette)
                        }
                    }
                    .frame(maxWidth: 520)
                    if !model.session.snapshot.configured {
                        Button("完成設定 / Finish setup", action: model.setup)
                            .tint(yellow)
                    } else {
                        Button("測試一分鐘簽證 / Test 1-minute visa", action: model.grant)
                            .tint(yellow)
                        Button("測試觀看時間 / Test viewing budget", action: model.seedTestViewingBudget)
                            .tint(yellow)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("准許影片清單（僅家長） / Allowlist (parent only)")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        TextField("YouTube 網址或影片編號 / YouTube URL or video ID", text: $model.parentVideoIDDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 520)
                        TextField("片長秒數 / Duration seconds", text: $model.parentVideoDurationDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                        HStack(spacing: 16) {
                            Button("加入准許清單 / Add to allowlist", action: model.addAllowlistedVideo)
                                .tint(yellow)
                            if let first = model.allowlist.videos.first {
                                Button("試播准許影片 / Preview allowlisted") {
                                    model.playAllowlisted(id: first.id)
                                }
                                .tint(yellow)
                            }
                        }
                        ForEach(model.allowlist.videos) { video in
                            HStack {
                                Text(video.parentLabel)
                                    .font(.system(size: 18, design: .rounded))
                                Spacer()
                                Button("播放 / Play") { model.playAllowlisted(id: video.id) }
                                    .tint(yellow)
                                Button("移除 / Remove") { model.removeAllowlistedVideo(id: video.id) }
                                    .tint(accent)
                            }
                            .frame(maxWidth: 640)
                        }
                        if model.allowlist.videos.isEmpty {
                            Text("尚未加入影片。 / No videos yet.")
                                .font(.system(size: 18, design: .rounded))
                        }
                        if let videoID = model.activePlayVideoID {
                            ScopedPlayerView(videoID: videoID) {
                                model.stopScopedPlayback(reason: .navigationRejected)
                            }
                            .frame(minHeight: 220, maxHeight: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    if let playbackMessage = model.playbackMessage {
                        Text(playbackMessage)
                            .font(.system(size: 20, design: .rounded))
                            .foregroundStyle(yellow)
                    }
                    Button("返回 / Return", action: model.returnToChild)
                        .tint(accent)
                    if model.message != nil {
                        Button("清除簽證及重設儲存 / Clear visa and reset storage", action: model.resetStorage)
                            .tint(accent)
                    }
                    Button("離開程式 / Quit app") { NSApp.terminate(nil) }
                        .tint(accent)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if let message = model.message {
                Text(message).foregroundStyle(yellow)
                    .font(.system(size: 22, design: .rounded))
            }
            Spacer()
            if model.session.mode != .parent {
                Button("家長 / Parent", action: model.unlock)
                    .disabled(model.authenticating)
                    .tint(accent)
            }
            Text("v0.3.2").font(.system(size: 16, design: .rounded))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(56)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color(rgb: theme.foreground))
            if let id = model.successFeedbackID,
               model.session.mode == .lock || model.session.mode == .play {
                SuccessParkAnimation(color: accent, yellow: yellow)
                    .id(id)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 28)
            }
        }
    }
}
