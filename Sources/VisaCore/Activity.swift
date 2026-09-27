import Foundation

/// Stable asset reference for a two-picture option (silhouette id or image asset id).
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

/// Outcome of evaluating one child selection.
public enum ActivityEvaluation: Sendable, Equatable {
    case correct(assisted: Bool)
    case incorrect
}

/// Pure evaluator for two-picture questions. Wrong answers are gentle retries (no invented penalty).
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
