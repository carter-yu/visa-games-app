import AppKit
import SwiftUI
import VisaCore

/// Board 7 feedback: hop / wiggle / hint glow. Respects Reduce Motion.
enum ChoiceFeedback: Equatable {
    case idle
    case incorrect
    case correct
    case hint
}

struct ChoiceCardChrome<Content: View>: View {
    let feedback: ChoiceFeedback
    let isHintTarget: Bool
    var isInteractionEnabled: Bool = true
    var cardWidth: Double = DesignTokens.choiceCardWidth
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.canvasMetrics) private var metrics
    @State private var hop = false
    @State private var wiggle = false
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: metrics.u(30), style: .continuous)
                    .fill(Color(hex: DesignTokens.Palette.paper))
                RoundedRectangle(cornerRadius: metrics.u(30), style: .continuous)
                    .strokeBorder(borderColor, lineWidth: metrics.u(isHintTarget || feedback == .hint ? 8 : 5))
                content()
                    .padding(metrics.u(16))
                if feedback == .correct {
                    SparkleBurst()
                        .allowsHitTesting(false)
                }
            }
            .frame(width: metrics.u(cardWidth),
                   height: metrics.u(DesignTokens.choiceCardHeight))
            .offset(y: hop ? metrics.u(-14) : 0)
            .offset(x: wiggle ? metrics.u(8) : 0)
            .scaleEffect(pulse ? 1.04 : 1.0)
            .shadow(color: Color.ink.opacity(0.18), radius: 0, x: 0, y: metrics.u(8))
        }
        .buttonStyle(BouncyChildButtonStyle())
        .disabled(!isInteractionEnabled)
        .allowsHitTesting(isInteractionEnabled)
        .onChange(of: feedback) { newValue in
            applyFeedback(newValue)
        }
        .onChange(of: isHintTarget) { on in
            if on && !reduceMotion {
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { pulse = true }
            } else if !on {
                pulse = false
            }
        }
        .onAppear { applyFeedback(feedback) }
    }

    private func applyFeedback(_ newValue: ChoiceFeedback) {
        guard !reduceMotion else { return }
        switch newValue {
        case .correct:
            withAnimation(.spring(response: 0.28, dampingFraction: 0.45)) { hop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.15)) { hop = false }
            }
            NSSound(named: "Glass")?.play()
        case .incorrect:
            withAnimation(.easeInOut(duration: 0.08).repeatCount(3, autoreverses: true)) { wiggle = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { wiggle = false }
            NSSound(named: "Tink")?.play()
        case .hint:
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { pulse = true }
        case .idle:
            hop = false; wiggle = false; pulse = false
        }
    }

    private var borderColor: Color {
        if isHintTarget || feedback == .hint || feedback == .correct {
            return Color(hex: DesignTokens.Palette.sunny)
        }
        return Color.ink
    }
}

private struct SparkleBurst: View {
    @Environment(\.canvasMetrics) private var metrics
    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                Circle()
                    .fill(Color(hex: DesignTokens.Palette.sunny))
                    .frame(width: metrics.u(i % 2 == 0 ? 14 : 10),
                           height: metrics.u(i % 2 == 0 ? 14 : 10))
                    .offset(x: metrics.u([-70.0, -30, 10, 40, 70, 90][i]),
                            y: metrics.u([-50.0, -70, -40, -75, -55, -65][i]))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Traffic-cone progress (board 2). One cone per question; filled = done.
struct ConeProgressView: View {
    let total: Int
    let completed: Int
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.u(8)) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                ConeGlyph(filled: index < completed)
            }
        }
        .padding(.horizontal, metrics.u(14))
        .padding(.vertical, metrics.u(10))
        .background(
            RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous)
                .fill(Color(hex: DesignTokens.Palette.paper).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.u(18), style: .continuous)
                        .strokeBorder(Color.ink, lineWidth: metrics.u(4))
                )
        )
        .accessibilityLabel("進度 \(completed)/\(total) / Progress \(completed) of \(total)")
    }
}

struct ConeGlyph: View {
    let filled: Bool
    @Environment(\.canvasMetrics) private var metrics

    var body: some View {
        // Simple traffic cone: trapezoid + stripes.
        ZStack {
            ConeShape()
                .fill(filled ? Color(hex: DesignTokens.Palette.tomato) : Color(hex: DesignTokens.Palette.inkSoft).opacity(0.25))
            ConeShape()
                .stroke(Color.ink, lineWidth: metrics.u(3))
            if filled {
                VStack(spacing: metrics.u(4)) {
                    Capsule().fill(Color(hex: DesignTokens.Palette.paper)).frame(width: metrics.u(18), height: metrics.u(4))
                    Capsule().fill(Color(hex: DesignTokens.Palette.paper)).frame(width: metrics.u(22), height: metrics.u(4))
                }
                .offset(y: metrics.u(4))
            }
        }
        .frame(width: metrics.u(28), height: metrics.u(36))
    }
}

private struct ConeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.82, y: rect.maxY * 0.78))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX * 0.18 + rect.width * 0.18, y: rect.maxY * 0.78))
        path.closeSubpath()
        return path
    }
}
