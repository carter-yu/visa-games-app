# PR #6 continuation — Parent window and YouTube URL paste

| Field | Value |
| --- | --- |
| Date | 2026-09-27 (HK) |
| Branch | `feat/m2-scoped-player-scaffold` |
| PR | https://github.com/carter-yu/visa-games-app/pull/6 (OPEN) |
| Version | 0.3.1 (PATCH) |

## Codex prompt (sanitized)

> Continue the existing PR #6 branch. Implement the smallest Parent UX slice confirmed by Carter: make Parent controls a normal resizable and minimizable macOS window so a parent can copy a YouTube URL from a browser, and extract the 11-character video ID from a bare ID or standard YouTube watch, share, and embed URLs. Switching apps while Parent is active must not return to child; returning to child must restore borderless full-screen kiosk presentation. Screen changes must not override Parent resizing. Keep the existing parent deadline, sleep behavior, D8 embed-only child navigation policy, and no child URL/search/browser surface. Add accepted and rejected parser cases to VisaCoreChecks. Bump Info.plist and shell footer to 0.3.1 / build 5. Update PROGRESS with factual verification status and exact Mac mini re-UAT steps. Use engineering English and Hong Kong Traditional Chinese plus English UI. Do not invent reward or timer policy, claim Mac mini or N1–N9 completion, merge, or open a new PR. Commit and push the existing branch.

## Mac mini re-UAT

```sh
cd /Users/carteryu/my-ai-projects/visa-games-app
git fetch origin
git checkout feat/m2-scoped-player-scaffold
git pull --ff-only
sh scripts/test.sh
# Expect: PASS: 7 session + 8 reward-ledger + 7 reward-persistence + 6 theme-preference + 5 scoped-playback checks
sh scripts/bundle.sh
open ".build/Visa Games.app"
```

In Parent mode, resize and minimize the window, switch to Safari or Chrome, copy a watch or share URL, restore the app, paste the URL, and add it to the allowlist. Confirm the Parent controls remain available until the existing two-minute deadline. Return to child and confirm borderless full-screen presentation with no URL bar or search. Record actual target-device results and residual OS escape paths before any Mac mini acceptance claim.
