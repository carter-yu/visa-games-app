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

/// The parent editor checks the draft before offering Save. Persistence still validates again.
public struct LetterPickerSaveCheck: Equatable {
    public let reason: String?
    public var canSave: Bool { reason == nil }

    public init(reason: String?) { self.reason = reason }

    public static func evaluate(_ draft: LetterSelectionSettings,
                                availability: [String: LetterCapability], writingAssigned: Bool,
                                allowedReview: Set<String>, load: LetterSelectionLoad,
                                repairCorruptV2: Bool, bankAvailable: Bool = true) -> Self {
        guard bankAvailable else { return Self(reason: "字母卡未能讀取，暫時儲存唔到。") }
        guard load != .corruptV2 || repairCorruptV2 else {
            return Self(reason: reason(for: LetterSelectionSettingsStore.StoreError.corruptStored))
        }
        do {
            _ = try draft.validated(availability: availability, writingAssigned: writingAssigned,
                                    allowedReview: allowedReview)
            return Self(reason: nil)
        } catch let error as LetterSelectionSettings.ValidationError {
            return Self(reason: reason(for: error))
        } catch {
            return Self(reason: "字母設定未能檢查，請再試吓。")
        }
    }

    public static func reason(for error: LetterSelectionSettings.ValidationError) -> String {
        switch error {
        case .emptyFocus: return "請最少揀 1 個字母。"
        case .tooMany: return "最多只可揀 26 個字母。"
        case .invalidLetter: return "只可揀細階英文字母 a 至 z。"
        case .unavailableFocus: return "有主練字母未開放，請移除先儲存。"
        case .noWriteTargets: return "『搵完寫』已開啟；請揀最少 1 個可寫字母，或者先關閉呢個遊戲。"
        case .insufficientBoardLetters: return "呢組字母暫時砌唔到完整遊戲板，請揀其他可用字母。"
        case .invalidReview: return "溫習字母要喺近 90 日練過，而且唔可以同主練重複；請重揀或熄咗溫習。"
        case .invalidOrder: return "字母次序無效，請重新揀呢組字母。"
        case .invalidSchema: return "字母設定格式唔啱，請重新開啟設定。"
        }
    }

    public static func reason(for error: LetterSelectionSettingsStore.StoreError) -> String {
        switch error {
        case .notParent: return "請先解鎖家長設定，再儲存字母。"
        case .corruptStored: return "字母設定讀唔到，請先揀「修復字母設定」。"
        case .writeFailed: return "儲存失敗；請檢查呢部 Mac 嘅儲存空間，再試吓。"
        }
    }
}
