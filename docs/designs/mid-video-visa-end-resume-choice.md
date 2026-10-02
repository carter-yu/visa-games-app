# Design: Mid-video visa-end — Resume Choice board

**Status:** Implemented **v0.15.0** (branch `feat/resume-choice-board`, 2026-10-02 HKT). Carter lock overrides D2: Right clears cursor **immediately** (not keep-until-card-pick).  
**Audience:** Manager (EN). Child-facing microcopy: **Hong Kong Traditional Chinese** only (never Simplified).  
**Child:** Carter Yu, ~4yo, TV + Wacom, cannot read; voice + picture do the work.  
**Baseline tip:** v0.14.0 resume (PR #12 merged) + wrong-answer pending shrink. Read against `TimesUpView` / `WatchPlaybackView` / `VideoPickerView` / `IncompletePlayback` / stamp flow.

---

## Problem (today)

1. Child earns a short visa (e.g. **5 min**), picks a longer allowlisted video (~**10 min**).
2. Visa / viewing budget hits zero **while the video is incomplete** → stop saves `Snapshot.lastIncomplete`, ends play visa, shows classic **TimesUp** (dusk park-and-sleep + 「再揀車票」).
3. After a new mission → stamp 「出發！」→ **VideoPicker** with a mint-green **「繼續睇」** banner bolted above the 3×2 grid (PR #12).
4. UAT: the green Continue is easy to miss / feels like chrome on top of the canvas world, not part of the vehicle story. Kid often ignores it and taps a random card.

Carter ask: a **dedicated** board for this case only — split left / right, natural Depot canvas, not bolted green chrome.

---

## A. When this board shows (vs other endings)

Name the new board **Resume Choice** (code sketch: `ResumeChoiceView`). Product beat: the road forked — same film paused on the left, other films on the right.

| Event | Incomplete cursor? | Board | Notes |
| --- | --- | --- | --- |
| **Visa / budget exhausted WHILE video incomplete** (`positionSeconds > 0`, stop reason `.budgetExhausted` / `.sessionExpired`) | **Saved** (PR #12 policy unchanged) | **① Classic TimesUp first** (park & sleep → 「再揀車票」→ Depot), then after **new visa + stamp + 「出發！」** → **② Resume Choice** (this design) | Continue needs a live play visa + bank (D4). Do **not** invent time on the TimesUp screen. |
| Visa / budget exhausted, **no** valid cursor (no `currentTime`, position ≤ 0, API miss) | None | Classic **TimesUp** only | Same as today; no Resume Choice, no picker Continue. |
| **Natural YouTube end**, visa + budget still left | Cleared (`ended`) | Same-visa **VideoPicker** (「揀片睇！」) | PR #11 / `VideoEndRouting.afterVideoEnded` → `.videoPicker`. No Resume Choice. |
| Natural end, **no** time left | Cleared | Classic **TimesUp** | No Continue. |
| D8 nav reject / not allowlisted mid-play | Not saved | Same-visa **VideoPicker** + message | Unchanged. |
| Parent Preview stop | Never saved | Parent UI only | Unchanged. |
| Picker reached **with** `resumeCandidate` but Resume Choice **skipped** (fallback) | Present | Today's mint **「繼續睇」** banner on VideoPicker | Keep as safety net only (cold paths / feature flag off). Primary path = Resume Choice. |

### Why not show Resume Choice *on* the exhaustion TimesUp itself?

Left = 「Continue」and Right = 「VideoPicker」are **play-visa actions**. At exhaustion the session is already ending into lock; D4 forbids inventing viewing time. Putting Continue on TimesUp recreates the bolted-on green chrome problem and would either no-op or cheat budget.  
**Recommended:** keep TimesUp as the soft landing (“go earn another ticket”), then make Resume Choice the **first board after 「出發！」** whenever `resumeCandidate != nil`. That is when Left/Right can do real work.

### Flow (happy path)

```
Watch (5 min visa / ~10 min film)
  → stop mid-video (budget/visa)
  → save lastIncomplete
  → TimesUp (park) → 「再揀車票」→ Depot
  → activity success → Stamp → 「出發！」
  → Resume Choice   ← NEW (replaces picker+green banner)
        ├─ Left  → continueIncompleteVideo() → Watch @ saved start=
        └─ Right → VideoPicker (no Continue banner this visit)
              └─ card pick → clear cursor, play from 0 (PR #12)
```

---

## B. Layout, visuals, microcopy, tap targets

### Stage

- Canvas **1280×720**, TV safe **5%**, ADR 0007 tokens / Baloo 2 + Noto Sans HK.
- World: **same Depot / dusk family as TimesUp** (navy sky, moon/stars optional, grass + sand, Stampy) — not a new chrome sheet. Think “fork in the road at the depot,” not a settings dialog.
- Avoid mint strip / toolbar Continue. Both choices are **equal giant picture-buttons** in the scenery.

### Split layout (artboard coordinates)

```
┌──────────────────────────────────────────────────────────────┐
│  Stampy + speech bubble (top, full width, ~y 40–140)         │
│                                                              │
│   ┌──────────── LEFT ────────────┐  ┌──── RIGHT ──────────┐ │
│   │  Frozen / still “TV” frame   │  │  Film bay / cards    │ │
│   │  of paused video             │  │  icon cluster        │ │
│   │  big play badge              │  │  「揀片睇」           │ │
│   │  「繼續睇」                  │  │                      │ │
│   │  hit ~ 520×380               │  │  hit ~ 520×380       │ │
│   └──────────────────────────────┘  └──────────────────────┘ │
│                         road / sand strip                    │
└──────────────────────────────────────────────────────────────┘
```

- **Gap** between panes ~24–32u so a pen miss doesn’t hit both.
- Each pane: chunky ink outline (4–5u), paper/sand fill, shadow depth like other boards — **vehicle-world props**, not Material buttons.
- Parent 3s corner stays (non-Watch child screen rule). No version chrome.

### Left pane — Continue (same incomplete cursor)

- **Picture:** best-effort still of “where we stopped.”
  - **v1 (ship):** allowlist / YouTube CDN thumbnail for `resumeCandidate.videoID` + large mint **play** badge centered + ticket vehicle watermark corner. Optional small chip 「停喺呢度」 (no raw clock required for the child).
  - **v2 (later):** optional `WKWebView` bitmap snapshot at stop if reliable offline; never block the board on network.
- **Labels (child sees picture; parents see tiny EN):**
  - Primary Trad: **繼續睇**
  - English subtitle: Continue watching
- **Voice (auto on appear, tap bubble to replay):**  
  - Trad: **仲可以繼續睇！**  
  - EN (parent): You can keep watching!
  - Optional second beat after 1.2s silence if unused: **定係揀第二條？** / Or pick another?
- **a11y:** `繼續睇 / Continue watching`
- **Tap:** whole left pane (min ~**200×200** CSS-pt equivalent at TV; design for ≥ **480×340** artboard units). One tap → `continueIncompleteVideo()` (PR #12 seek/`start=`).

### Right pane — Pick a video

- **Picture:** stack of 2–3 preview-card silhouettes / film-strip + Stampy-sized 「揀」 glyph — reads as the picker bay, not “New mission ticket.”
- **Labels:**
  - Primary Trad: **揀片睇**
  - English subtitle: Pick a video
- **a11y:** `揀片睇 / Pick a video`
- **Tap:** whole right pane → route to **VideoPickerView** for the **current** play visa.
- **Incomplete on Right (recommended default):** **keep** cursor; **suppress** the mint Continue banner on this picker visit (child already chose “pick”). Card pick still **clears** cursor and starts at 0 (PR #12). If they somehow leave picker without picking (shouldn’t — only watch path is pick/Continue), cursor remains for next 「出發！」→ Resume Choice again.

### What we remove / demote

- Primary path: **do not** show the mint Continue banner when Resume Choice was the gate after 「出發！」.
- Keep banner **only** as fallback when `resumeCandidate != nil` but Resume Choice was not shown.

### Microcopy pack (Trad + EN subtitle)

| Key | Traditional Chinese | English (parent subtitle) |
| --- | --- | --- |
| `resumeChoice.prompt` | 仲可以繼續睇！ | You can keep watching! |
| `resumeChoice.orPick` | 定係揀第二條？ | Or pick another? |
| `resumeChoice.continue` | 繼續睇 | Continue watching |
| `resumeChoice.pick` | 揀片睇 | Pick a video |
| `resumeChoice.pausedChip` | 停喺呢度 | Paused here |

Never Simplified forms (继续 / 选片 / etc.).

---

## C. State machine (fits PR #12)

### Unchanged (PR #12 / IncompletePlaybackPolicy)

- **Save** on child-play stop when reason ∈ `{budgetExhausted, sessionExpired}` and `positionSeconds > 0`.
- **Never save** on `ended`, nav reject, parent preview, invalid id.
- **Offer** only if cursor valid + id still allowlisted.
- **Clear** on: natural `ended`, allowlist remove of that id, storage reset, **card pick** (`pickOther`).
- Continue uses same id + `activePlayStartSeconds` / embed `start=` + seek; **does not invent budget** (D4).
- Continue does **not** clear cursor until a clear-rule fires (so a second mid-stop can refresh position).

### New routing seam

Extend play presentation after stamp Go:

```
confirmDeparture / play canvas when awaitingDeparture == false:
  if activeVideoID != nil        → Watch
  else if allowlist empty        → EmptyAllowlist
  else if resumeCandidate != nil → Resume Choice   // NEW gate
  else                           → VideoPicker
```

Optional pure helper (testable):  
`PlayStageRoute` gains `.resumeChoice`, or a sibling `PostDepartureRoute.resumeChoice | .videoPicker`.

### Interactions

| Tap / event | Action | Cursor | Next board |
| --- | --- | --- | --- |
| Left Continue | `continueIncompleteVideo()` | kept until later clear | Watch @ seek |
| Right 揀片睇 | `pickOtherFromResumeChoice()` → clear cursor + `activePlayVideoID=nil` | **cleared immediately** (Carter lock) | VideoPicker |
| Picker card | `pickVideo` | **cleared** | Watch from 0 |
| Watch mid-stop again | save new position; TimesUp | updated | TimesUp → … → Resume Choice |
| Watch natural end, time left | clear; picker | cleared | VideoPicker (no Resume Choice) |
| Continue rejected (dead bank) | existing `continueRejected-*` → TimesUp | kept or per today’s stop save | TimesUp |

### TimesUp vs Resume Choice responsibility

- **TimesUp:** “visa trip over — park — earn another ticket.” Single CTA 「再揀車票」. No Continue. No Picker.
- **Resume Choice:** “you have a new ticket AND a paused film — continue it or pick another.” Only when `mode == .play` && `resumeCandidate != nil` && no active video && not awaiting stamp.

---

## D. Open questions (max 5) + recommended default pack

Reply **APPROVE DEFAULTS** (or edit one line) to unlock implementation.

| # | Question | **Recommended default** |
| --- | --- | --- |
| 1 | When does Resume Choice appear — at exhaustion, or after next 「出發！」? | **After next stamp 「出發！」** when `resumeCandidate != nil`. TimesUp at exhaustion stays. |
| 2 | Right → picker: clear incomplete immediately, or keep until card pick? | **Cleared immediately** (Carter lock 2026-10-02; overrides earlier keep-until-pick default). |
| 3 | Left still art: true freeze frame vs thumbnail? | **v1 thumbnail + play badge + 「停喺呢度」**; true WK snapshot deferred. |
| 4 | Demote picker mint Continue banner? | **Yes on primary path** (Resume Choice gate). Keep banner only as fallback. |
| 5 | TimesUp voice when a cursor was just saved — same park line, or soft “come back”? | **Keep today’s** 「…返車廠瞓覺喇！」. Soft “film waiting” line only if UAT shows confusion. |

### One-message approve pack

> **APPROVE DEFAULTS:** Resume Choice after next 「出發！」when incomplete exists; TimesUp unchanged at mid-video stop; Left = Continue (PR #12 seek); Right = VideoPicker keeping cursor until card pick, no Continue banner that visit; v1 YouTube thumbnail still (not WK freeze); demote picker Continue to fallback; TimesUp copy unchanged; HK Trad only.

---

## E. Implementation sketch (files only — later PR)

No code in this pass. Likely touch list:

| Area | Files |
| --- | --- |
| New board UI | `Sources/VisaGames/ResumeChoiceView.swift` **or** extend `StampWatchTimesUpViews.swift` |
| Shell routing | `Sources/VisaGames/AppDelegate.swift` (`ShellView.playCanvasBoard`, `confirmDeparture` / post-stamp gate, `suppressContinueBanner`) |
| Route enum / pure policy | `Sources/VisaCore/ChildUXProgress.swift` (`PlayStageRoute` + tests) |
| Voice lines | `Sources/VisaCore/CantoneseVoice.swift` (`SpokenPrompt` resumeChoice.*) |
| Picker banner gate | `Sources/VisaGames/VideoPickerView.swift` (hide Continue when suppressed) |
| Continue / cursor (reuse) | `Sources/VisaGames/AppDelegate.swift` (`continueIncompleteVideo`, `pickVideo`, `resumeCandidate`) — behavior unchanged |
| Incomplete policy (reuse) | `Sources/VisaCore/IncompletePlayback.swift` — likely untouched |
| Tests | `Tests/VisaCoreTests/…` route + “after Go → resumeChoice vs picker”; banner suppress; Right keeps cursor |
| Docs | `PROGRESS.md`, optional ADR note under `docs/decisions/` or amend 0007 |
| Concept art (optional) | `docs/concept-canvas-boards/08-resume-choice.png` |

**Out of scope for that PR:** WK freeze capture, passport board, recorded voice clips, changing D4/D8, merging unrelated branches.

**Suggested version:** next MINOR after v0.14.0 (e.g. v0.15.0) once defaults approved.

---

## Fit check vs existing boards

| Board | Role after this design |
| --- | --- |
| StampSuccess | Unchanged; 「出發！」still presentation gate. |
| WatchPlayback | Unchanged; road timer + garage parent hold. |
| TimesUp | Still the only “no time left / trip over” board. |
| VideoPicker | Still mid-visa film choice; Continue banner demoted. |
| Resume Choice | **New** first choice when a paused film + new visa meet. |

