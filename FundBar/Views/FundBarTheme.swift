import SwiftUI

enum FundBarTheme {
    // Accent colors (same in both modes)
    static let accent = Color(red: 0.22, green: 0.57, blue: 0.97)
    static let accentSoft = Color(red: 0.70, green: 0.90, blue: 1.0)
    static let accentDeep = Color(red: 0.14, green: 0.39, blue: 0.86)

    // Semantic colors (same in both modes - intentional for financial data)
    static let positive = Color(red: 0.88, green: 0.35, blue: 0.36)
    static let negative = Color(red: 0.25, green: 0.71, blue: 0.54)
    static let stale = Color(red: 0.94, green: 0.60, blue: 0.27)

    // Adaptive text colors (using NSColor dynamic provider for correct NSPopover appearance)
    static let textPrimary = Color(nsColor: NSColor(name: "DynamicTextPrimary", dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
            : NSColor(red: 0.16, green: 0.19, blue: 0.24, alpha: 1.0)
    }))
    static let textSecondary = Color(nsColor: NSColor(name: "DynamicTextSecondary", dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(red: 0.62, green: 0.65, blue: 0.70, alpha: 1.0)
            : NSColor(red: 0.40, green: 0.45, blue: 0.54, alpha: 1.0)
    }))
    static let textTertiary = Color(nsColor: NSColor(name: "DynamicTextTertiary", dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(red: 0.45, green: 0.48, blue: 0.53, alpha: 1.0)
            : NSColor(red: 0.62, green: 0.66, blue: 0.74, alpha: 1.0)
    }))

    // Adaptive surface colors
    static let cardFill = Color(nsColor: NSColor(name: "DynamicCardFill", dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 0.85)
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.82)
    }))
    static let canvasBase = Color(nsColor: NSColor(name: "DynamicCanvasBase", dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 0.96)
            : NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.96)
    }))
    static let softShadow = Color.black.opacity(0.10)

    // Adaptive chip/pill background
    static let chipFill = Color(nsColor: NSColor(name: "DynamicChipFill", dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(white: 1.0, alpha: 0.08)
            : NSColor(white: 1.0, alpha: 0.50)
    }))
    static let chipFillStrong = Color(nsColor: NSColor(name: "DynamicChipFillStrong", dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
            ? NSColor(white: 1.0, alpha: 0.12)
            : NSColor(white: 1.0, alpha: 0.92)
    }))

    static func trendColor(_ value: Double?) -> Color {
        guard let value else { return textSecondary }
        if value > 0 { return positive }
        if value < 0 { return negative }
        return textSecondary
    }
}

struct FundBarCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.96),
                        FundBarTheme.accent.opacity(0.12),
                        Color(red: 0.10, green: 0.11, blue: 0.14).opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(FundBarTheme.accent.opacity(0.15))
                    .frame(width: 220, height: 220)
                    .blur(radius: 70)
                    .offset(x: 150, y: -180)
                Circle()
                    .fill(Color.black.opacity(0.30))
                    .frame(width: 240, height: 240)
                    .blur(radius: 85)
                    .offset(x: -180, y: 180)
            } else {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.96),
                        FundBarTheme.accentSoft.opacity(0.38),
                        Color.white.opacity(0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(FundBarTheme.accentSoft.opacity(0.55))
                    .frame(width: 220, height: 220)
                    .blur(radius: 70)
                    .offset(x: 150, y: -180)
                Circle()
                    .fill(Color.white.opacity(0.88))
                    .frame(width: 240, height: 240)
                    .blur(radius: 85)
                    .offset(x: -180, y: 180)
            }
        }
    }
}

struct FundBarCardBackground: View {
    var tint: Color = Color.white
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let baseTint = colorScheme == .dark ? Color(red: 0.16, green: 0.18, blue: 0.22) : tint
        let borderColor = colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.56)
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        baseTint.opacity(colorScheme == .dark ? 0.85 : 0.92),
                        (colorScheme == .dark ? Color(red: 0.12, green: 0.14, blue: 0.18) : Color.white).opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            .shadow(color: FundBarTheme.softShadow.opacity(colorScheme == .dark ? 0.20 : 0.06), radius: 8, x: 0, y: 4)
            .shadow(color: FundBarTheme.softShadow.opacity(colorScheme == .dark ? 0.14 : 0.04), radius: 20, x: 0, y: 12)
    }
}

struct FundBarHeroBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.16, blue: 0.26),
                        Color(red: 0.10, green: 0.14, blue: 0.24),
                        Color(red: 0.08, green: 0.12, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(FundBarTheme.accent.opacity(0.20))
                    .frame(width: 150, height: 150)
                    .blur(radius: 22)
                    .offset(x: 130, y: -70)
                Circle()
                    .fill(FundBarTheme.accent.opacity(0.10))
                    .frame(width: 180, height: 180)
                    .blur(radius: 24)
                    .offset(x: -120, y: 80)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.90, green: 0.96, blue: 1.0),
                        Color(red: 0.77, green: 0.90, blue: 1.0),
                        Color(red: 0.68, green: 0.84, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.white.opacity(0.65))
                    .frame(width: 150, height: 150)
                    .blur(radius: 22)
                    .offset(x: 130, y: -70)
                Circle()
                    .fill(FundBarTheme.accent.opacity(0.12))
                    .frame(width: 180, height: 180)
                    .blur(radius: 24)
                    .offset(x: -120, y: 80)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke((colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.50)), lineWidth: 0.5)
        )
        .shadow(color: FundBarTheme.accent.opacity(colorScheme == .dark ? 0.20 : 0.10), radius: 16, x: 0, y: 8)
        .shadow(color: FundBarTheme.accent.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 28, x: 0, y: 14)
    }
}

struct FundBarTag: View {
    let text: String
    var tone: Color = FundBarTheme.accent
    
    @State private var isBreathing = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tone)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.opacity(0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tone.opacity(0.12), lineWidth: 0.5)
            )
            .opacity(tone == FundBarTheme.negative ? (isBreathing ? 0.35 : 1.0) : 1.0)
            .onAppear {
                if tone == FundBarTheme.negative {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        isBreathing = true
                    }
                }
            }
            .onChange(of: tone) { _, newTone in
                if newTone == FundBarTheme.negative {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                        isBreathing = true
                    }
                } else {
                    withAnimation { isBreathing = false }
                }
            }
    }
}

struct FundBarStatusMessage: View {
    let text: String
    var highlighted = false

    var body: some View {
        Group {
            if highlighted {
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FundBarTheme.accentDeep)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(FundBarTheme.accent.opacity(0.12))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(FundBarTheme.accent.opacity(0.18), lineWidth: 0.6)
                    )
            } else {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FundBarTheme.textSecondary)
            }
        }
    }
}

struct FundBarMetricChip: View {
    let title: String
    let value: String
    var tint: Color = FundBarTheme.textSecondary

    private var valueColor: Color {
        tint == FundBarTheme.textSecondary ? FundBarTheme.textPrimary : tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FundBarTheme.textSecondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(valueColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FundBarTheme.chipFill)
        )
    }
}

struct FundBarSourceModeTag: View {
    let mode: SnapshotSourceMode?

    var body: some View {
        switch mode {
        case .realtime:
            FundBarTag(text: "实时", tone: FundBarTheme.negative)
        case .estimated:
            FundBarTag(text: "本地估算", tone: FundBarTheme.stale)
        case .preOpenEstimated:
            FundBarTag(text: "盘前估算", tone: FundBarTheme.accent)
        case .estimatedClosed:
            FundBarTag(text: "本地参考", tone: FundBarTheme.textSecondary)
        case .official, nil:
            EmptyView()
        }
    }
}

enum FundBarButtonTone {
    case accent
    case neutral
    case destructive
}

struct FundBarButtonStyle: ButtonStyle {
    let tone: FundBarButtonTone

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(foregroundColor)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor(configuration.isPressed))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch tone {
        case .accent:
            return .white
        case .neutral:
            return FundBarTheme.accent
        case .destructive:
            return FundBarTheme.positive
        }
    }

    private var borderColor: Color {
        switch tone {
        case .accent:
            return FundBarTheme.accent.opacity(0.18)
        case .neutral:
            return FundBarTheme.textTertiary.opacity(0.30)
        case .destructive:
            return FundBarTheme.positive.opacity(0.12)
        }
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        let pressedOpacity = isPressed ? 0.85 : 1.0
        switch tone {
        case .accent:
            return FundBarTheme.accent.opacity(pressedOpacity)
        case .neutral:
            return FundBarTheme.textTertiary.opacity(isPressed ? 0.18 : 0.12)
        case .destructive:
            return FundBarTheme.positive.opacity(isPressed ? 0.12 : 0.08)
        }
    }
}
