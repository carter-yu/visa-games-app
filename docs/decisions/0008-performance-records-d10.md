# ADR 0008 — Performance records (D10)

Status: Accepted by Carter Yu (2026-10-09 08:03 HKT, design §13 "A" on every decision; decision 8
replaced by Carter). v0.20.0 / build 42 ships **Record** only, on `feat/perf-record-v020`.
v0.21 (parent review screen) and v0.22 (adaptive dealing) are separate PRs.

Design: `perf-review-design.md` (box `/workspace/visa-games-design/`, approved 2026-10-09).

## Context

D10 was open since ADR 0002. The app wrote text logs (`VisaGamesLog`, mirrored to the repo's
gitignored `logs/`) but nothing a parent could count: which games are hard, which wrong options
confuse, which videos the child picks. A dealer that leans toward weak games (v0.22) needs
clean, tagged data first.

## Decisions

1. **Local, parent-only, append-only.** One JSON Lines file per Hong Kong calendar day:
   `~/Library/Application Support/VisaGames/stats/events-YYYY-MM-DD.jsonl`, plus
   `rollup-v1.json` (daily summaries) and `exports/`. Separate from `state.json`, the
   UserDefaults stores and the text logs. Never written to the repo `logs/` mirror (that folder is
   gitignored, but a force-add or a pasted excerpt would still leak a child's records). Nothing is
   uploaded. No child-visible change.
2. **Envelope v1.** Every line: `v, t, ts (UTC ms), tz, mono (systemUptime), launch, seq, app,
   actor, mode, session` plus flat event fields; sorted keys. Readers skip torn lines and
   `v > 1`, order by `(launch, seq)` and never assume file order. Unknown `t` values decode.
3. **Events.** `app_launch`, `app_terminate`, `session_start`, `parent_enter`, `parent_leave`,
   `uat_mode`, `game_dealt` (kind, item, stars, pool, dealt slots), `answer_attempt` (choice,
   asset, slot, correct, pending before/after, confusion tags, repeat/fast, convoy step),
   `hint_shown`, `round_result` (solved / zeroed / abandoned, first try, misses, active / total /
   parent ms, mash taps, wrong choices), `visa_start` / `visa_end` (earned / parent_test /
   unknown), `picker_visit` (deck, entry), `video_impressions` (ids fully drawn on a page),
   `video_pick` (page, slot, accepted / refused), `resume_offered` / `resume_used` /
   `resume_cleared` (saved position dropped: pick_other, resume_choice_pick_other, ended,
   allowlist_removed, storage_reset),
   `video_start` (source pick / continue / after_parent / parent_preview), `video_progress`
   (every 60 s), `video_end` (stop reason, watched / wall seconds, max position, completion,
   resume saved), `allowlist_change`, `config_change`, `stats_exclude` / `stats_include`,
   `stats_marker`, `clock_jump`.
4. **Video stop reasons match the code (decision 8 replaced).** The child has no stop button; a
   child play ends by finishing or by time running out. `PerfVideoStopReason`: `ended`,
   `visa_expired`, `budget_exhausted`, `nav_guard` (D8 guard, rare and technical),
   `parent_unlock`, `preview_stopped`, `allowlist_removed`, `storage_reset`,
   `storage_failure`, `app_terminate`, plus defensive `superseded` / `unknown` (not expected).
   The field is `video_end.stop_reason`. A missing end (power cut) is read as `interrupted`,
   never written. No quick-exit or early-exit classification. Embed errors do not stop
   playback; a play with no player samples has `telemetry=none` and `watched_s=0`.
   `resumed_later` (CSV, rollup) is resolved by the reader: `yes` (a later child start of the
   same video from 繼續睇), `no` (another child start or `resume_cleared` first), `pending`
   (still saved), `n/a` (nothing saved).
5. **Who counts.** One actor rule: parent playtest → `parent_playtest`; other parent-mode video →
   `parent_preview`; other parent mode → `parent`; 🧪 家長測試中 on → `parent_uat`; play inside a
   「測試一分鐘簽證」 → `parent_test_visa`; else `child`. Only `child` lines in sessions not marked
   「唔計呢段」 count. 🧪 is memory-only and turns itself off after 60 minutes.
6. **Retention (2A).** Raw days are kept for 90 HKT calendar days including today. Older days are
   folded into `rollup-v1.json` (per day: games by kind and stars, videos by id; countable only)
   and then deleted. The rollup is written atomically before any delete, and folded days are
   remembered, so a crash between the two never double counts. Runs off the main thread at launch.
7. **Clear (3A).** 「清除簽證及重設儲存」 does not touch `stats/`. 「清除表現紀錄」 (Advanced, with
   confirm) deletes `stats/` only and writes a fresh `stats_marker{cleared}`.
8. **Export.** Parent-only 「匯出表現 (CSV)」 writes `rounds.csv`, `videos.csv`,
   `video_impressions.csv`, `daily_games.csv`, `daily_videos.csv` and a bilingual `README.txt` to
   `stats/exports/performance-YYYYMMDD-HHMMSS/` (UTF-8 BOM, CRLF, HKT date/time + UTC column,
   `counted` yes/no) and reveals it in Finder.
9. **Never in the child's way.** File I/O runs on one serial utility queue. A write error never
   throws into the child flow and never sets `storageFailed`; it raises one parent banner
   「表現紀錄未能儲存（唔影響小朋友玩）」. The recorder never touches `Session`, the ledger or
   `update(_:)`.
10. **Test visa decks.** `grant()` now mints a picker visit seed (entry `test_visa`), the same as
    「出發！」, so a test visa's picker visit is recorded as its own visit. Parent-only path.

## Consequences

- A parent can tag their own play two ways (🧪 switch, or 「唔計呢段」 on the last sessions of this
  launch). Older sessions can be dropped later in the v0.21 review screen.
- The day file name is the HKT day of the event, so a session that crosses midnight spans two files;
  readers merge by `(launch, seq)`.
- Unchanged: kiosk boundary, parent authentication, reward policy D1–D7, D8 playback gate,
  activity content, child screens.
