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
    /// Which games each star may deal. UserDefaults, not the reward snapshot.
    @Published private(set) var gameAssignment = MissionGameAssignment.defaults
    /// Shown when the parent tries to turn off the last game on a star.
    @Published private(set) var gameAssignmentBanner: String?
    /// Playtest cover. Nil unless a parent is reviewing a game. Never a child round.
    @Published private(set) var playtestKind: ActivityKind?
    /// Card to mark sunny after 返回家長.
    @Published private(set) var playtestHighlightedKind: ActivityKind?
    @Published private(set) var playtestHintUsed = false
    @Published private(set) var playtestMissCount = 0
    @Published private(set) var playtestLastIncorrectID: String?
    @Published private(set) var playtestLastCorrectID: String?
    @Published private(set) var playtestCompleted = false
    /// Local fuel copy so the board gauge can be reviewed. Discarded. Starts at 5.
    @Published private(set) var playtestPendingMinutes = 5
    @Published private(set) var playtestStartingMinutes = 5
    @Published private(set) var playtestThinkRemaining = 0
    @Published private(set) var playtestFuelMessage: String?
    @Published private(set) var playtestSequenceTaps: [String] = []
    /// New UUID each playtest. Choice order is a function of this, not the catalog id.
    @Published private(set) var playtestChoiceDealSeed = ""
    /// v0.22.0: question tier of this playtest. Each 試玩 of a kind walks L1 → L2 → L3
    /// (memory only), so a parent can review every tier without a ticket.
    @Published private(set) var playtestLevel: ActivityLevel = .l1
    private var playtestNextLevel: [ActivityKind: ActivityLevel] = [:]
    /// Playtest copies of the generated questions. Never the child round's questions.
    private var playtestFindSameQuestion = ActivityCatalog.findSameQuestion()
    private var playtestCountQuestion = ActivityCatalog.countQuestion()
    /// v0.23.0 連一連 playtest board (never the child round's board).
    @Published private(set) var playtestLineMatchBoard = LineMatchBoard(question: ActivityCatalog.lineMatchQuestion())
    /// Guided 連一連 playtest board (nil when the playtest kind is free match / 自己配).
    @Published private(set) var playtestLineMatchGuidedBoard: LineMatchGuidedBoard?
    /// v0.25.0 畫線畫形 playtest board (nil unless the playtest kind is a shape-trace card).
    @Published private(set) var playtestShapeTraceBoard: ShapeTraceBoard?
    /// v0.28.0 一架一架數 playtest board (nil unless the playtest kind is a tap-count card).
    @Published private(set) var playtestTapCountBoard: TapCountBoard?
    @Published private(set) var playtestTapLetterBoard: TapLetterBoard?
    private var playtestThinkEndsAt: Date?
    var isParentPlaytest: Bool { playtestKind != nil && session.mode == .parent }
    var playtestChoicesLocked: Bool { playtestThinkEndsAt != nil || playtestCompleted }
    var playtestSequenceHintAssetID: String? {
        activityEvaluator.nextExpectedAssetID(
            question: sequenceQuestion,
            tappedSoFar: playtestSequenceTaps
        )
    }
    /// Parent-only draft for the allowlist text field (never shown on child path).
    @Published var parentVideoIDDraft = "" {
        didSet {
            if parentVideoIDDraft != oldValue { refreshParentDraftPreview() }
        }
    }
    /// Live paste status → preview card before Add (v0.12.0).
    @Published private(set) var parentDraftStatus: ParentAllowlistDraft = .empty
    /// oEmbed title for the pasted id (nil while fetching / unavailable).
    @Published private(set) var parentDraftTitle: String?
    @Published private(set) var isFetchingDraftTitle = false
    /// Parent-session cache so Add reuses the preview fetch instead of a second request.
    private var oEmbedTitleCache: [String: String] = [:]
    private var draftTitleTask: Task<Void, Never>?
    /// Optional advanced override — happy path uses oEmbed title (not required).
    @Published var parentVideoTitleDraft = ""
    /// Optional advanced override for D4 budget-fit seconds. Default 120 when empty/invalid.
    @Published var parentVideoDurationDraft = "120"
    @Published var showAllowlistAdvanced = false
    @Published private(set) var isFetchingAllowlistMetadata = false
    /// v0.27.0 (ADR 0016): full-page in-app YouTube finder over the parent view. Same window,
    /// same kiosk presentation; nothing in AppKit changes when it opens or closes.
    /// v0.27.1: finder flow (confirm card over the finder, stay after add, toast, undo, flash).
    @Published private(set) var parentFinder = ParentFinderState()
    var parentBrowserOpen: Bool { parentFinder.isOpen }
    /// D13: the list scrolls to and flashes this card after the finder closes.
    @Published private(set) var parentFlashVideoID: String?
    @Published private(set) var parentFlashUntil: Date?
    @Published private(set) var parentFlashRequest = 0
    /// 08: oEmbed embeddability of the draft id. Blocked → 加入 greyed out.
    @Published private(set) var parentDraftEmbedCheck: ParentEmbedCheck = .unknown
    private var embedCheckCache: [String: ParentEmbedCheck] = [:]
    /// Duration field value the confirm card started with (Update only after an edit).
    @Published private(set) var parentDraftDurationBaseline = "120"
    @Published private(set) var parentRecentSearches: [String] = []
    /// Length read from the YouTube page for the id handed over by the browser (D4 budget-fit).
    @Published private(set) var parentDraftPageDuration: (videoID: String, seconds: TimeInterval)?
    /// 試播 on the add card: the child's scoped player for a not-yet-added id (parent only).
    @Published private(set) var parentDraftTrialVideoID: String?
    @Published private(set) var activePlayVideoID: String? {
        didSet {
            // D10: every path that clears or swaps the player passes through here.
            if let oldValue, oldValue != activePlayVideoID { perfActivePlayCleared(oldValue) }
        }
    }
    /// Resume offset for the active child load (`start=`). Nil for fresh picks / parent preview.
    @Published private(set) var activePlayStartSeconds: TimeInterval?
    /// Last reported player position for the active child video (in-memory).
    private var lastKnownPlaybackSeconds: TimeInterval?
    @Published private(set) var playbackMessage: String?
    @Published private(set) var entryRetryMessage: String?
    @Published private(set) var entryHintUsed = false
    /// Incorrect taps this round; auto-hint at 2 (D7 assisted) after Think Pause when pending > 0.
    @Published private(set) var entryMissCount = 0
    @Published private(set) var lastIncorrectChoiceID: String? = nil
    @Published private(set) var lastCorrectChoiceID: String? = nil
    @Published private(set) var activityJustCompleted = false
    /// Pending visa minutes for this round (starts at chosen 5/10/15; halved on each miss; floor 0).
    @Published private(set) var pendingAwardMinutes = 0
    /// Ticket minutes when the round opened (fuel gauge denominator).
    @Published private(set) var roundStartingMinutes = 0
    /// Absolute end of the current Think Pause; nil when choices are unlocked.
    private var thinkPauseEndsAt: Date? = nil
    /// Whole seconds remaining on Think Pause (UI countdown). 0 = unlocked.
    @Published private(set) var thinkPauseRemainingSeconds = 0
    /// Earned minutes frozen at success (stamp/watch/road). Stars stay as difficulty chosen.
    @Published private(set) var earnedAwardMinutes = 0
    /// Soft status line after fuel-halve (cleared when pause ends or round resets).
    @Published private(set) var fuelFeedbackMessage: String? = nil
    /// Choices locked during Think Pause (mash ignored).
    var choicesLocked: Bool { thinkPauseEndsAt != nil }
    /// Board 3 stamp gate — visa already running; Go reveals watch UI.
    @Published private(set) var awaitingDeparture = false
    /// Board 5 park-and-sleep after visa expiry.
    @Published private(set) var showTimesUp = false
    @Published private(set) var timesUpTicket: MissionTicket? = nil
    /// v0.21.1: YouTube blocked this embed — show the child board, then picker / Time's up.
    @Published private(set) var showProviderBlocked = false
    /// Videos that failed the bot-check this visa (hidden on the picker).
    @Published private(set) var providerBlockedUnavailableIDs: Set<String> = []
    /// Sticky parent banner after a bot-check (cleared on dismiss / return).
    @Published private(set) var providerBlockedParentHint: String? = nil
    private var providerBlockedState = ProviderBlockedPolicy.CreditState()
    private var providerBlockedLoadStartedAt: Date?
    /// Skip board 5 when the child leaves play early (empty allowlist return).
    private var suppressNextTimesUp = false
    private var almostHomeSpoken = false
    private var playVisaTotalSeconds: TimeInterval = 0
    @Published private(set) var taskRoundOpen = false
    @Published private(set) var selectedStars: Int?
    @Published private(set) var activeActivityKind: ActivityKind?
    var targetVisaMinutes: Int? { selectedStars.flatMap { ChildDifficulty(rawValue: $0) }?.minutes }
    private var roundCompletionID: String?
    private var twoPictureQuestion = ActivityCatalog.twoPictureQuestion()
    private var findSameQuestion = ActivityCatalog.findSameQuestion()
    private var countQuestion = ActivityCatalog.countQuestion()
    /// v0.23.0 連一連 child board: question + unjudged / locked lines + eraser (VisaCore rules).
    @Published private(set) var lineMatchBoard = LineMatchBoard(question: ActivityCatalog.lineMatchQuestion())
    /// Parent 連一連 settings (tolerance, category weights). UserDefaults, not the snapshot.
    @Published private(set) var lineMatchSettings = LineMatchSettings.defaults
    /// Parent-only line when a weight change is refused (last category on).
    @Published private(set) var lineMatchSettingsBanner: String?
    /// Gentle line under the 連一連 board (start from green / not all joined / try Done). Never a miss.
    @Published private(set) var lineMatchNotice: SpokenPrompt?
    private let lineMatchSettingsStore = LineMatchSettingsStore()
    /// Guided 連一連 child board (沿路送 / 沿路過橋). Nil = free match (自己配).
    /// The question is also on `lineMatchBoard`, so prompts / deal facts read one place.
    @Published private(set) var lineMatchGuidedBoard: LineMatchGuidedBoard?
    /// v0.25.0 畫線畫形 child board (畫直線 / 畫形狀 · 跟虛線). Nil on every other kind.
    @Published private(set) var shapeTraceBoard: ShapeTraceBoard?
    /// 畫形狀設定 (shared by the shape-trace cards). UserDefaults, not the snapshot.
    @Published private(set) var shapeTraceSettings = ShapeTraceSettings.defaults
    @Published private(set) var shapeTraceSettingsBanner: String?
    /// Gentle line under the 畫線畫形 board (wrong start / reverse / 停). Never a miss.
    @Published private(set) var shapeTraceNotice: SpokenPrompt?
    /// D11: which cards a parent has played through in 試玩 (stars stay grey until then).
    @Published private(set) var parentPlaytestLog = ParentPlaytestLog()
    private let shapeTraceSettingsStore = ShapeTraceSettingsStore()
    private let parentPlaytestLogStore = ParentPlaytestLogStore()
    /// Strokes ("shape.stroke") whose off-path hint was already spoken (once per stroke).
    private var shapeTraceHintSpoken: Set<String> = []
    /// v0.28.0 一架一架數 child board (點一點 / 數完畫 / 揀啱數). Nil on every other kind.
    @Published private(set) var tapCountBoard: TapCountBoard?
    @Published private(set) var tapLetterWriteRound: TapLetterWriteRound?
    @Published private(set) var tapLetterWriteGuide = "none"
    @Published private(set) var tapLetterWriteDemoStartedAt: Double = 0
    @Published private(set) var tapLetterGuideRun: TapCountGuideRun?
    private var tapLetterGuideSpeechGeneration = 0
    private var letterWriteProgress = LetterWriteProgressStore().load()
    private var tapLetterCuspSpoken = false
    private var tapLetterGlanceReason: StrokeOrderProgress.GlanceReason?
    @Published private(set) var tapLetterBoard: TapLetterBoard?
    @Published private(set) var tapLetterBubble: String?
    private var tapLetterBubbleGeneration = 0
    @Published private(set) var tapLetterCelebrating = false
    @Published private(set) var tapLetterStrokeReveal: StrokeOrderReveal?
    @Published private(set) var tapLetterPlaqueNudge = false
    @Published private(set) var tapLetterFuelBefore = 0
    private var tapLetterSettings = TapLetterSettingsStore().load()
    private var tapLetterProgress = LetterProgressStore().load()
    private var tapLetterDecks = LetterWordDecksStore().load()
    private var tapLetterRoundIndex = LetterRoundIndexStore().load()
    private var tapLetterLastActionAt = Date().timeIntervalSinceReferenceDate
    private var tapLetterRoundStart = Date().timeIntervalSinceReferenceDate
    private var tapLetterIdleSpoken = false
    private var tapLetterPenaltyPending = false
    /// 數字設定 (shared by the 3 tap-count cards). UserDefaults, not the snapshot.
    @Published private(set) var tapCountSettings = TapCountSettings.defaults
    /// Gentle line in the tap-count tray (未揀車喎 / wrong start / 試吓撳 OK). Never a miss.
    @Published private(set) var tapCountNotice: SpokenPrompt?
    /// Fuel before the latest ★★★ halving, for the Think Pause card 「15 → 7 分鐘」.
    @Published private(set) var tapCountFuelBefore = 0
    private let tapCountSettingsStore = TapCountSettingsStore()
    /// Last numerals dealt (memory only; the next deal avoids the last 3, design D3).
    private var tapCountRecentTargets: [Int] = []
    private var tapCountLastScene: TapCountScene?
    /// Strokes whose off-path hint was already spoken (once per stroke).
    private var tapCountTraceHintSpoken: Set<String> = []
    /// Model clock when the current tap-count board appeared (idle nudge / reprompt base).
    private var tapCountRoundStart: Double = 0
    /// v0.30.0 識咗 per numeral (2 clean traces in a row). UserDefaults; a failed save never blocks.
    @Published private(set) var tapCountGuideProgress = TapCountGuideProgress()
    private let tapCountGuideProgressStore = TapCountGuideProgressStore()
    /// v0.31.0 筆順動畫: glances left after 識咗 and the last trace day per numeral (UserDefaults, best effort).
    private(set) var strokeOrderProgress = StrokeOrderProgress()
    private let strokeOrderProgressStore = StrokeOrderProgressStore()
    /// The guidance line in the voice bubble beside the trace board (cue / hop / stall), until a time.
    @Published private(set) var tapCountGuideBubble: TapCountGuideBubble?
    /// Bumped to cancel the demo lines still scheduled (a touch ended the demo, a new round).
    private var tapCountGuideSpeechGeneration = 0
    /// Rows whose off-road hint was already spoken (at most once per road).
    private var guidedHintSpokenRows: Set<Int> = []
    /// Tags + fields of the 完成 being evaluated (consumed by the answer record).
    private var pendingAnswerRecord: (tags: [String], fields: [String: PerfValue])?
    /// v0.22.0: last generated item per kind (memory only). The next deal of that kind avoids it.
    private var lastDealtItem: [ActivityKind: String] = [:]
    private var sequenceQuestion = ActivityCatalog.sequenceQuestion()
    private var halfMatchQuestion = ActivityCatalog.halfMatchQuestion()
    private var shapeCousinQuestion = ActivityCatalog.shapeCousinQuestion()
    private var capacityCompareQuestion = ActivityCatalog.capacityCompareQuestion()
    private var moreFewerQuestion = ActivityCatalog.moreFewerQuestion()
    private var shadowMatchQuestion = ActivityCatalog.shadowMatchQuestion()
    private var emptyBayQuestion = ActivityCatalog.emptyBayQuestion()
    @Published private(set) var sequenceTappedAssetIDs: [String] = []
    /// New UUID each child round (`selectDifficulty`). Not the catalog completion id.
    @Published private(set) var choiceDealSeed = ""
    /// Video-picker visit. Minted when the picker is entered, not in `body` or `onAppear`
    /// (those can run again on the 0.5s `tick()` refresh). Not UserDefaults.
    @Published private(set) var videoPickerOrderSeed = ""
    /// 「出發！」 bay. Minted when the stamp gate opens. Stable until the child taps.
    @Published private(set) var departureDockSeed = ""
    /// 「再揀車票」 bay. Minted when Time's up is shown. Not `choiceDealSeed`
    /// (`resetTaskRound()` clears that seed on the same transition).
    @Published private(set) var timesUpDockSeed = ""
    private let activityEvaluator = ActivityEvaluator()
    /// Canvas guide voice (interim zh-HK system voice, ADR 0007). Also drives activity prompts.
    private let guideVoice = SystemSpeechPrompt()
    private var activityAudio: ActivityAudioPrompting { guideVoice }
    private let store: SnapshotStore
    private let themeStore = ThemePreferenceStore()
    private let allowlistStore = VideoAllowlistStore()
    private let gameAssignmentStore = MissionGameAssignmentStore()
    private let shuffleStore = VideoPlaybackShuffleStore()
    private var playbackShuffle = VideoPlaybackShuffle()
    private var nextFeedbackID = 0
    /// Load failure only (state.json unreadable). Save failures never set this (v0.21.4).
    private var storageFailed = false
    /// Parent-only banner: saves are queued in memory and retried. Never gates the child.
    @Published private(set) var storageSaveWarning: String? = nil
    private lazy var resilientStore = ResilientSnapshotStore { [store] snapshot in try store.save(snapshot) }
    private var authentication: LAContext?
    private var parentDeadline: Date?
    private let parentAccessSeconds: TimeInterval = 600
    /// Not assigned by AppDelegate since v0.21.5 (ADR 0011): kiosk presentation is constant.
    /// Any future AppKit work hung here must be coalesced and deferred with
    /// `DispatchQueue.main.async`, never run inside the model mutation.
    var changed: (() -> Void)?
    /// D10 performance records (v0.20.0). Local, parent-only, never blocks the child flow.
    let perf = PerformanceRecorder()
    /// Parent banner only: 「表現紀錄未能儲存（唔影響小朋友玩）」.
    @Published private(set) var perfWriteFailed = false
    /// Why the next player clear happens (consumed by `perfActivePlayCleared`).
    private var pendingVideoStopReason: PerfVideoStopReason?
    /// Source of the next `playAllowlisted` start (pick / continue). Nil → preview or legacy.
    private var pendingVideoStartSource: String?
    /// Why the next visa end happens (consumed in `update(_:)`).
    private var pendingVisaEndReason: String?
    /// Parent-only status line for export / clear.
    @Published var perfStatusMessage: String?
    /// v0.21 表現 report (parent-only). Computed off-main when the segment opens / 更新.
    @Published private(set) var perfReview: PerfReviewState = .idle
    @Published private(set) var perfReviewWindow: PerfReportWindow = .days30
    private var perfReviewGeneration = 0
    /// Convoy tap context for the answer being evaluated (step, expected asset, tapped before).
    private var pendingSequenceContext: (step: Int, expected: String?, tappedSoFar: [String])?

    init() {
        themePaletteID = ThemePreferenceStore().load()
        allowlist = VideoAllowlistStore().load()
        parentRecentSearches = UserDefaults.standard.stringArray(forKey: ParentYouTubeBrowser.recentSearchesKey) ?? []
        gameAssignment = MissionGameAssignmentStore().load()
        lineMatchSettings = LineMatchSettingsStore().load()
        shapeTraceSettings = ShapeTraceSettingsStore().load()
        tapCountSettings = TapCountSettingsStore().load()
        tapCountGuideProgress = TapCountGuideProgressStore().load()
        strokeOrderProgress = StrokeOrderProgressStore().load()
        parentPlaytestLog = ParentPlaytestLogStore().load()
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
        perf.contextProvider = { [weak self] in
            guard let self else { return PerfRecorderContext(mode: .lock, isPlaytest: false) }
            return PerfRecorderContext(mode: self.session.mode, isPlaytest: self.isParentPlaytest)
        }
        perf.onWriteFailed = { [weak self] in self?.perfWriteFailed = true }
        perf.launch(
            recoveredPlay: session.mode == .play,
            visaEndsAt: session.snapshot.endsAt,
            allowlistIDs: allowlist.videos.map(\.id),
            assignment: gameAssignment
        )
        // Durable endsAt can resume into .play while selectedStars is still nil → legacyShell.
        recoverPlayPresentationAfterLaunch()
    }

    /// Cold start mid-visa: restore stars/timer so canvas Picker/Watch/TimesUp can show.
    private func recoverPlayPresentationAfterLaunch() {
        guard session.mode == .play else { return }
        if selectedStars == nil {
            let records = session.snapshot.reward?.successRecords ?? []
            let inferred = records.reversed()
                .compactMap { PlayPresentation.stars(fromAwardedSeconds: $0.awardedSeconds) }
                .first
            selectedStars = inferred ?? ChildDifficulty.easy.rawValue
        }
        if playVisaTotalSeconds <= 0 {
            playVisaTotalSeconds = ChildDifficulty(rawValue: selectedStars ?? 1)?.seconds ?? ChildDifficulty.easy.seconds
        }
        // Stamp gate is in-memory; resume past it so the child picks (or watches) again.
        awaitingDeparture = false
        mintVideoPickerOrderIfRouteIsPicker(entry: "recovered")
        VisaGamesLog.append(
            "recoverPlayPresentation — 恢復遊玩 stars=\(selectedStars ?? -1) total=\(playVisaTotalSeconds) allowlist=\(allowlist.videos.count)"
        )
    }

    /// v0.21.4: log + parent-only banner; never touches routing or the child path.
    private func noteSaveOutcome(_ outcome: ResilientSnapshotStore.Outcome, context: String) {
        switch outcome {
        case .saved:
            break
        case .recovered:
            storageSaveWarning = nil
            VisaGamesLog.append("storage save recovered — 儲存回復 ctx=\(context)")
        case .queued(let error):
            storageSaveWarning = "未能儲存（已記喺記憶體，會自動再試；小朋友可以照玩）。 / Save failed — kept in memory, retrying."
            VisaGamesLog.append(
                "storage save FAILED — 儲存失敗 (queued, child continues) ctx=\(context) n=\(resilientStore.consecutiveFailures) error=\(error)"
            )
        }
    }

    func update(_ action: (inout Session) -> Void) {
        var next = session
        action(&next)
        if next.snapshot != session.snapshot {
            noteSaveOutcome(resilientStore.commit(next.snapshot), context: "update")
        }
        let visaEnded = session.snapshot.endsAt != nil && next.snapshot.endsAt == nil
        let incompleteToSave: IncompletePlayback? = {
            guard visaEnded, session.mode == .play || next.mode == .lock,
                  let id = activePlayVideoID,
                  let position = lastKnownPlaybackSeconds,
                  IncompletePlaybackPolicy.shouldSaveOnStop(
                    isChildPlay: true,
                    reason: .sessionExpired,
                    positionSeconds: position
                  ) else { return nil }
            return IncompletePlayback.make(videoID: id, positionSeconds: position)
        }()
        session = next
        if let incompleteToSave {
            // Persist cursor before clearing the in-memory player (visa tick expiry bypasses stopScopedPlayback).
            var stamped = session
            stamped.replaceLastIncomplete(incompleteToSave)
            session = stamped
            noteSaveOutcome(resilientStore.commit(stamped.snapshot), context: "resume")
            VisaGamesLog.append(
                "resume save — 簽證到期記進度 id=\(incompleteToSave.videoID) at=\(Int(incompleteToSave.positionSeconds))s"
            )
        }
        if visaEnded {
            awaitingDeparture = false
            almostHomeSpoken = false
            if pendingVideoStopReason == nil { pendingVideoStopReason = .visaExpired }
            activePlayVideoID = nil
            pendingVideoStopReason = nil
            perf.visaEnded(reason: pendingVisaEndReason ?? "expired")
            pendingVisaEndReason = nil
            activePlayStartSeconds = nil
            lastKnownPlaybackSeconds = nil
            let ticket = resolvedPlayTicket
            if suppressNextTimesUp {
                suppressNextTimesUp = false
                showTimesUp = false
                timesUpTicket = nil
            } else {
                timesUpTicket = ticket
                // New bay only when Time's up appears. A later tick must not move it.
                if !showTimesUp {
                    timesUpDockSeed = UUID().uuidString
                }
                showTimesUp = true
                guideVoice.speak(.timesUp(for: ticket))
            }
            resetTaskRound()
        }
        changed?()
    }

    func tick() {
        now = Date()
        let current = now
        advanceThinkPauseIfNeeded(now: current)
        advancePlaytestThinkPauseIfNeeded(now: current)
        tapCountIdleCheck(now: current.timeIntervalSinceReferenceDate)
        tapLetterIdleCheck(now: current.timeIntervalSinceReferenceDate)
        if let outcome = resilientStore.retryIfDue(now: current) {
            noteSaveOutcome(outcome, context: "retry")
        }
        let modeBefore = session.mode
        update { $0.tick(now: current) }
        if session.mode != modeBefore {
            VisaGamesLog.append("mode change — 模式變更 \(modeBefore) → \(session.mode) via tick")
            logShellBranch(context: "tick")
        }
        if let parentDeadline, current >= parentDeadline { returnToChild(reason: "auto_lock") }
        perf.tick(now: current)
        if session.mode == .play, !awaitingDeparture, let endsAt = session.snapshot.endsAt {
            let progress = RoadTimerProgress.from(endsAt: endsAt, totalSeconds: playVisaTotalSeconds, now: current)
            if progress.almostHome, !almostHomeSpoken {
                almostHomeSpoken = true
                guideVoice.speak(.almostHome)
            }
        }
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
            enterParentAfterAuthentication()
        }
    }

    /// The LAContext success branch. The debug soak hook is the only other caller (ADR 0011).
    private func enterParentAfterAuthentication() {
        parentDeadline = Date().addingTimeInterval(parentAccessSeconds)
        if !storageFailed { message = nil }
        guideVoice.stop()
        let modeBeforeParent = session.mode
        // The player is torn down under parent controls: close the child play first.
        perf.endPlay(reason: .parentUnlock, resumeSaved: false)
        update { $0.enterParent(authenticated: true, now: Date()) }
        perf.parentEntered(fromMode: modeBeforeParent)
        VisaGamesLog.append("mode → parent — 進入家長模式")
        logShellBranch(context: "enterParent")
    }

    /// Debug soak only (ADR 0011): enter parent without LAContext. No-op unless the launch
    /// environment opted in; called only from AppDelegate's soak timer, never from a view.
    func soakEnterParent() {
        guard KioskSoak.isEnabled else { return }
        guard !authenticating, session.mode != .parent else { return }
        VisaGamesLog.append("soak — enter parent (auth bypassed, soak only)")
        enterParentAfterAuthentication()
    }

    func returnToChild(reason: String = "return") {
        providerBlockedParentHint = nil
        parentFinder = ParentFinderState()
        parentDraftTrialVideoID = nil
        // Auto-lock, sleep, and Return all come through here. Drop a playtest
        // before leaveParent so it cannot resume as a child round.
        discardPlaytestCover(reason: "leaveParent")
        let beforeMode = session.mode
        if beforeMode == .parent {
            // An inline 試播 preview (if any) ends with parent controls.
            perf.endPlay(reason: .previewStopped, resumeSaved: false)
        }
        let beforeEntry = isEntryActivityCompleted
        authentication?.invalidate()
        authentication = nil
        authenticating = false
        parentDeadline = nil
        update { $0.leaveParent(now: Date()) }
        if beforeMode == .parent { perf.parentLeft(reason: reason, toMode: session.mode) }
        // Drop parent preview if we are no longer in play with a valid policy.
        pendingVideoStopReason = .previewStopped
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
            if !decision.allowed {
                activePlayVideoID = nil
            } else if beforeMode == .parent {
                // Watch is rebuilt after parent controls: the same id loads again from its start offset.
                perfVideoStarted(id: id, source: "after_parent")
            }
        }
        pendingVideoStopReason = nil
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
        let modeBeforeGrant = session.mode
        update { $0.grant(seconds: 60, now: Date()) }
        guard session.mode == .play else { return }
        if modeBeforeGrant == .parent {
            // 測試一分鐘簽證 leaves parent controls straight into play (no returnToChild).
            perf.endPlay(reason: .previewStopped, resumeSaved: false)
            perf.abandonRound(reason: "test_visa")
            perf.parentLeft(reason: "test_visa", toMode: session.mode)
        }
        // Parent test visa has no activity ticket — keep canvas (picker), never legacyShell.
        if selectedStars == nil {
            selectedStars = ChildDifficulty.easy.rawValue
        }
        playVisaTotalSeconds = 60
        awaitingDeparture = false
        pendingVideoStopReason = .previewStopped
        activePlayVideoID = nil
        pendingVideoStopReason = nil
        showTimesUp = false
        perf.visaStarted(id: "test-\(UUID().uuidString)", source: .parentTest, seconds: 60,
                         endsAt: session.snapshot.endsAt, stars: nil)
        // D10: give the test visa its own picker visit (deck order is per visit, as for 出發).
        mintVideoPickerOrderIfRouteIsPicker(entry: "test_visa")
        VisaGamesLog.append("grant — 測試一分鐘簽證 canvasPlay stars=\(selectedStars ?? -1)")
        logShellBranch(context: "grant")
    }

    func selectTheme(_ palette: ThemePaletteID) {
        guard session.mode == .parent else { return }
        themeStore.save(palette)
        themePaletteID = palette
    }

    func triggerSuccessFeedback() {
        guard session.mode == .lock || session.mode == .play else { return }
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

    /// Storage needs a parent: child screens then show a visible Parent button, not only the corner.
    var needsParentAttention: Bool { storageFailed }

    /// Board 1 bubble: speak (or replay) the depot line in Cantonese.
    func speakDepotPrompt() {
        guard session.mode == .lock, !taskRoundOpen else { return }
        guideVoice.speak(.depotPickTicket)
    }

    func guideSpeakStamped() {
        if activeActivityKind?.isTapLetterFamily == true { tapLetterSpeak("stamp", "Stamped!") }
        else { guideVoice.speak(.stamped) }
    }
    func guideSpeakEmptyAllowlist() { guideVoice.speak(.emptyAllowlist) }
    func guideSpeakPickVideo() { guideVoice.speak(.pickVideo) }
    func guideSpeakResumeChoice() { guideVoice.speak(.resumeChoiceKeepWatching) }
    func guideSpeakResumeChoiceOrPick() { guideVoice.speak(.resumeChoiceOrPick) }

    /// Full allowlist in this visit's order. Pure function of `videoPickerOrderSeed`,
    /// so a shell refresh does not roll the cards.
    var pickerVideosInVisitOrder: [ApprovedVideo] {
        let ordered = VideoPickerDeck.ordered(allowlist.videos, seed: videoPickerOrderSeed)
        guard !providerBlockedUnavailableIDs.isEmpty else { return ordered }
        return ordered.filter { !providerBlockedUnavailableIDs.contains($0.id) }
    }

    private func mintVideoPickerOrderSeed(entry: String) {
        videoPickerOrderSeed = UUID().uuidString
        let now = Date()
        perf.pickerVisit(
            visit: videoPickerOrderSeed,
            entry: entry,
            deck: pickerVideosInVisitOrder.map(\.id),
            visaLeft: session.remaining(at: now),
            budgetLeft: remainingViewingBudget(at: now)
        )
    }

    /// D10: the picker reports each page it draws (no visual change).
    func videoPickerPageShown(page: Int, via: String) {
        guard session.mode == .play else { return }
        let now = Date()
        perf.pageShown(
            visit: videoPickerOrderSeed,
            deck: pickerVideosInVisitOrder.map(\.id),
            page: page,
            via: via,
            visaLeft: session.remaining(at: now),
            budgetLeft: remainingViewingBudget(at: now)
        )
    }

    /// New deck only when the route actually lands on the picker.
    private func mintVideoPickerOrderIfRouteIsPicker(entry: String) {
        let route = PlayStageRoute.route(
            awaitingDeparture: awaitingDeparture,
            allowlistCount: allowlist.videos.count,
            activeVideoID: activePlayVideoID,
            hasResumeCandidate: resumeCandidate != nil
        )
        if route == .videoPicker {
            mintVideoPickerOrderSeed(entry: entry)
        }
    }

    /// Board 4 prelude: child sees preview cards of allowlisted videos (Holiday P0).
    func videoPickerOpened() {
        if let candidate = resumeCandidate, session.mode == .play {
            perf.resumeOffered(video: candidate.videoID, position: candidate.positionSeconds, surface: "picker_banner")
        }
        let resume = resumeCandidate.map { "\($0.videoID)@\(Int($0.positionSeconds))s" } ?? "nil"
        VisaGamesLog.append(
            "videoPicker open — 揀片 allowlistCount=\(allowlist.videos.count) viewing=\(remainingViewingBudget(at: Date())) resume=\(resume)"
        )
    }

    /// Incomplete cursor still on the allowlist → show Continue on the picker.
    var resumeCandidate: IncompletePlayback? {
        IncompletePlaybackPolicy.shouldOfferContinue(
            incomplete: session.snapshot.lastIncomplete,
            allowlistContainsID: { allowlist.contains(id: $0) }
        )
    }

    /// Child tapped 繼續睇 — resume same id from saved position (does not clear cursor yet).
    func continueIncompleteVideo() {
        guard session.mode == .play, !awaitingDeparture,
              let candidate = resumeCandidate else { return }
        VisaGamesLog.append(
            "resume continue — 繼續睇 id=\(candidate.videoID) at=\(Int(candidate.positionSeconds))s"
        )
        activePlayStartSeconds = candidate.positionSeconds
        lastKnownPlaybackSeconds = candidate.positionSeconds
        perf.resumeUsed(video: candidate.videoID, position: candidate.positionSeconds, choice: "continue")
        pendingVideoStartSource = "continue"
        let decision = playAllowlisted(id: candidate.videoID)
        pendingVideoStartSource = nil
        if activePlayVideoID == nil {
            activePlayStartSeconds = nil
            VisaGamesLog.append(
                "resume continue rejected — 未能播放 id=\(candidate.videoID) message=\(playbackMessage ?? "nil")"
            )
            if let reason = decision.stopReason,
               VideoEndRouting.afterPlaybackStopped(reason: reason, isChildPlay: true) == .timesUp {
                finishPlayVisaToTimesUp(reason: "continueRejected-\(reason.rawValue)")
            }
        }
    }

    /// Resume Choice Right 「揀片睇」— clear incomplete cursor immediately (Carter 2026-10-02 lock),
    /// then land on VideoPicker (no mint Continue banner; cursor already gone).
    func pickOtherFromResumeChoice() {
        guard session.mode == .play, !awaitingDeparture else { return }
        VisaGamesLog.append("resumeChoice pickOther — 揀片睇 clearCursor=immediate")
        if let candidate = resumeCandidate {
            perf.resumeUsed(video: candidate.videoID, position: candidate.positionSeconds, choice: "pick_other")
        }
        clearLastIncomplete(reason: "resumeChoicePickOther")
        activePlayVideoID = nil
        activePlayStartSeconds = nil
        lastKnownPlaybackSeconds = nil
        playbackMessage = nil
        // 「揀片睇」enters the picker. Mint here, not in the view's onAppear.
        mintVideoPickerOrderIfRouteIsPicker(entry: "resume_pick_other")
        logShellBranch(context: "resumeChoicePickOther")
    }

    func resumeChoiceOpened() {
        if let candidate = resumeCandidate, session.mode == .play {
            perf.resumeOffered(video: candidate.videoID, position: candidate.positionSeconds, surface: "resume_choice")
        }
        let resume = resumeCandidate.map { "\($0.videoID)@\(Int($0.positionSeconds))s" } ?? "nil"
        VisaGamesLog.append(
            "resumeChoice open — 繼續定揀片 resume=\(resume) allowlistCount=\(allowlist.videos.count)"
        )
    }

    func notePlaybackCurrentTime(videoID: String, seconds: TimeInterval) {
        guard activePlayVideoID == videoID,
              seconds.isFinite, seconds > 0 else { return }
        if session.mode == .play {
            lastKnownPlaybackSeconds = seconds
            perf.playSample(video: videoID, seconds: seconds)
        }
        noteProviderPlaybackProgress()
    }

    /// Log reason → design §5.5 `resume_cleared.reason`.
    private static func perfResumeClearReason(_ reason: String) -> String {
        switch reason {
        case "resumeChoicePickOther": return "resume_choice_pick_other"
        case "pickOther": return "pick_other"
        case "allowlistRemove": return "allowlist_removed"
        case "ended": return "ended"
        default: return reason
        }
    }

    private func clearLastIncomplete(reason: String) {
        guard let cleared = session.snapshot.lastIncomplete else { return }
        perf.resumeCleared(video: cleared.videoID, position: cleared.positionSeconds,
                           reason: Self.perfResumeClearReason(reason))
        update { $0.replaceLastIncomplete(nil) }
        VisaGamesLog.append("resume clear — 清進度 reason=\(reason)")
    }

    private func persistLastIncomplete(videoID: String, positionSeconds: TimeInterval, reason: String) {
        guard let cursor = IncompletePlayback.make(videoID: videoID, positionSeconds: positionSeconds) else {
            return
        }
        update { $0.replaceLastIncomplete(cursor) }
        VisaGamesLog.append(
            "resume save — 記進度 id=\(cursor.videoID) at=\(Int(cursor.positionSeconds))s reason=\(reason)"
        )
    }

    /// Child tapped a preview card. Same D8 allowlist gate as every other start.
    /// Any card pick clears the resume cursor and starts from the beginning.
    func pickVideo(id: String) {
        guard session.mode == .play, !awaitingDeparture else { return }
        VisaGamesLog.append("videoPicker pick — 揀咗 id=\(id)")
        perf.pickTapped(visit: videoPickerOrderSeed, video: id, deck: pickerVideosInVisitOrder.map(\.id))
        clearLastIncomplete(reason: "pickOther")
        activePlayStartSeconds = nil
        lastKnownPlaybackSeconds = nil
        pendingVideoStartSource = "pick"
        let decision = playAllowlisted(id: id)
        pendingVideoStartSource = nil
        if activePlayVideoID == nil {
            perf.pickRefused(reason: decision.stopReason?.rawValue)
            VisaGamesLog.append("videoPicker pick rejected — 未能播放 id=\(id) message=\(playbackMessage ?? "nil")")
            // Dead budget on the picker (e.g. day rollover) → Time's up, not a stuck picker.
            if let reason = decision.stopReason,
               VideoEndRouting.afterPlaybackStopped(reason: reason, isChildPlay: true) == .timesUp {
                finishPlayVisaToTimesUp(reason: "pickRejected-\(reason.rawValue)")
            }
        }
    }
    func guideSpeakTimesUp() {
        if let ticket = timesUpTicket {
            guideVoice.speak(.timesUp(for: ticket))
        } else {
            guideVoice.speak(.timesUpPark)
        }
    }

    var currentTwoPictureQuestion: TwoPictureQuestion { twoPictureQuestion }
    var currentFindSameQuestion: FindSameQuestion { findSameQuestion }
    var currentCountQuestion: CountQuestion { countQuestion }
    var currentPlaytestFindSameQuestion: FindSameQuestion { playtestFindSameQuestion }
    var currentPlaytestCountQuestion: CountQuestion { playtestCountQuestion }
    var currentSequenceQuestion: SequenceQuestion { sequenceQuestion }
    var currentHalfMatchQuestion: HalfMatchQuestion { halfMatchQuestion }
    var currentShapeCousinQuestion: ShapeCousinQuestion { shapeCousinQuestion }
    var currentCapacityCompareQuestion: CapacityCompareQuestion { capacityCompareQuestion }
    var currentMoreFewerQuestion: MoreFewerQuestion { moreFewerQuestion }
    var currentShadowMatchQuestion: ShadowMatchQuestion { shadowMatchQuestion }
    var currentEmptyBayQuestion: EmptyBayQuestion { emptyBayQuestion }

    func selectDifficulty(stars: Int) {
        guard session.mode == .lock, !taskRoundOpen,
              let difficulty = ChildDifficulty(rawValue: stars) else { return }
        guideVoice.stop()
        resetTaskRound()
        selectedStars = stars
        let seed = UUID().uuidString
        roundCompletionID = seed
        choiceDealSeed = seed
        let pool = gameAssignment.pool(for: difficulty)
        let kind = ActivityCatalog.kind(forRoundSeed: seed, pool: pool)
        activeActivityKind = kind
        // D1 (v0.22.0): the ticket's stars are also the question tier for generated kinds.
        let level = ActivityLevel(difficulty)
        twoPictureQuestion = ActivityCatalog.twoPictureQuestion()
        findSameQuestion = ActivityCatalog.findSameQuestion(
            seed: seed, level: level, avoidingItem: lastDealtItem[.findTheSame])
        countQuestion = ActivityCatalog.countQuestion(
            seed: seed, level: level, avoidingItem: lastDealtItem[.countVehicles])
        let lineMatchQuestion: LineMatchQuestion
        if let deal = kind.lineMatchDeal(missionLevel: level) {
            lineMatchQuestion = ActivityCatalog.lineMatchQuestion(
                seed: seed, level: deal.level, avoidingItem: lastDealtItem[kind], settings: lineMatchSettings,
                mode: deal.mode)
        } else {
            lineMatchQuestion = ActivityCatalog.lineMatchQuestion()
        }
        lineMatchBoard = LineMatchBoard(question: lineMatchQuestion, tolerance: lineMatchSettings.tolerance)
        lineMatchGuidedBoard = lineMatchQuestion.isGuided
            ? LineMatchGuidedBoard(question: lineMatchQuestion, tolerance: lineMatchSettings.tolerance) : nil
        guidedHintSpokenRows = []
        lineMatchNotice = nil
        shapeTraceBoard = kind.isShapeTraceFamily ? makeShapeTraceBoard(
            seed: seed, kind: kind, avoidingItem: lastDealtItem[kind]) : nil
        shapeTraceHintSpoken = []
        shapeTraceNotice = nil
        tapCountBoard = kind.isTapCountFamily ? makeTapCountBoard(
            seed: seed, kind: kind, avoidingItem: lastDealtItem[kind]) : nil
        tapLetterBoard = kind.isTapLetterFamily ? makeTapLetterBoard(seed: seed) : nil
        tapLetterWriteRound = kind == .tapLetterWrite ? tapLetterBoard.map { TapLetterWriteRound(deal: $0.deal) } : nil
        tapLetterGuideRun = nil
        tapLetterGuideSpeechGeneration += 1
        tapLetterCuspSpoken = false
        tapLetterBubble = nil
        tapLetterCelebrating = false
        tapLetterStrokeReveal = nil
        tapLetterPlaqueNudge = false
        tapLetterLastActionAt = Date().timeIntervalSinceReferenceDate
        tapLetterRoundStart = tapLetterLastActionAt
        tapLetterIdleSpoken = false
        tapLetterPenaltyPending = false
        resetTapCountTransient()
        sequenceQuestion = ActivityCatalog.sequenceQuestion()
        halfMatchQuestion = ActivityCatalog.halfMatchQuestion()
        shapeCousinQuestion = ActivityCatalog.shapeCousinQuestion()
        capacityCompareQuestion = ActivityCatalog.capacityCompareQuestion()
        moreFewerQuestion = ActivityCatalog.moreFewerQuestion()
        shadowMatchQuestion = ActivityCatalog.shadowMatchQuestion()
        emptyBayQuestion = ActivityCatalog.emptyBayQuestion()
        sequenceTappedAssetIDs = []
        pendingAwardMinutes = difficulty.minutes
        roundStartingMinutes = difficulty.minutes
        earnedAwardMinutes = 0
        fuelFeedbackMessage = nil
        clearThinkPause()
        taskRoundOpen = true
        let facts = dealFacts(kind: kind, seed: seed, findSame: findSameQuestion, count: countQuestion,
                              lineMatch: lineMatchBoard.question, shapeTrace: shapeTraceBoard, tapCount: tapCountBoard)
        if QuestionGeneration.isGenerated(kind) { lastDealtItem[kind] = facts.item }
        noteTapCountDealt(tapCountBoard)
        perf.roundDealt(round: seed, kind: kind, stars: stars, pendingStart: difficulty.minutes, pool: pool,
                        facts: facts)
        VisaGamesLog.append("selectDifficulty — 選擇難度 stars=\(stars) kind=\(kind.rawValue) level=\(level.code) item=\(facts.item) seed=\(seed) pendingMin=\(pendingAwardMinutes) pool=\(pool.count)")
    }

    private func resetTaskRound() {
        // D10: a round still open here was left without an answer (specific reasons are logged earlier).
        perf.abandonRound(reason: "round_reset")
        taskRoundOpen = false
        selectedStars = nil
        roundCompletionID = nil
        activeActivityKind = nil
        entryHintUsed = false
        entryMissCount = 0
        lastIncorrectChoiceID = nil
        lastCorrectChoiceID = nil
        activityJustCompleted = false
        entryRetryMessage = nil
        pendingAwardMinutes = 0
        roundStartingMinutes = 0
        earnedAwardMinutes = 0
        fuelFeedbackMessage = nil
        clearThinkPause()
        // Keep activePlayVideoID / awaitingDeparture under caller's control during play.
        playbackMessage = nil
        successFeedbackID = nil
        sequenceTappedAssetIDs = []
        choiceDealSeed = ""
        tapLetterBoard = nil
        tapLetterWriteRound = nil
        tapLetterBubble = nil
    }

    func useEntryHint() {
        guard session.mode == .lock, taskRoundOpen, let kind = activeActivityKind else { return }
        guard !choicesLocked else { return }
        entryHintUsed = true
        entryRetryMessage = hintText(for: kind, findSame: findSameQuestion, count: countQuestion)
    }

    /// Generated questions carry their own hint (it names the vehicle / the detail to check).
    private func hintText(for kind: ActivityKind, findSame: FindSameQuestion, count: CountQuestion) -> String {
        switch kind {
        case .findTheSame: return findSame.hintTraditionalChinese
        case .countVehicles: return count.hintTraditionalChinese
        case .lineMatch, .lineMatchGuidedStraight, .lineMatchGuidedBridge:
            return lineMatchBoard.question.hintTraditionalChinese
        case .traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree:
            return ShapeTraceCopy.hint
        case .tapCountAll, .tapCountTrace, .tapCountPick:
            return TapCountCopy.hint
        case .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish:
            return TapCountEnglishCopy.hint
        default: return ActivityCatalog.hintTraditionalChinese(for: kind)
        }
    }

    /// Performance facts of the question actually dealt (item, slots, gen, level, tags).
    private func dealFacts(kind: ActivityKind, seed: String, findSame: FindSameQuestion,
                           count: CountQuestion, lineMatch: LineMatchQuestion,
                           shapeTrace: ShapeTraceBoard? = nil, tapCount: TapCountBoard? = nil) -> PerfDealFacts {
        switch kind {
        case .findTheSame: return PerfChoiceCatalog.facts(findSame: findSame, seed: seed)
        case .countVehicles: return PerfChoiceCatalog.facts(count: count, seed: seed)
        case .lineMatch, .lineMatchGuidedStraight, .lineMatchGuidedBridge:
            return PerfChoiceCatalog.facts(lineMatch: lineMatch, settings: lineMatchSettings)
        case .traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree:
            let board = shapeTrace ?? ShapeTraceBoard(question: ShapeTraceGenerator.reference(kind: kind))
            return PerfChoiceCatalog.facts(shapeTrace: board.question, settings: shapeTraceSettings,
                                           tolerance: board.tolerance)
        case .tapCountAll, .tapCountTrace, .tapCountPick, .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish:
            let question = tapCount?.question ?? TapCountGenerator.reference(kind: kind)
            return PerfChoiceCatalog.facts(tapCount: question, settings: tapCountSettings,
                                           tolerance: tapCountTolerance, recentTargets: tapCountRecentTargets)
        case .tapLetterAll, .tapLetterWrite:
            return tapLetterFacts(currentTapLetterBoard)
        default: return PerfChoiceCatalog.facts(kind: kind, seed: seed)
        }
    }

    func speakEntryPrompt() {
        guard session.mode == .lock, taskRoundOpen, let kind = activeActivityKind else { return }
        // Interim zh-HK system voice (ADR 0007). Recorded clips wait on D9 / UX Phase 5.
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
            zh = sequenceQuestion.promptTraditionalChinese
            en = sequenceQuestion.promptEnglish
        case .halfMatch:
            zh = halfMatchQuestion.promptTraditionalChinese
            en = halfMatchQuestion.promptEnglish
        case .shapeCousin:
            zh = shapeCousinQuestion.promptTraditionalChinese
            en = shapeCousinQuestion.promptEnglish
        case .capacityCompare:
            zh = capacityCompareQuestion.promptTraditionalChinese
            en = capacityCompareQuestion.promptEnglish
        case .moreFewer:
            zh = moreFewerQuestion.promptTraditionalChinese
            en = moreFewerQuestion.promptEnglish
        case .shadowMatch:
            zh = shadowMatchQuestion.promptTraditionalChinese
            en = shadowMatchQuestion.promptEnglish
        case .emptyBay:
            zh = emptyBayQuestion.promptTraditionalChinese
            en = emptyBayQuestion.promptEnglish
        case .lineMatch, .lineMatchGuidedStraight, .lineMatchGuidedBridge:
            zh = lineMatchBoard.question.promptTraditionalChinese
            en = lineMatchBoard.question.promptEnglish
        case .traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree:
            let question = shapeTraceBoard?.question ?? ShapeTraceGenerator.reference(kind: kind)
            zh = question.promptTraditionalChinese
            en = question.promptEnglish
        case .tapCountAll, .tapCountTrace, .tapCountPick, .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish:
            speakTapCountPrompt()
            return
        case .tapLetterAll, .tapLetterWrite:
            speakTapLetterPrompt()
            return
        }
        guideVoice.speak(SpokenPrompt(
            key: "activity.\(kind.rawValue)",
            traditionalChinese: zh,
            english: en
        ))
    }

    func selectEntryOption(id: String) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .twoPictureChoose else { return }
        guard !choicesLocked else { perf.roundMashTap(); return }
        let evaluation = activityEvaluator.evaluate(
            question: twoPictureQuestion,
            selectedOptionID: id,
            hintUsed: entryHintUsed
        )
        handleEvaluation(evaluation, selectionLabel: id)
    }

    func selectFindSameOption(id: String) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .findTheSame else { return }
        guard !choicesLocked else { perf.roundMashTap(); return }
        let evaluation = activityEvaluator.evaluate(
            question: findSameQuestion,
            selectedOptionID: id,
            hintUsed: entryHintUsed
        )
        handleEvaluation(evaluation, selectionLabel: id)
    }

    func selectCountChoice(_ count: Int) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .countVehicles else { return }
        guard !choicesLocked else { perf.roundMashTap(); return }
        let evaluation = activityEvaluator.evaluate(
            question: countQuestion,
            selectedCount: count,
            hintUsed: entryHintUsed
        )
        handleEvaluation(evaluation, selectionLabel: "count-\(count)")
    }

    func selectSequenceAsset(id assetID: String) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .sequenceShortToLong else { return }
        guard !choicesLocked else { perf.roundMashTap(); return }
        guard !sequenceTappedAssetIDs.contains(assetID) else { return }
        let expected = activityEvaluator.nextExpectedAssetID(
            question: sequenceQuestion,
            tappedSoFar: sequenceTappedAssetIDs
        )
        if expected != assetID {
            pendingSequenceContext = (sequenceTappedAssetIDs.count + 1, expected, sequenceTappedAssetIDs)
            sequenceTappedAssetIDs = []
            handleEvaluation(.incorrect, selectionLabel: assetID)
            pendingSequenceContext = nil
            return
        }
        let tappedBefore = sequenceTappedAssetIDs
        sequenceTappedAssetIDs.append(assetID)
        if sequenceTappedAssetIDs.count < sequenceQuestion.orderedAssetIDs.count {
            perf.roundAnswer(choice: assetID, correct: true, pendingBefore: pendingAwardMinutes,
                             pendingAfter: pendingAwardMinutes, hintOn: entryHintUsed,
                             sequence: (tappedBefore.count + 1, expected, tappedBefore))
        } else {
            pendingSequenceContext = (tappedBefore.count + 1, expected, tappedBefore)
        }
        if sequenceTappedAssetIDs.count == sequenceQuestion.orderedAssetIDs.count {
            let evaluation = activityEvaluator.evaluate(
                question: sequenceQuestion,
                orderedSelectionIDs: sequenceTappedAssetIDs,
                hintUsed: entryHintUsed
            )
            handleEvaluation(evaluation, selectionLabel: "seq-complete")
            pendingSequenceContext = nil
        } else {
            entryRetryMessage = "好！下一架～ / Good! Next one~"
            VisaGamesLog.append("sequence progress — 車隊進度 count=\(sequenceTappedAssetIDs.count)")
        }
    }

    func selectHalfMatchOption(id: String) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .halfMatch else { return }
        guard !choicesLocked else { perf.roundMashTap(); return }
        let evaluation = activityEvaluator.evaluate(
            question: halfMatchQuestion,
            selectedOptionID: id,
            hintUsed: entryHintUsed
        )
        handleEvaluation(evaluation, selectionLabel: id)
    }

    func selectShapeCousinOption(id: String) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .shapeCousin else { return }
        guard !choicesLocked else { perf.roundMashTap(); return }
        let evaluation = activityEvaluator.evaluate(
            question: shapeCousinQuestion,
            selectedOptionID: id,
            hintUsed: entryHintUsed
        )
        handleEvaluation(evaluation, selectionLabel: id)
    }

    func selectCapacityOption(id: String) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .capacityCompare else { return }
        guard !choicesLocked else { perf.roundMashTap(); return }
        let evaluation = activityEvaluator.evaluate(
            question: capacityCompareQuestion,
            selectedOptionID: id,
            hintUsed: entryHintUsed
        )
        handleEvaluation(evaluation, selectionLabel: id)
    }

    func selectMoreFewerSide(_ side: ParkingLotSide) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .moreFewer else { return }
        guard !choicesLocked else { perf.roundMashTap(); return }
        let evaluation = activityEvaluator.evaluate(
            question: moreFewerQuestion,
            selectedSide: side,
            hintUsed: entryHintUsed
        )
        handleEvaluation(evaluation, selectionLabel: "lot-\(side.rawValue)")
    }

    func selectShadowMatchOption(id: String) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .shadowMatch else { return }
        guard !choicesLocked else { perf.roundMashTap(); return }
        let evaluation = activityEvaluator.evaluate(
            question: shadowMatchQuestion,
            selectedOptionID: id,
            hintUsed: entryHintUsed
        )
        handleEvaluation(evaluation, selectionLabel: id)
    }

    func selectEmptyBay(id: String) {
        guard session.mode == .lock, taskRoundOpen, activeActivityKind == .emptyBay else { return }
        guard !choicesLocked else { perf.roundMashTap(); return }
        let evaluation = activityEvaluator.evaluate(
            question: emptyBayQuestion,
            selectedBayID: id,
            hintUsed: entryHintUsed
        )
        handleEvaluation(evaluation, selectionLabel: id)
    }

    private func handleEvaluation(_ evaluation: ActivityEvaluation, selectionLabel: String) {
        guard WrongAnswerPolicy.shouldAcceptChoiceInput(choicesLocked: choicesLocked) else {
            VisaGamesLog.append("activity input ignored — Think Pause mash selection=\(selectionLabel)")
            return
        }
        switch evaluation {
        case .incorrect:
            // Order: feedback → halve pending → 10s Think Pause → (0 after pause) Depot else unlock (+ hint).
            entryMissCount += 1
            lastIncorrectChoiceID = selectionLabel
            lastCorrectChoiceID = nil
            entryRetryMessage = nil
            let before = pendingAwardMinutes
            pendingAwardMinutes = WrongAnswerPolicy.halvedPendingMinutes(pendingAwardMinutes)
            fuelFeedbackMessage = WrongAnswerCopy.fuelHalvedTraditionalChinese
            perf.roundAnswer(choice: selectionLabel, correct: false, pendingBefore: before,
                             pendingAfter: pendingAwardMinutes, hintOn: entryHintUsed,
                             sequence: pendingSequenceContext, record: pendingAnswerRecord)
            VisaGamesLog.append(
                "activity incorrect — 答錯 selection=\(selectionLabel) kind=\(activeActivityKind?.rawValue ?? "nil") misses=\(entryMissCount) pending \(before)→\(pendingAwardMinutes) hintUsed=\(entryHintUsed)"
            )
            let flashed = selectionLabel
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                if self?.lastIncorrectChoiceID == flashed {
                    self?.lastIncorrectChoiceID = nil
                }
            }
            beginThinkPause(now: Date())
        case .correct(let assisted):
            let answeredChoice = selectionLabel == "seq-complete"
                ? (sequenceTappedAssetIDs.last ?? selectionLabel) : selectionLabel
            perf.roundAnswer(choice: answeredChoice, correct: true, pendingBefore: pendingAwardMinutes,
                             pendingAfter: pendingAwardMinutes, hintOn: entryHintUsed,
                             sequence: pendingSequenceContext, record: pendingAnswerRecord)
            guard pendingAwardMinutes > 0 else {
                // Should not reach stamp with 0 fuel; send to Depot safely.
                VisaGamesLog.append("activity correct blocked — pending=0 → depot")
                returnToDepotOutOfFuel()
                return
            }
            lastCorrectChoiceID = selectionLabel
            lastIncorrectChoiceID = nil
            activityJustCompleted = true
            VisaGamesLog.append(
                "activity correct — 答對 selection=\(selectionLabel) kind=\(activeActivityKind?.rawValue ?? "nil") assisted=\(assisted) earnedMin=\(pendingAwardMinutes)"
            )
            applyEntrySuccess(assisted: assisted)
        }
    }

    private func applyEntrySuccess(assisted: Bool) {
        let now = Date()
        let calendar = budgetCalendar
        guard taskRoundOpen, session.mode == .lock,
              let stars = selectedStars, ChildDifficulty(rawValue: stars) != nil,
              let completionID = roundCompletionID else { return }
        let earnedMinutes = pendingAwardMinutes
        let awardSeconds = WrongAnswerPolicy.awardSeconds(fromPendingMinutes: earnedMinutes)
        guard earnedMinutes > 0, awardSeconds > 0 else {
            returnToDepotOutOfFuel()
            return
        }
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
            // Bank earned pending (may be reduced by wrongs); D7 kind still assisted/unassisted.
            _ = ledger.applyCompletion(
                id: completionID,
                rewardSeconds: awardSeconds,
                kind: kind,
                now: now,
                calendar: calendar
            )
            session.replaceRewardState(ledger.exportState())
            session.startPlayVisa(seconds: awardSeconds, now: now)
        }
        guard session.mode == .play else { return }
        perf.roundFinished(outcome: .solved, earnedMinutes: earnedMinutes, assisted: assisted)
        perf.visaStarted(id: completionID, source: .earned, seconds: awardSeconds,
                         endsAt: session.snapshot.endsAt, stars: stars)
        taskRoundOpen = false
        entryRetryMessage = nil
        fuelFeedbackMessage = nil
        clearThinkPause()
        earnedAwardMinutes = earnedMinutes
        playVisaTotalSeconds = awardSeconds
        almostHomeSpoken = false
        // Dock is chosen when the gate opens, before the stamp view's first frame.
        departureDockSeed = UUID().uuidString
        awaitingDeparture = true
        showTimesUp = false
        triggerSuccessFeedback()
        if activeActivityKind?.isTapLetterFamily != true { guideSpeakStamped() }
        VisaGamesLog.append(
            "applyEntrySuccess — 入口成功 assisted=\(assisted) earnedMin=\(earnedMinutes) entryCompleted=\(isEntryActivityCompleted) viewing=\(remainingViewingBudget(at: Date())) mode=\(session.mode) stampGate=true"
        )
        logShellBranch(context: "applyEntrySuccess")
        // v0.11.0 / v0.15.0: no pre-selected video. Stamp 「出發！」 → Resume Choice (if incomplete)
        // or VideoPickerView. `nextShuffledAllowlistedVideoID` stays for the legacy shell.
        activePlayVideoID = nil
        playbackMessage = nil
    }

    /// Board 3 Go button — reveal watch / empty-allowlist presentation.
    func confirmDeparture() {
        clearProviderBlockedVisaState()
        guard session.mode == .play, awaitingDeparture else { return }
        awaitingDeparture = false
        guideVoice.speak(.departGo)
        // 「出發！」 enters the picker only when there is no Resume Choice and the bay is not empty.
        mintVideoPickerOrderIfRouteIsPicker(entry: "go")
        VisaGamesLog.append("confirmDeparture — 出發 watchUI allowlistCount=\(allowlist.videos.count)")
        logShellBranch(context: "confirmDeparture")
    }

    func dismissTimesUp() {
        showTimesUp = false
        clearProviderBlockedVisaState()
        timesUpTicket = nil
        guideVoice.stop()
        VisaGamesLog.append("dismissTimesUp — 再揀車票 → depot")
    }

    func returnFromEmptyAllowlist() {
        guard session.mode == .play else { return }
        guideVoice.stop()
        activePlayVideoID = nil
        awaitingDeparture = false
        suppressNextTimesUp = true
        // End the active visa (child left play); skip park-and-sleep and return to depot.
        pendingVisaEndReason = "empty_allowlist_return"
        update { $0.endPlayVisa(now: Date()) }
        pendingVisaEndReason = nil
        VisaGamesLog.append("returnFromEmptyAllowlist — 返回車廠")
    }

    // MARK: - Wrong-answer Think Pause (pending shrink)

    private func clearThinkPause() {
        thinkPauseEndsAt = nil
        thinkPauseRemainingSeconds = 0
    }

    private func beginThinkPause(now: Date) {
        // A line being drawn when the pause starts springs back (design §1.2).
        lineMatchBoard.cancelDrag()
        thinkPauseEndsAt = now.addingTimeInterval(TimeInterval(WrongAnswerPolicy.thinkPauseSeconds))
        thinkPauseRemainingSeconds = WrongAnswerPolicy.thinkPauseSeconds
        perf.roundPauseStarted()
        VisaGamesLog.append(
            "think-pause start — 停一停 pendingMin=\(pendingAwardMinutes) secs=\(WrongAnswerPolicy.thinkPauseSeconds)"
        )
        changed?()
    }

    private func advanceThinkPauseIfNeeded(now: Date) {
        guard let ends = thinkPauseEndsAt else { return }
        let remaining = max(0, Int(ceil(ends.timeIntervalSince(now))))
        if remaining != thinkPauseRemainingSeconds {
            thinkPauseRemainingSeconds = remaining
        }
        if remaining == 0 {
            thinkPauseEndsAt = nil
            finishThinkPause()
        }
    }

    private func finishThinkPause() {
        thinkPauseRemainingSeconds = 0
        perf.roundPauseEnded()
        fuelFeedbackMessage = nil
        if WrongAnswerPolicy.shouldReturnToDepot(pendingMinutes: pendingAwardMinutes) {
            VisaGamesLog.append("think-pause end — pending=0 → depot")
            returnToDepotOutOfFuel()
            return
        }
        VisaGamesLog.append(
            "think-pause end — unlock pendingMin=\(pendingAwardMinutes) misses=\(entryMissCount)"
        )
        if activeActivityKind?.isLineMatchFamily == true {
            lineMatchBoard.noteUnlocked(now: now.timeIntervalSinceReferenceDate)
        }
        if activeActivityKind?.isTapCountFamily == true {
            // ★★★: after the 2nd miss the rescue is the demo count (rings the first N); it replaces
            // the text hint and makes the success assisted.
            tapCountAfterThinkPause(playtest: false)
            changed?()
            return
        }
        if activeActivityKind?.isTapLetterFamily == true {
            tapLetterAfterPause()
            changed?()
            return
        }
        // Existing assisted/hint rescue still helps when fuel remains.
        if ActivityHintPolicy.shouldAutoHint(afterMissCount: entryMissCount), !entryHintUsed {
            useEntryHint()
            speakEntryPrompt()
            perf.roundHint(afterMisses: entryMissCount)
            VisaGamesLog.append("auto-hint — 自動提示 after pause misses=\(entryMissCount) → assisted")
        }
        changed?()
    }

    private func returnToDepotOutOfFuel() {
        if activeActivityKind?.isTapLetterFamily == true, let board = tapLetterBoard, !board.isComplete {
            var fields = tapLetterResultFields(board)
            let boxes = tapLetterSaveRound(board)
            fields["box_before"] = .string(boxes.before)
            fields["box_after"] = .string(boxes.after)
            perf.roundResultExtra(fields)
        }
        if activeActivityKind?.isTapLetterFamily == true {
            guideVoice.speak(SpokenPrompt.englishOnly(key: "en.tapLetter.outOfFuel",
                                                      WrongAnswerCopy.returnDepotEnglish))
        } else { guideVoice.speak(.outOfFuelDepot) }
        VisaGamesLog.append("returnToDepotOutOfFuel — 油用晒 返車廠")
        perf.roundFinished(outcome: .zeroed, earnedMinutes: 0, assisted: false)
        resetTaskRound()
        changed?()
    }

    var selectedMissionTicket: MissionTicket? {
        guard let stars = selectedStars,
              let difficulty = ChildDifficulty(rawValue: stars) else { return nil }
        return MissionTicket.all.first { $0.difficulty == difficulty }
    }

    /// Always a ticket for canvas play boards (easy fallback when stars were lost).
    var resolvedPlayTicket: MissionTicket {
        PlayPresentation.ticket(selectedStars: selectedStars)
    }

    var sequenceHintAssetID: String? {
        activityEvaluator.nextExpectedAssetID(
            question: sequenceQuestion,
            tappedSoFar: sequenceTappedAssetIDs
        )
    }

    var roadTimerProgress: RoadTimerProgress {
        let total = playVisaTotalSeconds > 0 ? playVisaTotalSeconds : (ChildDifficulty(rawValue: selectedStars ?? 1)?.seconds ?? ChildDifficulty.easy.seconds)
        guard let endsAt = session.snapshot.endsAt else {
            return RoadTimerProgress(elapsed: total, total: total, remaining: 0)
        }
        return RoadTimerProgress.from(endsAt: endsAt, totalSeconds: total, now: now)
    }


    func addAllowlistedVideo() {
        guard session.mode == .parent else { return }
        guard !isFetchingAllowlistMetadata else { return }
        guard let id = YouTubeEmbedURL.extractVideoID(from: parentVideoIDDraft) else {
            playbackMessage = "影片編號無效。 / Invalid video ID."
            return
        }
        // v0.27.1 (08): the owner blocks embedding → it would never play for the child.
        if parentDraftStatus.videoID == id, parentDraftEmbedCheck == .blocked {
            playbackMessage = "擁有者唔准喺其他地方播，加咗小朋友都播唔到。 / Owner blocks embedding; it would never play."
            return
        }
        let durationText = parentVideoDurationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let durationParsed = TimeInterval(durationText) ?? 0
        // v0.27.0: the browser read the real length from the page → use it unless the parent typed one.
        let pageSeconds = parentDraftPageDuration.flatMap { $0.videoID == id ? $0.seconds : nil }
        let durationSeconds: TimeInterval
        if let pageSeconds, durationText == "120" || durationText.isEmpty {
            durationSeconds = pageSeconds
        } else {
            durationSeconds = durationParsed > 0 ? durationParsed : 120
        }
        let titleOverride = parentVideoTitleDraft
        let overrideFields = Self.parentTitleFields(from: titleOverride)

        isFetchingAllowlistMetadata = true
        playbackMessage = "正在取得片名… / Fetching title…"

        Task { @MainActor in
            defer { self.isFetchingAllowlistMetadata = false }

            var titleEnglish = overrideFields.0
            var titleCantonese = overrideFields.1
            let hasOverride = titleEnglish != nil || titleCantonese != nil

            if !hasOverride {
                // Reuse the paste-preview title when we already have it; else fetch now.
                // oEmbed failure still allows add with id + optional override + thumb from id.
                var fetched = self.oEmbedTitleCache[id]
                if fetched == nil {
                    fetched = await Self.fetchOEmbedTitle(videoID: id)
                    if let fetched { self.oEmbedTitleCache[id] = fetched }
                }
                if let fetched {
                    let fields = Self.parentTitleFields(from: fetched)
                    titleEnglish = fields.0
                    titleCantonese = fields.1
                }
            }

            var next = self.allowlist
            let ok = next.upsert(ApprovedVideo(
                id: id,
                titleEnglish: titleEnglish,
                titleCantonese: titleCantonese,
                durationSeconds: durationSeconds,
                playerDurationSeconds: next.video(id: id)?.playerDurationSeconds ?? pageSeconds,
                addedAt: next.video(id: id).map { $0.addedAt } ?? Date()
            ))
            guard ok else {
                self.playbackMessage = "影片編號無效。 / Invalid video ID."
                return
            }
            let existed = self.allowlist.video(id: id) != nil
            self.allowlist = next
            self.allowlistStore.save(next)
            self.perf.allowlistChanged(op: existed ? "update" : "add", video: id)
            // D4: an add from the finder's confirm card keeps the finder open with a toast.
            self.parentFinder.didAdd(videoID: id, allowlistCount: next.videos.count, now: Date())
            self.parentVideoIDDraft = ""
            self.parentDraftPageDuration = nil
            self.parentDraftDurationBaseline = "120"
            self.parentDraftTrialVideoID = nil
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

    // MARK: - Parent in-app YouTube finder (v0.27.0, ADR 0016)

    /// Yellow 「喺 YouTube 搵片」. Stops any inline 試播 so two players never sound at once.
    func openParentBrowser() {
        guard session.mode == .parent, !parentFinder.isOpen else { return }
        if activePlayVideoID != nil { stopParentPreview() }
        parentDraftTrialVideoID = nil
        parentFinder.open()
        noteParentBrowserActivity()
        VisaGamesLog.append("parent browser open — 喺 YouTube 搵片")
    }

    /// 完成，返去清單. The view pauses page media before calling this. Flashes the last card
    /// added this visit (D13).
    func closeParentBrowser(reason: String = "close") {
        guard parentFinder.isOpen else { return }
        if parentFinder.confirmVideoID != nil { cancelFinderConfirm() }
        let flash = parentFinder.close()
        if let flash { requestCardFlash(videoID: flash) }
        VisaGamesLog.append("parent browser close — 返去清單 reason=\(reason)")
    }

    /// 睇吓張卡: leave the finder, scroll to that card and flash it.
    func showCardFromFinder(videoID: String) {
        guard parentFinder.isOpen else { return }
        if parentFinder.confirmVideoID != nil { cancelFinderConfirm() }
        requestCardFlash(videoID: parentFinder.showCard(videoID: videoID))
        VisaGamesLog.append("parent browser show card id=\(videoID)")
    }

    private func requestCardFlash(videoID: String) {
        guard allowlist.contains(id: videoID) else { return }
        parentFlashVideoID = videoID
        parentFlashUntil = Date().addingTimeInterval(2.5)
        parentFlashRequest += 1
    }

    /// Flash is on for this card right now (time-based; no animation in the parent view).
    func isCardFlashing(_ id: String) -> Bool {
        guard parentFlashVideoID == id, let until = parentFlashUntil else { return false }
        return now < until
    }

    /// D5 top-bar countdown. Nil outside parent mode.
    var parentAutoLockRemaining: TimeInterval? {
        guard session.mode == .parent, let parentDeadline else { return nil }
        return max(0, parentDeadline.timeIntervalSince(now))
    }

    /// Browsing counts as parent activity (same 10-minute window as 試播).
    func noteParentBrowserActivity() {
        guard session.mode == .parent else { return }
        parentDeadline = Date().addingTimeInterval(parentAccessSeconds)
    }

    func noteParentBrowserSearch(_ query: String) {
        guard session.mode == .parent else { return }
        let next = ParentYouTubeBrowser.recentSearches(adding: query, to: parentRecentSearches)
        noteParentBrowserActivity()
        guard next != parentRecentSearches else { return }
        parentRecentSearches = next
        UserDefaults.standard.set(next, forKey: ParentYouTubeBrowser.recentSearchesKey)
    }

    func clearParentRecentSearches() {
        guard session.mode == .parent else { return }
        parentRecentSearches = []
        UserDefaults.standard.removeObject(forKey: ParentYouTubeBrowser.recentSearchesKey)
    }

    /// 「＋ 加入呢條片」 (or 更新片名／片長, or a pasted link): the existing preview card opens over
    /// the finder (08). Nothing is saved until 加入. The page length fills 「片長秒數」.
    func beginFinderConfirm(videoID: String, pageDurationSeconds: TimeInterval?) {
        guard session.mode == .parent, parentFinder.isOpen, YouTubeEmbedURL.isValidVideoID(videoID) else { return }
        parentDraftTrialVideoID = nil
        parentVideoTitleDraft = ""
        if let existing = allowlist.video(id: videoID) {
            parentDraftPageDuration = pageDurationSeconds.map { (videoID: videoID, seconds: $0) }
            parentVideoDurationDraft = String(Int(existing.durationSeconds.rounded()))
        } else if let seconds = pageDurationSeconds {
            parentDraftPageDuration = (videoID: videoID, seconds: seconds)
            parentVideoDurationDraft = String(Int(seconds.rounded()))
        } else {
            parentDraftPageDuration = nil
            parentVideoDurationDraft = "120"
        }
        parentDraftDurationBaseline = parentVideoDurationDraft
        parentVideoIDDraft = "https://www.youtube.com/watch?v=\(videoID)"
        parentFinder.beginConfirm(videoID: videoID)
        noteParentBrowserActivity()
        VisaGamesLog.append("parent browser confirm — 加入呢條片 id=\(videoID) length=\(pageDurationSeconds.map { String(Int($0)) } ?? "?")")
    }

    /// 取消 / Esc on the confirm card: back to the finder, nothing saved.
    func cancelFinderConfirm() {
        parentFinder.cancelConfirm()
        parentDraftTrialVideoID = nil
        parentVideoIDDraft = ""
        parentVideoTitleDraft = ""
        parentVideoDurationDraft = "120"
        parentDraftDurationBaseline = "120"
        parentDraftPageDuration = nil
    }

    /// 加入 / Return on the confirm card. On success the finder stays open (D4).
    func confirmFinderAdd() {
        guard parentFinder.confirmVideoID != nil else { return }
        noteParentBrowserActivity()
        addAllowlistedVideo()
    }

    /// 復原 while the toast shows.
    func undoFinderAdd() {
        guard let id = parentFinder.undo(now: Date()) else { return }
        removeAllowlistedVideo(id: id)
        playbackMessage = "已復原，冇加到。 / Undone, not added."
        VisaGamesLog.append("parent browser undo id=\(id)")
    }

    /// Confirm card: 加入 / 更新 enabled?
    var finderConfirmCanAdd: Bool {
        guard !isFetchingAllowlistMetadata, parentDraftEmbedCheck.allowsAdd else { return false }
        switch parentDraftStatus {
        case .ready: return true
        case .alreadyAllowlisted:
            let titleTyped = !parentVideoTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let durationEdited = parentVideoDurationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                != parentDraftDurationBaseline
            return titleTyped || durationEdited
        case .empty, .invalid: return false
        }
    }

    func noteFinderDataCleared() {
        guard session.mode == .parent else { return }
        playbackMessage = "已清除搵片器資料（小朋友播放器唔受影響）。 / Finder data cleared (child player untouched)."
        VisaGamesLog.append("parent finder data cleared")
    }

    /// Length shown on the add card: page length from the browser or the 試播 player.
    var parentDraftLengthLabel: String? {
        guard let known = parentDraftPageDuration, known.videoID == parentDraftStatus.videoID else { return nil }
        return ApprovedVideo.clockLabel(seconds: known.seconds)
    }

    /// 試播 on the add card plays the draft id in the child's scoped player (parent only).
    func startDraftTrial() {
        guard session.mode == .parent, let id = parentDraftStatus.videoID else { return }
        if activePlayVideoID != nil { stopParentPreview() }
        parentDraftTrialVideoID = id
        noteParentBrowserActivity()
        VisaGamesLog.append("draft trial — 試播 id=\(id)")
    }

    func stopDraftTrial() {
        parentDraftTrialVideoID = nil
    }

    func noteDraftTrialDuration(videoID: String, seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0, videoID == parentDraftStatus.videoID else { return }
        parentDraftPageDuration = (videoID: videoID, seconds: seconds.rounded())
    }

    func handleDraftTrialBlocked(videoID: String) {
        guard session.mode == .parent else { return }
        playbackMessage = "YouTube 要求驗證，試播唔到；照樣可以撳「加入」。 / YouTube bot check — preview failed, you can still Add."
        VisaGamesLog.append("draft trial blocked — 試播被擋 id=\(videoID)")
    }

    /// Public oEmbed title for an id (no API key). Nil on any failure.
    private static func fetchOEmbedTitle(videoID: String) async -> String? {
        await fetchOEmbed(videoID: videoID).title
    }

    /// Title plus the HTTP status (embeddability, 08). Nil status = network failure.
    private static func fetchOEmbed(videoID: String) async -> (title: String?, status: Int?) {
        guard let url = YouTubeOEmbed.requestURL(videoID: videoID) else { return (nil, nil) }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return (nil, nil) }
            guard (200..<300).contains(status) else { return (nil, status) }
            return (YouTubeOEmbed.parse(data)?.title, status)
        } catch {
            return (nil, nil)
        }
    }

    /// Paste field changed: recompute status and fetch the title for a new valid id
    /// (debounced) so the parent sees thumbnail + title before pressing Add.
    private func refreshParentDraftPreview() {
        let previousID = parentDraftStatus.videoID
        let status = ParentAllowlistDraft.evaluate(parentVideoIDDraft, allowlist: allowlist)
        parentDraftStatus = status
        if parentDraftTrialVideoID != nil, parentDraftTrialVideoID != status.videoID { parentDraftTrialVideoID = nil }
        guard let id = status.videoID else {
            draftTitleTask?.cancel()
            draftTitleTask = nil
            parentDraftTitle = nil
            isFetchingDraftTitle = false
            parentDraftEmbedCheck = .unknown
            return
        }
        guard id != previousID else { return }
        draftTitleTask?.cancel()
        draftTitleTask = nil
        if let known = allowlist.video(id: id), known.hasParentTitle {
            parentDraftTitle = known.parentLabel
            isFetchingDraftTitle = false
            parentDraftEmbedCheck = embedCheckCache[id] ?? .unknown
            return
        }
        if let cached = oEmbedTitleCache[id] {
            parentDraftTitle = cached
            isFetchingDraftTitle = false
            parentDraftEmbedCheck = embedCheckCache[id] ?? .embeddable
            return
        }
        parentDraftTitle = nil
        isFetchingDraftTitle = true
        parentDraftEmbedCheck = embedCheckCache[id] ?? .checking
        draftTitleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let result = await Self.fetchOEmbed(videoID: id)
            let title = result.title
            guard let self, !Task.isCancelled, self.parentDraftStatus.videoID == id else { return }
            self.isFetchingDraftTitle = false
            let check = ParentEmbedCheck.from(httpStatus: result.status)
            if check != .unknown { self.embedCheckCache[id] = check }
            self.parentDraftEmbedCheck = check
            if let title {
                self.oEmbedTitleCache[id] = title
                self.parentDraftTitle = title
            }
            VisaGamesLog.append("allowlist preview — 預覽 id=\(id) title=\(title == nil ? "unavailable" : "ok")")
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
        perf.allowlistChanged(op: "remove", video: id)
        if activePlayVideoID == id {
            pendingVideoStopReason = .allowlistRemoved
            activePlayVideoID = nil
            pendingVideoStopReason = nil
            activePlayStartSeconds = nil
            lastKnownPlaybackSeconds = nil
        }
        if session.snapshot.lastIncomplete?.videoID == id {
            clearLastIncomplete(reason: "allowlistRemove")
        }
        refreshParentDraftPreview()
        VisaGamesLog.append("allowlist remove — 移除 id=\(id) count=\(next.videos.count)")
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
        perf.abandonRound(reason: "reset_entry_uat")
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
            if showTimesUp {
                branch = "play-timesUp"
            } else {
                switch PlayStageRoute.route(
                    awaitingDeparture: awaitingDeparture,
                    allowlistCount: allowlist.videos.count,
                    activeVideoID: activePlayVideoID,
                    hasResumeCandidate: resumeCandidate != nil
                ) {
                case .stamp: branch = "play-stamp"
                case .emptyAllowlist: branch = "play-emptyAllowlist"
                case .resumeChoice: branch = "play-resumeChoice"
                case .videoPicker: branch = "play-videoPicker"
                case .watch: branch = "play-watch"
                }
            }
        }
        let starsLabel = selectedStars.map(String.init) ?? "nil"
        VisaGamesLog.append(
            "shell branch=\(branch) — 介面分支 mode=\(session.mode) stars=\(starsLabel) entryCompleted=\(isEntryActivityCompleted) rewardNil=\(session.snapshot.reward == nil) storageFailed=\(storageFailed) ctx=\(context)"
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

    @discardableResult
    func playAllowlisted(id: String) -> PlaybackDecision {
        // Not a policy verdict (storage / wrong mode): no stop reason, so callers never route it.
        let refused = PlaybackDecision(allowed: false, stopReason: nil)
        guard session.mode == .parent || session.mode == .play else { return refused }
        let now = Date()
        let isParentPreview = session.mode == .parent
        if isParentPreview {
            if remainingViewingBudget(at: now) <= 0 {
                seedTestViewingBudget()
            }
            if session.snapshot.endsAt.map({ $0 <= now }) ?? true {
                update { $0.extendVisaKeepingParent(seconds: 600, now: now) }
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
            activePlayStartSeconds = nil
            switch decision.stopReason {
            case .notAllowlisted: playbackMessage = "不在准許清單。 / Not allowlisted."
            case .invalidVideoID: playbackMessage = "影片編號無效。 / Invalid video ID."
            case .budgetExhausted: playbackMessage = "觀看時間用完。 / Viewing budget empty."
            case .sessionExpired: playbackMessage = "簽證已到期。 / Visa expired."
            case .navigationRejected: playbackMessage = "禁止導向。 / Navigation blocked."
            case .providerBlocked: playbackMessage = "YouTube 暫時睇唔到。 / YouTube blocked."
            case .none: playbackMessage = "未能播放。 / Cannot play."
            }
            return decision
        }
        activePlayVideoID = id
        playbackMessage = nil
        showProviderBlocked = false
        // Keep a prior VPN hint until real progress; starting a new try is fine.
        if session.mode == .play { providerBlockedLoadStartedAt = Date() }
        if isParentPreview {
            // Parent preview never resumes and never writes the incomplete cursor.
            activePlayStartSeconds = nil
            lastKnownPlaybackSeconds = nil
            parentDeadline = Date().addingTimeInterval(parentAccessSeconds)
        }
        perfVideoStarted(id: id, source: pendingVideoStartSource ?? (isParentPreview ? "parent_preview" : "legacy"))
        return decision
    }

    // MARK: - D10 performance records (v0.20.0)

    private func perfVideoStarted(id: String, source: String) {
        let now = Date()
        perf.videoStarted(
            video: id,
            source: source,
            startSeconds: activePlayStartSeconds,
            durationSeconds: allowlist.video(id: id)?.playerDurationSeconds,
            visaLeft: session.remaining(at: now),
            budgetLeft: remainingViewingBudget(at: now)
        )
    }

    /// `activePlayVideoID` left `oldID`: close the open play with the pending reason.
    private func perfActivePlayCleared(_ oldID: String) {
        guard perf.openPlayVideoID == oldID else { return }
        let reason = pendingVideoStopReason ?? (session.mode == .parent ? .previewStopped : .unknown)
        let timeUp = reason == .visaExpired || reason == .budgetExhausted
        let saved = timeUp && session.snapshot.lastIncomplete?.videoID == oldID
        perf.endPlay(reason: reason, resumeSaved: saved)
    }

    /// Parent 🧪 家長測試中 switch (60-minute auto-off).
    var perfUATOn: Bool { perf.uat.isOn(at: now) }
    var perfUATMinutesLeft: Int { perf.uat.minutesLeft(at: now) }

    func perfToggleUAT() {
        guard session.mode == .parent else { return }
        perf.setUAT(on: !perf.uat.isOn(at: Date()))
        objectWillChange.send()
    }

    var perfRecentSessions: [PerfSessionSummary] { perf.recentSessions }

    func perfToggleSessionExcluded(_ id: String) {
        guard session.mode == .parent else { return }
        perf.setSessionExcluded(id, excluded: !perf.excludedSessions.contains(id))
        objectWillChange.send()
    }

    func perfExport() {
        guard session.mode == .parent else { return }
        var titles: [String: String] = [:]
        for video in allowlist.videos { titles[video.id] = video.parentLabel }
        perfStatusMessage = "匯出緊…"
        perf.export(titles: titles, order: allowlist.videos.map(\.id)) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let url):
                NSWorkspace.shared.activateFileViewerSelecting([url])
                self.perfStatusMessage = "已匯出，資料夾已開啟。 / Exported."
            case .failure:
                self.perfStatusMessage = "未能匯出表現紀錄。 / Export failed."
            }
        }
    }

    /// 表現: (re)build the report off-main. Called when the segment opens, on 更新, on a window
    /// change and after 唔計呢段 / 計返 — never from a view body.
    func perfRefreshReview() {
        guard session.mode == .parent else { return }
        perfReviewGeneration += 1
        let generation = perfReviewGeneration
        perfReview = .computing(previous: perfReview.report)
        var titles: [String: String] = [:]
        for video in allowlist.videos { titles[video.id] = video.parentLabel }
        perf.buildReport(window: perfReviewWindow, videoIDs: allowlist.videos.map(\.id), titles: titles) { [weak self] report in
            guard let self, generation == self.perfReviewGeneration else { return }
            self.perfReview = .ready(report)
        }
    }

    func perfSetReviewWindow(_ window: PerfReportWindow) {
        guard session.mode == .parent, window != perfReviewWindow else { return }
        perfReviewWindow = window
        perfRefreshReview()
    }

    /// 最近玩過 → 唔計呢段 / 計返 from the 表現 segment (state read back from the log).
    func perfReviewSetSessionExcluded(_ id: String, excluded: Bool) {
        guard session.mode == .parent else { return }
        perf.setSessionExcluded(id, excluded: excluded)
        VisaGamesLog.append("parent review — session \(excluded ? "exclude" : "include")")
        perfRefreshReview()
    }

    func perfClear() {
        guard session.mode == .parent else { return }
        perf.clearAll { [weak self] ok in
            guard let self else { return }
            if ok { self.perfWriteFailed = false }
            self.perfReviewGeneration += 1
            self.perfReview = .idle
            self.perfStatusMessage = ok
                ? "已清除表現紀錄。 / Performance records cleared."
                : "未能清除表現紀錄。 / Could not clear."
        }
    }


    /// v0.21.1: YouTube bot-check / player error / ready-never-playing.
    func handleProviderBlocked(videoID: String, via: String) {
        guard activePlayVideoID == videoID else { return }
        let now = Date()
        let elapsed = providerBlockedLoadStartedAt.map { now.timeIntervalSince($0) } ?? ProviderBlockedPolicy.watchdogSeconds
        let outcome = ProviderBlockedPolicy.applyBlocked(videoID: videoID, elapsed: elapsed, state: providerBlockedState)
        switch outcome {
        case .returnToPicker(let credit, let state):
            providerBlockedState = state
            providerBlockedUnavailableIDs = state.unavailableIDs
            if credit > 0 { update { $0.creditVisaSeconds(credit, now: now) } }
            VisaGamesLog.append(
                "provider blocked — 片睇唔到 id=\(videoID) via=\(via) credit=\(Int(credit))s strikes=\(state.strikes) → board"
            )
            providerBlockedParentHint = "YouTube 要求驗證（可能係 Mac mini 嘅 NordVPN／網絡）。試關 VPN 或換伺服器。 / YouTube verification (Mac mini NordVPN/network?). Try VPN off or another server."
            providerBlockedLoadStartedAt = nil
            if session.mode == .play {
                pendingVideoStopReason = .blocked
                activePlayVideoID = nil
                activePlayStartSeconds = nil
                lastKnownPlaybackSeconds = nil
                pendingVideoStopReason = nil
                showProviderBlocked = true
            } else {
                // Parent 試播: keep the inline player so the parent can see the embed /
                // retry; only surface a dismissible banner (v0.21.3).
                pendingVideoStopReason = .previewStopped
                pendingVideoStopReason = nil
                playbackMessage = nil
                VisaGamesLog.append("provider blocked — parent preview kept playing id=\(videoID)")
            }
        case .timesUp(let credit, let bank, let state):
            providerBlockedState = state
            providerBlockedUnavailableIDs = state.unavailableIDs
            if credit > 0 { update { $0.creditVisaSeconds(credit, now: now) } }
            let leftover = TimeInterval(max(0, session.remaining(at: now)))
            if bank, session.mode == .play, leftover > 0 {
                let calendar = budgetCalendar
                var granted: TimeInterval = 0
                update { session in
                    var ledger: RewardLedger
                    if let state = session.snapshot.reward {
                        ledger = RewardLedger(state: state)
                        ledger.normalizeAfterLoad(now: now, calendar: calendar)
                    } else {
                        ledger = RewardLedger(policy: RewardPolicy(initialAllowanceSeconds: 60, rewardCapSeconds: 1_200))
                    }
                    granted = ledger.creditViewingSeconds(leftover, now: now, calendar: calendar)
                    session.replaceRewardState(ledger.exportState())
                }
                VisaGamesLog.append("provider blocked — banked leftover visa \(Int(granted))s into viewing")
            }
            VisaGamesLog.append(
                "provider blocked — 片睇唔到 id=\(videoID) via=\(via) credit=\(Int(credit))s strikes=\(state.strikes) → timesUp"
            )
            showProviderBlocked = false
            pendingVideoStopReason = .blocked
            finishPlayVisaToTimesUp(reason: "provider-blocked-2strikes")
            pendingVideoStopReason = nil
            providerBlockedParentHint = "YouTube 要求驗證（可能係 Mac mini 嘅 NordVPN／網絡）。試過兩條片都唔得。 / YouTube verification (Mac mini NordVPN/network?). Two videos blocked."
            playbackMessage = providerBlockedParentHint
            clearProviderBlockedVisaState()
        }
    }

    func dismissProviderBlockedParentHint() {
        providerBlockedParentHint = nil
        if playbackMessage?.contains("YouTube") == true {
            playbackMessage = nil
        }
    }

    /// Successful playback progress clears a stale VPN / bot-check banner.
    func noteProviderPlaybackProgress() {
        guard providerBlockedParentHint != nil || (playbackMessage?.contains("YouTube") == true) else { return }
        providerBlockedParentHint = nil
        if playbackMessage?.contains("YouTube") == true { playbackMessage = nil }
        VisaGamesLog.append("provider blocked hint cleared — 有播到")
    }

    func dismissProviderBlocked() {
        guard showProviderBlocked else { return }
        showProviderBlocked = false
        mintVideoPickerOrderSeed(entry: "provider_blocked")
        VisaGamesLog.append("provider blocked dismiss — 返揀片 unavailable=\(providerBlockedUnavailableIDs.count)")
        logShellBranch(context: "providerBlockedDismiss")
    }

    private func clearProviderBlockedVisaState() {
        providerBlockedState = ProviderBlockedPolicy.CreditState()
        providerBlockedUnavailableIDs = []
        showProviderBlocked = false
        providerBlockedLoadStartedAt = nil
    }

    /// Policy (tick) or D8 navigation stop. v0.12.0: in child play, no time left → Time's up
    /// (was: clear id → picker with a dead budget while the road kept ticking).
    func stopScopedPlayback(reason: PlaybackStopReason) {
        let stoppedID = activePlayVideoID
        let isChild = session.mode == .play
        switch reason {
        case .budgetExhausted: pendingVideoStopReason = isChild ? .budgetExhausted : .previewStopped
        case .sessionExpired: pendingVideoStopReason = isChild ? .visaExpired : .previewStopped
        case .navigationRejected: pendingVideoStopReason = isChild ? .navGuard : .previewStopped
        case .providerBlocked: pendingVideoStopReason = isChild ? .blocked : .previewStopped
        case .notAllowlisted, .invalidVideoID: pendingVideoStopReason = .unknown
        }
        let route = VideoEndRouting.afterPlaybackStopped(reason: reason, isChildPlay: isChild)
        if isChild,
           let id = stoppedID,
           IncompletePlaybackPolicy.shouldSaveOnStop(
            isChildPlay: true,
            reason: reason,
            positionSeconds: lastKnownPlaybackSeconds
           ),
           let position = lastKnownPlaybackSeconds {
            persistLastIncomplete(videoID: id, positionSeconds: position, reason: reason.rawValue)
        }
        activePlayVideoID = nil
        pendingVideoStopReason = nil
        activePlayStartSeconds = nil
        lastKnownPlaybackSeconds = nil
        switch reason {
        case .budgetExhausted: playbackMessage = "觀看時間用完，已停止。 / Stopped: budget empty."
        case .sessionExpired: playbackMessage = "簽證到期，已停止。 / Stopped: visa expired."
        case .navigationRejected: playbackMessage = "已阻擋連結。 / Link blocked (D8)."
        case .providerBlocked: playbackMessage = "YouTube 暫時睇唔到（網絡／VPN？）。 / YouTube blocked (network/VPN?)."
        default: playbackMessage = "已停止播放。 / Playback stopped."
        }
        VisaGamesLog.append(
            "playback stop — 停止播放 id=\(stoppedID ?? "nil") reason=\(reason.rawValue) route=\(route) mode=\(session.mode)"
        )
        if route == .timesUp {
            finishPlayVisaToTimesUp(reason: "stop-\(reason.rawValue)")
        } else if route == .videoPicker {
            mintVideoPickerOrderSeed(entry: "stop_return")
        }
    }

    /// ScopedPlayer reported YouTube ended (state 0) for the current allowlisted video.
    /// Time left → same visa back to `VideoPickerView`; no time left → Time's up board.
    func handleScopedPlaybackEnded(videoID: String) {
        let now = Date()
        let budget = remainingViewingBudget(at: now)
        let route = VideoEndRouting.afterVideoEnded(
            isChildPlay: session.mode == .play,
            hasActiveVideo: activePlayVideoID == videoID,
            remainingViewingBudgetSeconds: budget,
            sessionEndsAt: session.snapshot.endsAt,
            now: now
        )
        VisaGamesLog.append(
            "video ended — 片播完 id=\(videoID) route=\(route) mode=\(session.mode) viewing=\(Int(budget)) visaLeft=\(session.remaining(at: now))s"
        )
        if route != .ignore { pendingVideoStopReason = .ended }
        defer { pendingVideoStopReason = nil }
        switch route {
        case .videoPicker:
            clearLastIncomplete(reason: "ended")
            activePlayVideoID = nil
            activePlayStartSeconds = nil
            lastKnownPlaybackSeconds = nil
            playbackMessage = nil
            // Clip ended with time left: a new visit, a new deck. Refused picks do not come through here.
            mintVideoPickerOrderSeed(entry: "ended_time_left")
            VisaGamesLog.append("video ended → picker — 返揀片 visaLeft=\(session.remaining(at: now))s")
            logShellBranch(context: "videoEnded")
        case .timesUp:
            // Natural end with no time left: clear cursor (video finished).
            clearLastIncomplete(reason: "ended")
            activePlayStartSeconds = nil
            lastKnownPlaybackSeconds = nil
            finishPlayVisaToTimesUp(reason: "videoEnded")
        case .stopPreview:
            activePlayVideoID = nil
            activePlayStartSeconds = nil
            lastKnownPlaybackSeconds = nil
            playbackMessage = "影片播完。 / Video finished."
        case .ignore:
            break
        }
    }

    /// No viewing time left during child play: end the play visa so the existing visa-ended
    /// seam in `update` shows Time's up (park and sleep). Never used for parent preview.
    private func finishPlayVisaToTimesUp(reason: String) {
        activePlayVideoID = nil
        activePlayStartSeconds = nil
        lastKnownPlaybackSeconds = nil
        guard session.mode == .play else { return }
        let now = Date()
        VisaGamesLog.append(
            "visa end → timesUp — 冇時間喇 reason=\(reason) viewing=\(Int(remainingViewingBudget(at: now))) visaLeft=\(session.remaining(at: now))s"
        )
        guideVoice.stop()
        pendingVisaEndReason = "no_time_left"
        update { $0.endPlayVisa(now: now) }
        pendingVisaEndReason = nil
        logShellBranch(context: "timesUp-\(reason)")
    }

    /// Real length from the player → parent card chip only (D4 `durationSeconds` unchanged).
    func recordPlayerDuration(videoID: String, seconds: TimeInterval) {
        perf.playDuration(video: videoID, seconds: seconds)
        var next = allowlist
        guard next.recordPlayerDuration(id: videoID, seconds: seconds) else { return }
        allowlist = next
        allowlistStore.save(next)
        VisaGamesLog.append("allowlist duration — 片長 id=\(videoID) seconds=\(Int(seconds.rounded()))")
    }

    /// Parent card: stop the inline preview player.
    func stopParentPreview() {
        guard session.mode == .parent else { return }
        pendingVideoStopReason = .previewStopped
        activePlayVideoID = nil
        pendingVideoStopReason = nil
        playbackMessage = nil
    }

    /// Parent-only: reveal the active ScopedPlayer log directory in Finder.
    func openScopedPlayerLogsFolder() {
        guard session.mode == .parent else { return }
        VisaGamesLog.openActiveDirectory()
        let path = VisaGamesLog.activeLogDirectory.path
        playbackMessage = "日誌資料夾已開啟。 / Logs folder opened.\n" + path
        VisaGamesLog.append("openLogsFolder — 開啟日誌 path=\(path)")
    }

    // MARK: - 連一連 / Line Match (v0.23.0, ADR 0012)

    /// The 連一連 board on screen: the playtest copy while a parent is reviewing it.
    var currentLineMatchBoard: LineMatchBoard {
        lineMatchUsesPlaytest ? playtestLineMatchBoard : lineMatchBoard
    }

    private var lineMatchUsesPlaytest: Bool { isParentPlaytest && playtestKind?.isLineMatchFamily == true }

    /// Runs one board change when input is open (round on 連一連, not in a Think Pause), then
    /// refreshes the round's `round_result` extras. Nil = input ignored.
    private func changeLineMatchBoard<T>(_ change: (inout LineMatchBoard) -> T) -> T? {
        // Guided rounds have no free lines, 擦晒 or 完成.
        guard currentLineMatchGuidedBoard == nil else { return nil }
        if lineMatchUsesPlaytest {
            guard !playtestChoicesLocked else { return nil }
            var board = playtestLineMatchBoard
            let result = change(&board)
            playtestLineMatchBoard = board
            perf.playtestResultExtra(board.resultFields)
            return result
        }
        guard session.mode == .lock, taskRoundOpen, activeActivityKind?.isLineMatchFamily == true else { return nil }
        guard !choicesLocked else {
            perf.roundMashTap()
            return nil
        }
        var board = lineMatchBoard
        let result = change(&board)
        lineMatchBoard = board
        perf.roundResultExtra(board.resultFields)
        return result
    }

    private func showLineMatchNotice(_ prompt: SpokenPrompt) {
        lineMatchNotice = prompt
        guideVoice.speak(prompt)
    }

    /// Pen down at a stage point (1280 × 720 units). Returns the row the truck draws from.
    func lineMatchBeginDrag(x: Double, y: Double) -> Int? {
        let start = changeLineMatchBoard { $0.beginDrag(at: LineMatchPoint(x: x, y: y)) }
        switch start {
        case .started(let row)?:
            lineMatchNotice = nil
            return row
        case .wrongDirection?:
            // Motor slip, never a miss (design §6 step 6; counted as `wrong_direction`).
            showLineMatchNotice(SpokenPrompt(key: "lineMatch.startGreen",
                                             traditionalChinese: LineMatchCopy.startGreenTraditionalChinese,
                                             english: LineMatchCopy.startGreenEnglish))
            VisaGamesLog.append("lineMatch wrong direction — 由綠點開始 (no miss)")
            return nil
        default:
            return nil
        }
    }

    /// Pen up. Joins the line or lets it spring back; never judged here (D3).
    func lineMatchEndDrag(x: Double, y: Double) {
        guard let outcome = changeLineMatchBoard({ $0.endDrag(at: LineMatchPoint(x: x, y: y)) }) else { return }
        let board = currentLineMatchBoard
        switch outcome {
        case .joined(_, let slot, _), .unchanged(_, let slot):
            // Read the card that was joined, never whether it is right (design §6 step 4–5).
            if let pair = board.question.rightPair(atSlot: slot) {
                guideVoice.speak(SpokenPrompt(key: "lineMatch.word.\(pair.key)",
                                              traditionalChinese: pair.labelTraditionalChinese,
                                              english: pair.labelEnglish))
            }
        case .retracted:
            VisaGamesLog.append("lineMatch line retracted — 彈返 (incomplete_stroke, no miss)")
        case .ignored:
            break
        }
    }

    /// Gesture lost (window change, system cancel): the live line is dropped.
    func lineMatchCancelDrag() {
        if lineMatchUsesPlaytest {
            playtestLineMatchBoard.cancelDrag()
        } else {
            lineMatchBoard.cancelDrag()
        }
    }

    /// 擦晒: clears unjudged lines only. 3 s cooldown, 4th use nudges 完成, 6th hides it.
    func lineMatchErase() {
        let clock = Date().timeIntervalSinceReferenceDate
        guard let outcome = changeLineMatchBoard({ $0.erase(now: clock) }) else { return }
        guard case .cleared(let lines, let nudge, let hidden) = outcome else { return }
        if nudge {
            showLineMatchNotice(SpokenPrompt(key: "lineMatch.tryDone",
                                             traditionalChinese: LineMatchCopy.tryDoneTraditionalChinese,
                                             english: LineMatchCopy.tryDoneEnglish))
        } else {
            lineMatchNotice = nil
        }
        VisaGamesLog.append(
            "lineMatch erase — 擦晒 lines=\(lines) uses=\(currentLineMatchBoard.eraserUses) nudge=\(nudge) hidden=\(hidden)"
        )
    }

    /// 完成: judged once. Any wrong line = one miss (existing wrong-answer policy); right lines
    /// stay green, wrong ones clear. All right = the existing success flow.
    func lineMatchSubmit() {
        guard let outcome = changeLineMatchBoard({ $0.submit() }) else { return }
        let board = currentLineMatchBoard
        switch outcome {
        case .notReady(let missing):
            showLineMatchNotice(SpokenPrompt(key: "lineMatch.notReady",
                                             traditionalChinese: LineMatchCopy.notReadyTraditionalChinese,
                                             english: LineMatchCopy.notReadyEnglish))
            VisaGamesLog.append("lineMatch done not ready — 仲有未連 missing=\(missing) (no miss)")
        case .judged(let judgement):
            lineMatchNotice = nil
            pendingAnswerRecord = board.submitRecord(judgement)
            VisaGamesLog.append(
                "lineMatch done — 完成 submit=\(board.submits) right=\(judgement.correct.count) wrong=\(judgement.wrong.count) item=\(board.question.itemID)"
            )
            if lineMatchUsesPlaytest {
                let evaluation: ActivityEvaluation = judgement.solved ? .correct(assisted: playtestHintUsed) : .incorrect
                playtestHandle(evaluation, selectionLabel: LineMatchSubmit.choice)
            } else {
                let evaluation: ActivityEvaluation = judgement.solved ? .correct(assisted: entryHintUsed) : .incorrect
                handleEvaluation(evaluation, selectionLabel: LineMatchSubmit.choice)
            }
            pendingAnswerRecord = nil
        case .ignored:
            break
        }
    }

    // MARK: 連一連 guided roads (v0.24.0, ADR 0013)

    /// The guided board on screen (playtest copy while a parent reviews it). Nil = free match.
    var currentLineMatchGuidedBoard: LineMatchGuidedBoard? {
        lineMatchUsesPlaytest ? playtestLineMatchGuidedBoard : lineMatchGuidedBoard
    }

    /// Guided input is open: the round (or playtest) is on 連一連 and not finished.
    private var guidedInputOpen: Bool {
        if lineMatchUsesPlaytest { return !playtestCompleted && playtestLineMatchGuidedBoard != nil }
        return session.mode == .lock && taskRoundOpen && activeActivityKind?.isLineMatchFamily == true
            && !activityJustCompleted && lineMatchGuidedBoard != nil
    }

    /// The view drives the truck locally and hands the board over on pen-up and when a road is
    /// done. Only a board that grew from the current one is taken (never a stale copy). A newly
    /// finished road reads its word (Cantonese, then English); the last one ends the round.
    func lineMatchGuidedCommit(_ next: LineMatchGuidedBoard) {
        guard guidedInputOpen, let current = currentLineMatchGuidedBoard else { return }
        guard next.isMonotonicSuccessor(of: current) else {
            VisaGamesLog.append("lineMatch guided commit refused — 舊版本 item=\(next.question.itemID)")
            return
        }
        guard next != current else { return }
        if lineMatchUsesPlaytest {
            playtestLineMatchGuidedBoard = next
            perf.playtestResultExtra(next.resultFields)
        } else {
            lineMatchGuidedBoard = next
            perf.roundResultExtra(next.resultFields)
        }
        if lineMatchNotice != nil, next.progress != current.progress { lineMatchNotice = nil }
        let finished = next.doneRows.dropFirst(current.doneRows.count)
        guard let row = finished.last, next.question.pairs.indices.contains(row) else { return }
        let pair = next.question.pairs[row]
        guideVoice.speakWordCue(LineMatchGuidedCopy.cue(pair))
        VisaGamesLog.append(
            "lineMatch guided road — 送到 row=\(row) word=\(pair.key) done=\(next.doneRows.count)/\(next.roads.count) offPath=\(next.offPathCount) (no miss)"
        )
        guard next.isComplete, !current.isComplete else { return }
        // Let the word be heard, then the existing success flow (no 完成 in guided mode).
        let token = lineMatchUsesPlaytest ? playtestChoiceDealSeed : choiceDealSeed
        let playtest = lineMatchUsesPlaytest
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.finishGuidedRound(token: token, playtest: playtest)
        }
    }

    /// Every road is driven. Practice only: no `answer_attempt`, no miss, no Think Pause —
    /// the child round goes straight to the usual stamp / visa (not assisted).
    private func finishGuidedRound(token: String, playtest: Bool) {
        if playtest {
            guard isParentPlaytest, playtestKind?.isLineMatchFamily == true, playtestChoiceDealSeed == token,
                  !playtestCompleted, playtestLineMatchGuidedBoard?.isComplete == true else { return }
            perf.playtestSolved(earnedMinutes: playtestPendingMinutes, assisted: false)
            playtestLastCorrectID = LineMatchMode.guided.rawValue
            playtestCompleted = true
            playtestFuelMessage = nil
            VisaGamesLog.append("playtest guided done — 試玩引導完成 local no visa")
            return
        }
        guard session.mode == .lock, taskRoundOpen, activeActivityKind?.isLineMatchFamily == true, choiceDealSeed == token,
              !activityJustCompleted, lineMatchGuidedBoard?.isComplete == true else { return }
        guard pendingAwardMinutes > 0 else {
            VisaGamesLog.append("lineMatch guided done blocked — pending=0 → depot")
            returnToDepotOutOfFuel()
            return
        }
        lastCorrectChoiceID = LineMatchMode.guided.rawValue
        lastIncorrectChoiceID = nil
        activityJustCompleted = true
        VisaGamesLog.append(
            "lineMatch guided done — 全部送到 item=\(lineMatchBoard.question.itemID) earnedMin=\(pendingAwardMinutes) (practice, no mastery)"
        )
        applyEntrySuccess(assisted: false)
    }

    /// Pen down on a red dot / picture: 「由綠點開始啊！」. Never a miss.
    func lineMatchGuidedWrongStart() {
        guard guidedInputOpen else { return }
        showLineMatchNotice(LineMatchGuidedCopy.wrongStartPrompt)
        VisaGamesLog.append("lineMatch guided wrong start — 由綠點開始 (no miss)")
    }

    /// The off-road hint just appeared: Stampy says it at most once per road.
    func lineMatchGuidedHintShown(row: Int) {
        guard guidedInputOpen else { return }
        guard guidedHintSpokenRows.insert(row).inserted else { return }
        guideVoice.speak(LineMatchGuidedCopy.offRoadPrompt)
        VisaGamesLog.append("lineMatch guided hint — 架車等緊你 row=\(row) (no miss)")
    }

    // MARK: 連一連 parent settings (shared by 沿路送 / 沿路過橋 / 自己配)


    func setLineMatchTolerance(_ tolerance: LineMatchTolerance) {
        guard session.mode == .parent, tolerance != lineMatchSettings.tolerance else { return }
        saveLineMatchSettings(lineMatchSettings.withTolerance(tolerance), what: "tolerance",
                              value: tolerance.rawValue)
    }

    func adjustLineMatchWeight(_ category: LineMatchCategory, steps: Int) {
        guard session.mode == .parent else { return }
        guard let next = lineMatchSettings.adjusting(category, steps: steps) else {
            lineMatchSettingsBanner = "最少要留一個類別 / Keep at least one category"
            return
        }
        saveLineMatchSettings(next, what: "category_weight", value: "\(category.rawValue):\(next.weight(category))")
    }

    func resetLineMatchMix() {
        guard session.mode == .parent else { return }
        saveLineMatchSettings(lineMatchSettings.withDefaultMix(), what: "category_mix", value: "default")
    }

    private func saveLineMatchSettings(_ next: LineMatchSettings, what: String, value: String) {
        lineMatchSettings = next
        lineMatchSettingsStore.save(next)
        lineMatchSettingsBanner = nil
        perf.lineMatchSettingChanged(what: what, value: value, mix: next.mixDescription)
        VisaGamesLog.append("lineMatch settings — 連一連設定 \(what)=\(value) mix=\(next.mixDescription) tolerance=\(next.tolerance.rawValue)")
    }

    // MARK: - 畫線畫形 / Lines & Shapes (v0.25.0, ADR 0014)

    private func makeShapeTraceBoard(seed: String, kind: ActivityKind, avoidingItem: String?) -> ShapeTraceBoard {
        let question = ShapeTraceGenerator.make(seed: seed, kind: kind, settings: shapeTraceSettings,
                                                avoidingItem: avoidingItem)
        return ShapeTraceBoard(question: question,
                               tolerance: shapeTraceSettings.effectiveTolerance(lineMatch: lineMatchSettings.tolerance),
                               directionHint: shapeTraceSettings.directionHint)
    }

    private var shapeTraceUsesPlaytest: Bool { isParentPlaytest && playtestKind?.isShapeTraceFamily == true }

    /// The shape-trace board on screen (playtest copy while a parent reviews it).
    var currentShapeTraceBoard: ShapeTraceBoard? {
        shapeTraceUsesPlaytest ? playtestShapeTraceBoard : shapeTraceBoard
    }

    private var shapeTraceInputOpen: Bool {
        if shapeTraceUsesPlaytest { return !playtestCompleted && playtestShapeTraceBoard != nil }
        return session.mode == .lock && taskRoundOpen && activeActivityKind?.isShapeTraceFamily == true
            && !activityJustCompleted && shapeTraceBoard != nil
    }

    /// The view drives the vehicle on a local copy and hands the board over on pen-up and at
    /// every milestone (corner, stroke, shape). Only a board that grew from the current one is
    /// taken. Corners and stroke ends say 「停！」 (corner stop on); a finished shape says its
    /// name, Cantonese then English (「三角形、triangle」); the last one ends the round.
    func shapeTraceCommit(_ next: ShapeTraceBoard) {
        guard shapeTraceInputOpen, let current = currentShapeTraceBoard else { return }
        guard next.isMonotonicSuccessor(of: current) else {
            VisaGamesLog.append("shapeTrace commit refused — 舊版本 item=\(next.question.itemID)")
            return
        }
        guard next != current else { return }
        if shapeTraceUsesPlaytest {
            playtestShapeTraceBoard = next
            perf.playtestResultExtra(next.resultFields)
        } else {
            shapeTraceBoard = next
            perf.roundResultExtra(next.resultFields)
        }
        if shapeTraceNotice != nil, next.strokesDone != current.strokesDone || next.progress > current.progress + 20 {
            shapeTraceNotice = nil
        }
        let coaching = shapeTraceSettings.cornerStop
        if next.erases > current.erases {
            // ★★★ 擦晒: the current shape only (finished shapes never change). Never a miss.
            if next.erasesThisShape == ShapeTraceBoard.eraserNudgeAt { showShapeTraceNotice(ShapeTraceCopy.eraserNudgePrompt) }
            VisaGamesLog.append(
                "shapeTrace 擦晒 shape=\(next.shapeIndex) presses=\(next.erasesThisShape) hidden=\(next.eraserHidden) (no miss)"
            )
        }
        if next.shapeIndex > current.shapeIndex, next.shapes.indices.contains(current.shapeIndex) {
            let shape = next.shapes[current.shapeIndex]
            // Lines: the next line's start words follow the cue (「打直，向落！」). Shapes: the first
            // of its group this round adds the link (「正方形好似「口」字！」); a built car says 嘟嘟.
            let follow: SpokenPrompt?
            if next.isComplete, next.question.scene == .garage {
                follow = ShapeTraceCopy.buildDonePrompt
            } else if let index = next.currentShape, next.shapes[index].kind.isLine {
                follow = ShapeTraceCopy.start(next.shapes[index].kind)
            } else if !shape.kind.isLine,
                      !next.shapes.prefix(current.shapeIndex).contains(where: { $0.kind.mixGroup == shape.kind.mixGroup }) {
                follow = ShapeTraceCopy.link(shape.kind)
            } else {
                follow = nil
            }
            guideVoice.speakWordCue(ShapeTraceCopy.cue(shape.kind), then: follow)
            VisaGamesLog.append(
                "shapeTrace shape done — 畫好 slot=\(shape.slot) kind=\(shape.kind.rawValue) done=\(next.shapeIndex)/\(next.shapes.count) offPath=\(next.offPathCount) lifts=\(next.lifts) (practice, no miss)"
            )
        } else if next.strokesDone > current.strokesDone {
            if coaching { guideVoice.speak(ShapeTraceCopy.stopPrompt) }
            VisaGamesLog.append("shapeTrace stroke done — 停 shape=\(current.shapeIndex) stroke=\(current.strokeIndex)")
        } else if next.cornersReached.count > current.cornersReached.count {
            if coaching { guideVoice.speak(ShapeTraceCopy.cornerPrompt) }
            VisaGamesLog.append("shapeTrace corner — 停！轉彎！ shape=\(next.shapeIndex) stroke=\(next.strokeIndex)")
        } else if next.cornerOvershoots > current.cornerOvershoots {
            if coaching { showShapeTraceNotice(ShapeTraceCopy.cornerPrompt) }
            VisaGamesLog.append("shapeTrace corner overshoot — 衝過角位 (tag only, no miss)")
        }
        guard next.isComplete, !current.isComplete else { return }
        let token = shapeTraceUsesPlaytest ? playtestChoiceDealSeed : choiceDealSeed
        let playtest = shapeTraceUsesPlaytest
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            self?.finishShapeTraceRound(token: token, playtest: playtest)
        }
    }

    /// Everything is drawn. Practice only: no `answer_attempt`, no miss — the child round goes
    /// straight to the usual stamp / visa (not assisted). A finished 試玩 unlocks the stars (D11).
    private func finishShapeTraceRound(token: String, playtest: Bool) {
        if playtest {
            guard isParentPlaytest, let kind = playtestKind, kind.isShapeTraceFamily, playtestChoiceDealSeed == token,
                  !playtestCompleted, playtestShapeTraceBoard?.isComplete == true else { return }
            perf.playtestSolved(earnedMinutes: playtestPendingMinutes, assisted: false)
            playtestLastCorrectID = "shape_trace"
            playtestCompleted = true
            playtestFuelMessage = nil
            if parentPlaytestLog.playtestedOn(kind) == nil {
                parentPlaytestLog = parentPlaytestLog.recording(kind, on: Date())
                parentPlaytestLogStore.save(parentPlaytestLog)
                if gameAssignmentBanner == ParentPlaytestLog.needsPlaytestBanner { gameAssignmentBanner = nil }
            }
            VisaGamesLog.append("playtest shapeTrace done — 試玩畫線畫形完成 kind=\(kind.rawValue) stars unlocked, no visa")
            return
        }
        guard session.mode == .lock, taskRoundOpen, activeActivityKind?.isShapeTraceFamily == true,
              choiceDealSeed == token, !activityJustCompleted, shapeTraceBoard?.isComplete == true else { return }
        guard pendingAwardMinutes > 0 else {
            VisaGamesLog.append("shapeTrace done blocked — pending=0 → depot")
            returnToDepotOutOfFuel()
            return
        }
        lastCorrectChoiceID = "shape_trace"
        lastIncorrectChoiceID = nil
        activityJustCompleted = true
        VisaGamesLog.append(
            "shapeTrace done — 全部畫好 item=\(shapeTraceBoard?.question.itemID ?? "") earnedMin=\(pendingAwardMinutes) (practice, no mastery)"
        )
        applyEntrySuccess(assisted: false)
    }

    private func showShapeTraceNotice(_ prompt: SpokenPrompt) {
        shapeTraceNotice = prompt
        guideVoice.speak(prompt)
    }

    /// Pen down on another stroke's marker: 「由綠色箭嘴開始啊！」. Never a miss.
    func shapeTraceWrongStart() {
        guard shapeTraceInputOpen else { return }
        showShapeTraceNotice(ShapeTraceCopy.wrongStartPrompt)
        VisaGamesLog.append("shapeTrace wrong start — 由綠色箭嘴開始 (no miss)")
    }

    /// Pen down on the red end with the direction hint on: 「跟住箭嘴方向畫啊！」. Never a miss.
    func shapeTraceReverse() {
        guard shapeTraceInputOpen else { return }
        showShapeTraceNotice(ShapeTraceCopy.reversePrompt)
        VisaGamesLog.append("shapeTrace reverse start — 跟住箭嘴方向 (no miss)")
    }

    /// The off-path hint just appeared: said at most once per stroke.
    func shapeTraceHintShown(key: String) {
        guard shapeTraceInputOpen else { return }
        guard shapeTraceHintSpoken.insert(key).inserted else { return }
        guideVoice.speak(ShapeTraceCopy.offPathPrompt)
        VisaGamesLog.append("shapeTrace hint — 架車等緊你 stroke=\(key) (no miss)")
    }

    // MARK: 畫形狀設定 (shared by the shape-trace cards)

    func adjustShapeTraceWeight(_ shape: ShapeTraceMixShape, steps: Int) {
        guard session.mode == .parent else { return }
        guard let next = shapeTraceSettings.adjusting(shape, steps: steps) else {
            shapeTraceSettingsBanner = "最少要留一款形狀 / Keep at least one shape"
            return
        }
        saveShapeTraceSettings(next, what: "shape_weight", value: "\(shape.rawValue):\(next.weight(shape))")
    }

    func resetShapeTraceMix() {
        guard session.mode == .parent else { return }
        saveShapeTraceSettings(shapeTraceSettings.withDefaultMix(), what: "shape_mix", value: "default")
    }

    func setShapeTraceTolerance(_ tolerance: LineMatchTolerance?) {
        guard session.mode == .parent, tolerance != shapeTraceSettings.tolerance else { return }
        var next = shapeTraceSettings
        next.tolerance = tolerance
        saveShapeTraceSettings(next, what: "tolerance", value: tolerance?.rawValue ?? "follow_lineMatch")
    }

    func setShapeTraceDirectionHint(_ on: Bool) {
        guard session.mode == .parent, on != shapeTraceSettings.directionHint else { return }
        var next = shapeTraceSettings
        next.directionHint = on
        saveShapeTraceSettings(next, what: "direction_hint", value: on ? "on" : "off")
    }

    func setShapeTraceCornerStop(_ on: Bool) {
        guard session.mode == .parent, on != shapeTraceSettings.cornerStop else { return }
        var next = shapeTraceSettings
        next.cornerStop = on
        saveShapeTraceSettings(next, what: "corner_stop", value: on ? "on" : "off")
    }

    func setShapeTraceSlantLines(_ on: Bool) {
        guard session.mode == .parent, on != shapeTraceSettings.slantLines else { return }
        var next = shapeTraceSettings
        next.slantLines = on
        saveShapeTraceSettings(next, what: "slant_lines", value: on ? "on" : "off")
    }

    func setShapeTraceDotStyle(_ style: ShapeTraceDotStyle) {
        guard session.mode == .parent, style != shapeTraceSettings.dotStyle else { return }
        var next = shapeTraceSettings
        next.dotStyle = style
        saveShapeTraceSettings(next, what: "dot_style", value: style.rawValue)
    }

    private func saveShapeTraceSettings(_ next: ShapeTraceSettings, what: String, value: String) {
        shapeTraceSettings = next
        shapeTraceSettingsStore.save(next)
        shapeTraceSettingsBanner = nil
        perf.shapeTraceSettingChanged(what: what, value: value, mix: next.mixDescription)
        VisaGamesLog.append("shapeTrace settings — 畫形狀設定 \(what)=\(value) mix=\(next.mixDescription)")
    }

    // MARK: - Parent game catalog + playtest (no visa)

    func toggleMissionStar(kind: ActivityKind, star: ChildDifficulty) {
        guard session.mode == .parent else { return }
        // D11: a shape-trace card gets its first star only after one full 試玩 (turning off is fine).
        if !gameAssignment.isEnabled(kind, star: star), !parentPlaytestLog.allowsStars(for: kind) {
            gameAssignmentBanner = ParentPlaytestLog.needsPlaytestBanner
            VisaGamesLog.append("game assignment refused — 試玩一次先開 kind=\(kind.rawValue) star=\(star.rawValue)")
            return
        }
        switch gameAssignment.toggling(kind, star: star) {
        case .updated(let next):
            gameAssignment = next
            gameAssignmentStore.save(next)
            gameAssignmentBanner = nil
            perf.assignmentChanged(kind: kind, star: star.rawValue, on: next.isEnabled(kind, star: star))
            VisaGamesLog.append(
                "game assignment — 星級 kind=\(kind.rawValue) star=\(star.rawValue) on=\(next.isEnabled(kind, star: star))"
            )
        case .rejectedLastStar:
            gameAssignmentBanner = MissionGameAssignment.emptyTierBanner
            VisaGamesLog.append("game assignment rejected — 最後一個星級 star=\(star.rawValue)")
        }
    }

    /// Cover on parent settings. Does not call selectDifficulty, grant, or the ledger.
    func startPlaytest(kind: ActivityKind) {
        guard session.mode == .parent else { return }
        guard ActivityCatalog.playableKinds.contains(kind) else { return }
        stopParentPreview()
        discardPlaytestCover(reason: "restart")
        playtestHighlightedKind = nil
        playtestKind = kind
        playtestHintUsed = false
        playtestMissCount = 0
        playtestLastIncorrectID = nil
        playtestLastCorrectID = nil
        playtestCompleted = false
        playtestPendingMinutes = 5
        playtestStartingMinutes = 5
        playtestFuelMessage = nil
        playtestSequenceTaps = []
        playtestChoiceDealSeed = UUID().uuidString
        let level = playtestNextLevel[kind] ?? .l1
        playtestNextLevel[kind] = level.cycled
        playtestLevel = level
        playtestFindSameQuestion = ActivityCatalog.findSameQuestion(seed: playtestChoiceDealSeed, level: level)
        playtestCountQuestion = ActivityCatalog.countQuestion(seed: playtestChoiceDealSeed, level: level)
        let playtestLineMatchQuestion: LineMatchQuestion
        if let deal = kind.lineMatchDeal(missionLevel: level) {
            // Guided kinds pin geometry (straight = L1, bridge = L2); free match cycles L1→L2→L3.
            playtestLineMatchQuestion = ActivityCatalog.lineMatchQuestion(
                seed: playtestChoiceDealSeed, level: deal.level, settings: lineMatchSettings, mode: deal.mode)
        } else {
            playtestLineMatchQuestion = ActivityCatalog.lineMatchQuestion()
        }
        playtestLineMatchBoard = LineMatchBoard(question: playtestLineMatchQuestion,
                                                tolerance: lineMatchSettings.tolerance)
        playtestLineMatchGuidedBoard = playtestLineMatchQuestion.isGuided
            ? LineMatchGuidedBoard(question: playtestLineMatchQuestion, tolerance: lineMatchSettings.tolerance) : nil
        guidedHintSpokenRows = []
        lineMatchNotice = nil
        playtestShapeTraceBoard = kind.isShapeTraceFamily
            ? makeShapeTraceBoard(seed: playtestChoiceDealSeed, kind: kind, avoidingItem: nil) : nil
        shapeTraceHintSpoken = []
        shapeTraceNotice = nil
        playtestTapCountBoard = kind.isTapCountFamily
            ? makeTapCountBoard(seed: playtestChoiceDealSeed, kind: kind, avoidingItem: nil) : nil
        playtestTapLetterBoard = kind.isTapLetterFamily ? makeTapLetterBoard(seed: playtestChoiceDealSeed) : nil
        tapLetterWriteRound = kind == .tapLetterWrite ? playtestTapLetterBoard.map { TapLetterWriteRound(deal: $0.deal) } : nil
        tapLetterGuideRun = nil
        tapLetterGuideSpeechGeneration += 1
        tapLetterCuspSpoken = false
        tapLetterBubble = nil
        tapLetterCelebrating = false
        tapLetterStrokeReveal = nil
        tapLetterPlaqueNudge = false
        tapLetterLastActionAt = Date().timeIntervalSinceReferenceDate
        tapLetterRoundStart = tapLetterLastActionAt
        tapLetterIdleSpoken = false
        tapLetterPenaltyPending = false
        resetTapCountTransient()
        clearPlaytestThinkPause()
        let facts = dealFacts(kind: kind, seed: playtestChoiceDealSeed,
                              findSame: playtestFindSameQuestion, count: playtestCountQuestion,
                              lineMatch: playtestLineMatchBoard.question, shapeTrace: playtestShapeTraceBoard,
                              tapCount: playtestTapCountBoard)
        noteTapCountDealt(playtestTapCountBoard)
        perf.playtestStarted(round: playtestChoiceDealSeed, kind: kind, pendingStart: playtestStartingMinutes,
                             facts: facts)
        VisaGamesLog.append("playtest start — 試玩 kind=\(kind.rawValue) level=\(level.code) item=\(facts.item) mode=parent visa=false")
    }

    /// 返回家長. Mode stays `.parent` until the settings bar Return / auto-lock says otherwise.
    func endPlaytestToParent() {
        guard session.mode == .parent, let kind = playtestKind else { return }
        discardPlaytestCover(reason: "backToParent")
        playtestHighlightedKind = kind
    }

    func speakPlaytestPrompt() {
        guard isParentPlaytest, let kind = playtestKind else { return }
        let zh: String
        let en: String
        switch kind {
        case .twoPictureChoose:
            zh = twoPictureQuestion.promptTraditionalChinese
            en = twoPictureQuestion.promptEnglish
        case .findTheSame:
            zh = playtestFindSameQuestion.promptTraditionalChinese
            en = playtestFindSameQuestion.promptEnglish
        case .countVehicles:
            zh = playtestCountQuestion.promptTraditionalChinese
            en = playtestCountQuestion.promptEnglish
        case .sequenceShortToLong:
            zh = sequenceQuestion.promptTraditionalChinese
            en = sequenceQuestion.promptEnglish
        case .halfMatch:
            zh = halfMatchQuestion.promptTraditionalChinese
            en = halfMatchQuestion.promptEnglish
        case .shapeCousin:
            zh = shapeCousinQuestion.promptTraditionalChinese
            en = shapeCousinQuestion.promptEnglish
        case .capacityCompare:
            zh = capacityCompareQuestion.promptTraditionalChinese
            en = capacityCompareQuestion.promptEnglish
        case .moreFewer:
            zh = moreFewerQuestion.promptTraditionalChinese
            en = moreFewerQuestion.promptEnglish
        case .shadowMatch:
            zh = shadowMatchQuestion.promptTraditionalChinese
            en = shadowMatchQuestion.promptEnglish
        case .emptyBay:
            zh = emptyBayQuestion.promptTraditionalChinese
            en = emptyBayQuestion.promptEnglish
        case .lineMatch, .lineMatchGuidedStraight, .lineMatchGuidedBridge:
            zh = playtestLineMatchBoard.question.promptTraditionalChinese
            en = playtestLineMatchBoard.question.promptEnglish
        case .traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree:
            let question = playtestShapeTraceBoard?.question ?? ShapeTraceGenerator.reference(kind: kind)
            zh = question.promptTraditionalChinese
            en = question.promptEnglish
        case .tapCountAll, .tapCountTrace, .tapCountPick, .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish:
            speakTapCountPrompt()
            return
        case .tapLetterAll, .tapLetterWrite:
            speakTapLetterPrompt()
            return
        }
        guideVoice.speak(SpokenPrompt(
            key: "playtest.\(kind.rawValue)",
            traditionalChinese: zh,
            english: en
        ))
    }

    func playtestSelectEntry(id: String) {
        guard isParentPlaytest, playtestKind == .twoPictureChoose, !playtestChoicesLocked else { return }
        let evaluation = activityEvaluator.evaluate(
            question: twoPictureQuestion,
            selectedOptionID: id,
            hintUsed: playtestHintUsed
        )
        playtestHandle(evaluation, selectionLabel: id)
    }

    func playtestSelectFindSame(id: String) {
        guard isParentPlaytest, playtestKind == .findTheSame, !playtestChoicesLocked else { return }
        let evaluation = activityEvaluator.evaluate(
            question: playtestFindSameQuestion,
            selectedOptionID: id,
            hintUsed: playtestHintUsed
        )
        playtestHandle(evaluation, selectionLabel: id)
    }

    func playtestSelectCount(_ count: Int) {
        guard isParentPlaytest, playtestKind == .countVehicles, !playtestChoicesLocked else { return }
        let evaluation = activityEvaluator.evaluate(
            question: playtestCountQuestion,
            selectedCount: count,
            hintUsed: playtestHintUsed
        )
        playtestHandle(evaluation, selectionLabel: "count-\(count)")
    }

    func playtestSelectSequence(id assetID: String) {
        guard isParentPlaytest, playtestKind == .sequenceShortToLong else { return }
        guard playtestThinkEndsAt == nil, !playtestCompleted else { return }
        guard !playtestSequenceTaps.contains(assetID) else { return }
        let expected = activityEvaluator.nextExpectedAssetID(
            question: sequenceQuestion,
            tappedSoFar: playtestSequenceTaps
        )
        if expected != assetID {
            pendingSequenceContext = (playtestSequenceTaps.count + 1, expected, playtestSequenceTaps)
            playtestSequenceTaps = []
            playtestHandle(.incorrect, selectionLabel: assetID)
            pendingSequenceContext = nil
            return
        }
        let tappedBefore = playtestSequenceTaps
        playtestSequenceTaps.append(assetID)
        if playtestSequenceTaps.count < sequenceQuestion.orderedAssetIDs.count {
            perf.playtestAnswer(choice: assetID, correct: true, pendingBefore: playtestPendingMinutes,
                                pendingAfter: playtestPendingMinutes, hintOn: playtestHintUsed,
                                sequence: (tappedBefore.count + 1, expected, tappedBefore))
        } else {
            pendingSequenceContext = (tappedBefore.count + 1, expected, tappedBefore)
        }
        if playtestSequenceTaps.count == sequenceQuestion.orderedAssetIDs.count {
            let evaluation = activityEvaluator.evaluate(
                question: sequenceQuestion,
                orderedSelectionIDs: playtestSequenceTaps,
                hintUsed: playtestHintUsed
            )
            playtestHandle(evaluation, selectionLabel: "seq-complete")
            pendingSequenceContext = nil
        } else {
            VisaGamesLog.append("playtest sequence — 試玩車隊 local count=\(playtestSequenceTaps.count)")
        }
    }

    func playtestSelectHalfMatch(id: String) {
        guard isParentPlaytest, playtestKind == .halfMatch, !playtestChoicesLocked else { return }
        let evaluation = activityEvaluator.evaluate(
            question: halfMatchQuestion,
            selectedOptionID: id,
            hintUsed: playtestHintUsed
        )
        playtestHandle(evaluation, selectionLabel: id)
    }

    func playtestSelectShapeCousin(id: String) {
        guard isParentPlaytest, playtestKind == .shapeCousin, !playtestChoicesLocked else { return }
        let evaluation = activityEvaluator.evaluate(
            question: shapeCousinQuestion,
            selectedOptionID: id,
            hintUsed: playtestHintUsed
        )
        playtestHandle(evaluation, selectionLabel: id)
    }

    func playtestSelectCapacity(id: String) {
        guard isParentPlaytest, playtestKind == .capacityCompare, !playtestChoicesLocked else { return }
        let evaluation = activityEvaluator.evaluate(
            question: capacityCompareQuestion,
            selectedOptionID: id,
            hintUsed: playtestHintUsed
        )
        playtestHandle(evaluation, selectionLabel: id)
    }

    func playtestSelectMoreFewer(_ side: ParkingLotSide) {
        guard isParentPlaytest, playtestKind == .moreFewer, !playtestChoicesLocked else { return }
        let evaluation = activityEvaluator.evaluate(
            question: moreFewerQuestion,
            selectedSide: side,
            hintUsed: playtestHintUsed
        )
        playtestHandle(evaluation, selectionLabel: "lot-\(side.rawValue)")
    }

    func playtestSelectShadow(id: String) {
        guard isParentPlaytest, playtestKind == .shadowMatch, !playtestChoicesLocked else { return }
        let evaluation = activityEvaluator.evaluate(
            question: shadowMatchQuestion,
            selectedOptionID: id,
            hintUsed: playtestHintUsed
        )
        playtestHandle(evaluation, selectionLabel: id)
    }

    func playtestSelectEmptyBay(id: String) {
        guard isParentPlaytest, playtestKind == .emptyBay, !playtestChoicesLocked else { return }
        let evaluation = activityEvaluator.evaluate(
            question: emptyBayQuestion,
            selectedBayID: id,
            hintUsed: playtestHintUsed
        )
        playtestHandle(evaluation, selectionLabel: id)
    }

    /// Local miss / hint / fuel only. Never `applyEntrySuccess`, visa extend, or depot speech.
    private func playtestHandle(_ evaluation: ActivityEvaluation, selectionLabel: String) {
        guard WrongAnswerPolicy.shouldAcceptChoiceInput(choicesLocked: playtestThinkEndsAt != nil) else {
            return
        }
        guard !playtestCompleted else { return }
        switch evaluation {
        case .incorrect:
            playtestMissCount += 1
            playtestLastIncorrectID = selectionLabel
            playtestLastCorrectID = nil
            let before = playtestPendingMinutes
            playtestPendingMinutes = WrongAnswerPolicy.halvedPendingMinutes(playtestPendingMinutes)
            playtestFuelMessage = WrongAnswerCopy.fuelHalvedTraditionalChinese
            perf.playtestAnswer(choice: selectionLabel, correct: false, pendingBefore: before,
                                pendingAfter: playtestPendingMinutes, hintOn: playtestHintUsed,
                                sequence: pendingSequenceContext, record: pendingAnswerRecord)
            VisaGamesLog.append(
                "playtest incorrect — 試玩答錯 local selection=\(selectionLabel) pending \(before)→\(playtestPendingMinutes) misses=\(playtestMissCount)"
            )
            let flashed = selectionLabel
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                if self?.playtestLastIncorrectID == flashed {
                    self?.playtestLastIncorrectID = nil
                }
            }
            beginPlaytestThinkPause(now: Date())
        case .correct(let assisted):
            let answeredChoice = selectionLabel == "seq-complete"
                ? (playtestSequenceTaps.last ?? selectionLabel) : selectionLabel
            perf.playtestAnswer(choice: answeredChoice, correct: true, pendingBefore: playtestPendingMinutes,
                                pendingAfter: playtestPendingMinutes, hintOn: playtestHintUsed,
                                sequence: pendingSequenceContext, record: pendingAnswerRecord)
            perf.playtestSolved(earnedMinutes: playtestPendingMinutes, assisted: assisted)
            playtestLastCorrectID = selectionLabel
            playtestLastIncorrectID = nil
            playtestCompleted = true
            playtestFuelMessage = nil
            clearPlaytestThinkPause()
            guideVoice.stop()
            VisaGamesLog.append("playtest correct — 試玩完成 local no visa selection=\(selectionLabel)")
        }
    }

    private func beginPlaytestThinkPause(now: Date) {
        playtestLineMatchBoard.cancelDrag()
        playtestThinkEndsAt = now.addingTimeInterval(TimeInterval(WrongAnswerPolicy.thinkPauseSeconds))
        playtestThinkRemaining = WrongAnswerPolicy.thinkPauseSeconds
    }

    private func advancePlaytestThinkPauseIfNeeded(now: Date) {
        guard let ends = playtestThinkEndsAt else { return }
        guard playtestKind != nil, session.mode == .parent else {
            clearPlaytestThinkPause()
            return
        }
        let remaining = max(0, Int(ceil(ends.timeIntervalSince(now))))
        if remaining != playtestThinkRemaining {
            playtestThinkRemaining = remaining
        }
        if remaining == 0 {
            playtestThinkEndsAt = nil
            finishPlaytestThinkPause()
        }
    }

    private func finishPlaytestThinkPause() {
        playtestThinkRemaining = 0
        playtestFuelMessage = nil
        guard playtestKind != nil, !playtestCompleted else { return }
        perf.playtestPauseEnded()
        if playtestKind?.isLineMatchFamily == true {
            playtestLineMatchBoard.noteUnlocked(now: Date().timeIntervalSinceReferenceDate)
        }
        if playtestKind?.isTapCountFamily == true {
            tapCountAfterThinkPause(playtest: true)
            return
        }
        if playtestKind?.isTapLetterFamily == true {
            tapLetterAfterPause()
            return
        }
        // Fuel may hit 0. Stay on the cover — do not speak the depot line or end the visa.
        if ActivityHintPolicy.shouldAutoHint(afterMissCount: playtestMissCount), !playtestHintUsed {
            playtestHintUsed = true
            speakPlaytestPrompt()
            perf.playtestHint(afterMisses: playtestMissCount)
            VisaGamesLog.append("playtest auto-hint — 試玩提示 local misses=\(playtestMissCount)")
        }
    }

    private func clearPlaytestThinkPause() {
        playtestThinkEndsAt = nil
        playtestThinkRemaining = 0
    }

    /// Drops local playtest state. Does not write the ledger or change `session.mode`.
    private func discardPlaytestCover(reason: String) {
        guard playtestKind != nil || playtestThinkEndsAt != nil else { return }
        perf.abandonPlaytest(reason: "playtest_\(reason)")
        guideVoice.stop()
        playtestKind = nil
        playtestHintUsed = false
        playtestMissCount = 0
        playtestLastIncorrectID = nil
        playtestLastCorrectID = nil
        playtestCompleted = false
        playtestPendingMinutes = 5
        playtestStartingMinutes = 5
        playtestFuelMessage = nil
        playtestSequenceTaps = []
        playtestChoiceDealSeed = ""
        playtestShapeTraceBoard = nil
        shapeTraceNotice = nil
        playtestTapCountBoard = nil
        playtestTapLetterBoard = nil
        tapLetterWriteRound = nil
        tapCountNotice = nil
        clearPlaytestThinkPause()
        VisaGamesLog.append("playtest discard — 試玩收起 reason=\(reason)")
    }

    func resetStorage() {
        guard session.mode == .parent else { return }
        // Visa / ledger only. Mission-game star assignment stays in UserDefaults.
        do {
            let fresh = Snapshot(configured: true)
            let clearedResume = session.snapshot.lastIncomplete
            try store.save(fresh)
            storageFailed = false
            message = nil
            perf.abandonRound(reason: "reset_storage")
            resetTaskRound()
            pendingVideoStopReason = .storageReset
            activePlayVideoID = nil
            pendingVideoStopReason = nil
            // 清除簽證及重設儲存 never touches stats/ (Carter 3A): that is 「清除表現紀錄」.
            perf.visaEnded(reason: "reset")
            if let clearedResume {
                perf.resumeCleared(video: clearedResume.videoID, position: clearedResume.positionSeconds,
                                   reason: "storage_reset")
            }
            perf.marker("reset_storage")
            activePlayStartSeconds = nil
            lastKnownPlaybackSeconds = nil
            session = Session(snapshot: fresh, now: Date())
            changed?()
            VisaGamesLog.append("resetStorage — 重設儲存 (cleared resume cursor, game assignment kept)")
        } catch { message = "仍未能儲存。 / Storage is still unavailable." }
    }

    /// Parent 「離開程式」. Terminate on the next main-loop turn so the SwiftUI button action
    /// returns before `AppDelegate.prepareForTerminate` drops the hosting view (quit crash IPS
    /// 2026-10-01: layout re-entered ShellView.body during teardown).
    func quitFromParent() {
        guard session.mode == .parent else { return }
        VisaGamesLog.append("quit requested — 家長離開程式 activeVideo=\(activePlayVideoID ?? "nil")")
        pendingVideoStopReason = .appTerminate
        activePlayVideoID = nil
        pendingVideoStopReason = nil
        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }

    /// Tear down play/voice before NSHostingView/WKWebView die on quit (crash on terminate).
    func prepareForTerminate() {
        discardPlaytestCover(reason: "terminate")
        changed = nil
        draftTitleTask?.cancel()
        draftTitleTask = nil
        guideVoice.stop()
        pendingVideoStopReason = .appTerminate
        activePlayVideoID = nil
        pendingVideoStopReason = nil
        perf.endPlay(reason: .appTerminate, resumeSaved: false)
        perf.abandonRound(reason: "terminate")
        perf.terminate(reason: "quit")
        playbackMessage = nil
        authentication?.invalidate()
        authentication = nil
        authenticating = false
        parentDeadline = nil
        VisaGamesLog.append("prepareForTerminate — 離開前清播放／語音")
    }
}

final class KioskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Debug soak (ADR 0011). Off unless the process was launched with VISAGAMES_SOAK=1.
/// No shipped launch path (Info.plist, scripts, Desktop alias) sets it.
enum KioskSoak {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["VISAGAMES_SOAK"] == "1"
    }

    /// Parent → child round trips before the soak stops. Default 50.
    static var cycles: Int {
        guard let raw = ProcessInfo.processInfo.environment["VISAGAMES_SOAK_CYCLES"],
              let value = Int(raw), value > 0 else { return 50 }
        return value
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private let penSpark = PenSparkModel()
    private var window: KioskWindow!
    private var timer: Timer?
    private var keyMonitor: Any?
    private var pointerMonitor: Any?
    private var didPrepareTerminate = false
    private var screenRefitPending = false
    private var soakTimer: Timer?
    private var soakCycle = 0

    /// v0.21.5 (ADR 0011): set once at launch, never toggled on parent enter / exit.
    private static let kioskPresentationOptions: NSApplication.PresentationOptions = [
        .hideDock, .hideMenuBar, .disableAppleMenu, .disableProcessSwitching,
        .disableForceQuit, .disableSessionTermination, .disableHideApplication
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        VisaGamesLog.append("fonts — 字型 canvas=\(CanvasFont.isAvailable)")
        window = KioskWindow(contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Visa Games / 簽證遊戲"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenDisallowsTiling]
        window.acceptsMouseMovedEvents = true
        // Constant kiosk presentation (ADR 0011): borderless, full screen, above the menu bar,
        // for setup, child and parent alike. Parent settings render inside this same window.
        // macOS 27: toggling these on parent exit, inside the model mutation, crashed in the
        // Swift runtime executor check (ShellView.body / MenuBarClientCore).
        window.level = .mainMenu + 1
        window.contentView = NSHostingView(rootView: ShellView(model: model, penSpark: penSpark))
        NSApp.presentationOptions = Self.kioskPresentationOptions
        fitWindowToScreen()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.model.session.blocksKey(isEscape: event.keyCode == 53,
                                            hasCommand: event.modifierFlags.contains(.command)) { return nil }
            // v0.27.0: the kiosk window has no Edit menu (ADR 0011), so ⌘V / ⌘C / ⌘X / ⌘A / ⌘Z
            // go to the first responder here. Parent mode only; child keys are blocked above.
            if let action = Self.editingAction(for: event, allowsExit: self.model.session.allowsExit),
               NSApp.sendAction(action, to: nil, from: nil) { return nil }
            return event
        }
        // Observe-only: feeds the pen glow and always passes the event on unchanged.
        pointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .tabletProximity]
        ) { [weak self] event in
            self?.penSpark.handle(event)
            return event
        }
        // v0.22.2: restore the Task hop. The 0.22.1 selector Timer coincided with a depot
        // hang (idle main thread); keep ticks on MainActor the same way as before ADR 0010.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.model.tick()
                self?.penSpark.tick(now: Date())
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        startSoakIfRequested()
    }

    private static func editingAction(for event: NSEvent, allowsExit: Bool) -> Selector? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shortcut = ParentEditingShortcut.shortcut(
            characters: event.charactersIgnoringModifiers,
            command: flags.contains(.command),
            otherModifiers: !flags.intersection([.control, .option, .shift]).isEmpty,
            allowsExit: allowsExit
        )
        switch shortcut {
        case .paste: return #selector(NSText.paste(_:))
        case .copy: return #selector(NSText.copy(_:))
        case .cut: return #selector(NSText.cut(_:))
        case .selectAll: return #selector(NSText.selectAll(_:))
        case .undo: return Selector(("undo:"))
        case nil: return nil
        }
    }

    @objc private func willSleep() { model.returnToChild(reason: "sleep") }
    @objc private func didWake() { model.tick() }
    /// Coalesced and deferred: never resize inside AppKit's screen-change callout.
    @objc private func screenChanged() {
        guard !screenRefitPending else { return }
        screenRefitPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.screenRefitPending = false
            self.fitWindowToScreen()
        }
    }

    /// Full-screen frame in every mode. Launch and the deferred screen-change refit only.
    private func fitWindowToScreen() {
        guard !didPrepareTerminate, let window = self.window,
              let screen = window.screen ?? NSScreen.main else { return }
        guard window.frame != screen.frame else { return }
        window.setFrame(screen.frame, display: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.session.allowsExit else { return .terminateCancel }
        prepareForTerminate()
        return .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        prepareForTerminate()
        NSApp.presentationOptions = []
    }

    /// Stop timers/monitors and drop hosting view before further SwiftUI layout on quit.
    /// IPS VisaGames-2026-10-01-084331 (v0.11.6/33): EXC_BAD_ACCESS in ShellView.body MainActor check
    /// during NSHostingView.layout while quitting from parent with live ScopedPlayer.
    private func prepareForTerminate() {
        guard !didPrepareTerminate else { return }
        didPrepareTerminate = true
        VisaGamesLog.append("terminate — 準備離開 teardown timer/monitors/hosting")
        timer?.invalidate()
        timer = nil
        soakTimer?.invalidate()
        soakTimer = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
            self.pointerMonitor = nil
        }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        model.prepareForTerminate()
        // Dismantle SwiftUI + WKWebView before AppKit continues terminate layout.
        window?.contentView = nil
        window?.delegate = nil
    }

    // MARK: Debug soak (ADR 0011)

    /// Alternates parent ↔ child every 1.5 s on an AppKit timer to reproduce the macOS 27
    /// executor crash. Only when launched with VISAGAMES_SOAK=1; stays running when done.
    private func startSoakIfRequested() {
        guard KioskSoak.isEnabled else { return }
        VisaGamesLog.append("soak start cycles=\(KioskSoak.cycles)")
        soakTimer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(soakStep),
                                         userInfo: nil, repeats: true)
    }

    @objc private func soakStep() {
        guard KioskSoak.isEnabled, !didPrepareTerminate else { return }
        if model.session.mode == .parent {
            model.returnToChild(reason: "soak")
            if soakCycle >= KioskSoak.cycles {
                soakTimer?.invalidate()
                soakTimer = nil
                VisaGamesLog.append("soak done")
            }
        } else {
            soakCycle += 1
            VisaGamesLog.append("soak cycle \(soakCycle)")
            model.soakEnterParent()
        }
    }
}

struct ShellView: View {
    @ObservedObject var model: AppModel
    /// Not observed here, so only `PenSparkOverlay` re-renders while the pen moves.
    let penSpark: PenSparkModel

    /// Child content needs room for large task targets and the scoped player.
    private var usesCompactShell: Bool {
        model.session.mode == .lock || model.session.mode == .play
    }

    private var isChildMode: Bool {
        model.session.mode == .lock || model.session.mode == .play
    }

    private var playRoute: PlayStageRoute {
        PlayStageRoute.route(
            awaitingDeparture: model.awaitingDeparture,
            allowlistCount: model.allowlist.videos.count,
            activeVideoID: model.activePlayVideoID,
            hasResumeCandidate: model.resumeCandidate != nil
        )
    }

    /// True when `childOrLegacy` shows `WatchPlaybackView`.
    private var isWatching: Bool {
        !model.showTimesUp && model.session.mode == .play && playRoute == .watch
    }

    /// v0.22.2: build the ZStack in place (no precomputed `content`). Skip ParentCornerLayer
    /// on the depot — DepotHomeView already embeds ParentCornerEntry; a second full-screen
    /// CanvasStage/GeometryReader overlay can steal ticket taps (hang sample: idle main thread).
    /// Actions stay explicit closures (ADR 0010).
    var body: some View {
        let childMode = isChildMode
        let watching = isWatching
        // Depot has its own parent corner; Watch uses the garage glyph (ADR 0007 §5).
        let onDepot = model.session.mode == .lock && !model.taskRoundOpen
        let showsParentCorner = childMode && !watching && !onDepot
        return ZStack {
            childOrLegacy
            if showsParentCorner {
                ParentCornerLayer(onUnlock: { model.unlock() })
                    .ignoresSafeArea()
            }
            if childMode {
                PenSparkOverlay(model: penSpark)
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            model.logShellBranch(context: "shellAppear")
        }
    }

    @ViewBuilder
    private var childOrLegacy: some View {
        if model.session.mode == .parent {
            // v0.12.0: parent controls win over a pending Time's up board (shown again on Return).
            ParentSettingsView(model: model)
        } else if model.showProviderBlocked {
            ProviderBlockedView(onContinue: { model.dismissProviderBlocked() })
                .ignoresSafeArea()
        } else if model.showTimesUp {
            TimesUpView(
                ticket: model.timesUpTicket ?? model.resolvedPlayTicket,
                dockLeadingX: CGFloat(BayDock.chosen(seed: model.timesUpDockSeed).leadingX),
                onNewMission: { model.dismissTimesUp() },
                onSpeak: { model.guideSpeakTimesUp() }
            )
            .ignoresSafeArea()
        } else if model.session.mode == .lock && !model.taskRoundOpen {
            DepotHomeView(
                onSelect: { model.selectDifficulty(stars: $0.rawValue) },
                onSpeakPrompt: { model.speakDepotPrompt() },
                onParentUnlock: { model.unlock() }
            )
            .ignoresSafeArea()
            parentNotice
        } else if model.session.mode == .lock && model.taskRoundOpen {
            CanvasActivityHost(model: model)
                .ignoresSafeArea()
        } else if model.session.mode == .play {
            // Active visa never uses ADR 0006 legacyShell (cold start / grant without stars).
            playCanvasBoard(ticket: model.resolvedPlayTicket)
        } else {
            legacyShell
        }
    }

    @ViewBuilder
    private func playCanvasBoard(ticket: MissionTicket) -> some View {
        switch playRoute {
        case .stamp:
            StampSuccessView(
                ticket: ticket,
                earnedMinutes: model.earnedAwardMinutes > 0
                    ? model.earnedAwardMinutes
                    : (model.targetVisaMinutes ?? ticket.difficulty.minutes),
                dockLeadingX: CGFloat(BayDock.chosen(seed: model.departureDockSeed).leadingX),
                onGo: { model.confirmDeparture() },
                onSpeak: { model.guideSpeakStamped() },
                englishOnly: model.activeActivityKind?.isTapLetterFamily == true
            )
            .ignoresSafeArea()
        case .emptyAllowlist:
            EmptyAllowlistView(
                onReturn: { model.returnFromEmptyAllowlist() },
                onSpeak: { model.guideSpeakEmptyAllowlist() }
            )
            .ignoresSafeArea()
        case .resumeChoice:
            if let incomplete = model.resumeCandidate {
                ResumeChoiceView(
                    ticket: ticket,
                    incomplete: incomplete,
                    onContinue: { model.continueIncompleteVideo() },
                    onPickOther: { model.pickOtherFromResumeChoice() },
                    onSpeak: { model.guideSpeakResumeChoice() },
                    onSpeakOrPick: { model.guideSpeakResumeChoiceOrPick() },
                    onAppearLog: { model.resumeChoiceOpened() }
                )
                .ignoresSafeArea()
            } else {
                // Candidate vanished (allowlist remove) — fall through to picker.
                VideoPickerView(
                    ticket: ticket,
                    videos: model.pickerVideosInVisitOrder,
                    resumeCandidate: nil,
                    message: model.playbackMessage,
                    onPick: { model.pickVideo(id: $0) },
                    onContinue: nil,
                    onSpeak: { model.guideSpeakPickVideo() },
                    onAppearLog: { model.videoPickerOpened() },
                    onPageShown: { model.videoPickerPageShown(page: $0, via: $1) }
                )
                .ignoresSafeArea()
            }
        case .videoPicker:
            // Continue banner is fallback only: primary incomplete path is Resume Choice.
            // After Right 「揀片睇」the cursor is already cleared, so banner stays hidden.
            VideoPickerView(
                ticket: ticket,
                videos: model.pickerVideosInVisitOrder,
                resumeCandidate: model.resumeCandidate,
                message: model.playbackMessage,
                onPick: { model.pickVideo(id: $0) },
                onContinue: model.resumeCandidate == nil ? nil : { model.continueIncompleteVideo() },
                onSpeak: { model.guideSpeakPickVideo() },
                onAppearLog: { model.videoPickerOpened() },
                onPageShown: { model.videoPickerPageShown(page: $0, via: $1) }
            )
            .ignoresSafeArea()
        case .watch:
            WatchPlaybackView(
                ticket: ticket,
                videoID: model.activePlayVideoID,
                startSeconds: model.activePlayStartSeconds,
                progress: model.roadTimerProgress,
                onNavigationRejected: { model.stopScopedPlayback(reason: .navigationRejected) },
                onPlaybackEnded: { model.handleScopedPlaybackEnded(videoID: $0) },
                onDurationKnown: { model.recordPlayerDuration(videoID: $0, seconds: $1) },
                onCurrentTime: { model.notePlaybackCurrentTime(videoID: $0, seconds: $1) },
                onProviderBlocked: { model.handleProviderBlocked(videoID: $0, via: $1) },
                onParentUnlock: { model.unlock() }
            )
            .ignoresSafeArea()
        }
    }

    /// Parent-facing notice on the depot (storage or authentication messages).
    @ViewBuilder
    private var parentNotice: some View {
        if let message = model.message {
            VStack(spacing: 10) {
                Text(message)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                if model.needsParentAttention {
                    Button("家長 / Parent", action: { model.unlock() })
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(model.authenticating)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.9)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 40)
        }
    }

    /// Setup + parent only. Child lock/play must never reach here (ADR 0007 canvas).
    @ViewBuilder
    private var legacyShell: some View {
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
                // Child screens use the 3-second parent corner; setup and storage failures keep a visible button.
                if model.session.mode == .setup || (model.session.mode != .parent && model.needsParentAttention) {
                    Button("家長 / Parent", action: { model.unlock() })
                        .disabled(model.authenticating)
                        .tint(accent)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(usesCompactShell ? 24 : 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(Color(rgb: theme.foreground))
            // Legacy celebration only — canvas stamp (board 3) replaces this on the play path.
            if let id = model.successFeedbackID,
               model.session.mode == .lock,
               !model.awaitingDeparture {
                SuccessParkAnimation(color: accent, yellow: yellow)
                    .id(id)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func modeContent(theme: ThemePack, accent: Color, yellow: Color, sand: Color) -> some View {
        switch model.session.mode {
        case .setup:
            Text("請家長設定 / Parent setup required")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
        case .lock:
            // Without an open round the canvas depot (DepotHomeView) is shown instead of this shell.
            if model.taskRoundOpen {
                entryGateContent(theme: theme, accent: accent, yellow: yellow, sand: sand)
            }
        case .play:
            VStack(spacing: 12) {
                Text("簽證時間 / Visa time: \(model.session.remaining(at: model.now)) 秒 / seconds")
                    .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(yellow)
                if let videoID = model.activePlayVideoID {
                    ScopedPlayerView(
                        videoID: videoID,
                        onNavigationRejected: { model.stopScopedPlayback(reason: .navigationRejected) },
                        onPlaybackEnded: { model.handleScopedPlaybackEnded(videoID: $0) }
                    )
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
            // v0.12.0: `ParentSettingsView` (routed directly from `childOrLegacy`).
            EmptyView()
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
                    dealSeed: model.choiceDealSeed,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    onSelect: { model.selectFindSameOption(id: $0) },
                    onHint: { model.useEntryHint() },
                    onSpeakPrompt: { model.speakEntryPrompt() }
                )
            case .countVehicles:
                CountActivityView(
                    question: model.currentCountQuestion,
                    dealSeed: model.choiceDealSeed,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    onSelectCount: { model.selectCountChoice($0) },
                    onHint: { model.useEntryHint() },
                    onSpeakPrompt: { model.speakEntryPrompt() }
                )
            case .sequenceShortToLong:
                SequenceActivityView(
                    question: model.currentSequenceQuestion,
                    dealSeed: model.choiceDealSeed,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    tappedAssetIDs: model.sequenceTappedAssetIDs,
                    onTapAsset: { model.selectSequenceAsset(id: $0) },
                    onHint: { model.useEntryHint() },
                    onSpeakPrompt: { model.speakEntryPrompt() }
                )
            case .halfMatch:
                HalfMatchActivityView(
                    question: model.currentHalfMatchQuestion,
                    dealSeed: model.choiceDealSeed,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    onSelect: { model.selectHalfMatchOption(id: $0) },
                    onHint: { model.useEntryHint() },
                    onSpeakPrompt: { model.speakEntryPrompt() }
                )
            case .shapeCousin:
                ShapeCousinActivityView(
                    question: model.currentShapeCousinQuestion,
                    dealSeed: model.choiceDealSeed,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    onSelect: { model.selectShapeCousinOption(id: $0) },
                    onHint: { model.useEntryHint() },
                    onSpeakPrompt: { model.speakEntryPrompt() }
                )
            case .capacityCompare:
                CapacityCompareActivityView(
                    question: model.currentCapacityCompareQuestion,
                    dealSeed: model.choiceDealSeed,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    onSelect: { model.selectCapacityOption(id: $0) },
                    onHint: { model.useEntryHint() },
                    onSpeakPrompt: { model.speakEntryPrompt() }
                )
            case .moreFewer:
                MoreFewerActivityView(
                    question: model.currentMoreFewerQuestion,
                    dealSeed: model.choiceDealSeed,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    onSelectSide: { model.selectMoreFewerSide($0) },
                    onHint: { model.useEntryHint() },
                    onSpeakPrompt: { model.speakEntryPrompt() }
                )
            case .shadowMatch:
                ShadowMatchActivityView(
                    question: model.currentShadowMatchQuestion,
                    dealSeed: model.choiceDealSeed,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    onSelect: { model.selectShadowMatchOption(id: $0) },
                    onHint: { model.useEntryHint() },
                    onSpeakPrompt: { model.speakEntryPrompt() }
                )
            case .emptyBay:
                EmptyBayActivityView(
                    question: model.currentEmptyBayQuestion,
                    dealSeed: model.choiceDealSeed,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    onSelectBay: { model.selectEmptyBay(id: $0) },
                    onHint: { model.useEntryHint() },
                    onSpeakPrompt: { model.speakEntryPrompt() }
                )
            case .twoPictureChoose, .lineMatch, .lineMatchGuidedStraight, .lineMatchGuidedBridge, .traceLines, .traceShapesArrows, .traceShapesFree,
                 .traceShapesDotted, .tapCountAll, .tapCountTrace, .tapCountPick, .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish, .tapLetterAll, .tapLetterWrite, .none:
                // Legacy shell is setup / parent only; 連一連 is canvas-only (CanvasActivityHost).
                EntryActivityView(
                    question: model.currentTwoPictureQuestion,
                    dealSeed: model.choiceDealSeed,
                    accent: accent,
                    yellow: yellow,
                    foreground: Color(rgb: theme.foreground),
                    sand: sand,
                    retryMessage: model.entryRetryMessage,
                    hintUsed: model.entryHintUsed,
                    onSelect: { model.selectEntryOption(id: $0) },
                    onHint: { model.useEntryHint() },
                    onSpeakPrompt: { model.speakEntryPrompt() }
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 480, alignment: .top)
        .layoutPriority(1)
    }
}

// MARK: - Letters ABC / Find & flip

extension AppModel {
    private var tapLetterUsesPlaytest: Bool { isParentPlaytest && playtestKind?.isTapLetterFamily == true }
    private var currentTapLetterKind: ActivityKind? { tapLetterUsesPlaytest ? playtestKind : activeActivityKind }

    var currentTapLetterBoard: TapLetterBoard? {
        tapLetterUsesPlaytest ? playtestTapLetterBoard : tapLetterBoard
    }

    private func makeTapLetterBoard(seed: String) -> TapLetterBoard? {
        guard let bank = try? LetterWordBank.loadBundled() else { return nil }
        let n = tapLetterRoundIndex + 1
        guard let deal = TapLetterGenerator.make(seed: seed, n: n, settings: tapLetterSettings,
                                                 progress: tapLetterProgress, decks: tapLetterDecks,
                                                 bank: bank, now: Date()) else { return nil }
        return TapLetterBoard(deal: deal)
    }

    private func tapLetterFacts(_ board: TapLetterBoard?) -> PerfDealFacts {
        guard let board else { return PerfChoiceCatalog.facts(kind: currentTapLetterKind ?? .tapLetterAll, seed: "reference") }
        let deal = board.deal
        let rows = deal.board.rows.map { $0.joined() }
        let item = "tapLetter.\(currentTapLetterKind == .tapLetterWrite ? "write" : "all").\(deal.target).\(deal.board.letters.joined()).\(rows.joined(separator: "-"))"
        var extras: [String: PerfValue] = [
            "target": .string(deal.target), "board_set": .string(deal.board.letters.joined()),
            "rows": .strings(rows), "targets": .int(2), "path": .string(tapLetterSettings.path.rawValue),
            "this_week": .strings(tapLetterSettings.validWeek), "lane": .string(deal.lane.rawValue),
            "guard": .string(tapLetterSettings.mirrorGuard ? "on" : "off"),
            "glyph_scale": .double(deal.glyphScale), "match_mode": .string("test")
        ]
        if currentTapLetterKind == .tapLetterWrite {
            extras["letter_glyph"] = .string("latin:\(deal.target)")
            extras["formation"] = .string("lwt")
            extras["strokes"] = .int(LatinGlyphs.strokes(deal.target.first ?? "a").count)
            extras["trace_scaffold"] = .string("dots")
            extras["tolerance"] = .string("standard")
            extras["guidance"] = .string("standard")
        }
        return PerfDealFacts(item: item, gen: "letters_v1", level: currentTapLetterKind == .tapLetterWrite ? .l2 : .l1, chance: 1.0 / 45,
                             slots: (0..<10).map { "card-\($0)" }, correctChoice: nil,
                             tagsByChoice: [:], assetByChoice: [:], extraDealtFields: extras
        )
    }

    private func tapLetterSpeak(_ key: String, _ line: String, queued: Bool = true) {
        let prompt = SpokenPrompt.englishOnly(key: "en.tapLetter.\(key)", line)
        if queued { guideVoice.speakQueued(prompt) } else { guideVoice.speak(prompt) }
    }

    private func tapLetterShowBubble(_ line: String, seconds: Double = 1.2) {
        tapLetterBubbleGeneration += 1
        let generation = tapLetterBubbleGeneration
        tapLetterBubble = line
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard self?.tapLetterBubbleGeneration == generation else { return }
            self?.tapLetterBubble = nil
        }
    }

    func speakTapLetterPrompt() {
        guard let board = currentTapLetterBoard else { return }
        if currentTapLetterKind == .tapLetterWrite, tapLetterWriteRound?.phase == .writing {
            tapLetterSpeak("write.reprompt", TapLetterCopy.writeReprompt(board.deal.target))
            return
        }
        guard !board.isComplete, !tapLetterPenaltyPending,
              (tapLetterUsesPlaytest ? !playtestChoicesLocked : (taskRoundOpen && !choicesLocked)) else { return }
        tapLetterSpeak("prompt", TapLetterCopy.prompt(board.deal.target))
    }

    func tapLetterTap(card: Int) {
        let playtest = tapLetterUsesPlaytest
        guard let current = currentTapLetterBoard, !current.isComplete, !tapLetterPenaltyPending,
              (playtest ? !playtestChoicesLocked : (session.mode == .lock && taskRoundOpen &&
                activeActivityKind?.isTapLetterFamily == true && !choicesLocked && !activityJustCompleted)) else { return }
        let clock = Date().timeIntervalSinceReferenceDate
        var board = current
        let outcome = board.tap(card, at: clock)
        if playtest { playtestTapLetterBoard = board } else { tapLetterBoard = board }
        if outcome == .allFound, var write = tapLetterWriteRound {
            write.acceptFoundBoard(board)
            tapLetterWriteRound = write
        }
        guard outcome != .ignored && outcome != .doubleTapIgnored else { return }
        tapLetterLastActionAt = clock
        tapLetterIdleSpoken = false
        let letter = board.deal.board.rows[card / 5][card % 5]
        let choice = "card-\(card)"
        let attempt = (tags: tapLetterTags(target: board.deal.target, chosen: letter),
                       fields: ["card": PerfValue.int(card), "letter": .string(letter)])
        switch outcome {
        case .found, .allFound, .foundRetap:
            let slot = board.deal.board.targetCards.firstIndex(of: card) ?? 0
            let word = board.deal.words[slot]
            tapLetterShowBubble(word.word)
            tapLetterSpeak(word.voiceKey, "\(word.word)!" )
            if outcome == .found || outcome == .allFound {
                let before = playtest ? playtestPendingMinutes : pendingAwardMinutes
                if playtest {
                    perf.playtestAnswer(choice: choice, correct: true, pendingBefore: before, pendingAfter: before,
                                        hintOn: board.assisted, record: attempt)
                } else {
                    perf.roundAnswer(choice: choice, correct: true, pendingBefore: before, pendingAfter: before,
                                     hintOn: board.assisted, record: attempt)
                }
            }
            if outcome == .allFound {
                let token = playtest ? playtestChoiceDealSeed : choiceDealSeed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, self.currentTapLetterBoard?.isComplete == true else { return }
                    self.tapLetterCelebrating = true
                    let line = TapLetterCopy.allFound(board.deal.target, board.deal.words[0].word,
                                                      board.deal.words[1].word)
                    self.tapLetterShowBubble(line, seconds: 4)
                    self.tapLetterSpeak("allFound", line)
                    let delay = self.startTapLetterStrokeReveal(letter: board.deal.target)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.finishTapLetterFind(token: token, playtest: playtest)
                    }
                }
            }
        case .miss, .knownWrongRetap:
            let line = TapLetterCopy.wrong(letter)
            tapLetterShowBubble(line)
            tapLetterSpeak("thats.\(letter)", line)
            if outcome == .miss {
                tapLetterPenaltyPending = true
                tapLetterFuelBefore = playtest ? playtestPendingMinutes : pendingAwardMinutes
                let token = playtest ? playtestChoiceDealSeed : choiceDealSeed
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self, (playtest ? self.playtestChoiceDealSeed : self.choiceDealSeed) == token else { return }
                    self.pendingAnswerRecord = attempt
                    if playtest { self.playtestHandle(.incorrect, selectionLabel: choice) }
                    else { self.handleEvaluation(.incorrect, selectionLabel: choice) }
                    self.pendingAnswerRecord = nil
                    self.tapLetterPenaltyPending = false
                }
            }
        default: break
        }
    }

    private func startTapLetterStrokeReveal(letter: String) -> Double {
        let learned = letterWriteProgress.isLearned(letter)
        guard let character = letter.first,
              let dosage = StrokeOrderPlan.star1(setting: tapCountSettings.strokeOrder, learned: learned),
              let glyph = StrokeGlyph.latin(character) else { return 2.4 }
        let timeline = StrokeOrderTimeline(glyph: glyph, dosage: dosage)
        let clock = Date().timeIntervalSinceReferenceDate
        tapLetterStrokeReveal = StrokeOrderReveal(dosage: dosage, duration: timeline.duration,
                                                  startAt: clock + Self.strokeRevealLead)
        return tapLetterStrokeReveal?.finishDelay(now: clock, minimum: 2.4, flash: Self.strokeRevealFlash) ?? 2.4
    }

    private func finishTapLetterFind(token: String, playtest: Bool) {
        guard (playtest ? playtestChoiceDealSeed : choiceDealSeed) == token,
              currentTapLetterBoard?.isComplete == true else { return }
        let clock = Date().timeIntervalSinceReferenceDate
        if let reveal = tapLetterStrokeReveal {
            let wait = reveal.finishDelay(now: clock, minimum: 0, flash: Self.strokeRevealFlash)
            if wait > 0.05 {
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                    self?.finishTapLetterFind(token: token, playtest: playtest)
                }
                return
            }
        }
        tapLetterStrokeReveal = nil
        if currentTapLetterKind == .tapLetterWrite { beginTapLetterWriting(token: token) }
        else { finishTapLetterRound(token: token, playtest: playtest) }
    }

    private func beginTapLetterWriting(token: String) {
        guard currentTapLetterKind == .tapLetterWrite, let board = currentTapLetterBoard,
              board.isComplete, var write = tapLetterWriteRound,
              (tapLetterUsesPlaytest ? playtestChoiceDealSeed : choiceDealSeed) == token else { return }
        let letter = board.deal.target
        let learned = letterWriteProgress.isLearned(letter)
        let clock = Date().timeIntervalSinceReferenceDate
        let key = "latin:\(letter)"
        let plan = TapCountGuidePlan(level: tapCountSettings.guidance, learned: learned)
        let reason = StrokeOrderPlan.star2Glance(setting: tapCountSettings.strokeOrder,
            guidance: tapCountSettings.guidance, learned: learned, carDemo: plan.demo,
            progress: strokeOrderProgress, key: key, today: StrokeOrderProgress.day(clock: clock))
        tapLetterGlanceReason = reason
        let glyphGuide = letter.first.flatMap { NumeralGuide(letter: $0) }
        let glanceGlyph = letter.first.flatMap { StrokeGlyph.latin($0) }
        let glanceDuration = reason != nil && !plan.demo && tapCountSettings.strokeOrder != .off
            ? glanceGlyph.map { StrokeOrderTimeline(glyph: $0, dosage: .glance).duration } ?? 0 : 0
        let timeline = glyphGuide.map { TapCountDemoTimeline(guide: $0) }
        tapLetterGuideRun = glyphGuide.map {
            TapCountGuideRun(plan: plan, demoDuration: timeline?.duration ?? 0, now: clock,
                             demoLead: Self.tapCountGuideDemoLead, glanceDuration: glanceDuration)
        }
        tapLetterWriteGuide = tapLetterGuideRun?.isGlance == true ? "glance" : (plan.demo && glyphGuide != nil ? "car" : "none")
        tapLetterWriteDemoStartedAt = clock + Self.tapCountGuideDemoLead
        tapLetterCuspSpoken = false
        tapLetterGuideSpeechGeneration += 1
        write.beginWriting(demo: tapLetterWriteGuide != "none")
        tapLetterWriteRound = write
        tapLetterCelebrating = false
        if tapLetterWriteGuide == "car" {
            tapLetterSpeak("guide.\(letter).watchFirst", letterGuideLine(LetterGuideData.copy.watchFirst.en, letter: letter))
            scheduleLetterGuideSpeech(letter: letter, start: tapLetterWriteDemoStartedAt)
        } else {
            tapLetterSpeak("write.prompt.\(letter)", TapLetterCopy.writePrompt(letter))
        }
        if let run = tapLetterGuideRun, let start = run.demoStartedAt {
            let duration = run.demoDuration + start - clock
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self, (self.tapLetterUsesPlaytest ? self.playtestChoiceDealSeed : self.choiceDealSeed) == token,
                      var current = self.tapLetterWriteRound, current.phase == .writing, current.demoActive else { return }
                current.finishDemo()
                self.tapLetterWriteRound = current
                if self.tapLetterWriteGuide == "car" { self.tapLetterSpeak("guide.\(letter).yourTurn", self.letterGuideLine(LetterGuideData.copy.yourTurn.en, letter: letter)) }
            }
        }
    }

    private func spokenLetterName(_ letter: String) -> String {
        ["a": "ay", "b": "bee", "c": "see", "d": "dee", "e": "ee", "g": "jee",
         "k": "kay", "o": "oh", "u": "you"][letter] ?? letter
    }

    private func letterGuideLine(_ line: String, letter: String) -> String {
        line.replacingOccurrences(of: "{L}", with: spokenLetterName(letter))
    }

    private func scheduleLetterGuideSpeech(letter: String, start: Double) {
        guard let character = letter.first, let glyphGuide = NumeralGuide(letter: character) else { return }
        let timeline = TapCountDemoTimeline(guide: glyphGuide)
        tapLetterGuideSpeechGeneration += 1
        let generation = tapLetterGuideSpeechGeneration
        let token = tapLetterUsesPlaytest ? playtestChoiceDealSeed : choiceDealSeed
        let events = timeline.beatStarts.enumerated().map { ($0.element, "beat\($0.offset + 1)", glyphGuide.spec.beats[$0.offset].line.en) }
            + [(timeline.mergeStart, "merge", glyphGuide.spec.merge.en)]
        for (offset, key, line) in events {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, start + offset - Date().timeIntervalSinceReferenceDate)) { [weak self] in
                guard let self, self.tapLetterGuideSpeechGeneration == generation,
                      (self.tapLetterUsesPlaytest ? self.playtestChoiceDealSeed : self.choiceDealSeed) == token,
                      self.tapLetterWriteRound?.demoActive == true else { return }
                self.tapLetterSpeak("guide.\(letter).\(key)", line)
            }
        }
    }

    /// The first touch during a demo or glance only dismisses it.
    func tapLetterWritePenDown(_ point: LineMatchPoint) -> Bool {
        guard currentTapLetterKind == .tapLetterWrite, var round = tapLetterWriteRound,
              round.phase == .writing else { return false }
        if round.endDemoNoPaint() {
            tapLetterWriteRound = round
            var run = tapLetterGuideRun
            _ = run?.skipDemo(now: Date().timeIntervalSinceReferenceDate)
            tapLetterGuideRun = run
            tapLetterGuideSpeechGeneration += 1
            if tapLetterWriteGuide == "car" { tapLetterSpeak("guide.\(round.board.deal.target).yourTurn", letterGuideLine(LetterGuideData.copy.yourTurn.en, letter: round.board.deal.target)) }
            return false
        }
        var trace = round.trace
        _ = trace.penDown(at: point, now: Date().timeIntervalSinceReferenceDate)
        if trace.wrongStarts > round.trace.wrongStarts {
            noteLetterGuideHelp(key: "wrong_start.\(trace.wrongStarts)", kind: "wrong_start")
        }
        round.acceptTrace(trace)
        tapLetterWriteRound = round
        return true
    }

    func tapLetterWritePenMove(_ point: LineMatchPoint) {
        guard var round = tapLetterWriteRound, round.phase == .writing, !round.demoActive else { return }
        var trace = round.trace
        _ = trace.penMove(to: point, now: Date().timeIntervalSinceReferenceDate)
        if trace.wrongStarts > round.trace.wrongStarts || trace.reverseDirections > round.trace.reverseDirections {
            noteLetterGuideHelp(key: "direction.\(trace.wrongStarts).\(trace.reverseDirections)", kind: "direction")
        }
        round.acceptTrace(trace)
        tapLetterWriteRound = round
        tapLetterGuideTick(now: Date().timeIntervalSinceReferenceDate)
        if round.canStamp {
            let letter = round.board.deal.target
            let line = TapLetterCopy.writeDone(letter)
            tapLetterShowBubble(line, seconds: 2)
            tapLetterSpeak("write.done.\(letter)", line)
            let token = tapLetterUsesPlaytest ? playtestChoiceDealSeed : choiceDealSeed
            let playtest = tapLetterUsesPlaytest
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.finishTapLetterRound(token: token, playtest: playtest)
            }
        }
    }

    func tapLetterWritePenUp() {
        guard var round = tapLetterWriteRound, round.phase == .writing else { return }
        var trace = round.trace
        trace.penUp()
        round.acceptTrace(trace)
        tapLetterWriteRound = round
    }

    private func tapLetterAfterPause() {
        guard var board = currentTapLetterBoard else { return }
        let playtest = tapLetterUsesPlaytest
        if board.misses >= 2 && !board.assisted {
            board.showHint()
            if playtest { playtestTapLetterBoard = board; perf.playtestHint(afterMisses: board.misses) }
            else { tapLetterBoard = board; perf.roundHint(afterMisses: board.misses) }
            tapLetterSpeak("hint", TapLetterCopy.hint(board.deal.target))
        } else {
            tapLetterSpeak("findAgain", TapLetterCopy.findAgain(board.deal.target))
        }
    }

    private func tapLetterTags(target: String, chosen: String) -> [String] {
        if (target == "b" && chosen == "d") || (target == "d" && chosen == "b") { return ["mirror_lr"] }
        if target == "c" && chosen == "b" { return ["has_stick"] }
        return []
    }

    private func noteLetterGuideHelp(key: String, kind: String) {
        guard var run = tapLetterGuideRun else { return }
        let wasClean = run.clean
        guard run.noteHelp(key: key, kind: kind) else { return }
        tapLetterGuideRun = run
        if wasClean, let letter = tapLetterWriteRound?.board.deal.target {
            letterWriteProgress.record(letter, clean: false)
            LetterWriteProgressStore().save(letterWriteProgress)
            var strokes = strokeOrderProgress
            strokes.reset("latin:\(letter)")
            saveStrokeOrderProgress(strokes)
        }
        if kind == "redemo", run.redemos <= Self.tapCountGuideMaxRedemos,
           let round = tapLetterWriteRound, let letter = round.board.deal.target.first {
            run.restartDemo(now: Date().timeIntervalSinceReferenceDate, lead: Self.tapCountGuideDemoLead)
            tapLetterGuideRun = run
            tapLetterWriteGuide = "car"
            var replay = round
            replay.restartDemo()
            tapLetterWriteRound = replay
            tapLetterWriteDemoStartedAt = run.demoStartedAt ?? 0
            let generation = tapLetterGuideSpeechGeneration + 1
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.tapCountGuideDemoLead + run.demoDuration) { [weak self] in
                guard let self, self.tapLetterGuideSpeechGeneration == generation,
                      var current = self.tapLetterWriteRound, current.demoActive else { return }
                current.finishDemo()
                self.tapLetterWriteRound = current
            }
            tapLetterSpeak("guide.redemo", LetterGuideData.copy.redemo.en)
            scheduleLetterGuideSpeech(letter: String(letter), start: tapLetterWriteDemoStartedAt)
        } else if (kind == "stall" || kind == "ghost_to_end"), run.plan.cueWords,
                  let round = tapLetterWriteRound,
                  let letter = round.board.deal.target.first, let guide = NumeralGuide(letter: letter) {
            if let index = guide.beats.firstIndex(where: { $0.stroke == round.trace.strokeIndex && $0.end > round.trace.progress + 10 }) {
                let line = guide.spec.beats[index].line.en
                tapLetterSpeak("guide.\(letter).beat\(index + 1)", line, queued: false)
                tapLetterShowBubble(line, seconds: 3)
            }
        }
    }

    private func tapLetterGuideTick(now clock: Double) {
        guard let round = tapLetterWriteRound, round.phase == .writing, !round.demoActive,
              let character = round.board.deal.target.first,
              let guide = NumeralGuide(letter: character), let run = tapLetterGuideRun else { return }
        let help = TapCountGuideCoach.help(plan: run.plan, guide: guide, trace: round.trace, readyAt: run.readyAt, now: clock)
        if let key = help.key { noteLetterGuideHelp(key: key, kind: help.kind) }
        if run.plan.cueWords, let cue = TapCountGuideCoach.activeCue(guide: guide, trace: round.trace),
           !run.cuesSaid.contains(cue.index) {
            var next = tapLetterGuideRun ?? run
            _ = next.noteCue(cue.index)
            tapLetterGuideRun = next
            let line = guide.spec.cues[cue.index].line.en
            tapLetterSpeak("guide.\(character).cue\(cue.index + 1)", line, queued: false)
            tapLetterShowBubble(line, seconds: 3)
        }
    }

    private func tapLetterIdleCheck(now clock: Double) {
        tapLetterGuideTick(now: clock)
        guard let board = currentTapLetterBoard, !board.isComplete, !tapLetterIdleSpoken,
              clock - tapLetterLastActionAt >= 10,
              (tapLetterUsesPlaytest ? !playtestChoicesLocked : (activeActivityKind?.isTapLetterFamily == true &&
                taskRoundOpen && !choicesLocked)) else { return }
        tapLetterIdleSpoken = true
        tapLetterPlaqueNudge = true
        tapLetterSpeak("idle", TapLetterCopy.idle(board.deal.target))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.tapLetterPlaqueNudge = false
        }
    }

    private func finishTapLetterRound(token: String, playtest: Bool) {
        if currentTapLetterKind == .tapLetterWrite, tapLetterWriteRound?.canStamp != true { return }
        guard let board = currentTapLetterBoard, board.isComplete,
              (playtest ? playtestChoiceDealSeed : choiceDealSeed) == token else { return }
        if playtest { guard !playtestCompleted else { return } }
        else { guard taskRoundOpen, !activityJustCompleted else { return } }
        var fields = tapLetterResultFields(board)
        if currentTapLetterKind == .tapLetterWrite, let write = tapLetterWriteRound {
            let trace = write.trace
            fields["lifts"] = .int(trace.lifts)
            fields["off_path"] = .int(trace.offPathCount)
            fields["cusp_overshoot"] = .int(trace.cornerOvershoots)
            fields["reverse"] = .int(trace.reverseDirections)
            fields["guide_demo"] = .string(tapLetterWriteGuide)
            let clean = (tapLetterGuideRun?.clean ?? true) && trace.wrongStarts == 0 && trace.reverseDirections == 0 && trace.offPathCount == 0
            letterWriteProgress.record(board.deal.target, clean: clean)
            LetterWriteProgressStore().save(letterWriteProgress)
            var strokes = strokeOrderProgress
            let key = "latin:\(board.deal.target)"
            if let reason = tapLetterGlanceReason { strokes.consume(key, reason: reason) }
            strokes.noteTraced(key, today: StrokeOrderProgress.day(clock: Date().timeIntervalSinceReferenceDate))
            saveStrokeOrderProgress(strokes)
        }
        let boxes = tapLetterSaveRound(board)
        fields["box_before"] = .string(boxes.before)
        fields["box_after"] = .string(boxes.after)
        if playtest {
            perf.playtestResultExtra(fields)
            perf.playtestSolved(earnedMinutes: playtestPendingMinutes, assisted: board.assisted)
            playtestCompleted = true
            playtestLastCorrectID = "tap_letter"
            if let kind = currentTapLetterKind, parentPlaytestLog.playtestedOn(kind) == nil {
                parentPlaytestLog = parentPlaytestLog.recording(kind, on: Date())
                parentPlaytestLogStore.save(parentPlaytestLog)
            }
            return
        }
        perf.roundResultExtra(fields)
        guard pendingAwardMinutes > 0 else { returnToDepotOutOfFuel(); return }
        lastCorrectChoiceID = "tap_letter"
        activityJustCompleted = true
        applyEntrySuccess(assisted: board.assisted)
    }

    private func tapLetterResultFields(_ board: TapLetterBoard) -> [String: PerfValue] {
        [
            "first_try": .bool(board.misses == 0), "misses": .int(board.misses),
            "hint_used": .bool(board.assisted), "assisted": .bool(board.assisted),
            "duration_ms": .int(Int((Date().timeIntervalSinceReferenceDate - tapLetterRoundStart) * 1_000)),
            "flip_words": .strings(board.deal.words.map(\.word)),
            "scan_order": .string(board.tapOrder == board.tapOrder.sorted() ? "reading" : "other"),
            "deck_pos": .int(board.deal.decks.letters[board.deal.target]?.seenIDs.count ?? 0)
        ]
    }

    private func tapLetterSaveRound(_ board: TapLetterBoard) -> (before: String, after: String) {
        let before = tapLetterProgress.state(for: board.deal.target).box.rawValue
        tapLetterProgress.record(board.deal.target, clean: board.misses == 0 && !board.assisted,
                                 round: tapLetterRoundIndex + 1, at: Date(), lane: board.deal.lane)
        tapLetterRoundIndex += 1
        LetterRoundIndexStore().save(tapLetterRoundIndex)
        tapLetterDecks = board.deal.decks
        LetterProgressStore().save(tapLetterProgress)
        LetterWordDecksStore().save(tapLetterDecks)
        return (before, tapLetterProgress.state(for: board.deal.target).box.rawValue)
    }
}

// MARK: - 一架一架數 / Tap & Count (v0.28.0, ADR 0017)

extension AppModel {
    private var tapCountTolerance: LineMatchTolerance {
        tapCountSettings.effectiveTolerance(shapeTrace: shapeTraceSettings, lineMatch: lineMatchSettings.tolerance)
    }

    private func makeTapCountBoard(seed: String, kind: ActivityKind, avoidingItem: String?) -> TapCountBoard {
        let question = TapCountGenerator.make(seed: seed, kind: kind, settings: tapCountSettings,
                                              recentTargets: tapCountRecentTargets, avoidingItem: avoidingItem,
                                              avoidingScene: tapCountLastScene)
        return TapCountBoard(question: question)
    }

    /// After the deal facts are written: remember the numeral (last 3 avoided) and the scene.
    private func noteTapCountDealt(_ board: TapCountBoard?) {
        guard let board else { return }
        tapCountRecentTargets = Array((tapCountRecentTargets + [board.target]).suffix(3))
        tapCountLastScene = board.question.scene
    }

    private func resetTapCountTransient() {
        tapCountNotice = nil
        tapCountTraceHintSpoken = []
        tapCountGuideBubble = nil
        tapCountGuideSpeechGeneration += 1
        tapCountFuelBefore = 0
        tapCountRoundStart = Date().timeIntervalSinceReferenceDate
    }

    private var tapCountUsesPlaytest: Bool { isParentPlaytest && playtestKind?.isTapCountFamily == true }

    /// The tap-count board on screen (playtest copy while a parent reviews it).
    var currentTapCountBoard: TapCountBoard? {
        tapCountUsesPlaytest ? playtestTapCountBoard : tapCountBoard
    }

    /// Input is open: the round (or playtest) is on a tap-count card, not finished, not paused.
    var tapCountInputOpen: Bool {
        if tapCountUsesPlaytest {
            return !playtestCompleted && playtestTapCountBoard != nil && !playtestChoicesLocked
        }
        return session.mode == .lock && taskRoundOpen && activeActivityKind?.isTapCountFamily == true
            && !activityJustCompleted && tapCountBoard != nil && !choicesLocked
    }

    private var tapCountToken: String { tapCountUsesPlaytest ? playtestChoiceDealSeed : choiceDealSeed }

    /// Applies `body` to the board on screen and records the result fields. Nil when input is closed.
    @discardableResult
    private func changeTapCountBoard<T>(force: Bool = false, _ body: (inout TapCountBoard) -> T) -> T? {
        guard force || tapCountInputOpen else { return nil }
        if tapCountUsesPlaytest {
            guard var board = playtestTapCountBoard else { return nil }
            let result = body(&board)
            playtestTapCountBoard = board
            perf.playtestResultExtra(board.resultFields)
            return result
        }
        guard var board = tapCountBoard else { return nil }
        let result = body(&board)
        tapCountBoard = board
        perf.roundResultExtra(board.resultFields)
        return result
    }

    /// The words of the card on screen (Cantonese or English; the game logic is the same).
    private var tapCountLines: TapCountLines {
        TapCountLines(currentTapCountBoard?.question.language ?? .cantonese)
    }

    private func showTapCountNotice(_ prompt: SpokenPrompt) {
        tapCountNotice = prompt
        guideVoice.speak(prompt)
    }

    /// Stampy / the header: says the line that fits the stage (count, pick, or trace).
    private func speakTapCountPrompt() {
        guard let board = currentTapCountBoard else { return }
        let prompt: SpokenPrompt
        switch board.stage {
        case .tapping:
            prompt = board.isPick ? tapCountLines.pickPrompt(board.target) : board.question.prompt
        case .counted, .tracing:
            let clock = Date().timeIntervalSinceReferenceDate
            if board.question.tracesNumeral, board.stage == .tracing, board.guide?.isGlance != true,
               board.guideDemoPending(now: clock) {
                prompt = tapCountLines.guideWatchFirst(board.target)
            } else {
                prompt = board.question.tracesNumeral ? tapCountLines.tracePrompt(board.target)
                                                      : tapCountLines.total(board.target, scene: board.question.scene)
            }
        case .done:
            return
        }
        guideVoice.speak(prompt)
    }

    // MARK: Taps

    /// One tap on the vehicle in `bay` (the view's per-vehicle tap target). ★ / ★★: count
    /// (「一、二、三」, the last one reveals the numeral). ★★★: pick / unpick. Never a miss.
    func tapCountTap(bay tappedBay: Int) {
        let clock = Date().timeIntervalSinceReferenceDate
        guard currentTapCountBoard != nil else { return }
        let bay: Int? = tappedBay
        guard let outcome = changeTapCountBoard({ $0.tap(bay: bay, now: clock) }) else { return }
        guard let board = currentTapCountBoard else { return }
        let speakCount = tapCountSettings.countVoice
        switch outcome {
        case .counted(let k), .selected(let k):
            tapCountNotice = nil
            if speakCount { guideVoice.speakQueued(tapCountLines.number(k)) }
            VisaGamesLog.append("tapCount tap — 點 bay=\(bay ?? -1) k=\(k) pick=\(board.isPick)")
        case .unselected(let k):
            tapCountNotice = nil
            VisaGamesLog.append("tapCount unpick — 唔要 bay=\(bay ?? -1) k=\(k) (no miss)")
        case .completed(let k):
            tapCountNotice = nil
            if speakCount { guideVoice.speakQueued(tapCountLines.number(k)) }
            guideVoice.speakQueued(tapCountLines.total(k, scene: board.question.scene),
                                   english: tapCountSettings.english ? TapCountNumber.en(k) : nil)
            VisaGamesLog.append("tapCount counted — 點晒 \(k) item=\(board.question.itemID) taps=\(board.taps)")
            scheduleTapCountAfterCount(delay: startTapCountStrokeReveal(board: board, now: clock))
        case .recount(let again):
            VisaGamesLog.append("tapCount recount — 已點 bay=\(again) (badge flashes, not counted again)")
        case .doubleTapIgnored, .empty, .locked:
            break
        }
    }

    /// After the reveal: ★ finishes; ★★ / ★★★ park the set and open the numeral trace.
    private func scheduleTapCountAfterCount(delay: Double) {
        let token = tapCountToken
        let playtest = tapCountUsesPlaytest
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.tapCountToken == token, self.tapCountUsesPlaytest == playtest,
                  let board = self.currentTapCountBoard, board.stage == .counted else { return }
            if board.question.tracesNumeral {
                let tolerance = self.tapCountTolerance
                let colour = TapCountDrawing.traceColorIndex(board.question.scene)
                let plan = self.tapCountGuidePlan(for: board)
                let clock = Date().timeIntervalSinceReferenceDate
                let glance = self.strokeGlance(for: board, plan: plan, now: clock)
                self.changeTapCountBoard(force: true) {
                    $0.startTracing(tolerance: tolerance, colorIndex: colour, guidance: plan, now: clock,
                                    demoLead: Self.tapCountGuideDemoLead, glanceDuration: glance?.duration ?? 0)
                }
                self.tapCountTraceHintSpoken = []
                self.tapCountGuideBubble = nil
                self.noteStrokeGlance(board: board, reason: glance?.reason, now: clock)
                if let started = self.currentTapCountBoard, started.guide?.isGlance == true {
                    // The glance is silent (D8): only the usual trace prompt.
                    self.guideVoice.speakQueued(self.tapCountLines.tracePrompt(board.target))
                } else if let started = self.currentTapCountBoard, started.guideDemoPending(now: clock) {
                    self.guideVoice.speakQueued(self.tapCountLines.guideWatchFirst(board.target))
                    self.scheduleTapCountGuideDemoSpeech(target: board.target, at: clock + Self.tapCountGuideDemoLead)
                } else {
                    self.guideVoice.speakQueued(self.tapCountLines.tracePrompt(board.target))
                }
                VisaGamesLog.append(
                    "tapCount trace start — 畫 \(board.target) tolerance=\(tolerance.rawValue) guide=\(plan.level.rawValue) learned=\(plan.learned) demo=\(plan.demo)"
                )
            } else {
                let clock = Date().timeIntervalSinceReferenceDate
                // 筆順動畫: a replay (tap on the plate) moves the end; wait for the pen, then the flash.
                if let reveal = board.strokeReveal {
                    let wait = reveal.endsAt(now: clock) + Self.strokeRevealFlash - clock
                    if wait > 0.05 {
                        self.scheduleTapCountAfterCount(delay: wait)
                        return
                    }
                }
                self.changeTapCountBoard(force: true) { $0.finishWithoutTrace(now: clock) }
                self.finishTapCountRound(token: token, playtest: playtest)
            }
        }
    }

    // MARK: ★★★ OK and 擦晒

    /// OK: judged once. Stampy recounts the picks first (「一、二、三、四。四架。」). Right = the trace;
    /// wrong (more or fewer) = one miss with the existing policy (half the fuel + Think Pause).
    func tapCountSubmit() {
        let clock = Date().timeIntervalSinceReferenceDate
        guard let outcome = changeTapCountBoard({ $0.submit(now: clock) }) else { return }
        guard let board = currentTapCountBoard else { return }
        switch outcome {
        case .needsSelection:
            showTapCountNotice(tapCountLines.noneYet)
            VisaGamesLog.append("tapCount OK empty — 未揀車 (no miss)")
        case .judged(let correct, let k):
            tapCountNotice = nil
            pendingAnswerRecord = (board.submitTags(now: clock), board.resultFields)
            guideVoice.speakQueued(tapCountLines.recount(k), interrupt: true)
            VisaGamesLog.append(
                "tapCount OK — 撳 OK picked=\(k) target=\(board.target) correct=\(correct) submits=\(board.submits) item=\(board.question.itemID)"
            )
            if correct {
                recordTapCountCorrect()
                pendingAnswerRecord = nil
                scheduleTapCountAfterCount(delay: 0.9 * Double(k) + 1.2)
            } else {
                let playtest = tapCountUsesPlaytest
                tapCountFuelBefore = playtest ? playtestPendingMinutes : pendingAwardMinutes
                if playtest {
                    playtestHandle(.incorrect, selectionLabel: TapCountSubmitChoice.choice)
                } else {
                    handleEvaluation(.incorrect, selectionLabel: TapCountSubmitChoice.choice)
                }
                pendingAnswerRecord = nil
                guideVoice.speakQueued(tapCountLines.need(board.target))
            }
        case .locked:
            break
        }
    }

    /// A right OK is recorded now (mastery evidence); the visa waits for the trace.
    private func recordTapCountCorrect() {
        if tapCountUsesPlaytest {
            perf.playtestAnswer(choice: TapCountSubmitChoice.choice, correct: true, pendingBefore: playtestPendingMinutes,
                                pendingAfter: playtestPendingMinutes, hintOn: playtestHintUsed,
                                sequence: nil, record: pendingAnswerRecord)
        } else {
            perf.roundAnswer(choice: TapCountSubmitChoice.choice, correct: true, pendingBefore: pendingAwardMinutes,
                             pendingAfter: pendingAwardMinutes, hintOn: entryHintUsed,
                             sequence: nil, record: pendingAnswerRecord)
        }
    }

    /// 擦晒: clears every pick (never a miss). 3 s cooldown; the 4th press nudges OK; the 6th hides it.
    func tapCountErase() {
        let clock = Date().timeIntervalSinceReferenceDate
        guard let outcome = changeTapCountBoard({ $0.erase(now: clock) }) else { return }
        switch outcome {
        case .clearedNudge:
            showTapCountNotice(tapCountLines.eraserNudge)
        case .cleared, .clearedAndHidden:
            tapCountNotice = nil
        case .coolingDown, .unavailable:
            return
        }
        VisaGamesLog.append("tapCount 擦晒 — outcome=\(outcome) erases=\(currentTapCountBoard?.erases ?? 0) (no miss)")
    }

    /// After a ★★★ Think Pause: from the 2nd miss the demo count rings the first N vehicles
    /// (「一、二、三。三架。」); the success then counts as assisted.
    private func tapCountAfterThinkPause(playtest: Bool) {
        guard let board = currentTapCountBoard, board.isPick, board.stage == .tapping else { return }
        tapCountRoundStart = Date().timeIntervalSinceReferenceDate
        if board.misses >= TapCountBoard.demoAfterMisses, board.demoBays.isEmpty {
            changeTapCountBoard(force: true) { $0.startDemo() }
            guideVoice.speakQueued(tapCountLines.demo(board.target), interrupt: true)
            if playtest {
                playtestHintUsed = true
                perf.playtestHint(afterMisses: playtestMissCount)
            } else {
                entryHintUsed = true
                perf.roundHint(afterMisses: entryMissCount)
            }
            VisaGamesLog.append("tapCount demo — 示範數 \(board.target) after misses=\(board.misses) → assisted")
        } else {
            guideVoice.speak(tapCountLines.pickPrompt(board.target))
        }
    }

    // MARK: Trace

    /// The view drives the paint car on a local copy and hands the trace over at milestones and
    /// pen-up. Only a trace that grew from the current one is taken.
    func tapCountTraceCommit(_ next: ShapeTraceBoard) {
        guard tapCountInputOpen, let board = currentTapCountBoard, board.stage == .tracing,
              let current = board.trace else { return }
        guard next.isMonotonicSuccessor(of: current), next != current else { return }
        let clock = Date().timeIntervalSinceReferenceDate
        changeTapCountBoard { $0.updateTrace(next, now: clock) }
        if tapCountNotice != nil, next.strokesDone != current.strokesDone || next.progress > current.progress + 20 {
            tapCountNotice = nil
        }
        if next.isComplete, !current.isComplete {
            guideVoice.speakWordCue(tapCountLines.cuePrompt(board.target), then: nil)
            tapCountGuideBubble = nil
            noteTapCountGuideTraceDone(board: board)
            VisaGamesLog.append(
                "tapCount trace done — 畫好 \(board.target) offPath=\(next.offPathCount) lifts=\(next.lifts) (practice, no miss)"
            )
            let token = tapCountToken
            let playtest = tapCountUsesPlaytest
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                self?.finishTapCountRound(token: token, playtest: playtest)
            }
        } else if next.strokesDone > current.strokesDone {
            if let plan = board.guide?.plan, plan.hops, plan.cueWords, let hop = tapCountLines.guideHop(board.target) {
                // Guidance: the car hops to the next stroke 「返上去，戴帽！」 (mockup 03).
                guideVoice.speak(hop)
                showTapCountGuideBubble(hop, seconds: 3)
            } else {
                guideVoice.speak(tapCountLines.traceNext)
            }
            VisaGamesLog.append("tapCount stroke done — 第 \(next.strokesDone) 筆")
        } else if next.cornersReached.count > current.cornersReached.count, shapeTraceSettings.cornerStop {
            // A guidance cue line was already said just before this corner: no second voice.
            let cueSaid = board.guide.map { $0.plan.cueWords && !$0.cuesSaid.isEmpty } ?? false
            if !cueSaid { guideVoice.speak(tapCountLines.cornerPrompt) }
        }
    }

    func tapCountTraceWrongStart() {
        guard tapCountInputOpen else { return }
        noteTapCountGuideHelp(key: "wrong_start.\(currentTapCountBoard?.trace?.wrongStarts ?? 0)", kind: "wrong_start")
        showTapCountNotice(tapCountLines.wrongStartPrompt)
        VisaGamesLog.append("tapCount wrong start — 由綠色箭嘴開始 (no miss)")
    }

    func tapCountTraceReverse() {
        guard tapCountInputOpen else { return }
        noteTapCountGuideHelp(key: "reverse.\(currentTapCountBoard?.trace?.reverseDirections ?? 0)", kind: "reverse")
        showTapCountNotice(tapCountLines.reversePrompt)
        VisaGamesLog.append("tapCount reverse start — 跟住箭嘴方向 (no miss)")
    }

    func tapCountTraceHintShown(key: String) {
        guard tapCountInputOpen, tapCountTraceHintSpoken.insert(key).inserted else { return }
        noteTapCountGuideHelp(key: "off_path.\(key)", kind: "off_path")
        // With a stall help (標準 / 多啲) the guidance line speaks instead of 「架車等緊你」.
        if currentTapCountBoard?.guide?.plan.stallSeconds != nil { return }
        guideVoice.speak(tapCountLines.offPathPrompt)
        VisaGamesLog.append("tapCount hint — 架車等緊你 stroke=\(key) (no miss)")
    }

    // MARK: Guidance (v0.30.0; Opus spec approved by Carter 2026-10-18)

    /// The watch-first line plays before the demo car sets off.
    static let tapCountGuideDemoLead: Double = 1.4
    /// The 20 s re-demo plays at most this often per round.
    static let tapCountGuideMaxRedemos = 2

    /// Level from 數字設定; 識咗 from the clean-trace streak (both card languages share it).
    private func tapCountGuidePlan(for board: TapCountBoard) -> TapCountGuidePlan {
        TapCountGuidePlan(level: tapCountSettings.guidance,
                          learned: tapCountGuideProgress.isLearned(board.target, language: board.question.language))
    }

    /// Says each rhyme line as the ghost car starts its beat, then 「到你喇！」. A touch that ends the
    /// demo (or a new round) bumps the generation and the rest is dropped.
    private func scheduleTapCountGuideDemoSpeech(target n: Int, at start: Double) {
        guard let guide = NumeralGuide(n) else { return }
        tapCountGuideSpeechGeneration += 1
        let generation = tapCountGuideSpeechGeneration
        let token = tapCountToken
        let timeline = TapCountDemoTimeline(guide: guide)
        let lines = tapCountLines
        let beats = lines.guideBeats(n)
        var cues: [(Double, SpokenPrompt)] = zip(timeline.beatStarts, beats).map { ($0, $1) }
        if let merge = lines.guideMerge(n) { cues.append((timeline.mergeStart, merge)) }
        let clock = Date().timeIntervalSinceReferenceDate
        for (offset, prompt) in cues {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, start + offset - clock)) { [weak self] in
                guard let self, self.tapCountGuideSpeechGeneration == generation, self.tapCountToken == token,
                      let board = self.currentTapCountBoard, board.stage == .tracing else { return }
                self.guideVoice.speakQueued(prompt)
            }
        }
    }

    private func showTapCountGuideBubble(_ prompt: SpokenPrompt, seconds: Double) {
        tapCountGuideBubble = TapCountGuideBubble(prompt: prompt, until: Date().timeIntervalSinceReferenceDate + seconds)
    }

    /// A touch during the demo: it ends at once (input is never locked); the remaining lines are dropped.
    func tapCountGuideSkipDemo() {
        let clock = Date().timeIntervalSinceReferenceDate
        let glance = currentTapCountBoard?.guide?.isGlance == true
        guard changeTapCountBoard({ $0.skipGuideDemo(now: clock) }) == true, let board = currentTapCountBoard else { return }
        tapCountGuideSpeechGeneration += 1
        if glance {
            // 筆順動畫 glance: silent (D8); the touch just ends it, nothing is painted.
            VisaGamesLog.append("tapCount stroke glance skipped — 落筆 (no miss)")
            return
        }
        guideVoice.speak(tapCountLines.guideYourTurn(board.target))
        VisaGamesLog.append("tapCount guide demo skipped — 落筆，示範停 (no miss)")
    }

    /// The board shows a help (stall ring + ghost, ghost to the end, or the 20 s re-demo). Noted once;
    /// any help means this trace is not clean, so the numeral is back to learning (識咗 needs 2 clean).
    func tapCountGuideHelp(key: String, kind: String) {
        guard tapCountInputOpen, let board = currentTapCountBoard, let guide = board.guide else { return }
        if kind == "redemo" {
            guard guide.redemos < Self.tapCountGuideMaxRedemos else { return }
        }
        guard noteTapCountGuideHelp(key: key, kind: kind) else { return }
        let lines = tapCountLines
        switch kind {
        case "stall", "ghost_to_end":
            guard guide.plan.cueWords, let trace = board.trace, let numeral = NumeralGuide(board.target) else { break }
            // The rhyme line of the bit ahead.
            let beats = lines.guideBeats(board.target)
            if let index = numeral.beats.firstIndex(where: { $0.stroke == trace.strokeIndex && $0.end > trace.progress + 10 }),
               beats.indices.contains(index) {
                guideVoice.speak(beats[index])
                showTapCountGuideBubble(beats[index], seconds: 3)
            }
        case "redemo":
            let clock = Date().timeIntervalSinceReferenceDate
            changeTapCountBoard { $0.restartGuideDemo(now: clock, lead: Self.tapCountGuideDemoLead) }
            tapCountGuideBubble = nil
            guideVoice.speak(lines.guideRedemo(board.target))
            scheduleTapCountGuideDemoSpeech(target: board.target, at: clock + Self.tapCountGuideDemoLead)
        default:
            break
        }
        VisaGamesLog.append("tapCount guide help — \(kind) key=\(key) (no miss)")
    }

    /// Just before a crossing / turn: the cue line, once per round (標準 until 識咗, 多啲).
    func tapCountGuideCue(index: Int) {
        guard tapCountInputOpen, let board = currentTapCountBoard, let plan = board.guide?.plan else { return }
        guard changeTapCountBoard({ $0.noteGuideCue(index) }) == true, plan.cueWords else { return }
        let cues = tapCountLines.guideCues(board.target)
        guard cues.indices.contains(index) else { return }
        guideVoice.speak(cues[index])
        showTapCountGuideBubble(cues[index], seconds: 3)
        VisaGamesLog.append("tapCount guide cue — \(board.target) cue=\(index + 1)")
    }

    /// Notes a help on the board; the first help of a child round puts the numeral back to learning.
    @discardableResult
    private func noteTapCountGuideHelp(key: String, kind: String) -> Bool {
        guard let board = currentTapCountBoard, board.guide != nil else { return false }
        let wasClean = board.guide?.clean ?? true
        guard changeTapCountBoard({ $0.noteGuideHelp(key: key, kind: kind) }) == true else { return false }
        if wasClean, !tapCountUsesPlaytest {
            var progress = tapCountGuideProgress
            progress.recordStall(board.target, language: board.question.language)
            saveTapCountGuideProgress(progress)
            // Back to learning: the 3 glances come back for when it is learned again.
            var strokes = strokeOrderProgress
            strokes.reset(TapCountGuideProgress.key(board.target, language: board.question.language))
            saveStrokeOrderProgress(strokes)
        }
        return true
    }

    /// Trace finished: a clean one adds to the streak (2 in a row = 識咗). Playtests never count.
    private func noteTapCountGuideTraceDone(board: TapCountBoard) {
        guard let guide = currentTapCountBoard?.guide ?? board.guide, !tapCountUsesPlaytest else { return }
        guard guide.clean else { return }
        var progress = tapCountGuideProgress
        progress.recordClean(board.target, language: board.question.language)
        saveTapCountGuideProgress(progress)
        VisaGamesLog.append(
            "tapCount guide clean — \(board.target) streak=\(progress.streak(board.target, language: board.question.language))"
        )
    }

    /// UserDefaults only; a failed write never reaches the child (the in-memory record still applies).
    private func saveTapCountGuideProgress(_ next: TapCountGuideProgress) {
        tapCountGuideProgress = next
        tapCountGuideProgressStore.save(next)
    }

    // MARK: 筆順動畫 (v0.31.0; stroke-order design D2–D4, digits only)

    /// ★ after the pen is done: the plate glows this long before the round finishes.
    static let strokeRevealFlash: Double = 0.8
    /// ★ the pen starts this long after 「八架！」 begins (D2).
    static let strokeRevealLead: Double = 0.2

    /// ★: the pen writes the lit numeral (提 / 一閃 once learned / 教). Returns the finish delay
    /// (2.4 s as in v0.30 when the pen is off or the numeral has no data).
    private func startTapCountStrokeReveal(board: TapCountBoard, now clock: Double) -> Double {
        guard !board.question.tracesNumeral, !board.isPick else { return 2.4 }
        let learned = tapCountGuideProgress.isLearned(board.target, language: board.question.language)
        guard let dosage = StrokeOrderPlan.star1(setting: tapCountSettings.strokeOrder, learned: learned),
              let timeline = StrokeOrderTimeline.digit(board.target, dosage: dosage) else {
            VisaGamesLog.append("tapCount stroke reveal — off or no data n=\(board.target)")
            return 2.4
        }
        changeTapCountBoard(force: true) {
            $0.startStrokeReveal(dosage: dosage, duration: timeline.duration, startAt: clock + Self.strokeRevealLead)
        }
        VisaGamesLog.append("tapCount stroke reveal — 筆仔寫 \(board.target) dose=\(dosage.rawValue) s=\(timeline.duration)")
        return max(2.4, Self.strokeRevealLead + timeline.duration + Self.strokeRevealFlash)
    }

    /// ★: a tap on the numeral plate (writing → finish now; written → replay, at most 2). Never a miss.
    func tapCountStrokeRevealTap() {
        let clock = Date().timeIntervalSinceReferenceDate
        guard let result = changeTapCountBoard({ $0.tapStrokeReveal(now: clock) }), result != .ignored else { return }
        VisaGamesLog.append("tapCount stroke reveal tap — \(result == .finished ? "寫完" : "再寫") (no miss)")
    }

    /// ★★ / ★★★: a silent pen glance instead of nothing, for a learned numeral at 標準 (D3).
    private func strokeGlance(for board: TapCountBoard, plan: TapCountGuidePlan,
                              now clock: Double) -> (duration: Double, reason: StrokeOrderProgress.GlanceReason)? {
        let key = TapCountGuideProgress.key(board.target, language: board.question.language)
        guard let reason = StrokeOrderPlan.star2Glance(
                setting: tapCountSettings.strokeOrder, guidance: plan.level, learned: plan.learned, carDemo: plan.demo,
                progress: strokeOrderProgress, key: key, today: StrokeOrderProgress.day(clock: clock)),
              let timeline = StrokeOrderTimeline.digit(board.target, dosage: .glance) else { return nil }
        return (timeline.duration, reason)
    }

    /// Glance budget and the 7-day day stamp (child rounds only; playtests never change it).
    private func noteStrokeGlance(board: TapCountBoard, reason: StrokeOrderProgress.GlanceReason?, now clock: Double) {
        guard !tapCountUsesPlaytest else { return }
        let key = TapCountGuideProgress.key(board.target, language: board.question.language)
        var next = strokeOrderProgress
        if let reason, currentTapCountBoard?.guide?.isGlance == true {
            next.consume(key, reason: reason)
            VisaGamesLog.append("tapCount stroke glance — \(board.target) reason=\(reason.rawValue) left=\(next.remaining(key))")
        }
        next.noteTraced(key, today: StrokeOrderProgress.day(clock: clock))
        saveStrokeOrderProgress(next)
    }

    /// UserDefaults only; a failed write never reaches the child.
    private func saveStrokeOrderProgress(_ next: StrokeOrderProgress) {
        strokeOrderProgress = next
        strokeOrderProgressStore.save(next)
    }

    /// Done (★ after the reveal; ★★ / ★★★ after the trace). The child round goes to the usual
    /// stamp; a finished 試玩 unlocks the stars (D11). Saving the playtest log never blocks.
    private func finishTapCountRound(token: String, playtest: Bool) {
        if playtest {
            guard isParentPlaytest, let kind = playtestKind, kind.isTapCountFamily, playtestChoiceDealSeed == token,
                  !playtestCompleted, let board = playtestTapCountBoard, board.isComplete else { return }
            perf.playtestSolved(earnedMinutes: playtestPendingMinutes, assisted: board.assisted || playtestHintUsed)
            playtestLastCorrectID = "tap_count"
            playtestCompleted = true
            playtestFuelMessage = nil
            clearPlaytestThinkPause()
            if parentPlaytestLog.playtestedOn(kind) == nil {
                parentPlaytestLog = parentPlaytestLog.recording(kind, on: Date())
                parentPlaytestLogStore.save(parentPlaytestLog)
                if gameAssignmentBanner == ParentPlaytestLog.needsPlaytestBanner { gameAssignmentBanner = nil }
            }
            VisaGamesLog.append("playtest tapCount done — 試玩一架一架數完成 kind=\(kind.rawValue) stars unlocked, no visa")
            return
        }
        guard session.mode == .lock, taskRoundOpen, activeActivityKind?.isTapCountFamily == true,
              choiceDealSeed == token, !activityJustCompleted, let board = tapCountBoard, board.isComplete else { return }
        guard pendingAwardMinutes > 0 else {
            VisaGamesLog.append("tapCount done blocked — pending=0 → depot")
            returnToDepotOutOfFuel()
            return
        }
        let assisted = board.assisted || (board.isPick && entryHintUsed)
        lastCorrectChoiceID = "tap_count"
        lastIncorrectChoiceID = nil
        activityJustCompleted = true
        VisaGamesLog.append(
            "tapCount done — 完成 item=\(board.question.itemID) target=\(board.target) misses=\(board.misses) earnedMin=\(pendingAwardMinutes) assisted=\(assisted)"
        )
        applyEntrySuccess(assisted: assisted)
    }

    // MARK: Idle (model clock)

    /// ★ / ★★: after 8 s with nothing tapped the next vehicle blinks (twice at most).
    /// ★★★: after 10 s the prompt is read again. Never a miss.
    private func tapCountIdleCheck(now clock: Double) {
        guard tapCountInputOpen, let board = currentTapCountBoard, board.stage == .tapping else { return }
        let idle = board.idleFor(now: clock, since: tapCountRoundStart)
        if board.isPick {
            guard idle >= TapCountBoard.pickRepromptSeconds, board.idleReprompts < TapCountBoard.maxNudges else { return }
            changeTapCountBoard { $0.reprompt(now: clock) }
            guideVoice.speak(tapCountLines.pickPrompt(board.target))
            VisaGamesLog.append("tapCount idle reprompt — 再讀題 (no miss)")
        } else {
            guard idle >= TapCountBoard.nudgeAfterSeconds, board.idleNudges < TapCountBoard.maxNudges else { return }
            if changeTapCountBoard({ $0.nudge(now: clock) }) == true {
                guideVoice.speak(board.question.prompt)
                VisaGamesLog.append("tapCount idle nudge — 閃下一架 (no miss)")
            }
        }
    }

    // MARK: 數字設定 (parent; shared by the 3 cards)

    func setTapCountRange(_ range: TapCountRange) {
        guard session.mode == .parent, range != tapCountSettings.range else { return }
        var next = tapCountSettings
        next.range = range
        saveTapCountSettings(next, what: "range", value: range.label)
    }

    func setTapCountCountVoice(_ on: Bool) {
        guard session.mode == .parent, on != tapCountSettings.countVoice else { return }
        var next = tapCountSettings
        next.countVoice = on
        saveTapCountSettings(next, what: "count_voice", value: on ? "on" : "off")
    }

    func setTapCountEnglish(_ on: Bool) {
        guard session.mode == .parent, on != tapCountSettings.english else { return }
        var next = tapCountSettings
        next.english = on
        saveTapCountSettings(next, what: "english", value: on ? "on" : "off")
    }

    func setTapCountBadgeStyle(_ style: TapCountBadgeStyle) {
        guard session.mode == .parent, style != tapCountSettings.badgeStyle else { return }
        var next = tapCountSettings
        next.badgeStyle = style
        saveTapCountSettings(next, what: "badge_style", value: style.rawValue)
    }

    func setTapCountTraceScaffold(_ scaffold: TapCountTraceScaffold) {
        guard session.mode == .parent, scaffold != tapCountSettings.traceScaffold else { return }
        var next = tapCountSettings
        next.traceScaffold = scaffold
        saveTapCountSettings(next, what: "trace_scaffold", value: scaffold.code)
    }

    /// 描數字提示: 多啲 / 標準 / 少啲 (both card languages; the next trace uses it).
    func setTapCountGuidance(_ level: TapCountGuidanceLevel) {
        guard session.mode == .parent, level != tapCountSettings.guidance else { return }
        var next = tapCountSettings
        next.guidance = level
        saveTapCountSettings(next, what: "guidance", value: level.rawValue)
    }

    /// 筆順動畫 for digits: 教 / 提 / 熄 (★ reveal and the ★★ glance; both card languages).
    func setTapCountStrokeOrder(_ setting: StrokeOrderSetting) {
        guard session.mode == .parent, setting != tapCountSettings.strokeOrder else { return }
        var next = tapCountSettings
        next.strokeOrder = setting
        saveTapCountSettings(next, what: "stroke_order", value: setting.rawValue)
    }

    /// nil = follow 畫形狀's tolerance.
    func setTapCountTolerance(_ tolerance: LineMatchTolerance?) {
        guard session.mode == .parent, tolerance != tapCountSettings.tolerance else { return }
        var next = tapCountSettings
        next.tolerance = tolerance
        saveTapCountSettings(next, what: "tolerance", value: tolerance?.rawValue ?? "follow_shape_trace")
    }

    /// UserDefaults only; a failed write never reaches the child (the in-memory setting still applies).
    private func saveTapCountSettings(_ next: TapCountSettings, what: String, value: String) {
        tapCountSettings = next
        tapCountSettingsStore.save(next)
        perf.tapCountSettingChanged(what: what, value: value)
        VisaGamesLog.append("tapCount settings — 數字設定 \(what)=\(value)")
    }
}
