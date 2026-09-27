# Phase 2 — M2 scoped official embed playback

Phase 2 scaffolds the **D8-contained** playback surface: parent allowlisted video IDs only, official embed construction only, no general browser. It sits on top of the M1 reward / viewing-budget model without claiming that every M1 slice is closed.

## Relationship to M1

- M1 reward model (P1-1) and durable persistence (P1-2) exist on main.
- **P1-3** (budget-aware approved-video boundary) and **P1-4** (parent configuration + M1 evidence) **may still be open**. Do **not** claim M1 fully closed in this phase.
- M2 may scaffold the player **behind an allowlist** and a `PlaybackPolicy` seam that applies ADR 0002 budget/session stop rules. Completing P1-3/P1-4 evidence remains a separate obligation.

## Scope

- ADR 0003: Confirmed D8 containment (scoped official embed; allowlist IDs; no URL bar / unrestricted search / arbitrary navigation; stop on budget or session expiry; residual risks documented).
- VisaCore types: `ApprovedVideo`, `VideoAllowlist`, embed-URL construction helpers that reject non-embed / arbitrary URLs, and `PlaybackPolicy` (allowlist + ADR 0002 stop).
- Deterministic `FakePlaybackEngine` (and a playback protocol) for offline tests.
- VisaGames: `ScopedPlayerView` stub using `WKWebView` only with a tightly constructed `youtube-nocookie` embed URL for an allowlisted ID; cancel user link navigation as far as WK allows.
- Parent-only UI: list/add allowlisted video IDs (text field on **parent path only**); grant/play stub when policy allows.
- Offline tests: allowlist rejects unknown ID; budget/session stop; D8 helper rejects non-embed construction.
- Family-visible stub → honest MINOR version bump when the player surface ships in the app shell.

## Out of scope

- General browser, URL bar, unrestricted YouTube search, or child text inputs.
- Inventing D6, D9, or D10.
- Tomica / Takara / Thomas IP, logos, faces, or names.
- Claiming full M1 exit evidence or production YouTube policy clearance.
- Merging to main without parent UAT on the Mac mini.
- Full ads SDK, provider OAuth, cloud sync, or LLM teacher.

## Slices

### P2-0 — ADR, phase file, and policy seams (this scaffold)

- Land ADR 0003 and this phase file.
- Land allowlist + embed URL + `PlaybackPolicy` + FakePlaybackEngine + tests.
- Land ScopedPlayerView stub + parent allowlist/play stub UI + version bump.
- Stop before claiming live provider UAT complete.

### P2-1 — Mac mini compile, offline checks, and residual WK evidence

- Run `sh scripts/test.sh` and `sh scripts/bundle.sh` on the target Mac mini.
- Launch the app; parent-add an allowlisted ID; confirm child path has no URL field; exercise stop-on-budget/session with the fake or stub path.
- Record residual YouTube/WK chrome and OS escape paths honestly.

### P2-2 — Budget-fit selection wired to durable allowlist (after / with P1-3)

- Prefer an allowlisted video that fits remaining viewing budget (ADR 0002 D4).
- Persist parent allowlist with the durable config boundary when P1-3/P1-4 land; do not invent schema here beyond the scaffold store.

### P2-3 — Hardening and stop evidence

- Tighten WK navigation denials, document remaining provider UI, and record M2 stop evidence without overclaiming OS security.

## Stop condition

Do not treat M2 as done until:

1. Child playback can start only for an allowlisted ID via constructed embed URL;
2. Arbitrary / non-embed URL construction is rejected in tests;
3. Playback stops when viewing budget is exhausted or the session deadline expires;
4. Parent-only allowlist editing is authenticated; child path has no URL bar or search;
5. Mac mini has reproducible test + bundle + manual containment notes; and
6. Residual OS/web risks remain listed (not waved away).

M2 scaffold merge readiness still requires parent review; this phase file does not authorize merge by itself.

## Exit evidence

- Implementation commit(s) and changed-file list;
- Offline VisaCoreChecks output including new M2 checks;
- Mac mini bundle/launch notes and residual risk observations;
- Explicit statement of M1 slice status (what is done vs P1-3/P1-4 still open);
- Version number for the family-visible stub.
