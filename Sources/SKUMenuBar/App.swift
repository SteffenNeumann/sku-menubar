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

    // ── Orange-Kreis #FF2301 mit leichter Corona ───────────────────────────
    let c = CGPoint(x: s/2, y: s/2)
    let discR = s * 0.17
    let orange = (r: 1.0, g: 35.0/255, b: 1.0/255)

    // Corona: weicher Lichtkranz, der vom Kreisrand nach außen ausläuft
    let coronaColors = [
        CGColor(red: orange.r, green: orange.g, blue: orange.b, alpha: 0.38),
        CGColor(red: orange.r, green: orange.g, blue: orange.b, alpha: 0.10),
        CGColor(red: orange.r, green: orange.g, blue: orange.b, alpha: 0.0)
    ]
    let coronaGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: coronaColors as CFArray,
                                locations: [0, 0.35, 1])!
    cg.drawRadialGradient(coronaGrad,
                          startCenter: c, startRadius: discR,
                          endCenter: c, endRadius: discR * 2.1,
                          options: [])

    // Kreis
    cg.setFillColor(CGColor(red: orange.r, green: orange.g, blue: orange.b, alpha: 1))
    cg.fillEllipse(in: CGRect(x: c.x - discR, y: c.y - discR, width: discR * 2, height: discR * 2))

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(bitmapRep)
    return image
}
