import Foundation

/// Board 1 mission tickets. Stars and road tiles restate the Confirmed 10 / 20 / 30 minute
/// difficulties (one road tile = 10 minutes); no reward policy lives here.
public struct MissionTicket: Equatable, Sendable {
    public let difficulty: ChildDifficulty
    public let titleTraditionalChinese: String
    public let titleEnglish: String
    public let artwork: CanvasArtwork
    public let bodyColor: UInt32
    public let headerColor: UInt32

    public var stars: Int { difficulty.rawValue }
    public var roadTiles: Int { difficulty.minutes / 10 }
    public var minutesLabel: String { "\(difficulty.minutes) 分鐘" }
    public var accessibilityLabel: String {
        "\(titleTraditionalChinese)：\(difficulty.minutes) 分鐘 / \(titleEnglish): \(difficulty.minutes) minutes"
    }

    public static let all: [MissionTicket] = [
        MissionTicket(difficulty: .easy, titleTraditionalChinese: "的士短程", titleEnglish: "Taxi hop",
                      artwork: CanvasArt.taxi,
                      bodyColor: DesignTokens.Palette.taxiTicket, headerColor: DesignTokens.Palette.sunnyPale),
        MissionTicket(difficulty: .medium, titleTraditionalChinese: "消防車任務", titleEnglish: "Fire mission",
                      artwork: CanvasArt.fireEngine,
                      bodyColor: DesignTokens.Palette.fireTicket, headerColor: DesignTokens.Palette.fireTicketHeader),
        MissionTicket(difficulty: .challenge, titleTraditionalChinese: "地鐵長程", titleEnglish: "Metro ride",
                      artwork: CanvasArt.metro,
                      bodyColor: DesignTokens.Palette.metroTicket, headerColor: DesignTokens.Palette.metroTicketHeader)
    ]
}
