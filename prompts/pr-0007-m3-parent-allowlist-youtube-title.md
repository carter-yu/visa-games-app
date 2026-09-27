# PR #7 — Parent allowlist shows YouTube Title + ID (v0.5.1)

Carter Confirmed (HK Cantonese request): on the parental control YouTube allowlist page, besides YouTube ID there should also be a YouTube Title so it is easier to track what was added.

Branch: `feat/m3-first-learning-loop` @ ~6ea5fec (v0.5.0). Continue PR #7 — do NOT open a new PR, do NOT merge. Do not invent D9 YouTube pack IDs. No Tomica IP. No Simplified Chinese. Linux has no Swift — do not claim `swift test` / `test.sh` PASS.

## Source-verified facts

- `ApprovedVideo` already has `titleEnglish`, `titleCantonese`, and `parentLabel` (falls back to id). Do not invent a third title field.
- Parent UI in `Sources/VisaGames/AppDelegate.swift` (~733–766):
  - TextFields: `parentVideoIDDraft`, `parentVideoDurationDraft`
  - `addAllowlistedVideo()` upserts `ApprovedVideo(id:durationSeconds:)` with **no titles**
  - List row shows only `Text(video.parentLabel)` — so with no title it is ID-only; with title it hides the raw ID
- Carter wants: **Title + ID** visible for tracking. Never hide the ID when a title exists.
- Existing unit test `testApprovedVideoParentLabelAndUpsert` already covers model parentLabel + upsert.

## Product requirements (Confirmed)

1. Parent allowlist add form: add a **YouTube Title** text field with bilingual placeholder Traditional Chinese (HK) + English, e.g. `YouTube 標題 / YouTube Title`.
2. Persist the title on upsert into `ApprovedVideo` using existing fields only.
   - One parent-facing Title draft (`parentVideoTitleDraft`) is enough.
   - If the draft (after trim) contains HK Traditional Chinese / CJK characters, store in `titleCantonese` and leave `titleEnglish` nil (keep simple — do not split bilingual drafts in this slice).
   - Otherwise store in `titleEnglish` and leave `titleCantonese` nil.
   - Empty/whitespace title is allowed: leave both nil (list still shows ID via untitled fallback).
3. List each video showing **both Title and ID**:
   - Primary line = title via existing `parentLabel` when a title exists, OR `"(未命名 / Untitled)"` when both titles are nil (do not show raw id as the primary title line when untitled — show the bilingual Untitled label, and always show id as secondary).
   - Secondary (or same-row secondary style) = video id in monospaced / secondary / caption style.
   - Never hide the ID when a title exists.
4. Clear the title draft after successful add (same as ID draft).
5. Language lock: UI strings Traditional Chinese (HK) + English only. Engineering English. **Never Simplified Chinese.** If a pasted title looks Simplified, still store as parent-typed raw string but do not convert/normalize in this slice.
6. Do NOT auto-fetch titles from YouTube network (offline/kiosk; no new network dependency).
7. Do NOT claim M3 complete; do NOT merge; do NOT invent D9 pack policy.
8. Bump marketing version patch **0.5.0 → 0.5.1** and CFBundleVersion **14 → 15** in `Resources/Info.plist` and ShellView footer `v0.5.1`.
9. Update `PROGRESS.md` briefly (fact-only); this prompt file is the archive under `prompts/` (no secrets).
10. Add/adjust a small unit test if needed that list semantics still hold (untitled vs titled; id always present conceptually). Existing `testApprovedVideoParentLabelAndUpsert` already covers model — extend lightly if helpful (e.g. untitled parentLabel == id; titled never equals empty). Do not break TestRunner wiring.

## Implementation hints

- Add `@Published var parentVideoTitleDraft = ""` next to the other parent drafts on AppModel.
- In `addAllowlistedVideo()`: trim title draft; detect CJK with a simple character check (e.g. Unicode scalars in CJK ranges); pass `titleEnglish` / `titleCantonese` into `ApprovedVideo(...)`; clear `parentVideoTitleDraft` on success.
- List row: VStack(alignment: .leading) with title Text + id Text(.monospaced / .secondary / smaller), keep Play / Remove buttons.
- One writer on AppDelegate for this UI change is fine; keep diff focused.
- Parent emergency Reset / Test 1-min / logs stay unchanged.

## Do NOT

- Fetch YouTube titles over the network.
- Invent D9 pack IDs; Tomica IP; Simplified Chinese UI strings; merge to main; open a new PR.
- Claim Linux swift tests passed.
- Change Snapshot schema / RewardLedger / PlaybackPolicy unless required (should not be).
- Claim M3 complete.

## Docs / commit / push

- Append a short PROGRESS.md entry for 2026-09-27 PR #7 PATCH v0.5.1 parent allowlist Title+ID. Note Linux workshop has no Swift; Mac mini must UAT. Exact next task = Mac mini checklist below. Do not mark M3 done.
- Keep this file at `prompts/pr-0007-m3-parent-allowlist-youtube-title.md`.
- Commit message style: `feat: show YouTube title with id on parent allowlist`
- **Push** to `origin feat/m3-first-learning-loop` so PR #7 updates. Do not merge. Do not open a new PR.

## Done when

- Code + optional small test + docs + prompt archive landed.
- Info.plist 0.5.1 / 15; footer v0.5.1.
- Commit on branch and pushed to origin for PR #7.
- Report tip SHA, version 0.5.1, Mac mini UAT steps in your final message.

## Mac mini UAT (for Carter — do not run here)

1. Pull tip of `feat/m3-first-learning-loop`.
2. `sh scripts/test.sh` then `sh scripts/bundle.sh`.
3. Open app → Parent controls → Allowlist.
4. Add a video **with** a YouTube Title → list shows Title + ID (id never hidden).
5. Add a video **without** title → list shows `(未命名 / Untitled)` + ID.
6. Remove still works; Preview/Play still works; emergency Reset / Test 1-min / logs unchanged.
7. Footer shows **v0.5.1**. Do not merge until Carter OK.

Start by reading `PROGRESS.md`, `Sources/VisaCore/ApprovedVideo.swift`, the parent allowlist section of `Sources/VisaGames/AppDelegate.swift`, `Resources/Info.plist`, and `Tests/VisaCoreTests/ScopedPlaybackTests.swift`. Implement, update PROGRESS + version, commit, push.
