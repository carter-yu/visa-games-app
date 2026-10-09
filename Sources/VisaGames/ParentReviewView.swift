import SwiftUI
import VisaCore

// MARK: - v0.21.0 表現 / Review (design §8.4–8.5, layout L5) — parent-only

/// Report lifecycle in `AppModel`. Built off-main by `PerformanceRecorder.buildReport`.
enum PerfReviewState: Equatable {
    case idle
    case computing(previous: PerfReport?)
    case ready(PerfReport)

    var report: PerfReport? {
        switch self {
        case .idle: return nil
        case .computing(let previous): return previous
        case .ready(let report): return report
        }
    }

    var isComputing: Bool {
        if case .computing = self { return true }
        return false
    }
}

/// 表現 segment: 遊戲表現 / 影片表現 tabs over one precomputed `PerfReport`.
///
/// Layout safety (parent SIGBUS history): no I/O or heavy work in `body` (the report is a
/// finished value), `Equatable` + `.equatable()` so the 0.5 s clock tick does not re-render it,
/// plain VStack / HStack rows only (no lazy stacks, grids or geometry readers), no animations,
/// and every control is a full-row `Button` with a rectangular hit area.
struct ParentReviewView: View, Equatable {
    let state: PerfReviewState
    let window: PerfReportWindow
    let uatOn: Bool
    let onRefresh: () -> Void
    let onWindow: (PerfReportWindow) -> Void
    let onSetSessionExcluded: (String, Bool) -> Void

    @State private var tab: ReviewTab = .games
    @State private var selectedGame: ActivityKind?
    @State private var selectedVideo: String?

    enum ReviewTab { case games, videos }

    static func == (lhs: ParentReviewView, rhs: ParentReviewView) -> Bool {
        lhs.state == rhs.state && lhs.window == rhs.window && lhs.uatOn == rhs.uatOn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            tabBar
            headerBar
            notes
            content
        }
        .padding(18)
        .modifier(ChunkyPanel(fill: .white, cornerRadius: 22, shadowDepth: 5, lineWidth: 3))
        .transaction { $0.animation = nil }
    }

    // MARK: Tabs + header

    private var tabBar: some View {
        HStack(spacing: 12) {
            ReviewTabButton(title: "遊戲表現", subtitle: "Games", selected: tab == .games,
                            action: { selectTab(.games) })
            ReviewTabButton(title: "影片表現", subtitle: "Videos", selected: tab == .videos,
                            action: { selectTab(.videos) })
        }
    }

    private func selectTab(_ next: ReviewTab) {
        guard tab != next else { return }
        tab = next
        VisaGamesLog.append("parent review — tab \(next == .games ? "games" : "videos")")
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            ReviewChipButton(title: PerfReportWindow.days30.zh, selected: window == .days30,
                             action: { onWindow(.days30) })
            ReviewChipButton(title: PerfReportWindow.all.zh, selected: window == .all,
                             action: { onWindow(.all) })
            Spacer(minLength: 8)
            if state.isComputing {
                ReviewText("計緊…", size: 13, weight: .semibold, color: .inkSoft)
            } else if let report = state.report {
                ReviewText("更新於 \(ReviewFormat.time(report.builtAt))", size: 13, weight: .semibold, color: .inkSoft)
            }
            ReviewChipButton(title: "更新", symbol: "arrow.clockwise", selected: false, action: onRefresh)
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 4) {
            if uatOn {
                ReviewText("🧪 測試模式開緊：而家玩嘅唔會計。", size: 14, weight: .bold)
            }
            ReviewText("只計小朋友自己玩。家長試玩、測試簽證、測試模式都唔計。", size: 13, weight: .regular, color: .inkSoft)
            ReviewText("紀錄只存喺呢部 Mac，唔會上網。", size: 13, weight: .regular, color: .inkSoft)
        }
    }

    // MARK: Content states

    @ViewBuilder
    private var content: some View {
        if let report = state.report {
            if report.isEmpty {
                emptyState
            } else {
                switch tab {
                case .games: gamesTab(report)
                case .videos: videosTab(report)
                }
                sessionsBlock(report)
            }
        } else {
            ReviewText("計緊…", size: 18, weight: .bold, color: .inkSoft)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            ReviewText("未有紀錄", size: 22, weight: .heavy)
            ReviewText("小朋友玩幾次之後，呢度就會見到每個遊戲同影片嘅表現。", size: 15, weight: .regular)
            ReviewText("每個遊戲要玩夠 5 次先會有標籤，未夠就會寫「未夠數據」。", size: 14, weight: .regular, color: .inkSoft)
            ReviewText("No records yet. Each game needs 5 rounds before it gets a label.", size: 13, weight: .regular,
                       color: .inkSoft)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.ink.opacity(0.05)))
    }

    // MARK: 遊戲表現

    @ViewBuilder
    private func gamesTab(_ report: PerfReport) -> some View {
        glance(report)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(report.games) { row in
                GameReviewRow(row: row, selected: selectedGame == row.kind, action: { toggleGame(row.kind) })
                if selectedGame == row.kind {
                    GameReviewDetail(row: row)
                }
            }
            ReviewText("● 一次答啱　◐ 試多次先啱　○ 油用晒　· 未完成", size: 13, weight: .regular, color: .inkSoft)
        }
    }

    private func toggleGame(_ kind: ActivityKind) {
        selectedGame = selectedGame == kind ? nil : kind
    }

    private func glance(_ report: PerfReport) -> some View {
        let confident = report.glanceConfident.map(\.kind.parentCardTitle)
        let practise = report.glancePractise.map(\.kind.parentCardTitle)
        let fuel = report.games.filter { $0.fuelOutFlag != nil }
        return VStack(alignment: .leading, spacing: 6) {
            ReviewText("一眼睇", size: 17, weight: .heavy)
            if confident.isEmpty && practise.isEmpty {
                ReviewText("未有遊戲玩夠 5 次（未夠數據）。", size: 14, weight: .regular, color: .inkSoft)
            }
            if !confident.isEmpty {
                ReviewText("熟手：\(confident.joined(separator: "、"))", size: 14, weight: .semibold)
            }
            if !practise.isEmpty {
                ReviewText("要多練：\(practise.joined(separator: "、"))", size: 14, weight: .semibold)
            }
            ForEach(fuel) { row in
                ReviewText("\(row.kind.parentCardTitle)：最近油用晒 \(row.fuelOutFlag ?? 0) 次", size: 14, weight: .regular)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hex: DesignTokens.Palette.sunnyPale)))
    }

    // MARK: 影片表現

    @ViewBuilder
    private func videosTab(_ report: PerfReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let rate = report.pagingRate {
                ReviewText("\(ReviewFormat.percent(rate))% 次會揭去第 2 頁", size: 15, weight: .semibold)
            }
            ReviewText("撳邊個位多", size: 15, weight: .semibold)
            SlotMap(shares: report.slotShares)
            if report.noTelemetryPlays > 0 {
                ReviewText("\(report.noTelemetryPlays) 次冇播放資料", size: 13, weight: .regular, color: .inkSoft)
            }
            if report.navGuardStops > 0 {
                ReviewText("\(report.navGuardStops) 次因為撳咗 YouTube 畫面上嘅連結而停（技術原因，唔影響標籤）",
                           size: 13, weight: .regular, color: .inkSoft)
            }
            ReviewText("播放結果只供參考，唔影響標籤。", size: 13, weight: .regular, color: .inkSoft)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.ink.opacity(0.05)))
        VStack(alignment: .leading, spacing: 8) {
            if report.videos.isEmpty {
                ReviewText("片單未有片。 / No videos on the list.", size: 14, weight: .regular, color: .inkSoft)
            }
            ForEach(report.videos) { row in
                VideoReviewRow(row: row, selected: selectedVideo == row.id, action: { toggleVideo(row.id) })
                if selectedVideo == row.id {
                    VideoReviewDetail(row: row)
                }
            }
        }
    }

    private func toggleVideo(_ id: String) {
        selectedVideo = selectedVideo == id ? nil : id
    }

    // MARK: 最近玩過

    private func sessionsBlock(_ report: PerfReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ReviewText("最近玩過", size: 17, weight: .heavy)
            if report.sessions.isEmpty {
                ReviewText("近 7 日未有。", size: 14, weight: .regular, color: .inkSoft)
            }
            ForEach(report.sessions) { session in
                SessionReviewRow(session: session, action: { onSetSessionExcluded(session.id, !session.excluded) })
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Rows and pieces (plain, fixed-size)

private struct ReviewText: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    var color: Color = .ink

    init(_ text: String, size: CGFloat, weight: Font.Weight, color: Color = .ink) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum ReviewFormat {
    static func time(_ date: Date) -> String {
        String(PerfClock.timeStamp(date, timeZone: PerfClock.hongKong).prefix(5))
    }

    /// 「10月9日」 from the HKT day stamp.
    static func date(_ date: Date) -> String {
        let parts = PerfClock.dayStamp(date, timeZone: PerfClock.hongKong).split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return "" }
        return "\(month)月\(day)日"
    }

    static func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }

    static func seconds(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(Int(value.rounded()))
    }
}

private struct ReviewTabButton: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ParentLabel(title, size: 20, weight: 900)
                ParentLabel(subtitle, size: 12, weight: 700, color: .inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: selected ? Color(hex: DesignTokens.Palette.sunnyPale) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 14, shadowDepth: selected ? 2 : 4, lineWidth: 3
        ))
        .accessibilityLabel("\(title) \(subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ReviewChipButton: View {
    let title: String
    var symbol: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: selected ? Color(hex: DesignTokens.Palette.sunnyPale) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 12, shadowDepth: selected ? 1 : 3, lineWidth: 2
        ))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LabelPill: View {
    let text: String
    let fill: Color

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.ink)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(width: 96)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2))
    }

    static func fill(_ label: PerfMastery.Label) -> Color {
        switch label {
        case .confident: return Color(hex: DesignTokens.Palette.mint)
        case .learning: return Color(hex: DesignTokens.Palette.sunnyPale)
        case .practise: return Color(hex: DesignTokens.Palette.fireTicket)
        case .insufficient: return Color(hex: DesignTokens.Palette.glass)
        }
    }

    static func fill(_ label: PerfVideoAppeal.Label) -> Color {
        switch label {
        case .favourite: return Color(hex: DesignTokens.Palette.mint)
        case .sometimes: return Color(hex: DesignTokens.Palette.sunnyPale)
        case .rare, .seenNever: return Color(hex: DesignTokens.Palette.taxiTicket)
        case .insufficient, .notShown: return Color(hex: DesignTokens.Palette.glass)
        }
    }
}

/// Full-row button; the whole row is the hit area.
private struct ReviewRowButton<Content: View>: View {
    let selected: Bool
    let accessibility: String
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                content()
                Spacer(minLength: 6)
                Image(systemName: selected ? "chevron.down" : "chevron.right")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.inkSoft)
                    .frame(width: 16)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color(hex: DesignTokens.Palette.sunnyPale) : Color(hex: DesignTokens.Palette.paper)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.ink, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct GameReviewRow: View {
    let row: PerfGameRow
    let selected: Bool
    let action: () -> Void

    var body: some View {
        ReviewRowButton(selected: selected, accessibility: "\(row.kind.parentCardTitle) \(row.label.zh)", action: action) {
            LabelPill(text: row.label.zh, fill: LabelPill.fill(row.label))
            VStack(alignment: .leading, spacing: 1) {
                Text(row.kind.parentCardTitle)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                Text(summary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.inkSoft)
                    .lineLimit(1)
            }
            .frame(width: 260, alignment: .leading)
            Text(row.dots.map(\.glyph).joined(separator: " "))
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .lineLimit(1)
            if let trend = row.trend {
                Text(trend.arrow).font(.system(size: 16, weight: .heavy, design: .rounded))
            }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if row.label == .insufficient && row.roundsMissing > 0 {
            parts.append("仲差 \(row.roundsMissing) 次")
        }
        parts.append("\(row.answered) 次 · 一次答啱 \(row.firstTry)")
        if let fuel = row.fuelOutFlag { parts.append("最近油用晒 \(fuel) 次") }
        return parts.joined(separator: " · ")
    }
}

private struct GameReviewDetail: View {
    let row: PerfGameRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if row.label == .insufficient {
                ReviewText("未夠數據 · 仲差 \(max(row.roundsMissing, 0)) 次", size: 15, weight: .bold)
                if row.roundsMissing == 0 {
                    ReviewText("最近玩得少，舊紀錄計少啲；再玩幾次就會有標籤。", size: 13, weight: .regular, color: .inkSoft)
                }
            }
            ReviewText("掌握度 \(ReviewFormat.percent(row.estimate.mastery))%"
                       + "（\(ReviewFormat.percent(row.estimate.masteryLow))%–\(ReviewFormat.percent(row.estimate.masteryHigh))%）",
                       size: 15, weight: .semibold)
            ReviewText("已扣除估中機會（兩揀一 50%，三揀一 33%）", size: 12, weight: .regular, color: .inkSoft)
            ForEach(row.stars, id: \.stars) { star in
                ReviewText(String(repeating: "★", count: star.stars)
                           + "　\(star.rounds) 次 · 一次答啱 \(star.firstTry) · 油用晒 \(star.fuelOuts)",
                           size: 14, weight: .regular)
            }
            if let seconds = row.medianActiveSeconds {
                ReviewText("通常 \(ReviewFormat.seconds(seconds)) 秒答啱", size: 14, weight: .regular)
            }
            if let seconds = row.medianFirstTapSeconds {
                ReviewText("第一下通常 \(ReviewFormat.seconds(seconds)) 秒", size: 14, weight: .regular)
            }
            ReviewText(row.trend?.zh ?? "近 7 日：未夠數據", size: 14, weight: .regular)
            if let last = row.lastPlayed {
                ReviewText("上次玩：\(ReviewFormat.date(last))", size: 13, weight: .regular, color: .inkSoft)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.ink.opacity(0.05)))
    }
}

private struct VideoReviewRow: View {
    let row: PerfVideoRow
    let selected: Bool
    let action: () -> Void

    var body: some View {
        ReviewRowButton(selected: selected, accessibility: "\(row.title) \(row.label.zh)", action: action) {
            LabelPill(text: row.label.zh, fill: LabelPill.fill(row.label))
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                Text("揀咗 \(row.picks) 次／見過 \(row.impressions) 次")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.inkSoft)
                    .lineLimit(1)
            }
        }
    }
}

private struct VideoReviewDetail: View {
    let row: PerfVideoRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReviewText("播咗 \(row.plays) 次 · 睇咗 \(row.watchedMinutes) 分鐘 · 睇完 \(row.completions) 次",
                       size: 14, weight: .regular)
            ReviewText("時間到停咗 \(row.timeUpStops) 次 · 之後繼續睇 \(row.timeUpResumedLater) 次",
                       size: 14, weight: .regular)
            if let last = row.lastPicked {
                ReviewText("上次揀：\(ReviewFormat.date(last))", size: 14, weight: .regular)
            }
            if row.noTelemetryPlays > 0 {
                ReviewText("\(row.noTelemetryPlays) 次冇播放資料", size: 13, weight: .regular, color: .inkSoft)
            }
            if row.navGuardStops > 0 {
                ReviewText("\(row.navGuardStops) 次因為撳咗 YouTube 畫面上嘅連結而停（技術原因，唔影響標籤）",
                           size: 13, weight: .regular, color: .inkSoft)
            }
            ReviewText("播放結果只供參考，唔影響標籤。", size: 12, weight: .regular, color: .inkSoft)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.ink.opacity(0.05)))
    }
}

/// 4×2 pick-share map (row-major slots 0–7), fixed cell size.
private struct SlotMap: View {
    let shares: [Double]?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<2, id: \.self) { rowIndex in
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { column in
                        cell(rowIndex * 4 + column)
                    }
                }
            }
        }
    }

    private func cell(_ slot: Int) -> some View {
        let share = shares.map { slot < $0.count ? $0[slot] : 0 }
        return Text(share.map { "\(ReviewFormat.percent($0))%" } ?? "—")
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .frame(width: 72, height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: DesignTokens.Palette.mint).opacity(0.15 + 0.85 * min(1, (share ?? 0) * 3))))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.ink, lineWidth: 1.5))
    }
}

private struct SessionReviewRow: View {
    let session: PerfReportSession
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(ReviewFormat.date(session.start)) \(ReviewFormat.time(session.start))–\(ReviewFormat.time(session.end))"
                     + " · \(session.rounds) 個遊戲 · \(session.plays) 條片")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                if session.tested || session.excluded {
                    Text(session.excluded ? "唔計緊" : "🧪 測試（本身已唔計）")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.inkSoft)
                }
            }
            Spacer(minLength: 8)
            Button(action: action) {
                Text(session.excluded ? "計返" : "唔計呢段")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .frame(width: 110, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ChunkyButtonStyle(
                fill: session.excluded ? Color(hex: DesignTokens.Palette.mint) : Color(hex: DesignTokens.Palette.paper),
                cornerRadius: 10, shadowDepth: 3, lineWidth: 2
            ))
            .accessibilityLabel(session.excluded ? "計返" : "唔計呢段")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.ink.opacity(0.3), lineWidth: 1.5))
    }
}
