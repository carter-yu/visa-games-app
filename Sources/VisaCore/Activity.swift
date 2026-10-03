import Foundation

/// Stable asset reference for a picture option (silhouette id or image asset id).
/// VisaCore stays UI-free: the app maps `assetID` to original VehicleSilhouette kinds.
public struct ActivityOption: Sendable, Equatable, Codable {
    public var id: String
    public var assetID: String
    public var labelTraditionalChinese: String
    public var labelEnglish: String

    public init(
        id: String,
        assetID: String,
        labelTraditionalChinese: String,
        labelEnglish: String
    ) {
        self.id = id
        self.assetID = assetID
        self.labelTraditionalChinese = labelTraditionalChinese
        self.labelEnglish = labelEnglish
    }
}

/// Activity genres suitable for a 3–5yo Wacom/touch kiosk.
/// Inspiration is activity-TYPE only (preschool workbook genres such as matching,
/// find-the-same, count-to-N, sequencing, half-match, shape cousin, capacity,
/// more/fewer, shadow match, empty bay). No Gakken / Play Smart pages, art,
/// characters, titles, or trademarked packaging are copied.
public enum ActivityKind: String, CaseIterable, Sendable, Codable, Equatable, Hashable {
    /// Two-picture choose (existing M3 fire-vs-taxi).
    case twoPictureChoose
    /// Show a target silhouette; pick the matching option among distractors.
    case findTheSame
    /// Show N vehicle silhouettes; tap the correct count.
    case countVehicles
    /// Order vehicles short→long (convoy lineup). Playable in v0.7+.
    case sequenceShortToLong
    /// Left half of a vehicle → pick the matching right half (v0.8).
    case halfMatch
    /// Round reference (sun) → pick the round cousin among props/vehicles (v0.8).
    case shapeCousin
    /// Bus vs taxi — who carries more people (v0.8).
    case capacityCompare
    /// Two parking lots — which has more vehicles (v0.8).
    case moreFewer
    /// Black silhouette → matching colored hero (v0.8).
    case shadowMatch
    /// Three depot bays — tap the empty one (v0.8).
    case emptyBay
}

extension ActivityKind {
    /// Parent catalog card title (HK Traditional). Not the child prompt.
    public var parentCardTitle: String {
        switch self {
        case .twoPictureChoose: return "邊架消防車"
        case .findTheSame: return "搵同一個"
        case .countVehicles: return "數消防車"
        case .sequenceShortToLong: return "短到長車隊"
        case .halfMatch: return "搵另一半"
        case .shapeCousin: return "圓圓嘅"
        case .capacityCompare: return "邊架載多啲人"
        case .moreFewer: return "邊邊車多啲"
        case .shadowMatch: return "邊個影子"
        case .emptyBay: return "空車位"
        }
    }

    /// Short English subtitle on the parent card (not the spoken prompt).
    public var parentCardEnglish: String {
        switch self {
        case .twoPictureChoose: return "Which fire truck"
        case .findTheSame: return "Find the same"
        case .countVehicles: return "Count the fire trucks"
        case .sequenceShortToLong: return "Short-to-long convoy"
        case .halfMatch: return "Find the other half"
        case .shapeCousin: return "Round like the sun"
        case .capacityCompare: return "Who carries more"
        case .moreFewer: return "Which lot has more"
        case .shadowMatch: return "Match the shadow"
        case .emptyBay: return "Empty parking bay"
        }
    }

    /// Corner pill on the art well.
    public var parentShortLabel: String {
        switch self {
        case .twoPictureChoose: return "兩圖"
        case .findTheSame: return "搵相同"
        case .countVehicles: return "數數"
        case .sequenceShortToLong: return "車隊"
        case .halfMatch: return "另一半"
        case .shapeCousin: return "圓形"
        case .capacityCompare: return "載人"
        case .moreFewer: return "多定少"
        case .shadowMatch: return "影子"
        case .emptyBay: return "空位"
        }
    }

    /// Help tip — the child prompt in HK Traditional, not the card title.
    public var parentHelpTraditionalChinese: String {
        switch self {
        case .twoPictureChoose: return "邊架係消防車呀？"
        case .findTheSame: return "搵同一個！邊架同上面一樣？"
        case .countVehicles: return "數一數有幾架消防車呀？"
        case .sequenceShortToLong: return "由短到長排車隊。"
        case .halfMatch: return "搵另一半！"
        case .shapeCousin: return "太陽圓圓嘅，邊樣都係圓圓嘅？"
        case .capacityCompare: return "巴士同的士，邊架載多啲人？"
        case .moreFewer: return "邊邊停車場嘅車多啲？"
        case .shadowMatch: return "邊架啱呢個影子？"
        case .emptyBay: return "邊個車位係空嘅？"
        }
    }

    public var parentHelpEnglish: String {
        switch self {
        case .twoPictureChoose: return "Which one is the fire truck?"
        case .findTheSame: return "Which one matches the one above?"
        case .countVehicles: return "How many fire trucks?"
        case .sequenceShortToLong: return "Line the convoy up from short to long."
        case .halfMatch: return "Find the other half!"
        case .shapeCousin: return "The sun is round — which one is also round?"
        case .capacityCompare: return "Bus or taxi — which carries more people?"
        case .moreFewer: return "Which parking lot has more vehicles?"
        case .shadowMatch: return "Which vehicle matches this shadow?"
        case .emptyBay: return "Which parking bay is empty?"
        }
    }

    /// Static hero asset ids for the parent card (not a live round).
    public var parentHeroAssetIDs: [String] {
        switch self {
        case .twoPictureChoose:
            return ["silhouette.fireEngine", "silhouette.hkTaxi"]
        case .findTheSame:
            return ["silhouette.hkTaxi"]
        case .countVehicles:
            return ["silhouette.fireEngine", "silhouette.fireEngine", "silhouette.fireEngine"]
        case .sequenceShortToLong:
            return ["silhouette.hkTaxi", "silhouette.fireEngine", "silhouette.crane", "silhouette.metroTrain"]
        case .halfMatch:
            return ["silhouette.fireEngine"]
        case .shapeCousin:
            return ["prop.sun", "silhouette.tanker"]
        case .capacityCompare:
            return ["silhouette.articulatedBus", "silhouette.hkTaxi"]
        case .moreFewer:
            return ["silhouette.hkTaxi", "silhouette.nyTaxi", "silhouette.fireEngine", "silhouette.articulatedBus"]
        case .shadowMatch:
            return ["silhouette.metroTrain"]
        case .emptyBay:
            return ["silhouette.hkTaxi", "silhouette.fireEngine"]
        }
    }
}

/// First child entry gate: choose one of two pictures (ADR 0004 / M3 scaffold).
/// Prompt copy is HK Traditional Chinese + English only — never Simplified.
public struct TwoPictureQuestion: Sendable, Equatable, Codable {
    public var promptTraditionalChinese: String
    public var promptEnglish: String
    public var options: [ActivityOption]
    public var correctOptionID: String
    /// Stable completion ID for exactly-once reward / assisted recording (ADR 0002 D3 / D7).
    public var completionID: String

    public init(
        promptTraditionalChinese: String,
        promptEnglish: String,
        options: [ActivityOption],
        correctOptionID: String,
        completionID: String
    ) {
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.options = options
        self.correctOptionID = correctOptionID
        self.completionID = completionID
    }

    public var isWellFormed: Bool {
        guard options.count == 2 else { return false }
        guard !completionID.isEmpty, !correctOptionID.isEmpty else { return false }
        let ids = Set(options.map(\.id))
        guard ids.count == 2, ids.contains(correctOptionID) else { return false }
        return options.allSatisfy { !$0.id.isEmpty && !$0.assetID.isEmpty }
    }
}

/// Find-the-same: match the target silhouette among options (M4).
public struct FindSameQuestion: Sendable, Equatable, Codable {
    public var promptTraditionalChinese: String
    public var promptEnglish: String
    public var targetAssetID: String
    public var options: [ActivityOption]
    public var correctOptionID: String
    public var completionID: String

    public init(
        promptTraditionalChinese: String,
        promptEnglish: String,
        targetAssetID: String,
        options: [ActivityOption],
        correctOptionID: String,
        completionID: String
    ) {
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.targetAssetID = targetAssetID
        self.options = options
        self.correctOptionID = correctOptionID
        self.completionID = completionID
    }

    public var isWellFormed: Bool {
        guard options.count >= 2, options.count <= 4 else { return false }
        guard !completionID.isEmpty, !correctOptionID.isEmpty, !targetAssetID.isEmpty else {
            return false
        }
        let ids = Set(options.map(\.id))
        guard ids.count == options.count, ids.contains(correctOptionID) else { return false }
        guard let correct = options.first(where: { $0.id == correctOptionID }),
              correct.assetID == targetAssetID else { return false }
        return options.allSatisfy { !$0.id.isEmpty && !$0.assetID.isEmpty }
    }
}

/// Count-to-N: tap how many vehicle silhouettes are shown (M4).
public struct CountQuestion: Sendable, Equatable, Codable {
    public var promptTraditionalChinese: String
    public var promptEnglish: String
    public var vehicleAssetIDs: [String]
    public var correctCount: Int
    public var choiceCounts: [Int]
    public var completionID: String

    public init(
        promptTraditionalChinese: String,
        promptEnglish: String,
        vehicleAssetIDs: [String],
        correctCount: Int,
        choiceCounts: [Int],
        completionID: String
    ) {
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.vehicleAssetIDs = vehicleAssetIDs
        self.correctCount = correctCount
        self.choiceCounts = choiceCounts
        self.completionID = completionID
    }

    public var isWellFormed: Bool {
        guard !completionID.isEmpty else { return false }
        guard correctCount >= 1, correctCount <= 5 else { return false }
        guard vehicleAssetIDs.count == correctCount else { return false }
        guard vehicleAssetIDs.allSatisfy({ !$0.isEmpty }) else { return false }
        guard choiceCounts.count >= 2, choiceCounts.count <= 5 else { return false }
        guard Set(choiceCounts).count == choiceCounts.count else { return false }
        guard choiceCounts.contains(correctCount) else { return false }
        guard choiceCounts.allSatisfy({ $0 >= 1 && $0 <= 5 }) else { return false }
        return true
    }
}

/// Sequencing short→long vehicles (convoy lineup). Original silhouettes only.
public struct SequenceQuestion: Sendable, Equatable, Codable {
    public var promptTraditionalChinese: String
    public var promptEnglish: String
    /// Asset IDs already ordered short → long (correct convoy order).
    public var orderedAssetIDs: [String]
    public var completionID: String

    public init(
        promptTraditionalChinese: String,
        promptEnglish: String,
        orderedAssetIDs: [String],
        completionID: String
    ) {
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.orderedAssetIDs = orderedAssetIDs
        self.completionID = completionID
    }

    /// Playable once catalog + large-target order UI are wired (v0.7).
    public var isPlayable: Bool { true }

    public var isWellFormed: Bool {
        orderedAssetIDs.count >= 3
            && orderedAssetIDs.count <= 4
            && !completionID.isEmpty
            && orderedAssetIDs.allSatisfy { !$0.isEmpty }
            && Set(orderedAssetIDs).count == orderedAssetIDs.count
    }
}

/// Half-match: show the LEFT half of `targetAssetID`; pick the option whose
/// RIGHT half completes the same vehicle (correct option assetID == target).
public struct HalfMatchQuestion: Sendable, Equatable, Codable {
    public var promptTraditionalChinese: String
    public var promptEnglish: String
    public var targetAssetID: String
    public var options: [ActivityOption]
    public var correctOptionID: String
    public var completionID: String

    public init(
        promptTraditionalChinese: String,
        promptEnglish: String,
        targetAssetID: String,
        options: [ActivityOption],
        correctOptionID: String,
        completionID: String
    ) {
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.targetAssetID = targetAssetID
        self.options = options
        self.correctOptionID = correctOptionID
        self.completionID = completionID
    }

    public var isWellFormed: Bool {
        guard options.count >= 2, options.count <= 4 else { return false }
        guard !completionID.isEmpty, !correctOptionID.isEmpty, !targetAssetID.isEmpty else {
            return false
        }
        let ids = Set(options.map(\.id))
        guard ids.count == options.count, ids.contains(correctOptionID) else { return false }
        guard let correct = options.first(where: { $0.id == correctOptionID }),
              correct.assetID == targetAssetID else { return false }
        return options.allSatisfy { !$0.id.isEmpty && !$0.assetID.isEmpty }
    }
}

/// Shape cousin: match a round (or other) reference among options.
/// Target may be a prop (`prop.sun`) or vehicle silhouette asset ID.
public struct ShapeCousinQuestion: Sendable, Equatable, Codable {
    public var promptTraditionalChinese: String
    public var promptEnglish: String
    public var targetAssetID: String
    public var options: [ActivityOption]
    public var correctOptionID: String
    public var completionID: String

    public init(
        promptTraditionalChinese: String,
        promptEnglish: String,
        targetAssetID: String,
        options: [ActivityOption],
        correctOptionID: String,
        completionID: String
    ) {
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.targetAssetID = targetAssetID
        self.options = options
        self.correctOptionID = correctOptionID
        self.completionID = completionID
    }

    public var isWellFormed: Bool {
        guard options.count >= 2, options.count <= 4 else { return false }
        guard !completionID.isEmpty, !correctOptionID.isEmpty, !targetAssetID.isEmpty else {
            return false
        }
        let ids = Set(options.map(\.id))
        guard ids.count == options.count, ids.contains(correctOptionID) else { return false }
        return options.allSatisfy { !$0.id.isEmpty && !$0.assetID.isEmpty }
    }
}

/// Capacity compare: which vehicle carries more (bus vs taxi, etc.).
public struct CapacityCompareQuestion: Sendable, Equatable, Codable {
    public var promptTraditionalChinese: String
    public var promptEnglish: String
    public var options: [ActivityOption]
    public var correctOptionID: String
    public var completionID: String

    public init(
        promptTraditionalChinese: String,
        promptEnglish: String,
        options: [ActivityOption],
        correctOptionID: String,
        completionID: String
    ) {
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.options = options
        self.correctOptionID = correctOptionID
        self.completionID = completionID
    }

    public var isWellFormed: Bool {
        guard options.count == 2 else { return false }
        guard !completionID.isEmpty, !correctOptionID.isEmpty else { return false }
        let ids = Set(options.map(\.id))
        guard ids.count == 2, ids.contains(correctOptionID) else { return false }
        return options.allSatisfy { !$0.id.isEmpty && !$0.assetID.isEmpty }
    }
}

/// Parking-lot side for more/fewer.
public enum ParkingLotSide: String, Sendable, Codable, Equatable {
    case left
    case right
}

/// More/fewer: two parking lots; tap the side with more vehicles.
public struct MoreFewerQuestion: Sendable, Equatable, Codable {
    public var promptTraditionalChinese: String
    public var promptEnglish: String
    public var leftLotAssetIDs: [String]
    public var rightLotAssetIDs: [String]
    public var correctSide: ParkingLotSide
    public var completionID: String

    public init(
        promptTraditionalChinese: String,
        promptEnglish: String,
        leftLotAssetIDs: [String],
        rightLotAssetIDs: [String],
        correctSide: ParkingLotSide,
        completionID: String
    ) {
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.leftLotAssetIDs = leftLotAssetIDs
        self.rightLotAssetIDs = rightLotAssetIDs
        self.correctSide = correctSide
        self.completionID = completionID
    }

    public var isWellFormed: Bool {
        guard !completionID.isEmpty else { return false }
        guard !leftLotAssetIDs.isEmpty, !rightLotAssetIDs.isEmpty else { return false }
        guard leftLotAssetIDs.count <= 5, rightLotAssetIDs.count <= 5 else { return false }
        guard leftLotAssetIDs.count != rightLotAssetIDs.count else { return false }
        guard leftLotAssetIDs.allSatisfy({ !$0.isEmpty }),
              rightLotAssetIDs.allSatisfy({ !$0.isEmpty }) else { return false }
        let more: ParkingLotSide =
            leftLotAssetIDs.count > rightLotAssetIDs.count ? .left : .right
        return correctSide == more
    }
}

/// Shadow match: black silhouette target → pick matching colored hero.
public struct ShadowMatchQuestion: Sendable, Equatable, Codable {
    public var promptTraditionalChinese: String
    public var promptEnglish: String
    public var targetAssetID: String
    public var options: [ActivityOption]
    public var correctOptionID: String
    public var completionID: String

    public init(
        promptTraditionalChinese: String,
        promptEnglish: String,
        targetAssetID: String,
        options: [ActivityOption],
        correctOptionID: String,
        completionID: String
    ) {
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.targetAssetID = targetAssetID
        self.options = options
        self.correctOptionID = correctOptionID
        self.completionID = completionID
    }

    public var isWellFormed: Bool {
        guard options.count >= 2, options.count <= 4 else { return false }
        guard !completionID.isEmpty, !correctOptionID.isEmpty, !targetAssetID.isEmpty else {
            return false
        }
        let ids = Set(options.map(\.id))
        guard ids.count == options.count, ids.contains(correctOptionID) else { return false }
        guard let correct = options.first(where: { $0.id == correctOptionID }),
              correct.assetID == targetAssetID else { return false }
        return options.allSatisfy { !$0.id.isEmpty && !$0.assetID.isEmpty }
    }
}

/// One depot parking bay — `vehicleAssetID == nil` means empty.
public struct EmptyBaySlot: Sendable, Equatable, Codable {
    public var id: String
    public var vehicleAssetID: String?

    public init(id: String, vehicleAssetID: String?) {
        self.id = id
        self.vehicleAssetID = vehicleAssetID
    }

    public var isEmpty: Bool { vehicleAssetID == nil }
}

/// Empty bay: three depot slots; tap the empty one.
public struct EmptyBayQuestion: Sendable, Equatable, Codable {
    public var promptTraditionalChinese: String
    public var promptEnglish: String
    public var bays: [EmptyBaySlot]
    public var correctBayID: String
    public var completionID: String

    public init(
        promptTraditionalChinese: String,
        promptEnglish: String,
        bays: [EmptyBaySlot],
        correctBayID: String,
        completionID: String
    ) {
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.bays = bays
        self.correctBayID = correctBayID
        self.completionID = completionID
    }

    public var isWellFormed: Bool {
        guard bays.count == 3 else { return false }
        guard !completionID.isEmpty, !correctBayID.isEmpty else { return false }
        let ids = Set(bays.map(\.id))
        guard ids.count == 3, ids.contains(correctBayID) else { return false }
        guard bays.allSatisfy({ !$0.id.isEmpty }) else { return false }
        let emptyBays = bays.filter(\.isEmpty)
        guard emptyBays.count == 1, emptyBays[0].id == correctBayID else { return false }
        // Occupied bays must have non-empty asset IDs.
        return bays.filter { !$0.isEmpty }.allSatisfy {
            ($0.vehicleAssetID ?? "").isEmpty == false
        }
    }
}

/// Outcome of evaluating one child selection.
public enum ActivityEvaluation: Sendable, Equatable {
    case correct(assisted: Bool)
    case incorrect
}

/// Pure evaluators for entry activities. Incorrect → UI applies WrongAnswerPolicy (pending shrink + Think Pause).
public struct ActivityEvaluator: Sendable {
    public init() {}

    public func evaluate(
        question: TwoPictureQuestion,
        selectedOptionID: String,
        hintUsed: Bool
    ) -> ActivityEvaluation {
        guard question.isWellFormed else { return .incorrect }
        guard question.options.contains(where: { $0.id == selectedOptionID }) else {
            return .incorrect
        }
        if selectedOptionID == question.correctOptionID {
            return .correct(assisted: hintUsed)
        }
        return .incorrect
    }

    public func evaluate(
        question: FindSameQuestion,
        selectedOptionID: String,
        hintUsed: Bool
    ) -> ActivityEvaluation {
        guard question.isWellFormed else { return .incorrect }
        guard question.options.contains(where: { $0.id == selectedOptionID }) else {
            return .incorrect
        }
        if selectedOptionID == question.correctOptionID {
            return .correct(assisted: hintUsed)
        }
        return .incorrect
    }

    public func evaluate(
        question: CountQuestion,
        selectedCount: Int,
        hintUsed: Bool
    ) -> ActivityEvaluation {
        guard question.isWellFormed else { return .incorrect }
        guard question.choiceCounts.contains(selectedCount) else { return .incorrect }
        if selectedCount == question.correctCount {
            return .correct(assisted: hintUsed)
        }
        return .incorrect
    }

    /// Full short→long tap order must match `orderedAssetIDs` exactly.
    public func evaluate(
        question: SequenceQuestion,
        orderedSelectionIDs: [String],
        hintUsed: Bool
    ) -> ActivityEvaluation {
        guard question.isPlayable, question.isWellFormed else { return .incorrect }
        guard orderedSelectionIDs.count == question.orderedAssetIDs.count else {
            return .incorrect
        }
        if orderedSelectionIDs == question.orderedAssetIDs {
            return .correct(assisted: hintUsed)
        }
        return .incorrect
    }

    /// Next expected asset for progressive convoy tapping (nil when complete).
    public func nextExpectedAssetID(
        question: SequenceQuestion,
        tappedSoFar: [String]
    ) -> String? {
        guard question.isPlayable, question.isWellFormed else { return nil }
        guard tappedSoFar.count < question.orderedAssetIDs.count else { return nil }
        // Prefix must already be correct; otherwise UI should have reset.
        let expectedPrefix = Array(question.orderedAssetIDs.prefix(tappedSoFar.count))
        guard tappedSoFar == expectedPrefix else { return nil }
        return question.orderedAssetIDs[tappedSoFar.count]
    }

    public func evaluate(
        question: HalfMatchQuestion,
        selectedOptionID: String,
        hintUsed: Bool
    ) -> ActivityEvaluation {
        guard question.isWellFormed else { return .incorrect }
        guard question.options.contains(where: { $0.id == selectedOptionID }) else {
            return .incorrect
        }
        if selectedOptionID == question.correctOptionID {
            return .correct(assisted: hintUsed)
        }
        return .incorrect
    }

    public func evaluate(
        question: ShapeCousinQuestion,
        selectedOptionID: String,
        hintUsed: Bool
    ) -> ActivityEvaluation {
        guard question.isWellFormed else { return .incorrect }
        guard question.options.contains(where: { $0.id == selectedOptionID }) else {
            return .incorrect
        }
        if selectedOptionID == question.correctOptionID {
            return .correct(assisted: hintUsed)
        }
        return .incorrect
    }

    public func evaluate(
        question: CapacityCompareQuestion,
        selectedOptionID: String,
        hintUsed: Bool
    ) -> ActivityEvaluation {
        guard question.isWellFormed else { return .incorrect }
        guard question.options.contains(where: { $0.id == selectedOptionID }) else {
            return .incorrect
        }
        if selectedOptionID == question.correctOptionID {
            return .correct(assisted: hintUsed)
        }
        return .incorrect
    }

    public func evaluate(
        question: MoreFewerQuestion,
        selectedSide: ParkingLotSide,
        hintUsed: Bool
    ) -> ActivityEvaluation {
        guard question.isWellFormed else { return .incorrect }
        if selectedSide == question.correctSide {
            return .correct(assisted: hintUsed)
        }
        return .incorrect
    }

    public func evaluate(
        question: ShadowMatchQuestion,
        selectedOptionID: String,
        hintUsed: Bool
    ) -> ActivityEvaluation {
        guard question.isWellFormed else { return .incorrect }
        guard question.options.contains(where: { $0.id == selectedOptionID }) else {
            return .incorrect
        }
        if selectedOptionID == question.correctOptionID {
            return .correct(assisted: hintUsed)
        }
        return .incorrect
    }

    public func evaluate(
        question: EmptyBayQuestion,
        selectedBayID: String,
        hintUsed: Bool
    ) -> ActivityEvaluation {
        guard question.isWellFormed else { return .incorrect }
        guard question.bays.contains(where: { $0.id == selectedBayID }) else {
            return .incorrect
        }
        if selectedBayID == question.correctBayID {
            return .correct(assisted: hintUsed)
        }
        return .incorrect
    }
}

/// Built-in first entry activity using original long-vehicle silhouette asset IDs already in the app.
/// Original city / works vehicles only. Does not hardcode YouTube pack IDs (D9 open).
public enum FirstEntryActivity {
    public static let completionID = "entry-two-picture-fire-vs-taxi-v1"

    /// HK fire engine vs HK red taxi — recognizable city vehicles, original art.
    public static let question = TwoPictureQuestion(
        promptTraditionalChinese: "邊架係消防車呀？撳一撳！",
        promptEnglish: "Which one is the fire truck? Tap!",
        options: [
            ActivityOption(
                id: "opt-fire",
                assetID: "silhouette.fireEngine",
                labelTraditionalChinese: "消防車",
                labelEnglish: "Fire truck"
            ),
            ActivityOption(
                id: "opt-hktaxi",
                assetID: "silhouette.hkTaxi",
                labelTraditionalChinese: "的士",
                labelEnglish: "Taxi"
            )
        ],
        correctOptionID: "opt-fire",
        completionID: completionID
    )
}

/// Catalog of original Visa Depot activities (M4 / v0.8 pack).
/// Activity-type inspiration only — no Gakken IP; no Tomica/Thomas/Tayo likenesses.
public enum ActivityCatalog {
    /// Playable kinds the child can get after picking difficulty (rotation by round seed).
    public static let playableKinds: [ActivityKind] = [
        .twoPictureChoose,
        .findTheSame,
        .countVehicles,
        .sequenceShortToLong,
        .halfMatch,
        .shapeCousin,
        .capacityCompare,
        .moreFewer,
        .shadowMatch,
        .emptyBay
    ]

    /// Reserved for future genres (path-trace, maze-lite, inside/outside, …).
    public static let stubKinds: [ActivityKind] = []

    /// Named in ADR 0005 but not built. Parent catalog shows these as a muted row — never as cards.
    public struct UnbuiltParentActivity: Equatable, Sendable {
        public var traditionalChinese: String
        public var english: String

        public init(traditionalChinese: String, english: String) {
            self.traditionalChinese = traditionalChinese
            self.english = english
        }
    }

    public static let unbuiltParentActivities: [UnbuiltParentActivity] = [
        UnbuiltParentActivity(traditionalChinese: "描線", english: "Path trace"),
        UnbuiltParentActivity(traditionalChinese: "迷宮", english: "Maze"),
        UnbuiltParentActivity(traditionalChinese: "形狀分類", english: "Shape sort"),
        UnbuiltParentActivity(traditionalChinese: "連點", english: "Connect the dots")
    ]

    /// Deterministic rotation from the round UUID / seed string across every playable kind.
    public static func kind(forRoundSeed seed: String) -> ActivityKind {
        kind(forRoundSeed: seed, pool: playableKinds)
    }

    /// Same hash as `kind(forRoundSeed:)`, modulo `pool` only.
    /// Empty pool falls back to all playable kinds (corrupt / empty star must still deal).
    public static func kind(forRoundSeed seed: String, pool: [ActivityKind]) -> ActivityKind {
        let kinds = pool.isEmpty ? playableKinds : pool
        let hash = seed.unicodeScalars.reduce(into: 0) { partial, scalar in
            partial = partial &* 31 &+ Int(scalar.value)
        }
        let count = kinds.count
        // Avoid Int.min abs overflow; keep index in 0..<count.
        let index = ((hash % count) + count) % count
        return kinds[index]
    }

    public static func twoPictureQuestion() -> TwoPictureQuestion {
        FirstEntryActivity.question
    }

    /// Target HK taxi; options fire / HK taxi / NY taxi. Original silhouettes only.
    public static func findSameQuestion() -> FindSameQuestion {
        FindSameQuestion(
            promptTraditionalChinese: "搵同一個！邊架同上面一樣？",
            promptEnglish: "Find the same! Which one matches above?",
            targetAssetID: "silhouette.hkTaxi",
            options: [
                ActivityOption(
                    id: "find-fire",
                    assetID: "silhouette.fireEngine",
                    labelTraditionalChinese: "消防車",
                    labelEnglish: "Fire truck"
                ),
                ActivityOption(
                    id: "find-hktaxi",
                    assetID: "silhouette.hkTaxi",
                    labelTraditionalChinese: "紅的",
                    labelEnglish: "Red taxi"
                ),
                ActivityOption(
                    id: "find-nytaxi",
                    assetID: "silhouette.nyTaxi",
                    labelTraditionalChinese: "黃的",
                    labelEnglish: "Yellow taxi"
                )
            ],
            correctOptionID: "find-hktaxi",
            completionID: "entry-find-same-hk-taxi-v1"
        )
    }

    /// Three fire trucks — tap 3 among 2/3/4.
    public static func countQuestion() -> CountQuestion {
        CountQuestion(
            promptTraditionalChinese: "數一數有幾架消防車呀？撳個數！",
            promptEnglish: "How many fire trucks? Tap the number!",
            vehicleAssetIDs: [
                "silhouette.fireEngine",
                "silhouette.fireEngine",
                "silhouette.fireEngine"
            ],
            correctCount: 3,
            choiceCounts: [2, 3, 4],
            completionID: "entry-count-fire-3-v1"
        )
    }

    /// Short→long convoy: taxi → fire → crane → metro (visual length order).
    public static func sequenceQuestion() -> SequenceQuestion {
        SequenceQuestion(
            promptTraditionalChinese: "由短到長排車隊。最短先撳。",
            promptEnglish: "Line up the convoy short to long. Tap the shortest first.",
            orderedAssetIDs: [
                "silhouette.hkTaxi",
                "silhouette.fireEngine",
                "silhouette.crane",
                "silhouette.metroTrain"
            ],
            completionID: "entry-sequence-short-to-long-v1"
        )
    }

    /// Compatibility alias — same playable convoy question.
    public static func sequenceStubQuestion() -> SequenceQuestion {
        sequenceQuestion()
    }

    /// Left half of fire engine; options show right halves — fire / bus / tanker.
    public static func halfMatchQuestion() -> HalfMatchQuestion {
        HalfMatchQuestion(
            promptTraditionalChinese: "搵另一半！邊幅係正確嘅右半邊？",
            promptEnglish: "Find the other half! Which is the matching right side?",
            targetAssetID: "silhouette.fireEngine",
            options: [
                ActivityOption(
                    id: "half-bus",
                    assetID: "silhouette.articulatedBus",
                    labelTraditionalChinese: "巴士",
                    labelEnglish: "Bus"
                ),
                ActivityOption(
                    id: "half-fire",
                    assetID: "silhouette.fireEngine",
                    labelTraditionalChinese: "消防車",
                    labelEnglish: "Fire truck"
                ),
                ActivityOption(
                    id: "half-tanker",
                    assetID: "silhouette.tanker",
                    labelTraditionalChinese: "油罐車",
                    labelEnglish: "Tanker"
                )
            ],
            correctOptionID: "half-fire",
            completionID: "entry-half-match-fire-v1"
        )
    }

    /// Sun is round → pick the round tanker tank among cone / toolbox / tanker.
    public static func shapeCousinQuestion() -> ShapeCousinQuestion {
        ShapeCousinQuestion(
            promptTraditionalChinese: "太陽圓圓嘅，邊樣都係圓圓嘅？",
            promptEnglish: "The sun is round — which one is also round?",
            targetAssetID: "prop.sun",
            options: [
                ActivityOption(
                    id: "shape-cone",
                    assetID: "prop.trafficCone",
                    labelTraditionalChinese: "雪糕筒",
                    labelEnglish: "Traffic cone"
                ),
                ActivityOption(
                    id: "shape-toolbox",
                    assetID: "prop.toolbox",
                    labelTraditionalChinese: "工具箱",
                    labelEnglish: "Toolbox"
                ),
                ActivityOption(
                    id: "shape-tanker",
                    assetID: "silhouette.tanker",
                    labelTraditionalChinese: "油罐車",
                    labelEnglish: "Tanker"
                )
            ],
            correctOptionID: "shape-tanker",
            completionID: "entry-shape-cousin-round-tanker-v1"
        )
    }

    /// Articulated bus vs HK taxi — bus carries more people.
    public static func capacityCompareQuestion() -> CapacityCompareQuestion {
        CapacityCompareQuestion(
            promptTraditionalChinese: "巴士同的士，邊架載多啲人？",
            promptEnglish: "Bus or taxi — which carries more people?",
            options: [
                ActivityOption(
                    id: "cap-taxi",
                    assetID: "silhouette.hkTaxi",
                    labelTraditionalChinese: "的士",
                    labelEnglish: "Taxi"
                ),
                ActivityOption(
                    id: "cap-bus",
                    assetID: "silhouette.articulatedBus",
                    labelTraditionalChinese: "巴士",
                    labelEnglish: "Bus"
                )
            ],
            correctOptionID: "cap-bus",
            completionID: "entry-capacity-bus-vs-taxi-v1"
        )
    }

    /// Left lot 2 taxis; right lot 4 mixed heroes — right has more.
    public static func moreFewerQuestion() -> MoreFewerQuestion {
        MoreFewerQuestion(
            promptTraditionalChinese: "邊邊停車場嘅車多啲？撳一撳！",
            promptEnglish: "Which parking lot has more vehicles? Tap!",
            leftLotAssetIDs: [
                "silhouette.hkTaxi",
                "silhouette.nyTaxi"
            ],
            rightLotAssetIDs: [
                "silhouette.fireEngine",
                "silhouette.articulatedBus",
                "silhouette.crane",
                "silhouette.toyCar"
            ],
            correctSide: .right,
            completionID: "entry-more-fewer-lots-v1"
        )
    }

    /// Shadow of metro train → pick metro among fire / metro / logistics.
    public static func shadowMatchQuestion() -> ShadowMatchQuestion {
        ShadowMatchQuestion(
            promptTraditionalChinese: "邊架啱呢個影子？",
            promptEnglish: "Which vehicle matches this shadow?",
            targetAssetID: "silhouette.metroTrain",
            options: [
                ActivityOption(
                    id: "shadow-fire",
                    assetID: "silhouette.fireEngine",
                    labelTraditionalChinese: "消防車",
                    labelEnglish: "Fire truck"
                ),
                ActivityOption(
                    id: "shadow-metro",
                    assetID: "silhouette.metroTrain",
                    labelTraditionalChinese: "地鐵",
                    labelEnglish: "Metro"
                ),
                ActivityOption(
                    id: "shadow-truck",
                    assetID: "silhouette.logisticsTruck",
                    labelTraditionalChinese: "貨車",
                    labelEnglish: "Truck"
                )
            ],
            correctOptionID: "shadow-metro",
            completionID: "entry-shadow-match-metro-v1"
        )
    }

    /// Three bays: taxi, empty, fire — empty is correct.
    public static func emptyBayQuestion() -> EmptyBayQuestion {
        EmptyBayQuestion(
            promptTraditionalChinese: "邊個車位係空嘅？",
            promptEnglish: "Which parking bay is empty?",
            bays: [
                EmptyBaySlot(id: "bay-a", vehicleAssetID: "silhouette.hkTaxi"),
                EmptyBaySlot(id: "bay-b", vehicleAssetID: nil),
                EmptyBaySlot(id: "bay-c", vehicleAssetID: "silhouette.fireEngine")
            ],
            correctBayID: "bay-b",
            completionID: "entry-empty-bay-v1"
        )
    }

    public static func hintTraditionalChinese(for kind: ActivityKind) -> String {
        switch kind {
        case .twoPictureChoose:
            return "提示：消防車有長梯。 / Hint: the fire truck has a long ladder."
        case .findTheSame:
            return "提示：搵紅色的士。 / Hint: look for the red taxi."
        case .countVehicles:
            return "提示：一架一架數消防車。 / Hint: count one fire truck at a time."
        case .sequenceShortToLong:
            return "提示：最短嗰架的士先。 / Hint: tap the shortest taxi first."
        case .halfMatch:
            return "提示：睇梯同車頭顏色。 / Hint: match the ladder and cab color."
        case .shapeCousin:
            return "提示：油罐車個罐好圓。 / Hint: the tanker tank is round."
        case .capacityCompare:
            return "提示：巴士好長，載好多人。 / Hint: the long bus carries many people."
        case .moreFewer:
            return "提示：數一數兩邊有幾架。 / Hint: count the vehicles on each side."
        case .shadowMatch:
            return "提示：影子好長，似地鐵。 / Hint: the long shadow looks like the metro."
        case .emptyBay:
            return "提示：邊格冇車停。 / Hint: find the bay with no vehicle."
        }
    }
}

/// Scaffold-only Cantonese / bilingual prompt audio. Full reviewed audio pack waits on D9 Confirm.
public protocol ActivityAudioPrompting: Sendable {
    /// Speak or queue the prompt. Implementations must not claim a reviewed pack exists.
    func speakPrompt(traditionalChinese: String, english: String)
}

/// No-op audio stub — keeps the seam ready without faking “audio done.”
public struct StubActivityAudioPrompt: ActivityAudioPrompting {
    public init() {}

    public func speakPrompt(traditionalChinese: String, english: String) {
        _ = traditionalChinese
        _ = english
    }
}
