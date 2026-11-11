import Foundation

// Clock + elapsed status chip C0 (0.39.0 / 85): where the chip sits. clock-playtime design §2.1–2.5 and Locked
// decision 1 at the R2 size (84 × 40 u, Carter 2026-11-10); chip-rows/compare.md FINAL v1 §4–§5. Canvas units on the
// 1280 × 720 artboard, mapped to screen points with `DesignTokens.stageLayout`. Pure geometry for the Linux collision
// and Watch-strip checks; the app's `StatusClockLayer` (C1, 0.39.0 / 86) draws the chip at `rect(for:)`, and the
// Watch view is unchanged until C5.

// MARK: - Routes

/// The screens of design §2.3, rows 1–13: the child screens and, since D-C0c (Carter 2026-11-10), Setup. The parent
/// surfaces (rows 14–16) are not here: the parent bars lay the chip out themselves (C2).
public enum StatusRoute: CaseIterable, Sendable {
    /// Depot home (row 1).
    case depot
    /// The Board-2 games in `ActivityBoardView` (row 2): the cone + fuel cluster ends at x 1164.
    case boardTwo
    /// Hanzi and Letter find / write (row 3): the header ends at x 1182.
    case hanziLetter
    /// LineMatch, ShapeTrace and TapCount (row 4): today's header panel and visa badge run under S.
    case lineMatchFamily
    /// Visa stamped (row 5).
    case stamp
    /// Time's up (row 6).
    case timesUp
    /// Resume choice (row 7).
    case resumeChoice
    /// Video picker and the resume-fallback picker (row 8): the ticket art sits at x 1134–1244.
    case videoPicker
    /// Empty allowlist (row 9).
    case emptyAllowlist
    /// Letter ticket unavailable (row 10).
    case letterUnavailable
    /// Provider blocked (row 11).
    case providerBlocked
    /// Watch, the real video (row 12).
    case watch
    /// Setup, the legacy shell before a parent finishes setup (row 13). D-C0c: the chip shows here too; the top right
    /// holds only the decorative sun accent.
    case setup

    /// The header family of a game board (rows 2–4), as `CanvasActivityHost` routes the kinds. Exhaustive, so a new
    /// kind has to pick its family.
    public init(board kind: ActivityKind) {
        switch kind {
        case .twoPictureChoose, .findTheSame, .countVehicles, .sequenceShortToLong, .halfMatch, .shapeCousin,
             .capacityCompare, .moreFewer, .shadowMatch, .emptyBay:
            self = .boardTwo
        case .tapLetterAll, .tapLetterWrite, .tapHanziAll, .tapHanziWrite:
            self = .hanziLetter
        case .lineMatch, .lineMatchGuidedStraight, .lineMatchGuidedBridge,
             .traceLines, .traceShapesDotted, .traceShapesArrows, .traceShapesFree,
             .tapCountAll, .tapCountTrace, .tapCountPick, .tapCountAllEnglish, .tapCountTraceEnglish, .tapCountPickEnglish:
            self = .lineMatchFamily
        }
    }
}

// MARK: - Slots

/// The R2 chip's slots and keep-outs (canvas units).
public enum StatusSlot {
    public static let chipWidth: Double = 84
    public static let chipHeight: Double = 40

    /// S: x 1190–1274, y 6–46 (113.4 × 54.0 pt on a 1920 × 1080 TV).
    public static let main = LineMatchRect(x: 1190, y: 6, width: chipWidth, height: chipHeight)
    /// K around S: x 1182–1280, y 0–56. No board element may enter it.
    public static let mainKeepOut = LineMatchRect(x: 1182, y: 0, width: 98, height: 56)
    /// S_pick: x 1042–1126, y 6–46, in the picker HUD's spacer, 8 u left of the ticket art.
    public static let picker = LineMatchRect(x: 1042, y: 6, width: chipWidth, height: chipHeight)
    /// K_pick: x 1034–1132, y 0–56.
    public static let pickerKeepOut = LineMatchRect(x: 1034, y: 0, width: 98, height: 56)
    /// The Watch strip chip on a 16:9 screen: x 1196–1280, y 0–40, its right edge on the safe line (`WatchStripLayout`
    /// places it on any screen).
    public static let watchStrip = LineMatchRect(x: 1196, y: 0, width: chipWidth, height: chipHeight)

    /// The chip on `route`, or nil while it is hidden there: the LM family until the C4 header nudge (today's header
    /// covers S) and Watch until the C5 strip. Setup uses S (D-C0c).
    public static func rect(for route: StatusRoute) -> LineMatchRect? { placement(route)?.slot }

    /// The keep-out around `rect(for:)`.
    public static func keepOut(for route: StatusRoute) -> LineMatchRect? { placement(route)?.keepOut }

    private static func placement(_ route: StatusRoute) -> (slot: LineMatchRect, keepOut: LineMatchRect)? {
        switch route {
        case .depot, .boardTwo, .hanziLetter, .stamp, .timesUp, .resumeChoice, .emptyAllowlist, .letterUnavailable,
             .providerBlocked, .setup:
            return (main, mainKeepOut)
        case .videoPicker:
            return (picker, pickerKeepOut)
        case .lineMatchFamily, .watch:
            // No slot until C4 nudges the LM header (§2.4) and C5 adds the Watch strip (§2.5); `StatusChipPlan`
            // names the same two routes as C1's hidden rule.
            return nil
        }
    }

    /// A canvas rect in screen points: the stage's scale and origin (`DesignTokens.stageLayout`).
    public static func onScreen(_ rect: LineMatchRect, screenWidth: Double, screenHeight: Double) -> LineMatchRect {
        let stage = DesignTokens.stageLayout(screenWidth: screenWidth, screenHeight: screenHeight)
        return LineMatchRect(x: stage.originX + rect.x * stage.scale, y: stage.originY + rect.y * stage.scale,
                             width: rect.width * stage.scale, height: rect.height * stage.scale)
    }

    /// The TV safe rect in screen points: `DesignTokens.safeAreaFraction` in from every edge.
    public static func safeRect(screenWidth: Double, screenHeight: Double) -> LineMatchRect {
        let inset = DesignTokens.safeAreaFraction
        return LineMatchRect(x: screenWidth * inset, y: screenHeight * inset,
                             width: screenWidth * (1 - 2 * inset), height: screenHeight * (1 - 2 * inset))
    }
}

// MARK: - Watch strip

/// Watch with the C5 status strip above the player (design §2.5, Decision 7; R2 figures in compare.md §4), or today's
/// Watch without it, in screen points. Watch lays out from the screen edges, not the canvas, so the chip sits at the
/// top right of the TV safe rect (§2.5: safeTop is 5% of the screen height) and the player's top moves to 8 u under it.
/// The sides, road strip and bottom stay as today, and nothing is drawn over the web view.
public struct WatchStripLayout: Equatable, Sendable {
    // Today's Watch (`StampWatchTimesUpViews` watchBody), in canvas units at the stage scale.
    public static let sideInset: Double = 36
    public static let topInset: Double = 20
    public static let stackSpacing: Double = 12
    public static let roadHeight: Double = 78
    public static let bottomInset: Double = 20
    public static let webViewInset: Double = 8
    /// Clear space between the chip and the player.
    public static let chipGap: Double = 8

    /// The night-tone chip; nil without the strip.
    public let chip: LineMatchRect?
    /// The player frame (dark panel with the metro outline).
    public let player: LineMatchRect
    /// The web view, inset inside the frame.
    public let webView: LineMatchRect
    /// A 16:9 video fitted and centred in the web view.
    public let video: LineMatchRect

    public init(screenWidth width: Double, screenHeight height: Double, strip: Bool) {
        let u = DesignTokens.stageLayout(screenWidth: width, screenHeight: height).scale
        let safe = StatusSlot.safeRect(screenWidth: width, screenHeight: height)
        let chip = strip
            ? LineMatchRect(x: safe.maxX - StatusSlot.chipWidth * u, y: safe.y,
                            width: StatusSlot.chipWidth * u, height: StatusSlot.chipHeight * u)
            : nil
        let top = max(Self.topInset * u, chip.map { $0.maxY + Self.chipGap * u } ?? 0)
        let bottom = height - (Self.bottomInset + Self.roadHeight + Self.stackSpacing) * u
        let player = LineMatchRect(x: Self.sideInset * u, y: top, width: width - 2 * Self.sideInset * u,
                                   height: bottom - top)
        let inset = Self.webViewInset * u
        let web = LineMatchRect(x: player.x + inset, y: player.y + inset,
                                width: player.width - 2 * inset, height: player.height - 2 * inset)
        let videoWidth = min(web.width, web.height * 16 / 9)
        let videoHeight = videoWidth * 9 / 16
        self.chip = chip
        self.player = player
        self.webView = web
        self.video = LineMatchRect(x: web.midX - videoWidth / 2, y: web.midY - videoHeight / 2,
                                   width: videoWidth, height: videoHeight)
    }

    /// This video against `today`'s as signed fractions: linear (width) and area. −0.104 is 10.4% smaller.
    public func videoChange(from today: WatchStripLayout) -> (linear: Double, area: Double) {
        (video.width / today.video.width - 1,
         video.width * video.height / (today.video.width * today.video.height) - 1)
    }
}
