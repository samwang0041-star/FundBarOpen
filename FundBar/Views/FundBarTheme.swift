import SwiftUI

enum FundBarTheme {
    static let accent = Color(red: 0.22, green: 0.57, blue: 0.97)
    static let accentSoft = Color(red: 0.70, green: 0.90, blue: 1.0)
    static let accentDeep = Color(red: 0.14, green: 0.39, blue: 0.86)
    static let positive = Color(red: 0.88, green: 0.35, blue: 0.36)
    static let negative = Color(red: 0.25, green: 0.71, blue: 0.54)
    static let stale = Color(red: 0.94, green: 0.60, blue: 0.27)
    static let textPrimary = Color(red: 0.16, green: 0.19, blue: 0.24)
    static let textSecondary = Color(red: 0.40, green: 0.45, blue: 0.54)
    static let textTertiary = Color(red: 0.62, green: 0.66, blue: 0.74)
    static let softShadow = Color.black.opacity(0.10)

    static func trendColor(_ value: Double?) -> Color {
        guard let value else { return textSecondary }
        if value > 0 { return positive }
        if value < 0 { return negative }
        return textSecondary
    }
}

struct FundBarCanvasBackground: View {
    var body: some View {
        ZStack {
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

struct FundBarCardBackground: View {
    var tint: Color = Color.white

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        tint.opacity(0.92),
                        Color.white.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.56), lineWidth: 0.5)
            )
            .shadow(color: FundBarTheme.softShadow.opacity(0.06), radius: 8, x: 0, y: 4)
            .shadow(color: FundBarTheme.softShadow.opacity(0.04), radius: 20, x: 0, y: 12)
    }
}

struct FundBarHeroBackground: View {
    var body: some View {
        ZStack {
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
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.50), lineWidth: 0.5)
        )
        .shadow(color: FundBarTheme.accent.opacity(0.10), radius: 16, x: 0, y: 8)
        .shadow(color: FundBarTheme.accent.opacity(0.06), radius: 28, x: 0, y: 14)
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
                .fill(Color.white.opacity(0.46))
        )
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
            return FundBarTheme.accentDeep
        case .destructive:
            return FundBarTheme.positive
        }
    }

    private var borderColor: Color {
        switch tone {
        case .accent:
            return FundBarTheme.accent.opacity(0.18)
        case .neutral:
            return Color.white.opacity(0.50)
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
            return Color.white.opacity(isPressed ? 0.52 : 0.72)
        case .destructive:
            return FundBarTheme.positive.opacity(isPressed ? 0.12 : 0.08)
        }
    }
}
