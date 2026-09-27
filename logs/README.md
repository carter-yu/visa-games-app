# Local troubleshooting logs

Put Mac mini UAT notes, console captures, and temporary debug dumps here.
Tracked in git: this README only. Ignore `*.log` and other local dumps via `.gitignore`.

Do not commit secrets, tokens, or full screen recordings with private data.

## ScopedPlayer log files (v0.3.5+)

The app writes lightweight ScopedPlayer diagnostics (no secrets) to:

1. **Always:** `~/Library/Logs/VisaGames/scoped-player-YYYYMMDD.log`
2. **Also, when found:** this repo `logs/` directory (discovered by walking upward from the process cwd and the `.app` bundle until `logs/README.md` is present)
3. **Optional override:** environment variable `VISA_GAMES_LOG_DIR` (directory path)

Parent UI: **開啟日誌資料夾 / Open logs folder** opens the active directory (repo `logs/` when discoverable, otherwise `~/Library/Logs/VisaGames/`).

### Workshop Mac mini tip

From a checkout such as `/Users/carteryu/my-ai-projects/visa-games-app`, launching via `open ".build/Visa Games.app"` usually keeps a cwd/bundle walk that finds this folder. If not, either:

```sh
export VISA_GAMES_LOG_DIR="/Users/carteryu/my-ai-projects/visa-games-app/logs"
open ".build/Visa Games.app"
```

or symlink / copy from Library after a run:

```sh
open ~/Library/Logs/VisaGames
```

### Log line fields (examples)

- `load mode=htmlString videoID=… embed=… base=…`
- `nav allow|cancel … host+path …`
- `wk didFail|didFailProvisional domain=… code=…`
- `wk note possible Error 153 …` when the page title looks like a configuration error


## VisaGames app log files (v0.4.2+)

Entry / mode / reset diagnostics (no secrets) write to:

1. **Always:** `~/Library/Logs/VisaGames/visa-games-YYYYMMDD.log`
2. **Also, when found:** this repo `logs/` directory (same discovery as ScopedPlayer)
3. **Optional override:** `VISA_GAMES_LOG_DIR`

ScopedPlayer lines remain in `scoped-player-YYYYMMDD.log`. Parent **開啟日誌資料夾 / Open logs folder** opens the shared active directory (both file kinds may be present).

### Useful visa-games log lines (Traditional Chinese + English)

- `resetEntryActivity before|after — 重設前|後 entryCompleted=… rewardNil=…`
- `shell branch=lock-entry|lock-completed|play-entry|play-ready|parent — 介面分支 …`
- `returnToChild — 返回兒童 beforeMode=… afterMode=…`
- `seedTestViewingBudget — 測試觀看時間 …`
- `selectEntryOption correct|incorrect — 答對|答錯 …`
- `applyEntrySuccess — 入口成功 …`
- `storage load|save FAILED — 載入|儲存失敗 …`

## YouTube Error 153 troubleshooting

**Error 153 — Video player configuration error** often means the embed ran without a YouTube-acceptable HTTPS **Referer** / origin (common when WKWebView loads a bare `URLRequest` to `youtube-nocookie`).

This app loads an HTML shell via `loadHTMLString` with:

- iframe `src` = constructed `https://www.youtube-nocookie.com/embed/<id>?…`
- `referrerpolicy="strict-origin-when-cross-origin"`
- `baseURL` = `https://www.youtube-nocookie.com/`
- `mediaTypesRequiringUserActionForPlayback = []`

D8 still applies: only allowlisted ids; main frame is shell host-root or `/embed/<id>` on approved hosts; watch/search/other-id remain denied.

If Error 153 persists after v0.3.5:

1. Confirm offline checks PASS and the shell footer shows **v0.3.5**.
2. Open the logs folder and check `load mode=htmlString` (not a bare URL load).
3. Note residual YouTube chrome honestly; do not claim OS-level containment.
4. Capture title / nav cancel lines and share with the workshop (no secrets).
