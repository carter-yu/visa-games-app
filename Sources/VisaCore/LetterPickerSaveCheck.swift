import Foundation

/// The letter card / save bar status word (build 78). A corrupt v2 never claims the child
/// plays the previous settings: letter games are suspended until the parent repairs.
public enum LetterPickerStatus {
    /// Build 79: one loading wording (and one ellipsis) for the card, the save check and the bar.
    public static let loadingLetters = "字母卡載入中…"
    public static let loadingLettersEnglish = "Loading letter cards…"

    public static func text(load: LetterSelectionLoad, hasDraft: Bool, hasChanges: Bool) -> String {
        guard hasDraft else { return "載入中…" }
        if load == .corruptV2 {
            return hasChanges ? "未儲存 · 字母遊戲暫停，要修復" : "讀唔到 · 字母遊戲暫停，要修復"
        }
        if hasChanges { return "未儲存" }
        if load.activeSelection != nil { return "已儲存" }
        // Nothing saved yet: the child still plays the previous letter settings.
        return "未儲存 · 而家用緊舊設定"
    }

    /// The English line under `text` (same states, build 79).
    public static func english(load: LetterSelectionLoad, hasDraft: Bool, hasChanges: Bool) -> String {
        guard hasDraft else { return "Loading…" }
        if load == .corruptV2 {
            return hasChanges ? "Unsaved · letter games paused, repair needed"
                : "Can't read · letter games paused, repair needed"
        }
        if hasChanges { return "Unsaved" }
        if load.activeSelection != nil { return "Saved" }
        return "Unsaved · using the previous settings"
    }
}

/// One parent message: the HK Chinese line and its English line (build 80, UX m5).
public struct LetterPickerMessage: Equatable, Sendable {
    public let zh: String
    public let en: String

    public init(zh: String, en: String) { self.zh = zh; self.en = en }
}

/// The parent editor checks the draft before offering Save. Persistence still validates again.
/// Build 80 adds English presentation text only; which reason applies is unchanged.
public struct LetterPickerSaveCheck: Equatable {
    /// HK Chinese block reason; nil means Save is allowed.
    public let reason: String?
    /// The English line for `reason`.
    public let reasonEnglish: String?
    public var canSave: Bool { reason == nil }
    public var message: LetterPickerMessage? {
        reason.map { LetterPickerMessage(zh: $0, en: reasonEnglish ?? "") }
    }

    public init(reason: String?, reasonEnglish: String? = nil) {
        self.reason = reason
        self.reasonEnglish = reasonEnglish
    }

    public init(message: LetterPickerMessage?) {
        self.init(reason: message?.zh, reasonEnglish: message?.en)
    }

    // Fixed parent messages (save bar and notices).
    public static let loading = LetterPickerMessage(zh: LetterPickerStatus.loadingLetters,
                                                    en: LetterPickerStatus.loadingLettersEnglish)
    public static let bankUnavailable = LetterPickerMessage(
        zh: "字母卡讀唔到，暫時儲存唔到。", en: "The letter cards couldn't be read, so Save isn't available.")
    public static let checkFailed = LetterPickerMessage(
        zh: "檢查唔到字母設定，請再試吓。", en: "The letter settings couldn't be checked. Please try again.")
    public static let saved = LetterPickerMessage(zh: "儲存咗，下局開始用。", en: "Saved. Applies next round.")
    public static let saveFailed = LetterPickerMessage(zh: "未儲存到，請再試吓。", en: "Could not save. Please try again.")

    public static func evaluate(_ draft: LetterSelectionSettings,
                                availability: [String: LetterCapability], writingAssigned: Bool,
                                allowedReview: Set<String>, load: LetterSelectionLoad,
                                repairCorruptV2: Bool, bankAvailable: Bool = true) -> Self {
        guard bankAvailable else { return Self(message: bankUnavailable) }
        guard load != .corruptV2 || repairCorruptV2 else {
            return Self(message: message(for: LetterSelectionSettingsStore.StoreError.corruptStored))
        }
        do {
            _ = try draft.validated(availability: availability, writingAssigned: writingAssigned,
                                    allowedReview: allowedReview)
            return Self(reason: nil)
        } catch let error as LetterSelectionSettings.ValidationError {
            return Self(message: message(for: error))
        } catch {
            return Self(message: checkFailed)
        }
    }

    public static func reason(for error: LetterSelectionSettings.ValidationError) -> String {
        message(for: error).zh
    }

    public static func reason(for error: LetterSelectionSettingsStore.StoreError) -> String {
        message(for: error).zh
    }

    public static func message(for error: LetterSelectionSettings.ValidationError) -> LetterPickerMessage {
        switch error {
        case .emptyFocus:
            return LetterPickerMessage(zh: "請最少揀 1 個字母。", en: "Choose at least one letter.")
        case .tooMany:
            return LetterPickerMessage(zh: "最多只可揀 26 個字母。", en: "You can choose up to 26 letters.")
        case .invalidLetter:
            return LetterPickerMessage(zh: "只可揀細階英文字母 a 至 z。", en: "Only lowercase letters a to z can be chosen.")
        case .unavailableFocus:
            return LetterPickerMessage(zh: "有主練字母未開放，請移除先儲存。",
                                       en: "A chosen letter isn't ready yet. Remove it, then save.")
        case .noWriteTargets:
            return LetterPickerMessage(zh: "『搵完寫』已開啟；請揀最少 1 個可寫字母，或者先關咗呢個遊戲。",
                                       en: "Find & write is on: choose at least one letter that can be written, or turn that game off first.")
        case .insufficientBoardLetters:
            return LetterPickerMessage(zh: "呢組字母暫時砌唔到完整遊戲板，請揀其他可用字母。",
                                       en: "These letters can't make a full game board yet. Choose other ready letters.")
        case .invalidReview:
            return LetterPickerMessage(zh: "溫習字母要喺近 90 日練過，而且唔可以同主練重複；請重揀或者關咗溫習。",
                                       en: "Review letters must be practised in the last 90 days and not repeat chosen letters. Choose again or turn review off.")
        case .invalidOrder:
            return LetterPickerMessage(zh: "字母次序無效，請重新揀呢組字母。", en: "The letter order isn't valid. Choose this set again.")
        case .invalidSchema:
            return LetterPickerMessage(zh: "字母設定格式唔啱，請重新開啟設定。",
                                       en: "The letter settings format is wrong. Open the settings again.")
        }
    }

    public static func message(for error: LetterSelectionSettingsStore.StoreError) -> LetterPickerMessage {
        switch error {
        case .notParent:
            return LetterPickerMessage(zh: "請先解鎖家長設定，再儲存字母。", en: "Unlock parent settings before saving letters.")
        case .corruptStored:
            return LetterPickerMessage(zh: "字母設定讀唔到，請先揀「修復字母設定」。",
                                       en: "The letter settings couldn't be read. Choose Repair letter settings first.")
        case .writeFailed:
            return LetterPickerMessage(zh: "儲存失敗；請檢查呢部 Mac 嘅儲存空間，再試吓。",
                                       en: "Saving failed. Check this Mac's storage space, then try again.")
        }
    }
}
