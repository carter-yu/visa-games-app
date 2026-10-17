# 0016 — Parent in-app YouTube finder (option A)

Status: proposed (v0.27.0 / 59). Carter chose option A on 2026-10-17 (20:00 HKT), with the
other design defaults D1–D17. D15 changes: favourite channels and RSS (option E) are phase 2.

## Context
Since ADR 0011 the parent page is part of the constant kiosk presentation. A parent can't
switch to Safari to copy a YouTube link while parent settings are open. Bringing back a
movable or resizable parent window would mean AppKit window changes on parent enter and exit.
That is exactly what crashed on macOS 27.

## Decision
- **A finder inside the parent view.** A yellow 「喺 YouTube 搜片 / Find on YouTube」 button
  sits next to the allowlist paste field. It opens `ParentYouTubeBrowserView` as a full-page
  layer in `ParentSettingsView`'s own `ZStack`. Opening or closing it changes no window style,
  level, frame, collection behaviour or `NSApp.presentationOptions`. It adds no menu code, and
  the model does no synchronous AppKit work. It is shown only when `session.mode == .parent`
  and no playtest is open. `returnToChild` (Return, auto-lock, sleep) closes it.
- **The app's own start page.** It has a search box, up to 6 recent searches
  (`VisaGames.parentYouTubeRecentSearches.v1`) and a ⌘V / 貼上 hint. A pasted link or id opens
  that video directly. YouTube's home and feeds (`/`, `/feed/…`) are never loaded: a navigation
  there, including in-page (SPA) navigation reported by the probe, shows the start page instead.
- **Toolbar:** back, forward, reload, search, and 「返准許清單」 (close).
- **Navigation policy** (`ParentYouTubeBrowser.navigation`, main frame only):
  - Allowed: https `www.youtube.com`, `youtube.com` and `m.youtube.com`, plus `youtu.be` and
    `consent.youtube.com`.
  - Cancelled, with a note: Google / YouTube sign-in. YouTube's Sign in buttons are also greyed
    out by CSS. Stays signed out, per ADR 0003.
  - Cancelled: every other site.
  - Pop-ups open in place only when allowed. Subframes may load over https (the player).
- **Add bar** (`ParentYouTubeAddBar`). The id comes only from the URL (`/watch?v=` with one
  `v`, or `youtu.be`).
  - 「＋ 加入呢條片」: a single video.
  - 「✓ 已經加咗」 (disabled, green): the video is already allowlisted.
  - Grey: Shorts, live (`/live/` or the player's live badge), or anything else
    (「揀一條片先」).
- **Add goes through the existing preview card.** The bar pauses page media, closes the
  finder and puts the watch URL in the paste field. The v0.12.0 card then shows the oEmbed
  title and thumbnail, plus 片長 when the page reported it (`<video>.duration` or
  `itemprop=duration`). Nothing is saved until the parent presses 加入. When the duration field
  is still the default 120, the page length becomes the D4 budget-fit length and the card
  length.
- **試播 on the card** plays the draft id in the child's `ScopedPlayerView`. It uses the same
  nocookie embed and navigation guards, in parent mode only. This is the one place a
  not-yet-allowlisted id plays. It is parent-authenticated, never on the child path.
- **Bot check.** A read-only probe (`visaBrowser` handler) reads only the visible player error
  panels' `innerText`. When `ProviderBlockedPolicy.pageTextIndicatesBotCheck` matches, the app
  shows its own banner: 「唔係你撳錯嘢」, a reload button, tips and a paste field. Adding still
  works, because the id is in the URL.
- **Leaving pauses media.** Close, add and the pasted-link path run a pause-and-mute script and
  `pauseAllMediaPlayback`. `onDisappear` shuts the web view down. Opening the finder stops any
  inline 試播. Autoplay with sound is off (`mediaTypesRequiringUserActionForPlayback = .audio`).
- **Parent window time.** Browsing, searching and adding extend the 10-minute parent window,
  the same way 試播 does.
- **⌘V / ⌘C / ⌘X / ⌘A / ⌘Z.** The kiosk window has no Edit menu (ADR 0011), so the existing
  local key monitor sends these to the first responder. This only runs after the child key
  block, only when `allowsExit` is true (parent), and only for plain ⌘ + key.
- **Web data.** The finder uses the shared default `WKWebsiteDataStore`, like the player
  (consent cookies). Nobody signs in.

## Out of scope (phase 2+)
- Option E: favourite channels with RSS and red dots on the start page.
- Option B (split view with the live allowlist).
- Adding Shorts or live streams.
- Playlists as a batch.

## Consequences / risks
- YouTube markup changes can break the probe. Then the bot-check banner, page length and live
  badge degrade quietly. The add bar and id parsing don't depend on page markup.
- The parent browser is a real YouTube page: related videos, comments and ads are visible to
  the parent, and on the TV. This is parent mode only.
- Typing into YouTube's own fields relies on WebKit. ⌘V is handled by the key monitor above.
- Shared cookies: what the parent browses can shape YouTube's own recommendations inside the
  embed's end screen. ADR 0003's residual risk is unchanged.

## Tests
`ParentYouTubeBrowserTests`:
- URL id parsing.
- Add-bar states and copy.
- The already-added state, including the hand-off into `ParentAllowlistDraft`.
- Navigation policy.
- Search destinations and recent searches.
- Page length parsing.
- ⌘ shortcuts in parent mode only.
- Source guards. The finder files contain no presentation, window or menu APIs, Tasks,
  DispatchQueue or KVO. The finder appears only in `ParentSettingsView` in parent mode. The
  model entry points are parent-gated and do no AppKit work. Every way out pauses media.

`KioskPresentationTests` are unchanged and pass.
