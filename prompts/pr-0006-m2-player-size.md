# PR #6 continuation — enlarge scoped player after Reported UAT

| Field | Value |
| --- | --- |
| Date | 2026-09-27 (HK) |
| Branch | `feat/m2-scoped-player-scaffold` |
| PR | #6 (open) |
| Version | 0.3.5 (PATCH) |
| Model | `gpt-6-sol` / mechanical UI slice |

## Request

Carter reported that Preview playback now works and Error 153 is fixed, but the player window is too small. Review the Mac mini ScopedPlayer log and fix the UI layout only.

## Authorized slice

1. Increase Parent preview to approximately 420–720 pt.
2. Increase Play mode to approximately 480–900 pt.
3. Use an 800 pt default Parent window height when no prior frame exists.
4. Verify the HTML shell keeps `html`, `body`, and `iframe` at 100% width/height with zero margins; leave it unchanged if already correct.
5. Bump to 0.3.5 / CFBundleVersion 9 and update `PROGRESS.md`.
6. Push the same PR #6 branch. Do not merge.

## Log summary

The reported log shows successful `load mode=htmlString`, nocookie embed load, and `wk didFinish` for the tested video. Repeated `popup deny` events for YouTube watch URLs are expected D8 provider chrome. No Error 153 or navigation-rejected teardown appears; diagnose the remaining issue as layout sizing, not WK navigation policy.

Language lock: engineering English; UI Hong Kong Traditional Chinese + English; never Simplified Chinese.
