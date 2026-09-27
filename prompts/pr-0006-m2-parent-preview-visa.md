# PR #6 continuation — Parent preview auto-ensures visa + budget

| Field | Value |
| --- | --- |
| Date | 2026-09-27 (HK) |
| Branch | `feat/m2-scoped-player-scaffold` |
| PR | https://github.com/carter-yu/visa-games-app/pull/6 (OPEN) |
| Version | 0.3.2 (PATCH) |
| Model | Prefer `gpt-6-sol` (UX/session seam) |

## Bug (Carter Reported 2026-09-27 UAT)

Cannot preview allowlisted video from Parent controls — always "簽證已到期 / Visa expired".

## Root cause

1. `PlaybackPolicy.evaluateStart` requires `sessionEndsAt > now`. Nil/expired → `.sessionExpired`.
2. Parent button "試播准許影片" calls `playAllowlisted` while `mode == .parent`, which passes `session.snapshot.endsAt`. If parent never granted, or 1-minute visa expired while pasting URLs, preview fails.
3. `Session.grant(seconds:now:)` sets `endsAt` **and forces `mode = .play`**, leaving Parent UI — so the documented UAT path "Test 1-minute visa then Preview" actually kicks the parent out of Parent controls. Existing SessionTests expect grant→play; do NOT break that contract for the child-start path.
4. Parent session auto-locks after **120s** (`parentDeadline`) — too short for browser copy-paste UAT; optionally extend.

## Codex prompt (sanitized)

> Language lock: engineering English only in code/docs/commits; UI strings Hong Kong Traditional Chinese + English; never Simplified Chinese.
>
> Repo `/workspace/visa-games-app` on branch `feat/m2-scoped-player-scaffold` (PR #6 open). Fix Carter UAT bug: Parent "試播准許影片 / Preview allowlisted" always shows "簽證已到期 / Visa expired" because `PlaybackPolicy.evaluateStart` needs `endsAt > now`, and parent Preview does not ensure a visa without calling `Session.grant` (which leaves `.parent` for `.play`).
>
> Implement the smallest authorized slice:
> 1. Add `Session.extendVisaKeepingParent(seconds:now:)` (or `ensureVisaDeadline`) that requires `mode == .parent` and `configured`, sets `snapshot.endsAt = now + seconds` (clamp ≤ 3600 like grant), and **does not** change mode away from `.parent`.
> 2. In `AppModel.playAllowlisted` when `session.mode == .parent`: if viewing budget ≤ 0, seed the same path as `seedTestViewingBudget()`; if `endsAt` is nil or ≤ now, call the new helper with ~600s (10 minutes, or at least 300s); refresh `parentDeadline` on successful parent preview; then evaluateStart / set `activePlayVideoID`. Keep child path and `AppModel.grant()` → `Session.grant` → `.play` unchanged.
> 3. Confirm ScopedPlayerView already embeds under parent allowlist when `activePlayVideoID != nil`; fix only if missing.
> 4. Extend `parentDeadline` on unlock (and refresh on successful parent preview) to **at least 600s**. Update Parent UI string from "兩分鐘後自動鎖定 / Locks automatically after two minutes" to match (e.g. "十分鐘後自動鎖定 / Locks automatically after ten minutes").
> 5. Unit test: ensureVisaKeepingParent sets endsAt and stays `.parent`; grant still goes to `.play`. Prefer pure VisaCore. Optionally scoped/app-level: parent preview path can start when endsAt was nil after ensure helper. Update PASS banner if new session checks added (was 7+8+7+6+5).
> 6. Version bump **0.3.2** / CFBundleVersion 6 in Info.plist + shell footer. Update PROGRESS.md factually (Linux no Swift — do not claim Mac mini PASS). Archive this prompt. Do NOT merge. Do NOT invent new reward policy beyond scaffolding helpers already used by `seedTestViewingBudget`. Commit and push the same PR #6 branch.
>
> Constraints: no merge; no Simplified Chinese; no fake N1–N9; prefer gpt-6-sol.

## Mac mini re-UAT

```sh
cd /Users/carteryu/my-ai-projects/visa-games-app
git fetch origin && git checkout feat/m2-scoped-player-scaffold && git pull --ff-only
sh scripts/test.sh
sh scripts/bundle.sh
open ".build/Visa Games.app"
```

Parent: add allowlisted URL → tap Preview **without** needing Test 1-minute visa first → player should appear in parent window; no "visa expired". Optional: still try Test 1-minute visa (should leave to play mode as before).
