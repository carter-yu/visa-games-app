import SwiftUI
import VisaCore

// MARK: - Board 3 — Visa stamped

struct StampSuccessView: View {
    let ticket: MissionTicket
    /// Actual pending award at success (minutes/road follow this; stars stay ticket difficulty).
    let earnedMinutes: Int
    let onGo: () -> Void
    let onSpeak: () -> Void
    @Environment(\.canvasMetrics) private var metrics
    @State private var confetti = false
    @State private var zoomVehicle = false

    var body: some View {
        CanvasStage {
            ZStack {
                Color(hex: DesignTokens.Palette.sunny)
                // Soft sunburst
                ForEach(0..<12, id: \.self) { i in
                    Capsule()
                        .fill(Color(hex: DesignTokens.Palette.sunnyPale).opacity(0.55))
                        .frame(width: metrics.u(40), height: metrics.u(900))
                        .rotationEffect(.degrees(Double(i) * 15))
                }
                Color(hex: DesignTokens.Palette.sand)
                    .frame(height: metrics.u(90))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                if confetti {
                    ConfettiField()
                }
            }
        } content: {
            HStack(alignment: .center, spacing: metrics.u(12)) {
                VectorArtView(artwork: CanvasArt.stampy)
                    .frame(width: metrics.u(120), height: metrics.u(120))
                SpeechBubbleButton(prompt: .stamped, action: onSpeak)
                    .scaleEffect(0.8, anchor: .leading)
            }
            .canvasPlaced(x: 36, y: 40)

            PassportSpread(ticket: ticket, earnedMinutes: earnedMinutes)
                .canvasPlaced(x: 250, y: 120)

            HStack(spacing: metrics.u(18)) {
                Button(action: onGo) {
                    HStack(spacing: metrics.u(14)) {
                        Image(systemName: "play.fill")
                            .font(.system(size: metrics.u(28), weight: .bold))
                        VStack(spacing: 0) {
                            CanvasText("出發！", size: 32, weight: 900)
                            CanvasText("Go!", size: 18, weight: 800)
                        }
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, metrics.u(36))
                    .padding(.vertical, metrics.u(18))
                }
                .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.mint),
                                               cornerRadius: 40, shadowDepth: 10))
                .accessibilityLabel("出發！ Go!")

                VectorArtView(artwork: ticket.artwork)
                    .frame(width: metrics.u(120), height: metrics.u(75))
                    .offset(x: zoomVehicle ? metrics.u(160) : 0)
                    .opacity(zoomVehicle ? 0 : 1)
            }
            .canvasPlaced(x: 360, y: 560)
        }
        .onAppear {
            onSpeak()
            confetti = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeIn(duration: 0.55)) { zoomVehicle = true }
            }
        }
    }
}

private struct PassportSpread: View {
    let ticket: MissionTicket
    let earnedMinutes: Int
    @Environment(\.canvasMetrics) private var metrics

    private var roadTileCount: Int {
        WrongAnswerPolicy.roadTiles(forEarnedMinutes: earnedMinutes)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left page — polaroid vehicle
            VStack(spacing: metrics.u(14)) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: metrics.u(8))
                        .fill(Color(hex: DesignTokens.Palette.paper))
                        .overlay(RoundedRectangle(cornerRadius: metrics.u(8))
                            .strokeBorder(Color.ink, lineWidth: metrics.u(3)))
                    VectorArtView(artwork: ticket.artwork)
                        .frame(width: metrics.u(180), height: metrics.u(110))
                        .padding(.top, metrics.u(18))
                    Capsule()
                        .fill(Color(hex: DesignTokens.Palette.sunny))
                        .frame(width: metrics.u(70), height: metrics.u(18))
                        .overlay(Capsule().strokeBorder(Color.ink, lineWidth: metrics.u(2)))
                        .offset(y: metrics.u(-6))
                }
                .frame(width: metrics.u(220), height: metrics.u(160))
                HStack(spacing: metrics.u(4)) {
                    ForEach(0..<ticket.stars, id: \.self) { _ in
                        VectorArtView(artwork: CanvasArt.star)
                            .frame(width: metrics.u(28), height: metrics.u(28))
                    }
                }
                VStack(spacing: 2) {
                    CanvasText(ticket.titleTraditionalChinese, size: 22, weight: 800)
                    CanvasText(ticket.titleEnglish, size: 16, weight: 700)
                    CanvasText("\(earnedMinutes) 分鐘", size: 18, weight: 800)
                }
            }
            .frame(width: metrics.u(340), height: metrics.u(380))
            .background(Color.white)
            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: metrics.u(2)))

            // Right page — stamp
            ZStack {
                Color.white
                VStack(spacing: metrics.u(16)) {
                    VisaStampBadge()
                        .rotationEffect(.degrees(-12))
                    HStack(spacing: metrics.u(6)) {
                        ForEach(0..<max(roadTileCount, 0), id: \.self) { _ in RoadTileView() }
                    }
                }
            }
            .frame(width: metrics.u(340), height: metrics.u(380))
            .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: metrics.u(2)))
        }
        .padding(metrics.u(10))
        .background(
            RoundedRectangle(cornerRadius: metrics.u(24), style: .continuous)
                .fill(Color(hex: DesignTokens.Palette.passportBlue))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.u(24), style: .continuous)
                        .strokeBorder(Color.ink, lineWidth: metrics.u(5))
                )
        )
        .shadow(color: Color.ink.opacity(0.25), radius: 0, x: 0, y: metrics.u(10))
    }
}

struct VisaStampBadge: View {
    @Environment(\.canvasMetrics) private var metrics
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: DesignTokens.Palette.stampRed),
                        style: StrokeStyle(lineWidth: metrics.u(6), dash: [metrics.u(10), metrics.u(6)]))
                .frame(width: metrics.u(180), height: metrics.u(180))
            Circle()
                .strokeBorder(Color(hex: DesignTokens.Palette.stampRed), lineWidth: metrics.u(4))
                .frame(width: metrics.u(150), height: metrics.u(150))
            VStack(spacing: 4) {
                CanvasText("簽證", size: 36, weight: 900, color: Color(hex: DesignTokens.Palette.stampRed))
                CanvasText("VISA", size: 26, weight: 900, color: Color(hex: DesignTokens.Palette.stampRed))
            }
        }
        .accessibilityLabel("簽證 VISA")
    }
}

private struct ConfettiField: View {
    @Environment(\.canvasMetrics) private var metrics
    private let colors: [UInt32] = [
        DesignTokens.Palette.mint, DesignTokens.Palette.tomato,
        DesignTokens.Palette.metro, DesignTokens.Palette.ink
    ]
    var body: some View {
        GeometryReader { geo in
            ForEach(0..<28, id: \.self) { i in
                let x = CGFloat((i * 47) % 100) / 100 * geo.size.width
                let y = CGFloat((i * 37) % 100) / 100 * geo.size.height * 0.7
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: colors[i % colors.count]))
                    .frame(width: metrics.u(i % 3 == 0 ? 14 : 10),
                           height: metrics.u(i % 2 == 0 ? 14 : 8))
                    .rotationEffect(.degrees(Double(i * 23)))
                    .position(x: x, y: y)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Board 4 — Watching + road timer

struct WatchPlaybackView: View {
    let ticket: MissionTicket
    let videoID: String?
    /// Child Continue resume offset (nil = start from beginning).
    var startSeconds: TimeInterval? = nil
    let progress: RoadTimerProgress
    let onNavigationRejected: () -> Void
    /// v0.12.0: YouTube ended → AppModel routes to picker (time left) or Time's up.
    let onPlaybackEnded: (String) -> Void
    let onDurationKnown: (String, TimeInterval) -> Void
    var onCurrentTime: ((String, TimeInterval) -> Void)? = nil
    /// 3-second hold on the garage glyph (ADR 0007 §5, Carter 2026-09-30).
    let onParentUnlock: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = DesignTokens.stageLayout(screenWidth: Double(proxy.size.width),
                                                  screenHeight: Double(proxy.size.height))
            let metrics = CanvasMetrics(scale: CGFloat(layout.scale))
            watchBody(metrics: metrics)
                .environment(\.canvasMetrics, metrics)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func watchBody(metrics: CanvasMetrics) -> some View {
        // v0.16.0: grow the framed player to fill vertical space (less letterbox) while
        // keeping the road strip as a real bottom band — never overlayed on the video.
        ZStack {
            Color(hex: DesignTokens.Palette.ink)
            VStack(spacing: metrics.u(12)) {
                ZStack {
                    RoundedRectangle(cornerRadius: metrics.u(24), style: .continuous)
                        .fill(Color.black.opacity(0.55))
                        .overlay(
                            RoundedRectangle(cornerRadius: metrics.u(24), style: .continuous)
                                .strokeBorder(Color(hex: DesignTokens.Palette.metro), lineWidth: metrics.u(5))
                        )
                    if let videoID {
                        ScopedPlayerView(
                            videoID: videoID,
                            startSeconds: startSeconds,
                            onNavigationRejected: onNavigationRejected,
                            onPlaybackEnded: onPlaybackEnded,
                            onDurationKnown: onDurationKnown,
                            onCurrentTime: onCurrentTime
                        )
                            .clipShape(RoundedRectangle(cornerRadius: metrics.u(20), style: .continuous))
                            .padding(metrics.u(8))
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(Color(hex: DesignTokens.Palette.metro))
                            CanvasText("家長准許嘅影片會喺呢度播。", size: 22, weight: 700,
                                       color: Color(hex: DesignTokens.Palette.paper))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, metrics.u(36))
                .padding(.top, metrics.u(20))

                RoadTimerStrip(ticket: ticket, progress: progress, onParentUnlock: onParentUnlock)
                    .padding(.horizontal, metrics.u(36))
                    .padding(.bottom, metrics.u(20))
            }
        }
    }
}

struct RoadTimerStrip: View {
    let ticket: MissionTicket
    let progress: RoadTimerProgress
    let onParentUnlock: () -> Void
    @Environment(\.canvasMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var glowColor: Color { Color(hex: DesignTokens.Palette.tomato) }

    var body: some View {
        GeometryReader { geo in
            let roadHeight = metrics.u(78)
            let travel = max(geo.size.width - metrics.u(160), 1)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous)
                    .fill(Color(hex: DesignTokens.Palette.road))
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous)
                            .strokeBorder(progress.almostHome ? Color(hex: DesignTokens.Palette.stampRed) : Color.ink,
                                          lineWidth: metrics.u(progress.almostHome ? 6 : 4))
                    )
                    // Last minute: soft red glow so a ~4yo notices home is near (no red X).
                    .shadow(color: glowColor.opacity(almostHomeGlowOpacity), radius: metrics.u(18))
                    .shadow(color: glowColor.opacity(almostHomeGlowOpacity * 0.8), radius: metrics.u(6))
                // Dashed center line
                Path { path in
                    path.move(to: CGPoint(x: metrics.u(50), y: roadHeight / 2))
                    path.addLine(to: CGPoint(x: geo.size.width - metrics.u(90), y: roadHeight / 2))
                }
                .stroke(Color(hex: DesignTokens.Palette.sunny),
                        style: StrokeStyle(lineWidth: metrics.u(4), dash: [metrics.u(14), metrics.u(10)]))

                // Start flag
                Text("🏁")
                    .font(.system(size: metrics.u(28)))
                    .offset(x: metrics.u(10))

                // Vehicle
                VectorArtView(artwork: ticket.artwork)
                    .frame(width: metrics.u(90), height: metrics.u(56))
                    .offset(x: metrics.u(40) + travel * progress.fraction)

                // Parent readout
                CanvasText("仲有 \(progress.remainingMinutesCeil) 分鐘", size: 18, weight: 800,
                           color: Color(hex: DesignTokens.Palette.paper))
                    .offset(x: geo.size.width * 0.55)

                // Garage destination; the parent 3s hold sits above the house art (v0.11.0).
                ZStack {
                    GarageGlyph(lit: progress.almostHome)
                        .frame(width: metrics.u(56), height: metrics.u(56))
                        .shadow(color: glowColor.opacity(almostHomeGlowOpacity), radius: metrics.u(12))
                    ParentCornerEntry(onUnlock: onParentUnlock, size: 72, showsMark: false)
                }
                .frame(width: metrics.u(72), height: metrics.u(72))
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: roadHeight)
        }
        .frame(height: metrics.u(78))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("仲有 \(progress.remainingMinutesCeil) 分鐘 / \(progress.remainingMinutesCeil) minutes left")
        .onAppear { updatePulse(progress.almostHome) }
        .onChange(of: progress.almostHome) { updatePulse($0) }
        .onChange(of: reduceMotion) { _ in updatePulse(progress.almostHome) }
    }

    /// Reduce Motion: steady bright glow. Otherwise a soft opacity pulse.
    private var almostHomeGlowOpacity: Double {
        guard progress.almostHome else { return 0 }
        if reduceMotion { return 0.9 }
        return pulse ? 0.95 : 0.35
    }

    private func updatePulse(_ almostHome: Bool) {
        guard almostHome, !reduceMotion else {
            withAnimation(nil) { pulse = false }
            return
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

private struct GarageGlyph: View {
    let lit: Bool
    @Environment(\.canvasMetrics) private var metrics
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.u(6))
                .fill(Color(hex: DesignTokens.Palette.sand))
            RoundedRectangle(cornerRadius: metrics.u(6))
                .strokeBorder(Color.ink, lineWidth: metrics.u(3))
            // Roof
            Path { path in
                path.move(to: CGPoint(x: 0, y: metrics.u(18)))
                path.addLine(to: CGPoint(x: metrics.u(28), y: 0))
                path.addLine(to: CGPoint(x: metrics.u(56), y: metrics.u(18)))
            }
            .fill(Color(hex: DesignTokens.Palette.tomato))
            .overlay(Path { path in
                path.move(to: CGPoint(x: 0, y: metrics.u(18)))
                path.addLine(to: CGPoint(x: metrics.u(28), y: 0))
                path.addLine(to: CGPoint(x: metrics.u(56), y: metrics.u(18)))
            }.stroke(Color.ink, lineWidth: metrics.u(3)))
            RoundedRectangle(cornerRadius: 2)
                .fill(lit ? Color(hex: DesignTokens.Palette.sunny) : Color(hex: DesignTokens.Palette.woodDark))
                .frame(width: metrics.u(28), height: metrics.u(26))
                .offset(y: metrics.u(10))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.ink, lineWidth: metrics.u(2))
                        .frame(width: metrics.u(28), height: metrics.u(26))
                        .offset(y: metrics.u(10))
                )
        }
    }
}

// MARK: - Board 5 — Time's up

struct TimesUpView: View {
    let ticket: MissionTicket
    let onNewMission: () -> Void
    let onSpeak: () -> Void
    @Environment(\.canvasMetrics) private var metrics

    private var prompt: SpokenPrompt { .timesUp(for: ticket) }

    var body: some View {
        CanvasStage {
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color(hex: 0x1B2A4A), Color(hex: DesignTokens.Palette.metro)],
                    startPoint: .top, endPoint: .bottom
                )
                // Stars
                ForEach(0..<18, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 3, height: 3)
                        .offset(x: CGFloat((i * 73) % 1200) - 600,
                                y: CGFloat((i * 41) % 280) - 280)
                }
                // Moon
                Text("🌙")
                    .font(.system(size: 42))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(40)
                // Hills
                Ellipse()
                    .fill(Color(hex: DesignTokens.Palette.grass).opacity(0.85))
                    .frame(height: metrics.u(160))
                    .offset(y: metrics.u(40))
                Color(hex: DesignTokens.Palette.sand)
                    .frame(height: metrics.u(100))
            }
        } content: {
            HStack(alignment: .bottom, spacing: metrics.u(20)) {
                VectorArtView(artwork: CanvasArt.stampy)
                    .frame(width: metrics.u(140), height: metrics.u(140))
                SpeechBubbleButton(prompt: prompt, action: onSpeak)
                    .scaleEffect(0.85, anchor: .leading)
            }
            .canvasPlaced(x: 60, y: 80)

            SleepingGarage(ticket: ticket)
                .canvasPlaced(x: 420, y: 180)

            Button(action: onNewMission) {
                HStack(spacing: metrics.u(12)) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: metrics.u(26), weight: .bold))
                    VStack(spacing: 0) {
                        CanvasText("再揀車票", size: 28, weight: 900)
                        CanvasText("New mission", size: 16, weight: 800)
                    }
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, metrics.u(40))
                .padding(.vertical, metrics.u(18))
            }
            .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sand),
                                           cornerRadius: 40, shadowDepth: 10))
            .canvasPlaced(x: 430, y: 560)
            .accessibilityLabel("再揀車票 New mission")
        }
        .onAppear(perform: onSpeak)
    }
}

private struct SleepingGarage: View {
    let ticket: MissionTicket
    @Environment(\.canvasMetrics) private var metrics
    var body: some View {
        ZStack(alignment: .bottom) {
            // Building
            VStack(spacing: 0) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: metrics.u(40)))
                    path.addLine(to: CGPoint(x: metrics.u(160), y: 0))
                    path.addLine(to: CGPoint(x: metrics.u(320), y: metrics.u(40)))
                    path.closeSubpath()
                }
                .fill(Color(hex: DesignTokens.Palette.tomato))
                .frame(width: metrics.u(320), height: metrics.u(40))
                ZStack {
                    Rectangle().fill(Color(hex: DesignTokens.Palette.sand))
                    // Door
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: DesignTokens.Palette.sunnyPale))
                        .overlay(
                            VStack(spacing: 4) {
                                ForEach(0..<5, id: \.self) { _ in
                                    Rectangle().fill(Color.ink.opacity(0.25)).frame(height: 3)
                                }
                            }.padding(8)
                        )
                        .padding(.horizontal, metrics.u(40))
                        .padding(.vertical, metrics.u(20))
                    VectorArtView(artwork: ticket.artwork)
                        .frame(width: metrics.u(180), height: metrics.u(110))
                        .opacity(0.95)
                }
                .frame(width: metrics.u(320), height: metrics.u(200))
                .overlay(Rectangle().strokeBorder(Color.ink, lineWidth: metrics.u(5)))
            }
            Text("z  z  Z")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
                .offset(x: metrics.u(180), y: -metrics.u(160))
        }
    }
}

// MARK: - Empty allowlist sister screen

struct EmptyAllowlistView: View {
    let onReturn: () -> Void
    let onSpeak: () -> Void
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        CanvasStage {
            ZStack(alignment: .bottom) {
                Color(hex: DesignTokens.Palette.sky)
                Color(hex: DesignTokens.Palette.sand).frame(height: metrics.u(120))
            }
        } content: {
            HStack(spacing: metrics.u(16)) {
                VectorArtView(artwork: CanvasArt.stampy)
                    .frame(width: metrics.u(150), height: metrics.u(150))
                SpeechBubbleButton(prompt: .emptyAllowlist, action: onSpeak)
            }
            .canvasPlaced(x: 80, y: 120)

            // Empty garage vibe
            RoundedRectangle(cornerRadius: metrics.u(24), style: .continuous)
                .fill(Color(hex: DesignTokens.Palette.paper))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.u(24), style: .continuous)
                        .strokeBorder(Color.ink, lineWidth: metrics.u(5))
                )
                .overlay(
                    CanvasText("空車房 / Empty bay", size: 28, weight: 800)
                )
                .frame(width: metrics.u(420), height: metrics.u(200))
                .canvasPlaced(x: 430, y: 280)

            Button(action: onReturn) {
                VStack(spacing: 0) {
                    CanvasText("返回車廠", size: 28, weight: 900)
                    CanvasText("Back to depot", size: 16, weight: 800)
                }
                .foregroundStyle(Color.ink)
                .padding(.horizontal, metrics.u(40))
                .padding(.vertical, metrics.u(16))
            }
            .buttonStyle(ChunkyButtonStyle(fill: Color(hex: DesignTokens.Palette.sunny),
                                           cornerRadius: 36, shadowDepth: 10))
            .canvasPlaced(x: 480, y: 540)
            .accessibilityLabel("返回車廠 Back to depot")
        }
        .onAppear(perform: onSpeak)
    }
}
