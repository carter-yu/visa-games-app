# PR #8 — Storybook faces push + allowlist shuffle play v0.7.2

Carter held v0.7.1: vehicle faces still not cute/natural enough; allowlisted
YouTube always played in fixed `videos.first` order after earning a visa.

## Faces
Push original fleet further toward storybook refs (inspiration only — do not copy
Egypt IP scenes): face IS the front (headlights/boiler/grille), half-lidded sleepy
eyes, soft painterly fills, round toy / chubby proportions. Primary file
`Sources/VisaGames/VehicleSilhouettes.swift`. Keep HK/NY taxi, fire, metro without
roundel, long works. No Tomica/Thomas/Takara/HIT/Mattel likenesses.

## Shuffle
After earning visa / entering scoped playback, pick next allowlisted video with
shuffle (Fisher–Yates deck; reshuffle when exhausted; avoid immediate repeat of
last played when count > 1). Persist shuffle cursor. Pure logic in VisaCore
`VideoPlaybackShuffle`; child path wiring in AppDelegate. Parent preview may keep
explicit id / first. D8 scoped embed / parent allowlist / kiosk unchanged except
play-order. Unit tests in ScopedPlaybackTests (+3 → 12 scoped-playback checks).

## Version / process
Info.plist **0.7.2 / build 21**, shell footer **v0.7.2**. Update PROGRESS briefly.
Do not invent D9/D10. Do not merge PR #8. Language: HK Traditional Chinese + English.
