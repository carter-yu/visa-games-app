# UI polish v0.16.0 — picker 4×2, watch fill, install + Stampy icon

**Status:** Implemented on branch `feat/ui-polish-picker-watch-install` (2026-10-03 HKT).  
**Language:** Hong Kong Traditional Chinese for new child affordances (「仲有」). No Simplified Chinese.

## Carter locks

1. **Picker:** 4×2 (not 3×2); remove 300u thumbnail cap; compact/floating Stampy HUD so the speech bubble never overlaps cards; use the right-side canvas.
2. **Page affordance:** both giant kid 「仲有」 arrows (≥96×160 artboard units) **and** next-page peek (~15% of the next page’s cards).
3. **Watch:** grow the framed player to fill vertical space (less letterbox) but **keep** framed player + bottom road strip (road is not an overlay on the video).
4. **Install:** after bundle, `ditto` to `/Applications/Visa Games.app` + Desktop alias helper via `scripts/install-mac-mini.sh`.
5. **Stampy AppIcon.icns** in the bundle + `CFBundleIconFile` = `AppIcon`.

## Version

**0.16.0 / build 38.** Parent footer `Visa Games v0.16.0`.

## Out of scope

Merge to main, kiosk launch, passport / D9 recorded voice, policy changes.
