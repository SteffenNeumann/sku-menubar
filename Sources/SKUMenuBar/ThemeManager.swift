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
    let acTextR, acTextG, acTextB: Double  // darker text variant for medium-tone backgrounds

    // Light/dark variant flag
    let isLight: Bool

    // Medium-tone themes (mid-grey range, ~96–140 brightness) — need dark text like light themes
    var isMedium: Bool { ["slate", "pewter", "ash"].contains(id) }

    // Computed accent colors using Mirror's opacity scale
    var accentSoft:         Color { Color(r: acR, g: acG, b: acB, a: 0.10) }
    var accent:             Color { Color(r: acR, g: acG, b: acB, a: 0.15) }
    var accentHover:        Color { Color(r: acR, g: acG, b: acB, a: 0.20) }
    var accentStrong:       Color { Color(r: acR, g: acG, b: acB, a: 0.60) }
    var accentFull:         Color { Color(r: acR, g: acG, b: acB, a: 1.00) }
    var accentText:         Color { Color(r: acTextR, g: acTextG, b: acTextB, a: 1.0) }
    var accentBorder:       Color { Color(r: acR, g: acG, b: acB, a: 0.30) }
    var accentBorderStrong: Color { Color(r: acR, g: acG, b: acB, a: 0.40) }
    var accentRing:         Color { Color(r: acR, g: acG, b: acB, a: 0.25) }

    // Background gradient
    var bgTop: Color { Color(r: bgTopR, g: bgTopG, b: bgTopB, a: bgTopA) }
    var bgBot: Color { Color(r: bgBotR, g: bgBotG, b: bgBotB, a: bgBotA) }

    // Card surface (Mirror: rgba(255,255,255,0.05))
    var cardBg:     Color { (isLight || isMedium) ? Color(white: 0, opacity: 0.07) : Color(white: 1, opacity: 0.05) }
    var cardBorder: Color { (isLight || isMedium) ? Color(white: 0, opacity: 0.15) : Color(white: 1, opacity: 0.12) }

    // Solid card surface (flat, no material blur)
    var cardSurface: Color {
        if isLight {
            return Color(red: 240/255, green: 242/255, blue: 248/255)
        } else if isMedium {
            return Color(white: 1, opacity: 0.72)
        } else {
            return Color(white: 1, opacity: 0.07)
        }
    }

    // Row/item background — used for list rows and action buttons inside tiles
    var rowBg: Color { (isLight || isMedium) ? Color.black.opacity(0.05) : Color.white.opacity(0.04) }

    // Hover background — subtle tint for hovered rows/items
    var hoverBg: Color { (isLight || isMedium) ? Color.black.opacity(0.08) : Color.white.opacity(0.06) }

    // Sidebar surface (Mirror: rgba(2,6,23,0.75) dark / rgba(248,241,233,0.95) light)
    var sidebarBg: Color {
        if isLight {
            return Color(r: 248, g: 241, b: 233, a: 0.82)
        } else if glowEnabled {
            return Color(r: 2, g: 6, b: 23, a: 0.75)
        } else {
            return Color(r: bgTopR, g: bgTopG, b: bgTopB, a: 0.90)
        }
    }

    // Primary text — medium themes get dark text like light themes for sufficient contrast
    var primaryText:   Color { (isLight || isMedium) ? Color(white: 0.05) : Color(white: 0.95) }
    var secondaryText: Color { (isLight || isMedium) ? Color(white: 0.25) : Color(white: 0.60) }
    var tertiaryText:  Color { (isLight || isMedium) ? Color(white: 0.42) : Color(white: 0.40) }

    // Base window background — glow themes use deep-space blue, others use their own bgTop
    var windowBg: Color {
        if isLight {
            return Color(r: bgTopR, g: bgTopG, b: bgTopB, a: 1)
        } else if glowEnabled {
            return Color(r: 2, g: 6, b: 23, a: 1)
        } else {
            return Color(r: bgTopR, g: bgTopG, b: bgTopB, a: 1)
        }
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

    static let all: [AppTheme] = [cyan, emerald, violet, coffeeDark, bitterDark, monoDark, graphite, stone, eclipse, iron, basalt, coffeeLight, bitterLight, monoLight, fog, dusk, mist, cement, slate, pewter, ash]

    static let cyan = AppTheme(
        id: "cyan", name: "Cyan",
        bgTopR: 14,  bgTopG: 165, bgTopB: 233, bgTopA: 0.20,
        bgBotR: 59,  bgBotG: 130, bgBotB: 246, bgBotA: 0.12,
        glowEnabled: true,
        acR: 14, acG: 165, acB: 233,
        acTextR: 14, acTextG: 165, acTextB: 233,
        isLight: false
    )
    static let emerald = AppTheme(
        id: "emerald", name: "Emerald",
        bgTopR: 34, bgTopG: 197, bgTopB: 94,  bgTopA: 0.18,
        bgBotR: 21, bgBotG: 128, bgBotB: 61,  bgBotA: 0.10,
        glowEnabled: true,
        acR: 34, acG: 197, acB: 94,
        acTextR: 34, acTextG: 197, acTextB: 94,
        isLight: false
    )
    static let violet = AppTheme(
        id: "violet", name: "Violet",
        bgTopR: 124, bgTopG: 58, bgTopB: 237, bgTopA: 0.20,
        bgBotR: 99,  bgBotG: 102,bgBotB: 241, bgBotA: 0.12,
        glowEnabled: true,
        acR: 124, acG: 58, acB: 237,
        acTextR: 167, acTextG: 139, acTextB: 250, // #A78BFA — 7.8:1 on dark bg
        isLight: false
    )
    static let coffeeDark = AppTheme(
        id: "coffeeDark", name: "Coffee Dark",
        bgTopR: 38, bgTopG: 29, bgTopB: 26, bgTopA: 0.9,
        bgBotR: 28, bgBotG: 22, bgBotB: 20, bgBotA: 0.92,
        glowEnabled: false,
        acR: 201, acG: 155, acB: 119,
        acTextR: 201, acTextG: 155, acTextB: 119,
        isLight: false
    )
    static let bitterDark = AppTheme(
        id: "bitterDark", name: "Bitter Dark",
        bgTopR: 13, bgTopG: 12, bgTopB: 16, bgTopA: 1.0,
        bgBotR: 21, bgBotG: 21, bgBotB: 24, bgBotA: 1.0,
        glowEnabled: false,
        acR: 255, acG: 35, acB: 1,
        acTextR: 255, acTextG: 35, acTextB: 1,
        isLight: false
    )
    static let coffeeLight = AppTheme(
        id: "coffeeLight", name: "Coffee Light",
        bgTopR: 248, bgTopG: 241, bgTopB: 233, bgTopA: 0.95,
        bgBotR: 239, bgBotG: 226, bgBotB: 217, bgBotA: 0.94,
        glowEnabled: false,
        acR: 176, acG: 112, acB: 73,
        acTextR: 138, acTextG: 74, acTextB: 31, // #8A4A1F — 5.5:1 on cream
        isLight: true
    )
    static let bitterLight = AppTheme(
        id: "bitterLight", name: "Bitter Light",
        bgTopR: 247, bgTopG: 246, bgTopB: 244, bgTopA: 1.0,
        bgBotR: 240, bgBotG: 238, bgBotB: 235, bgBotA: 1.0,
        glowEnabled: false,
        acR: 255, acG: 35, acB: 1,
        acTextR: 192, acTextG: 26, acTextB: 0, // #C01A00 — 5.3:1 on off-white
        isLight: true
    )
    static let monoDark = AppTheme(
        id: "monoDark", name: "Mono Dark",
        bgTopR: 13, bgTopG: 17, bgTopB: 23, bgTopA: 1.0,
        bgBotR: 13, bgBotG: 17, bgBotB: 23, bgBotA: 1.0,
        glowEnabled: false,
        acR: 88, acG: 166, acB: 255,
        acTextR: 88, acTextG: 166, acTextB: 255,
        isLight: false
    )
    static let monoLight = AppTheme(
        id: "monoLight", name: "Mono Light",
        bgTopR: 246, bgTopG: 248, bgTopB: 250, bgTopA: 1.0,
        bgBotR: 246, bgBotG: 248, bgBotB: 250, bgBotA: 1.0,
        glowEnabled: false,
        acR: 9, acG: 105, acB: 218,
        acTextR: 9, acTextG: 105, acTextB: 218,
        isLight: true
    )

    // ── Grey Shades ──────────────────────────────────────────────────────────

    // Eclipse — ultra-tief, kühl, blau-grau (Linear/Vercel-Stil)
    static let eclipse = AppTheme(
        id: "eclipse", name: "Eclipse",
        bgTopR: 17,  bgTopG: 17,  bgTopB: 19,  bgTopA: 1.0,
        bgBotR: 8,   bgBotG: 8,   bgBotB: 11,  bgBotA: 1.0,
        glowEnabled: false,
        acR: 124, acG: 124, acB: 138,
        acTextR: 124, acTextG: 124, acTextB: 138,
        isLight: false
    )
    // Iron — near-black mit subtilen Lila/Rose Glow-Blobs (Raycast/Fig-Stil)
    static let iron = AppTheme(
        id: "iron", name: "Iron",
        bgTopR: 160, bgTopG: 32,  bgTopB: 240, bgTopA: 0.10,
        bgBotR: 244, bgBotG: 63,  bgBotB: 94,  bgBotA: 0.07,
        glowEnabled: true,
        acR: 224, acG: 64, acB: 251,
        acTextR: 224, acTextG: 64, acTextB: 251,
        isLight: false
    )
    // Basalt — warmes Anthrazit mit leuchtendem Orange (macOS Premium Night)
    static let basalt = AppTheme(
        id: "basalt", name: "Basalt",
        bgTopR: 30,  bgTopG: 28,  bgTopB: 26,  bgTopA: 1.0,
        bgBotR: 22,  bgBotG: 20,  bgBotB: 18,  bgBotA: 1.0,
        glowEnabled: false,
        acR: 251, acG: 146, acB: 60,
        acTextR: 251, acTextG: 146, acTextB: 60,
        isLight: false
    )

    static let fog = AppTheme(
        id: "fog", name: "Fog",
        bgTopR: 232, bgTopG: 232, bgTopB: 232, bgTopA: 1.0,
        bgBotR: 220, bgBotG: 220, bgBotB: 220, bgBotA: 1.0,
        glowEnabled: false,
        acR: 59, acG: 130, acB: 246,
        acTextR: 14, acTextG: 77, acTextB: 161, // #0E4DA1 — 5.9:1 on light grey
        isLight: true
    )
    // Dusk — warmes Greige, Paper-Ton (Obsidian/Bear-Stil)
    static let dusk = AppTheme(
        id: "dusk", name: "Dusk",
        bgTopR: 212, bgTopG: 208, bgTopB: 202, bgTopA: 1.0,
        bgBotR: 200, bgBotG: 196, bgBotB: 190, bgBotA: 1.0,
        glowEnabled: false,
        acR: 124, acG: 58, acB: 237,
        acTextR: 90, acTextG: 30, acTextB: 140, // #5A1E8C — 6.3:1 on warm greige
        isLight: true
    )
    // Mist — kühles Blaugrau (Notion/Linear Light-Stil)
    static let mist = AppTheme(
        id: "mist", name: "Mist",
        bgTopR: 205, bgTopG: 210, bgTopB: 216, bgTopA: 1.0,
        bgBotR: 191, bgBotG: 197, bgBotB: 204, bgBotA: 1.0,
        glowEnabled: false,
        acR: 59, acG: 130, acB: 246,
        acTextR: 14, acTextG: 77, acTextB: 161, // #0E4DA1 — 4.7:1 on blue-grey
        isLight: true
    )
    // Cement — neutrales Mittelgrau, kein Farbstich
    // Accent: tiefes Bernstein-Orange (245→210, 158→95) — deutlich höherer Kontrast auf Hellgrau
    static let cement = AppTheme(
        id: "cement", name: "Cement",
        bgTopR: 200, bgTopG: 200, bgTopB: 200, bgTopA: 1.0,
        bgBotR: 186, bgBotG: 186, bgBotB: 186, bgBotA: 1.0,
        glowEnabled: false,
        acR: 200, acG: 85, acB: 5,
        acTextR: 140, acTextG: 55, acTextB: 0,
        isLight: true
    )
    // Slate — Cool steel-blue, Linear/Raycast mid-tone feel
    // Content: desaturated blue-steel (176,181,192) → WCAG AA ~5.1:1 with black text
    // Sidebar: 36 pts darker, clear structural separation
    // Accent: vivid sky-blue, saturated enough to pop on the mid-grey surface
    static let slate = AppTheme(
        id: "slate", name: "Slate",
        bgTopR: 176, bgTopG: 181, bgTopB: 192, bgTopA: 1.0,
        bgBotR: 138, bgBotG: 143, bgBotB: 156, bgBotA: 1.0,
        glowEnabled: false,
        acR: 37, acG: 139, acB: 242,
        acTextR: 11, acTextG: 41, acTextB: 72,
        isLight: false
    )
    // Pewter — Warm titanium-silver, Apple Pro Hardware feel
    // Content: warm greige (182,177,170) → WCAG AA ~5.3:1 with black text
    // Sidebar: 40 pts cooler-darker, reinforces premium layering
    // Accent: deep amber-orange, rich against the warm grey
    static let pewter = AppTheme(
        id: "pewter", name: "Pewter",
        bgTopR: 182, bgTopG: 177, bgTopB: 170, bgTopA: 1.0,
        bgBotR: 140, bgBotG: 136, bgBotB: 130, bgBotA: 1.0,
        glowEnabled: false,
        acR: 234, acG: 108, acB: 19,
        acTextR: 58, acTextG: 27, acTextB: 4,
        isLight: false
    )
    // Ash — Neutral blue-grey, clean macOS / Notion feel
    // Content: cool neutral (172,173,180) → WCAG AA ~4.9:1 with black text
    // Sidebar: 38 pts darker, clean split without warmth or coolness bias
    // Accent: vivid teal-mint, high saturation for visibility on neutral grey
    static let ash = AppTheme(
        id: "ash", name: "Ash",
        bgTopR: 172, bgTopG: 173, bgTopB: 180, bgTopA: 1.0,
        bgBotR: 130, bgBotG: 131, bgBotB: 140, bgBotA: 1.0,
        glowEnabled: false,
        acR: 16, acG: 210, acB: 176,
        acTextR: 5, acTextG: 73, acTextB: 61,
        isLight: false
    )
    static let stone = AppTheme(
        id: "stone", name: "Stone",
        bgTopR: 72, bgTopG: 72, bgTopB: 76, bgTopA: 1.0,
        bgBotR: 58, bgBotG: 58, bgBotB: 62, bgBotA: 1.0,
        glowEnabled: false,
        acR: 245, acG: 158, acB: 11,
        acTextR: 251, acTextG: 185, acTextB: 41, // #FBB929 — 4.7:1 on dark grey
        isLight: false
    )
    static let graphite = AppTheme(
        id: "graphite", name: "Graphite",
        bgTopR: 28, bgTopG: 28, bgTopB: 30, bgTopA: 1.0,
        bgBotR: 20, bgBotG: 20, bgBotB: 22, bgBotA: 1.0,
        glowEnabled: false,
        acR: 160, acG: 160, acB: 165,
        acTextR: 160, acTextG: 160, acTextB: 165,
        isLight: false
    )
}

// MARK: - Theme Manager

@MainActor
final class ThemeManager: ObservableObject {
    @Published var current: AppTheme = .cyan {
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
    static let defaultValue: AppTheme = .cyan
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
