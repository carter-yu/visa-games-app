# UX rebuild brief: Visa Games (簽證車廠)

Handoff from a claude.ai design session to Claude Code. Put this file at `docs/ux-rebuild-brief.md`.

## 0. Ground rules (read first)

1. Read `AGENTS.md`, `PROGRESS.md`, `ROADMAP` (if present), and every ADR in `docs/` before touching code. **If this brief conflicts with an ADR or AGENTS.md, the repo wins.** Flag the conflict to the user instead of silently choosing.
2. Branch: PROGRESS.md (v0.8.0, build 24) says the storybook UI, hero PNGs and new activities live on `feat/m4-gakken-style-activities` (PR #8, unmerged). **Ask the user which branch to base on** before creating a new branch.
3. Language: user-facing text is Traditional Chinese (Hong Kong Cantonese) + English only. Never Simplified Chinese.
4. IP: all characters and art stay original. No Tayo, Tomica, Thomas or Gakken likeness.
5. Kiosk invariants are out of scope. Do not change escape-path blocking, parent authentication, allowlist playback or visa accounting logic unless the user asks.
6. Do **not** change reward policy (minutes per ticket, rounds, daily caps) without an explicit user decision. See section 6.
7. Work in small, reviewable PRs, one phase at a time. Run the repo's test script after each change and update PROGRESS.md the way the repo already does.

## 1. What is verified vs. proposed

**Verified from repo docs (README, AGENTS.md, PROGRESS.md), not from source code.** The design session could not open `Sources/`.

- Native macOS kiosk: a Mac mini driving a TV, with Wacom pen + finger input.
- The loop: lock screen (depot) → 3 mission tickets (的士短程 10 min / 消防車任務 20 min / 地鐵長程 30 min) → activity (10 kinds in rotation) → success → visa stamp → allowlisted video playback → visa countdown → expiry → back to tickets.
- Audio prompting is a scaffold only (`ActivityAudioPrompting` + `StubActivityAudioPrompt`). D9 (audio) was still open at v0.8.0.
- Earlier notes (v0.4.x) say the lock screen showed the Parent button and version number. Recheck whether this is still true.

**Unverified. Check in code during Phase 0:**

- Whether Easy / Medium / Challenge change task difficulty, or only rotate the same activities.
- Whether the Wacom pen reports hover (proximity) position to the app on the Mac mini.

## 2. Design principles (why)

The user is about 4 years old, **cannot read**, and points with a pen on a tablet while looking at a TV.

| Problem | Principle |
|---|---|
| Can't read prompts | **Voice-first.** Every prompt is spoken in Cantonese. Text is a small parent subtitle. |
| Indirect pointing (tablet → TV) | **Pen spark cursor**, at most 3 choices, huge targets. |
| Minutes are abstract | **One road tile = 10 minutes**, used everywhere time appears. |
| Endings trigger meltdowns | **Predictable wind-down**: warning, then vehicle parks and sleeps, then one next action. |
| Failure feels bad | **No fail states.** Wiggle, then hint. Never a red X or buzzer. |
| Adult UI distracts | **Hide adult chrome** from child screens. |

## 3. Design tokens

Reference canvas is 1280×720. Scale proportionally to the TV resolution.

- **Colours:** Ink `#3A2718` (all outlines and text), Sky `#A8E0F7`, Grass `#6FC063`, Sand `#F4CD74`, Sunny `#FFC928`, Tomato `#F0553A`, Metro `#2F7DE1`, Mint `#3CC49A`, Paper `#FFF6DF`, Stamp red `#D93A2B`, Road `#5B5F73`.
- **Outline:** 5 pt ink stroke on every interactive shape and every character.
- **Chunky button:** corner radius about 30, hard shadow offset y +10 with no blur. Pressed state moves down 6 and shrinks the shadow to 2. Response starts in under 100 ms.
- **Targets:** activity choice cards about 300×210 at the 1280×720 reference (about 23% of screen width). Never more than 3 choices.
- **Type:** `Font.system(size:weight:design: .rounded)`; CJK falls back to the system HK font. Verify on the Mac mini. Parent subtitle is 17–20 pt; the child sees mostly pictures.
- **TV safe area:** keep all interactive and critical UI at least 5% in from every edge (TV overscan).
- **Motion:** respect Reduce Motion. When it's on, replace wiggle and pulse with static states.

## 4. Screen specs (map to existing screens)

1. **Depot home / ticket picker**
   - Guide character with speech bubble. **The bubble is the replay-voice button.**
   - 3 physical-ticket cards, each showing: the vehicle, stars (1/2/3), road tiles (1/2/3), and a small "10/20/30 分鐘" parent label.
   - Passport button top-right with a stamp count.
   - Version number removed from child view. Parent entry becomes a faint, long-press-only corner that keeps the existing authentication.
2. **Activity**
   - Guide + bubble (auto-plays the prompt on entry, replays on tap).
   - One stimulus panel (for example the shadow), then 3 choice cards with no text.
   - Progress shown as road cones.
3. **Success / visa stamp**
   - Passport spread: vehicle sticker on the left page, a big tilted stamp 「簽證 VISA」 with road tiles on the right.
   - Confetti, then a big green 「出發！ Go!」 button that starts playback. The child's tap gives her agency.
4. **Playback + road timer**
   - Video area plus a road strip below it: start flag, then the mission vehicle driving toward the garage. Vehicle position = elapsed / total.
   - Small parent readout 「仲有 N 分鐘」.
   - At 1 minute left: the garage lights up and the guide says it's almost home.
5. **Time's up**
   - Dusk scene: the vehicle rolls into the garage and falls asleep, the guide waves, one big 「再揀車票 New mission」 button.
   - Needs a "see you tomorrow" variant if a daily cap exists. See decisions.
6. **Passport (collection)**
   - Stamp grid, a "my vehicle" portrait, and "N more stamps → new vehicle joins the depot".
   - Needs a user decision before building.
7. **Feedback states** (shared component)
   - **Pen spark:** big glow ring follows the pen, including hover.
   - **Correct:** card hops, sparkles, chime, guide cheers. Under 0.5 s.
   - **Not yet:** soft wiggle and a friendly sound. Nothing is taken away.
   - **Hint:** after 2 misses the answer pulses, the guide rolls toward it and repeats the prompt.

The guide character, 「印仔 Stampy」 (a round yellow depot cart with a rubber-stamp handle), is a **placeholder**. Confirm the name and design with the user.

## 5. Phases

**Phase 0: Audit (report only, no code changes).**
Map every current child-facing view to screens 1–7 above. List the gaps, and answer the two unverified questions in section 1. Propose a file-by-file plan, then stop and wait for approval.

**Phase 1: Foundation (no policy changes).**
- Add tokens (colours, outline, shadow, radius, rounded type).
- Build the chunky button style.
- Apply TV safe margins.
- Hide the version and demote parent entry.
- Build the shared feedback component (section 4.7) with Reduce Motion support.
- Build the pen spark overlay (hover-driven if the hardware supports it; otherwise show it on touch-down).

**Phase 2: Voice-first.**
- Implement a real conformer of the existing audio-prompt protocol.
- Preferred: pre-recorded Cantonese clips, one per prompt key. Fallback: `AVSpeechSynthesizer` with a `zh-HK` voice, if the Mac mini has one installed (verify).
- Wire the speech bubble as the replay button. Auto-play on screen entry.
- Deliver a list of prompt keys and script lines for the user to record.

**Phase 3: Time language.**
- Road-tile component, used on tickets, the stamp and the playback road timer.
- 1-minute warning.
- Time's-up wind-down scene.

**Phase 4: Needs decisions first.**
- Rounds per ticket.
- Passport unlocks.
- Daily-cap end state.

## 6. Decisions the user must make

1. Base branch for the rebuild.
2. Guide character name and design.
3. Rounds = stars (1/2/3 rounds for 10/20/30 min)? This changes reward policy.
4. Passport collection unlocking vehicles: yes or no.
5. Time's-up screen when the daily limit is reached: offer a new mission, or show "see you tomorrow"?
6. Whose voice records the Cantonese prompts.

## 7. Done means

- The repo test script passes. PROGRESS.md is updated per repo convention.
- On the real TV, from the child's seat:
  - every choice is readable and hittable with the pen;
  - every prompt is spoken;
  - no child-facing screen needs reading to proceed;
  - no red or failure feedback appears anywhere.
- One observed session with the child, noting where she hesitates.

Concept mockups: https://claude.ai/artifact/WvGZiPg7v8pKjVhKzDrVmk
This link is private to the owner. If Claude Code can't open it, rely on sections 3–4.
