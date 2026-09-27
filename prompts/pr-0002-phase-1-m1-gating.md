# PR #2 — Phase 1 M1 gating docs

> **Reconstruction notice:** This file is **reconstructed** from parent chat + `PROGRESS.md` / ADR 0002 / `phases/phase-1-gating-rewards.md`. It is **not** a verbatim copy of a live-archived filesystem original. Sanitize and treat as engineering intent, not a chat dump.

| Field | Value |
| --- | --- |
| Date | 2026-09-27 (HK) |
| Branch | `docs/phase-1-m1-gating` |
| PR | https://github.com/carter-yu/visa-games-app/pull/2 (MERGED) |
| Model | Luna / docs preferred (workshop Codex acceptable for docs-only) |
| Goal | Record parent **Confirmed** accept of all Proposed D1–D5 and D7; land Phase 1 plan + ADR 0002 + PROGRESS update. Documentation only. |

## Constraints
- Documentation only: create `phases/phase-1-gating-rewards.md`, `docs/decisions/0002-reward-gating-d1-d7.md`, and update `PROGRESS.md`.
- **No Swift**, no app version, no behavior changes.
- Do **not** invent D6, D8, D9, or D10 — leave them explicitly open.
- Do not add YouTube / media / UI; do not claim M2 or media integration done.
- Language lock: engineering English + HK Traditional Chinese UI only (never Simplified Chinese).
- Open the PR; do not invent merge authority beyond opening the PR for parent review.

## Deliverables
1. `phases/phase-1-gating-rewards.md` — M1 scope, out-of-scope, starting policy, slices P1-0…P1-4, stop condition, exit evidence. Note M0 Reported at main `7c18c65`.
2. `docs/decisions/0002-reward-gating-d1-d7.md` — Confirmed starting policy for D1–D5 and D7; open list for D6/D8–D10.
3. `PROGRESS.md` — facts: M0 Reported; D1–D5/D7 Confirmed; next task P1-1 reward model + tests.

## Essential decision list (paste into ADR; Confirmed)

### D1 — First-video entry
The first video unlocks through a short entry activity and the configured initial allowance. The allowance is parent-configured; this ADR does not choose a numeric default. The entry activity is a controlled child-path gate, not a general browser or provider surface.

### D2 — Answering and viewing time are separate
Answering does not consume viewing time. The viewing budget is a separate balance from the active session deadline and from task-answer time. The absolute session deadline remains independently enforced.

### D3 — Exactly-once rewards and cap
A reward is awarded at most once for each stable completion ID. Duplicate delivery, relaunch, or replay of the same completion ID must not award again. Earned time does not carry over to the next day. A parent-set cap bounds the available reward/allowance balance; rewards above that cap are not banked for a later day.

### D4 — Prefer a fitting video and stop at the boundary
When more than one approved video is available, prefer one that fits within the remaining viewing budget. If no suitable choice fits, the child must not borrow from a later day. Playback stops when the viewing budget reaches zero or the independent session deadline expires, whichever comes first.

### D5 — One written playback/time policy
Confirmed starting policy (not an inferred reset rule):
- **Pause:** Explicit pause does not spend viewing budget. Same state resumes only while session deadline and remaining budget still permit it.
- **Buffering:** Buffering (vs eligible playback) does not spend viewing budget. If a provider cannot distinguish buffering from playback, that needs a later ADR — do not infer a reset or free allowance.
- **Ads:** Ads inside an approved playback surface count against viewing budget while playing. Uncontrollable provider behavior needs a later provider ADR.
- **Seek:** Seeking backward never restores spent budget. Seeking forward does not award credit for unplayed content; budget follows eligible playback actually observed.
- **Sleep/wake:** Sleep pauses eligible playback accounting. On wake, re-evaluate absolute session deadline, visa expiry, and remaining viewing budget. Sleep does not create a new allowance, reset the day, or extend a deadline.
- **Timezone/date boundary:** Store deadlines and reward timestamps as absolute instants. Crossing local midnight or changing timezone does not reset the balance and does not create next-day carryover.

### D7 — Language replay and assisted success
Replay in the other supported language is unpenalized and does not reduce the reward. An assisted success is recorded separately from an unassisted success so later reporting can distinguish them without changing this reward rule.

### Open (do not invent)
D6, D8, D9, and D10 remain open (including the medium-time product goal and any unrecorded provider/content/reporting policy).

## Essential prompt text (sanitized, reconstructed)

> Parent Confirmed: accept all Proposed **D1–D5 and D7** as starting Phase 1 / M1 policy. D6 and D8–D10 stay open.
>
> On branch `docs/phase-1-m1-gating`, docs-only:
> 1. Create `phases/phase-1-gating-rewards.md` with M1 durable gating/rewards plan (P1-0 through P1-4), stop condition, and exit evidence. M0 is Reported at main `7c18c65` and is not re-opened.
> 2. Create `docs/decisions/0002-reward-gating-d1-d7.md` spelling out each Confirmed decision above; call out open D6/D8–D10; easiest/hardest product goals remain 5 and 20 minutes; medium goal stays under open D6 — do not invent numbers.
> 3. Update `PROGRESS.md`: M0 Reported; D1–D5/D7 Confirmed; next task = P1-1 reward model + tests. Do not add YouTube or mark M2/media done.
>
> No Swift. Open the PR for parent review. Language lock: engineering English; never Simplified Chinese.

## Verification
- `git diff --check` clean.
- No `Sources/` / `Tests/` / version bumps in the PR.
