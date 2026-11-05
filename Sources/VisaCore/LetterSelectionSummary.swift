import Foundation

/// The letter card's per-game summary (build 80, fix round 1). One pure value for the loaded
/// card and its loading stand-in. Both draw the same rows and one fixed status line, so the
/// warnings that only the loaded capabilities can show (已揀・暫停, find-only, nothing to
/// write) never change the card's height.
public struct LetterSelectionSummary: Equatable, Sendable {
    /// False while the letter cards load: the rows reserve the whole focus set, and the
    /// status line says loading.
    public let resolved: Bool
    public let focus: [String]
    /// Focus letters 翻字卡 can ask (ready to find).
    public let find: [String]
    /// Focus letters 搵完寫 can ask (ready to write).
    public let write: [String]
    /// Ready to find but not to write.
    public let findOnly: [String]
    /// Chosen letters that are not ready at all (已揀・暫停).
    public let unavailable: [String]

    /// Summary chips per row; a row reserves chip rows for the whole focus set.
    public static let chipsPerRow = 13

    public init(focus: [String], capabilities: [String: LetterCapability]) {
        let find = focus.filter { capabilities[$0]?.canFind == true }
        let write = focus.filter { capabilities[$0]?.canWrite == true }
        self.init(resolved: true, focus: focus, find: find, write: write,
                  findOnly: find.filter { !write.contains($0) },
                  unavailable: focus.filter { capabilities[$0]?.canFind != true })
    }

    /// The loading stand-in for the same focus set (capabilities not loaded yet).
    public static func loading(focus: [String]) -> Self {
        Self(resolved: false, focus: focus, find: focus, write: focus, findOnly: [], unavailable: [])
    }

    private init(resolved: Bool, focus: [String], find: [String], write: [String],
                 findOnly: [String], unavailable: [String]) {
        self.resolved = resolved
        self.focus = focus
        self.find = find
        self.write = write
        self.findOnly = findOnly
        self.unavailable = unavailable
    }

    /// 搵完寫 has nothing it can ask (known only once loaded).
    public var writeEmpty: Bool { resolved && write.isEmpty }

    public var hasWarning: Bool { !unavailable.isEmpty || !findOnly.isEmpty || writeEmpty }

    /// Chip rows each summary row reserves. Depends on the focus set only, so it is the same
    /// for the loading stand-in and the loaded card.
    public var chipRows: Int { max(1, (focus.count + Self.chipsPerRow - 1) / Self.chipsPerRow) }

    /// The one status line under the rows: loading, every warning joined, or all clear.
    public var status: LetterPickerMessage {
        guard resolved else { return LetterPickerSaveCheck.loading }
        var zh: [String] = []
        var en: [String] = []
        if !unavailable.isEmpty {
            zh.append("已揀・暫停：\(unavailable.joined(separator: "、"))，儲存之前要移除")
            en.append("Selected · unavailable: \(unavailable.joined(separator: ", ")) — remove before saving")
        }
        if !findOnly.isEmpty {
            zh.append("\(findOnly.joined(separator: "、")) 暫時只可以搵，未可以寫")
            en.append("\(findOnly.joined(separator: ", ")): find only for now")
        }
        if write.isEmpty {
            zh.append("呢組暫時玩唔到『搵完寫』")
            en.append("This set can't play Find & write yet")
        }
        guard !zh.isEmpty else {
            return LetterPickerMessage(zh: "兩個遊戲都可以用呢組字母。", en: "Both letter games can use these letters.")
        }
        return LetterPickerMessage(zh: zh.joined(separator: "；") + "。", en: en.joined(separator: ". ") + ".")
    }
}
