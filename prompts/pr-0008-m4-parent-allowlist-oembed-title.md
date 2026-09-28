# PR #8 — Parent allowlist oEmbed title + preview (v0.6.2)

Carter ask: for allowed videos, extract both **title** and **preview image** from YouTube; explain Duration and why default 120; can duration be extracted too?

Clarification (Mac mini): ideally parent only pastes the YouTube link. Happy path = one URL/id field → Add; auto-fill title + preview; duration auto if possible without API key, else default 120 with optional Advanced override — title/duration not required.

Branch: `feat/m4-gakken-style-activities` @ ~17390d2 (v0.6.1). Continue PR #8 — do NOT open a new PR, do NOT merge. No Tomica IP. No Simplified Chinese. Linux has no Swift — do not claim `swift test` / `test.sh` PASS. M4 not claimed complete. D8 scoped playback unchanged.

## Product requirements (Confirmed)

1. After extracting video id from URL/id paste: fetch **title** via YouTube oEmbed (`https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v={id}&format=json`) — returns title + thumbnail_url; no API key.
2. Preview: keep/use thumbnail (`thumbnail_url` or derived `img.youtube.com/vi/{id}/hqdefault.jpg`). Derived thumb remains the list preview (not persisted).
3. Prefill/save into existing `ApprovedVideo` title fields. Language lock: if title is Simplified Chinese, keep raw as evidence but store for display; prefer HK Trad + English UI labels; do not invent translation.
4. **Duration 120:** `durationSeconds` is for **D4 budget-fit** (PlaybackPolicy / whether video fits remaining viewing bank), NOT live YouTube player length. Default 120 was scaffold when parent only pasted an id — safe short placeholder so upsert succeeds (duration must be > 0).
5. **Duration from YouTube:** oEmbed does not return duration. M4 practical approach: keep editable duration under Advanced; no fragile watch-page/innertube scrape; Data API key is future (do not require Carter to paste a key). Ship title+thumb auto-fill with default 120 + bilingual note.
6. UX: primary paste field only; Title/Duration demoted to Advanced (optional). While fetching show 「正在取得片名… / Fetching title…」. On failure still allow add.
7. Bump 0.6.1 → **0.6.2**, build 17 → 18. Tests for oEmbed URL builder / parsing with fixture JSON (no live network). PROGRESS + this prompt archive.

## Implementation

- `Sources/VisaCore/YouTubeOEmbed.swift` — `requestURL(videoID:)` + `parse(_:)` (Sendable Response: title, thumbnailURL).
- `AppModel.addAllowlistedVideo()` — async oEmbed fetch; Advanced title override wins; duration from Advanced or 120.
- Parent UI: paste field + Add; DisclosureGroup Advanced; duration bilingual hint.
- Test: `testYouTubeOEmbedURLAndParseFixture`; PASS banner scoped-playback 8 → 9.

## Do NOT

- Require API key in chat; scrape watch pages as primary; invent D9 pack IDs; Tomica IP; Simplified Chinese UI/docs; merge; open new PR; claim Linux swift PASS; claim M4 complete; change D8 scoped playback.

## Mac mini UAT (for Carter — do not run here)

1. Pull tip of `feat/m4-gakken-style-activities`.
2. `sh scripts/test.sh` (expect 10+10+7+6+9+12) then `sh scripts/bundle.sh`.
3. Open app → Parent → Allowlist. Footer **v0.6.2**.
4. Paste a YouTube URL only → Add → briefly see Fetching title… → row shows title + thumb + id (duration defaults 120).
5. Paste bare id → same happy path.
6. Disconnect network / bad id handling: invalid id rejected; oEmbed fail still adds (Untitled OK); Advanced can override title/duration.
7. Play / Remove / Preview / Reset still work. Do not merge until Carter OK.
