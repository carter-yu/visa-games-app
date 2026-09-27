# PR #6 continuation — Error 153 embed Referer + ScopedPlayer logs

| Field | Value |
| --- | --- |
| Date | 2026-09-27 (HK) |
| Branch | `feat/m2-scoped-player-scaffold` |
| PR | https://github.com/carter-yu/visa-games-app/pull/6 (OPEN) |
| Version | 0.3.4 (PATCH) |
| Model | Prefer `gpt-6-sol` / astra for WK; workshop executor applied |

## Bug (Carter Reported Mac mini UAT 2026-09-27)

`sh scripts/test.sh` PASS **8+8+7+6+6**; `bundle.sh` OK @ `08c304c`.
Real Preview play shows YouTube **Error 153 — Video player configuration error** (often missing/invalid Referer when WKWebView loads bare `URLRequest` to youtube-nocookie).

Also requested: write ScopedPlayer troubleshooting logs under repo `logs/` (gitignore `logs/*` except README) with a parent affordance to open the folder.

## Fix (smallest authorized slice)

1. Prefer `loadHTMLString` HTML shell wrapping official iframe to `https://www.youtube-nocookie.com/embed/<id>?…` with `referrerpolicy="strict-origin-when-cross-origin"`, meta referrer, and `baseURL` `https://www.youtube-nocookie.com/`.
2. Enable `mediaTypesRequiringUserActionForPlayback = []`.
3. Keep D8: allowlisted id only; main frame = nocookie shell host-root **or** `/embed/<id>` on approved hosts; watch/search/other-id denied; HTTPS subframes allowed for player internals.
4. Dual-path logging: always `~/Library/Logs/VisaGames/scoped-player-YYYYMMDD.log`; also repo `logs/` when `logs/README.md` found walking up from cwd/bundle; optional `VISA_GAMES_LOG_DIR`. Parent button **開啟日誌資料夾 / Open logs folder**.
5. Version **0.3.4** / CFBundleVersion 8; PROGRESS; ADR 0003 note; update `logs/README.md`. Do **NOT** merge. Push same PR #6 branch.

## Codex prompt (sanitized)

> Language lock: engineering English only in code/docs/commits; UI strings Hong Kong Traditional Chinese + English; never Simplified Chinese.
>
> Repo on `feat/m2-scoped-player-scaffold` (PR #6). Fix Error 153 via loadHTMLString iframe+referrerpolicy+nocookie baseURL; add ScopedPlayer dual-path logs + Open logs folder; bump 0.3.4; archive this prompt. No merge.

## Mac mini re-UAT

```sh
cd /Users/carteryu/my-ai-projects/visa-games-app
git fetch origin && git checkout feat/m2-scoped-player-scaffold && git pull --ff-only
sh scripts/test.sh
sh scripts/bundle.sh
open ".build/Visa Games.app"
```

Expect PASS **8+8+7+6+7**. Parent: Preview allowlisted → video should play without Error 153. Use **開啟日誌資料夾 / Open logs folder** if needed. Note residual YouTube chrome honestly. Still do not merge until Carter OK.
