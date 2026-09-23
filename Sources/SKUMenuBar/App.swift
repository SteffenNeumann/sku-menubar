import SwiftUI
import AppKit

@main
struct SKUMenuBarApp: App {
    /// Property-Initializer laufen in Deklarationsreihenfolge und vor dem init-Body —
    /// deshalb steht das hier oben und nicht in init(). Ohne SIG_IGN beendet ein Write
    /// auf eine geschlossene Pipe die App (SIGPIPE, exit 141), statt einen fangbaren
    /// Fehler zu liefern.
    private let sigpipeGuard: Void = { signal(SIGPIPE, SIG_IGN) }()
    @StateObject private var state = AppState()
    @StateObject private var themeManager = ThemeManager()

    init() {
        FontManager.registerBundledFonts()
        DispatchQueue.main.async {
            NSApp?.applicationIconImage = makeAppIcon()
        }
    }

    var body: some Scene {
        WindowGroup("") {
            MainWindowView()
                .environmentObject(state)
                .environmentObject(themeManager)
                .environment(\.appTheme, themeManager.current)
                .environment(\.colorScheme, themeManager.current.isLight ? .light : .dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsFormView()
                .environmentObject(state)
                .environmentObject(themeManager)
                .environment(\.appTheme, themeManager.current)
                .environment(\.colorScheme, themeManager.current.isLight ? .light : .dark)
                .padding(20)
                .frame(width: 520)
        }
    }
}

// MARK: - Programmatic App Icon (works for SPM executables without .app bundle)

private func makeAppIcon(size: Int = 512) -> NSImage {
    let s = CGFloat(size)
    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return NSImage() }
    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
        NSGraphicsContext.restoreGraphicsState()
        return NSImage()
    }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    // ── Rounded background ──────────────────────────────────────────────────
    let cornerR = s * 0.225
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)
    cg.addPath(bgPath)
    cg.clip()

    // Warmes Fast-Schwarz als Grund (bottom → top in CG coords)
    let bgColors = [
        CGColor(red: 0.098, green: 0.086, blue: 0.082, alpha: 1), // top
        CGColor(red: 0.055, green: 0.047, blue: 0.043, alpha: 1)  // bottom
    ]
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: bgColors as CFArray,
                            locations: [0, 1])!
    cg.drawLinearGradient(bgGrad,
                          start: CGPoint(x: s/2, y: s),
                          end: CGPoint(x: s/2, y: 0),
                          options: [])

    // ── Orange-Ring #FF2301 (ohne Füllung) mit leichter Corona ─────────────
    let c = CGPoint(x: s/2, y: s/2)
    let ringR = s * 0.20
    let ringW = s * 0.032
    let orange = (r: 1.0, g: 35.0/255, b: 1.0/255)
    let rgb = CGColorSpaceCreateDeviceRGB()
    func glow(_ alphas: [CGFloat], _ locs: [CGFloat]) -> CGGradient {
        CGGradient(colorsSpace: rgb,
                   colors: alphas.map { CGColor(red: orange.r, green: orange.g, blue: orange.b, alpha: $0) } as CFArray,
                   locations: locs)!
    }

    // Corona außen: weicher Lichtkranz, der vom Ring nach außen ausläuft
    cg.drawRadialGradient(glow([0.38, 0.10, 0], [0, 0.35, 1]),
                          startCenter: c, startRadius: ringR + ringW / 2,
                          endCenter: c, endRadius: ringR * 1.8,
                          options: [])
    // Corona innen: nur ein Hauch, damit der Ring nicht flach wirkt
    cg.drawRadialGradient(glow([0, 0.22], [0, 1]),
                          startCenter: c, startRadius: ringR * 0.6,
                          endCenter: c, endRadius: ringR - ringW / 2,
                          options: [])

    // Ring
    cg.setStrokeColor(CGColor(red: orange.r, green: orange.g, blue: orange.b, alpha: 1))
    cg.setLineWidth(ringW)
    cg.strokeEllipse(in: CGRect(x: c.x - ringR, y: c.y - ringR, width: ringR * 2, height: ringR * 2))

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(bitmapRep)
    return image
}
