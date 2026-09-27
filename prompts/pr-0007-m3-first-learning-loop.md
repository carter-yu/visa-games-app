# PR prompt archive — M3 first learning loop (v0.4.0)

| Field | Value |
|-------|--------|
| Branch | `feat/m3-first-learning-loop` |
| Base | `origin/main` @ `53e5f29` (PR #6 M2 merged, v0.3.5) |
| Version | **0.4.0** (MINOR — family-visible first entry activity) |
| Goal | First 先做再玩 learning loop: two-picture entry gate, RewardLedger unlock, pen-usable UI; scaffold audio; do not invent D9/D6/D10 |

## Constraints
- Language lock: engineering English; UI HK Traditional Chinese + English; **never** Simplified Chinese.
- Do **not** invent D6 / D9 / D10. Do **not** hardcode unverified YouTube IDs as an approved pack.
- No Tomica / Takara / Thomas IP — use existing original VehicleSilhouettes.
- Cantonese audio: scaffold / stub only; do not fake “audio done.”
- Reuse existing RewardLedger `completeEntryActivity` / `applyCompletion` and PlaybackPolicy seams; do not invent new timer numbers.
- Linux workshop may lack Swift — write tests; Mac mini UAT is Carter’s.
- Branch from `origin/main`. **Do NOT merge.**

## Deliverables
1. `phases/phase-3-first-learning-loop.md` + `docs/decisions/0004-first-learning-loop-m3.md`.
2. VisaCore `Activity` / `TwoPictureQuestion` / evaluator / `FirstEntryActivity` / audio stub.
3. VisaGames entry UI on lock (+ play gate); wire rewards; SuccessParkAnimation on success.
4. Tests into VisaCoreChecks; expected PASS adds `+ 7 activity checks`.
5. Parent note: entry game live; YouTube pack still D9.
6. This prompts archive; `PROGRESS.md` facts; version **0.4.0**.
7. Open PR with `gh`; report SHA, URL, child UX, unlock path, D9 reminder, Mac mini steps.

## Acceptance
- PR open against main; not merged.
- Offline checks include activity suite.
- No claim of D9 pack approval or full Cantonese audio pack.

## Mac mini test notes
```sh
cd /Users/carteryu/my-ai-projects/visa-games-app
git fetch origin && git checkout feat/m3-first-learning-loop && git pull --ff-only
sh scripts/test.sh
# Expect: PASS: 8 session + 8 reward-ledger + 7 reward-persistence + 6 theme-preference + 7 scoped-playback + 7 activity checks
sh scripts/bundle.sh
open ".build/Visa Games.app"
```
Child lock: large two-picture (crane vs bus); wrong → gentle retry; right → park-in + viewing budget. Parent: note entry live / D9 open; add allowlist; Test 1-minute visa; return to child — play shows entry gate if needed, then allowlisted video when visa+budget allow. Footer **v0.4.0**.

## Essential prompt text (sanitized)

> Repo `/workspace/visa-games-app` on main @ 53e5f29 (PR #6 merged). Reward ADR 0002 D1–D5/D7 Confirmed; D8 Confirmed; D6/D9/D10 open. Start M3 first learning loop on branch `feat/m3-first-learning-loop`. Two-picture entry gate, RewardLedger unlock, pen-usable silhouettes, audio stub only, version 0.4.0, tests, docs ADR 0004 + phase-3, open PR, do not merge. Language lock; no Simplified; no Tomica IP; no inventing YouTube pack IDs.
