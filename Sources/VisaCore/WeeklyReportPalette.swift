import Foundation

// Weekly report W4 (weekly-report design §8): every colour the report HTML may use, in one place. The CSS
// and the SVG charts read these tokens only; `testHTMLPaletteTokens` requires every hex in the rendered
// HTML to be one of them. ADR 0024 records the validator run.

public enum WeeklyReportPalette {
    /// Slots 1–3 of the validated reference palette (design §8), light mode on a white page. Checked with
    /// `validate_palette.js "#2a78d6,#eb6834,#1baf7a" --mode light --surface "#ffffff"` (adjacent pairs and
    /// all pairs: every check passes; aqua is below 3:1 on white, so every chart carries direct labels or a
    /// table). Colour follows the entity across the report.
    public static let quiz = "#2a78d6"
    public static let video = "#eb6834"
    public static let practice = "#1baf7a"
    public static let validatedSeries = [quiz, video, practice]

    /// Ink: primary, secondary (also the last-week marker), muted (axes, notes).
    public static let ink = "#0b0b0b"
    public static let ink2 = "#52514e"
    public static let muted = "#898781"
    /// Gridlines and the lucky-guess band (§8 uses the same hex for both), the baseline, the page.
    public static let grid = "#e1e0d9"
    public static let guessBand = "#e1e0d9"
    public static let baseline = "#c3c2b7"
    public static let surface = "#ffffff"
    /// Matrix cell tints: the series colour at 12 % on white, 255 − round(0.12 × (255 − c)) per channel.
    public static let quizTint = "#e5effa"
    public static let practiceTint = "#e4f5ef"
    /// Chrome from the app's brand tokens (`DesignTokens.Palette`): passport blue, paper, taxi and metro tickets.
    public static let brand = "#2f4b8f"
    public static let paper = "#fff6df"
    public static let ticket = "#fff4c7"
    public static let metro = "#ddebff"
    /// The sample tag and watermark (mockup), panel and badge greys, badge outlines.
    public static let stamp = "#b8312f"
    public static let panel = "#f6f5f1"
    public static let badgeGrey = "#f1f0ec"
    public static let badgeQuizLine = "#9ec5f4"
    public static let badgePracticeLine = "#8fd8bd"
    public static let badgeNew = "#fde3d7"
    public static let badgeNewLine = "#f3b39a"

    public static let all: [String] = [
        quiz, video, practice, ink, ink2, muted, grid, guessBand, baseline, surface, quizTint, practiceTint, brand,
        paper, ticket, metro, stamp, panel, badgeGrey, badgeQuizLine, badgePracticeLine, badgeNew, badgeNewLine
    ]
}
