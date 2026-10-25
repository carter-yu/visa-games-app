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
    /// 連一連 · 自己配: free drag matching (v0.23.0 free match; v0.24.1 own card).
    case lineMatch
    /// 連一連 · 沿路送: guided straight wide same-row roads (v0.24.1; was ★ guided).
    case lineMatchGuidedStraight
    /// 連一連 · 沿路過橋: guided narrower curved roads with one bridge (v0.24.1; was ★★ guided).
    case lineMatchGuidedBridge
    /// 畫線畫形 · 畫直線 · 熱身: across, down (and slant) lines with a vehicle (v0.25.0).
    case traceLines
    /// 畫線畫形 · 畫形狀 · 跟虛線: circle, square, ★ spire on dotted lanes (v0.25.0).
    case traceShapesDotted
    /// 畫線畫形 · 畫形狀 · 跟箭嘴: faint outlines + start / stop arrows; 3–4 shapes incl. ▲ ◁ ▽ (v0.26.0).
    case traceShapesArrows
    /// 畫線畫形 · 畫形狀 · 自己畫: corner dots + model card; the child's own crayon ink; 擦晒 (v0.26.0).
    case traceShapesFree
    /// 一架一架數 · 點一點: tap every vehicle once (N = target, 1–10); the pale numeral is revealed. Practice only (v0.28.0).
    case tapCountAll
    /// 一架一架數 · 數完畫: tap every vehicle, then trace the numeral on a dotted lane. Practice only (v0.28.0).
    case tapCountTrace
    /// 一架一架數 · 揀啱數: pick exactly T of N (3–10) vehicles; OK is judged; then trace the numeral (v0.28.0).
    case tapCountPick
    /// v0.29.0 English twins of the three 一架一架數 cards: the same game, every child-facing word and
    /// voice line in English (Carter, 2026-10-18). Shared code; only the language differs.
    case tapCountAllEnglish
    case tapCountTraceEnglish
    case tapCountPickEnglish
    /// Letters ABC · Find & flip: find both copies of the lowercase target.
    case tapLetterAll
    /// Letters ABC · Find & write: find both copies, then trace the lowercase target.
    case tapLetterWrite
}

extension ActivityKind {
    /// The three 連一連 parent cards (shared settings; separate star assignment).
    public var isLineMatchFamily: Bool {
        switch self {
        case .lineMatch, .lineMatchGuidedStraight, .lineMatchGuidedBridge: return true
        default: return false
        }
    }

    /// The 畫線畫形 cards (shared 畫形狀設定; practice only, never mastery — design D10).
    public var isShapeTraceFamily: Bool {
        self == .traceLines || self == .traceShapesDotted || self == .traceShapesArrows || self == .traceShapesFree
    }

    /// The three 一架一架數 parent cards (shared 數字設定; separate star assignment; ADR 0017).
    public var isTapCountFamily: Bool { tapCountBase != nil }

    /// The game a tap-count card plays: the English twins play exactly the Cantonese card's game.
    /// Every rule (judging, penalty, layout, tracing, guidance) keys off this, never off the language.
    public var tapCountBase: ActivityKind? {
        switch self {
        case .tapCountAll, .tapCountAllEnglish: return .tapCountAll
        case .tapCountTrace, .tapCountTraceEnglish: return .tapCountTrace
        case .tapCountPick, .tapCountPickEnglish: return .tapCountPick
        default: return nil
        }
    }

    /// What the child sees and hears on a tap-count card (nil = not a tap-count card).
    public var tapCountLanguage: TapCountLanguage? {
        switch self {
        case .tapCountAll, .tapCountTrace, .tapCountPick: return .cantonese
        case .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish: return .english
        default: return nil
        }
    }

    /// The twin of a tap-count card in the other language.
    public func tapCountKind(in language: TapCountLanguage) -> ActivityKind? {
        guard let base = tapCountBase else { return nil }
        switch (base, language) {
        case (.tapCountAll, .cantonese): return .tapCountAll
        case (.tapCountTrace, .cantonese): return .tapCountTrace
        case (.tapCountPick, .cantonese): return .tapCountPick
        case (.tapCountAll, .english): return .tapCountAllEnglish
        case (.tapCountTrace, .english): return .tapCountTraceEnglish
        default: return .tapCountPickEnglish
        }
    }

    /// Pinned difficulty. The mission star only sets visa length for these cards (design D12).
    public var tapCountLevel: ActivityLevel? {
        switch tapCountBase {
        case .tapCountAll?: return .l1
        case .tapCountTrace?: return .l2
        case .tapCountPick?: return .l3
        default: return nil
        }
    }

    /// D11: a parent plays the card through once in 試玩 before a star can be turned on.
    public var isTapLetterFamily: Bool { self == .tapLetterAll || self == .tapLetterWrite }
    public var tapLetterLevel: ActivityLevel? { self == .tapLetterAll ? .l1 : self == .tapLetterWrite ? .l2 : nil }
    public var requiresPlaytestBeforeStars: Bool { isShapeTraceFamily || isTapCountFamily || isTapLetterFamily }

    /// How this kind deals a line-match question. Guided kinds pin geometry (straight = L1,
    /// bridge = L2); free match uses the mission star's level. Nil when not a line-match kind.
    public func lineMatchDeal(missionLevel: ActivityLevel) -> (level: ActivityLevel, mode: LineMatchMode)? {
        switch self {
        case .lineMatchGuidedStraight: return (.l1, .guided)
        case .lineMatchGuidedBridge: return (.l2, .guided)
        case .lineMatch: return (missionLevel, .free)
        default: return nil
        }
    }
}

extension ActivityKind {
    /// Parent catalog card title (HK Traditional). Not the child prompt.
    public var parentCardTitle: String {
        switch self {
        case .twoPictureChoose: return "邊架消防車"
        case .findTheSame: return "搵同一個"
        case .countVehicles: return "數車仔"
        case .sequenceShortToLong: return "短到長車隊"
        case .halfMatch: return "搵另一半"
        case .shapeCousin: return "圓圓嘅"
        case .capacityCompare: return "邊架載多啲人"
        case .moreFewer: return "邊邊車多啲"
        case .shadowMatch: return "邊個影子"
        case .emptyBay: return "空車位"
        case .lineMatch: return "連一連 · 自己配"
        case .lineMatchGuidedStraight: return "連一連 · 沿路送"
        case .lineMatchGuidedBridge: return "連一連 · 沿路過橋"
        case .traceLines: return "畫直線 · 熱身"
        case .traceShapesDotted: return "畫形狀 · 跟虛線"
        case .traceShapesArrows: return "畫形狀 · 跟箭嘴"
        case .traceShapesFree: return "畫形狀 · 自己畫"
        case .tapCountAll: return "一架一架數 · 點一點"
        case .tapCountTrace: return "一架一架數 · 數完畫"
        case .tapCountPick: return "一架一架數 · 揀啱數"
        case .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish: return TapCountEnglishCopy.parentCardTitle(self)
        case .tapLetterAll: return "英文字母 ABC · 翻字卡"
        case .tapLetterWrite: return "英文字母 ABC · 搵完寫"
        }
    }

    /// Short English subtitle on the parent card (not the spoken prompt).
    public var parentCardEnglish: String {
        switch self {
        case .twoPictureChoose: return "Which fire truck"
        case .findTheSame: return "Find the same"
        case .countVehicles: return "Count the vehicles"
        case .sequenceShortToLong: return "Short-to-long convoy"
        case .halfMatch: return "Find the other half"
        case .shapeCousin: return "Round like the sun"
        case .capacityCompare: return "Who carries more"
        case .moreFewer: return "Which lot has more"
        case .shadowMatch: return "Match the shadow"
        case .emptyBay: return "Empty parking bay"
        case .lineMatch: return "Line Match · Free match"
        case .lineMatchGuidedStraight: return "Line Match · Straight road"
        case .lineMatchGuidedBridge: return "Line Match · Bridge road"
        case .traceLines: return "Lines · Warm-up"
        case .traceShapesDotted: return "Shapes · Follow the dots"
        case .traceShapesArrows: return "Shapes · Follow the arrows"
        case .traceShapesFree: return "Shapes · Draw it yourself"
        case .tapCountAll: return "Tap & Count · Tap each one"
        case .tapCountTrace: return "Tap & Count · Count, then trace"
        case .tapCountPick: return "Tap & Count · Pick just enough"
        case .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish: return TapCountEnglishCopy.parentCardEnglish(self)
        case .tapLetterAll: return "Letters ABC · Find & flip"
        case .tapLetterWrite: return "Letters ABC · Find & write"
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
        case .lineMatch: return "自己配"
        case .lineMatchGuidedStraight: return "沿路送"
        case .lineMatchGuidedBridge: return "過橋"
        case .traceLines: return "直線"
        case .traceShapesDotted: return "虛線"
        case .traceShapesArrows: return "箭嘴"
        case .traceShapesFree: return "自己畫"
        case .tapCountAll: return "點一點"
        case .tapCountTrace: return "數完畫"
        case .tapCountPick: return "揀啱數"
        case .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish: return TapCountEnglishCopy.parentShortLabel(self)
        case .tapLetterAll: return "翻字卡"
        case .tapLetterWrite: return "搵完寫"
        }
    }

    /// Help tip — the child prompt in HK Traditional, not the card title.
    public var parentHelpTraditionalChinese: String {
        switch self {
        case .twoPictureChoose: return "邊架係消防車呀？"
        case .findTheSame: return "搵同一個！邊架同上面一樣？"
        case .countVehicles: return "數一數有幾多架車呀？"
        case .sequenceShortToLong: return "由短到長排車隊。"
        case .halfMatch: return "搵另一半！"
        case .shapeCousin: return "太陽圓圓嘅，邊樣都係圓圓嘅？"
        case .capacityCompare: return "巴士同的士，邊架載多啲人？"
        case .moreFewer: return "邊邊停車場嘅車多啲？"
        case .shadowMatch: return "邊架啱呢個影子？"
        case .emptyBay: return "邊個車位係空嘅？"
        case .lineMatch: return "幫小貨車將圖仔連去啱嘅字！"
        case .lineMatchGuidedStraight: return "沿住條路揸，將字送去啱嘅圖！"
        case .lineMatchGuidedBridge: return "沿住條路過橋，將字送去啱嘅圖！"
        case .traceLines: return "由綠色箭嘴畫去紅色箭嘴！"
        case .traceShapesDotted: return "跟住虛線，畫圓形、正方形同尖頂！"
        case .traceShapesArrows: return "由綠色箭嘴開始，跟住箭嘴畫形狀！"
        case .traceShapesFree: return "照住範本，自己畫形狀！"
        case .tapCountAll: return "點一點每架車，數吓有幾多架！"
        case .tapCountTrace: return "點晒啲車，再跟住箭嘴畫個數字！"
        case .tapCountPick: return "數啱幾架就撳 OK，再畫個數字！"
        case .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish: return TapCountEnglishCopy.parentHelpTraditionalChinese(self)
        case .tapLetterAll: return "搵晒嗰個英文字母，點啱一張就翻出一張字卡（圖 + 字 + 讀音）！"
        case .tapLetterWrite: return "搵晒個英文字母（一樣翻出字卡），再跟住箭嘴寫一次！"
        }
    }

    public var parentHelpEnglish: String {
        switch self {
        case .twoPictureChoose: return "Which one is the fire truck?"
        case .findTheSame: return "Which one matches the one above?"
        case .countVehicles: return "How many vehicles?"
        case .sequenceShortToLong: return "Line the convoy up from short to long."
        case .halfMatch: return "Find the other half!"
        case .shapeCousin: return "The sun is round — which one is also round?"
        case .capacityCompare: return "Bus or taxi — which carries more people?"
        case .moreFewer: return "Which parking lot has more vehicles?"
        case .shadowMatch: return "Which vehicle matches this shadow?"
        case .emptyBay: return "Which parking bay is empty?"
        case .lineMatch: return "Help the truck join each picture to its word!"
        case .lineMatchGuidedStraight: return "Drive along the road to take each word to its picture!"
        case .lineMatchGuidedBridge: return "Drive over the bridge to take each word to its picture!"
        case .traceLines: return "Draw from the green arrow to the red arrow!"
        case .traceShapesDotted: return "Follow the dots to draw circles, squares and roofs!"
        case .traceShapesArrows: return "Start at the green arrow and follow the arrows!"
        case .traceShapesFree: return "Copy the model and draw the shape yourself!"
        case .tapCountAll: return "Tap every vehicle and count them!"
        case .tapCountTrace: return "Tap them all, then trace the number!"
        case .tapCountPick: return "Tap just the right number, press OK, then trace it!"
        case .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish: return TapCountEnglishCopy.parentHelpEnglish(self)
        case .tapLetterAll: return "Find every copy of the letter; each one flips into a word card!"
        case .tapLetterWrite: return "Find every copy, then write the letter along the arrows!"
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
        case .lineMatch:
            return ["lineMatch.eye", "lineMatch.rabbit"]
        case .lineMatchGuidedStraight:
            return ["lineMatch.eye", "lineMatch.hand"]
        case .lineMatchGuidedBridge:
            return ["lineMatch.cat", "lineMatch.rabbit"]
        case .traceLines:
            return ["shapeTrace.lines"]
        case .traceShapesDotted:
            return ["shapeTrace.dotted"]
        case .traceShapesArrows:
            return ["shapeTrace.arrows"]
        case .traceShapesFree:
            return ["shapeTrace.free"]
        case .tapCountAll:
            return ["tapCount.icon.all"]
        case .tapCountTrace:
            return ["tapCount.icon.trace"]
        case .tapCountPick:
            return ["tapCount.icon.pick"]
        case .tapCountAllEnglish:
            return ["tapCount.icon.all"]
        case .tapCountTraceEnglish:
            return ["tapCount.icon.trace"]
        case .tapCountPickEnglish:
            return ["tapCount.icon.pick"]
        case .tapLetterAll:
            return ["tapLetter.icon.all"]
        case .tapLetterWrite:
            return ["tapLetter.icon.write"]
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
    /// v0.22.0 generated variant (level, target look, item id, hint). Nil = fixed v0 item.
    public var variant: FindSameVariant?

    public init(
        promptTraditionalChinese: String,
        promptEnglish: String,
        targetAssetID: String,
        options: [ActivityOption],
        correctOptionID: String,
        completionID: String,
        variant: FindSameVariant? = nil
    ) {
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.targetAssetID = targetAssetID
        self.options = options
        self.correctOptionID = correctOptionID
        self.completionID = completionID
        self.variant = variant
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
        // Exactly one option may look like the target, and no two options may look alike.
        guard hasExactlyOneMatch, Set(options.map(\.assetID)).count == options.count else { return false }
        if let variant, variant.target.assetID != targetAssetID { return false }
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
    /// v0.22.0 generated variant (level, vehicle, layout, item id, hint). Nil = fixed v0 item.
    public var variant: CountVariant?

    public init(
        promptTraditionalChinese: String,
        promptEnglish: String,
        vehicleAssetIDs: [String],
        correctCount: Int,
        choiceCounts: [Int],
        completionID: String,
        variant: CountVariant? = nil
    ) {
        self.promptTraditionalChinese = promptTraditionalChinese
        self.promptEnglish = promptEnglish
        self.vehicleAssetIDs = vehicleAssetIDs
        self.correctCount = correctCount
        self.choiceCounts = choiceCounts
        self.completionID = completionID
        self.variant = variant
    }

    /// Design §7: counts up to 10 (was ≤ 5 while the catalog had one 3-truck item).
    public var isWellFormed: Bool {
        let maxCount = CountVehiclesGenerator.maxCount
        guard !completionID.isEmpty else { return false }
        guard correctCount >= 1, correctCount <= maxCount else { return false }
        guard vehicleAssetIDs.count == correctCount else { return false }
        guard vehicleAssetIDs.allSatisfy({ !$0.isEmpty }) else { return false }
        guard choiceCounts.count >= 2, choiceCounts.count <= 5 else { return false }
        guard Set(choiceCounts).count == choiceCounts.count else { return false }
        guard choiceCounts.contains(correctCount) else { return false }
        guard choiceCounts.allSatisfy({ $0 >= 1 && $0 <= maxCount }) else { return false }
        // 6 and 9 look alike upside down: never both on the numeral cards.
        guard !(choiceCounts.contains(6) && choiceCounts.contains(9)) else { return false }
        return placementsAreClear
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
        .emptyBay,
        .lineMatchGuidedStraight,
        .lineMatchGuidedBridge,
        .lineMatch,
        .traceLines,
        .traceShapesDotted,
        .traceShapesArrows,
        .traceShapesFree,
        .tapCountAll,
        .tapCountTrace,
        .tapCountPick,
        .tapCountAllEnglish,
        .tapCountTraceEnglish,
        .tapCountPickEnglish,
        .tapLetterAll, .tapLetterWrite
    ]

    /// D7 (Carter 2026-10-13, option B): new kinds join no ticket until a parent turns a star on
    /// in 家長 → 遊戲 (after 試玩). They stay playable from the parent catalog.
    public static let defaultOffKinds: [ActivityKind] = [
        .lineMatchGuidedStraight, .lineMatchGuidedBridge, .lineMatch, .traceLines, .traceShapesDotted,
        .traceShapesArrows, .traceShapesFree, .tapCountAll, .tapCountTrace, .tapCountPick,
        .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish, .tapLetterAll, .tapLetterWrite
    ]

    /// Kinds every ticket deals before a parent changes anything (the v0.22 rotation).
    public static var defaultOnKinds: [ActivityKind] {
        playableKinds.filter { !defaultOffKinds.contains($0) }
    }

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
        UnbuiltParentActivity(traditionalChinese: "迷宮", english: "Maze"),
        UnbuiltParentActivity(traditionalChinese: "形狀分類", english: "Shape sort"),
        UnbuiltParentActivity(traditionalChinese: "連點", english: "Connect the dots")
    ]

    /// Deterministic rotation from the round UUID / seed string across the default-on kinds.
    public static func kind(forRoundSeed seed: String) -> ActivityKind {
        kind(forRoundSeed: seed, pool: defaultOnKinds)
    }

    /// Same hash as `kind(forRoundSeed:)`, modulo `pool` only.
    /// Empty pool falls back to the default-on kinds (corrupt / empty star must still deal;
    /// a D7 default-off kind never appears that way).
    public static func kind(forRoundSeed seed: String, pool: [ActivityKind]) -> ActivityKind {
        let kinds = pool.isEmpty ? defaultOnKinds : pool
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

    /// v0.22.0: seeded variant for the ticket's ★ tier (design §7, D1).
    /// The no-argument form below stays the fixed v0 item (old records, tests).
    public static func findSameQuestion(seed: String, level: ActivityLevel,
                                        avoidingItem: String? = nil) -> FindSameQuestion {
        FindTheSameGenerator.make(seed: seed, level: level, avoidingItem: avoidingItem)
    }

    /// v0.22.0: seeded variant for the ticket's ★ tier (design §7, D1).
    public static func countQuestion(seed: String, level: ActivityLevel,
                                     avoidingItem: String? = nil) -> CountQuestion {
        CountVehiclesGenerator.make(seed: seed, level: level, avoidingItem: avoidingItem)
    }

    /// v0.23.0 連一連 (design §6): seeded question for a deal level and the parent's category
    /// weights. v0.24.1: three kinds — guided straight (L1 roads), guided bridge (L2 roads),
    /// free match (mission star level). `mode` `.guided` only at L1/L2; L3 guided falls back to free.
    public static func lineMatchQuestion(seed: String, level: ActivityLevel, avoidingItem: String? = nil,
                                         settings: LineMatchSettings = .defaults,
                                         mode: LineMatchMode = .free) -> LineMatchQuestion {
        LineMatchGenerator.make(seed: seed, level: level, avoidingItem: avoidingItem, settings: settings, mode: mode)
    }

    /// Fixed reference item (placeholder before the first deal; per-kind perf facts).
    public static func lineMatchQuestion() -> LineMatchQuestion {
        LineMatchGenerator.reference
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
        case .lineMatch:
            return "提示：由綠點拉去閃緊嘅字卡。 / Hint: draw from the green dot to the shining word."
        case .lineMatchGuidedStraight, .lineMatchGuidedBridge:
            return LineMatchGuidedCopy.hint
        case .traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree:
            return ShapeTraceCopy.hint
        case .tapCountAll, .tapCountTrace, .tapCountPick:
            return TapCountCopy.hint
        case .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish:
            return TapCountEnglishCopy.hint
        case .tapLetterAll, .tapLetterWrite:
            return "提示：搵一樣嘅字母。 / Hint: look for the same letter."
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
