import SwiftUI
import VisaCore

// MARK: - Half match

struct HalfMatchActivityView: View {
    let question: HalfMatchQuestion
    let accent: Color
    let yellow: Color
    let foreground: Color
    let sand: Color
    let retryMessage: String?
    let hintUsed: Bool
    let onSelect: (String) -> Void
    let onHint: () -> Void
    let onSpeakPrompt: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(question.promptTraditionalChinese)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
            Text(question.promptEnglish)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 18, weight: .medium, design: .rounded))

            // Target: LEFT half
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(yellow, lineWidth: 5)
                HalfVehicleClip(assetID: question.targetAssetID, side: .left, mood: .calm)
                    .padding(16)
            }
            .frame(width: 220, height: 150)
            .accessibilityLabel("左半邊目標 / Left-half target")

            HStack(spacing: 20) {
                ForEach(question.options, id: \.id) { option in
                    Button { onSelect(option.id) } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .fill(Color.white.opacity(0.55))
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color(red: 0.45, green: 0.28, blue: 0.14), lineWidth: 4)
                                HalfVehicleClip(assetID: option.assetID, side: .right, mood: .happy)
                                    .padding(12)
                            }
                            .frame(minWidth: 180, minHeight: 140)
                            Text("\(option.labelTraditionalChinese) / \(option.labelEnglish)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(foreground)
                        }
                    }
                    .buttonStyle(BouncyChildButtonStyle())
                    .accessibilityLabel("\(option.labelTraditionalChinese), \(option.labelEnglish)")
                }
            }

            if let retryMessage {
                Text(retryMessage)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)
            }
            hintRow
        }
        .background(sand.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: 1140)
    }

    private var hintRow: some View {
        HStack(spacing: 20) {
            Button(hintUsed ? "提示已用 / Hint used" : "提示 / Hint", action: onHint)
                .disabled(hintUsed)
                .tint(accent)
            Button("聽提示（稍後） / Hear prompt (later)", action: onSpeakPrompt)
                .tint(yellow)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

// MARK: - Shape cousin

struct ShapeCousinActivityView: View {
    let question: ShapeCousinQuestion
    let accent: Color
    let yellow: Color
    let foreground: Color
    let sand: Color
    let retryMessage: String?
    let hintUsed: Bool
    let onSelect: (String) -> Void
    let onHint: () -> Void
    let onSpeakPrompt: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(question.promptTraditionalChinese)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
            Text(question.promptEnglish)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 18, weight: .medium, design: .rounded))

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(yellow, lineWidth: 5)
                ActivityAssetView(assetID: question.targetAssetID, mood: .calm)
                    .padding(22)
            }
            .frame(minWidth: 200, minHeight: 140)
            .accessibilityLabel("圓形參考 / Round reference")

            HStack(spacing: 22) {
                ForEach(question.options, id: \.id) { option in
                    Button { onSelect(option.id) } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .fill(Color.white.opacity(0.55))
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(Color(red: 0.45, green: 0.28, blue: 0.14), lineWidth: 4)
                                ActivityAssetView(assetID: option.assetID, mood: .happy)
                                    .padding(16)
                            }
                            .frame(minWidth: 200, minHeight: 150)
                            Text("\(option.labelTraditionalChinese) / \(option.labelEnglish)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(foreground)
                        }
                    }
                    .buttonStyle(BouncyChildButtonStyle())
                    .accessibilityLabel("\(option.labelTraditionalChinese), \(option.labelEnglish)")
                }
            }

            if let retryMessage {
                Text(retryMessage)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)
            }
            hintRow
        }
        .background(sand.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: 1140)
    }

    private var hintRow: some View {
        HStack(spacing: 20) {
            Button(hintUsed ? "提示已用 / Hint used" : "提示 / Hint", action: onHint)
                .disabled(hintUsed)
                .tint(accent)
            Button("聽提示（稍後） / Hear prompt (later)", action: onSpeakPrompt)
                .tint(yellow)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

// MARK: - Capacity compare

struct CapacityCompareActivityView: View {
    let question: CapacityCompareQuestion
    let accent: Color
    let yellow: Color
    let foreground: Color
    let sand: Color
    let retryMessage: String?
    let hintUsed: Bool
    let onSelect: (String) -> Void
    let onHint: () -> Void
    let onSpeakPrompt: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Text(question.promptTraditionalChinese)
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
            Text(question.promptEnglish)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 20, weight: .medium, design: .rounded))

            HStack(spacing: 36) {
                ForEach(question.options, id: \.id) { option in
                    Button { onSelect(option.id) } label: {
                        VStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .fill(Color.white.opacity(0.55))
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .stroke(Color(red: 0.45, green: 0.28, blue: 0.14), lineWidth: 5)
                                ActivityAssetView(assetID: option.assetID, mood: .happy)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 28)
                            }
                            .frame(minWidth: 300, minHeight: 220)
                            .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
                            Text("\(option.labelTraditionalChinese) / \(option.labelEnglish)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(foreground)
                        }
                    }
                    .buttonStyle(BouncyChildButtonStyle())
                    .accessibilityLabel("\(option.labelTraditionalChinese), \(option.labelEnglish)")
                }
            }

            if let retryMessage {
                Text(retryMessage)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 20) {
                Button(hintUsed ? "提示已用 / Hint used" : "提示 / Hint", action: onHint)
                    .disabled(hintUsed)
                    .tint(accent)
                Button("聽提示（稍後） / Hear prompt (later)", action: onSpeakPrompt)
                    .tint(yellow)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .background(sand.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: 1040)
    }
}

// MARK: - More / fewer lots

struct MoreFewerActivityView: View {
    let question: MoreFewerQuestion
    let accent: Color
    let yellow: Color
    let foreground: Color
    let sand: Color
    let retryMessage: String?
    let hintUsed: Bool
    let onSelectSide: (ParkingLotSide) -> Void
    let onHint: () -> Void
    let onSpeakPrompt: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(question.promptTraditionalChinese)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
            Text(question.promptEnglish)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 18, weight: .medium, design: .rounded))

            HStack(spacing: 28) {
                lotButton(
                    side: .left,
                    titleZH: "左邊車場",
                    titleEN: "Left lot",
                    assets: question.leftLotAssetIDs
                )
                lotButton(
                    side: .right,
                    titleZH: "右邊車場",
                    titleEN: "Right lot",
                    assets: question.rightLotAssetIDs
                )
            }

            if let retryMessage {
                Text(retryMessage)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 20) {
                Button(hintUsed ? "提示已用 / Hint used" : "提示 / Hint", action: onHint)
                    .disabled(hintUsed)
                    .tint(accent)
                Button("聽提示（稍後） / Hear prompt (later)", action: onSpeakPrompt)
                    .tint(yellow)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .background(sand.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: 1180)
    }

    private func lotButton(side: ParkingLotSide, titleZH: String, titleEN: String, assets: [String]) -> some View {
        Button { onSelectSide(side) } label: {
            VStack(spacing: 12) {
                Text("\(titleZH) / \(titleEN)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(foreground)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                    ForEach(Array(assets.enumerated()), id: \.offset) { _, assetID in
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.5))
                            ActivityAssetView(assetID: assetID, mood: .happy)
                                .padding(6)
                        }
                        .frame(width: 100, height: 72)
                    }
                }
                .padding(12)
            }
            .frame(minWidth: 360, minHeight: 220)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color(red: 0.45, green: 0.28, blue: 0.14), lineWidth: 4)
            )
        }
        .buttonStyle(BouncyChildButtonStyle())
        .accessibilityLabel("\(titleZH), \(titleEN)")
    }
}

// MARK: - Shadow match

struct ShadowMatchActivityView: View {
    let question: ShadowMatchQuestion
    let accent: Color
    let yellow: Color
    let foreground: Color
    let sand: Color
    let retryMessage: String?
    let hintUsed: Bool
    let onSelect: (String) -> Void
    let onHint: () -> Void
    let onSpeakPrompt: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(question.promptTraditionalChinese)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
            Text(question.promptEnglish)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 18, weight: .medium, design: .rounded))

            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.7))
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(yellow, lineWidth: 5)
                ActivityAssetView(assetID: question.targetAssetID, mood: .calm, asShadow: true)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 22)
            }
            .frame(minWidth: 380, minHeight: 150)
            .accessibilityLabel("影子目標 / Shadow target")

            HStack(spacing: 22) {
                ForEach(question.options, id: \.id) { option in
                    Button { onSelect(option.id) } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .fill(Color.white.opacity(0.55))
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(Color(red: 0.45, green: 0.28, blue: 0.14), lineWidth: 4)
                                ActivityAssetView(assetID: option.assetID, mood: .happy)
                                    .padding(16)
                            }
                            .frame(minWidth: 210, minHeight: 150)
                            Text("\(option.labelTraditionalChinese) / \(option.labelEnglish)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(foreground)
                        }
                    }
                    .buttonStyle(BouncyChildButtonStyle())
                    .accessibilityLabel("\(option.labelTraditionalChinese), \(option.labelEnglish)")
                }
            }

            if let retryMessage {
                Text(retryMessage)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 20) {
                Button(hintUsed ? "提示已用 / Hint used" : "提示 / Hint", action: onHint)
                    .disabled(hintUsed)
                    .tint(accent)
                Button("聽提示（稍後） / Hear prompt (later)", action: onSpeakPrompt)
                    .tint(yellow)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .background(sand.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: 1140)
    }
}

// MARK: - Empty bay

struct EmptyBayActivityView: View {
    let question: EmptyBayQuestion
    let accent: Color
    let yellow: Color
    let foreground: Color
    let sand: Color
    let retryMessage: String?
    let hintUsed: Bool
    let onSelectBay: (String) -> Void
    let onHint: () -> Void
    let onSpeakPrompt: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(question.promptTraditionalChinese)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(foreground)
            Text(question.promptEnglish)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
            Text("用筆畫 / Draw with your pen")
                .font(.system(size: 18, weight: .medium, design: .rounded))

            HStack(spacing: 24) {
                ForEach(Array(question.bays.enumerated()), id: \.element.id) { index, bay in
                    Button { onSelectBay(bay.id) } label: {
                        VStack(spacing: 10) {
                            Text("車位 \(index + 1) / Bay \(index + 1)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(foreground)
                            ZStack {
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(Color.white.opacity(0.5))
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(
                                        bay.isEmpty
                                            ? yellow
                                            : Color(red: 0.45, green: 0.28, blue: 0.14),
                                        style: StrokeStyle(
                                            lineWidth: bay.isEmpty ? 5 : 4,
                                            dash: bay.isEmpty ? [10, 8] : []
                                        )
                                    )
                                if let assetID = bay.vehicleAssetID {
                                    ActivityAssetView(assetID: assetID, mood: .happy)
                                        .padding(14)
                                } else {
                                    Text("空 / Empty")
                                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                                        .foregroundStyle(foreground.opacity(0.55))
                                }
                            }
                            .frame(minWidth: 240, minHeight: 170)
                        }
                    }
                    .buttonStyle(BouncyChildButtonStyle())
                    .accessibilityLabel(bay.isEmpty ? "空車位 / Empty bay" : "有車車位 / Occupied bay")
                }
            }

            if let retryMessage {
                Text(retryMessage)
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 20) {
                Button(hintUsed ? "提示已用 / Hint used" : "提示 / Hint", action: onHint)
                    .disabled(hintUsed)
                    .tint(accent)
                Button("聽提示（稍後） / Hear prompt (later)", action: onSpeakPrompt)
                    .tint(yellow)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .background(sand.opacity(0.08), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: 1180)
    }
}
