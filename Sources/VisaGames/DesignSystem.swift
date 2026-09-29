import AppKit
import CoreText
import SwiftUI
import VisaCore

// Canvas design system for child screens (ADR 0007). Views are authored in the canvas's
// 1280×720 coordinates and scaled through `CanvasMetrics`, so text and vector art stay sharp.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let channels = DesignTokens.rgb(hex)
        self.init(.sRGB, red: channels.red, green: channels.green, blue: channels.blue, opacity: opacity)
    }

    static let ink = Color(hex: DesignTokens.Palette.ink)
    static let inkSoft = Color(hex: DesignTokens.Palette.inkSoft)
}

/// Canvas-unit → screen-point conversion for the current stage.
struct CanvasMetrics: Equatable {
    var scale: CGFloat

    func u(_ value: CGFloat) -> CGFloat { value * scale }
}

private struct CanvasMetricsKey: EnvironmentKey {
    static let defaultValue = CanvasMetrics(scale: 1)
}

extension EnvironmentValues {
    var canvasMetrics: CanvasMetrics {
        get { self[CanvasMetricsKey.self] }
        set { self[CanvasMetricsKey.self] = newValue }
    }
}

/// Full-bleed backdrop plus a 1280×720 content layer fitted inside the 5% TV safe area.
struct CanvasStage<Backdrop: View, Content: View>: View {
    @ViewBuilder let backdrop: () -> Backdrop
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let layout = DesignTokens.stageLayout(screenWidth: Double(proxy.size.width),
                                                  screenHeight: Double(proxy.size.height))
            let scale = CGFloat(layout.scale)
            ZStack(alignment: .topLeading) {
                backdrop()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                ZStack(alignment: .topLeading) {
                    content()
                }
                .frame(width: CGFloat(DesignTokens.referenceWidth) * scale,
                       height: CGFloat(DesignTokens.referenceHeight) * scale,
                       alignment: .topLeading)
                .offset(x: CGFloat(layout.originX), y: CGFloat(layout.originY))
                .environment(\.canvasMetrics, CanvasMetrics(scale: scale))
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
    }
}

extension View {
    /// Places a view at canvas coordinates (top-left of the 1280×720 artboard).
    func canvasPlaced(x: CGFloat, y: CGFloat) -> some View {
        modifier(CanvasPlacement(x: x, y: y))
    }
}

private struct CanvasPlacement: ViewModifier {
    let x: CGFloat
    let y: CGFloat
    @Environment(\.canvasMetrics) private var metrics

    func body(content: Content) -> some View {
        content.offset(x: metrics.u(x), y: metrics.u(y))
    }
}

/// Bundled canvas fonts: Baloo 2 for Latin and digits, Noto Sans HK for Traditional Chinese.
enum CanvasFont {
    /// Registers the bundled fonts once. False when they are missing; text then falls back to
    /// the system rounded font.
    static let isAvailable: Bool = registerBundledFonts()

    private static let fileNames = ["Baloo2-VariableFont_wght", "NotoSansHK-VariableFont_wght"]
    private static let weightAxis = 0x77676874 // 'wght'

    /// `weight` uses the canvas's CSS weights (500–900).
    static func font(size: CGFloat, weight: Int) -> Font {
        guard isAvailable else { return .system(size: size, weight: systemWeight(weight), design: .rounded) }
        return Font(ctFont(size: size, weight: weight))
    }

    private static func ctFont(size: CGFloat, weight: Int) -> CTFont {
        let chinese = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: "Noto Sans HK",
            kCTFontVariationAttribute: [weightAxis: min(max(weight, 100), 900)]
        ] as CFDictionary)
        let latin = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: latinInstance(for: weight),
            kCTFontCascadeListAttribute: [chinese]
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(latin, size, nil)
    }

    /// Baloo 2 ships 400–800; heavier canvas weights use its ExtraBold, as browsers do.
    private static func latinInstance(for weight: Int) -> String {
        switch weight {
        case ..<550: return "Baloo2-Medium"
        case ..<650: return "Baloo2-SemiBold"
        case ..<750: return "Baloo2-Bold"
        default: return "Baloo2-ExtraBold"
        }
    }

    private static func systemWeight(_ weight: Int) -> Font.Weight {
        switch weight {
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        case ..<850: return .heavy
        default: return .black
        }
    }

    private static func registerBundledFonts() -> Bool {
        let directories = [
            Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
            // `swift run` from the repository root has no app bundle.
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Fonts", isDirectory: true)
        ].compactMap { $0 }
        for name in fileNames {
            guard let url = directories.map({ $0.appendingPathComponent("\(name).ttf") })
                .first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { continue }
            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) // already-registered is fine
        }
        let latin = CTFontCreateWithName("Baloo2-ExtraBold" as CFString, 12, nil)
        let chinese = CTFontCreateWithFontDescriptor(
            CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: "Noto Sans HK"] as CFDictionary), 12, nil)
        return CTFontCopyPostScriptName(latin) as String == "Baloo2-ExtraBold"
            && CTFontCopyFamilyName(chinese) as String == "Noto Sans HK"
    }
}

/// One line of canvas text at a canvas size, weight and CSS line height.
struct CanvasText: View {
    let text: String
    let size: CGFloat
    let weight: Int
    var color: Color = .ink
    var lineHeight: CGFloat = 1.2
    var tracking: CGFloat = 0
    @Environment(\.canvasMetrics) private var metrics

    init(_ text: String, size: CGFloat, weight: Int, color: Color = .ink,
         lineHeight: CGFloat = 1.2, tracking: CGFloat = 0) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
        self.lineHeight = lineHeight
        self.tracking = tracking
    }

    var body: some View {
        Text(text)
            .font(CanvasFont.font(size: metrics.u(size), weight: weight))
            .tracking(metrics.u(tracking))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .frame(height: metrics.u(size * lineHeight))
    }
}

/// Chunky toy button: 5 pt ink outline and a hard ink shadow with no blur. Pressing moves it
/// down 6 and shrinks the shadow to 2; hovering lifts it 4. Reduce Motion keeps the states
/// but drops the transitions.
struct ChunkyButtonStyle: ButtonStyle {
    var fill: Color
    /// Canvas units.
    var cornerRadius: CGFloat
    /// Canvas units.
    var shadowDepth: CGFloat
    var lineWidth = CGFloat(DesignTokens.outlineWidth)
    /// Clip the label inside the outline (tickets). Speech bubbles let their tail cross it.
    var clipsContent = true

    func makeBody(configuration: Configuration) -> some View {
        ChunkyButtonBody(label: configuration.label, isPressed: configuration.isPressed, style: self)
    }
}

private struct ChunkyButtonBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let style: ChunkyButtonStyle
    @Environment(\.canvasMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.u(style.cornerRadius), style: .circular)
        let lineWidth = metrics.u(style.lineWidth)
        let depth = metrics.u(isPressed ? CGFloat(DesignTokens.pressedShadowDepth) : style.shadowDepth)
        let shift = isPressed ? metrics.u(CGFloat(DesignTokens.pressedOffset))
            : (hovering ? -metrics.u(CGFloat(DesignTokens.hoverLift)) : 0)
        let transition: Animation? = reduceMotion ? nil : .easeOut(duration: 0.12)
        Group {
            if style.clipsContent {
                label.clipShape(shape.inset(by: lineWidth))
            } else {
                label
            }
        }
        .background {
            ZStack {
                shape.fill(Color.ink).offset(y: depth)
                shape.fill(style.fill)
                shape.strokeBorder(Color.ink, lineWidth: lineWidth)
            }
        }
        .contentShape(shape)
        .offset(y: shift)
        .animation(transition, value: isPressed)
        .animation(transition, value: hovering)
        .onHover { hovering = $0 }
    }
}

/// Static hard-shadowed panel (signs, bubbles that are not buttons).
struct ChunkyPanel: ViewModifier {
    var fill: Color
    var cornerRadius: CGFloat
    var shadowDepth: CGFloat
    var lineWidth = CGFloat(DesignTokens.outlineWidth)
    @Environment(\.canvasMetrics) private var metrics

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: metrics.u(cornerRadius), style: .circular)
        content.background {
            ZStack {
                shape.fill(Color.ink).offset(y: metrics.u(shadowDepth))
                shape.fill(fill)
                shape.strokeBorder(Color.ink, lineWidth: metrics.u(lineWidth))
            }
        }
    }
}
