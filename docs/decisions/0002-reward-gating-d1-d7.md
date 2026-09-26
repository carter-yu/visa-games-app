# ADR 0002 — Reward gating decisions D1–D7

Status: Confirmed starting policy for Phase 1 (M1)

## Context

M0 provides the native shell, durable local state boundary, and absolute visa expiry model. M1 needs a precise reward and viewing-budget contract before child tasks or media-provider work proceed. Carter Yu confirmed the starting points below on 2026-09-27.

These decisions define the family rules without inventing a new timer or allowance number. The easiest and hardest product goals remain 5 minutes and 20 minutes. The medium goal remains open under D6.

## Decisions

### D1 — First-video entry

The first video unlocks through a short entry activity and the configured initial allowance. The allowance is parent-configured; this ADR does not choose a numeric default. The entry activity is a controlled child-path gate, not a general browser or provider surface.

### D2 — Answering and viewing time are separate

Answering does not consume viewing time. The viewing budget is a separate balance from the active session deadline and from task-answer time. The absolute session deadline remains independently enforced.

### D3 — Exactly-once rewards and cap

A reward is awarded at most once for each stable completion ID. Duplicate delivery, relaunch, or replay of the same completion ID must not award again. Earned time does not carry over to the next day. A parent-set cap bounds the available reward/allowance balance; rewards above that cap are not banked for a later day.

### D4 — Prefer a fitting video and stop at the boundary

When more than one approved video is available, prefer one that fits within the remaining viewing budget. If no suitable choice fits, the child must not borrow from a later day. Playback stops when the viewing budget reaches zero or the independent session deadline expires, whichever comes first.

### D5 — One written playback/time policy

The following is the confirmed starting policy for M1; it is not an inferred reset rule:

- **Pause:** Explicit pause does not spend viewing budget. The same state resumes only while the session deadline and remaining budget still permit it.
- **Buffering:** Time reported as buffering, rather than eligible playback, does not spend viewing budget. If a provider cannot distinguish buffering from playback, that provider-specific limitation requires a later ADR rather than an inferred reset or free allowance.
- **Ads:** Ads shown inside an approved playback surface count against the viewing budget while they are playing. A provider that cannot expose or control this behavior requires a later provider ADR.
- **Seek:** Seeking backward never restores spent budget. Seeking forward does not award credit for unplayed content; budget accounting follows eligible playback actually observed by the player.
- **Sleep/wake:** Sleep pauses eligible playback accounting. On wake, re-evaluate the absolute session deadline, visa expiry, and remaining viewing budget. Sleep does not create a new allowance, reset the day, or extend a deadline.
- **Timezone/date boundary:** Store deadlines and reward timestamps as absolute instants. Crossing local midnight or changing timezone does not reset the balance and does not create next-day carryover.

The exact provider telemetry needed to enforce the buffering and ad rules may require a later media-provider ADR. Until then, tests use a deterministic playback seam and must not silently assume a reset.

### D7 — Language replay and assisted success

Replay in the other supported language is unpenalized and does not reduce the reward. An assisted success is recorded separately from an unassisted success so later reporting can distinguish them without changing this reward rule.

## Open decisions

D6, D8, D9, and D10 remain open. In particular, this ADR does not decide the medium-time product goal or any unrecorded provider, content, or reporting policy. Open decisions must not be inferred from this ADR.

## Consequences

- Reward application needs stable completion IDs and an atomic durable write.
- Viewing budget, answer time, and the absolute session deadline need separate state and tests.
- M1 can use a fake/local playback seam for deterministic evidence; YouTube and other provider integration remain out of scope.
- A later ADR may refine provider telemetry, but it must preserve the confirmed no-reset and no-next-day-carryover rules unless the parent explicitly changes them.
