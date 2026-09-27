# PR prompt archive — M3 entry gate ScrollView collapse fix (v0.4.3)

| Field | Value |
|-------|--------|
| Branch | `feat/m3-first-learning-loop` (same PR #7) |
| Base tip | `7bdd592` (v0.4.2) |
| Version | **0.4.3** (PATCH — restore entry target visibility) |
| Goal | Two large crane/bus silhouettes visible again on lock/play after 0.4.2 layout regression |

## Problem (Carter confirmed)
On **v0.4.1** he COULD see the two crane/bus buttons. After pull to **v0.4.2** (`7bdd592`) he does NOT see them. Title + Parent + version remain; the two targets vanish.

## Root cause (code)
`entryGateScroll` wraps `EntryActivityView` in `ScrollView { … }.frame(maxWidth: .infinity, maxHeight: .infinity)`. In a parent `VStack`, an unbounded-height ScrollView often **collapses to ~0 height** (flexible min size), so the gate content is laid out but not visible. 0.4.1 put `EntryActivityView` directly in the VStack — that worked for Carter.

## Required changes (done)
1. Remove collapsing ScrollView wrapper; restore **direct** `EntryActivityView` in lock/play (`entryGateContent`) like 0.4.1.
2. Optional safety: `.frame(minHeight: 480)` on the entry gate content so it cannot shrink away.
3. Keep compact spacing / slightly smaller title when showing entry (`showsEntryGate`); visibility first.
4. Keep all good 0.4.2 work: reset always persists incomplete ledger, confirmation under Reset, VisaGamesLog, seedTest without `completeEntry`.
5. Version **0.4.3** / CFBundleVersion 13; PROGRESS + this prompt. Commit push PR #7. **Do not merge.**
6. Linux has no Swift — do not claim tests ran here.

## Constraints
- HK Traditional Chinese + English UI only; never Simplified Chinese.
- Do not invent D6/D9/D10 or hardcode YouTube packs. No Tomica IP.
- Linux workshop has no Swift — do not claim tests passed on Linux.

## Essential prompt text (sanitized)
> VisaGames workshop: v0.4.2 ScrollView entryGateScroll collapsed EntryActivityView to ~0 height in VStack (Carter: buttons gone after 0.4.1→0.4.2). Restore direct EntryActivityView like 0.4.1; optional minHeight 480; keep 0.4.2 reset/log/seed fixes; bump 0.4.3; commit push PR #7; do not merge.
