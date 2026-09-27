# ADR 0004 — First learning loop (M3 scaffold)

Status: Proposed implementation for Phase 3 (M3) scaffold — parent review of this PR; **D9 / D6 / D10 remain open**

## Context

M0 owns the native kiosk shell. M1 (ADR 0002) owns reward / viewing-budget rules (D1–D5, D7 Confirmed). M2 (ADR 0003) owns D8 scoped YouTube embed containment. Carter Yu directed the workshop to **merge M2 and start the first game** (PR #6 merged to main @ `53e5f29`, v0.3.5), with UI polish deferred.

M3 exit (manager) asks for: one reviewed pack, Cantonese audio, two-picture question, feedback, next-video gate, pen-usable targets. This ADR records what the **scaffold** may ship now versus what still waits on open decisions.

## Decisions (scaffold scope)

### First child activity

The first child-path activity is a **two-picture choice** entry gate with large hit targets suitable for Wacom pen / finger. Prompt and labels are **Hong Kong Traditional Chinese + English** only — never Simplified Chinese. Options use existing original `VehicleSilhouette` asset IDs (e.g. crane truck vs articulated bus). **No Tomica / Takara / Thomas trademarks**, logos, faces, or names.

### Reward unlock (D1 + D7)

On correct selection:

1. Call existing `RewardLedger.completeEntryActivity` so the configured initial allowance unlocks once (ADR 0002 D1).
2. Record assisted vs unassisted via `applyCompletion` with the activity’s stable `completionID` and **zero extra reward seconds** (D7 recording without inventing a second grant). Hint used ⇒ assisted.
3. Wrong answers are a gentle retry only — no invented penalty beyond D7’s recording model.
4. Viewing budget remains separate from answering time and from absolute visa `endsAt`. Play / allowlisted video still requires existing `PlaybackPolicy` (visa + budget + parent allowlist). This ADR does **not** invent new timer numbers.

### Cantonese audio

Cantonese / bilingual prompt audio is **scaffold only** (`ActivityAudioPrompting` + `StubActivityAudioPrompt`). Optional system speech may be added later if trivial; a full reviewed audio pack **waits on D9 Confirm**. Do not claim “audio done.”

### Success feedback

Success may reuse the existing `SuccessParkAnimation` park-in delight. No new media provider work is authorized here.

## Explicitly open (do not invent)

| ID | Topic | Scaffold rule |
|----|--------|----------------|
| **D9** | Reviewed YouTube / content pack (candidate #7, #9 backup proposed elsewhere) | Candidates are **not** in-repo as approved. Do **not** hardcode unverified YouTube IDs as an “approved pack.” Parent allowlist remains manual. |
| **D6** | Medium product goal minutes | Do not invent. |
| **D10** | Reporting policy | Do not invent. |

D8 remains Confirmed in ADR 0003. D1–D5 / D7 remain Confirmed in ADR 0002.

## Consequences

- VisaCore gains pure `TwoPictureQuestion` / `ActivityEvaluator` / `FirstEntryActivity` types and tests.
- VisaGames replaces the lock-mode “activities coming later” placeholder with the entry gate; play mode also gates video until entry completion (先做再玩).
- Version bumps to **0.4.0** (MINOR — family-visible first learning loop).
- Parent controls should note that the entry game is live and that YouTube pack review remains D9.
- Mac mini UAT remains required before merge; Linux workshop hosts may lack Swift.
