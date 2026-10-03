# Parent settings — game catalog & star assignment

**Status:** Accepted. Carter lock 2026-10-03 (defaults). Implemented on `feat/parent-settings-games-catalog` from `main` after v0.16.0 (PR #15). Version **0.17.0 / build 39**. Do not merge in this PR.  
**Read from:** parent UI at v0.16.0 (`7547988`).  
**Language:** Hong Kong Traditional Chinese + English. Never Simplified.  
**Child:** about 4, cannot read. This screen is parent-only (ADR 0007 §5).  
**Policy:** do not change 5 / 10 / 15 minute visas, reward ledger, or D1–D7. Stars stay visa length, not a harder question.

## A. Current parent IA

One parent screen, `ParentSettingsView`, mode `.parent` only. One vertical scroll (max ~940) plus a pinned bottom bar.

| Band | What it is | Notes |
| --- | --- | --- |
| Header | 家長設定 / Parent controls + Stampy + 「10 分鐘自動鎖」 | Stays. |
| Notices | Auth / storage, then last action | Stays. |
| 測試同主題 | 測試一分鐘簽證, 測試觀看時間, theme chips | Frequent. `grant()` leaves parent and enters child `.play` for 60s. |
| 准許影片 | Paste row, draft preview, title/length disclosure, inline player, `AllowlistVideoCard` grid | The only content library. Cards: 16:9 thumb, duration chip, title, 試播 Preview, trash + confirm. Playing card fill = sunny pale. Inline player is a dark chunky panel with 停止 Stop. |
| 進階 | Disclosure: stale game sentence, reset entry UAT, logs, reset storage, license | The game sentence lists only 兩圖／搵相同／數車／車隊排序. Six v0.8 kinds are missing. |
| Bottom bar | 返回 Return, version, 離開程式 Quit | Return calls `leaveParent` → lock, or `.play` if `endsAt` is still in the future. |

There is no game list, no star assignment, and no way to open an activity from here.

**What the child actually gets today**

- Depot shows three tickets (`MissionTicket.all`): ★1 的士短程 5 分鐘, ★2 消防車任務 10 分鐘, ★3 地鐵長程 15 分鐘. Stars = `ChildDifficulty.rawValue`. Minutes = raw × 5. One road tile per star.
- `selectDifficulty` does **not** look at the star. It hashes a new UUID and picks `ActivityCatalog.kind(forRoundSeed:)`, modulo **all 10** playable kinds. Every ticket can deal any game.
- Each kind has **one** fixed question. `stubKinds` is empty.
- A correct tap in `.lock` runs `applyEntrySuccess` → ledger `completeEntryActivity` + `applyCompletion` + `startPlayVisa` → stamp → 出發. Selectors refuse anything except `session.mode == .lock`.

**Built games (10).** Parent-facing names below are for the new cards. Child prompts stay as they are.

| Kind | 卡片名 | Prompt (HK) | Hero |
| --- | --- | --- | --- |
| `twoPictureChoose` | 邊架消防車 | 邊架係消防車呀？ | 消防車 vs 的士 |
| `findTheSame` | 搵同一個 | 搵同一個！邊架同上面一樣？ | 紅的 |
| `countVehicles` | 數消防車 | 數一數有幾架消防車呀？ | 三架消防車，揀 2／3／4 |
| `sequenceShortToLong` | 短到長車隊 | 由短到長排車隊。 | 的士→消防車→吊臂→地鐵 |
| `halfMatch` | 搵另一半 | 搵另一半！ | 消防車左半 |
| `shapeCousin` | 圓圓嘅 | 太陽圓圓嘅，邊樣都係圓圓嘅？ | 太陽 → 油罐車 |
| `capacityCompare` | 邊架載多啲人 | 巴士同的士，邊架載多啲人？ | 巴士 vs 的士 |
| `moreFewer` | 邊邊車多啲 | 邊邊停車場嘅車多啲？ | 左 2／右 4 |
| `shadowMatch` | 邊個影子 | 邊架啱呢個影子？ | 地鐵影子 |
| `emptyBay` | 空車位 | 邊個車位係空嘅？ | 三格，中間空 |

**Named in ADR 0005, not built** (no `ActivityKind`, no view): 描線 path-trace, 迷宮 maze-lite, 形狀分類 shape sort, 連點 connect-the-dots. Do not invent playable cards for these.

## B. Recommended IA

**Not an AppKit tab. Not a new window. Not a child-facing control.**

Inside parent settings, a **two-way chunky segment** under the test row:

**影片 Videos · N** | **遊戲 Games · 10**

Selected segment: sunny-pale fill, ink 3 pt, radius ~16, same family as `ThemeChip`. Unselected: paper. Labels HK large, English small. Remember the last segment for this parent visit only (default 影片, so today’s screen does not jump).

**Why this and not “a tab for games” or three segments**

- Videos and games are both long card libraries. One scroll makes the game grid a scavenger hunt under a growing allowlist, and makes 試播’s inline player fight the game grid for the same column.
- 測試同主題 is two buttons plus theme chips, and 測試一分鐘簽證 **leaves** parent mode. Hiding it behind a third segment adds a tap to the action used most. Keep it **pinned above** the segment on both sides.
- A real tab bar would look like macOS Settings, not the canvas parent (paper, ink, chunky panels). The segment is the same control language as the video cards.
- Advanced stays **once**, at the bottom of the scrolling region, on both segments. Delete the stale “四款遊戲” sentence; the Games segment is that list.

**Chrome**

```
pinned: header
pinned: notices
pinned: 測試同主題
pinned: 影片 | 遊戲
scroll:  active library only
scroll:  進階
pinned: 返回 / version / 離開程式
```

Switching segment stops an inline video preview (`stopParentPreview`) and does not start a playtest. Playtest is a cover, not a segment.

## C. Game card UX and star rules

Mirror `AllowlistVideoCard`: white/paper chunky panel, radius 18, ink 3 pt, shadow 5. Grid `adaptive(minimum: 230, maximum: 320)`, spacing 18/22, same as videos. No trash. Games are not parent-authored.

Each card:

1. **Art well** (16:9, ink 2 pt, radius 12). Static hero from the catalog question via existing `ActivityAssetView` / canvas art. Not a live game, not a YouTube thumb. No play glyph until hover/focus; a corner pill with the kind’s short name (兩圖, 搵相同, 數數, 車隊, 另一半, 圓形, 載人, 多定少, 影子, 空位).
2. **Title** HK Trad `CanvasFont` 15/800, two lines reserved. English parent subtitle 12 pt ink-soft (the “Prompt (HK)” line is the help tip, not the title).
3. **Three star toggles** in a row, not a duration chip. Each toggle is a mini chunky button:
   - ★1 5 分鐘
   - ★2 10 分鐘
   - ★3 15 分鐘
   - On: sunny fill + filled star. Off: paper + outline star.
   - Tapping toggles only that star. Accessibility label includes the ticket name: 「★1 的士短程 5 分鐘」.
4. **試玩 Playtest** — sunny chunky button, same slot as 試播 Preview. Card fill goes sunny-pale while that playtest is the one just returned from (same “is playing” cue as video cards). No second button.

**Below the grid, one muted row (not cards):** 「未做好 / Not built yet」 plus the four ADR names. No stars, no 試玩. This is how Carter sees every designed game without a fake activity.

### Star rules (defaults)

Stars are **which ticket may deal this game**. They do not change the question, the minutes, or the reward.

| Rule | Default |
| --- | --- |
| Multi-star | **Yes.** A game may be on ★1 and ★2 and ★3. Today every ticket already deals every game; exclusive stars would pretend the questions get harder. They do not. |
| Exclusive | **No.** Turning on ★2 does not clear ★1. |
| Empty tier | **Forbidden.** The last on-star for a ticket does not turn off. Banner: 「每個星級至少要有一個遊戲 / Each star needs at least one game」. The child ticket must always have a deal. |
| Hidden game | A game with all three stars off **stays on the grid** with pill 「唔會出現 / Hidden from missions」. Carter can still 試玩 it. |
| Child deal | `selectDifficulty` hashes as today, but the pool is that star’s on-set only. Same kind of modulo. Unknown or empty stored set → **all 10** (today’s behaviour). |
| First launch | **All 10 games on all 3 stars.** Nothing changes for the child until a star is turned off. |
| New kind later | A kind the store has never seen joins **all three stars** (opt-out, not invisible). |
| Persistence | `UserDefaults` key beside the allowlist (`VideoAllowlistStore` pattern). **Not** the reward `Snapshot`. `resetStorage` clears visa/ledger only; it does **not** clear this map. |

## D. Playtest exits to parent and does not award a visa

Playtest is a **cover on top of parent settings**. `session.mode` stays `.parent`. It must not call `selectDifficulty`, `handleEvaluation`, `applyEntrySuccess`, `startPlayVisa`, `grant`, `extendVisaKeepingParent`, `completeEntryActivity`, or `applyCompletion`.

Why the video path is the wrong template: parent 試播 calls `extendVisaKeepingParent(600)`, which writes `endsAt` while staying in `.parent`. `leaveParent` then `normalize`s into `.play` if that deadline is still in the future. A game playtest must not set `endsAt`, viewing budget, `lastIncomplete`, or entry-completed.

**Stage.** Reuse `CanvasActivityHost` visuals (same board the child sees) inside the cover. A parent bar is pinned on top of the safe area, ink on sand, not child chrome:

- Left: 「試玩 · {卡片名} / Playtest」 and 「冇簽證 / No visa」 pill (sand).
- Right: **返回家長 / Back to parent** (mint chunky, always visible). This is the only exit that matters. It does not call `returnToChild`.

**Input.** A playtest-only evaluator uses the same `ActivityEvaluator` and the same catalog template, with **local** miss count, hint flag, and a local fuel counter that starts at 5 only so the on-screen fuel copy can be reviewed. That counter is discarded. Selectors that require `.lock` are not used, so a correct tap cannot fall through into the stamp.

**Correct.** No stamp, no 出發, no picker, no watch. The board stays. A paper banner: 「試玩完成，冇發簽證。 / Playtest finished. No visa.」 The parent bar stays. 返回家長 goes to the Games segment with that card marked. Speech stops.

**Wrong.** Same child wiggle and, after two misses, the existing hint line, so Carter can review it. Local fuel copy may show. Nothing is written. Do not call `returnToDepotOutOfFuel` (that speaks the depot line and clears a real round).

**Other exits, all discard local state, mode stays `.parent` until the existing parent path says otherwise:**

- Segment is not reachable under the cover; back is explicit.
- Parent 10-minute auto-lock: tear the cover down first, then the existing lock path. Do not resume the playtest as a child round.
- 返回 Return on the settings bar is hidden while the cover is up, so it cannot `leaveParent` mid-question. After back, Return works as today.
- Quit: `prepareForTerminate` also drops the cover and stops speech. No ledger write.

**Voice.** Playtest speaks the same zh-HK prompt as the child (`speakEntryPrompt` content, but allowed in `.parent` only for this cover). Stop on any exit.

## E. Open questions (5) and APPROVE DEFAULTS

Reply **APPROVE DEFAULTS** to lock every line below. Reply with a number only to override that one.

1. **Unbuilt ADR genres** (描線 / 迷宮 / 形狀分類 / 連點). **Default:** one muted 「未做好」 row, no stars, no 試玩. Not hidden, not fake cards.
2. **Playtest voice.** **Default:** speak the zh-HK prompt, stop on exit. Silent only if the Mac has no zh-HK voice (same as the child).
3. **Wrong answers inside playtest.** **Default:** simulate wiggle, hint after 2, and a local fuel counter; discard all of it. Do not skip the feedback, and do not touch the ledger.
4. **Card = kind, not question variant.** **Default:** one card per `ActivityKind`. 試玩 loads today’s single template. Stars attach to the kind. A future second question of the same kind does not become a second card unless Carter asks.
5. **Where the map lives.** **Default:** UserDefaults next to the video allowlist. Not the reward snapshot. Visa reset does not clear it. Missing or empty star → all 10 games on that star.

## F. Later PR file list (when approved — do not do it in the design turn)

One PR, design doc included. No deploy.

- `docs/designs/parent-settings-games-catalog.md` (this file; status → accepted)
- `Sources/VisaCore/Activity.swift` — parent display names (HK Trad + English) and short kind labels for the 10 kinds. No new kinds.
- `Sources/VisaCore/MissionGameAssignment.swift` (new) — map kind → set of `ChildDifficulty`, defaults, “last star” guard, empty-set fallback, Codable store. Pure, tested.
- `Sources/VisaGames/AppDelegate.swift` — load/save store; `selectDifficulty` filters the pool; playtest session object that never calls `applyEntrySuccess` / visa extend. Do not weaken `.lock` guards on the child selectors.
- `Sources/VisaGames/ParentSettingsView.swift` — segment, game grid, muted unbuilt row, delete the stale Advanced sentence.
- `Sources/VisaGames/ParentGameCard.swift` (new, or private in the settings file if it stays small) — card matching `AllowlistVideoCard`.
- `Sources/VisaGames/ParentPlaytestCover.swift` (new) — cover + parent bar; hosts the existing activity board with playtest callbacks.
- `Tests/VisaCoreTests/ActivityTests.swift` or `MissionGameAssignmentTests.swift` — defaults all-on, multi-star, reject empty tier, corrupt fallback, new-kind opt-out, rotation stays inside the star’s set.
- `PROGRESS.md` — one design-accepted line, then an implementation line in the code PR. Version bump only in the code PR (not 0.16.0 again).

Out of scope for that PR: new activities, passport, recorded D9 audio, changing 5/10/15, merging to main, Mac mini install.
