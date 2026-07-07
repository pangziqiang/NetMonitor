import NetworkMonitorCore
import SwiftUI

// MARK: - Theme Colors

struct ThemeColors {
    let appBg: Color
    let cardBg: Color
    let cardBorder: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color
    let tableHeaderBg: Color
    let tableRowAlt: Color

    static let dark = ThemeColors(
        appBg: Color(red: 0x0f / 255, green: 0x0f / 255, blue: 0x23 / 255),
        cardBg: Color.white.opacity(0.06),
        cardBorder: Color.white.opacity(0.08),
        textPrimary: Color(red: 0xe2 / 255, green: 0xe8 / 255, blue: 0xf0 / 255),
        textSecondary: Color.white.opacity(0.72),
        textMuted: Color.white.opacity(0.5),
        tableHeaderBg: Color.white.opacity(0.04),
        tableRowAlt: Color.white.opacity(0.03)
    )

    static let light = ThemeColors(
        appBg: Color(red: 0xf8 / 255, green: 0xf9 / 255, blue: 0xfa / 255),
        cardBg: .white,
        cardBorder: Color(red: 0xe2 / 255, green: 0xe5 / 255, blue: 0xe9 / 255),
        textPrimary: Color(red: 0x1a / 255, green: 0x1a / 255, blue: 0x2e / 255),
        textSecondary: Color(red: 0x6b / 255, green: 0x72 / 255, blue: 0x80 / 255),
        textMuted: Color(red: 0x9c / 255, green: 0xa3 / 255, blue: 0xaf / 255),
        tableHeaderBg: Color(red: 0xf1 / 255, green: 0xf3 / 255, blue: 0xf5 / 255),
        tableRowAlt: Color(red: 0xf9 / 255, green: 0xfa / 255, blue: 0xfb / 255)
    )
}

// MARK: - Semantic Colors (scheme-adaptive via ThemeColors, scheme-independent accents below)

extension Color {
    static let uploadColor = Color(red: 0x9d / 255, green: 0x78 / 255, blue: 0xfc / 255)
    static let downloadColor = Color(red: 0x34 / 255, green: 0xd3 / 255, blue: 0x99 / 255)
    static let accentPurple = Color(red: 0x8b / 255, green: 0x4c / 255, blue: 0xf7 / 255)
    static let connectionBlue = Color(red: 0x4e / 255, green: 0x8c / 255, blue: 0xf7 / 255)
    static let memoryPink = Color(red: 0xf4 / 255, green: 0x72 / 255, blue: 0xb6 / 255)
    static let warningColor = Color(red: 0xfb / 255, green: 0xbf / 255, blue: 0x24 / 255)
    static let errorColor = Color(red: 0xef / 255, green: 0x44 / 255, blue: 0x44 / 255)
    static let glowPurple = Color(red: 0x8b / 255, green: 0x4c / 255, blue: 0xf7 / 255).opacity(0.15)
    static let glowGreen = Color(red: 0x34 / 255, green: 0xd3 / 255, blue: 0x99 / 255).opacity(0.12)
    static let cpuColor = Color(red: 0xfb / 255, green: 0xbf / 255, blue: 0x24 / 255)
    static let gpuColor = Color(red: 0x4e / 255, green: 0x8c / 255, blue: 0xf7 / 255)
    static let memoryColor = Color(red: 0x38 / 255, green: 0xdf / 255, blue: 0xc4 / 255)
    static let temperatureColor = Color(red: 0xef / 255, green: 0x44 / 255, blue: 0x44 / 255)
    static let statusActive = Color(red: 0x34 / 255, green: 0xd3 / 255, blue: 0x99 / 255)
    static let statusPaused = Color(red: 0xfb / 255, green: 0xbf / 255, blue: 0x24 / 255)
}

// MARK: - Environment Key

// MARK: - View Extension for Adaptive Colors

// MARK: - Spacing Tokens

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Corner Radius Tokens

enum CornerRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 14
    static let card: CGFloat = 14
}

// MARK: - Card Variants

enum CardVariant {
    case glass
    case solid
    case outline
    case elevated
    case tone(Color)
    case ghost
}

// MARK: - View Modifiers

struct CardModifier: ViewModifier {
    let variant: CardVariant
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        let colors = colorScheme == .dark ? ThemeColors.dark : ThemeColors.light
        let isDark = colorScheme == .dark
        let cornerRadius = CornerRadius.card
        switch variant {
        case .glass:
            content
                .background(colors.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(colors.cardBorder, lineWidth: 1))
        case .solid:
            content
                .background(colors.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(colors.cardBorder, lineWidth: 1))
        case .outline:
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(isDark ? Color.white.opacity(0.06) : colors.cardBorder, lineWidth: 1))
        case .elevated:
            content
                .background(colors.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(colors.cardBorder, lineWidth: 1))
        case let .tone(color):
            content
                .background(colors.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(color.opacity(isDark ? 0.25 : 0.15), lineWidth: 1))
        case .ghost:
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.05), lineWidth: 1))
        }
    }
}

// MARK: - Button Variants

enum ButtonVariant {
    case primary
    case secondary
    case glass
    case outline
    case ghost
    case destructive
}

struct GlassButtonStyle: ButtonStyle {
    let variant: ButtonVariant
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { colorScheme == .dark ? .dark : .light }

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        switch variant {
        case .primary:
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.lg).padding(.vertical, 6)
                .background(pressed ? Color.accentPurple.opacity(0.8) : Color.accentPurple)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .scaleEffect(pressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.15), value: pressed)
        case .secondary:
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.accentPurple)
                .padding(.horizontal, Spacing.lg).padding(.vertical, 6)
                .background(Color.accentPurple.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .glass:
            configuration.label
                .font(.system(size: 12))
                .foregroundColor(pressed ? theme.textPrimary : theme.textSecondary)
                .padding(.horizontal, Spacing.md).padding(.vertical, 6)
                .background(pressed ? Color.white.opacity(0.1) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .animation(.easeOut(duration: 0.15), value: pressed)
        case .outline:
            configuration.label
                .font(.system(size: 12))
                .foregroundColor(theme.textSecondary)
                .padding(.horizontal, Spacing.md).padding(.vertical, 6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.cardBorder, lineWidth: 1))
        case .ghost:
            configuration.label
                .font(.system(size: 12))
                .foregroundColor(pressed ? theme.textPrimary : theme.textSecondary)
                .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                .background(pressed ? Color.white.opacity(0.06) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .animation(.easeOut(duration: 0.15), value: pressed)
        case .destructive:
            configuration.label
                .font(.system(size: 12))
                .foregroundColor(pressed ? Color.errorColor.opacity(0.8) : Color.errorColor)
                .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
                .background(pressed ? Color.errorColor.opacity(0.06) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .animation(.easeOut(duration: 0.15), value: pressed)
        }
    }
}

// MARK: - Holographic Elements

enum Holographic {
    static let gradient = LinearGradient(
        colors: [Color.downloadColor, Color.uploadColor, Color.gpuColor, Color.memoryColor],
        startPoint: .leading, endPoint: .trailing
    )
}

extension View {
    func holographicTitle() -> some View {
        self.foregroundStyle(Holographic.gradient)
    }
}

// MARK: - View Extensions

extension View {
    func card(_ variant: CardVariant = .glass) -> some View {
        modifier(CardModifier(variant: variant))
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static func glass(_ variant: ButtonVariant) -> GlassButtonStyle {
        GlassButtonStyle(variant: variant)
    }
}
