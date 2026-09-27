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
    /// Order vehicles short→long (convoy lineup). Playable in v0.7+.
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

/// Catalog of original long-vehicle activities (M4). Activity-type inspiration only — no Gakken IP.
public enum ActivityCatalog {
    /// Playable kinds the child can get after picking difficulty (rotation by round seed).
    public static let playableKinds: [ActivityKind] = [
        .twoPictureChoose,
        .findTheSame,
        .countVehicles,
        .sequenceShortToLong
    ]

    /// Reserved for future genres (path-trace, maze-lite, …). Empty in v0.7.
    public static let stubKinds: [ActivityKind] = []

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

    /// Three logistics trucks — tap 3 among 2/3/4.
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

    /// Short→long convoy: toy car → logistics → bus → crane (visual length order).
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
