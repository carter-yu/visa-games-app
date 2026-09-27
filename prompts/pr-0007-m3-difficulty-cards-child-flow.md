# PR #7 — Child difficulty cards → task → visa → YouTube (v0.5.0)

Carter Confirmed (this turn): child flow from visa-games reference; durations **★1=10 / ★2=20 / ★3=30** minutes (Confirmed — NOT 10/18/28).

Branch: `feat/m3-first-learning-loop` @ ~432e5eb (v0.4.3). Do not merge to main. Do not invent D9 YouTube pack IDs. No Tomica IP. No Simplified Chinese. Linux has no Swift — do not claim `test.sh` passed.

## Required child flow

1. After setup/configured, **lock** shows three large pen-friendly difficulty cards (Trad Chinese + English):
   - ★1 簡單 / Easy → **10** min
   - ★2 適中 / Medium → **20** min
   - ★3 挑戰 / Challenge → **30** min
   Show minutes on each card.

2. Tap card → enter **task** UI showing existing `EntryActivityView` (crane vs bus). Store `selectedStars` + target visa minutes in AppModel. Prefer in-session AppModel round state (`taskRoundOpen` / `selectedStars` / minutes) while Session mode stays lock until success — do not invent a durable schema bump unless necessary.

3. Wrong → gentle retry (existing). Hint → assisted (existing D7).

4. Correct → `completeEntryActivity` + `applyCompletion` (D7 recording); **`startPlayVisa(seconds:)`** child path that sets `endsAt` and `mode=.play` without requiring parent mode (`grant` stays parent-only). Visa seconds = minutes×60 (10→600, 20→1200, 30→1800). SuccessParkAnimation; go to **play**. If allowlisted video present, start via existing `playAllowlisted` / PlaybackPolicy (allowlist+budget+visa).

   Viewing budget: PlaybackPolicy still needs budget>0. On success, bank viewing seconds for the round via `applyCompletion` with a **round-unique** completion ID and `rewardSeconds: minutes*60` (subject to existing rewardCap — document if Challenge hits cap). Keep D1 `entryActivityCompleted` ledger flag as today (once). Do not invent D9.

5. Play shows countdown + scoped player when allowlisted; if no allowlist, clear bilingual message asking parent to add video (visa already running).

6. Visa expiry → back to **lock with cards again**. Reset per-round UI: clear `taskRoundOpen`, `selectedStars`, entry hint/retry flags, activePlayVideoID. Critical: UI gate must be **per round**, NOT blocked by D1 `entryActivityCompleted`. After first success, child must still see the three cards next time — never stuck on "Entry activity done". Prefer: keep `entryActivityCompleted` for D1; add separate `taskRoundOpen` / `selectedStars` for UI.

7. Parent mode essentials unchanged: Reset entry / logs / Test 1-min visa / Test viewing budget still OK as emergency.

## VisaCore

- Extract pure difficulty mapping (stars → minutes → seconds) + tests.
- Add `Session.startPlayVisa(seconds:now:)` for configured child path (fail-closed on invalid seconds / unconfigured / non-finite; allow while mode is lock or after task — not from setup; max still sane e.g. ≤3600).
- Tests: difficulty→seconds; startPlayVisa sets endsAt+play; expiry returns lock; child cannot use parent-only `grant`.

## UI

- New difficulty card view (large targets, pen-friendly). Labels: 簡單/Easy, 適中/Medium, 挑戰/Challenge + star glyphs + minutes.
- ShellView lock: cards when `!taskRoundOpen`; EntryActivityView when `taskRoundOpen`. Do **not** gate on `isEntryActivityCompleted` for showing cards vs task.
- Remove / stop using the "入口活動完成 / Entry activity done" lock dead-end as the default child home.
- Version footer **v0.5.0**. Info.plist CFBundleShortVersionString 0.5.0, bump CFBundleVersion (e.g. 14).

## Docs

- Short ADR note or update ADR 0004 / PROGRESS: Carter Confirmed child flow from visa-games reference; durations **10/20/30 Confirmed** (closes practical D6 for this scaffold — label evidence). Update `phases/phase-3-first-learning-loop.md` if present.
- PROGRESS fact-only entry for v0.5.0; exact next task = Mac mini UAT (open → 3 cards → pick → two pictures → success → YouTube if allowlisted). Do not claim M3 fully done without Mac UAT.

## Do NOT

- Invent D9 pack IDs; Tomica IP; Simplified Chinese; merge to main; claim Linux swift tests passed.
- Use 10/18/28 — those are obsolete; use **10/20/30**.

## Done when

- Code + tests + docs + prompt archive landed.
- Commit on branch and **push** to origin for PR #7.
- Report tip SHA, version 0.5.0, Mac mini UAT steps.
