# Ground rules

1. Product name is Visa Games / 簽證遊戲.
2. Ritual line is 先做再玩.
3. The child flow is pen + finger first.
4. The child flow has zero text inputs.
5. UI language is Hong Kong Cantonese + English; never Simplified Chinese.
6. Code, comments, commits, architecture notes, and tests are English only.
7. Parent-only actions must not be reachable accidentally from the child path.
8. Approved video/content selection is controlled by the parent.
9. The child must never receive a general browser surface, URL bar, arbitrary link navigation, or unrestricted web search.
10. Visa time is stored as an absolute `endsAt` timestamp and survives relaunch.
11. Help may reduce earned visa minutes; preserve the existing family rule unless a phase explicitly changes it.
12. Tests first for behavior that can regress: lock state, earning time, expiry, relaunch, parent unlock, media resume, and kiosk escape paths.
13. Keep dependencies minimal. Prefer Swift/macOS frameworks over third-party packages.
14. Every family-visible slice has a SemVer version. PATCH = fix/UX, MINOR = new capability, MAJOR = breaking persistence or product change.
15. Document platform limits honestly. Do not describe app-level controls as an OS security boundary.
16. Build the smallest household-testable slice before adding skins, cloud sync, accounts, LLM features, or analytics.
