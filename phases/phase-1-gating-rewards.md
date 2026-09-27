# Phase 1 — M1 durable gating and rewards

Phase 1 turns the confirmed family rules into a durable, testable gating and reward model. It is the smallest slice that can unlock approved viewing without making a reward disappear across relaunch, sleep, or ordinary clock changes.

M0 (Phase 0) is recorded as **Reported** at main commit `7c18c65`. M0 acceptance is not re-opened by this phase; this phase adds the reward and viewing-budget layer above the native shell.

## Scope

- A durable model for the configured initial allowance, earned reward, parent-set cap, completion IDs, viewing budget, and the active session deadline.
- The first-video path: a short entry activity followed by the configured initial allowance.
- Exactly-once reward application by completion ID, including duplicate-delivery protection.
- A separate viewing budget that is not consumed by answering and is bounded by the active session deadline.
- Selection of an approved video that fits the remaining budget where possible, with playback stopped at the budget boundary.
- One explicit starting policy for pause, buffering, ads, seeking, sleep, and timezone behavior (ADR 0002).
- Persistence, relaunch normalization, and deterministic tests for the model. Provider integration is not required for this phase.

## Out of scope

- YouTube or any other media-provider integration, provider authentication, ads SDK work, or general browser surface.
- The full child task catalog, skins, cloud sync, accounts, analytics, LLM teacher, or remote administration.
- New timer values or a replacement for the existing absolute `endsAt` visa model.
- Resolving D6, D9, or D10. (D8 is Confirmed separately in ADR 0003 / Phase 2; this phase still does not implement provider playback.)
- Claiming M2 or media integration complete.

## Starting policy

The rules in ADR 0002 are the confirmed starting policy for M1. They intentionally do not invent a new allowance or timer number. The easiest and hardest product goals remain 5 minutes and 20 minutes respectively; the medium goal and any provider-specific implementation detail remain open where noted.

## Slices

### P1-0 — Policy, state contract, and test fixtures

- Land ADR 0002 and name the durable records and invariants.
- Define stable completion IDs, the configured initial allowance, reward balance, parent-set cap, viewing budget, and session deadline as separate concepts.
- Add deterministic clock and playback/test seams without connecting a provider.
- Write fixtures for first entry, duplicate completion, relaunch, sleep/wake, and timezone transitions.

### P1-1 — Reward model and tests

- Implement the pure reward decision/application model behind tests.
- Unlock the first video through the short entry activity and configured initial allowance.
- Apply a completion reward at most once for each completion ID, enforce the parent-set cap, and reject next-day carryover.
- Record assisted success separately from unassisted success; language replay must not reduce the reward.

This is the next implementation task. It must not add YouTube or another provider.

### P1-2 — Durable gating and session accounting

- Persist reward and allowance state atomically with the existing local state boundary.
- Keep answering time separate from viewing budget; enforce the existing absolute session deadline independently.
- Normalize stale or expired state on relaunch, wake, and clock changes without inferring a reset or creating a new allowance.
- Add failure-path tests for invalid, duplicated, capped, and partially written state.

### P1-3 — Budget-aware approved-video boundary

- Represent parent-approved videos with a duration/budget-fit value and choose a video that fits the remaining viewing budget where possible.
- Stop at the budget boundary rather than borrowing from the next day or the session deadline.
- Apply the ADR 0002 pause, buffering, ad, seek, sleep, and timezone rules through a deterministic playback seam.
- Keep the provider surface out of this phase; a fake or local playback source is sufficient for evidence.

### P1-4 — Parent configuration and M1 evidence

- Expose only the parent-controlled configuration needed for the initial allowance, cap, approved-video set, and policy-visible state.
- Exercise the child path, relaunch, sleep/wake, duplicate completion, cap, boundary, and assisted-success cases on the target configuration.
- Record test commands, environment, outcomes, and any policy gaps. Do not record unrun checks as passing.

## Stop condition

Do not proceed to provider/media integration, broader child tasks, or M2 work until P1-0 through P1-4 have evidence showing that:

1. the first-video unlock follows the configured initial allowance;
2. reward application is durable, exactly once per completion ID, capped, and has no next-day carryover;
3. language replay is unpenalized and assisted success is separately recorded;
4. answering does not spend viewing budget, while the independent absolute session deadline is enforced;
5. an approved video is selected to fit the budget when possible and playback stops at the boundary;
6. the ADR 0002 edge-case policy is implemented and tested for pause, buffering, ads, seeking, sleep, and timezone changes; and
7. state survives relaunch and invalid or partial state fails safely.

A target-device run and reproducible test output are required for exit evidence. M1 evidence does not authorize or imply YouTube integration or M2 completion.

## Exit evidence

The phase exit record must include:

- the implementation commit and list of changed files;
- deterministic unit/offline test output for every invariant above;
- target Mac acceptance results, including relaunch and sleep/wake observations;
- the configured parent values used for the run, without inventing values not approved by the parent;
- explicit evidence that no Swift/app version or unrelated app behavior changed; and
- a list of any remaining open decisions, especially D6, D9, and D10 (D8 tracked in ADR 0003).
