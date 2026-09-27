# PR prompt archive — M3 entry gate layout + reset persist + VisaGamesLog (v0.4.2)

| Field | Value |
|-------|--------|
| Branch | `feat/m3-first-learning-loop` (same PR #7) |
| Base tip | `d2af476` (v0.4.1) |
| Version | **0.4.2** (PATCH — child UAT unblock) |
| Goal | Lock reliably shows two-picture `EntryActivityView`; Reset works when reward nil; troubleshooting logs |

## Problem (Carter Mac mini UAT)
After v0.4.1 tip: lock still showed no two-picture game; parent Reset entry activity appeared inert; no new logs for troubleshooting.

## Root cause (code)
1. ShellView Spacers above/below mode content clipped/compressed large EntryActivityView.
2. `resetEntryActivityForChildUAT` early-returned when `snapshot.reward == nil`.
3. No app-level entry/mode/reset logging (only ScopedPlayer).

## Required changes (done)
1. Layout: suppress Spacers when entry gate shown; ScrollView + layoutPriority for EntryActivityView; compact play visa strip during entry.
2. Reset: always persist ledger with entryActivityCompleted=false (create empty 60/1200 if nil); confirmation under button; objectWillChange.
3. VisaGamesLog → visa-games-YYYYMMDD.log (Library + repo logs/); log reset before/after, shell branch, seed, select, apply, returnToChild, storage failures, mode tick changes.
4. Unit test for nil reward = entry incomplete + persist fresh false flag. PASS reward-ledger **9 → 10**.
5. Version **0.4.2** / CFBundleVersion 12; PROGRESS + this prompt. Commit push PR #7. **Do not merge.**

## Constraints
- HK Traditional Chinese + English UI only; never Simplified Chinese.
- Do not invent D6/D9/D10 or hardcode YouTube packs. No Tomica IP.
- Linux workshop has no Swift — do not claim tests passed on Linux.

## Essential prompt text (sanitized)
> Diagnose inert Reset / missing two-picture on PR #7 after v0.4.1. Fix layout so EntryActivityView is always visible; fix nil-reward reset no-op; add VisaGamesLog; bump 0.4.2; commit push; do not merge.
