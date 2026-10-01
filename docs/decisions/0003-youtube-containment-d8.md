# ADR 0003 — YouTube containment (D8)

Status: Confirmed by Carter Yu (2026-09-27) for Phase 2 (M2) scaffold

## Context

M0 owns the native kiosk shell. M1 (ADR 0002) owns the reward and viewing-budget contract; D8 was left open there. Parent Carter Yu confirmed **1+4 / D8** as: the child path may only use a **scoped official embed** surface — not a general browser, URL bar, or unrestricted search.

The earlier browser prototype showed that YouTube and web chrome create child escape paths (tabs, related videos, external links, search). This ADR records the containment rule before any real provider playback ships.

## Decision (D8)

1. **Scoped official embed only.** The child playback path may load an approved video only through a tightly constructed official embed URL (YouTube `youtube-nocookie` embed pattern, or a later parent-approved equivalent). No general `WKWebView` / browser surface is exposed on the child path.
2. **Allowlist video IDs from parent config.** Playback may start only for a video ID present in the parent-maintained allowlist. Unknown IDs are rejected. Parent add/edit UI is parent-authenticated only; the child path has zero text inputs and no URL entry.
3. **No arbitrary navigation.** The player must not offer a URL bar, free-form navigation, unrestricted YouTube search, related-video browsing that leaves the allowlisted ID, or open-in-browser affordances reachable by the child.
4. **Stop on budget or session expiry.** Playback stops when the viewing budget reaches zero or the independent absolute session deadline expires, whichever comes first (ADR 0002 D4 / D5). Containment does not replace those timers.
5. **D6, D9, and D10 remain open.** This ADR does not invent medium-goal timing, reporting policy, or other unrecorded decisions.

## Residual OS / web risks (honest)

App-level embed containment is **not** a managed-device boundary (ADR 0001). Residual risks include, without claiming completeness:

- **Provider chrome inside the embed:** YouTube (or another provider) may still show title, share, end-screen, or related UI that the app cannot fully strip. Treat provider UI as a residual escape/attention path and log it during Mac mini evidence.
- **WKWebView / WebKit surfaces:** Link clicks, target=_blank, javascript navigation, and gesture zoom/fullscreen must be denied or cancelled where the API allows; anything WebKit still permits is a residual risk.
- **Process / OS escapes:** Force Quit, Mission Control, hot corners, other apps, browser apps on the same account, and Screen Time gaps remain OS/deployment concerns, not solved by this ADR.
- **Network / account side channels:** A signed-in Google/YouTube account in the shared WebKit data store, cookies, or recommendations could widen the surface. Prefer nocookie embed and a dedicated child Mac user without browser/YouTube sign-in.
- **Malicious or mistyped parent allowlist entries:** Parent-configured IDs are trusted configuration, not child input; a wrong ID still plays only that embed, but content suitability remains a parent responsibility.

## Consequences

- M2 may scaffold `ApprovedVideo` / allowlist types, a `PlaybackPolicy` seam, a FakePlaybackEngine for tests, and a ScopedPlayerView that builds only allowlisted embed URLs.
- Arbitrary URL helpers must fail closed in tests.
- No general browser, search UI, or child text field for URLs is permitted.
- To avoid YouTube **Error 153** (missing/invalid Referer in WKWebView), the scoped player may load a minimal **HTML shell** via `loadHTMLString` whose iframe `src` is still the constructed nocookie `/embed/<id>` URL, with `referrerpolicy="strict-origin-when-cross-origin"` and HTTPS `baseURL` on the nocookie host root. The shell host-root is not a general browse grant; watch/search/other-id remain denied.
- Main-frame navigation may follow **official embed redirects** between `youtube-nocookie.com` and `youtube.com` / `m.youtube.com` for the **same** allowlisted `/embed/<id>` only. Watch, results, channel, search, and other-id embeds remain denied. This does not authorize a URL bar or general browsing, and does not claim OS-level containment.
- Provider telemetry details (buffering vs ads) remain subject to ADR 0002 and any later provider ADR; D8 does not relax those rules.
- **v0.12.0 end-of-video bridge (Carter UAT 2026-10-01):** the HTML shell may load the official YouTube IFrame API script (`https://www.youtube.com/iframe_api`, a `<script>` subresource — not a main-frame navigation) and attach it to the same constructed iframe (`enablejsapi=1`, `origin` = shell origin). The shell posts player state to a **read-only** `WKScriptMessageHandler` (`visaPlayer`): `ready` / `state` / `duration` / `ended` / `apiError`, tagged with the loaded id. Swift ignores messages for any other id and never lets the page navigate, open windows, or pick another video. On `ended` the app leaves the player (picker if time is left, Time's up if not), so the provider end screen / related videos are no longer a resting state. Main-frame navigation rules are unchanged. Residual: if the API script fails to load the video still plays but end detection is lost (logged as `player api-unavailable`); the old end-screen risk then remains until the visa or budget stops playback.
