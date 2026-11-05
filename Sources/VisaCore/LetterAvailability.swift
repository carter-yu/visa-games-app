import Foundation

public struct LetterCapability: Sendable, Equatable {
    public let canDisplay: Bool
    public let canFind: Bool
    public let canWrite: Bool
    public init(canDisplay: Bool, canFind: Bool, canWrite: Bool) {
        self.canDisplay = canDisplay; self.canFind = canFind; self.canWrite = canWrite
    }
    public var reason: String? {
        if !canFind { return "Letter cards are not ready" }
        if !canWrite { return "Writing is not ready" }
        return nil
    }
}

public enum LetterAvailability {
    /// Injected asset facts let future dots be displayed without claiming judge support.
    public struct Assets: Sendable {
        public let display: Bool
        public let trace: Bool
        public let judge: Bool
        public let guide: Bool
        public let mnemonic: Bool
        public init(display: Bool, trace: Bool, judge: Bool, guide: Bool, mnemonic: Bool) {
            self.display = display; self.trace = trace; self.judge = judge
            self.guide = guide; self.mnemonic = mnemonic
        }
    }

    public static func assets(for letter: String) -> Assets {
        guard letter.count == 1, let character = letter.first else {
            return Assets(display: false, trace: false, judge: false, guide: false, mnemonic: false)
        }
        let strokes = LatinGlyphs.strokes(character)
        let paths = LatinGlyphs.paths(character, offset: LineMatchPoint(x: 0, y: 0), scale: 1)
        let drawable = !paths.isEmpty && paths.count == strokes.count && paths.allSatisfy { $0.length > 0 }
        return Assets(display: drawable, trace: drawable, judge: drawable,
                      guide: NumeralGuide(letter: character) != nil,
                      mnemonic: !TapLetterCopy.mnemonic(letter).isEmpty)
    }

    public static func check(letter: String, bank: LetterWordBank, decks: LetterWordDecks,
                             assets supplied: Assets? = nil) -> LetterCapability {
        let assets = supplied ?? assets(for: letter)
        let core = bank.usableWords(letter: letter, box: .learning, decks: decks)
        let canFind = assets.display && Set(core.map(\.id)).count >= 2 && Set(core.map(\.word)).count >= 2
        return LetterCapability(canDisplay: assets.display, canFind: canFind,
                                canWrite: canFind && assets.trace && assets.judge && assets.guide && assets.mnemonic)
    }

    public static func resolve(bank: LetterWordBank, decks: LetterWordDecks) -> [String: LetterCapability] {
        Dictionary(uniqueKeysWithValues: Array("abcdefghijklmnopqrstuvwxyz").map {
            let letter = String($0)
            return (letter, check(letter: letter, bank: bank, decks: decks))
        })
    }

    public static func pickerModel(bank: LetterWordBank, decks: LetterWordDecks,
                                   enabled: Set<String>) -> PracticePickerModel {
        let capabilities = resolve(bank: bank, decks: decks)
        return pickerModel(capabilities: capabilities, enabled: enabled)
    }

    public static func pickerModel(capabilities: [String: LetterCapability],
                                   enabled: Set<String>) -> PracticePickerModel {
        let letters = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)
        let availability = Dictionary(uniqueKeysWithValues: letters.map { letter in
            let cap = capabilities[letter] ?? LetterCapability(canDisplay: false, canFind: false, canWrite: false)
            return (letter, PracticePickerAvailability(consumers: cap.canFind ?
                (cap.canWrite ? ["find", "write"] : ["find"]) : [],
                reason: !cap.canFind ? "字母卡未準備好" : !cap.canWrite ? "未有寫字指引" : nil))
        })
        // Mockup 01: headline = the ready letters, sub-line = "ABC group · 5 letters".
        let presets = ["abcde", "fghij"].map { group in
            PracticePickerPreset(id: group, label: group.map(String.init).joined(separator: " "),
                                 subtitle: "ABC group · \(group.count) letters", listsItems: true,
                                 itemIDs: group.map(String.init))
        }
        return PracticePickerModel(catalogID: "letters.en.lowercase", catalogRevision: "1",
            items: letters.map { PracticePickerItem(id: $0, label: $0, role: .target) },
            availabilityByItem: availability, enabledIDs: enabled, presets: presets, minimum: 1, maximum: 26)
    }
}
