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
    /// Optional advanced override — happy path uses oEmbed title (not required).
    @Published var parentVideoTitleDraft = ""
    /// Optional advanced override for D4 budget-fit seconds. Default 120 when empty/invalid.
    @Published var parentVideoDurationDraft = "120"
    @Published var showAllowlistAdvanced = false
    @Published private(set) var isFetchingAllowlistMetadata = false
    @Published private(set) var activePlayVideoID: String?
    @Published private(set) var playbackMessage: String?
    @Published private(set) var entryRetryMessage: String?
    @Published private(set) var entryHintUsed = false
    @Published private(set) var taskRoundOpen = false
    @Published private(set) var selectedStars: Int?
    @Published private(set) var activeActivityKind: ActivityKind?
    var targetVisaMinutes: Int? { selectedStars.flatMap { ChildDifficulty(rawValue: $0) }?.minutes }
    private var roundCompletionID: String?
    private var twoPictureQuestion = ActivityCatalog.twoPictureQuestion()
    private var findSameQuestion = ActivityCatalog.findSameQuestion()
    private var countQuestion = ActivityCatalog.countQuestion()
    private var sequenceQuestion = ActivityCatalog.sequenceQuestion()
    @Published private(set) var sequenceTappedAssetIDs: [String] = []
    private let activityEvaluator = ActivityEvaluator()
    private let activityAudio: ActivityAudioPrompting = StubActivityAudioPrompt()
    private let store: SnapshotStore
    private let themeStore = ThemePreferenceStore()
    private let allowlistStore = VideoAllowlistStore()
    private let shuffleStore = VideoPlaybackShuffleStore()
    private var playbackShuffle = VideoPlaybackShuffle()
    private var nextFeedbackID = 0
    private var storageFailed = false
    private var authentication: LAContext?
    private var parentDeadline: Date?
    private let parentAccessSeconds: TimeInterval = 600
    var changed: (() -> Void)?

    init() {
        themePaletteID = ThemePreferenceStore().load()
        allowlist = VideoAllowlistStore().load()
        playbackShuffle = VideoPlaybackShuffleStore().load()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = SnapshotStore(url: directory.appendingPathComponent("VisaGames/state.json"))
        do {
            session = Session(snapshot: try store.load(), now: Date())
        } catch {
            session = Session(snapshot: Snapshot(configured: true), now: Date())
            storageFailed = true
            message = "儲存資料有問題，請家長處理。 / Storage needs parent attention."
            VisaGamesLog.append("storage load FAILED — 載入失敗 storageFailed=true")
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
                VisaGamesLog.append("storage save FAILED — 儲存失敗 storageFailed=true")
                session = Session(snapshot: Snapshot(configured: true), now: Date())
                resetTaskRound()
                changed?()
                return
            }
        }
        let visaEnded = session.snapshot.endsAt != nil && next.snapshot.endsAt == nil
        session = next
        if visaEnded { resetTaskRound() }
        changed?()
    }

    func tick() {
        now = Date()
        let current = now
        let modeBefore = session.mode
        update { $0.tick(now: current) }
        if session.mode != modeBefore {
            VisaGamesLog.append("mode change — 模式變更 \(modeBefore) → \(session.mode) via tick")
            logShellBranch(context: "tick")
        }
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
            VisaGamesLog.append("mode → parent — 進入家長模式")
            logShellBranch(context: "enterParent")
        }
    }

    func returnToChild() {
        let beforeMode = session.mode
        let beforeEntry = isEntryActivityCompleted
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
        VisaGamesLog.append(
            "returnToChild — 返回兒童 beforeMode=\(beforeMode) afterMode=\(session.mode) entryBefore=\(beforeEntry) entryAfter=\(isEntryActivityCompleted) rewardNil=\(session.snapshot.reward == nil)"
        )
        logShellBranch(context: "returnToChild")
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

    /// Whether the first entry activity has unlocked today's / current ledger entry flag.
    var isEntryActivityCompleted: Bool {
        session.snapshot.reward?.entryActivityCompleted == true
    }

    var currentTwoPictureQuestion: TwoPictureQuestion { twoPictureQuestion }
    var currentFindSameQuestion: FindSameQuestion { findSameQuestion }
    var currentCountQuestion: CountQuestion { countQuestion }
    var currentSequenceQuestion: SequenceQuestion { sequenceQuestion }

    func selectDifficulty(stars: Int) {
        guard !storageFailed, session.mode == .lock, !taskRoundOpen,
              ChildDifficulty(rawValue: stars) != nil else { return }
        resetTaskRound()
        selectedStars = stars
        let seed = UUID().uuidString
        roundCompletionID = seed
        let kind = ActivityCatalog.kind(forRoundSeed: seed)
        activeActivityKind = kind
        // Refresh catalog payloads each round (stable templates today; seam for future variants).
        twoPictureQuestion = ActivityCatalog.twoPictureQuestion()
        findSameQuestion = ActivityCatalog.findSameQuestion()
        countQuestion = ActivityCatalog.countQuestion()
        sequenceQuestion = ActivityCatalog.sequenceQuestion()
        sequenceTappedAssetIDs = []
        taskRoundOpen = true
        VisaGamesLog.append("selectDifficulty — 選擇難度 stars=\(stars) kind=\(kind.rawValue) seed=\(seed)")
    }

    private func resetTaskRound() {
        taskRoundOpen = false
        selectedStars = nil
        roundCompletionID = nil
        activeActivityKind = nil
        entryHintUsed = false
        entryRetryMessage = nil
        activePlayVideoID = nil
        playbackMessage = nil
        successFeedbackID = nil
        sequenceTappedAssetIDs = []
    }

    func useEntryHint() {
        guard session.mode == .lock, taskRoundOpen, let kind = activeActivityKind else { return }
        entryHintUsed = true
        entryRetryMessage = ActivityCatalog.hintTraditionalChinese(for: kind)
    }

    func speakEntryPrompt() {
        guard session.mode == .lock, taskRoundOpen, let kind = activeActivityKind else { return }
        // Scaffold only — StubActivityAudioPrompt; reviewed Cantonese pack waits on D9.
        let zh: String
        let en: String
        switch kind {
        case .twoPictureChoose:
            zh = twoPictureQuestion.promptTraditionalChinese
            en = twoPictureQuestion.promptEnglish
        case .findTheSame:
            zh = findSameQuestion.promptTraditionalChinese
            en = findSameQuestion.promptEnglish
        case .countVehicles:
            zh = countQuestion.promptTraditionalChinese
            en = countQuestion.promptEnglish
        case .sequenceShortToLong:
            zh = ActivityCatalog.sequenceStubQuestion().promptTraditionalChinese
            en = ActivityCatalog.sequenceStubQuestion().promptEnglish
        }
        activityAudio.speakPrompt(traditionalChinese: zh, english: en)
        entryRetryMessage = "粵語錄音稍後加入（等 D9）。 / Cantonese audio later (waiting on D9)."
    }

    func selectEntryOption(id: String) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .twoPictureChoose else { return }
        guard !storageFailed else {
            VisaGamesLog.append("selectEntryOption blocked — 已封鎖 storageFailed=true id=\(id)")
            return
        }
        let evaluation = activityEvaluator.evaluate(
            question: twoPictureQuestion,
            selectedOptionID: id,
            hintUsed: entryHintUsed
        )
        handleEvaluation(evaluation, selectionLabel: id)
    }

    func selectFindSameOption(id: String) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .findTheSame else { return }
        guard !storageFailed else {
            VisaGamesLog.append("selectFindSameOption blocked — 已封鎖 storageFailed=true id=\(id)")
            return
        }
        let evaluation = activityEvaluator.evaluate(
            question: findSameQuestion,
            selectedOptionID: id,
            hintUsed: entryHintUsed
        )
        handleEvaluation(evaluation, selectionLabel: id)
    }

    func selectCountChoice(_ count: Int) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .countVehicles else { return }
        guard !storageFailed else {
            VisaGamesLog.append("selectCountChoice blocked — 已封鎖 storageFailed=true count=\(count)")
            return
        }
        let evaluation = activityEvaluator.evaluate(
            question: countQuestion,
            selectedCount: count,
            hintUsed: entryHintUsed
        )
        handleEvaluation(evaluation, selectionLabel: "count-\(count)")
    }

    func selectSequenceAsset(id assetID: String) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .sequenceShortToLong else { return }
        guard !storageFailed else {
            VisaGamesLog.append("selectSequenceAsset blocked — 已封鎖 storageFailed=true asset=\(assetID)")
            return
        }
        guard !sequenceTappedAssetIDs.contains(assetID) else { return }
        let expected = activityEvaluator.nextExpectedAssetID(
            question: sequenceQuestion,
            tappedSoFar: sequenceTappedAssetIDs
        )
        if expected != assetID {
            sequenceTappedAssetIDs = []
            handleEvaluation(.incorrect, selectionLabel: "seq-\(assetID)")
            return
        }
        sequenceTappedAssetIDs.append(assetID)
        if sequenceTappedAssetIDs.count == sequenceQuestion.orderedAssetIDs.count {
            let evaluation = activityEvaluator.evaluate(
                question: sequenceQuestion,
                orderedSelectionIDs: sequenceTappedAssetIDs,
                hintUsed: entryHintUsed
            )
            handleEvaluation(evaluation, selectionLabel: "seq-complete")
        } else {
            entryRetryMessage = "好！下一架～ / Good! Next one~"
            VisaGamesLog.append("sequence progress — 車隊進度 count=\(sequenceTappedAssetIDs.count)")
        }
    }

    private func handleEvaluation(_ evaluation: ActivityEvaluation, selectionLabel: String) {
        switch evaluation {
        case .incorrect:
            entryRetryMessage = "再試一次，得嘅。 / Try again — you can do it."
            VisaGamesLog.append("activity incorrect — 答錯 selection=\(selectionLabel) kind=\(activeActivityKind?.rawValue ?? "nil") hintUsed=\(entryHintUsed)")
        case .correct(let assisted):
            VisaGamesLog.append("activity correct — 答對 selection=\(selectionLabel) kind=\(activeActivityKind?.rawValue ?? "nil") assisted=\(assisted)")
            applyEntrySuccess(assisted: assisted)
        }
    }

    private func applyEntrySuccess(assisted: Bool) {
        let now = Date()
        let calendar = budgetCalendar
        guard taskRoundOpen, session.mode == .lock,
              let stars = selectedStars, let difficulty = ChildDifficulty(rawValue: stars),
              let completionID = roundCompletionID else { return }
        let kind: SuccessKind = assisted ? .assisted : .unassisted
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
            _ = ledger.completeEntryActivity(now: now, calendar: calendar)
            // Each round records D7 and banks viewing time subject to the existing cap.
            _ = ledger.applyCompletion(
                id: completionID,
                rewardSeconds: difficulty.seconds,
                kind: kind,
                now: now,
                calendar: calendar
            )
            session.replaceRewardState(ledger.exportState())
            session.startPlayVisa(seconds: difficulty.seconds, now: now)
        }
        guard !storageFailed, session.mode == .play else { return }
        taskRoundOpen = false
        entryRetryMessage = nil
        triggerSuccessFeedback()
        VisaGamesLog.append(
            "applyEntrySuccess — 入口成功 assisted=\(assisted) entryCompleted=\(isEntryActivityCompleted) viewing=\(remainingViewingBudget(at: Date())) mode=\(session.mode)"
        )
        logShellBranch(context: "applyEntrySuccess")
        // Play path: active visa + shuffled allowlisted video via existing PlaybackPolicy.
        if session.mode == .play, remainingViewingBudget(at: Date()) > 0,
           let id = nextShuffledAllowlistedVideoID() {
            playAllowlisted(id: id)
        }
    }

    func addAllowlistedVideo() {
        guard session.mode == .parent else { return }
        guard !isFetchingAllowlistMetadata else { return }
        guard let id = YouTubeEmbedURL.extractVideoID(from: parentVideoIDDraft) else {
            playbackMessage = "影片編號無效。 / Invalid video ID."
            return
        }
        let durationParsed = TimeInterval(parentVideoDurationDraft.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let durationSeconds: TimeInterval = durationParsed > 0 ? durationParsed : 120
        let titleOverride = parentVideoTitleDraft
        let overrideFields = Self.parentTitleFields(from: titleOverride)

        isFetchingAllowlistMetadata = true
        playbackMessage = "正在取得片名… / Fetching title…"

        Task { @MainActor in
            defer { self.isFetchingAllowlistMetadata = false }

            var titleEnglish = overrideFields.0
            var titleCantonese = overrideFields.1
            let hasOverride = titleEnglish != nil || titleCantonese != nil

            if !hasOverride, let oembedURL = YouTubeOEmbed.requestURL(videoID: id) {
                do {
                    let (data, response) = try await URLSession.shared.data(from: oembedURL)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    if (200..<300).contains(status),
                       let parsed = YouTubeOEmbed.parse(data),
                       let fetched = parsed.title {
                        let fields = Self.parentTitleFields(from: fetched)
                        titleEnglish = fields.0
                        titleCantonese = fields.1
                    }
                } catch {
                    // oEmbed failed — still allow add with id + optional override + thumb from id.
                }
            }

            var next = self.allowlist
            let ok = next.upsert(ApprovedVideo(
                id: id,
                titleEnglish: titleEnglish,
                titleCantonese: titleCantonese,
                durationSeconds: durationSeconds
            ))
            guard ok else {
                self.playbackMessage = "影片編號無效。 / Invalid video ID."
                return
            }
            self.allowlist = next
            self.allowlistStore.save(next)
            self.parentVideoIDDraft = ""
            self.parentVideoTitleDraft = ""
            self.parentVideoDurationDraft = "120"
            self.showAllowlistAdvanced = false
            if hasOverride {
                self.playbackMessage = "已加入准許清單（使用進階標題）。 / Added to allowlist (Advanced title)."
            } else if titleEnglish != nil || titleCantonese != nil {
                self.playbackMessage = "已加入准許清單（已取得片名）。 / Added to allowlist (title fetched)."
            } else {
                self.playbackMessage = "已加入准許清單（未能取得片名，可於進階手動填）。 / Added (title unavailable — optional Advanced edit)."
            }
        }
    }

    /// One parent-facing title draft → existing ApprovedVideo title fields.
    /// CJK → titleCantonese; otherwise titleEnglish; empty → both nil.
    private static func parentTitleFields(from draft: String) -> (String?, String?) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }
        if trimmed.unicodeScalars.contains(where: Self.containsCJKScalar) {
            return (nil, trimmed)
        }
        return (trimmed, nil)
    }

    private static func containsCJKScalar(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        switch value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x3000...0x303F, 0xFF00...0xFFEF:
            return true
        default:
            return false
        }
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
    /// Grants via applyCompletion only — never marks entryActivityCompleted (child UAT needs the game).
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
            // Parent preview / Test viewing budget must leave entryActivityCompleted == false
            // Round UI is independent of this durable D1 flag.
            if ledger.availableViewingSeconds(now: now, calendar: calendar) <= 0 {
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
        VisaGamesLog.append(
            "seedTestViewingBudget — 測試觀看時間 entryCompleted=\(isEntryActivityCompleted) viewing=\(remainingViewingBudget(at: Date())) rewardNil=\(session.snapshot.reward == nil)"
        )
        logShellBranch(context: "seedTestViewingBudget")
    }

    /// Parent-only UAT: clear entryActivityCompleted so the child two-picture game returns.
    /// Keeps remaining viewing budget and awards when a ledger already exists.
    /// If reward state is nil, creates an empty ledger with entryActivityCompleted=false and persists it.
    func resetEntryActivityForChildUAT() {
        guard session.mode == .parent else {
            VisaGamesLog.append("resetEntryActivity blocked — 非家長模式 mode=\(session.mode)")
            return
        }
        guard !storageFailed else {
            VisaGamesLog.append("resetEntryActivity blocked — 儲存失敗 storageFailed=true")
            return
        }
        let beforeCompleted = isEntryActivityCompleted
        let beforeNil = session.snapshot.reward == nil
        VisaGamesLog.append(
            "resetEntryActivity before — 重設前 entryCompleted=\(beforeCompleted) rewardNil=\(beforeNil) mode=\(session.mode)"
        )
        update { session in
            var ledger: RewardLedger
            if let state = session.snapshot.reward {
                ledger = RewardLedger(state: state)
                ledger.resetEntryActivityForParentUAT()
            } else {
                // Nil reward must still show EntryActivityView; persist empty incomplete ledger
                // so subsequent reads are consistent after Reset + Return.
                ledger = RewardLedger(policy: RewardPolicy(
                    initialAllowanceSeconds: 60,
                    rewardCapSeconds: 1_200
                ))
                // Fresh ledger already has entryActivityCompleted == false.
            }
            session.replaceRewardState(ledger.exportState())
        }
        resetTaskRound()
        // Force ObservableObject subscribers to refresh derived entry UI even if other fields look similar.
        objectWillChange.send()
        playbackMessage = "入口活動已重設（兒童 UAT）。 / Entry activity reset (child UAT)."
        VisaGamesLog.append(
            "resetEntryActivity after — 重設後 entryCompleted=\(isEntryActivityCompleted) rewardNil=\(session.snapshot.reward == nil) createdFromNil=\(beforeNil)"
        )
        logShellBranch(context: "resetEntryActivity")
    }

    /// Log which ShellView branch the child/parent UI should take (Traditional Chinese + English).
    func logShellBranch(context: String) {
        let branch: String
        switch session.mode {
        case .setup:
            branch = "setup"
        case .parent:
            branch = "parent"
        case .lock:
            branch = taskRoundOpen ? "lock-task" : "lock-cards"
        case .play:
            branch = "play-ready"
        }
        VisaGamesLog.append(
            "shell branch=\(branch) — 介面分支 mode=\(session.mode) entryCompleted=\(isEntryActivityCompleted) rewardNil=\(session.snapshot.reward == nil) storageFailed=\(storageFailed) ctx=\(context)"
        )
    }

    /// Child path: next allowlisted id in shuffled order (reshuffle when exhausted; no immediate repeat if count > 1).
    func nextShuffledAllowlistedVideoID() -> String? {
        var rng = SystemRandomNumberGenerator()
        let ids = allowlist.videos.map(\.id)
        let picked = playbackShuffle.nextVideoID(from: ids, using: &rng)
        shuffleStore.save(playbackShuffle)
        if let picked {
            VisaGamesLog.append("shuffle pick — 隨機選片 id=\(picked) remaining=\(playbackShuffle.remainingIDs.count)")
        }
        return picked
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

    /// Parent-only: reveal the active ScopedPlayer log directory in Finder.
    func openScopedPlayerLogsFolder() {
        guard session.mode == .parent else { return }
        VisaGamesLog.openActiveDirectory()
        let path = VisaGamesLog.activeLogDirectory.path
        playbackMessage = "日誌資料夾已開啟。 / Logs folder opened.\n" + path
        VisaGamesLog.append("openLogsFolder — 開啟日誌 path=\(path)")
    }

    func resetStorage() {
        guard session.mode == .parent else { return }
        do {
            let fresh = Snapshot(configured: true)
            try store.save(fresh)
            storageFailed = false
            message = nil
            resetTaskRound()
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
            let preferred = parentWindowFrame?.size ?? NSSize(width: 960, height: 800)
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

    /// Child content needs room for large task targets and the scoped player.
    private var usesCompactShell: Bool {
        model.session.mode == .lock || model.session.mode == .play
    }

    var body: some View {
        let theme = ThemePack.forID(model.themePaletteID)
        let accent = Color(rgb: theme.accent)
        let yellow = Color(rgb: theme.yellow)
        let sand = Color(rgb: theme.sand)
        ZStack {
            StorybookWorldBackground(theme: theme)
            SoftSunRoadAccent(yellow: yellow, accent: accent)
            if model.session.mode == .lock || model.session.mode == .play {
                VehicleParade(color: Color(rgb: theme.watermark), yellow: yellow)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
            VStack(spacing: usesCompactShell ? 14 : 28) {
                if model.session.mode == .lock || model.session.mode == .play {
                    WoodenStationSign(
                        title: "簽證車廠 / Visa Depot",
                        subtitle: "先做再玩 / Do first, then play",
                        foreground: Color(rgb: theme.foreground),
                        yellow: yellow,
                        sand: sand
                    )
                } else {
                    Text("Visa Games / 簽證遊戲")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("先做再玩 / Do first, then play")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                }
                if !usesCompactShell {
                    Spacer(minLength: 8)
                }
                modeContent(theme: theme, accent: accent, yellow: yellow, sand: sand)
                    .layoutPriority(1)
                if let message = model.message {
                    Text(message).foregroundStyle(accent)
                        .font(.system(size: 22, design: .rounded))
                }
                if !usesCompactShell {
                    Spacer(minLength: 8)
                }
                if model.session.mode != .parent {
                    Button("家長 / Parent", action: model.unlock)
                        .disabled(model.authenticating)
                        .tint(accent)
                }
                Text("v0.7.4").font(.system(size: 16, design: .rounded))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(usesCompactShell ? 24 : 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color(rgb: theme.foreground))
            if let id = model.successFeedbackID,
               model.session.mode == .lock || model.session.mode == .play {
                SuccessParkAnimation(color: accent, yellow: yellow)
                    .id(id)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            model.logShellBranch(context: "shellAppear")
        }
    }

    @ViewBuilder
    private func modeContent(theme: ThemePack, accent: Color, yellow: Color, sand: Color) -> some View {
        switch model.session.mode {
        case .setup:
            Text("請家長設定 / Parent setup required")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
        case .lock:
            if model.taskRoundOpen {
                entryGateContent(theme: theme, accent: accent, yellow: yellow, sand: sand)
            } else {
                DifficultyCardsView(
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    onSelect: model.selectDifficulty
                )
            }
        case .play:
            VStack(spacing: 12) {
                Text("簽證時間 / Visa time: \(model.session.remaining(at: model.now)) 秒 / seconds")
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(yellow)
                if let videoID = model.activePlayVideoID {
                    ScopedPlayerView(videoID: videoID) {
                        model.stopScopedPlayback(reason: .navigationRejected)
                    }
                    .frame(minHeight: 360, maxHeight: 900)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if !model.allowlist.videos.isEmpty {
                    Button("播放准許影片 / Play allowlisted") {
                        if let id = model.nextShuffledAllowlistedVideoID() {
                            model.playAllowlisted(id: id)
                        }
                    }
                    .tint(yellow)
                } else {
                    Text("簽證已開始，請家長加入准許影片。 / Visa running. Ask a parent to add a video.")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                }
                if let message = model.playbackMessage {
                    Text(message).font(.system(size: 22, design: .rounded))
                }
            }
        case .parent:
            ScrollView {
                VStack(spacing: 20) {
                    Text("家長設定 / Parent controls")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text("十分鐘後自動鎖定 / Locks automatically after ten minutes")
                        .font(.system(size: 22, design: .rounded))
                    Text("入口遊戲已開（兩圖／搵相同／數車／車隊排序）。YouTube 內容包仍待家長 D9 審核。 / Entry games live (two-picture / find-same / count / convoy order). YouTube pack still parent D9.")
                        .font(.system(size: 18, design: .rounded))
                        .foregroundStyle(accent)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 640)
                    ParentLicenseFooter()
                        .frame(maxWidth: 720)
                    Button("重設入口活動（兒童 UAT）/ Reset entry activity (child UAT)", action: model.resetEntryActivityForChildUAT)
                        .tint(yellow)
                    // Immediate confirmation under Reset so parent UAT does not require scrolling.
                    if let playbackMessage = model.playbackMessage {
                        Text(playbackMessage)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(yellow)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 640)
                    }
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
                        Text("貼上網址或編號即可加入；片名與預覽圖會自動取得。 / Paste URL or ID to add — title and preview auto-fill.")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 640, alignment: .leading)
                        TextField("YouTube 網址或影片編號 / YouTube URL or video ID", text: $model.parentVideoIDDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 520)
                            .disabled(model.isFetchingAllowlistMetadata)
                        HStack(spacing: 16) {
                            Button("加入准許清單 / Add to allowlist", action: model.addAllowlistedVideo)
                                .tint(yellow)
                                .disabled(model.isFetchingAllowlistMetadata)
                            if let first = model.allowlist.videos.first {
                                Button("試播准許影片 / Preview allowlisted") {
                                    model.playAllowlisted(id: first.id)
                                }
                                .tint(yellow)
                            }
                        }
                        DisclosureGroup(isExpanded: $model.showAllowlistAdvanced) {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("標題覆寫（可選） / Title override (optional)", text: $model.parentVideoTitleDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 520)
                                    .disabled(model.isFetchingAllowlistMetadata)
                                TextField("片長秒數（觀看預算） / Duration seconds (viewing budget)", text: $model.parentVideoDurationDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 320)
                                    .disabled(model.isFetchingAllowlistMetadata)
                                Text("片長用於觀看預算；預設 120 秒；可手動改／YouTube oEmbed 無提供時長。 / Duration is for viewing-budget fit (not live player length); default 120s; editable — oEmbed has no duration.")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: 640, alignment: .leading)
                            }
                            .padding(.top, 4)
                        } label: {
                            Text("進階（可選） / Advanced (optional)")
                                .font(.system(size: 16, design: .rounded))
                        }
                        .frame(maxWidth: 640)
                        ForEach(model.allowlist.videos) { video in
                            HStack(alignment: .center, spacing: 12) {
                                AllowlistVideoThumbnail(videoID: video.id)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(video.parentListTitle)
                                        .font(.system(size: 18, design: .rounded))
                                    Text(video.id)
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
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
                            .frame(minHeight: 420, maxHeight: 720)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    Button("開啟日誌資料夾 / Open logs folder", action: model.openScopedPlayerLogsFolder)
                        .tint(yellow)
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
    }

    /// Direct activity gate (v0.4.1 proven layout). Do not wrap in unbounded-height ScrollView
    /// inside the parent VStack — that collapses to ~0 height and hides the targets (v0.4.2 regression).
    @ViewBuilder
    private func entryGateContent(theme: ThemePack, accent: Color, yellow: Color, sand: Color) -> some View {
        Group {
            switch model.activeActivityKind {
            case .findTheSame:
                FindSameActivityView(
                    question: model.currentFindSameQuestion,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    onSelect: { model.selectFindSameOption(id: $0) },
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
                )
            case .countVehicles:
                CountActivityView(
                    question: model.currentCountQuestion,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    onSelectCount: { model.selectCountChoice($0) },
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
                )
            case .sequenceShortToLong:
                SequenceActivityView(
                    question: model.currentSequenceQuestion,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    tappedAssetIDs: model.sequenceTappedAssetIDs,
                    onTapAsset: { model.selectSequenceAsset(id: $0) },
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
                )
            case .twoPictureChoose, .none:
                EntryActivityView(
                    question: model.currentTwoPictureQuestion,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    onSelect: { model.selectEntryOption(id: $0) },
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 480, alignment: .top)
        .layoutPriority(1)
    }
}


/// Parent-visible home-use + original-art license note (HK Trad + English).
/// Names third-party companies only here for non-affiliation clarity — never on the child path.
private struct ParentLicenseFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("關於插圖／版權說明 / About artwork & license")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text("本應用程式僅作家中教育用途。畫面上嘅插圖同友善車輛角色均為原創作品，並非任何第三方商標角色。本應用程式與 Takara Tomy、HIT Entertainment、Mattel 或其他玩具／動畫品牌無關，亦無授權關係。家中免責聲明並不授予使用第三方角色肖像嘅權利。")
                .font(.system(size: 14, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Text("This app is for home educational use. On-screen art and friendly vehicle characters are original works, not third-party trademark characters. Visa Games is not affiliated with Takara Tomy, HIT Entertainment, Mattel, or other toy/animation brands. A home-use disclaimer does not grant rights to use third-party character likenesses.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .accessibilityLabel("Artwork and license notice")
    }
}



/// Parent allowlist row preview: YouTube thumbnail CDN via AsyncImage.
/// Network failure / invalid id → placeholder (never crash). Not child playback.
private struct AllowlistVideoThumbnail: View {
    let videoID: String
    private let width: CGFloat = 96
    private let height: CGFloat = 54

    var body: some View {
        Group {
            if let url = YouTubeEmbedURL.thumbnailURL(videoID: videoID) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholder
                    case .empty:
                        ZStack {
                            placeholderBackground
                            ProgressView()
                                .controlSize(.small)
                        }
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel("預覽圖 / Preview")
    }

    private var placeholder: some View {
        ZStack {
            placeholderBackground
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
        }
    }

    private var placeholderBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.secondary.opacity(0.18))
    }
}
