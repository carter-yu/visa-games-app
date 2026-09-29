# ADR 0006 — Storybook child UX + original recognizable vehicles (v0.7)

Status: Implemented on `feat/m4-gakken-style-activities` (PR #8) — Mac mini UAT pending; **do not merge** until Carter OK. D9 / D10 remain open.

Update 2026-09-29: PR #8 was squash-merged to `main` (`e77d8ee`, 2026-09-28). The child look is
superseded screen by screen by ADR 0007 (concept canvas); the hard IP rules below still apply.

## Context

Carter Confirmed that home educational use must appeal to a **4-year-old boy**. Reference storybook notes (Egypt + anthropomorphic vehicles, Cantonese kid-speak) set the energy: warm painterly sand worlds, convoy adventure, wooden station signs, friendly vehicle faces. Separately, Carter asked whether a home-use disclaimer licenses Tomica-like images — it does **not**.

## Hard IP rules

1. A home-use disclaimer **does not** grant rights to Takara Tomy, HIT Entertainment, Mattel, or any third-party character likenesses.
2. **Do not** embed official photos, logos, box art, or near-exact copies of licensed characters.
3. **Do** create **original** friendly vehicle faces + silhouettes inspired by *recognizable real-world types* a HK child knows instantly:
   - Hong Kong red taxi
   - New York yellow taxi
   - Hong Kong fire engine
   - Metro / MTR-*inspired* train livery (soft silver + blue stripe) — **no protected roundel logo**
   - Long construction / logistics vehicles (crane, tanker, bus, flatbed, truck)
4. Parent-visible About / license footer (HK Traditional Chinese + English) states educational home use, original artwork, and non-affiliation. Trademarked company names appear **only** in that parent footer for clarity — never on the child path, never as mascot names in UI chrome.

## Product decisions (v0.7.0)

1. **World shell:** Storybook depot — soft sky + ochre dunes (`StorybookWorldBackground`), wooden station sign title, friendly convoy parade.
2. **Difficulty cards:** Three mission tickets / routes (的士短程 / 消防車任務 / 地鐵長程) with mascot + stars + Confirmed 10/20/30 minutes + press animation.
3. **Games:** Keep `ActivityCatalog` rotation; upgrade visuals (faces, bigger taps); make **sequence short→long convoy** playable (4 playable kinds).
4. **Success:** Toy-like visa stamp / ticket punch, then park-in celebration.
5. Keep D8 scoped player, one-paste allowlist, parent LA, kiosk rules, no Simplified Chinese.
6. Version **0.7.0** (MINOR visual/product leap) / CFBundleVersion **19**.

## Consequences

- Theme backgrounds shift from dark teal to warm sand storybook palettes (parent picker labels updated).
- Offline activity suite expects **13** activity checks (sequence playable + evaluator).
- Mac mini visual UAT for 4yo appeal is required before merge.
