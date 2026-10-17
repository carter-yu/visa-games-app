# 0016 — Parent in-app YouTube finder (option A)

Status: proposed (v0.27.0 / 59; aligned with the design in v0.27.1 / 60). Carter chose
option A on 2026-10-17 (20:00 HKT) and approved every bold default in the design notes
(D1–D17, mockups 00–10). D15: favourite channels and RSS (option E) are phase 2.

## Context
Since ADR 0011 the parent page is part of the constant kiosk presentation. A parent can't
switch to Safari to copy a YouTube link while parent settings are open. Bringing back a
movable or resizable parent window would mean AppKit window changes on parent enter and exit.
That is exactly what crashed on macOS 27.

## Decision
- **A finder inside the parent view (D1).** A yellow 「喺 YouTube 搵片 / Find on YouTube」
  button with a 「新 NEW」 tag sits next to the allowlist paste field (the paste field stays as
  the fallback). It opens `ParentYouTubeBrowserView` as a full-page layer in
  `ParentSettingsView`'s own `ZStack`. Opening or closing it changes no window style, level,
  frame, collection behaviour or `NSApp.presentationOptions`. It adds no menu code, and the
  model does no synchronous AppKit work. It is shown only when `session.mode == .parent` and no
  playtest is open. `returnToChild` (Return, auto-lock, sleep) closes it.
- **Top bar (mockup 01).** 返回 (back to the child, same as the parent page), the title
  「喺 YouTube 搵片 · parent only」, the auto-lock countdown 「8:42 後自動鎖」 (D5: browsing,
  searching and adding reset the 10-minute window), the version and 離開程式.
- **Toolbar.** Back, forward, 首頁 (the app's start page), reload, search, text size
  A− / 125% / A+ (D11: steps 100–175%, default 125%, remembered in
  `VisaGames.parentFinderZoom.v1`) and 「完成，返去清單」.
  Shortcuts: ⌘F search, ⌘L search field, ⌘[ / ⌘] back / forward, ⌘R reload, ⌘↩ add,
  Esc cancels the confirm card. They are SwiftUI `keyboardShortcut`s inside the finder, not
  menu items.
- **Start page (D2, mockup 10).** 「今日想搵咩片？」 with a search box, up to 6 recent searches
  (`VisaGames.parentYouTubeRecentSearches.v1`), a ⌘V / 貼上 hint and 「點解唔顯示 YouTube 首頁？」.
  YouTube's home and feeds (`/`, `/feed/…`) are never loaded: a navigation there, including
  in-page (SPA) navigation reported by the probe, shows the start page instead.
- **Page clean-up (D8, D12).** Injected CSS hides YouTube's own search bar, Shorts shelves and
  comments, and greys out Sign in. Related videos stay (D12). Videos already in the allowlist
  get a 「✓ 已加」 badge on thumbnails and next to the watch title (D10). The id list is written
  into the page only as validated 11-character ids.
- **Navigation policy** (`ParentYouTubeBrowser.navigation`, main frame only):
  - Allowed: https `www.youtube.com`, `youtube.com` and `m.youtube.com`, plus `youtu.be` and
    `consent.youtube.com`.
  - Cancelled, with a note: Google / YouTube sign-in. Stays signed out (D7, ADR 0003).
  - Cancelled: every other site.
  - **New-window links are refused** (`createWebViewWith` returns nil and shows a note). They
    are not opened in place either.
- **Add bar (mockup 01, 07, 09).** The id comes only from the URL (`/watch?v=` with one `v`, or
  `youtu.be`). Left: thumbnail, title, channel, id and length. Middle: 「准許影片 · N」, or for
  a video already added 「已經喺准許影片 · 第 2 張卡 · 10 月 3 日加」 with 睇吓張卡 and
  「更新片名／片長 ›」. Right: the big button with ⌘↩.
  - 「＋ 加入呢條片」: a single video (D9: on a playlist only the open video).
  - 「✓ 已經加咗」: already allowlisted.
  - Grey with a reason: 「Shorts 唔支援，揀普通片」, 「直播唔加得」 (D14), 「揀一條片先」.
- **Two-step add over the finder (D3, mockup 08).** The button pauses page media and opens the
  confirm card over the darkened finder: preview, length from the page, title and length
  fields, 取消 / 試播 / ＋加入. Return adds, Esc cancels. 試播 plays the draft id in the child's
  `ScopedPlayerView` (parent mode only; the one place a not-yet-allowlisted id plays).
- **Embeddability.** The card asks oEmbed. 401 / 403 / 404 means the owner blocks embedding
  (or the video is private or gone): 加入 is greyed out with 「擁有者唔准喺其他地方播，加咗小朋友都播
  唔到。」. A network failure stays unknown and still allows adding (the pre-0.27 behaviour).
  The same gate applies to the paste field and to `addAllowlistedVideo` itself.
- **Stay after adding (D4).** After 加入 the parent stays in the finder. A 3-second toast shows
  「已加入 · 准許影片而家 N 條」 with 睇吓張卡 and 復原 (undo removes the card again).
- **Back in the list (D13).** New cards go last. On 「完成，返去清單」 the list scrolls to the last
  card added this visit and flashes it (time-based, no animation). 睇吓張卡 does the same.
- **Bot check (mockup 06).** A read-only probe (`visaBrowser` handler) reads only the visible
  player error panels' `innerText`. `ProviderBlockedPolicy.pageTextIndicatesBotCheck` now
  matches the Chinese UI as well (不是機械人 / 不是機器人 / 確認你不是 …). The banner says
  「唔係你撳錯嘢」, keeps the add bar working when the id is in the URL (「片編號已攞到，照樣加得」),
  and offers reload, three tips and a paste field. There is no automatic retry.
- **Media.** Close and the confirm card pause and mute the page and call
  `pauseAllMediaPlayback`. `onDisappear` shuts the web view down. Opening the finder stops any
  inline 試播. Autoplay is off entirely (`mediaTypesRequiringUserActionForPlayback = .all`).
- **Web data (D6).** The finder has its own persistent `WKWebsiteDataStore(forIdentifier:)`
  (macOS 14+; a non-persistent store on macOS 13). The child player keeps the shared `.default()`
  store, unchanged. 進階 has 「清除搵片器資料」, which clears only the finder store. Nobody signs in.
- **⌘V / ⌘C / ⌘X / ⌘A / ⌘Z.** The kiosk window has no Edit menu (ADR 0011), so the existing
  local key monitor sends these to the first responder. This only runs after the child key
  block, only when `allowsExit` is true (parent), and only for plain ⌘ + key.
- **No KVO (ADR 0010).** The controller refreshes back / forward / URL / title from the
  navigation delegate and the probe message, not from key-value observation or Task hops.

## Out of scope (phase 2+)
- Option E: favourite channels with RSS and red dots on the start page (the start page's
  channels column is not built).
- Option B (split view with the live allowlist).
- Adding Shorts or live streams.
- Playlists as a batch.
- D16: no scroll buttons.

## Consequences / risks
- YouTube markup changes can break the probe and the CSS. Then the bot-check banner, page
  length, live badge, 「✓ 已加」 marks and hidden shelves degrade quietly. The add bar, id parsing
  and the embed check don't depend on page markup.
- The finder is still a real YouTube page: related videos and ads are visible to the parent,
  and on the TV. This is parent mode only.
- Typing into YouTube's own fields relies on WebKit. ⌘V is handled by the key monitor above.
- With a separate store, consent / cookie choices made in the finder don't carry over to the
  child player, and vice versa. Clearing finder data never touches the child player.

## Tests
`ParentYouTubeBrowserTests` (12 checks):
- URL id parsing; add-bar states and copy; the already-added state; navigation policy;
  search destinations and recent searches; page length; ⌘ shortcuts in parent mode only.
- Embeddability mapping and gating; the Chinese bot-check text; the add-and-stay flow
  (confirm, toast, undo, close-and-flash); zoom, countdown, the 「✓ 已加」 id script (injection
  safe), the 07 line, card number, and `addedAt` decoding for older allowlists.
- Source guards. The finder files contain no presentation, window or menu APIs, Tasks,
  DispatchQueue or KVO. The finder appears only in `ParentSettingsView` in parent mode. The
  model entry points are parent-gated and do no AppKit work. Close and the confirm card pause
  media. Pop-ups return nil. The finder uses its own store; `ScopedPlayerView` still uses
  `.default()`. Autoplay is `.all`.

`KioskPresentationTests` are unchanged and pass.
