# PR #8 — Option 4 hybrid hero + simple fleet v0.7.3

Carter locked UX direction: **Option 4 — Hybrid hero + simple fleet**
（英雄主角 + 簡車隊）. Sample lock:
`/workspace/visa-games-ux-samples/option-4-hybrid-hero-fleet.png` + STRATEGY.md.

## Visual system
1. **Illustrated hero PNGs** for mission tickets / lock parade leader / success stamp —
   richly faced soft storybook OR preschool-cute original vehicles
   (HK red taxi, NY yellow taxi, HK fire, metro with original stripe **no roundel**).
2. **Simple fleet** for dense games (count / sequence / find-same clutter):
   procedural silhouettes, minimal or no faces — same ToyPaint color language.
3. SwiftUI: `FriendlyVehicleView(role: .hero | .fleet)` prefers `Image` assets for heroes;
   fleet stays procedural. Assets under `Resources/Vehicles/`; `bundle.sh` copies into
   `Contents/Resources/Vehicles/`.
4. Production assets via Codex built-in image_gen — original only.
   NO Tayo / Tomica / Thomas / Iconix likenesses. Strip accidental text/logos.

## Version / process
Info.plist **0.7.3 / build 22**, shell footer **v0.7.3**. Update PROGRESS briefly.
Parent IP disclaimer unchanged. Do not invent D9/D10. Do not merge PR #8.
Language: HK Traditional Chinese + English only.
