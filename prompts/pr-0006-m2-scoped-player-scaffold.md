# PR #6 — M2 scoped player scaffold (D8)

| Field | Value |
| --- | --- |
| Date | 2026-09-27 (HK) |
| Branch | `feat/m2-scoped-player-scaffold` |
| Base | `origin/main` @ `cfc05d4` (theme PR #5 merged) |
| PR | (filled after `gh pr create`) |
| Model | Prefer `gpt-6-sol`; Astra only if WK kiosk boundary needs it |
| Goal | Start M2 scaffold: Confirmed D8 scoped official embed only; allowlist + PlaybackPolicy + ScopedPlayerView stub; tests; no merge |

## Constraints
- Language lock: engineering English; UI HK Traditional Chinese + English; **never** Simplified Chinese.
- Do **not** invent D6 / D9 / D10.
- No general browser / URL bar / unrestricted search on the child path.
- No Tomica / Takara / Thomas IP.
- Parent Carter Confirmed **1+4**: D8 = scoped official embed only.
- M1 reward model exists; **P1-3 / P1-4 may still be open** — do not claim M1 fully closed.
- Linux workshop has no Swift — Mac mini must compile/test.
- Branch from `origin/main`. **Do NOT merge.**

## Deliverables
1. `docs/decisions/0003-youtube-containment-d8.md` — Confirmed D8; residual OS/web risks honest.
2. `phases/phase-2-scoped-playback.md` — M2 scope, slices, stop condition; note M1 open slices.
3. Minimal Swift scaffold: `ApprovedVideo` / `VideoAllowlist`; `PlaybackPolicy`; `YouTubeEmbedURL` nocookie construction; `FakePlaybackEngine`; `ScopedPlayerView` (WKWebView, cancel user links); parent-only allowlist text field + grant/play stub.
4. Tests: allowlist reject unknown ID; budget/session stop; D8 rejects non-embed construction.
5. This prompts archive (sanitized).
6. `PROGRESS.md` facts; SemVer **MINOR 0.3.0** if family-visible player stub ships.
7. Open PR with `gh`; report URL + Mac mini test steps.

## Acceptance
- PR open against main; not merged.
- Offline checks include new scoped-playback suite.
- No claim of full M1 close or production YouTube clearance.

## Mac mini test notes
```sh
cd /Users/carteryu/my-ai-projects/visa-games-app
git fetch origin && git checkout feat/m2-scoped-player-scaffold && git pull --ff-only
sh scripts/test.sh
# Expect: PASS: 7 session + 8 reward-ledger + 7 reward-persistence + 6 theme-preference + 4 scoped-playback checks
sh scripts/bundle.sh
open ".build/Visa Games.app"
```
Parent: authenticate → add a valid 11-char YouTube video ID → Test viewing budget → Test 1-minute visa → Preview/Play allowlisted. Confirm lock/play child path has **no** URL text field. Footer **v0.3.0**. Note residual YouTube/WK chrome.

## Essential prompt text (sanitized)

> Repo `/workspace/visa-games-app` on main @ cfc05d4 (theme PR #5 merged). Parent Carter Confirmed 1+4: D8 = scoped official embed only (no general browser / URL bar / search). Start M2 scaffold. Branch `feat/m2-scoped-player-scaffold` from origin/main. Do NOT merge. Deliver ADR 0003, phase-2 doc, VisaCore ApprovedVideo/VideoAllowlist/PlaybackPolicy/youtube-nocookie helper + FakePlaybackEngine, VisaGames ScopedPlayerView WK stub, parent-only allowlist UI, tests, prompts archive, PROGRESS, honest MINOR 0.3.0. Constraints: language lock; no invent D6/D9/D10; no general browser; no Tomica IP; prefer gpt-6-sol; Linux no Swift — Mac mini must test. Open PR with gh; report URL + Mac mini test steps.
