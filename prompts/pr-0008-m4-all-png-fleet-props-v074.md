# PR #8 — All-PNG child fleet + props v0.7.4

Carter UAT on v0.7.3 tip `701a10c`: direction OK, hero tickets great, BUT geometric
SwiftUI cars still visible in parade strip + find-same (and other dense games via
`VehicleVisualRole.fleet`).

## Change
1. Replace ALL child-visible geometric vehicles with illustrated PNGs matching
   existing hero style (`Resources/Vehicles/hero-*.png`).
2. Generate missing fleet kinds: toy-car, crane, tanker, articulated-bus,
   dino-flatbed (soft cargo, not licensed creature), logistics-truck.
3. Non-car props in same style under `Resources/Props/` — sun/cloud in world
   background; traffic cone/light on parade; garage/stamp/ticket/toolbox bundled
   for future accents. No new activity types.
4. Inspiration only from preschool chunky-toy energy (no IP copy of referenced
   YouTube channel characters; no Tomica/Thomas/Tayo/Iconix).
5. `FriendlyVehicleView` always prefers PNG when present; `.fleet` no longer
   forces procedural geometry. Parade uses full illustrated convoy.
6. Info.plist **0.7.4 / build 23**, footer **v0.7.4**. `bundle.sh` copies Vehicles
   + Props. Keep Trad Chinese + English, shuffle, parent IP disclaimer.
7. Do **not** merge PR #8.

## Mac mini UAT checklist
See PROGRESS tip for the exact checklist.
