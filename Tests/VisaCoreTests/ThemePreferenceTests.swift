import Foundation
import VisaCore

final class ThemePreferenceTests {
    private func makeDefaults() -> UserDefaults {
        let name = "VisaGames.ThemePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDefaultPalette() {
        let store = ThemePreferenceStore(defaults: makeDefaults())
        expectEqual(store.load(), .engineeringOrange)
    }

    func testSelectEachPalette() {
        let store = ThemePreferenceStore(defaults: makeDefaults())
        for palette in ThemePaletteID.allCases {
            store.save(palette)
            expectEqual(store.load(), palette)
            expectEqual(store.defaults.string(forKey: ThemePreferenceStore.key), palette.rawValue)
        }
        expectEqual(ThemePaletteID.allCases.count, 3)
    }

    func testPersistAndReload() {
        let defaults = makeDefaults()
        ThemePreferenceStore(defaults: defaults).save(.busBlue)
        expectEqual(ThemePreferenceStore(defaults: defaults).load(), .busBlue)
    }

    func testInvalidRawValueFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("unknown-palette", forKey: ThemePreferenceStore.key)
        expectEqual(ThemePreferenceStore(defaults: defaults).load(), .engineeringOrange)
        defaults.set(42, forKey: ThemePreferenceStore.key)
        expectEqual(ThemePreferenceStore(defaults: defaults).load(), .engineeringOrange)
    }

    func testBilingualTraditionalChineseLabels() {
        expectEqual(ThemePack.forID(.engineeringOrange).parentLabel, "工程橙 / Engineering Orange")
        expectEqual(ThemePack.forID(.logisticsWhiteRed).parentLabel, "物流白紅 / Logistics White-Red")
        expectEqual(ThemePack.forID(.busBlue).parentLabel, "巴士藍 / Bus Blue")
    }
}
