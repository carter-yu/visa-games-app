import SwiftUI
import VisaCore

/// Routes all 10 activity kinds into the board-2 shell with text-free choice cards.
struct CanvasActivityHost: View {
    @ObservedObject var model: AppModel

    /// Parent playtest reuses this board but never the `.lock` selectors.
    private var usingPlaytest: Bool { model.isParentPlaytest }

    private var shownKind: ActivityKind? {
        usingPlaytest ? model.playtestKind : model.activeActivityKind
    }
    private var hintUsed: Bool { usingPlaytest ? model.playtestHintUsed : model.entryHintUsed }
    private var lastCorrectID: String? { usingPlaytest ? model.playtestLastCorrectID : model.lastCorrectChoiceID }
    private var lastIncorrectID: String? { usingPlaytest ? model.playtestLastIncorrectID : model.lastIncorrectChoiceID }
    private var justCompleted: Bool { usingPlaytest ? model.playtestCompleted : model.activityJustCompleted }
    private var pendingMinutes: Int { usingPlaytest ? model.playtestPendingMinutes : model.pendingAwardMinutes }
    private var startingMinutes: Int { usingPlaytest ? model.playtestStartingMinutes : model.roundStartingMinutes }
    private var thinkRemaining: Int { usingPlaytest ? model.playtestThinkRemaining : model.thinkPauseRemainingSeconds }
    private var fuelFeedback: String? { usingPlaytest ? model.playtestFuelMessage : model.fuelFeedbackMessage }
    private var choicesAreLocked: Bool { usingPlaytest ? model.playtestChoicesLocked : model.choicesLocked }
    private var sequenceTaps: [String] { usingPlaytest ? model.playtestSequenceTaps : model.sequenceTappedAssetIDs }
    /// Stored on the model for this deal. The slot order is a pure function of the seed.
    private var choiceDealSeed: String {
        usingPlaytest ? model.playtestChoiceDealSeed : model.choiceDealSeed
    }
    private var sequenceHint: String? {
        usingPlaytest ? model.playtestSequenceHintAssetID : model.sequenceHintAssetID
    }

    private func speakPrompt() {
        if usingPlaytest { model.speakPlaytestPrompt() } else { model.speakEntryPrompt() }
    }
    private func selectTwoPicture(_ id: String) {
        if usingPlaytest { model.playtestSelectEntry(id: id) } else { model.selectEntryOption(id: id) }
    }
    private func selectFindSame(_ id: String) {
        if usingPlaytest { model.playtestSelectFindSame(id: id) } else { model.selectFindSameOption(id: id) }
    }
    private func selectCount(_ count: Int) {
        if usingPlaytest { model.playtestSelectCount(count) } else { model.selectCountChoice(count) }
    }
    private func selectSequence(_ id: String) {
        if usingPlaytest { model.playtestSelectSequence(id: id) } else { model.selectSequenceAsset(id: id) }
    }
    private func selectHalf(_ id: String) {
        if usingPlaytest { model.playtestSelectHalfMatch(id: id) } else { model.selectHalfMatchOption(id: id) }
    }
    private func selectShape(_ id: String) {
        if usingPlaytest { model.playtestSelectShapeCousin(id: id) } else { model.selectShapeCousinOption(id: id) }
    }
    private func selectCapacity(_ id: String) {
        if usingPlaytest { model.playtestSelectCapacity(id: id) } else { model.selectCapacityOption(id: id) }
    }
    private func selectMoreFewer(_ side: ParkingLotSide) {
        if usingPlaytest { model.playtestSelectMoreFewer(side) } else { model.selectMoreFewerSide(side) }
    }
    private func selectShadow(_ id: String) {
        if usingPlaytest { model.playtestSelectShadow(id: id) } else { model.selectShadowMatchOption(id: id) }
    }
    private func selectBay(_ id: String) {
        if usingPlaytest { model.playtestSelectEmptyBay(id: id) } else { model.selectEmptyBay(id: id) }
    }

    var body: some View {
        Group {
            switch shownKind {
            case .twoPictureChoose:
                twoPicture
            case .findTheSame:
                findSame
            case .countVehicles:
                countVehicles
            case .sequenceShortToLong:
                sequence
            case .halfMatch:
                halfMatch
            case .shapeCousin:
                shapeCousin
            case .capacityCompare:
                capacity
            case .moreFewer:
                moreFewer
            case .shadowMatch:
                shadowMatch
            case .emptyBay:
                emptyBay
            case .none:
                EmptyView()
            }
        }
    }

    // MARK: - Kind screens

    private var twoPicture: some View {
        let q = model.currentTwoPictureQuestion
        let options = q.presentedOptions(seed: choiceDealSeed)
        return board(promptZH: q.promptTraditionalChinese, promptEN: q.promptEnglish,
                     hintID: q.correctOptionID, choiceCount: options.count) {
            StimulusPanel {
                CanvasText("邊架？", size: 36, weight: 900)
            }
        } choices: {
            choiceRow(ids: options.map(\.id), hintID: q.correctOptionID) { id in
                if let opt = q.options.first(where: { $0.id == id }) {
                    ActivityAssetView(assetID: opt.assetID, mood: .happy)
                        .accessibilityLabel("\(opt.labelTraditionalChinese), \(opt.labelEnglish)")
                }
            } onSelect: { selectTwoPicture($0) }
        }
    }

    private var findSame: some View {
        let q = model.currentFindSameQuestion
        let options = q.presentedOptions(seed: choiceDealSeed)
        return board(promptZH: q.promptTraditionalChinese, promptEN: q.promptEnglish,
                     hintID: q.correctOptionID, choiceCount: options.count) {
            StimulusPanel {
                ActivityAssetView(assetID: q.targetAssetID, mood: .calm)
            }
        } choices: {
            choiceRow(ids: options.map(\.id), hintID: q.correctOptionID) { id in
                if let opt = q.options.first(where: { $0.id == id }) {
                    ActivityAssetView(assetID: opt.assetID, mood: .happy)
                        .accessibilityLabel("\(opt.labelTraditionalChinese), \(opt.labelEnglish)")
                }
            } onSelect: { selectFindSame($0) }
        }
    }

    private var countVehicles: some View {
        let q = model.currentCountQuestion
        let counts = q.presentedChoiceCounts(seed: choiceDealSeed)
        let hintID = "count-\(q.correctCount)"
        return board(promptZH: q.promptTraditionalChinese, promptEN: q.promptEnglish,
                     hintID: hintID, choiceCount: counts.count) {
            StimulusPanel {
                HStack(spacing: 8) {
                    ForEach(Array(q.vehicleAssetIDs.enumerated()), id: \.offset) { _, assetID in
                        ActivityAssetView(assetID: assetID, mood: .calm)
                    }
                }
            }
        } choices: {
            // Discrete numeral buttons, not a 1–5 number line, so the slots shuffle.
            choiceRow(ids: counts.map { "count-\($0)" }, hintID: hintID) { id in
                let n = Int(id.replacingOccurrences(of: "count-", with: "")) ?? 0
                CanvasText("\(n)", size: 64, weight: 900)
                    .accessibilityLabel("\(n)")
            } onSelect: { id in
                if let n = Int(id.replacingOccurrences(of: "count-", with: "")) {
                    selectCount(n)
                }
            }
        }
    }

    private var sequence: some View {
        let q = model.currentSequenceQuestion
        let nextID = sequenceHint
        // Dealt once from the round seed. Wrong taps clear progress but not this order.
        // Every vehicle stays on its slot (tapped ones dim) so the next correct picture
        // is never hidden, and the row is not already short→long.
        let display = q.presentedAssetIDs(seed: choiceDealSeed)
        let cardWidth = display.count > DesignTokens.maxChoices ? 240.0 : DesignTokens.choiceCardWidth
        return board(promptZH: q.promptTraditionalChinese, promptEN: q.promptEnglish,
                     hintID: nextID ?? "", choiceCount: display.count) {
            StimulusPanel {
                if sequenceTaps.isEmpty {
                    HStack(alignment: .bottom, spacing: 16) {
                        ForEach([28, 48, 72], id: \.self) { height in
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(hex: DesignTokens.Palette.metro))
                                .frame(width: 34, height: CGFloat(height))
                        }
                    }
                    .accessibilityLabel("短到長 / Short to long")
                } else {
                    HStack(spacing: 10) {
                        ForEach(sequenceTaps, id: \.self) { assetID in
                            ActivityAssetView(assetID: assetID, mood: .happy)
                        }
                    }
                }
            }
        } choices: {
            choiceRow(ids: display, hintID: nextID ?? "", cardWidth: cardWidth) { assetID in
                ActivityAssetView(assetID: assetID, mood: .happy)
                    .opacity(sequenceTaps.contains(assetID) ? 0.35 : 1)
                    .accessibilityLabel(assetID)
            } onSelect: { selectSequence($0) }
        }
    }

    private var halfMatch: some View {
        let q = model.currentHalfMatchQuestion
        let options = q.presentedOptions(seed: choiceDealSeed)
        return board(promptZH: q.promptTraditionalChinese, promptEN: q.promptEnglish,
                     hintID: q.correctOptionID, choiceCount: options.count) {
            StimulusPanel {
                HalfVehicleClip(assetID: q.targetAssetID, side: .left, mood: .calm)
            }
        } choices: {
            choiceRow(ids: options.map(\.id), hintID: q.correctOptionID) { id in
                if let opt = q.options.first(where: { $0.id == id }) {
                    HalfVehicleClip(assetID: opt.assetID, side: .right, mood: .happy)
                        .accessibilityLabel("\(opt.labelTraditionalChinese), \(opt.labelEnglish)")
                }
            } onSelect: { selectHalf($0) }
        }
    }

    private var shapeCousin: some View {
        let q = model.currentShapeCousinQuestion
        let options = q.presentedOptions(seed: choiceDealSeed)
        return board(promptZH: q.promptTraditionalChinese, promptEN: q.promptEnglish,
                     hintID: q.correctOptionID, choiceCount: options.count) {
            StimulusPanel {
                ActivityAssetView(assetID: q.targetAssetID, mood: .calm)
            }
        } choices: {
            choiceRow(ids: options.map(\.id), hintID: q.correctOptionID) { id in
                if let opt = q.options.first(where: { $0.id == id }) {
                    ActivityAssetView(assetID: opt.assetID, mood: .happy)
                        .accessibilityLabel("\(opt.labelTraditionalChinese), \(opt.labelEnglish)")
                }
            } onSelect: { selectShape($0) }
        }
    }

    private var capacity: some View {
        let q = model.currentCapacityCompareQuestion
        let options = q.presentedOptions(seed: choiceDealSeed)
        return board(promptZH: q.promptTraditionalChinese, promptEN: q.promptEnglish,
                     hintID: q.correctOptionID, choiceCount: options.count) {
            StimulusPanel {
                HStack(spacing: 20) {
                    ForEach(options, id: \.id) { opt in
                        ActivityAssetView(assetID: opt.assetID, mood: .calm)
                    }
                }
            }
        } choices: {
            choiceRow(ids: options.map(\.id), hintID: q.correctOptionID) { id in
                if let opt = q.options.first(where: { $0.id == id }) {
                    ActivityAssetView(assetID: opt.assetID, mood: .happy)
                        .accessibilityLabel("\(opt.labelTraditionalChinese), \(opt.labelEnglish)")
                }
            } onSelect: { selectCapacity($0) }
        }
    }

    private var moreFewer: some View {
        let q = model.currentMoreFewerQuestion
        let hintID = q.correctSide == .left ? "lot-left" : "lot-right"
        let ids = q.presentedSides(seed: choiceDealSeed).map { $0 == .left ? "lot-left" : "lot-right" }
        return board(promptZH: q.promptTraditionalChinese, promptEN: q.promptEnglish,
                     hintID: hintID, choiceCount: ids.count) {
            StimulusPanel {
                CanvasText("🅿️", size: 48, weight: 800)
            }
        } choices: {
            choiceRow(ids: ids, hintID: hintID) { id in
                let assets = id == "lot-left" ? q.leftLotAssetIDs : q.rightLotAssetIDs
                HStack(spacing: 4) {
                    ForEach(Array(assets.enumerated()), id: \.offset) { _, assetID in
                        ActivityAssetView(assetID: assetID, mood: .happy)
                    }
                }
                .accessibilityLabel("停車場 / Parking lot")
            } onSelect: { id in
                selectMoreFewer(id == "lot-left" ? .left : .right)
            }
        }
    }

    private var shadowMatch: some View {
        let q = model.currentShadowMatchQuestion
        let options = q.presentedOptions(seed: choiceDealSeed)
        return board(promptZH: q.promptTraditionalChinese, promptEN: q.promptEnglish,
                     hintID: q.correctOptionID, choiceCount: options.count) {
            StimulusPanel {
                ActivityAssetView(assetID: q.targetAssetID, mood: .calm, asShadow: true)
            }
        } choices: {
            choiceRow(ids: options.map(\.id), hintID: q.correctOptionID) { id in
                if let opt = q.options.first(where: { $0.id == id }) {
                    ActivityAssetView(assetID: opt.assetID, mood: .happy)
                        .accessibilityLabel("\(opt.labelTraditionalChinese), \(opt.labelEnglish)")
                }
            } onSelect: { selectShadow($0) }
        }
    }

    private var emptyBay: some View {
        let q = model.currentEmptyBayQuestion
        let bays = q.presentedBays(seed: choiceDealSeed)
        return board(promptZH: q.promptTraditionalChinese, promptEN: q.promptEnglish,
                     hintID: q.correctBayID, choiceCount: bays.count) {
            StimulusPanel {
                HStack(spacing: 12) {
                    ForEach(bays, id: \.id) { bay in
                        ZStack {
                            RoundedRectangle(cornerRadius: 16).stroke(Color.ink, lineWidth: 3)
                            if let asset = bay.vehicleAssetID {
                                ActivityAssetView(assetID: asset, mood: .calm)
                                    .padding(6)
                            }
                        }
                        .frame(width: 90, height: 90)
                    }
                }
            }
        } choices: {
            choiceRow(ids: bays.map(\.id), hintID: q.correctBayID) { id in
                if let bay = q.bays.first(where: { $0.id == id }) {
                    ZStack {
                        if let asset = bay.vehicleAssetID {
                            ActivityAssetView(assetID: asset, mood: .happy)
                        } else {
                            CanvasText("空", size: 40, weight: 900)
                        }
                    }
                    .accessibilityLabel(bay.vehicleAssetID == nil ? "空車位 / Empty bay" : "有車 / Occupied")
                }
            } onSelect: { selectBay($0) }
        }
    }

    // MARK: - Shared builders

    private func board<S: View, C: View>(
        promptZH: String,
        promptEN: String,
        hintID: String,
        choiceCount: Int,
        @ViewBuilder stimulus: @escaping () -> S,
        @ViewBuilder choices: @escaping () -> C
    ) -> some View {
        let prompt = SpokenPrompt(key: "activity.\(shownKind?.rawValue ?? "x")",
                                  traditionalChinese: promptZH, english: promptEN)
        let hintToward: CGFloat = (hintUsed && !hintID.isEmpty) ? 36 : 0
        return ActivityBoardView(
            prompt: prompt,
            coneTotal: 1,
            coneCompleted: justCompleted ? 1 : 0,
            stampyOffsetTowardHint: hintToward,
            pendingMinutes: pendingMinutes,
            startingMinutes: startingMinutes,
            thinkPauseRemaining: thinkRemaining,
            fuelFeedback: fuelFeedback,
            choicesLocked: choicesAreLocked,
            onSpeak: speakPrompt,
            stimulus: stimulus,
            choices: choices
        )
    }

    @ViewBuilder
    private func choiceRow<Content: View>(
        ids: [String],
        hintID: String,
        cardWidth: Double = DesignTokens.choiceCardWidth,
        @ViewBuilder content: @escaping (String) -> Content,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 24) {
            ForEach(ids, id: \.self) { id in
                let feedback: ChoiceFeedback = {
                    if lastCorrectID == id { return .correct }
                    if lastIncorrectID == id { return .incorrect }
                    if hintUsed && id == hintID { return .hint }
                    return .idle
                }()
                ChoiceCardChrome(
                    feedback: feedback,
                    isHintTarget: hintUsed && id == hintID,
                    isInteractionEnabled: !choicesAreLocked,
                    cardWidth: cardWidth,
                    action: { onSelect(id) }
                ) {
                    content(id)
                }
            }
        }
    }
}
