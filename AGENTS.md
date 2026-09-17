# visa-games-app

Read `README.md`, `docs/ground-rules.md`, and the current phase file before making changes.

- Name locked: Visa Games / 簽證遊戲. Ritual: 先做再玩.
- Target: native macOS family kiosk app for a dedicated Mac mini + TV.
- Child path: pen + finger only. Zero text inputs. Coach 「用筆畫」.
- UI: Hong Kong Cantonese + English. Never Simplified Chinese.
- Engineering: English only.
- Parent controls are explicit; child path never exposes unrestricted browser/navigation UI.
- No general-purpose web browser inside the child experience.
- Tests first for state transitions, timer expiry, persistence, and escape-path regressions.
- Offline test suite where practical.
- Keep architecture small. Add dependencies only when native APIs are insufficient.
- Do not copy cec-vivisystem calendar/Slack code.
- Preserve the successful Visa Games ritual and card/visa rules, but do not blindly port browser-era kiosk workarounds.
- Version every family-visible slice. PATCH = fix/UX, MINOR = new capability, MAJOR = breaking persistence or product change.
- Security truth: app-level kiosk controls are not a substitute for macOS device policy. Document every remaining OS escape path.

## Codex working rule

Before coding:
1. Read `PROGRESS.md`.
2. Read the current phase file under `phases/`.
3. State the smallest slice you will implement.
4. Add or update tests first when behavior can be tested.
5. Run tests/build before stopping.
6. Update `PROGRESS.md` with facts only.
