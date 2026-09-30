# Prompt — UX Phase 2+3: Voice + Activities + Stamp/Watch/Time's up (v0.10.0)

You are Claude Code Opus implementing Visa Games UX on branch `feat/ux-p2-p3-activity-watch`
(already checked out from `feat/ux-p1-canvas-depot` @ 4037f93 / PR #9 tip).

USE MAXIMUM EFFORT. Do NOT thrift tokens. Prefer one long focused implementation pass.
Carter said Opus design direction is correct; keep style consistency with Depot (PR #9).
用盡token要做好.

## Read first (required)
1. `docs/ux-rebuild-brief.md` §§0–5 (esp. boards 2–5, 7 + tokens §3)
2. `AGENTS.md`, latest `PROGRESS.md` entry (v0.9.0)
3. `docs/decisions/0007-concept-canvas-child-ux.md` and `0002-reward-gating-d1-d7.md` (D7 assisted)
4. `phases/phase-5-canvas-ux-rebuild.md`
5. Existing Depot tokens/art: `DesignTokens`, `CanvasArt`, `DesignSystem`, `DepotHomeView`,
   `SystemSpeechPrompt`, `CantoneseVoice`, `RoadTileView`, `ChunkyButtonStyle`, `CanvasStage`
6. Activity logic (DO NOT reinvent): `Sources/VisaCore/Activity.swift` + AppModel select* /
   handleEvaluation / applyEntrySuccess in `AppDelegate.swift`
7. Legacy activity views to rebuild: Entry/FindSame/Count/Sequence + NewActivityViews (6 kinds)

Concept canvas URL may be Cloudflare-blocked — rely on brief §3–4 + Depot style. Do NOT invent
Tomica/Thomas/Tayo likenesses.

## Locked decisions (do not reopen)
- Auto-hint after **2 misses** → record round as **assisted** (D7). Wire miss counting in AppModel;
  after 2 incorrects call the existing hint path (`entryHintUsed = true`) AND pulse the correct
  choice. Correct-after-hint already yields `.correct(assisted: true)` via evaluator.
- Keep Stampy placeholder name/design.
- Do NOT change reward minutes 10/20/30, kiosk escape, parent auth, allowlist/visa accounting.
- **Visa clock start:** keep CURRENT accounting (`startPlayVisa` on correct answer in
  `applyEntrySuccess`). Only replace presentation: insert stamp screen with 「出發！ Go!」 that
  reveals playback UI; visa may already be ticking (parent can see road timer move).
- Language: HK Traditional Chinese + English only; NEVER Simplified.
- Child ~4yo: voice-first, ≤3 huge choices, road tile = 10 min, no fail red X / buzzer, hide adult chrome.
- Phase 4 (passport unlocks / rounds-as-stars / daily-cap ending) = SKIP unless trivial stub.
  Do not invent D6/D9/D10 closures.

## Implement (priority order)

### UX Phase 2 — Voice + Activities (boards 2, 7)
1. **Shared ActivityBoard shell** (canvas 1280×720 via `CanvasStage`):
   - Stampy + speech bubble (reuse `SpeechBubbleButton` / GuideRow pattern from Depot).
   - Auto-play Cantonese prompt on entry via existing `SystemSpeechPrompt` / zh-HK path;
     tap bubble to replay. Use real activity prompts (not the D9 "later" stub message).
   - One stimulus panel + up to 3 text-FREE choice cards (no option labels on cards; a11y labels OK).
   - Progress as road cones (for single-question rounds, show 1 cone filled when done — or a simple
     cone row that reflects "question in progress"). Keep it simple for 1-question tickets.
   - Parent subtitle of the prompt at small size; child sees pictures.
2. **Feedback component** (board 7 shared states; Reduce Motion aware):
   - Correct: card hops, sparkles, soft chime (system sound OK), Stampy cheers briefly — under 0.5s feel.
   - Not-yet: soft wiggle + friendly sound. No red X, no buzzer, nothing taken away.
   - Hint: after 2 misses, correct answer pulses/glows; Stampy "rolls toward" it (subtle offset/point);
     re-speak prompt; mark assisted via hintUsed.
3. **Rebuild all 10 activity presentations** to this layout while **reusing existing activity logic**
   (questions, evaluators, AppModel select*). Prefer one shared shell + per-kind stimulus/choice
   content builders over 10 near-duplicate full screens. Legacy storybook chrome (wooden world,
   big bilingual prompt titles, visible Hint/Hear buttons) goes away on child activity screens.
4. **No-video / empty allowlist sister screen** (board 7): when play starts but allowlist is empty,
   show friendly empty stage (Stampy + empty garage vibe) + one return ticket / 「返回車廠」 chunky
   button that locks back to depot (existing return/lock path). Do not invent new accounting.

### UX Phase 3 — Stamp, Watch, Time's up (boards 3–5)
1. **Success / visa stamp:** replace overlay-only `SuccessParkAnimation` as the gate before video.
   Passport spread: vehicle sticker left, big tilted 「簽證 VISA」 stamp + road tiles right;
   confetti; big green 「出發！ Go!」 ChunkyButton. Tap starts showing playback (visa already started
   per locked decision). Pass mission vehicle from selected difficulty (taxi/fire/metro).
2. **Playback + road timer:** dark/watch presentation: video area + road strip below
   (start flag → mission vehicle → garage). Vehicle position = elapsed/total visa seconds.
   Parent readout 「仲有 N 分鐘」 (ceil remaining minutes). At 1 minute left: garage lights up +
   spoken almost-home Cantonese via SystemSpeechPrompt (add SpokenPrompt keys).
3. **Time's up:** when visa expires / session returns to lock after play, show dusk park-and-sleep
   scene once (vehicle into garage, sleeps, Stampy waves) + one 「再揀車票 New mission」 button
   that dismisses to Depot. Do not invent daily-cap "see you tomorrow" variant.
4. Keep ScopedPlayerView / PlaybackPolicy / shuffle / D8 containment unchanged.

## Engineering constraints
- Linux box often has NO Swift — WRITE correct Swift anyway. Do not claim compile pass if `swift`
  missing. Still add/adjust VisaCoreChecks tests for pure-logic pieces (miss→assisted, SpokenPrompt
  keys, road-timer progress math, new tokens/art parse).
- Version: bump to **v0.10.0 / build 26** (MINOR — new child UX capability). Update Info.plist,
  parent footer `Visa Games v0.10.0`, PROGRESS.md top entry with Mac mini UAT checklist.
- Update ADR 0007 open-decisions table: mark auto-hint→assisted as decided (Carter 2026-09-30);
  note visa clock presentation-only change (accounting unchanged). Flag any other ADR conflicts
  in PROGRESS — do not silently override ADRs.
- Update `phases/phase-5-canvas-ux-rebuild.md` exit notes for UX P2/P3 if appropriate.
- Archive this prompt path is already `prompts/pr-0010-ux-p2-p3-activity-watch.md`.
- Commits: coherent, reviewable (e.g. core miss/assisted + prompts; ActivityBoard shell; rebuild
  10 games; stamp+Go; road timer+times-up; version/PROGRESS/tests).
- Style: match Depot ink outline, chunky buttons, CanvasFont/CanvasText, DesignTokens palette,
  TV safe CanvasStage. Extract shared Guide/SpeechBubble if still private in DepotHomeView.
- Hide adult chrome on new child screens (no version, no one-tap Parent; keep ParentCornerEntry).

## Process / when done
1. Implement fully as far as quality allows in ONE PR worth of work (P2+P3).
2. Run `sh scripts/test.sh` if Swift exists; otherwise note exit 127.
3. `git diff --check`; commit; `git push -u origin feat/ux-p2-p3-activity-watch`.
4. Open PR to **main** with `gh pr create`. Title like:
   `UX P2+P3: voice activities + stamp/watch/time's up (v0.10.0)`
   Body must note: includes / depends on Depot commits from PR #9 (`feat/ux-p1-canvas-depot`);
   do not merge until Mac mini UAT; list what landed vs deferred.
5. Do NOT merge. Do NOT invent policy.

## Deliverables in your final message
- Tip SHA, PR URL, version/build
- What landed vs deferred
- Test status
- Mac mini UAT checklist commands
- Any ADR conflicts flagged

## Concept canvas screenshots (MUST match — Carter uploaded boards 1–7)

Local paths (READ these PNGs with your Read/image tool before coding UI):
- `docs/concept-canvas-boards/01-depot-home.png` (Depot — already built in P1; style reference)
- `docs/concept-canvas-boards/02-activity-shadow-match.png` ← **P2 primary reference**
- `docs/concept-canvas-boards/03-visa-stamped.png` ← **P3 stamp**
- `docs/concept-canvas-boards/04-watching-road-timer.png` ← **P3 watch**
- `docs/concept-canvas-boards/05-times-up-park-rest.png` ← **P3 time's up**
- `docs/concept-canvas-boards/06-my-passport.png` (shell only if easy; no unlock rules)
- `docs/concept-canvas-boards/07-feedback-palette.png` ← feedback states + palette

### Board 2 Activity (shadow match) — layout to replicate for ALL 10 games
- Sky + thin sand ground strip; Stampy (small) top-left + speech bubble with speaker + Cantonese + English subtitle.
- Progress: top-right rounded box with traffic cones (filled tomato / empty outline).
- ONE large ink-outlined white/paper stimulus card center (e.g. dark silhouette).
- THREE huge choice cards along bottom — vehicles ONLY, **no text labels on cards**.
- Yellow glow ring = pen spark / focus (already have PenSparkOverlay).

### Board 3 Visa stamped
- Sunny yellow sunburst + confetti; Stampy left cheering bubble 「蓋印！ / Stamped!」.
- Passport book (metro-blue frame): left page polaroid vehicle + stars + mission title; right page big red 「簽證 VISA」 stamp.
- Bottom mint chunky 「出發！ Go!」 with play icon; small vehicle zooms off right.

### Board 4 Watching road timer
- Dark ink/navy full background; large video frame with play affordance.
- Bottom road strip: checkered start flag → mission vehicle on dashed yellow center line → cone → 「仲有 N 分鐘」 → garage house destination.
- Vehicle X position = elapsed/total.

### Board 5 Time's up
- Night sky + moon + stars; garage with sleeping vehicle (closed eyes) + zzz; Stampy bubble
  「消防車返車廠 瞓覺喇！ / Time to park and rest.」 (vehicle name from mission).
- One sand/sunny chunky 「再揀車票 / New mission」 button.

### Board 7 Feedback
- Pen spark glow; Got it = hop+sparkles+chime; Not yet = soft wiggle+boop (NO red X);
  Hint after 2 misses = answer yellow glow, Stampy rolls toward it, re-speak.

### Board 6 Passport
- Optional UI shell stub only (open book + back). Do NOT invent stamp count unlocks / "3 more stamps" policy.

Palette locked: Ink #3A2718 Sky #A8E0F7 Grass #6FC063 Sand #F4CD74 Sunny #FFC928 Tomato #F0553A Metro #2F7DE1 Mint #3CC49A.
