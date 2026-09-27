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
        expectEqual(ThemePack.forID(.sunnyYellow).parentLabel, "陽光黃 / Sunny Yellow")
        expectEqual(ThemePack.forID(.engineeringOrange).parentLabel, "工程橙 / Engineering Orange")
        expectEqual(ThemePack.forID(.logisticsWhiteRed).parentLabel, "物流白紅 / Logistics White-Red")
        expectEqual(ThemePack.forID(.busBlue).parentLabel, "巴士藍 / Bus Blue")
    }

    func testEveryPaletteIncludesWarmYellowAccent() {
        for palette in ThemePaletteID.allCases {
            let pack = ThemePack.forID(palette)
            // Yellow channel must be warm (high R+G, lower B) for accent use — not a full-screen wall color.
            expectTrue(pack.yellow.red >= 0.90)
            expectTrue(pack.yellow.green >= 0.80)
            expectTrue(pack.yellow.blue <= 0.45)
            // Background stays calming soft blue/green family (blue or green dominate over yellow wall).
            expectTrue(pack.background.blue >= pack.background.red || pack.background.green >= pack.background.red)
        }
    }
}
