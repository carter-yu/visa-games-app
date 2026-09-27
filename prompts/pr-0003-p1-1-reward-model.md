# PR #3 — P1-1 in-memory reward model

> **Reconstruction notice:** This file is **reconstructed** from parent chat + `PROGRESS.md` / ADR 0002 / P1-1 sources. It is **not** a verbatim copy of a live-archived filesystem original. Sanitize and treat as engineering intent, not a chat dump.

| Field | Value |
| --- | --- |
| Date | 2026-09-27 (HK) |
| Branch | `feat/p1-1-reward-model` |
| PR | https://github.com/carter-yu/visa-games-app/pull/3 (MERGED) |
| Model | `gpt-6-sol` (Codex / sol; Linux workshop — no Swift on host) |
| Goal | Pure in-memory `RewardLedger` + VisaCoreChecks for Confirmed D1 / D2 / D3 / D7; leave Snapshot persistence to P1-2 |

## Constraints
- Implement only Confirmed D1, D2, D3, D7 from ADR 0002. **Do not invent D6** (or D8–D10).
- Leave `Session` / `Snapshot.endsAt` / `schemaVersion` **untouched**. No persistence / durable reward fields yet (that is P1-2).
- No YouTube / media / UI / AppKit / skin work.
- Do not mark M1 or Mac mini UAT complete.
- Linux workshop: `swift: not found` — report Mac mini retest commands; do not claim green here.
- Language lock: engineering English + HK Traditional Chinese UI only (never Simplified Chinese).
- Open the PR; **do not merge**.

## Acceptance (workshop host)
- Sources: `RewardLedger` / `RewardPolicy` / related types (`SuccessKind`, `SuccessRecord`, `RewardApplyOutcome`) under `Sources/VisaCore/`.
- Wire eight reward checks into `VisaCoreChecks` / TestRunner alongside existing seven session checks.
- Viewing budget kept separate from absolute session deadline; answering is a no-op on budget.
- Day boundary via injected `Calendar` day: no next-day carryover; no invented daily refill.
- PROGRESS updated with facts only.

## Tests (eight reward-ledger checks)
1. `testEntryActivityUnlocksConfiguredInitialAllowance` — D1 entry activity unlocks parent-configured initial allowance (no stacking on second entry).
2. `testExactlyOnceGrantPerCompletionID` — D3 award once per stable completion ID.
3. `testDuplicateCompletionIDRejected` — D3 duplicate / replay does not award again.
4. `testParentSetCapEnforcement` — D3 parent-set cap; excess not banked.
5. `testNoNextDayCarryover` — D3 no next-day carryover (injected Calendar day).
6. `testLanguageReplayDoesNotReduceReward` — D7 language replay unpenalized.
7. `testAssistedSuccessRecordedSeparately` — D7 assisted vs unassisted recorded separately.
8. `testAnsweringDoesNotSpendViewingBudget` — D2 answering does not spend viewing budget.

## Essential prompt text (sanitized, reconstructed)

> Implement Phase 1 slice **P1-1** on branch `feat/p1-1-reward-model` using `gpt-6-sol`.
>
> Build a **pure in-memory** reward decision/application model (`RewardLedger` + `RewardPolicy`) behind dependency-free VisaCoreChecks for ADR 0002 Confirmed **D1, D2, D3, D7** only:
> - D1: short entry activity unlocks parent-configured initial allowance.
> - D2: answering does not spend viewing budget; budget separate from absolute session deadline.
> - D3: exactly-once per completion ID; parent-set cap; no next-day carryover (injected Calendar day; no invented refill).
> - D7: language replay unpenalized; assisted vs unassisted recorded separately.
>
> Do **not** change `Session`, `endsAt`, or `schemaVersion`. Persistence is **P1-2**. Do not invent D6. No YouTube/media/UI. Do not claim M1 / Mac mini UAT complete.
>
> Add the eight reward-ledger checks listed above; keep the existing seven session checks. Update `PROGRESS.md` with facts. Linux has no Swift — report Mac mini commands. Open the PR; **do not merge**.

## Mac mini test notes
```sh
cd /Users/carteryu/my-ai-projects/visa-games-app
git fetch origin && git checkout feat/p1-1-reward-model && git pull --ff-only
sh scripts/test.sh
# Expect: PASS: 7 session checks + 8 reward-ledger checks
sh scripts/bundle.sh
```
