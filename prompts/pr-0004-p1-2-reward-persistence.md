# PR #4 — P1-2 reward persistence

| Field | Value |
| --- | --- |
| Date | 2026-09-27 (HK) |
| Branch | `feat/p1-2-reward-persistence` |
| PR | https://github.com/carter-yu/visa-games-app/pull/4 (MERGED → main ~`46f77b9`) |
| Model | Codex / sol (Linux workshop; no Swift on host) |
| Goal | Persist `RewardLedger` atomically with existing Snapshot storage; schema v2; keep answering vs viewing budget separate; absolute `endsAt` independent |

## Constraints
- Do not invent reward policy (D6 and other open decisions stay open).
- Do not add YouTube / media / UI / AppKit skin work.
- Preserve existing session + in-memory reward-ledger tests; add persistence failure-path tests.
- Fail closed on corrupt / unsupported schema / invalid reward fields.
- v1 → v2 migration must preserve `configured` / `endsAt` and must not invent reward/allowance.
- Language lock: engineering English + HK Traditional Chinese UI only (never Simplified Chinese).
- Linux workshop: no Swift — Mac mini must run tests/bundle.

## Acceptance (workshop host)
- Sources: `RewardState`, ledger export/import, `normalizeAfterLoad`, Snapshot schemaVersion 2, SnapshotStore validation.
- Tests: seven reward-persistence checks + existing 7 session + 8 reward-ledger.
- PROGRESS updated with facts; M1 / Mac mini UAT not claimed on Linux.

## Mac mini test notes
```sh
sh scripts/test.sh
# Expect: PASS: 7 session checks + 8 reward-ledger checks + 7 reward-persistence checks
sh scripts/bundle.sh
```

## Essential prompt text (sanitized)

> Implement P1-2 durable gating and session accounting on a feature branch: persist reward/allowance state atomically with the existing local Snapshot boundary; keep answering time separate from viewing budget; enforce absolute session deadline independently; normalize stale/expired state on relaunch/wake/clock changes; add failure-path tests for invalid/duplicated/capped/partially written state. Bump Snapshot schemaVersion 1→2 with safe v1 migration that does not invent reward. Do not invent D6 or other open policy. No YouTube/media/UI. Update PROGRESS. Linux has no Swift — report Mac mini retest commands. Do not claim M1 complete.
