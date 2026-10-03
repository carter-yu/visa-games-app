import SwiftUI
import VisaCore

/// One built activity in the parent game catalog. Mirrors `AllowlistVideoCard`:
/// chunky paper panel, static art, title, and a sunny 試玩 button. Stars are
/// which ticket may deal the game — not difficulty and not a delete control.
struct ParentGameCard: View {
    let kind: ActivityKind
    let assignment: MissionGameAssignment
    let isHighlighted: Bool
    let onToggleStar: (ChildDifficulty) -> Void
    let onPlaytest: () -> Void

    private var hidden: Bool { assignment.isHiddenFromMissions(kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ParentGameArtWell(kind: kind, onPlay: onPlaytest)

            Text(kind.parentCardTitle)
                .font(CanvasFont.font(size: 15, weight: 800))
                .foregroundStyle(Color.ink)
                .lineLimit(2, reservesSpace: true)
                .help("\(kind.parentHelpTraditionalChinese) / \(kind.parentHelpEnglish)")

            Text(kind.parentCardEnglish)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.inkSoft)
                .lineLimit(2, reservesSpace: true)

            if hidden {
                Text("唔會出現 / Hidden from missions")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.inkSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: DesignTokens.Palette.sand)))
                    .overlay(Capsule().strokeBorder(Color.ink.opacity(0.45), lineWidth: 1.5))
            }

            HStack(spacing: 6) {
                ForEach(ChildDifficulty.allCases, id: \.rawValue) { star in
                    starToggle(star)
                }
            }

            Button(action: onPlaytest) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                    Text("試玩 Playtest")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(ChunkyButtonStyle(
                fill: Color(hex: DesignTokens.Palette.sunny),
                cornerRadius: 12,
                shadowDepth: 3,
                lineWidth: 2
            ))
            .accessibilityLabel("試玩 \(kind.parentCardTitle) / Playtest")
        }
        .padding(12)
        .modifier(ChunkyPanel(
            fill: isHighlighted ? Color(hex: DesignTokens.Palette.sunnyPale) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 18,
            shadowDepth: 5,
            lineWidth: 3
        ))
    }

    private func starToggle(_ star: ChildDifficulty) -> some View {
        let on = assignment.isEnabled(kind, star: star)
        let ticket = MissionTicket.all.first { $0.difficulty == star }
        let ticketName = ticket?.titleTraditionalChinese ?? ""
        return Button(action: { onToggleStar(star) }) {
            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: on ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .heavy))
                    Text("\(star.rawValue)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                }
                Text("\(star.minutes) 分鐘")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .padding(.horizontal, 2)
        }
        .buttonStyle(ChunkyButtonStyle(
            fill: on ? Color(hex: DesignTokens.Palette.sunny) : Color(hex: DesignTokens.Palette.paper),
            cornerRadius: 12,
            shadowDepth: on ? 2 : 3,
            lineWidth: 2
        ))
        .accessibilityLabel("★\(star.rawValue) \(ticketName) \(star.minutes) 分鐘")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 16:9 static hero. Play glyph only while the pointer is over the well.
private struct ParentGameArtWell: View {
    let kind: ActivityKind
    let onPlay: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onPlay) {
            ZStack(alignment: .topLeading) {
                Color(hex: DesignTokens.Palette.sky).opacity(0.45)
                art
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(kind.parentShortLabel)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: DesignTokens.Palette.paper)))
                    .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 1.5))
                    .padding(8)
                if hovering {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.35), radius: 3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.ink, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("試玩 \(kind.parentCardTitle) / Playtest")
    }

    @ViewBuilder
    private var art: some View {
        if kind == .halfMatch, let asset = kind.parentHeroAssetIDs.first {
            HalfVehicleClip(assetID: asset, side: .left, mood: .happy)
        } else if kind == .shadowMatch, let asset = kind.parentHeroAssetIDs.first {
            ActivityAssetView(assetID: asset, mood: .calm, asShadow: true)
        } else if kind == .emptyBay {
            HStack(spacing: 6) {
                ActivityAssetView(assetID: "silhouette.hkTaxi", mood: .happy)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.ink, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.35)))
                ActivityAssetView(assetID: "silhouette.fireEngine", mood: .happy)
            }
        } else {
            HStack(spacing: 4) {
                ForEach(Array(kind.parentHeroAssetIDs.enumerated()), id: \.offset) { _, assetID in
                    ActivityAssetView(assetID: assetID, mood: .happy)
                }
            }
        }
    }
}
