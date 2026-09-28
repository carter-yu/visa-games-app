# PR #8 — Parent allowlist YouTube preview thumbnail (v0.6.1)

Carter (from Mac mini): add the preview image to the allowed video — parent allowlist rows should show a YouTube-style preview/thumbnail next to Title + ID.

Branch: `feat/m4-gakken-style-activities` @ ~c65faab (v0.6.0). Continue PR #8 — do NOT open a new PR, do NOT merge. Do not invent D9 YouTube pack IDs. No Tomica IP. No Simplified Chinese. Linux has no Swift — do not claim `swift test` / `test.sh` PASS. M4 not claimed complete.

## Product requirements (Confirmed)

1. Parent allowlist list: show a **preview image** for each allowlisted video (beside Title + ID).
2. Prefer offline-friendly approach:
   - Standard YouTube thumbnail URL pattern `https://img.youtube.com/vi/{VIDEO_ID}/hqdefault.jpg` loaded in SwiftUI AsyncImage — thumbnail CDN only, not full YouTube browse; D8 allowlist playback remains scoped embed.
   - If network fails, show a placeholder (not crash).
3. Do NOT require parent to paste a custom image file; auto thumb from id is the default.
4. Store nothing extra if URL is derived from id; Codable stays backward compatible.
5. Language: HK Traditional Chinese + English UI; never Simplified Chinese.
6. Bump patch version 0.6.0 → 0.6.1 and build number 16 → 17.
7. PROGRESS.md + prompts/ archive; commit + push to PR #8.
8. Linux may lack Swift — note Mac UAT. No merge.

## Implementation

- `YouTubeEmbedURL.thumbnailURL(videoID:)` → hqdefault CDN URL or nil.
- `ApprovedVideo.thumbnailURL` computed (not stored).
- `AllowlistVideoThumbnail` in AppDelegate beside Title + ID; AsyncImage + placeholder.
- Test: `testYouTubeThumbnailURLDerivedFromID`; PASS banner scoped-playback 7 → 8.

## Do NOT

- Require custom image upload; invent D9 pack IDs; Tomica IP; Simplified Chinese; merge; open new PR; claim Linux swift PASS; claim M4 complete.

## Mac mini UAT (for Carter — do not run here)

1. Pull tip of `feat/m4-gakken-style-activities`.
2. `sh scripts/test.sh` (expect 10+10+7+6+8+12) then `sh scripts/bundle.sh`.
3. Open app → Parent → Allowlist.
4. Existing/new allowlisted rows show thumbnail beside Title + ID.
5. If CDN unreachable, placeholder appears (no crash); Play/Remove/Preview still work.
6. Footer shows **v0.6.1**. Do not merge until Carter OK.
