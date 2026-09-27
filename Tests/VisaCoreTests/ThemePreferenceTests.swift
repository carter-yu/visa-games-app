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
        expectEqual(store.load(), .sunnyYellow)
    }

    func testSelectEachPalette() {
        let store = ThemePreferenceStore(defaults: makeDefaults())
        for palette in ThemePaletteID.allCases {
            store.save(palette)
            expectEqual(store.load(), palette)
            expectEqual(store.defaults.string(forKey: ThemePreferenceStore.key), palette.rawValue)
        }
        expectEqual(ThemePaletteID.allCases.count, 4)
    }

    func testPersistAndReload() {
        let defaults = makeDefaults()
        ThemePreferenceStore(defaults: defaults).save(.busBlue)
        expectEqual(ThemePreferenceStore(defaults: defaults).load(), .busBlue)
    }

    func testInvalidRawValueFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("unknown-palette", forKey: ThemePreferenceStore.key)
        expectEqual(ThemePreferenceStore(defaults: defaults).load(), .sunnyYellow)
        defaults.set(42, forKey: ThemePreferenceStore.key)
        expectEqual(ThemePreferenceStore(defaults: defaults).load(), .sunnyYellow)
    }

    func testBilingualTraditionalChineseLabels() {
        expectEqual(ThemePack.forID(.sunnyYellow).parentLabel, "陽光沙地 / Sunny Sand")
        expectEqual(ThemePack.forID(.engineeringOrange).parentLabel, "工程橙沙 / Engineering Ochre")
        expectEqual(ThemePack.forID(.logisticsWhiteRed).parentLabel, "物流紅沙 / Logistics Red Sand")
        expectEqual(ThemePack.forID(.busBlue).parentLabel, "巴士藍沙 / Bus Blue Sand")
    }

    func testEveryPaletteIncludesWarmYellowAccent() {
        for palette in ThemePaletteID.allCases {
            let pack = ThemePack.forID(palette)
            // Yellow channel must be warm (high R+G, lower B) for accent use.
            expectTrue(pack.yellow.red >= 0.90)
            expectTrue(pack.yellow.green >= 0.80)
            expectTrue(pack.yellow.blue <= 0.45)
            // Storybook sand backgrounds are warm ochre (red+green high); sky stays soft blue.
            expectTrue(pack.background.red >= 0.85)
            expectTrue(pack.background.green >= 0.75)
            expectTrue(pack.sky.blue >= pack.sky.red)
            expectTrue(pack.sand.red >= 0.80)
        }
    }
}
