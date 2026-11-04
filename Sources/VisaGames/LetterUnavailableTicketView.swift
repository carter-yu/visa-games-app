import SwiftUI
import VisaCore

/// No eligible target can be dealt. The usual three-second corner hold remains the only parent entry.
struct LetterUnavailableTicketView: View {
    var body: some View {
        ZStack {
            Color(hex: DesignTokens.Palette.paper)
            VStack(spacing: 18) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 64))
                Text("呢張遊戲票暫時玩唔到")
                    .font(CanvasFont.font(size: 34, weight: 900))
                Text("請家長長按右下角，檢查字母設定。")
                    .font(CanvasFont.font(size: 21, weight: 700))
            }
            .foregroundStyle(Color.ink)
            .padding(40)
            .modifier(ChunkyPanel(fill: Color(hex: DesignTokens.Palette.sunnyPale),
                                  cornerRadius: 18, shadowDepth: 4, lineWidth: 3))
        }
    }
}
