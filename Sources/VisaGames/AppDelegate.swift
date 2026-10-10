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
    @Published private(set) var gameAssignment = MissionGameAssignment.allOn
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
    private var storageFailed = false
    private var authentication: LAContext?
    private var parentDeadline: Date?
    private let parentAccessSeconds: TimeInterval = 600
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
        gameAssignment = MissionGameAssignmentStore().load()
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
        perf.contextProvider = { [unowned self] in
            PerfRecorderContext(mode: self.session.mode, isPlaytest: self.isParentPlaytest)
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

    func update(_ action: (inout Session) -> Void) {
        var next = session
        action(&next)
        if next.snapshot != session.snapshot {
            do { try store.save(next.snapshot) }
            catch {
                storageFailed = true
                message = "未能儲存，請家長處理。 / Could not save. Ask a parent."
                VisaGamesLog.append("storage save FAILED — 儲存失敗 storageFailed=true")
                perf.endPlay(reason: .storageFailure, resumeSaved: false)
                perf.abandonRound(reason: "storage_failure")
                perf.visaEnded(reason: "storage_failure")
                session = Session(snapshot: Snapshot(configured: true), now: Date())
                resetTaskRound()
                changed?()
                return
            }
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
            do {
                try store.save(stamped.snapshot)
                session = stamped
                VisaGamesLog.append(
                    "resume save — 簽證到期記進度 id=\(incompleteToSave.videoID) at=\(Int(incompleteToSave.positionSeconds))s"
                )
            } catch {
                storageFailed = true
                message = "未能儲存，請家長處理。 / Could not save. Ask a parent."
                VisaGamesLog.append("resume save FAILED — 簽證到期儲存失敗")
            }
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
    }

    func returnToChild(reason: String = "return") {
        providerBlockedParentHint = nil
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

    /// Storage needs a parent: child screens then show a visible Parent button, not only the corner.
    var needsParentAttention: Bool { storageFailed }

    /// Board 1 bubble: speak (or replay) the depot line in Cantonese.
    func speakDepotPrompt() {
        guard session.mode == .lock, !taskRoundOpen else { return }
        guideVoice.speak(.depotPickTicket)
    }

    func guideSpeakStamped() { guideVoice.speak(.stamped) }
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
    var currentSequenceQuestion: SequenceQuestion { sequenceQuestion }
    var currentHalfMatchQuestion: HalfMatchQuestion { halfMatchQuestion }
    var currentShapeCousinQuestion: ShapeCousinQuestion { shapeCousinQuestion }
    var currentCapacityCompareQuestion: CapacityCompareQuestion { capacityCompareQuestion }
    var currentMoreFewerQuestion: MoreFewerQuestion { moreFewerQuestion }
    var currentShadowMatchQuestion: ShadowMatchQuestion { shadowMatchQuestion }
    var currentEmptyBayQuestion: EmptyBayQuestion { emptyBayQuestion }

    func selectDifficulty(stars: Int) {
        guard !storageFailed, session.mode == .lock, !taskRoundOpen,
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
        // Refresh catalog payloads each round (stable templates today; seam for future variants).
        twoPictureQuestion = ActivityCatalog.twoPictureQuestion()
        findSameQuestion = ActivityCatalog.findSameQuestion()
        countQuestion = ActivityCatalog.countQuestion()
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
        perf.roundDealt(round: seed, kind: kind, stars: stars, pendingStart: difficulty.minutes, pool: pool)
        VisaGamesLog.append("selectDifficulty — 選擇難度 stars=\(stars) kind=\(kind.rawValue) seed=\(seed) pendingMin=\(pendingAwardMinutes) pool=\(pool.count)")
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
    }

    func useEntryHint() {
        guard session.mode == .lock, taskRoundOpen, let kind = activeActivityKind else { return }
        guard !choicesLocked else { return }
        entryHintUsed = true
        entryRetryMessage = ActivityCatalog.hintTraditionalChinese(for: kind)
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
        guard !choicesLocked else { perf.roundMashTap(); return }
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
        guard !choicesLocked else { perf.roundMashTap(); return }
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
        guard !choicesLocked else { perf.roundMashTap(); return }
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
        guard !storageFailed else {
            VisaGamesLog.append("selectHalfMatchOption blocked — 已封鎖 storageFailed=true id=\(id)")
            return
        }
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
        guard !storageFailed else {
            VisaGamesLog.append("selectShapeCousinOption blocked — 已封鎖 storageFailed=true id=\(id)")
            return
        }
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
        guard !storageFailed else {
            VisaGamesLog.append("selectCapacityOption blocked — 已封鎖 storageFailed=true id=\(id)")
            return
        }
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
        guard !storageFailed else {
            VisaGamesLog.append("selectMoreFewerSide blocked — 已封鎖 storageFailed=true side=\(side.rawValue)")
            return
        }
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
        guard !storageFailed else {
            VisaGamesLog.append("selectShadowMatchOption blocked — 已封鎖 storageFailed=true id=\(id)")
            return
        }
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
        guard !storageFailed else {
            VisaGamesLog.append("selectEmptyBay blocked — 已封鎖 storageFailed=true id=\(id)")
            return
        }
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
                             sequence: pendingSequenceContext)
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
                             sequence: pendingSequenceContext)
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
        guard !storageFailed, session.mode == .play else { return }
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
        guideVoice.speak(.stamped)
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
        guideVoice.speak(.outOfFuelDepot)
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
                playerDurationSeconds: next.video(id: id)?.playerDurationSeconds
            ))
            guard ok else {
                self.playbackMessage = "影片編號無效。 / Invalid video ID."
                return
            }
            let existed = self.allowlist.video(id: id) != nil
            self.allowlist = next
            self.allowlistStore.save(next)
            self.perf.allowlistChanged(op: existed ? "update" : "add", video: id)
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

    /// Public oEmbed title for an id (no API key). Nil on any failure.
    private static func fetchOEmbedTitle(videoID: String) async -> String? {
        guard let url = YouTubeOEmbed.requestURL(videoID: videoID) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { return nil }
            return YouTubeOEmbed.parse(data)?.title
        } catch {
            return nil
        }
    }

    /// Paste field changed: recompute status and fetch the title for a new valid id
    /// (debounced) so the parent sees thumbnail + title before pressing Add.
    private func refreshParentDraftPreview() {
        let previousID = parentDraftStatus.videoID
        let status = ParentAllowlistDraft.evaluate(parentVideoIDDraft, allowlist: allowlist)
        parentDraftStatus = status
        guard let id = status.videoID else {
            draftTitleTask?.cancel()
            draftTitleTask = nil
            parentDraftTitle = nil
            isFetchingDraftTitle = false
            return
        }
        guard id != previousID else { return }
        draftTitleTask?.cancel()
        draftTitleTask = nil
        if let known = allowlist.video(id: id), known.hasParentTitle {
            parentDraftTitle = known.parentLabel
            isFetchingDraftTitle = false
            return
        }
        if let cached = oEmbedTitleCache[id] {
            parentDraftTitle = cached
            isFetchingDraftTitle = false
            return
        }
        parentDraftTitle = nil
        isFetchingDraftTitle = true
        draftTitleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let title = await Self.fetchOEmbedTitle(videoID: id)
            guard let self, !Task.isCancelled, self.parentDraftStatus.videoID == id else { return }
            self.isFetchingDraftTitle = false
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
        guard !storageFailed else { return refused }
        guard session.mode == .parent || session.mode == .play else { return refused }
        let now = Date()
        let isParentPreview = session.mode == .parent
        if isParentPreview {
            if remainingViewingBudget(at: now) <= 0 {
                seedTestViewingBudget()
                guard !storageFailed else { return refused }
            }
            if session.snapshot.endsAt.map({ $0 <= now }) ?? true {
                update { $0.extendVisaKeepingParent(seconds: 600, now: now) }
                guard !storageFailed else { return refused }
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

    // MARK: - Parent game catalog + playtest (no visa)

    func toggleMissionStar(kind: ActivityKind, star: ChildDifficulty) {
        guard session.mode == .parent else { return }
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
        clearPlaytestThinkPause()
        perf.playtestStarted(round: playtestChoiceDealSeed, kind: kind, pendingStart: playtestStartingMinutes)
        VisaGamesLog.append("playtest start — 試玩 kind=\(kind.rawValue) mode=parent visa=false")
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
            question: findSameQuestion,
            selectedOptionID: id,
            hintUsed: playtestHintUsed
        )
        playtestHandle(evaluation, selectionLabel: id)
    }

    func playtestSelectCount(_ count: Int) {
        guard isParentPlaytest, playtestKind == .countVehicles, !playtestChoicesLocked else { return }
        let evaluation = activityEvaluator.evaluate(
            question: countQuestion,
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
                                sequence: pendingSequenceContext)
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
                                sequence: pendingSequenceContext)
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = AppModel()
    private let penSpark = PenSparkModel()
    private var window: KioskWindow!
    private var timer: Timer?
    private var keyMonitor: Any?
    private var pointerMonitor: Any?
    private var isChildPresentation: Bool?
    private var parentWindowFrame: NSRect?
    private var didPrepareTerminate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        VisaGamesLog.append("fonts — 字型 canvas=\(CanvasFont.isAvailable)")
        window = KioskWindow(contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720),
                             styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Visa Games / 簽證遊戲"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenDisallowsTiling]
        window.acceptsMouseMovedEvents = true
        window.contentView = NSHostingView(rootView: ShellView(model: model, penSpark: penSpark))
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
        // Observe-only: feeds the pen glow and always passes the event on unchanged.
        pointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .tabletProximity]
        ) { [weak self] event in
            self?.penSpark.handle(event)
            return event
        }
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

    @objc private func willSleep() { model.returnToChild(reason: "sleep") }
    @objc private func didWake() { model.tick() }
    @objc private func screenChanged() {
        if !model.session.allowsExit, let screen = window.screen ?? NSScreen.main {
            window.setFrame(screen.frame, display: true)
        }
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

    var body: some View {
        let childMode = isChildMode
        let watching = isWatching
        return ZStack {
            childOrLegacy
            if childMode {
                // On Watch the parent hold lives on the garage glyph (ADR 0007 §5); no second corner.
                if !watching {
                    ParentCornerLayer(onUnlock: { model.unlock() })
                        .ignoresSafeArea()
                }
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
            ProviderBlockedView(onContinue: model.dismissProviderBlocked)
                .ignoresSafeArea()
        } else if model.showTimesUp {
            TimesUpView(
                ticket: model.timesUpTicket ?? model.resolvedPlayTicket,
                dockLeadingX: CGFloat(BayDock.chosen(seed: model.timesUpDockSeed).leadingX),
                onNewMission: model.dismissTimesUp,
                onSpeak: { model.guideSpeakTimesUp() }
            )
            .ignoresSafeArea()
        } else if model.session.mode == .lock && !model.taskRoundOpen {
            DepotHomeView(
                onSelect: { model.selectDifficulty(stars: $0.rawValue) },
                onSpeakPrompt: model.speakDepotPrompt,
                onParentUnlock: model.unlock
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
                onGo: model.confirmDeparture,
                onSpeak: { model.guideSpeakStamped() }
            )
            .ignoresSafeArea()
        case .emptyAllowlist:
            EmptyAllowlistView(
                onReturn: model.returnFromEmptyAllowlist,
                onSpeak: { model.guideSpeakEmptyAllowlist() }
            )
            .ignoresSafeArea()
        case .resumeChoice:
            if let incomplete = model.resumeCandidate {
                ResumeChoiceView(
                    ticket: ticket,
                    incomplete: incomplete,
                    onContinue: model.continueIncompleteVideo,
                    onPickOther: model.pickOtherFromResumeChoice,
                    onSpeak: { model.guideSpeakResumeChoice() },
                    onSpeakOrPick: { model.guideSpeakResumeChoiceOrPick() },
                    onAppearLog: model.resumeChoiceOpened
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
                    onAppearLog: model.videoPickerOpened,
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
                onAppearLog: model.videoPickerOpened,
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
                    Button("家長 / Parent", action: model.unlock)
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
                    Button("家長 / Parent", action: model.unlock)
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
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
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
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
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
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
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
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
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
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
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
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
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
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
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
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
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
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
                )
            case .twoPictureChoose, .none:
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
                    onHint: model.useEntryHint,
                    onSpeakPrompt: model.speakEntryPrompt
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 480, alignment: .top)
        .layoutPriority(1)
    }
}
