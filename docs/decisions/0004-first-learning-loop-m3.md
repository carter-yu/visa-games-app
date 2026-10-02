# ADR 0004 — First learning loop (M3 scaffold)

Status: Proposed implementation for Phase 3 (M3) scaffold — parent review of this PR; **D9 / D10 remain open**; practical D6 Confirmed for this scaffold

## Context

M0 owns the native kiosk shell. M1 (ADR 0002) owns reward / viewing-budget rules (D1–D5, D7 Confirmed). M2 (ADR 0003) owns D8 scoped YouTube embed containment. Carter Yu directed the workshop to **merge M2 and start the first game** (PR #6 merged to main @ `53e5f29`, v0.3.5), with UI polish deferred.

M3 exit (manager) asks for: one reviewed pack, Cantonese audio, two-picture question, feedback, next-video gate, pen-usable targets. This ADR records what the **scaffold** may ship now versus what still waits on open decisions.

## Decisions (scaffold scope)

### First child activity

The first child-path activity is a **two-picture choice** entry gate with large hit targets suitable for Wacom pen / finger. Prompt and labels are **Hong Kong Traditional Chinese + English** only — never Simplified Chinese. Options use existing original `VehicleSilhouette` asset IDs (e.g. crane truck vs articulated bus). **No Tomica / Takara / Thomas trademarks**, logos, faces, or names.

### Reward unlock (D1 + D7)

On correct selection:

1. Call existing `RewardLedger.completeEntryActivity` so the configured initial allowance unlocks once (ADR 0002 D1).
2. Record assisted vs unassisted via `applyCompletion` with a round-unique UUID completion ID and **selected minutes × 60 reward seconds**, subject to the existing viewing cap. Hint used ⇒ assisted.
3. Wrong answers are a gentle retry only — no invented penalty beyond D7’s recording model.
4. Viewing budget remains separate from answering time and from absolute visa `endsAt`. Play / allowlisted video still requires existing `PlaybackPolicy` (visa + budget + parent allowlist). The child starts the selected visa through `Session.startPlayVisa`; parent-only `grant` remains separate.

### Cantonese audio

Cantonese / bilingual prompt audio is **scaffold only** (`ActivityAudioPrompting` + `StubActivityAudioPrompt`). Optional system speech may be added later if trivial; a full reviewed audio pack **waits on D9 Confirm**. Do not claim “audio done.”

### Success feedback

Success may reuse the existing `SuccessParkAnimation` park-in delight. No new media provider work is authorized here.

## Explicitly open (do not invent)

| ID | Topic | Scaffold rule |
|----|--------|----------------|
| **D9** | Reviewed YouTube / content pack (candidate #7, #9 backup proposed elsewhere) | Candidates are **not** in-repo as approved. Do **not** hardcode unverified YouTube IDs as an “approved pack.” Parent allowlist remains manual. |
| **D6** | Scaffold difficulty minutes | Carter Confirmed 2026-10-02: **5 / 10 / 15** (supersedes 2026-09-27 10/20/30 scaffold). |
| **D10** | Reporting policy | Do not invent. |

D8 remains Confirmed in ADR 0003. D1–D5 / D7 remain Confirmed in ADR 0002.

## Consequences

- VisaCore gains pure `TwoPictureQuestion` / `ActivityEvaluator` / `FirstEntryActivity` types and tests.
- Lock shows difficulty cards, then the two-picture task. In-session round state controls the UI independently of the durable D1 flag. Expiry clears round selection, hint/retry, and active video; the cards return.
- Version bumps to **0.5.0** (MINOR — family-visible first learning loop).
- Parent controls should note that the entry game is live and that YouTube pack review remains D9.
- Mac mini UAT remains required before merge; Linux workshop hosts may lack Swift.

## Confirmed child flow, v0.5.0

Evidence: Carter Yu explicitly Confirmed in the 2026-09-27 PR #7 task that the
visa-games reference flow is cards → task → visa → approved YouTube, with
Easy / Medium / Challenge at **5 / 10 / 15 minutes** (300 / 600 / 900 seconds; Carter 2026-10-02).
This closes practical D6 for this scaffold. No reference-repository inspection
or Mac UAT is implied by that evidence label.

The D1 initial allowance still unlocks once. Each successful round independently
records D7 and requests its selected viewing seconds. The existing default cap
is 1200 seconds: Challenge has a 900-second visa (well under the bank cap);
Medium can also have its incremental award reduced by existing banked seconds.
The initial 60-second D1 allowance remains additional subject to the same cap.
Visa and reward state persist atomically in schema 2; unfinished rounds are
intentionally in-session only. A restored active visa resumes the play surface.
The current scoped player still lacks provider-driven viewing-time accounting
(P1-3/P1-4 follow-up); this change preserves PlaybackPolicy's positive-budget
check and absolute visa expiry and does not claim full budget metering.

No approved pack IDs were added. D9 and reviewed audio remain pending. OS escape
paths remain those in `docs/phase-0-kiosk-checklist.md`; app kiosk controls do not
replace macOS device policy. M3 completion awaits Mac mini UAT.
