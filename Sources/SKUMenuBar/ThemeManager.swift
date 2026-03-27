import SwiftUI

// MARK: - Theme Definition
// Ported from Mirror app (app.js theme palette + app.css variables)

struct AppTheme: Identifiable, Equatable, Codable {
    let id: String
    let name: String

    // Background gradient (top/bottom glow blob colors)
    let bgTopR, bgTopG, bgTopB, bgTopA: Double
    let bgBotR, bgBotG, bgBotB, bgBotA: Double
    let glowEnabled: Bool

    // Accent tints (all premultiplied RGBA so we store as components)
    let acR, acG, acB: Double        // base accent RGB (0–255)

    // Light/dark variant flag
    let isLight: Bool

    // Computed accent colors using Mirror's opacity scale
    var accentSoft:         Color { Color(r: acR, g: acG, b: acB, a: 0.10) }
    var accent:             Color { Color(r: acR, g: acG, b: acB, a: 0.15) }
    var accentHover:        Color { Color(r: acR, g: acG, b: acB, a: 0.20) }
    var accentStrong:       Color { Color(r: acR, g: acG, b: acB, a: 0.60) }
    var accentBorder:       Color { Color(r: acR, g: acG, b: acB, a: 0.30) }
    var accentBorderStrong: Color { Color(r: acR, g: acG, b: acB, a: 0.40) }
    var accentRing:         Color { Color(r: acR, g: acG, b: acB, a: 0.25) }

    // Background gradient
    var bgTop: Color { Color(r: bgTopR, g: bgTopG, b: bgTopB, a: bgTopA) }
    var bgBot: Color { Color(r: bgBotR, g: bgBotG, b: bgBotB, a: bgBotA) }

    // Card surface (Mirror: rgba(255,255,255,0.05))
    var cardBg:     Color { isLight ? Color(white: 0, opacity: 0.04) : Color(white: 1, opacity: 0.05) }
    var cardBorder: Color { isLight ? Color(white: 0, opacity: 0.12) : Color(white: 1, opacity: 0.12) }

    // Solid card surface (flat, no material blur)
    var cardSurface: Color {
        isLight
            ? Color(red: 240/255, green: 242/255, blue: 248/255)
            : Color(white: 1, opacity: 0.07)
    }

    // Sidebar surface (Mirror: rgba(2,6,23,0.75) dark / rgba(248,241,233,0.95) light)
    var sidebarBg: Color {
        isLight
            ? Color(r: 248, g: 241, b: 233, a: 0.82)
            : Color(r:   2, g:   6, b:  23, a: 0.75)
    }

    // Primary text
    var primaryText:   Color { isLight ? Color(white: 0.08) : Color(white: 0.95) }
    var secondaryText: Color { isLight ? Color(white: 0.35) : Color(white: 0.60) }
    var tertiaryText:  Color { isLight ? Color(white: 0.55) : Color(white: 0.40) }

    // Base window background
    var windowBg: Color {
        isLight ? Color(r: 246, g: 248, b: 250, a: 1) : Color(r: 2, g: 6, b: 23, a: 1)
    }
}

private extension Color {
    init(r: Double, g: Double, b: Double, a: Double) {
        self.init(.sRGB, red: r/255, green: g/255, blue: b/255, opacity: a)
    }
    init(white: Double) { self.init(.sRGB, white: white, opacity: 1) }
}

// MARK: - Theme Catalogue
// All 9 themes from Mirror — names, accent RGB, gradient blob colors

extension AppTheme {

    static let all: [AppTheme] = [fuchsia, cyan, emerald, violet, coffeeDark, bitterDark, coffeeLight, bitterLight, monoDark]

    static let fuchsia = AppTheme(
        id: "fuchsia", name: "Fuchsia",
        bgTopR: 217, bgTopG: 70,  bgTopB: 239, bgTopA: 0.15,
        bgBotR: 34,  bgBotG: 211, bgBotB: 238, bgBotA: 0.10,
        glowEnabled: true,
        acR: 217, acG: 70, acB: 239, isLight: false
    )
    static let cyan = AppTheme(
        id: "cyan", name: "Cyan",
        bgTopR: 14,  bgTopG: 165, bgTopB: 233, bgTopA: 0.20,
        bgBotR: 59,  bgBotG: 130, bgBotB: 246, bgBotA: 0.12,
        glowEnabled: true,
        acR: 14, acG: 165, acB: 233, isLight: false
    )
    static let emerald = AppTheme(
        id: "emerald", name: "Emerald",
        bgTopR: 34, bgTopG: 197, bgTopB: 94,  bgTopA: 0.18,
        bgBotR: 21, bgBotG: 128, bgBotB: 61,  bgBotA: 0.10,
        glowEnabled: true,
        acR: 34, acG: 197, acB: 94, isLight: false
    )
    static let violet = AppTheme(
        id: "violet", name: "Violet",
        bgTopR: 124, bgTopG: 58, bgTopB: 237, bgTopA: 0.20,
        bgBotR: 99,  bgBotG: 102,bgBotB: 241, bgBotA: 0.12,
        glowEnabled: true,
        acR: 124, acG: 58, acB: 237, isLight: false
    )
    static let coffeeDark = AppTheme(
        id: "coffeeDark", name: "Coffee Dark",
        bgTopR: 38, bgTopG: 29, bgTopB: 26, bgTopA: 0.9,
        bgBotR: 28, bgBotG: 22, bgBotB: 20, bgBotA: 0.92,
        glowEnabled: false,
        acR: 201, acG: 155, acB: 119, isLight: false
    )
    static let bitterDark = AppTheme(
        id: "bitterDark", name: "Bitter Dark",
        bgTopR: 13, bgTopG: 12, bgTopB: 16, bgTopA: 1.0,
        bgBotR: 21, bgBotG: 21, bgBotB: 24, bgBotA: 1.0,
        glowEnabled: false,
        acR: 255, acG: 35, acB: 1, isLight: false
    )
    static let coffeeLight = AppTheme(
        id: "coffeeLight", name: "Coffee Light",
        bgTopR: 248, bgTopG: 241, bgTopB: 233, bgTopA: 0.95,
        bgBotR: 239, bgBotG: 226, bgBotB: 217, bgBotA: 0.94,
        glowEnabled: false,
        acR: 176, acG: 112, acB: 73, isLight: true
    )
    static let bitterLight = AppTheme(
        id: "bitterLight", name: "Bitter Light",
        bgTopR: 247, bgTopG: 246, bgTopB: 244, bgTopA: 1.0,
        bgBotR: 240, bgBotG: 238, bgBotB: 235, bgBotA: 1.0,
        glowEnabled: false,
        acR: 255, acG: 35, acB: 1, isLight: true
    )
    static let monoDark = AppTheme(
        id: "monoDark", name: "Mono Dark",
        bgTopR: 13, bgTopG: 17, bgTopB: 23, bgTopA: 1.0,
        bgBotR: 13, bgBotG: 17, bgBotB: 23, bgBotA: 1.0,
        glowEnabled: false,
        acR: 88, acG: 166, acB: 255, isLight: false
    )
}

// MARK: - Theme Manager

@MainActor
final class ThemeManager: ObservableObject {
    @Published var current: AppTheme = .fuchsia {
        didSet { persist() }
    }

    private let udKey = "myClaude_themeId"

    init() {
        if let saved = UserDefaults.standard.string(forKey: udKey),
           let t = AppTheme.all.first(where: { $0.id == saved }) {
            current = t
        }
    }

    private func persist() {
        UserDefaults.standard.set(current.id, forKey: udKey)
    }
}

// MARK: - Environment Key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .fuchsia
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Themed Glass Card Modifier
// Replaces the old GlassCard with Mirror-accurate card styling

struct MirrorGlassCard: ViewModifier {
    @Environment(\.appTheme) var theme
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(theme.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(theme.cardBorder, lineWidth: 1)
            )
    }
}

extension View {
    /// Mirror-themed glass card — replaces glassCard() across the app
    func mirrorCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(MirrorGlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Background Glow View (Mirror's bg-blob effect)

struct GlowBackground: View {
    @Environment(\.appTheme) var theme

    var body: some View {
        ZStack {
            // Base: very dark window background
            theme.windowBg.ignoresSafeArea()

            if theme.glowEnabled {
                // Top-left glow blob
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [theme.bgTop, .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 400
                        )
                    )
                    .frame(width: 700, height: 700)
                    .blur(radius: 90)
                    .offset(x: -200, y: -200)
                    .opacity(0.81)
                    .ignoresSafeArea()

                // Bottom-right glow blob
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [theme.bgBot, .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 350
                        )
                    )
                    .frame(width: 600, height: 600)
                    .blur(radius: 90)
                    .offset(x: 300, y: 300)
                    .opacity(0.81)
                    .ignoresSafeArea()
            }
        }
    }
}
