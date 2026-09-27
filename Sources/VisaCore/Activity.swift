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
/// find-the-same, count-to-N, sequencing). No Gakken / Play Smart pages, art,
/// characters, titles, or trademarked packaging are copied.
public enum ActivityKind: String, CaseIterable, Sendable, Codable, Equatable, Hashable {
    /// Two-picture choose (existing M3 crane-vs-bus).
    case twoPictureChoose
    /// Show a target silhouette; pick the matching option among distractors.
    case findTheSame
    /// Show N vehicle silhouettes; tap the correct count.
    case countVehicles
    /// Stub: order vehicles short→long. Not playable yet (M4 TODO).
    case sequenceShortToLong
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

/// Stub only — sequencing short→long vehicles. Do not wire as playable until implemented.
public struct SequenceQuestion: Sendable, Equatable, Codable {
    public var promptTraditionalChinese: String
    public var promptEnglish: String
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

    /// Always false until M4+ lands a real sequencer UI + evaluator.
    public var isPlayable: Bool { false }

    public var isWellFormed: Bool {
        orderedAssetIDs.count >= 3
            && !completionID.isEmpty
            && orderedAssetIDs.allSatisfy { !$0.isEmpty }
            && Set(orderedAssetIDs).count == orderedAssetIDs.count
    }
}

/// Outcome of evaluating one child selection.
public enum ActivityEvaluation: Sendable, Equatable {
    case correct(assisted: Bool)
    case incorrect
}

/// Pure evaluators for entry activities. Wrong answers are gentle retries (no invented penalty).
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
}

/// Built-in first entry activity using original long-vehicle silhouette asset IDs already in the app.
/// Does not reference Tomica / Takara / Thomas trademarks. Does not hardcode YouTube pack IDs (D9 open).
public enum FirstEntryActivity {
    public static let completionID = "entry-two-picture-crane-vs-bus-v1"

    /// Crane (long works vehicle) vs articulated bus — two distinct in-repo silhouettes.
    public static let question = TwoPictureQuestion(
        promptTraditionalChinese: "邊架係吊機車？用筆撳一撳。",
        promptEnglish: "Which one is the crane truck? Tap with your pen.",
        options: [
            ActivityOption(
                id: "opt-crane",
                assetID: "silhouette.crane",
                labelTraditionalChinese: "吊機車",
                labelEnglish: "Crane truck"
            ),
            ActivityOption(
                id: "opt-bus",
                assetID: "silhouette.articulatedBus",
                labelTraditionalChinese: "巴士",
                labelEnglish: "Bus"
            )
        ],
        correctOptionID: "opt-crane",
        completionID: completionID
    )
}

/// Catalog of original long-vehicle activities (M4). Activity-type inspiration only — no Gakken IP.
public enum ActivityCatalog {
    /// Playable kinds the child can get after picking difficulty (rotation by round seed).
    public static let playableKinds: [ActivityKind] = [
        .twoPictureChoose,
        .findTheSame,
        .countVehicles
    ]

    /// Stub kinds reserved for a later slice (clear TODOs in UI / docs).
    public static let stubKinds: [ActivityKind] = [
        .sequenceShortToLong
    ]

    /// Deterministic rotation from the round UUID / seed string.
    public static func kind(forRoundSeed seed: String) -> ActivityKind {
        let hash = seed.unicodeScalars.reduce(into: 0) { partial, scalar in
            partial = partial &* 31 &+ Int(scalar.value)
        }
        let count = playableKinds.count
        // Avoid Int.min abs overflow; keep index in 0..<count.
        let index = ((hash % count) + count) % count
        return playableKinds[index]
    }

    public static func twoPictureQuestion() -> TwoPictureQuestion {
        FirstEntryActivity.question
    }

    /// Target tanker; options tanker / crane / bus. Original silhouettes only.
    public static func findSameQuestion() -> FindSameQuestion {
        FindSameQuestion(
            promptTraditionalChinese: "搵同一個。邊架同上面一樣？用筆撳一撳。",
            promptEnglish: "Find the same. Which one matches the truck above? Tap with your pen.",
            targetAssetID: "silhouette.tanker",
            options: [
                ActivityOption(
                    id: "find-crane",
                    assetID: "silhouette.crane",
                    labelTraditionalChinese: "吊機車",
                    labelEnglish: "Crane truck"
                ),
                ActivityOption(
                    id: "find-tanker",
                    assetID: "silhouette.tanker",
                    labelTraditionalChinese: "油罐車",
                    labelEnglish: "Tanker"
                ),
                ActivityOption(
                    id: "find-bus",
                    assetID: "silhouette.articulatedBus",
                    labelTraditionalChinese: "巴士",
                    labelEnglish: "Bus"
                )
            ],
            correctOptionID: "find-tanker",
            completionID: "entry-find-same-tanker-v1"
        )
    }

    /// Three logistics trucks — tap 3 among 2/3/4.
    public static func countQuestion() -> CountQuestion {
        CountQuestion(
            promptTraditionalChinese: "數一數有幾架車？用筆撳個數。",
            promptEnglish: "How many trucks? Tap the number with your pen.",
            vehicleAssetIDs: [
                "silhouette.logisticsTruck",
                "silhouette.logisticsTruck",
                "silhouette.logisticsTruck"
            ],
            correctCount: 3,
            choiceCounts: [2, 3, 4],
            completionID: "entry-count-logistics-3-v1"
        )
    }

    /// Stub payload for short→long sequencing. Not playable (`isPlayable == false`).
    public static func sequenceStubQuestion() -> SequenceQuestion {
        SequenceQuestion(
            promptTraditionalChinese: "由短到長排一排。（稍後）",
            promptEnglish: "Line them up short to long. (Coming later)",
            orderedAssetIDs: [
                "silhouette.crane",
                "silhouette.tanker",
                "silhouette.articulatedBus",
                "silhouette.logisticsTruck"
            ],
            completionID: "entry-sequence-short-to-long-stub-v1"
        )
    }

    public static func hintTraditionalChinese(for kind: ActivityKind) -> String {
        switch kind {
        case .twoPictureChoose:
            return "提示：吊機有長臂。 / Hint: the crane has a long arm."
        case .findTheSame:
            return "提示：搵圓圓油罐嗰架。 / Hint: look for the round tank truck."
        case .countVehicles:
            return "提示：一架一架數。 / Hint: count one truck at a time."
        case .sequenceShortToLong:
            return "稍後開放。 / Coming later."
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
