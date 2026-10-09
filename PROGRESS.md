# Progress

- 2026-10-09: PR (pending) MINOR **v0.21.0 / build 44** — D10 **Review**: parent 「表現 / Review」 segment (layout L5, Carter's decisions all A: 5-round minimum, 7-day half-life). Branch `feat/perf-review-v021` from `main` @ 47410fe. Do not merge. No kiosk launch. No child-visible change; no adaptive dealing (v0.22).
  - **VisaCore:** `MasteryEstimator.swift` (decayed Beta–Binomial per kind, pooled prior m̄ clamped 0.2–0.8 / 0.5 below Σw 20, chance-corrected m̂ / m20 / m80, labels 熟手 / 學緊 / 要多練 / 未夠數據, 最近油用晒 flag, 7-day trend, ● ◐ ○ · dots); `VideoAppeal.swift` (expected picks from what was actually drawn on the page, slot model after 30 picks, appeal (O+1)/(E+1), labels 好鍾意 / 間中揀 / 少揀 / 見過未揀過 / 未夠數據 / 未出過; watch outcomes never change a label); `PerformanceReport.swift` (games, videos, paging rate, 4×2 slot map, sessions with exclusions; rollup days only where the raw day file is gone; 30-day / all window, labels always use all kept data).
  - **Rollup schema 2** (`rollup-v1.json`, schema 1 still loads): solved-round active-time histogram, impressions by page, picks per slot, expected picks, picker paging counts. Daily CSVs gain those columns; export adds `games_summary.csv` and `videos_summary.csv` (§5.10).
  - **App:** `ParentReviewView.swift` — 遊戲表現 / 影片表現 tabs, 近 30 日 / 全部, 更新 + 「更新於 HH:mm」, 一眼睇, label rows with a detail panel (掌握度, per-star counts, timings, trend), video header (paging %, 撳邊個位多 map, 冇播放資料 / nav guard counts), 最近玩過 with 唔計呢段 / 計返, empty state 「未有紀錄」 and 未夠數據 · 仲差 n 次. Report built on the recorder queue when the segment opens / 更新 / window change / exclusion; view is `Equatable` + `.equatable()`; plain stacks, full-row buttons, no animation, no I/O in `body`.
  - Version: Info.plist **0.21.0 / 44**, parent footer **Visa Games v0.21.0**.
  - Tests: +19 performance-review (worked examples A–D, §3.5 table, half-life, pooled prior, per-star, trend, exclusion, video labels, appeal vs impressions, paging, watch outcomes, rollup + raw merge, schema-2 rollup, empty + summary CSVs, 35k events, layout source guard) → PASS banner adds **19 performance-review**.

- 2026-10-09: PR #18 (pending) PATCH **v0.20.1 / build 43** — UAT fix: tapping 「進階 / Advanced」 in parent settings did nothing. On macOS a SwiftUI `DisclosureGroup` only toggles from its small chevron (same since v0.12), and the section sits at the bottom of the scroll view. Now a plain full-width button (chevron + 「打開 / 收埋」) that also scrolls the section to the top when opened (`ScrollViewReader`, no animation, no grid). Log line `parent advanced — 進階 open|close`. Source guard test + Info.plist/footer match → **20 performance-log** checks.
- 2026-10-09: PR (pending) MINOR **v0.20.0 / build 42** — D10 performance records, **Record** only (ADR 0008; design approved by Carter 2026-10-09 08:03 HKT, §13 all "A", decision 8 replaced). Branch `feat/perf-record-v020` from `main` @ e35430d. Do not merge. No kiosk launch.
  - **Store:** `~/Library/Application Support/VisaGames/stats/events-YYYY-MM-DD.jsonl` (one file per HKT day, append-only JSONL, envelope v1, sorted keys), `rollup-v1.json` (daily summaries), `exports/`. Separate from `state.json` and from the gitignored repo `logs/` mirror (stats are never written there). Serial utility queue; write errors only raise a parent banner, never `storageFailed`.
  - **Events:** launch / terminate / session; parent enter / leave / 🧪 uat_mode; game_dealt (dealt slots) / answer_attempt (choice, asset, slot, tags, pending before/after, convoy step) / hint_shown / round_result (solved / zeroed / abandoned, first try, misses, active / total / parent ms, mash taps); visa_start / visa_end (earned / parent_test); picker_visit / video_impressions (page ids) / video_pick (page, slot, accepted / refused); resume_offered / resume_used / resume_cleared; video_start (pick / continue / after_parent / parent_preview) / video_progress (60 s) / video_end (stop reason, watched / wall s, completion, resume saved); allowlist_change, config_change, stats_exclude / include / marker, clock_jump.
  - **Stop reasons (verified in code):** ended, visa_expired, budget_exhausted, nav_guard, parent_unlock, preview_stopped, allowlist_removed, storage_reset, storage_failure, app_terminate (+ defensive superseded / unknown) in `video_end.stop_reason`; telemetry full / none; resumed_later yes / no / pending / n/a. No quick / early exit (the child cannot close a video).
  - **Parent tagging:** actors child / parent_uat / parent_test_visa / parent_playtest / parent_preview / parent / system; only child lines in sessions not marked 「唔計呢段」 count. 🧪 家長測試中 switch in 測試同主題 (memory only, auto-off after 60 min, header pill). `grant()` now mints a picker visit (entry `test_visa`).
  - **Retention / clear / export:** raw 90 HKT days incl. today, older days folded into daily summaries then deleted (idempotent, launch, background). 「清除表現紀錄」 (Advanced, confirm) deletes `stats/` only; 「清除簽證及重設儲存」 leaves stats. 「匯出表現 (CSV)」 → `stats/exports/performance-…/` (rounds, videos, video_impressions, daily_games, daily_videos, README) and reveals it in Finder.
  - **UI:** parent only (toggle row, header pill, banner, Advanced 表現紀錄 block). No LazyVGrid edits, no I/O in `body`. `VideoPickerView` gains an optional `onPageShown` callback (no visual change).
  - Version: Info.plist **0.20.0 / 42**, parent footer **Visa Games v0.20.0**.
  - Tests: +19 performance-log → PASS banner adds **19 performance-log** (20 from v0.20.1).

- 2026-10-04: PR (pending) MINOR **v0.19.0 / build 41** — Shuffle the video picker once per visit, and dock 「出發！」 / 「再揀車票」 in one of three parking bays. Branch `feat/shuffle-picker-and-docks` from `main` @ 4058370 (same tree as v0.18.0 `47a8541`). Do not merge. No kiosk launch.

  - **Picker:** `VideoPickerDeck` Fisher–Yates via `ActivityChoiceOrder.shuffled(_:seed:)` on the full allowlist. Pages are 8-card slices (4×2). Empty slots stay at the end of the last page. Seed is in-memory, minted when the route becomes the picker (「出發！」, Resume Choice 「揀片睇」, clip ended with time left, or a child stop that returns to the picker). Not minted in `onAppear` or `body`. A refused pick does not roll the seed. Not `VideoPlaybackShuffle`. Not UserDefaults. 0 videos stays on the empty bay.
  - **Docks:** `BayDock` leading x 72 / 400 / 760, y 560. Departure seed minted in `applyEntrySuccess` when `awaitingDeparture` becomes true. Time's up seed minted when `showTimesUp` becomes true, not from `choiceDealSeed` (cleared by `resetTaskRound()`). First frame is already in the bay. Optional 0.12s scale settle; Reduce Motion skips it. Vehicle still drives off locally (+160). No decoy. Button size unchanged. Right bay + ~380 pair budget ends by x 1140.
  - Version: Info.plist **0.19.0 / 41**, parent footer **Visa Games v0.19.0**.
  - Tests: +2 ux (`testVideoPickerDeckIsStableAndNotAlwaysCatalogOrder`, `testBayDockIsStableAcrossRefreshAndUsesThreeBays`) → PASS banner **13 ux-p2-p3**.
  - **Mac mini toolchain (2026-10-04 00:12 HKT):** `sh scripts/test.sh` → PASS (**13 ux-p2-p3** + full banner); `sh scripts/bundle.sh` → `.build/Visa Games.app` **0.19.0 / 41**; `sh scripts/install-mac-mini.sh` → `/Applications/Visa Games.app` **0.19.0 / 41** + Desktop alias. Not running. No kiosk launch. No merge.


- 2026-10-03: PR (pending) MINOR **v0.18.0 / build 40** — Shuffle choice slots so a position is not the answer. Same branch `feat/parent-settings-games-catalog` (open PR #16). Do not merge. No kiosk launch.
  - **Deal:** `choiceDealSeed` (child round UUID) and `playtestChoiceDealSeed` (new UUID per playtest) are the only stored order state. `ActivityChoiceOrder` / `presented*` is a pure Fisher–Yates of that seed via `SeededGenerator`, so a wrong tap or SwiftUI refresh does not reshuffle. Catalog correct ids / short→long tap order / count value / fuller lot / empty bay id are unchanged.
  - **Kinds:** twoPicture, findSame, count (numeral buttons, not a number line), sequence (all vehicles stay in dealt slots; stimulus is a short→long cue, not the answer row), halfMatch, shapeCousin, capacity (preview uses the same order), moreFewer (lots swap screens; side label follows the screen), shadow, emptyBay (preview uses the same order). Legacy boards take the same seed. Live path is `CanvasActivityHost`, including parent playtest.
  - Version: Info.plist **0.18.0 / 40**, parent footer **Visa Games v0.18.0**.
  - Tests: +1 activity (`testChoiceOrderIsStableAndNotAlwaysCatalog`) → PASS banner **19 activity**.


- 2026-10-03: PR (pending) MINOR **v0.17.0 / build 39** — Parent settings game catalog. Branch `feat/parent-settings-games-catalog` from `main` @ 7547988 (v0.16.0 PR #15). Do not merge; Mac mini toolchain after push. No kiosk launch.
  - **Carter lock (2026-10-03):** chunky segment **影片 | 遊戲** under the test row (test/theme stay pinned; Advanced at the bottom; stale four-game sentence deleted). One card per built `ActivityKind` (10): static art, HK title, ★1/★2/★3 toggles (multi-star). All-off hides the game from missions but it stays playtestable. Last star on a tier cannot turn off (banner「每個星級至少要有一個遊戲」). Unbuilt ADR genres are one muted「未做好」row, not fake cards. Playtest cover keeps `session.mode == .parent`, same child board + zh-HK prompt, no visa/stamp/ledger, **返回家長**, wrong answers local only. Child `selectDifficulty` deals from that star's on-set. UserDefaults beside the allowlist; `resetStorage` does not clear it; missing store = all on.
  - **Code:** `MissionGameAssignment` + store; parent names on `ActivityKind`; `ParentSettingsView` segment + grid; `ParentGameCard`; `ParentPlaytestCover`; `CanvasActivityHost` playtest path does not use `.lock` selectors. Info.plist **0.17.0 / 39**; footer **Visa Games v0.17.0**. Design: `docs/designs/parent-settings-games-catalog.md`.
  - Tests: +10 mission-game-assignment (defaults, multi-star, empty-tier reject, hidden kind, corrupt/missing store, new-kind opt-out, empty-star fallback, rotation inside pool, Trad names, UserDefaults round trip). PASS banner adds **10 mission-game-assignment**.
  - **Mac mini toolchain (2026-10-03 15:16 HKT):** tip `e1344c5` — `sh scripts/test.sh` → PASS (**10 mission-game-assignment** + full banner); `sh scripts/bundle.sh` → `.build/Visa Games.app` **0.17.0 / 39**; `sh scripts/install-mac-mini.sh` → `/Applications/Visa Games.app` **0.17.0 / 39** + Desktop alias `~/Desktop/Visa Games`. Not running. No kiosk launch. No merge. PR https://github.com/carter-yu/visa-games-app/pull/16


- 2026-10-03: PR (pending) MINOR **v0.16.0 / build 38** — UI polish: picker **4×2** + floating Stampy HUD + 「仲有」 arrows + peek; watch vertical fill (framed + road strip); `/Applications` install + Desktop alias; Stampy AppIcon. Branch `feat/ui-polish-picker-watch-install` from `main` @ a314769 (v0.15.0 PR #14). Do not merge; Mac mini toolchain UAT after push.
  - **Carter lock:** (1) picker 4×2, no 300u card cap, compact floating Stampy HUD (bubble never overlaps cards), use right space; (2) giant kid 「仲有」 arrows ≥96×160 **and** ~15% next-page peek; (3) Watch grow player vertically, keep framed player + bottom road strip (not overlay); (4) `scripts/install-mac-mini.sh` dittos `.build/Visa Games.app` → `/Applications/Visa Games.app` + Desktop Finder alias; (5) Stampy `AppIcon.icns` + `CFBundleIconFile`. HK Trad for new child copy. Prefer Opus for UX.
  - **Code:** `VideoPickerView` redesign; `WatchPlaybackView` maxHeight grow; `bundle.sh` copies icns; new `install-mac-mini.sh`; Info.plist **0.16.0 / 38**; parent footer **Visa Games v0.16.0**; ADR 0007 picker row; design note `docs/designs/ui-polish-v016-picker-watch-install.md`.
  - Tests: layout-only — expect existing PASS banner unchanged (VisaCoreChecks). Linux box: no Swift.
  - **Mac mini toolchain (2026-10-03 00:30 HKT):** tip `7c0c8af` — `sh scripts/test.sh` → PASS (**11 ux-p2-p3** + full banner); `sh scripts/bundle.sh` → `.build/Visa Games.app` **0.16.0 / 38** with `AppIcon.icns`; `sh scripts/install-mac-mini.sh` → `/Applications/Visa Games.app` **0.16.0 / 38** + Desktop alias `~/Desktop/Visa Games`. No kiosk launch. No merge. PR https://github.com/carter-yu/visa-games-app/pull/15


- 2026-10-02: PR (pending) MINOR **v0.15.0 / build 37** — **Resume Choice** board after stamp 「出發！」when incomplete cursor exists. Branch `feat/resume-choice-board` from `main` @ ec7574b (v0.14.0 PR #13). Do not merge; Mac mini toolchain UAT after push.
  - **Carter lock (2026-10-02):** mid-video visa stop still → classic **TimesUp** (unchanged). After next mission + stamp 「出發！」: if `IncompletePlayback` offerable → **Resume Choice** (not immediate VideoPicker). **Left** 「繼續睇」→ `continueIncompleteVideo()` (PR #12 seek/`start=`). **Right** 「揀片睇」→ VideoPicker and **clear cursor immediately**. Natural end + time left → picker; v1 YouTube thumbnail still; demote picker mint Continue banner to fallback only; HK Trad only; canvas split left/right dusk Depot family (not bolted green chrome).
  - **Code:** `PlayStageRoute.resumeChoice` + `hasResumeCandidate`; `ResumeChoiceView`; AppModel `pickOtherFromResumeChoice` / voice lines; picker Continue banner only when candidate still present (primary path cleared). IncompletePlaybackPolicy / TimesUp / VideoEndRouting unchanged.
  - Tests: +1 ux route (`testPlayStageRoutesResumeChoiceAfterGoWhenIncomplete`) + Trad copy asserts → PASS banner **11 ux-p2-p3**.
  - Version: Info.plist **0.15.0 / 37**, parent footer **Visa Games v0.15.0**.
  - Design: `docs/designs/mid-video-visa-end-resume-choice.md` (D2 lock override noted).
  - **Mac mini toolchain (2026-10-03 00:02 HKT):** tip `cf881a0` — `sh scripts/test.sh` → PASS (**11 ux-p2-p3**); `sh scripts/bundle.sh` → `.build/Visa Games.app` **0.15.0 / 37**. No kiosk launch. No merge. PR https://github.com/carter-yu/visa-games-app/pull/14


- 2026-10-02: PR (pending) MINOR **v0.14.0 / build 36** — wrong-answer **pending-award shrink** + Think Pause (always on). Branch `feat/wrong-answer-pending-shrink` from `feat/resume-and-visa-tiers` @ fe2d090 (v0.13.0 PR #12 tip; do not merge #12). Do not merge; Mac mini toolchain UAT after push.
  - **Policy (Carter 2026-10-02 lock):** each incorrect → feedback → **halve** pending minutes (whole minutes, floor **0**) → **10s Think Pause** (choices locked; mash ignored). Pending is the chosen 5/10/15 ticket award for this round — **never** banked `viewingSeconds` (D2). When pending hits 0: after pause → Depot (reset round / lock entry), no stamp / no `startPlayVisa`. Correct awards **reduced** pending; ticket stars may stay difficulty-chosen; stamp/watch/road follow earned minutes. Auto-hint after pause when pending > 0 (D7 assisted unchanged). No parent feature flag; parent grant / test-visa bypass untouched.
  - **Code:** `WrongAnswerPolicy` + `WrongAnswerCopy` (VisaCore); AppModel pending / Think Pause / fuel feedback; ActivityBoard fuel gauge + 「停一停，想一想！」 overlay; ADR 0004 gentle-retry → pending shrink; tests for 15/10/5 halve chains, pause duration, 0→depot, reduced award, parent grant, Trad-only copy.
  - Version: Info.plist **0.14.0 / 36**, parent footer **Visa Games v0.14.0**.
  - **Mac mini toolchain (2026-10-02 22:38 HKT):** tip `4ed09f8` — `sh scripts/test.sh` → PASS (+8 wrong-answer-policy); `sh scripts/bundle.sh` → `.build/Visa Games.app` **0.14.0 / 36**. No kiosk launch. No merge.

- 2026-10-02: PR (pending) MINOR **v0.13.0 / build 35** — child-play mid-video **resume** + visa tiers **5 / 10 / 15**. Branch `feat/resume-and-visa-tiers` from `main` @ d83b694 (v0.12.0). Do not merge; Mac mini + TV UAT pending.
  - **Slice A — resume (child play only):** persist `Snapshot.lastIncomplete { videoID, positionSeconds }` when a mid-video stop is visa/budget time-out (not ended, not parent preview, not D8 nav reject). Picker offers **繼續睇** / Continue when that id is still allowlisted; card picks start from 0 and clear the cursor; ended / allowlist remove / storage reset clear it. Embed gains optional `start=` + seekTo; HTML shell polls `getCurrentTime` (~1s) via read-only `visaPlayer` `currentTime` events. Resume must not invent viewing budget (D4). Same allowlisted id only (D8).
  - **Slice B — tiers:** `ChildDifficulty` / `MissionTicket` / `PlayPresentation.stars` / AppModel star→seconds fallbacks: 1★→5 min, 2★→10, 3★→15 (300/600/900s). Docs ADR 0004 D6 + 0007 + ux brief live labels updated. Parent auto-lock 10 min and parent preview 600s extend unchanged.
  - Unchanged: kiosk escape blocking, parent LA, D8 navigation gate, provider viewing-budget metering (still open — positive-budget check + absolute visa expiry only).
  - Tests: Session/Canvas/UX stars + scoped `start=` / `currentTime` / IncompletePlaybackPolicy + Snapshot lastIncomplete round-trip. Linux box: `swift: not found` → no compile/test claim here.
  - Version: Info.plist **0.13.0 / 35**, parent footer **Visa Games v0.13.0**.
  - **Mac mini UAT tip for Carter:**
    1. `git fetch && git checkout feat/resume-and-visa-tiers && git pull`
    2. `sh scripts/test.sh`; `sh scripts/bundle.sh` → `.build/Visa Games.app` at **0.13.0 / 35**
    3. Child: start a video, let visa or budget stop mid-play → TimesUp → new visa → picker shows **繼續睇**; Continue resumes; picking another card clears resume. Parent Preview must not leave a Continue cursor.
    4. Tickets show **5 / 10 / 15 分鐘**.

- 2026-10-01: PR #11 MINOR **v0.12.0 / build 34** — end-of-video flow + parent UX rebuild + quit-crash teardown. Branch `feat/parent-ux-end-video-flow` from `main` @ 511a9b6 (v0.11.6 merge of PR #10). Do not merge; Mac mini + TV UAT pending. Prompt: `prompts/pr-0011-parent-ux-end-video-flow.md`.
  - **Bug A (Carter UAT):** after a ~20 min visa the child picked a ~5 min video; when it ended the UI stayed on the YouTube end / recommendations card while the road still read 「仲有 12 分鐘」. No way to pick another video and no Time's up.
  - **Fix A — detect end:** `YouTubeEmbedURL.make` adds `enablejsapi=1` + `origin=https://www.youtube-nocookie.com`; `embedHTMLString` loads the official IFrame API (`https://www.youtube.com/iframe_api`) and attaches `YT.Player` to the same constructed iframe (`id="visa-player"`). `onStateChange` 0 (plus raw widget `infoDelivery` / `onStateChange` messages from the official embed origin as backup) posts `{event, videoID}` to the read-only `WKScriptMessageHandler` `visaPlayer` (weak proxy; removed in `dismantleNSView`). `ScopedPlayerEvent.parse` (VisaCore) drops other ids; `PlaybackEndLatch` reports one `ended` per load; callback runs on the next main-loop turn. Main-frame navigation rules unchanged (ADR 0003 consequence added).
  - **Fix A — route:** `VideoEndRouting` (VisaCore). `AppModel.handleScopedPlaybackEnded`: child play + visa `endsAt` in the future + viewing budget > 0 → clear `activePlayVideoID` → `VideoPickerView` (same visa; Stampy re-asks 「揀片睇！」). No time left → `finishPlayVisaToTimesUp` → new `Session.endPlayVisa(now:)` → existing visa-ended seam → TimesUp (park and sleep). Parent preview → just stops (「影片播完。 / Video finished.」).
  - **Fix A — stops:** `stopScopedPlayback` in child play now routes `.budgetExhausted` / `.sessionExpired` → TimesUp (was: clear id → picker with a dead budget while the road kept ticking). `.navigationRejected` keeps the v0.11.0 behaviour (back to picker + message). A picker tap refused for budget/visa (e.g. viewing bank reset at midnight) also → TimesUp. `returnFromEmptyAllowlist` uses `endPlayVisa` instead of a far-future tick (same result). Logs: `video ended — 片播完 … route=…`, `video ended → picker`, `visa end → timesUp — 冇時間喇 reason=…`, `playback stop — 停止播放 …`; ScopedPlayer log: `player state=…`, `player ready duration=…`, `player ended → app`, `player api-unavailable`.
  - **Slice B — parent UX:** parent mode routes straight to new `ParentSettingsView.swift` (no longer through `legacyShell`; parent now wins over a pending TimesUp board, which shows again after Return). Canvas palette / fonts / ink outlines / chunky buttons. Primary surface: header + auto-lock pill, status banner, 測試同主題 (Test 1-min visa, Test viewing budget, theme chips), 准許影片 (paste row + live preview card with thumbnail + oEmbed title + id + New / Already-added state before Add; card grid with thumbnail, duration chip, title, 試播 Preview, delete with confirm; inline preview player with Stop). Pinned bottom bar: big 返回 Return, `Visa Games v0.12.0`, small 離開程式 Quit. **Advanced** (folded): entry-games / D9 note, Reset entry activity (child UAT), Open logs folder, Clear visa and reset storage (only when a storage message exists), artwork / licence notice. Title / budget-seconds overrides stay in their own small fold next to the paste row.
  - Paste preview: `ParentAllowlistDraft` (VisaCore) uses the same `extractVideoID`; title fetch debounced 0.35 s through the existing oEmbed path and cached so Add does not refetch. Add enabled for a new valid id; for an already-listed id only when an override is typed (button reads 更新 Update — keeps re-add-to-rename). `addAllowlistedVideo` behaviour otherwise unchanged.
  - Duration chip: `ApprovedVideo.playerDurationSeconds` (optional, display-only; old allowlist JSON still decodes) filled from the player's `getDuration` when a video is previewed or watched. Unknown → `~2:00` from the D4 budget-fit `durationSeconds` (unchanged, still default 120; not used for policy).
  - **Slice C — quit crash (7af69db kept):** IPS `VisaGames-2026-10-01-084331.ips` (v0.11.6/33) EXC_BAD_ACCESS 0x1e in `closure #1 in ShellView.body.getter` during `NSHostingView.layout` on parent quit with a live ScopedPlayer. 7af69db: `prepareForTerminate` (timer, monitors, observers, playback, voice, `contentView = nil`), `ScopedPlayerView.dismantleNSView`, closure instead of method reference in `ShellView.body`. v0.12.0 adds: Quit goes through `AppModel.quitFromParent` (log `quit requested — 家長離開程式`, clears the player, `NSApp.terminate` on the next main-loop turn so the button action returns before teardown); dismantle also pauses media and removes the `visaPlayer` handler; parent view uses explicit closures, not method references.
  - Unchanged: reward minutes 10/20/30, kiosk escape blocking, parent authentication (LocalAuthentication, 10-min auto-lock), D8 allowlist gate, passport / D6 / D9 / D10 (not invented).
  - **Deferred:** parent "pick any designed game to review" (out of scope for this PR). Passport board 6, recorded Cantonese clips (D9), daily-cap ending — unchanged from earlier entries.
  - Tests (VisaCoreChecks): +1 session (`testEndPlayVisaEndsOnlyChildPlay`), +4 scoped-playback (IFrame API shell, event parsing + latch, parent draft status, duration label + legacy decode), +3 ux (video ended → picker / → TimesUp, stop routing) → expect banner **PASS: 11 session + 10 reward-ledger + 7 reward-persistence + 6 theme-preference + 16 scoped-playback + 18 activity + 9 canvas + 4 voice + 4 pen-spark + 9 ux-p2-p3 checks**. Linux box: `swift` not installed → `sh scripts/test.sh` exits 127; no compile or test claim here. Embed shell JS exercised under Node with a stub `YT` / `webkit` (one `ended`, duplicate + foreign-origin messages ignored, script-load error reported).
  - Version: Info.plist **0.12.0 / 34**, parent footer **Visa Games v0.12.0**.
  - **Mac mini UAT checklist:**
    1. `git fetch && git checkout feat/parent-ux-end-video-flow && git pull --ff-only`
    2. `sh scripts/test.sh` → expect the PASS banner above; `sh scripts/bundle.sh` → `.build/Visa Games.app` at **0.12.0 / 34**
    3. Quit any running Visa Games; launch only `/Users/carteryu/my-ai-projects/visa-games-app/.build/Visa Games.app`; parent footer reads **Visa Games v0.12.0**
    4. Parent: paste a YouTube URL → thumbnail + title + id appear **before** Add; Add → card with thumbnail / title / `~2:00` chip / Preview / delete; garbage text → 「認唔到呢條連結」 and Add disabled; pasting an already-listed URL → 「已喺清單」
    5. Parent: 試播 Preview a short video to the end → player closes with 「影片播完。」; card chip now shows the real length (e.g. `5:01`); Stop button also closes the preview
    6. Parent: delete asks to confirm; theme chips switch; Test 1-min visa / Test viewing budget still work; Advanced → Reset entry activity shows its confirmation; Open logs folder opens Finder
    7. Child: game → stamp → 「出發！」 → pick a **short** video, let it end with visa time left → back on the **picker** (not the YouTube end card), Stampy says 「揀片睇！」, road minutes keep counting; pick another → plays
    8. Child: let the visa run out mid-video → TimesUp (dusk park and sleep) → 「再揀車票」 → depot
    9. Optional (budget 0 mid-visa): parent Test 1-min visa with an empty viewing bank → child taps a card → TimesUp instead of a stuck picker
    10. Logs: `~/Library/Logs/VisaGames/` shows `player state=playing`, `player ended → app`, `video ended — 片播完 … route=videoPicker` (or `timesUp`); if `player api-unavailable` appears, end detection did not load — report it
    11. Quit: parent → 離開程式 (with and without a preview playing) → app exits cleanly; log has `quit requested — 家長離開程式` and `terminate — 準備離開`; no new `VisaGames-*.ips` in `~/Library/Logs/DiagnosticReports/`
    12. Kiosk: Escape / Cmd-Q blocked on child screens; parent corner 3 s hold and garage hold on Watch still open the macOS password prompt
    13. PR stays unmerged until Carter reports PASS.

- 2026-10-01: PR #10 PATCH **v0.11.6 / build 33** — VideoPicker board truly centered on TV (no left/down cyan cluster). Branch `feat/ux-p2-p3-activity-watch`. Do not merge.
  - **Bug (Carter UAT Mac mini v0.11.5 / 14aa1a3):** 3×2 grid still shifted LEFT and DOWN — large cyan empty on the right, content low. Screenshot confirmed. Prior fix only added `maxWidth: .infinity` around `LazyVGrid` + `canvasPlaced(x:60,y:168)`; LazyVGrid still shrink-wrapped to intrinsic card width and offset placement pinned the board top-left of the remaining band.
  - **Fix:** drop `LazyVGrid` + `canvasPlaced` offsets for the picker. Full 1280×720 artboard `VStack`: Stampy/ticket header → `Spacer` → equal-width 3×2 `HStack` rows (cards `aspectRatio` fill columns) → `Spacer` → dots/message. Horizontally fills; vertically centers under Stampy in remaining space.
  - Version: Info.plist **0.11.6 / 33**, parent footer **v0.11.6**. Linux box: no Swift — Mac mini test+bundle verifies.
  - **Launch path:** `/Users/carteryu/my-ai-projects/visa-games-app/.build/Visa Games.app` only. Parent footer must read **v0.11.6**. Stamp → 「出發！」 → picker 3×2 centered (no big cyan gutter right / low cluster).
  - Mac mini UAT checklist:
    1. `git fetch && git checkout feat/ux-p2-p3-activity-watch && git pull --ff-only`
    2. `sh scripts/test.sh`; `sh scripts/bundle.sh` → expect **0.11.6 / 33**
    3. Parent footer **v0.11.6**; stamp → Go → picker board centered under Stampy, columns fill width evenly


- 2026-10-01: PR #10 PATCH **v0.11.5 / build 32** — VideoPicker cards centered / fill safe canvas (no left-cluster cyan gutter). Branch `feat/ux-p2-p3-activity-watch`. Do not merge.
  - **Bug (Carter UAT Mac mini v0.11.4):** 3×2 card grid clustered/shrunk to the LEFT with large empty cyan sky on the right; page arrows + dots visible on 1280×720 TV.
  - **Fix:** `pickerBoard` HStack + `LazyVGrid` use `frame(maxWidth: .infinity, alignment: .center)` inside a 1160-wide board placed at x:60; each `VideoPreviewCard` also `maxWidth: .infinity` so flexible columns evenly fill. No more intrinsic-width left cluster.
  - Version: Info.plist **0.11.5 / 32**, parent footer **v0.11.5**. Linux box: no Swift — Mac mini test+bundle verifies.
  - **Launch path:** `/Users/carteryu/my-ai-projects/visa-games-app/.build/Visa Games.app` only. Parent footer must read **v0.11.5**. Stamp → 「出發！」 → picker cards centered across the board (no big cyan gutter on the right).
  - Mac mini UAT checklist:
    1. `git fetch && git checkout feat/ux-p2-p3-activity-watch && git pull --ff-only`
    2. `sh scripts/test.sh`; `sh scripts/bundle.sh` → expect **0.11.5 / 32**
    3. Parent footer **v0.11.5**; stamp → Go → picker 3×2 fills/centers on TV

- 2026-10-01: PR #10 PATCH **v0.11.4 / build 31** — picker Stampy voice silent: accept `yue-HK` Sinji. Branch `feat/ux-p2-p3-activity-watch`. Do not merge.
  - **Bug (Carter):** Stampy bubble 「揀片睇！」 on VideoPicker had no sound (tap + auto-speak).
  - **Root cause:** macOS reports Sinji as BCP-47 `yue-HK`, not `zh-HK`. `CantoneseVoicePicker` only matched `zh-hk` → `picked=none` → `speak` no-op. `say -v ?` still listed Sinji; AVSpeech `speechVoices()` zh-HK filter was empty; `AVSpeechSynthesisVoice(language: "zh-HK")` returns Sinji with `lang=yue-HK`.
  - **Fix:** treat `yue-hk` as HK Cantonese (still reject zh-CN/zh-TW/cmn); language-tag fallback in `SystemSpeechPrompt`; log `voice speak` / `voice skip`; utterance volume 1.0. No Mandarin fallback (ADR 0007).
  - Also on tip: v0.11.3 mid-visa `legacyShell` fix (8769a07).
  - Version: Info.plist **0.11.4 / 31**, parent footer **v0.11.4**.
  - **Launch path:** `/Users/carteryu/my-ai-projects/visa-games-app/.build/Visa Games.app` only (no /Applications copy). Parent footer must read **v0.11.4**. Expect log `voice — … picked=Sinji lang=yue-HK` then `voice speak — … key=play.pickVideo`.


- 2026-10-01: PR #10 PATCH **v0.11.3 / build 30** — mid-visa / cold-start no longer falls through to ADR 0006 `legacyShell`. Branch `feat/ux-p2-p3-activity-watch`. Do not merge; Mac mini + TV UAT pending.
  - **Bug (Carter UAT):** after launching tip `.build` v0.11.2/29 he saw wooden 「簽證車廠 / Visa Depot」, 「簽證時間 … 秒」, yellow 「播放准許影片」, desert + parade — legacy play, not canvas Depot/Stampy/tickets.
  - **Root cause (not wrong binary):** running PID was tip `.build` @ 69698cb. Persisted `endsAt` resumes `Session` into `.play` while in-memory `selectedStars` / `awaitingDeparture` / `activePlayVideoID` are nil. `childOrLegacy` required `selectedMissionTicket` for stamp/picker/watch → **else → legacyShell**. Logs: relaunch `shellAppear` with `branch=play-ready` while visa still running.
  - **Fix:** `PlayPresentation.ticket` / stars-from-award helpers; `recoverPlayPresentationAfterLaunch` restores stars from last 10/20/30 award (else easy) and skips stamp gate; `playCanvasBoard` routes **all** `.play` to canvas Stamp/Picker/Watch/Empty; TimesUp uses resolved ticket; parent 「測試一分鐘簽證」 seeds canvas presentation. `legacyShell` remains for setup/parent only.
  - Version: Info.plist **0.11.3 / 30**, parent footer **v0.11.3**. Linux box: no Swift — Mac mini test+bundle verifies.
  - **Mac mini UAT tip for Carter:**
    1. Quit any running Visa Games
    2. Launch **only** `/Users/carteryu/my-ai-projects/visa-games-app/.build/Visa Games.app` (no /Applications copy found)
    3. Parent footer **v0.11.3**; if mid-visa still in `state.json` → expect **VideoPicker** (canvas), not wooden legacy; after visa ends → TimesUp → Depot (Stampy + tickets)
    4. Fresh path: Depot → game → stamp → 「出發！」 → picker → watch
    5. PR stays unmerged until Carter OKs.


- 2026-10-01: PR #10 PATCH **v0.11.2 / build 29** — macOS 13–compatible `onChange` so Release bundle builds on Mac mini (deployment target stays 13.0). Branch `feat/ux-p2-p3-activity-watch`. Do not merge; Mac mini + TV UAT pending.
  - **Blocker (Mac mini Release):** `VideoPickerView.swift` used `.onChange(of:initial:_:)` (two-parameter closure) which requires macOS 14.0+; product targets arm64-apple-macos13.0. Tests passed; Release bundle failed; stale app left at 0.11.0/27.
  - **Fix:** replace with single-arg `.onChange(of:perform:)` / `{ _ in … }` form (macOS 12+/13). Grep of holiday tip: other `onChange` sites in `StampWatchTimesUpViews` / `ChildFeedback` already use the single-arg form; no other macOS 14+ only APIs found in recent holiday commits. Deployment target unchanged (`Package.swift` `.macOS(.v13)`, Info.plist `LSMinimumSystemVersion` 13.0).
  - Version: Info.plist **0.11.2 / 29**, parent footer **v0.11.2**. Linux box: `swift: not found` → no compile or test claim here; Mac mini test+bundle is the verification.
  - **Mac mini UAT tip for Carter:**
    1. `git fetch && git checkout feat/ux-p2-p3-activity-watch && git pull`
    2. `sh scripts/test.sh`; `sh scripts/bundle.sh` → expect fresh `.build/Visa Games.app` at **0.11.2 / 29**
    3. Parent footer **v0.11.2**; stamp → 「出發！」 → picker still 3×2 full cards
    4. PR stays unmerged until Carter OKs the TV check.


- 2026-10-01: PR #10 PATCH **v0.11.1 / build 28** — Video picker shows the full allowlist on TV (no mid-card clip). Branch `feat/ux-p2-p3-activity-watch`. Do not merge; Mac mini + TV UAT pending.
  - **Bug (Carter UAT screenshot):** horizontal one-row picker showed ~2 full cards + a third cut mid-frame with empty blue sky beside it; `showsIndicators: false` gave no scroll affordance for a ~4yo + Wacom.
  - **Fix:** `VideoPickerView` is now a **3×2 page grid** of chunky cards (thumb ~248×132) inside the 1280×720 safe canvas so **up to six videos are fully visible**. More than six → chunky sunny prev/next arrows + page dots; never clip a card mid-frame with dead space beside it. 「揀片睇！」 / thumbnails / D8 pick path unchanged.
  - Version: Info.plist **0.11.1 / 28**, parent footer **v0.11.1**. Linux box: `swift: not found` → no compile or test claim.
  - **Mac mini UAT tip for Carter:**
    1. `git fetch && git checkout feat/ux-p2-p3-activity-watch && git pull`
    2. `sh scripts/test.sh`; `sh scripts/bundle.sh`; parent footer **v0.11.1**
    3. Stamp → 「出發！」 → picker: with ≤6 allowlisted videos, **every card fully on screen** (no half card, no empty blue strip)
    4. Titles readable (… OK); Stampy still says 「揀片睇！」; tap card → watch that video
    5. With >6 videos: big yellow arrows + dots page through the rest; each page still shows whole cards only
    6. PR stays unmerged until Carter OKs the TV check.


- 2026-09-30: PR #10 MINOR **v0.11.0 / build 27** — Holiday P0 on branch `feat/ux-p2-p3-activity-watch` (on top of `f06ae06`). Do not merge; Mac mini + TV UAT pending.
  - **Carter locks (2026-09-30):**
    1. **Parent on garage (Watch only):** `RoadTimerStrip` stacks an invisible `ParentCornerEntry` (72-unit hit target, `showsMark: false`) on the `GarageGlyph`; 3-second hold → `model.unlock` (unchanged auth); tap does nothing. `ShellView` hides the faint `ParentCornerLayer` only while `WatchPlaybackView` shows; all other child screens keep it.
    2. **Last-minute red glow:** when `progress.almostHome` (≤60s) the road bar gets a tomato/stamp-red border + pulsing glow, the garage glows too; Reduce Motion → steady glow. 「仲有 N 分鐘」 and the almost-home voice unchanged.
    3. **Child picks the video:** `applyEntrySuccess` no longer preselects a shuffled video. New `PlayStageRoute` (VisaCore) drives the play branch: stamp → (Go) → empty allowlist | `VideoPickerView` (allowlist non-empty and nothing picked; one video still shows one card) | `WatchPlaybackView`. Card tap → `AppModel.pickVideo` → existing `playAllowlisted` (D8 gate). Thumbnails via `ApprovedVideo.thumbnailURL` + `AsyncImage`; loading/failure → ticket vehicle art. `SpokenPrompt.pickVideo` 「揀片睇！ / Pick a video!」 spoken 1.2s after picker opens. Logs: `videoPicker open`, `videoPicker pick`, `videoPicker pick rejected`.
  - Behaviour note: if a started video is stopped (navigation rejected) the child returns to the picker instead of an empty watch frame. Shuffle helper remains for the legacy shell only.
  - Tests: +1 check (`testPlayStageRoutesPickerBeforeWatch`) and `pickVideo` in the Traditional-only check → expect PASS **10+10+7+6+12+18+9+4+4+5**. Linux box: `swift: not found` → no compile or test claim here.
  - Version: Info.plist **0.11.0 / 27**, parent footer **v0.11.0**. ADR 0007 §5 amended + two decision rows. Prompt: `prompts/pr-0010-holiday-p0-picker-glow.md`.
  - **Mac mini UAT checklist:**
    1. `git fetch && git checkout feat/ux-p2-p3-activity-watch && git pull`
    2. `sh scripts/test.sh` → expect PASS **10+10+7+6+12+18+9+4+4+5**; `swift build` clean
    3. `sh scripts/bundle.sh`; parent footer **v0.11.0**
    4. Correct answer → stamp → 「出發！」 → picker with one card per allowlisted video (thumbnails online; vehicle art offline); Stampy says 「揀片睇！」
    5. With exactly one allowlisted video the picker still shows its card; with none → empty stage + 「返回車廠」
    6. Tap a card → watch screen plays that video; visa minutes unchanged (10/20/30)
    7. Watch: no faint bottom-right corner; tap on garage does nothing; 3s hold on garage → macOS password prompt
    8. At ≤1 min: road bar + garage glow red and pulse; Reduce Motion on → steady glow; almost-home voice still plays
    9. Parent corner still works on Depot, Activity, Stamp, Picker, Time's up, Empty allowlist; Escape / Cmd-Q blocked
    10. PR stays unmerged until Carter OKs the TV check.
- 2026-09-30: PR #10 MINOR **v0.10.0 / build 26** — UX Phases 2+3: voice-first activities + stamp / road timer / Time's up. Branch `feat/ux-p2-p3-activity-watch` from `feat/ux-p1-canvas-depot` @ `4037f93` (includes Depot P1). Do not merge; Mac mini + TV UAT pending. Opus Pro session limit hit mid-build (~00:58 HKT, reset 02:10); implementation continued on the workshop box against Carter's uploaded canvas boards.
  - **Carter locks used:** auto-hint after 2 misses → assisted (D7); Stampy placeholder kept; reward 10/20/30 + kiosk + parent auth + allowlist/visa accounting unchanged; visa clock still starts on correct answer (presentation-only 「出發！」); HK Trad + English only; Phase 4 passport unlocks / rounds / daily-cap skipped (no invented policy).
  - **P2 Activity (board 2) + feedback (board 7):** `ActivityBoardView` + `ChoiceCardChrome` (hop / wiggle / hint glow, Reduce Motion) + `ConeProgressView`; `CanvasActivityHost` rebuilds all 10 kinds as stimulus panel + ≤3 text-free cards; Stampy bubble auto-plays zh-HK prompt via `SystemSpeechPrompt` (no D9 stub toast); miss counter auto-hints at 2.
  - **P2 empty allowlist:** `EmptyAllowlistView` + return to depot (ends visa, skips Time's up).
  - **P3 Stamp (board 3):** `StampSuccessView` passport spread + confetti + mint 「出發！ Go!」 gate before watch UI.
  - **P3 Watch (board 4):** `WatchPlaybackView` + `RoadTimerStrip` (flag → vehicle → garage; 「仲有 N 分鐘」; garage lights + `almostHome` speak at ≤60s).
  - **P3 Time's up (board 5):** `TimesUpView` dusk park-and-sleep + 「再揀車票 New mission」.
  - VisaCore: `ChildUXProgress` (`ActivityHintPolicy`, `RoadTimerProgress`); SpokenPrompt UX lines (`stamped`, `departGo`, `almostHome`, `timesUpPark`, `emptyAllowlist`, `timesUp(for:)`).
  - Concept boards copied to `docs/concept-canvas-boards/` (01–07). ADR 0007 open table updated (assisted + visa-clock presentation decided).
  - Unchanged: D8 scoped player, shuffle, reward minutes, kiosk escape, parent LA, allowlist accounting.
  - Tests: +4 ux-p2-p3 checks → expect PASS **10+10+7+6+12+18+9+4+4+4**. Linux `swift: not found` → no compile claim here.
  - Version: Info.plist **0.10.0 / 26**, parent footer **v0.10.0**. Prompt: `prompts/pr-0010-ux-p2-p3-activity-watch.md`.
  - **Deferred:** passport board 6 (needs Phase 4 decisions); recorded Cantonese clips (D9 / Phase 5); remaining vehicle vector art beyond taxi/fire/metro/bus; daily-cap ending.
  - **Mac mini UAT checklist:**
    1. `git fetch && git checkout feat/ux-p2-p3-activity-watch && git pull`
    2. `sh scripts/test.sh` → expect PASS **10+10+7+6+12+18+9+4+4+4**
    3. `sh scripts/bundle.sh`; footer **v0.10.0**; fonts still bundled
    4. Depot → ticket → activity looks like board 2 (Stampy bubble, stimulus, 3 cards, cones); prompt speaks on entry / bubble replay
    5. Wrong twice → soft wiggle then hint glow + assisted success; no red X
    6. Correct → stamp passport + 「出發！」; visa already ticking; Go → dark watch + road timer 「仲有 N 分鐘」
    7. At 1 min left: garage lights + almost-home voice; expiry → dusk sleep + 「再揀車票」
    8. Empty allowlist after Go → empty stage + 「返回車廠」
    9. Visas stay 10/20/30; parent corner 3s hold; Escape / Cmd-Q blocked
    10. PR stays unmerged until Carter OKs TV check.
- 2026-09-29: PR #9 MINOR **v0.9.0 / build 25** — UX Phase 1: concept-canvas foundation + Depot home (canvas board 1). Branch `feat/ux-p1-canvas-depot` from `main` @ `e77d8ee`. Do not merge; Mac mini + TV UAT pending.
  - Status correction: PR #8 was squash-merged to `main` on 2026-09-28 16:58 UTC as `e77d8ee`; older entries below that say it "must remain unmerged" predate the merge. No v0.8.0 Mac mini UAT result is recorded here.
  - Carter decisions (2026-09-29 chat): the concept canvas is the child-look source of truth (ADR 0007); base branch `main`; go-ahead for UX Phase 1; font download approved.
  - Phase 0 audit (report only, from source): Easy / Medium / Challenge change only visa minutes. The game comes from a random round seed, each game has one fixed question, and each ticket is one question. The app consumed no hover or tablet-proximity events. Child screens showed a one-tap Parent button and the version.
  - VisaCore: `DesignTokens` (canvas palette; 1280×720 stage fitted inside a 5% TV safe area, backdrop full-bleed), `SVGPathData` (path parser incl. arcs), `CanvasArt` (Stampy, taxi, fire engine, metro, bus, depot scene, star, speaker, parent mark, pen spark), `MissionTicket`, `SpokenPrompt` + `CantoneseVoicePicker` (zh-HK only, no Mandarin fallback), `PenSparkState`.
  - VisaGames: `DesignSystem` (colour tokens, `CanvasStage`, `CanvasFont`, `CanvasText`, `ChunkyButtonStyle`), `VectorArtView`, `DepotHomeView` (board 1 without the passport button), `ParentCornerEntry` (3-second hold → existing parent authentication), `SystemSpeechPrompt` (zh-HK system voice; logs installed zh-HK voices), `PenSparkOverlay` (observe-only monitor; logs proximity and first hover per approach). Removed `DifficultyCardsView`. Legacy activity/play screens lost the Parent button and version and gained the parent corner. Version shown in Parent controls.
  - Fonts: Baloo 2 + Noto Sans HK (SIL OFL 1.1) in `Resources/Fonts/` (+12.6 MB); `bundle.sh` copies them with their licences.
  - Unchanged: kiosk key blocking and presentation, parent authentication, allowlist playback, visa accounting, reward policy (10 / 20 / 30), activity content.
  - Tests: +17 checks → PASS **10+10+7+6+12+18+9+4+4**. The new checks failed to compile before implementation.
  - Verification on the dev MacBook Air (M4, macOS 15.5, Swift 6.1.2, Command Line Tools): `sh scripts/test.sh` PASS; `swift build` without warnings; `sh scripts/bundle.sh` built the app with fonts. The depot was rendered offscreen (ImageRenderer) at 1280×720, 1920×1080 and 1440×900 and compared with canvas board 1. The app was not launched on the MacBook (kiosk). No Mac mini, TV, Wacom or voice result is claimed.
  - ADR `docs/decisions/0007-concept-canvas-child-ux.md`; phase file `phases/phase-5-canvas-ux-rebuild.md`; kiosk checklist N8 + two new rows; brief committed at `docs/ux-rebuild-brief.md`. Prompt: `prompts/pr-0009-ux-p1-canvas-depot.md`.
  - **Mac mini UAT checklist:**
    1. `git fetch && git checkout feat/ux-p1-canvas-depot && git pull`
    2. `sh scripts/test.sh` → expect PASS **10+10+7+6+12+18+9+4+4**
    3. `sh scripts/bundle.sh`; `ls ".build/Visa Games.app/Contents/Resources/Fonts"` → two `.ttf` + two `OFL-*.txt`
    4. Depot on the TV looks like canvas board 1 (sign, Stampy, bubble, three tickets with stars and road tiles); nothing is cut off at the TV edges, including the faint bottom-right corner
    5. Voice: Stampy says 「揀一張車票！」 in Cantonese on arrival; tapping the bubble repeats it. If silent, the log shows `voice — 語音 zh-HK picked=none`: add a Cantonese (Hong Kong) voice in System Settings → Accessibility → Spoken Content
    6. Tickets push down when pressed and start a game; visas stay 10 / 20 / 30
    7. Parent: a tap on the corner does nothing; a 3-second hold opens the macOS password prompt; Parent controls show `Visa Games v0.9.0`; no Parent button or version on child screens
    8. Pen: the glow ring follows the pen while hovering or appears on touch. Logs show `pen proximity` lines and, if hover works, `pen hover observed`. Escape / Cmd-Q / Cmd-Tab stay blocked
    9. Games and video playback still work (legacy look until UX Phases 2–3)
    10. PR #9 stays unmerged until Carter OKs the TV check.

- 2026-09-29: PR #8 MINOR **v0.8.0 / build 24** — Visa Depot workbook-mechanic pack (6 new ActivityKinds). Do not merge; Mac mini UAT pending.
  - Inspiration ONLY from Carter's 6 uploaded preschool workbook pages (half-match, shape cousin, capacity, collage count/more/shadow, inside/outside, empty plate) — **mechanics mapped into original Visa Depot vehicles + props**. No squirrels/bears/fruit art, no Gakken/Play Smart pages/characters/layout IP, no Tomica/Thomas/Tayo.
  - **New playable kinds** (rotate with existing two-picture / find-same / count / sequence → **10** total):
    1. `halfMatch` — left half fire truck → pick matching right half
    2. `shapeCousin` — sun is round → pick round tanker among cone/toolbox/tanker
    3. `capacityCompare` — bus vs taxi who carries more people
    4. `moreFewer` — two parking lots (2 vs 4) tap the fuller lot
    5. `shadowMatch` — metro silhouette → pick colored metro hero
    6. `emptyBay` — three depot bays, tap the empty one
  - VisaCore: question structs + evaluators + catalog factories + bilingual HK Trad/English prompts + hints (never Simplified).
  - VisaGames: `ActivityAssetViews` (silhouette + prop + half-clip + shadow mask) + six activity views; AppModel select* + entryGate switch; success stamp / 10/20/30 / YouTube shuffle / D8 / parent IP disclaimer unchanged.
  - Tests: +6 activity checks → offline banner **10+10+7+6+12+18**. Catalog playableKinds == 10; rotation covers all.
  - Info.plist **0.8.0 / 24**, shell footer **v0.8.0**. Prompt: `prompts/pr-0008-m4-workbook-mechanic-pack-v080.md`.
  - Verification: `git diff --check`. `sh scripts/test.sh` / `bundle.sh` exit 127 (`swift: not found`) on Linux — no Swift compile/test/native visual pass claimed.
  - **Mac mini UAT checklist:**
    1. `git fetch && git checkout feat/m4-gakken-style-activities && git pull`
    2. Confirm tip ≥ this commit; `sh scripts/test.sh` → expect PASS **10+10+7+6+12+18**
    3. `sh scripts/bundle.sh` → footer **v0.8.0**; Vehicles (10) + Props (8) still bundled
    4. Lock depot → pick Easy/Medium/Challenge repeatedly until all **10** games appear (兩圖 / 搵相同 / 數車 / 車隊 / 另一半 / 圓形 / 載人 / 停車場 / 影子 / 空車位)
    5. Each new game: wrong → gentle retry; Hint bilingual; success → stamp + visa 10/20/30 + allowlist shuffle play
    6. Confirm art is Visa Depot heroes/props only — no workbook characters
    7. Parent IP disclaimer still present; child path never Simplified Chinese
    8. PR #8 must remain **unmerged**. D9/D10 open.


- 2026-09-28: PR #8 PATCH **v0.7.4 / build 23** — ALL child UI vehicles → illustrated PNGs + soft props. Do not merge; Mac mini visual UAT pending.
  - Carter UAT on tip `701a10c` / v0.7.3: tickets heroes OK, but parade + find-same still showed old geometric SwiftUI cars (`role: .fleet`). Direction otherwise correct.
  - **Fix:** `FriendlyVehicleView` always prefers bundled hero PNG for every `VehicleKind`; procedural silhouette is missing-asset fallback only. All activity views + parade use `.hero`.
  - **New vehicle PNGs** (Codex image_gen, original only): `hero-toy-car`, `hero-crane`, `hero-tanker`, `hero-articulated-bus`, `hero-dino-flatbed` (soft cargo — not a licensed creature), `hero-logistics-truck`. Existing four heroes kept.
  - **Props** under `Resources/Props/`: sun, cloud (world background), traffic-cone + traffic-light (parade accents); also garage-door, stamp, ticket, toolbox bundled for accents. No new activity types.
  - Inspiration only (chunky toy color/energy) — NO IP copy of referenced YouTube characters; NO Tayo/Tomica/Thomas/Iconix.
  - `bundle.sh` copies `Vehicles/*.png` and `Props/*.png`. Parent IP disclaimer + Trad Chinese/English + allowlist shuffle unchanged.
  - Info.plist **0.7.4 / 23**, shell footer **v0.7.4**. Prompt: `prompts/pr-0008-m4-all-png-fleet-props-v074.md`.
  - Verification: `git diff --check`, plist/version assertions. `sh scripts/test.sh` / `bundle.sh` exit 127 (`swift: not found`) on Linux — no Swift compile/test/native visual pass claimed.
  - **Mac mini UAT checklist:**
    1. `git fetch && git checkout feat/m4-gakken-style-activities && git pull`
    2. `sh scripts/test.sh` → expect PASS **10+10+7+6+12+13**
    3. `sh scripts/bundle.sh` → footer **v0.7.4**; confirm `Contents/Resources/Vehicles/*.png` (10) and `Contents/Resources/Props/*.png` (8)
    4. Lock depot: mission tickets still show illustrated heroes; soft sun/cloud in sky
    5. Parade strip: **no** oval/flat geometric cars — all illustrated PNGs (taxi/fire/metro/crane/tanker/bus/truck/toy/flatbed) + cone/light accents
    6. Find-same / two-picture / count / sequence: **no** geometric vehicles — PNG heroes only
    7. Success stamp still fires; allowlist shuffle + parent disclaimer unchanged
    8. PR #8 must remain **unmerged**. D9/D10 open.

- 2026-09-28: PR #8 PATCH **v0.7.3 / build 22** — Option 4 hybrid hero + simple fleet. Do not merge; Mac mini visual UAT pending.
  - Carter locked Option 4 (英雄主角 + 簡車隊). Illustrated hero PNGs for tickets / parade leader / success stamp; procedural simple fleet (faceless) for dense count/sequence/find-same games. Same ToyPaint color language.
  - Assets (original only, Codex image_gen): `Resources/Vehicles/hero-hk-taxi.png`, `hero-ny-taxi.png`, `hero-fire-engine.png`, `hero-metro-train.png`. Transparent BG; no text/logos/roundels. NO Tayo/Tomica/Thomas/Iconix likenesses.
  - Swift: `VehicleVisualRole` + `VehicleHeroAsset`; `FriendlyVehicleView(role:)` loads hero `NSImage` when present, else procedural. Tickets + success + parade index0 → `.hero`; entry/find-same/count/sequence → `.fleet`. `bundle.sh` copies Vehicles into app Resources.
  - Parent IP disclaimer unchanged (ADR 0006). Language HK Trad + English only.
  - Info.plist **0.7.3 / 22**, shell footer **v0.7.3**. Prompt: `prompts/pr-0008-m4-hybrid-hero-fleet-v073.md`.
  - Verification: `git diff --check`, plist/version assertions. `sh scripts/test.sh` / `bundle.sh` exit 127 (`swift: not found`) on Linux — no Swift compile/test/native visual pass claimed.
  - Next: Mac mini fetch tip of `feat/m4-gakken-style-activities`, `sh scripts/test.sh` (expect **10+10+7+6+12+13**), `sh scripts/bundle.sh`, confirm footer v0.7.3 and `Contents/Resources/Vehicles/*.png` present; visual UAT — tickets show illustrated heroes, dense games show simple fleet, success stamp fire hero, parade leader illustrated. PR #8 must remain unmerged. D9/D10 open.

- 2026-09-27: PR #8 PATCH **v0.7.2 / build 21** — storybook face push + allowlist shuffle play. Do not merge; Mac mini UAT pending.
  - Faces (Codex gpt-6-astra polish on workshop rewrite): front-disc / headlight eyes with heavier sleepy lids, cream sclera, low pupils, soft blush + tiny nostrils where natural; chubbier rounded cabs/noses; warmer fills + soft gradients; faces remain non-interactive. Original HK/NY taxi, fire, metro (no roundel), works fleet only — no Egypt IP scenes copied.
  - Shuffle: new VisaCore `VideoPlaybackShuffle` + UserDefaults cursor store. Child visa success and play-mode allowlist button pick next id via Fisher–Yates deck; reshuffle when exhausted; avoid immediate repeat of `lastPlayedVideoID` when allowlist count > 1. Parent preview still uses explicit row / first. D8 scoped player / allowlist / kiosk otherwise unchanged.
  - Tests: +3 scoped-playback (`testPlaybackShuffleAvoidsImmediateRepeatAndReshuffles`, `testPlaybackShuffleSingleAndEmpty`, `testShuffledDeckAvoidsImmediateFirstRepeat`) → expect PASS banner **10+10+7+6+12+13**.
  - Info.plist **0.7.2 / 21**, shell footer **v0.7.2**. Prompt: `prompts/pr-0008-m4-storybook-faces-shuffle-v072.md`.
  - Verification: `git diff --check`, plist/version assertions and shell syntax checks. `sh scripts/test.sh` / `bundle.sh` exit 127 (`swift: not found`) on Linux — no Swift compile/test/native visual pass claimed.
  - Next: Mac mini fetch tip of `feat/m4-gakken-style-activities`, `sh scripts/test.sh` (expect 10+10+7+6+12+13), `sh scripts/bundle.sh`, footer v0.7.2; visual face UAT + shuffle UAT (2+ allowlisted videos → earn visa twice → different order; exhaust deck → reshuffle without immediate repeat). PR #8 must remain unmerged. D9/D10 open.


- 2026-09-27: PR #8 PATCH **v0.7.1 / build 20** — redesigned original fleet faces after Carter's v0.7.0 feedback. Do not merge; Mac mini visual UAT pending.
  - Removed the floating white face plate. Cab-specific glass eye sockets now use cream whites, low pupils, soft brown outlines and heavier sleepy lids; happy mood widens the small curved hood/bumper smile. Flatbed eyes fit its low headlight zone. Drawing coordinates scale with the vehicle, without a minimum eye size.
  - Added warm silhouette outlines and clipped existing highlights/metro stripe to the vehicle body. All ten kinds retain faces; face overlays remain non-interactive. Games, parent IP disclaimer and ADR 0006 unchanged.
  - Info.plist **0.7.1 / 20**, shell footer **v0.7.1**. Prompt: `prompts/pr-0008-m4-cuter-vehicle-faces-v071.md`.
  - Verification: `git diff --check`, plist/version assertions and shell syntax checks passed. `sh scripts/test.sh` and `sh scripts/bundle.sh` each exited 127 (`swift: not found`) on Linux; no Swift compile/test pass or native visual acceptance claimed. No behavior changes or new unit tests in this drawing-only slice.
  - Next: Mac mini test + bundle, then inspect all fleet faces at game/card/parade sizes and calm/happy/sleepy moods; Carter's visual acceptance remains pending. PR #8 must remain unmerged.

- 2026-09-27: PR #8 MINOR **v0.7.0** — storybook child UX + original recognizable vehicles (HK/NY taxi, fire, metro, works). Do not merge; Mac mini visual UAT pending.
  - World shell: warm sand/ochre `StorybookWorldBackground`, wooden station sign 「簽證車廠」, friendly convoy parade.
  - Difficulty: three mission tickets (的士短程 / 消防車任務 / 地鐵長程) with mascots + ★ + Confirmed 10/20/30 + press bounce.
  - Vehicles: original cute faces; `hkTaxi` / `nyTaxi` / `fireEngine` / `metroTrain` (+ existing long works). No licensed character likenesses; metro uses original blue stripe (no transit roundel).
  - Games: faced bigger taps; find-same HK taxi; count fire trucks; **sequence short→long convoy playable** (4 catalog kinds). Success → visa stamp / ticket punch + park-in.
  - Parent: About/license footer (HK Trad + English) — home educational use; original art; not affiliated with named third-party toy/animation companies. ADR `docs/decisions/0006-storybook-child-ux-original-vehicles.md`.
  - Keep: D8 scoped player, one-paste allowlist + oEmbed, parent LA, kiosk, no Simplified Chinese.
  - Version: Info.plist **0.7.0 / 19**, footer **v0.7.0**. Prompt: `prompts/pr-0008-m4-storybook-child-ux-v070.md`.
  - Linux workshop: `swift: not found` expected — no compile/test claim from Linux. Offline suite conceptually **10+10+7+6+9+13**.
  - Exact next task: Mac mini — fetch tip of `feat/m4-gakken-style-activities`, `sh scripts/test.sh` (expect 10+10+7+6+9+13), `sh scripts/bundle.sh`, visual 4yo UAT (depot shell, tickets, faces, all 4 games, stamp, parent footer). Do not merge until Carter OK. D9/D10 remain open.

- 2026-09-27: PR #8 PATCH **v0.6.2** — parent allowlist paste-URL auto-fills title + preview (oEmbed); duration explained. Do not merge; Mac mini UAT pending.
  - Carter ask: extract title + preview from YouTube; explain Duration / why default 120; can duration come from YouTube? Clarification (Mac mini): happy path = paste URL/id only → Add; title/duration not required.
  - Auto-fetch: `YouTubeOEmbed.requestURL` + `parse` (no API key). Parent Add calls oEmbed; stores title into existing `titleEnglish` / `titleCantonese` (CJK → Cantonese field as raw evidence; no invented translation). Preview remains derived `img.youtube.com/vi/{id}/hqdefault.jpg` (oEmbed thumbnail_url also parsed for completeness). Fetching status: 「正在取得片名… / Fetching title…」. Failure still allows add with id + optional Advanced + thumb-from-id.
  - UX: one primary URL/id field + Add; Title/Duration demoted under DisclosureGroup 「進階（可選） / Advanced (optional)」. Duration is **D4 budget-fit** (not live player length); default **120** scaffold when parent only pasted id (upsert needs > 0). oEmbed does **not** return duration — no fragile watch-page scrape in M4; YouTube Data API key left as future; manual Advanced override kept.
  - Tests: +1 scoped-playback (`testYouTubeOEmbedURLAndParseFixture`, fixture JSON only) → expect PASS banner **10+10+7+6+9+12**.
  - Version: Info.plist **0.6.2 / 18**, footer **v0.6.2**. Prompt: `prompts/pr-0008-m4-parent-allowlist-oembed-title.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here. D8 scoped playback unchanged. M4 not claimed complete.
  - Exact next task: Mac mini — fetch tip of `feat/m4-gakken-style-activities`, `sh scripts/test.sh` (expect 10+10+7+6+9+12), `sh scripts/bundle.sh`, Parent → Allowlist → paste URL only → Add → title+thumb appear; offline oEmbed fail still adds; Advanced optional; footer v0.6.2. Do not merge until Carter OK.


- 2026-09-27: PR #8 PATCH **v0.6.1** — parent allowlist shows YouTube-style preview thumbnail beside Title + ID. Do not merge; Mac mini UAT pending.
  - Carter (Mac mini): add the preview image to the allowed video — parent allowlist rows should show a YouTube-style preview/thumbnail next to Title + ID.
  - Approach (offline-friendly): derive `https://img.youtube.com/vi/{VIDEO_ID}/hqdefault.jpg` from the allowlisted id (`YouTubeEmbedURL.thumbnailURL` + `ApprovedVideo.thumbnailURL`). Nothing extra persisted — Codable allowlist JSON stays backward compatible. No custom image paste required.
  - Parent UI: `AllowlistVideoThumbnail` (SwiftUI `AsyncImage`) beside Title + ID; network failure / invalid id → play-rectangle placeholder (no crash). Still thumbnail CDN only; D8 scoped embed playback unchanged.
  - Tests: +1 scoped-playback (`testYouTubeThumbnailURLDerivedFromID`) → expect PASS banner **10+10+7+6+8+12**.
  - Version: Info.plist **0.6.1 / 17**, footer **v0.6.1**. Prompt: `prompts/pr-0008-m4-parent-allowlist-preview-thumbnail.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here. M4 not claimed complete.
  - Exact next task: Mac mini — fetch tip of `feat/m4-gakken-style-activities`, `sh scripts/test.sh` (expect 10+10+7+6+8+12), `sh scripts/bundle.sh`, Parent → Allowlist → rows show thumb + Title + ID; offline/placeholder if CDN fails; Play/Remove/Preview still work; footer v0.6.1. Do not merge until Carter OK.


- 2026-09-27: PR #8 MINOR **v0.6.0** — M4 Gakken-style activity TYPES (original vehicles). Do not merge; Mac mini UAT pending.
  - Base: main @ `5603845` after merge of PR #7 (v0.5.1). Carter Confirmed M3 UAT good; asked for more games referencing Play Smart wipe-clean **activity genres only**.
  - Research (public product description): tracing lines/letters/numbers/shapes, matching, mazes, puzzles, search-and-find, counting/sorting → kiosk genres: two-picture choose, find-the-same, count-to-N, sequencing, maze-lite, path-trace lite, shape sort, connect-the-dots lite. **No Gakken pages/art/titles/packaging copied.** ADR 0005 + `phases/phase-4-gakken-style-activities.md`.
  - VisaCore: `ActivityKind`, `FindSameQuestion`, `CountQuestion`, `SequenceQuestion` stub (`isPlayable == false`), `ActivityCatalog` rotation by round seed, evaluator overloads. Playable: two-picture (existing crane-vs-bus), find-same (tanker target), count (3 logistics trucks → tap 2/3/4).
  - VisaGames: `FindSameActivityView`, `CountActivityView`, `SequenceActivityStub` TODO; AppModel picks kind after difficulty; ShellView switches gate; same D1/D7 + `startPlayVisa` 10/20/30 path. Parent note updated. Footer **v0.6.0**.
  - Tests: +5 activity checks → expect PASS banner **10+10+7+6+7+12**. Prompt: `prompts/pr-0008-m4-gakken-style-activities.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here.
  - Exact next task: Mac mini — fetch tip, `sh scripts/test.sh`, `sh scripts/bundle.sh`, footer v0.6.0, pick Easy/Medium/Challenge repeatedly until all three games appear (兩圖 / 搵相同 / 數車), wrong/retry/hint, visa 10/20/30, allowlist play, Parent Reset still works. Do not merge until Carter OK. D9/D10 remain open.


- 2026-09-27: PR #7 PATCH **v0.5.1** — parent allowlist shows YouTube Title + ID. Do not merge; Mac mini UAT pending.
  - Carter Confirmed (HK Cantonese): allowlist page should show a YouTube Title beside the ID so parents can track what was added.
  - Parent add form gains `parentVideoTitleDraft` + bilingual 「YouTube 標題 / YouTube Title」 field. Upsert writes into existing `ApprovedVideo.titleCantonese` (if draft has CJK) or `titleEnglish` otherwise; empty title leaves both nil. No YouTube network title fetch.
  - Allowlist rows show primary `parentListTitle` (title or 「(未命名 / Untitled)」) and secondary monospaced video id — id is never hidden when a title exists. Title draft clears on successful add.
  - Model: `ApprovedVideo.hasParentTitle` / `parentListTitle`. Existing `testApprovedVideoParentLabelAndUpsert` extended for untitled list semantics. Expect same PASS banner counts (7 scoped-playback).
  - Version: Info.plist **0.5.1 / 15**, footer **v0.5.1**. Prompt: `prompts/pr-0007-m3-parent-allowlist-youtube-title.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here.
  - Exact next task: Mac mini — pull tip, `sh scripts/test.sh`, `sh scripts/bundle.sh`, Parent → Allowlist → add with title (Title+ID), add without title (Untitled+ID), remove/preview still work, footer v0.5.1. Do not merge until Carter OK. M3 not marked complete.

- 2026-09-27: PR #7 MINOR **v0.5.0** — child difficulty cards → task → visa → scoped playback. Mac mini UAT pending; no merge.
  - Evidence: Carter Confirmed in this task the visa-games reference child flow and **10 / 20 / 30 minutes** (600 / 1200 / 1800 seconds); practical D6 closed for this scaffold. D9 IDs/audio and D10 remain open.
  - Added pure ChildDifficulty mapping and configured lock-only Session.startPlayVisa; parent grant remains parent-only. AppModel keeps round selection/UUID in memory, persists D1 + round-unique D7 reward + visa atomically in existing schema 2, and clears task/hint/retry/video on expiry. Lock cards are independent of the durable D1 completion flag.
  - Play shows visa countdown and existing scoped player through PlaybackPolicy, or bilingual parent-add-video guidance. Existing 1200-second viewing cap remains: Challenge requests 1800 but banks at most 1200, with a 1800-second visa. Existing provider viewing-time accounting is still a follow-up; this slice does not claim full budget metering.
  - Tests added before implementation for mapping, repeated successful rounds despite D1, duplicate rejection, assisted recording/cap, child visa boundaries and expiry; extended persistence check for child visa relaunch. Expected Mac runner: 10 session + 10 reward-ledger + 7 reward-persistence + 6 theme-preference + 7 scoped-playback + 7 activity checks.
  - Version: Info.plist **0.5.0 / 14**, footer **v0.5.0**. Prompt archive: `prompts/pr-0007-m3-difficulty-cards-child-flow.md`. ADR 0004 and Phase 3 updated. Existing OS escape paths remain documented in the Phase 0 kiosk checklist.
  - Linux verification: test and bundle each exited 127 (`swift: not found`); no Swift compile/test/native UAT pass claimed. Plist version assertions, shell syntax, and `git diff --check` passed.
  - Exact next task: Mac mini UAT — run test + bundle, open → 3 cards → pick → two pictures → success → YouTube if allowlisted. Check 10/20/30, wrong/retry, hint/assisted, no-allowlist message, expiry → cards → another success without Reset, parent emergency controls, and existing escape-path checklist. M3 is not marked complete.

- 2026-09-27: PR #7 PATCH **v0.4.3** — restore visible two-picture entry gate (ScrollView collapse regression). Do not merge; Mac mini re-UAT pending.
  - Root cause (Carter confirmed): on **v0.4.1** crane/bus targets visible; after pull to **v0.4.2** (`7bdd592`) they vanished while title + Parent + version remained. `entryGateScroll` wrapped `EntryActivityView` in `ScrollView { … }.frame(maxWidth: .infinity, maxHeight: .infinity)` inside a parent `VStack`; unbounded-height ScrollView often collapses to ~0 flexible height, so the two large silhouettes disappear.
  - Fix: remove collapsing ScrollView; restore **direct** `EntryActivityView` in lock/play via `entryGateContent` (0.4.1 proven path) plus `.frame(minHeight: 480)` so the gate cannot shrink away. Keep good 0.4.2 work: Spacer suppression / compact title when showing entry; Reset always persists incomplete ledger; confirmation under Reset; VisaGamesLog; seedTest without `completeEntry`.
  - Tests: no new unit tests (layout-only). Expect same PASS banner as 0.4.2: 8 session + **10** reward-ledger + 7 reward-persistence + 6 theme-preference + 7 scoped-playback + 7 activity.
  - Version: Info.plist + shell footer **0.4.3** (CFBundleVersion 13). Prompt: `prompts/pr-0007-m3-entry-gate-scrollview-collapse.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here.
  - Exact next task: Mac mini — fetch tip, `sh scripts/test.sh` (expect 8+10+7+6+7+7), `sh scripts/bundle.sh`, confirm footer **v0.4.3**, Parent → Reset entry if needed → Return → two large crane/bus silhouettes again on lock/play. Do not merge until Carter OK.


- 2026-09-27: PR #7 PATCH **v0.4.2** — lock entry gate visible + parent Reset persists nil reward + VisaGamesLog. Do not merge; Mac mini re-UAT pending.
  - Root cause (code evidence): (1) **Layout** — `ShellView` had `Spacer()` above and below the mode switch; large `EntryActivityView` (two ~280×220 targets) was compressed/clipped so lock looked like title + 先做再玩 + Parent + version only (「冇 game」). Completed-entry short text still fit (earlier 「入口活動完成」 screenshot). (2) **Reset no-op** — `resetEntryActivityForChildUAT` used `guard let reward else { return }`, so nil reward never persisted and left inconsistent state. (3) **No entry/reset logs** — only ScopedPlayer logs existed, so Reset produced no new lines.
  - Fix: suppress competing Spacers when showing entry gate; wrap `EntryActivityView` in `ScrollView` + `layoutPriority(1)`; compact play-mode visa strip while entry incomplete; parade/success `allowsHitTesting(false)`. Reset always ensures ledger with `entryActivityCompleted=false` (create 60/1200 if nil) and persists; immediate `playbackMessage` under Reset button; `objectWillChange.send()`. Added `VisaGamesLog` → `visa-games-YYYYMMDD.log` (Library + repo `logs/`).
  - Tests: +1 reward-ledger (`testNilRewardMeansEntryIncompleteAndFreshLedgerPersistsFlagFalse`). Expect PASS: 8 session + **10** reward-ledger + 7 reward-persistence + 6 theme-preference + 7 scoped-playback + 7 activity.
  - Version: Info.plist + shell footer **0.4.2** (CFBundleVersion 12). Prompt: `prompts/pr-0007-m3-entry-gate-layout-reset-logs.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here.
  - Exact next task: Mac mini — fetch tip, `sh scripts/test.sh` (expect 8+10+7+6+7+7), `sh scripts/bundle.sh`, Parent → Reset entry (see confirmation) → Return → two large silhouettes on lock/play; open logs folder and confirm `visa-games-*.log` lines. Do not merge until Carter OK.


- 2026-09-27: PR #7 PATCH **v0.4.1** — parent Test viewing budget / Preview no longer completes entry activity (child UAT unblock). Do not merge; Mac mini re-UAT pending.
  - Bug (Carter screenshot): `seedTestViewingBudget()` called `completeEntryActivity`, so lock showed 「入口活動完成 / Entry activity done」 and hid the two-picture game.
  - Fix: seed grants ~60s only via `applyCompletion(id: "parent-test-budget", .unassisted)` when budget ≤ 0; creates RewardLedger(60/1200) if no reward state; **leaves `entryActivityCompleted == false`**. Added `RewardLedger.resetEntryActivityForParentUAT()` + parent button 「重設入口活動（兒童 UAT）/ Reset entry activity (child UAT)」 (clears entry flag + UI hint/retry; keeps viewing seconds).
  - Tests: +1 reward-ledger check (`testResetEntryActivityForParentUATClearsFlagOnly`). Expect PASS: 8 session + **9** reward-ledger + 7 reward-persistence + 6 theme-preference + 7 scoped-playback + 7 activity.
  - Version: Info.plist + shell footer **0.4.1** (CFBundleVersion 11). Prompt: `prompts/pr-0007-m3-parent-test-budget-entry-gate.md`.
  - Linux workshop: `swift: not found` expected — no Swift compile/test/bundle claimed here.
  - Exact next task: Mac mini — fetch/pull branch tip, `sh scripts/test.sh` (expect 8+9+7+6+7+7), `sh scripts/bundle.sh`, Parent → Reset entry activity if needed → Return → confirm two-picture on lock; Parent Preview must not hide entry game. Do not merge until Carter OK.

- 2026-09-27: M3 first learning loop scaffold on `feat/m3-first-learning-loop` as **v0.4.0** (MINOR — family-visible two-picture entry gate); Do not merge; Mac mini verification pending.
  - Base: `origin/main` @ `53e5f29` (PR #6 M2 merged; Carter: play works; UI polish deferred). ADR 0002 D1–D5/D7 Confirmed; D8 Confirmed; **D6/D9/D10 still open**.
  - Docs: `docs/decisions/0004-first-learning-loop-m3.md`; `phases/phase-3-first-learning-loop.md`. States scaffold vs open D9 (pack/audio), D6, D10. No unverified YouTube IDs hardcoded as approved pack.
  - VisaCore: `Activity.swift` — `TwoPictureQuestion`, `ActivityOption`, `ActivityEvaluator`, `FirstEntryActivity` (crane vs articulated bus silhouette asset IDs), `ActivityAudioPrompting` + `StubActivityAudioPrompt` (scaffold only; not “audio done”).
  - VisaGames: lock-mode “activities coming later” replaced with large-target `EntryActivityView`; play mode gates video until entry completion (先做再玩). Success → `completeEntryActivity` + `applyCompletion` (stable completion ID, assisted if hint used, zero extra seconds). Wrong → gentle retry. SuccessParkAnimation reused. Parent note: entry game live; YouTube pack still D9.
  - Tests: `ActivityTests` (7) wired into VisaCoreChecks. Expect PASS: 8+8+7+6+7+**7**.
  - Version: Info.plist + shell footer **0.4.0** (CFBundleVersion 10). Prompt archive `prompts/pr-0007-m3-first-learning-loop.md`.
  - Linux workshop: `swift: not found` expected. No Swift compile/test/bundle claimed here. Mac mini must run test + bundle + Wacom UAT before merge.
  - Exact next task: Mac mini — fetch branch, `sh scripts/test.sh` (expect 8+8+7+6+7+7), `sh scripts/bundle.sh`, child entry UAT, parent visa+allowlist after entry; confirm D9 still open. Do not invent pack IDs.

- 2026-09-17: Created `visa-games-app` bootstrap plan as a native macOS successor to `visa-games`.
  - Product invariants preserved: Visa Games / 簽證遊戲, 先做再玩, pen + finger child path, Cantonese + English UI, no Simplified Chinese, parent-controlled approved content, absolute visa expiry timestamp.
  - Architecture reset: Swift + SwiftUI/AppKit target; browser fullscreen is no longer treated as the kiosk boundary.
  - ADR 0001 defines the app-vs-OS security boundary.
  - Phase 0 is intentionally limited to native shell, persistence, timer, parent boundary, and escape-path testing.
  - No child game tasks or media provider integration yet.

- 2026-09-18: Implemented Phase 0 native shell v0.1.0; target-device acceptance remains pending.
  - Added a dependency-free Swift package with a SwiftUI view hosted in one borderless AppKit window, child presentation options, local key filtering, and a parent-only quit action.
  - Added setup/lock/parent/play state, absolute `endsAt` expiry, atomic versioned JSON persistence, relaunch normalization, and fail-closed storage error handling with authenticated reset.
  - Parent controls use macOS device-owner authentication; parent access is not persisted and closes on a two-minute deadline, sleep, or loss of app activation.
  - Added visible bilingual branding and v0.1.0, a parent-only one-minute visa test, and a playback placeholder. No game tasks, browser, or media integration were added.
  - Initial `swift test` could not run because the installed Command Line Tools lack XCTest. The offline test entry point is now `sh scripts/test.sh`, using a dependency-free Swift executable.
  - Verified debug build and seven offline checks for setup/authentication gating, grants, expiry, relaunch, parent round trips, invalid data, persistence, and escape-key/exit policy. The new key-policy check failed to compile before implementation and passed afterward.
  - Verified release build, plist syntax, shell script syntax, and local ad-hoc signature of `.build/Visa Games.app` on the development host (Swift 6.1.2, arm64 macOS).
  - Added build/run instructions and `docs/phase-0-kiosk-checklist.md`, including OS escape paths and an explicit pending target Mac mini + TV acceptance record. Native GUI, system authentication, sleep/wake, and OS shortcut behavior have not been manually verified.
  - N1–N9 are not yet all green. Phase 0 remains the current phase; child tasks and media work must wait for target-device verification.

- 2026-09-18: User reported seeing the countdown and locked screen during a manual run and approved committing and pushing the implementation.
  - Device/display configuration was not specified. Relaunch behavior and the full target-device escape-path checklist remain unverified manually.

- 2026-09-18: Changed the GitHub repository to public at the user's request and added prominent README implementation credit to OpenAI GPT-6 Astra LLM through Codex, with product direction and manual verification credited to Carter Yu.
  - Debug build and all seven offline checks passed. This documentation update does not change app behavior or the v0.1.0 version.

- 2026-09-26: Reconciled Phase 0 / M0 status on the Linux workshop host.
  - Starting commit: `824e4d1`; branch: `chore/m0-status-reconcile`; working tree was clean before this documentation-only update.
  - Phase 0 remains active and acceptance is incomplete. The target Mac mini + TV checklist has no recorded target observations; Wacom input, system authentication, sleep/wake, and N1–N9 acceptance remain unverified on the target. The earlier countdown/lock report does not identify its device configuration.
  - `docs/project-plan.md` is absent. ADR 0001 is the only recorded ADR; no D1–D10 decisions are recorded. This update approves no proposed policy and changes no app behavior, dependencies, UI, or v0.1.0 version.
  - Verification blocker: `sh scripts/test.sh` exited 127 with `swift: not found` on Linux. No current Swift test or build success is claimed. The app shell was not touched; macOS bundling was not run on this host.
  - The smallest permitted follow-up is target-device Phase 0 evidence collection. Child tasks and media integration remain gated by the active phase's N1–N9 stop condition.
  - Exact next task: run `sh scripts/test.sh` and `sh scripts/bundle.sh` on the target Mac mini, then record the tester, macOS/TV/Wacom/account configuration and actual outcomes in `docs/phase-0-kiosk-checklist.md`, including parent authentication, sleep/wake, relaunch, and OS escape paths. Completion is blocked on access to that target configuration and its observations.

- 2026-09-26: Mac mini toolchain green + Carter Reported N1–N9 Pass + Wacom usable; Phase 0 M0 acceptance recorded as Reported.
  - Parent explicit decision (2026-09-26 chat): “N1-N9 all ok. i can use wacom in the app / merge and proceed”. Evidence label: Reported (Carter Yu), not Confirmed lab instrumentation. This overrides the standing line that said not to mark N1–N9 complete for this documentation slice only.
  - Target path: `/Users/carteryu/my-ai-projects/visa-games-app` @ `chore/m0-status-reconcile` / `45ef1dc`. Xcode 27.0 Build 27A266a; Swift 6.4; `xctest` present. `sh scripts/test.sh` → PASS (7 state, timer, authentication-boundary and persistence tests). `sh scripts/bundle.sh` → Built `.build/Visa Games.app`. `open ".build/Visa Games.app"` succeeded. Wacom input usable in the app (Reported).
  - Mac model, exact macOS marketing name, TV model, account name, and hot-corner inventory: Not specified by tester. Automated checks still do not simulate AppKit/LA; household managed-device caveats remain in `docs/phase-0-kiosk-checklist.md`.
  - Documentation-only update on branch `chore/m0-status-reconcile`. No Swift sources, version number, or app behavior changed. Do not invent Phase 1 timer or reward policy.
  - Exact next task: After this Reported M0 acceptance docs land and parent merges via `gh`, open or update the phase file / D decisions needed before child tasks or media work; child tasks and media remain gated until those Phase 1 decisions exist — do not invent Phase 1 policy.

- 2026-09-27: Phase 1 M1 durable gating/rewards starting policy confirmed by Carter Yu.
  - M0 is recorded as Reported at main commit `7c18c65`.
  - D1–D5 and D7 are Confirmed in `docs/decisions/0002-reward-gating-d1-d7.md`; D6, D8, D9, and D10 remain open.
  - Added `phases/phase-1-gating-rewards.md` with the M1 scope, stop condition, P1-0 through P1-4 slices, and exit evidence.
  - Next task: P1-1 reward model + tests. Do not add YouTube or mark M2/media integration done.

- 2026-09-27: P1-1 in-memory reward model + VisaCoreChecks tests (Linux workshop; Swift not available here).
  - Branch: `feat/p1-1-reward-model`. Added `Sources/VisaCore/RewardLedger.swift` (`RewardPolicy`, `RewardLedger`, `SuccessKind`, `SuccessRecord`, `RewardApplyOutcome`) and `Tests/VisaCoreTests/RewardLedgerTests.swift`; wired eight reward checks into `VisaCoreChecks` via `SessionTests.swift` TestRunner. `Session.swift` / `Snapshot.endsAt` left unchanged.
  - Implements ADR 0002 Confirmed D1 (entry activity unlocks parent-configured initial allowance), D2 (answering does not spend viewing budget), D3 (exactly-once per completion ID, parent-set cap, no next-day carryover via injected Calendar day), D7 (language replay unpenalized; assisted vs unassisted recorded separately). Viewing budget kept separate from absolute session deadline. No YouTube/media/UI; no schemaVersion/persistence change (P1-2); D6 not invented; M1 / Mac mini UAT not marked complete.
  - Verification blocker on this host: `swift: not found`. Mac mini must run `sh scripts/test.sh` (expects PASS: 7 session checks + 8 reward-ledger checks).
  - Exact next task: P1-2 durable gating and session accounting — persist reward/allowance state atomically with the existing local state boundary, keep answering time separate from viewing budget, enforce absolute session deadline independently, normalize stale/expired state on relaunch/wake/clock changes, and add failure-path tests for invalid/duplicated/capped/partially written state.

- 2026-09-27: P1-2 durable reward persistence with Snapshot (Linux workshop; Swift not available here).
  - Branch: `feat/p1-2-reward-persistence`. Bumped `Snapshot.schemaVersion` 1 → 2 with in-memory v1→v2 migration (preserves `configured`/`endsAt`; does not invent reward/allowance). Added `RewardState` and `RewardLedger` export/import + `normalizeAfterLoad` (day-boundary clear without new allowance or policy reset). `SnapshotStore` validates reward fields and fails closed on unsupported schema, corrupt JSON, negative/non-finite values, empty completion IDs, and partial payloads. Absolute `endsAt` remains independent of viewing budget; answering remains a no-op on budget.
  - Tests: `Tests/VisaCoreTests/RewardPersistenceTests.swift` adds seven checks (round-trip, duplicate-after-relaunch, day-carryover-after-reload, endsAt independence, v1 migration, invalid/partial fail-closed, answering-after-reload). Existing 7 session + 8 reward-ledger checks retained.
  - No UI / YouTube / AppKit / skin changes. D6 not invented. M1 / Mac mini UAT not marked complete.
  - Verification blocker on this host: `swift: not found`. Mac mini must run `sh scripts/test.sh` (expects PASS: 7 session + 8 reward-ledger + 7 reward-persistence checks).
  - Exact next task: P1-3 budget-aware approved-video boundary (parent-approved videos with duration/budget-fit; stop at budget boundary; ADR 0002 pause/buffering/ad/seek/sleep/timezone via deterministic playback seam; no provider integration).

- 2026-09-27: Implemented the theme-long-vehicles overnight slice on `feat/theme-long-vehicles` as v0.2.0 source; Mac mini verification is pending.
  - Added three Foundation-only `ThemePack` palettes and a `ThemePreferenceStore` using `VisaGames.themePaletteID` in UserDefaults. The authenticated parent view selects the palette; `Snapshot`, `RewardLedger`, and visa/session semantics were not changed.
  - Added five original SwiftUI vehicle silhouettes in a slow, low-opacity lock/play parade. A lock-mode demo tap calls `AppModel.triggerSuccessFeedback()` and shows a short park-in animation; no activity engine or reward grant was connected by this visual slice.
  - Added five theme-preference checks to the offline runner alongside the existing seven session, eight reward-ledger, and seven reward-persistence checks. Updated the bundle version to 0.2.0. `git diff --check`, plist parsing, and shell syntax checks passed on the Linux workshop host.
  - This Linux workshop has no Swift: `sh scripts/test.sh` and `sh scripts/bundle.sh` both exited 127 with `swift: not found`. No Swift compile, test pass, native launch, or visual UAT is claimed here. M1 completion is not claimed.
  - Existing macOS OS-level escape paths remain as documented in `docs/phase-0-kiosk-checklist.md`; app presentation and key filtering do not replace device policy.
  - Exact next task: morning Mac mini checklist — run `sh scripts/test.sh` and confirm 7 + 8 + 7 + 5 checks; run `sh scripts/bundle.sh` and launch the app; visually check all three parent-only palettes persist across relaunch, the five silhouettes move subtly only in lock/play, and the lock demo parks then clears in about two seconds. Recheck parent authentication, Escape/Cmd shortcuts, display edges, and system OS escape paths on the target setup; record actual outcomes before any M1 claim.

- 2026-09-27: Rebased `feat/theme-long-vehicles` onto main after PR #4 merge (`46f77b9`) and polished yellow-accent UI for ~age-4 attractiveness as v0.2.1 (PATCH); Mac mini verification still pending. Do not merge.
  - Resolved rebase conflicts in `PROGRESS.md` and `SessionTests.swift` TestRunner by keeping P1-2 reward-persistence checks and theme checks together (expect PASS: 7 + 8 + 7 + 6).
  - Added default palette `sunnyYellow` (陽光黃 / Sunny Yellow). All four palettes now carry a dedicated warm `yellow` highlight channel; Engineering Orange warmed; Logistics White-Red and Bus Blue keep identity with yellow button/sparkle highlights. Large backgrounds stay calming soft blue/green — yellow is accents only (buttons, vehicle stripe, soft sun/road stripes, success sparkles), not full-screen walls.
  - Watermark parade: subtle bob/bounce plus small yellow accent stripes on silhouettes; still low opacity / child lock+play only. Park-in success: larger truck (~320pt), soft spring bounce, brief yellow sparkle dots; clear still ~1.8s via `triggerSuccessFeedback`. Rounder / larger TV-readable type and friendlier spacing in `ShellView`.
  - Theme preference tests extended (default → sunnyYellow; allCases count 4; bilingual labels; new yellow-accent invariant). Silhouettes unchanged (crane/tanker/bus/dino flatbed/logistics); no Tomica/Takara/Thomas trademarks, logos, faces, or names. HK Traditional Chinese + English only. Snapshot / RewardLedger / reward policy untouched.
  - Verification blocker on this host: `swift: not found`. No Swift compile, test pass, native launch, or visual UAT claimed here. M1 completion not claimed.
  - Exact next task: Mac mini — `git fetch && git checkout feat/theme-long-vehicles && git pull` (or reset to pushed SHA), `sh scripts/test.sh` (expect 7+8+7+6), `sh scripts/bundle.sh`, launch app; visually check Sunny Yellow default + three other palettes, yellow accents without bedroom-yellow walls, playful parade bob, delightful park-in; record outcomes. Do not merge until parent UAT.

- 2026-09-27: Added top-level `prompts/` archive on `feat/theme-long-vehicles` for English Codex/manager prompts used per PR (README + pr-0001…0005). Sanitized; no secrets; engineering English; no Simplified Chinese. Does not change app behavior.

- 2026-09-27: M2 scoped player scaffold (D8) on `feat/m2-scoped-player-scaffold` as **v0.3.0** (MINOR — family-visible ScopedPlayerView stub); Do not merge; Mac mini verification pending.
  - Base: `origin/main` @ `cfc05d4` (PR #5 theme merged). Parent Confirmed D8 (1+4): child path may only use a scoped official YouTube (or approved) embed with allowlist IDs; no arbitrary navigation, URL bar, or unrestricted search; stop on budget/session expiry.
  - Docs: `docs/decisions/0003-youtube-containment-d8.md`; `phases/phase-2-scoped-playback.md`; ADR 0002 open-decisions line updated (D8 → ADR 0003; D6/D9/D10 still open). M1 reward model exists; **P1-3 / P1-4 may still be open** — M1 is not claimed fully closed.
  - VisaCore: `ApprovedVideo` / `VideoAllowlist` / `VideoAllowlistStore` (UserDefaults scaffold), `YouTubeEmbedURL` (nocookie embed construction + arbitrary-URL reject), `PlaybackPolicy` + `FakePlaybackEngine`, `Session.replaceRewardState`.
  - VisaGames: `ScopedPlayerView` (WKWebView, main-frame embed-only, link clicks cancelled, popups denied); parent-only allowlist text fields + add/remove/play; play-mode scoped surface; parent “Test viewing budget” seeds RewardLedger entry/test completion for demos.
  - Tests: 4 scoped-playback checks wired into VisaCoreChecks (allowlist unknown ID; budget/session stop; D8 non-embed reject; upsert/label). Expect PASS: 7+8+7+6+4.
  - Version: Info.plist + shell footer **0.3.0** (CFBundleVersion 4). Prompt archive `prompts/pr-0006-m2-scoped-player-scaffold.md`.
  - Linux workshop: `swift: not found` (no claim from Linux). **Mac mini toolchain green** on tip `cb871e7`: `sh scripts/test.sh` → PASS (7+8+7+6+4); `sh scripts/bundle.sh` → Built `.build/Visa Games.app` with no WK delegate warning after MainActor decisionHandler fix. Manual parent UAT / residual YouTube chrome observation still pending — do not merge until parent UAT.
  - Exact next task: Parent visual UAT on Mac mini (allowlist add → test viewing budget → 1-min visa → play allowlisted; confirm no child URL field; note residual WK/YouTube chrome); then parent merge decision.

- 2026-09-27: PR #6 Parent window and YouTube paste UX source updated to v0.3.1 (PATCH); Mac mini re-UAT pending.
  - Parent mode now uses a titled, resizable, minimizable window with scrollable controls. Returning to child restores borderless full-screen presentation; screen changes resize only the child presentation. Switching to another app no longer ends Parent mode; the existing two-minute deadline and sleep handling remain.
  - Parent allowlist entry extracts an 11-character ID from a bare ID or known YouTube watch, share, and embed URLs. D8 embed construction and child navigation policy remain separate. Added one scoped-playback check with accepted/rejected paste cases; expected offline output is 7+8+7+6+5 checks.
  - Info.plist is 0.3.1 / build 5; shell footer is v0.3.1. Prompt archived in `prompts/pr-0006-m2-parent-window-url-extract.md`.
  - Linux workshop: `sh scripts/test.sh` and `sh scripts/bundle.sh` exited 127 (`swift: not found`). No new Swift compile, test pass, native launch, or Mac mini PASS is claimed. PR #6 remains open; M1 P1-3/P1-4 and M2 target-device evidence remain open. Existing OS escape paths remain documented in `docs/phase-0-kiosk-checklist.md`.

- 2026-09-27: PR #6 parent preview visa fix prepared as v0.3.2 (PATCH); Mac mini re-UAT pending.
  - Added `Session.extendVisaKeepingParent(seconds:now:)`, limited to configured Parent mode and the existing 3600-second grant ceiling. Parent preview now uses the existing test-budget seeding path when needed, ensures a 600-second visa deadline when absent or expired, and refreshes the Parent deadline after a successful start. `Session.grant` still enters play mode.
  - Parent unlock deadline and the matching bilingual UI copy are now ten minutes. The existing Parent `ScopedPlayerView` was already conditional on `activePlayVideoID`; no player view change was needed.
  - Added one offline session check for unconfigured/child rejection, the visa deadline in Parent mode, and the unchanged grant transition. Expected banner: 8 session + 8 reward-ledger + 7 reward-persistence + 6 theme-preference + 5 scoped-playback checks. Info.plist is 0.3.2 / build 6; shell footer is v0.3.2. Prompt archived in `prompts/pr-0006-m2-parent-preview-visa.md`.
  - Linux workshop: `sh scripts/test.sh` and `sh scripts/bundle.sh` each exited 127 (`swift: not found`). `git diff --check`, plist parsing, and shell syntax checks passed. No Swift compile, test pass, native launch, or Mac mini PASS is claimed. PR #6 remains open; M1 P1-3/P1-4 and M2 target-device evidence remain open. OS escape paths remain documented in `docs/phase-0-kiosk-checklist.md`.

- 2026-09-27: PR #6 Link-blocked UAT fix prepared as **v0.3.3** (PATCH); Mac mini re-UAT pending.
  - Mac mini Reported offline green @ `327d6dd` (PASS 8+8+7+6+5; bundle OK) but real Preview play failed with 「已阻擋連結。 / Link blocked (D8).」 — WK policy cancelled YouTube official embed redirects / in-player chrome and stopped playback.
  - VisaCore: `isAllowedEmbedMainFrameURL(_:videoID:)`, `isBenignBlankURL`, `isClearEscapeURL`, and a tight host allowlist for `/embed/<exact-id>` on nocookie + youtube.com / m.youtube.com. Construction still uses nocookie `make(videoID:)`.
  - ScopedPlayerView: allow main-frame official embed family + about:blank; quiet-cancel linkActivated / popup / non-https subframe noise; call `onNavigationRejected` only for real main-frame escapes. ADR 0003 note: same-id embed redirects permitted; watch/search still denied.
  - Added one scoped-playback check for main-frame allow/reject cases. Expected banner: 8+8+7+6+**6**. Info.plist 0.3.3 / build 7; shell footer v0.3.3. Prompt archive `prompts/pr-0006-m2-embed-navigation-relax.md`. Added tracked `logs/README.md` (gitignore `logs/*` except README) for Mac mini UAT notes — no secret dumps.
  - Linux workshop: `swift: not found` expected. **Mac mini toolchain green** @ `7b505b4`: `sh scripts/test.sh` → PASS **8+8+7+6+7**; `sh scripts/bundle.sh` → Built `.build/Visa Games.app` (Info.plist 0.3.4 / build 8). Visual Error 153 / Preview play UAT still pending — do not merge until Carter OK.

- 2026-09-27: PR #6 YouTube Error 153 embed Referer fix + ScopedPlayer logs prepared as **v0.3.4** (PATCH); Mac mini re-UAT pending.
  - Mac mini Reported offline green @ `08c304c` (PASS 8+8+7+6+6; bundle OK) but Preview play showed **Error 153 — Video player configuration error** (likely missing/invalid Referer on bare WK `URLRequest` to youtube-nocookie).
  - VisaCore: `embedHTMLString(videoID:)`, `embedHTMLBaseURL()`, `isAllowedEmbedShellMainFrameURL` (nocookie host-root only). Construction still nocookie `/embed/<id>`; shell is not a general browse grant. `isClearEscapeURL` treats shell as non-escape.
  - ScopedPlayerView: `loadHTMLString` iframe + `referrerpolicy="strict-origin-when-cross-origin"` + meta referrer + baseURL nocookie `/`; `mediaTypesRequiringUserActionForPlayback = []`. Navigation allow shell or `/embed/<id>`; stop only on real escapes. Lightweight nav/fail/finish logs.
  - ScopedPlayerLog: always `~/Library/Logs/VisaGames/scoped-player-YYYYMMDD.log`; also repo `logs/` when `logs/README.md` found walking up from cwd/bundle; optional `VISA_GAMES_LOG_DIR`. Parent button 「開啟日誌資料夾 / Open logs folder」. Updated `logs/README.md` + ADR 0003 Error 153 note.
  - Added one scoped-playback check for HTML shell / referrerpolicy / shell allowlist. Expected banner: 8+8+7+6+**7**. Info.plist 0.3.4 / build 8; shell footer v0.3.4. Prompt archive `prompts/pr-0006-m2-error153-embed-referrer-logs.md`.
  - Linux workshop: `swift: not found` expected. **Mac mini toolchain green** @ `7b505b4`: `sh scripts/test.sh` → PASS **8+8+7+6+7**; `sh scripts/bundle.sh` → Built `.build/Visa Games.app` (Info.plist 0.3.4 / build 8). Visual Error 153 / Preview play UAT still pending — do not merge until Carter OK.

- 2026-09-27: PR #6 Carter Mac mini UAT reported **play works; Error 153 fixed**. v0.3.5 (PATCH) enlarges the ScopedPlayerView surfaces: Parent preview 420–720 pt, Play mode 480–900 pt, and the default Parent window height is 800 pt so the preview has room to grow. The existing HTML shell already uses margin/padding-free `html, body` plus a 100% width/height iframe, so no CSS behavior change was needed.
  - Log review for the reported run: `load mode=htmlString` and the nocookie embed for `zvdtlrMeR3U` succeeded; `wk didFinish` completed; repeated `popup deny url=www.youtube.com/watch` is expected D8 provider chrome; no Error 153 or `navigationRejected` teardown was present. The remaining small-player issue was UI layout, not WK policy.
  - Info.plist is 0.3.5 / build 9; shell footer is v0.3.5. Prompt archive: `prompts/pr-0006-m2-player-size.md`. Mac mini re-UAT is still required for the enlarged layout; PR #6 remains open and must not be merged here.
