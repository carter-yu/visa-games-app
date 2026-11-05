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

## Module map

### Package and entry points

- `Package.swift`: `VisaCore` library target, `VisaGames` macOS executable target, and `VisaCoreChecks` test executable target at `Tests/VisaCoreTests` with `Fixtures` excluded.
- `Sources/VisaCore/`: Foundation-level rules, generators, persistence, playback policy, and reports.
- `Sources/VisaGames/`: SwiftUI/AppKit application, child and parent screens, playback surface, and bundle-facing integrations.
- `Sources/VisaGames/main.swift`: executable entry point.
- `Sources/VisaGames/AppDelegate.swift`: `AppModel`, `AppDelegate`, `KioskWindow`, and `ShellView`; app state and native window shell.

### Core rules and activities

- `Sources/VisaCore/Session.swift`: `Session`, `Snapshot`, and `SnapshotStore` for mode, visa expiry, and saved state.
- `Sources/VisaCore/ResilientSnapshotStore.swift`: recovery boundary around saved snapshots.
- `Sources/VisaCore/RewardLedger.swift`: `RewardLedger` and reward policy/accounting.
- `Sources/VisaCore/Activity.swift`, `Sources/VisaCore/QuestionGenerator.swift`: activity model and question generation.
- `Sources/VisaCore/MissionTicket.swift`, `Sources/VisaCore/MissionGameAssignment.swift`: tickets and game assignment.
- `Sources/VisaCore/ChildDifficulty.swift`, `Sources/VisaCore/ChildUXProgress.swift`: child difficulty and progress rules.
- `Sources/VisaCore/CountVehiclesGenerator.swift`, `Sources/VisaCore/FindTheSameGenerator.swift`: early activity generators.
- `Sources/VisaCore/TapCountBoard.swift`, `Sources/VisaCore/TapCountCatalog.swift`: tap-count board and content catalog; adjacent `TapCount` files cover art, guidance, hit layout, and copy.
- `Sources/VisaCore/ShapeTraceEngine.swift`, `Sources/VisaCore/ShapeTraceCatalog.swift`: shape-trace state and content; adjacent `ShapeTraceArt.swift` supplies art.
- `Sources/VisaCore/LineMatchBoard.swift`, `Sources/VisaCore/LineMatchGenerator.swift`: line-match board and deals; adjacent `LineMatch` files cover catalog, guided play, and art.
- `Sources/VisaCore/TapLetterBoard.swift`, `Sources/VisaCore/TapLetterWrite.swift`: letter find and write board rules.
- `Sources/VisaCore/LetterWordBank.swift`, `Sources/VisaCore/LetterDeals.swift`: word bank and letter deals.
- `Sources/VisaCore/LetterSelectionSettings.swift`, `Sources/VisaCore/LetterPickerDraft.swift`: saved letter selection and parent editing draft.
- `Sources/VisaCore/LetterSelectionSchedule.swift`, `Sources/VisaCore/LetterTicketEligibility.swift`: letter scheduling and ticket availability; adjacent `Letter` files cover picker validation, guides, history, and summaries.
- `Sources/VisaCore/LatinGlyphs.swift`, `Sources/VisaCore/StrokeOrder.swift`: letter glyph paths and stroke-order data.
- `Sources/VisaCore/CanvasArt.swift`, `Sources/VisaCore/DesignTokens.swift`: canvas art primitives and design values.

### Core playback, records, and reports

- `Sources/VisaCore/ApprovedVideo.swift`, `Sources/VisaCore/VideoPickerDeck.swift`: approved video data and picker ordering.
- `Sources/VisaCore/PlaybackPolicy.swift`, `Sources/VisaCore/YouTubeEmbedURL.swift`: playback limits and scoped embed URL policy.
- `Sources/VisaCore/ProviderBlockedPolicy.swift`, `Sources/VisaCore/IncompletePlayback.swift`: blocked-provider and interrupted-playback decisions.
- `Sources/VisaCore/PerformanceEvent.swift`, `Sources/VisaCore/PerformanceEventStore.swift`: performance event schema and storage.
- `Sources/VisaCore/PerformanceTrackers.swift`, `Sources/VisaCore/PerformanceReport.swift`, `Sources/VisaCore/PerformanceCSV.swift`: event capture, review, and CSV export.
- `Sources/VisaCore/MasteryEstimator.swift`, `Sources/VisaCore/WeeklyMetrics.swift`: learning estimates and weekly metrics.
- `Sources/VisaCore/WeeklyAnalysis.swift`, `Sources/VisaCore/WeeklyRanking.swift`, `Sources/VisaCore/WeeklyComparison.swift`: weekly analysis, ranking, and comparisons.
- `Sources/VisaCore/WeeklyReportText.swift`, `Sources/VisaCore/WeeklyReportHTML.swift`: text and HTML report output.
- `Sources/VisaCore/WeeklyReportPDFMaker.swift`, `Sources/VisaCore/WeeklyReportExport.swift`: PDF creation and report export; adjacent `WeeklyReport` files hold layout, charts, labels, and styling.

### App screens and integration

- `Sources/VisaGames/DepotHomeView.swift`, `Sources/VisaGames/StampWatchTimesUpViews.swift`: child home, ticket, stamp, watch, and time-up screens.
- `Sources/VisaGames/ActivityBoardView.swift`, `Sources/VisaGames/CanvasActivityHost.swift`: child activity host and board routing.
- `Sources/VisaGames/TapCountBoardView.swift`, `Sources/VisaGames/ShapeTraceBoardView.swift`, `Sources/VisaGames/LineMatchBoardView.swift`: child activity boards.
- `Sources/VisaGames/TapLetterBoardView.swift`, `Sources/VisaGames/TapLetterWriteBoardView.swift`: child letter boards.
- `Sources/VisaGames/ParentSettingsView.swift`, `Sources/VisaGames/ParentGameCard.swift`: parent controls and game settings entry.
- `Sources/VisaGames/ParentTapLetterSettingsView.swift`, `Sources/VisaGames/ParentPracticeItemPicker.swift`: parent letter selection UI.
- `Sources/VisaGames/ParentTapCountSettingsView.swift`, `Sources/VisaGames/ParentShapeTraceSettingsView.swift`, `Sources/VisaGames/ParentLineMatchSettingsView.swift`: activity-specific parent settings.
- `Sources/VisaGames/ParentReviewView.swift`, `Sources/VisaGames/WeeklyReportCoordinator.swift`: parent performance review and weekly report export flow.
- `Sources/VisaGames/ParentYouTubeBrowserView.swift`, `Sources/VisaGames/VideoPickerView.swift`: parent video finder and child approved-video picker.
- `Sources/VisaGames/ScopedPlayerView.swift`, `Sources/VisaGames/ResumeChoiceView.swift`: scoped playback surface and resume choice.
- `Sources/VisaGames/PerformanceRecorder.swift`, `Sources/VisaGames/SystemSpeechPrompt.swift`: app-side event recording and spoken prompts.
- `Sources/VisaGames/DesignSystem.swift`, `Sources/VisaGames/ThemeViews.swift`: shared presentation and theme views.

### Checks, scripts, and assets

- `Tests/VisaCoreTests/`: offline checks for session, persistence, rewards, activities, playback, performance, and weekly reports; `SessionTests.swift` contains the executable test runner.
- `Tests/VisaCoreTests/Fixtures/`: report and Traditional Chinese fixture data, excluded from the test target's compiled sources.
- `scripts/test.sh`: box/Mac mini unit tests; builds `VisaCoreChecks` with `swift build --product VisaCoreChecks`, then runs `.build/debug/VisaCoreChecks`.
- `scripts/bundle.sh`: builds the release executable and assembles/signs `.build/Visa Games.app`.
- `scripts/install-mac-mini.sh`: installs the bundle on the family Mac mini; orchestrator only after Carter OK. Do not run it here.
- `scripts/`: also contains asset and guidance-spec generation helpers.
- `Resources/Info.plist`: app bundle metadata and version.
- `Resources/Fonts/`: bundled Baloo 2 and Noto Sans HK fonts with license files.
- `Resources/LetterTap/`: starter letter-word bank JSON.
- `Resources/Vehicles/`: illustrated vehicle PNGs and provenance notes.
- `Resources/Props/`: child-world prop PNGs and provenance notes.
- `Resources/Voice/`: optional recorded voice assets and notes.
- `Resources/AppIcon.icns`, `Resources/AppIcon.iconset/`: packaged icon and source icon set.

### Docs and commands

- `README.md`: product invariants, native target, and basic build instructions; `PROGRESS.md`: dated implementation and verification record.
- `CODEX_START.md`, `AGENTS.md`: initial task prompt and repository working rules.
- `phases/`: phase scopes and exit evidence; `phases/phase-6-performance-review.md` covers the latest listed phase.
- `docs/ground-rules.md`, `docs/phase-0-kiosk-checklist.md`: product rules and target-device kiosk checks.
- `docs/decisions/`: architecture and product decision records (ADRs).
- `docs/designs/`, `docs/concept-canvas-boards/`: design notes and child-screen concept images.
- `docs/ux-rebuild-brief.md`, `docs/parent-scroll-diagnostics.md`: UX direction and parent-scroll investigation.
- Box: `env PATH=/tmp/visa-games-swift/toolchain/usr/bin:/usr/bin:/bin bash scripts/test.sh`
- Mac mini: `bash scripts/test.sh` (and `bash scripts/bundle.sh` when packaging)
