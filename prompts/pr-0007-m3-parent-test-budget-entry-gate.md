# PR prompt archive — M3 parent test-budget must not complete entry (v0.4.1)

| Field | Value |
|-------|--------|
| Branch | `feat/m3-first-learning-loop` (same PR #7) |
| Base tip | `8ca13fe` (v0.4.0) |
| Version | **0.4.1** (PATCH — parent preview UAT fix) |
| Goal | Stop parent "Test viewing budget" / Preview from marking `entryActivityCompleted`, so child lock still shows the two-picture game |

## Problem (Carter screenshot / UAT)
Parent Preview / Test viewing budget called `completeEntryActivity`, setting `entryActivityCompleted=true`. Child lock then showed 「入口活動完成 / Entry activity done」 with **no** two-picture game — blocking child UAT.

## Required changes (done)
1. `seedTestViewingBudget()` — never call `completeEntryActivity`. If viewing budget empty/zero, grant ~60s via `applyCompletion(id: "parent-test-budget", …, .unassisted)`. Create RewardLedger(60/1200) when no reward state yet. Leave `entryActivityCompleted == false`.
2. Parent button near entry note: 「重設入口活動（兒童 UAT）/ Reset entry activity (child UAT)」 → `RewardLedger.resetEntryActivityForParentUAT()` (clears entry flag only; keeps viewing seconds) + clear `entryHintUsed` / `entryRetryMessage`.
3. VisaCore test for reset API; PASS banner reward-ledger **8 → 9**.
4. Version **0.4.1** / CFBundleVersion 11; PROGRESS fact note; this prompt archive.
5. Commit + push same PR #7 branch. **Do not merge.**

## Constraints
- HK Traditional Chinese + English UI only; never Simplified Chinese.
- Do not invent D6/D9/D10 or hardcode YouTube packs. No Tomica IP.
- Linux workshop has no Swift — do not claim tests passed on Linux.

## Essential prompt text (sanitized)
> Fix PR #7 branch feat/m3-first-learning-loop: parent Test viewing budget / Preview must not call completeEntryActivity. Grant ~60s via applyCompletion parent-test-budget without setting entry completed. Add parent Reset entry activity (child UAT) button. Version 0.4.1. Commit push; do not merge.
