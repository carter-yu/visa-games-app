# Phase 3 — M3 first learning loop

Phase 3 ships the first child **entry activity** (two-picture choice) wired to ADR 0002 reward unlock, with honest scaffolding for Cantonese audio and an explicit hold on open D9 / D6 / D10.

## Relationship to prior phases

- **M0** shell + absolute visa: Reported on target.
- **M1** reward model (P1-1 / P1-2) exists; **P1-3 / P1-4 may still be open** — do not claim M1 fully closed.
- **M2** scoped player (D8) merged to main @ `53e5f29` (v0.3.5). Parent reported play works; UI polish deferred.
- **M3** starts the ritual **先做再玩** with a real pen-usable gate before video.

## Scope (this scaffold)

- ADR 0004: M3 scaffold vs open D9 (pack/audio media), D6, D10.
- VisaCore: `Activity` / `TwoPictureQuestion` / `ActivityEvaluator` / `FirstEntryActivity` / audio protocol stub.
- VisaGames: lock-mode entry UI using original vehicle silhouettes; success → `completeEntryActivity` + D7 assisted flag; play path when visa + budget + allowlist allow via existing `PlaybackPolicy`.
- Offline activity tests into VisaCoreChecks.
- Parent note: entry game live; YouTube pack still D9.
- Version **0.4.0**.

## Out of scope

- Hardcoding unverified YouTube pack IDs (D9).
- Inventing D6 medium minutes or D10 reporting.
- Claiming reviewed Cantonese audio pack complete.
- Tomica / Takara / Thomas IP.
- Simplified Chinese UI or copy.
- Merging without parent Mac mini UAT.

## Slices

### P3-0 — Docs, activity core, UI gate, reward wire (this PR)

- Land ADR 0004 + this phase file.
- Land pure evaluator + first question + stub audio.
- Replace lock placeholder; gate play video until entry done.
- Wire RewardLedger; tests; version 0.4.0; prompts archive.

### P3-1 — Mac mini compile + child UAT

- `sh scripts/test.sh` / `sh scripts/bundle.sh` on Mac mini.
- Child: large targets with Wacom; wrong → gentle retry; right → park-in + viewing budget.
- Parent: grant visa + allowlist → play only after entry success.
- Record residual gaps (audio stub, D9 pack).

### P3-2 — Reviewed pack + Cantonese audio (after D9 Confirm)

- Only after parent Confirms D9: attach reviewed media / audio; never invent IDs earlier.

## Stop condition

Do not treat M3 as done until:

1. Two-picture entry works on child path with pen-usable targets;
2. Success unlocks viewing budget via existing RewardLedger D1 seam (exactly-once / assisted recorded);
3. Video remains behind visa + budget + allowlist (D8);
4. Cantonese audio status is honest (scaffold vs reviewed);
5. D9 / D6 / D10 are not invented;
6. Mac mini test + bundle + manual notes exist; and
7. Parent reviews the PR (this phase file does not authorize merge alone).

## Exit evidence

- Implementation commit(s) and changed-file list;
- VisaCoreChecks PASS banner including activity checks;
- Mac mini bundle/launch and Wacom notes;
- Explicit open-decision reminder (D9/D6/D10);
- Version **0.4.0**.
