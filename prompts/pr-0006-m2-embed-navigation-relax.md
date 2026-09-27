# PR #6 continuation — Relax WK embed navigation (Link blocked D8)

| Field | Value |
| --- | --- |
| Date | 2026-09-27 (HK) |
| Branch | `feat/m2-scoped-player-scaffold` |
| PR | https://github.com/carter-yu/visa-games-app/pull/6 (OPEN) |
| Version | 0.3.3 (PATCH) |
| Model | Prefer `gpt-6-sol` (containment tweak) |

## Bug (Carter Reported Mac mini UAT 2026-09-27)

`sh scripts/test.sh` PASS **8+8+7+6+5**; `bundle.sh` OK on `feat/m2-scoped-player-scaffold` @ `327d6dd`.
Real play fails with **「已阻擋連結。 / Link blocked (D8).」** — cannot watch the video.

## Root cause

WK navigation policy in `ScopedPlayerView` was too strict and stopped playback (`onNavigationRejected` → `stopScopedPlayback(.navigationRejected)`) on events YouTube’s official embed needs:

1. Main-frame checks only `youtube-nocookie.com` — redirects to `www.youtube.com/embed/<id>` were cancelled.
2. `navigationType == .linkActivated` always cancelled and called `onNavigationRejected`.
3. `createWebViewWith` called `onNavigationRejected` even when returning nil.
4. `about:blank` / nil URL edge cases could trip main-frame deny.

ADR 0003 still forbids general browsing / URL bar / arbitrary watch pages. Residual provider chrome is accepted — do not over-claim OS security.

## Codex prompt (sanitized)

> Language lock: engineering English only in code/docs/commits; UI strings Hong Kong Traditional Chinese + English; never Simplified Chinese.
>
> Repo `/workspace/visa-games-app` on branch `feat/m2-scoped-player-scaffold` (PR #6 open). Fix Carter UAT bug: Preview play shows 「已阻擋連結。 / Link blocked (D8).」 because ScopedPlayerView stops playback on official YouTube embed redirects and in-player chrome.
>
> Implement the smallest authorized slice:
> 1. Add VisaCore `isAllowedEmbedMainFrameURL(_:videoID:)` allowing https only, hosts `www.youtube-nocookie.com` / `youtube-nocookie.com` / `www.youtube.com` / `youtube.com` / `m.youtube.com`, path `/embed/<exact-11-char-id>` for this videoID only. Add `isBenignBlankURL` for about:blank. Keep constructing loads via nocookie `make(videoID:)`. Do not allow arbitrary https main-frame navigation.
> 2. ScopedPlayerView Coordinator: allow main-frame allowed embed or about:blank; only call `onNavigationRejected` for real escapes; linkActivated allow only matching embed else quiet cancel (stop only for clear main-frame escape); createWebViewWith return nil without stopping; subframes allow https, quiet-deny non-https.
> 3. Tests for allow/reject main-frame cases; update PASS banner if count changes.
> 4. Version bump **0.3.3** / CFBundleVersion 7; PROGRESS.md; ADR 0003 tiny note on same-id embed redirects; archive this prompt; add `logs/README.md` + gitignore `logs/*` except README. Do NOT merge. Commit and push the same PR #6 branch.
>
> Constraints: no merge; no Simplified Chinese; no invent reward policy; residual chrome honesty; prefer gpt-6-sol.

## Mac mini re-UAT

```sh
cd /Users/carteryu/my-ai-projects/visa-games-app
git fetch origin && git checkout feat/m2-scoped-player-scaffold && git pull --ff-only
sh scripts/test.sh
sh scripts/bundle.sh
open ".build/Visa Games.app"
```

Parent: Preview allowlisted → video should play (not Link blocked). Note residual YouTube chrome honestly. Still do not merge until Carter OK.
