import SwiftUI
import AppKit

@main
struct SKUMenuBarApp: App {
    @StateObject private var state = AppState()
    @StateObject private var themeManager = ThemeManager()

    init() {
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

    // Dark navy gradient background (bottom → top in CG coords)
    let bgColors = [
        CGColor(red: 0.075, green: 0.063, blue: 0.165, alpha: 1), // top (dark purple-navy)
        CGColor(red: 0.047, green: 0.039, blue: 0.110, alpha: 1)  // bottom
    ]
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: bgColors as CFArray,
                            locations: [0, 1])!
    cg.drawLinearGradient(bgGrad,
                          start: CGPoint(x: s/2, y: s),
                          end: CGPoint(x: s/2, y: 0),
                          options: [])

    // ── Purple → Indigo badge ───────────────────────────────────────────────
    let badgeW = s * 0.58
    let badgeX = (s - badgeW) / 2
    let badgeY = s * 0.21
    let badgeR = badgeW * 0.28

    let badgePath = CGPath(roundedRect: CGRect(x: badgeX, y: badgeY, width: badgeW, height: badgeW),
                           cornerWidth: badgeR, cornerHeight: badgeR, transform: nil)
    cg.saveGState()
    cg.addPath(badgePath)
    cg.clip()

    let badgeColors = [
        CGColor(red: 0.427, green: 0.157, blue: 0.851, alpha: 1), // top: vivid purple
        CGColor(red: 0.263, green: 0.212, blue: 0.792, alpha: 1)  // bottom: indigo
    ]
    let badgeGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: badgeColors as CFArray,
                               locations: [0, 1])!
    cg.drawLinearGradient(badgeGrad,
                          start: CGPoint(x: s/2, y: badgeY + badgeW),
                          end: CGPoint(x: s/2, y: badgeY),
                          options: [])
    cg.restoreGState()

    // ── Sparkle icon ────────────────────────────────────────────────────────
    let cx = s / 2
    let cy = badgeY + badgeW / 2
    let arm  = s * 0.155
    let thin = s * 0.038

    cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

    // 4-pointed star arms (vertical + horizontal)
    for angleDeg in [90.0, 270.0, 0.0, 180.0] {
        let a = angleDeg * .pi / 180
        let pts: [CGPoint] = [
            CGPoint(x: cx + cos(a) * arm,          y: cy + sin(a) * arm),
            CGPoint(x: cx + cos(a + .pi/2) * thin, y: cy + sin(a + .pi/2) * thin),
            CGPoint(x: cx - cos(a) * arm * 0.15,   y: cy - sin(a) * arm * 0.15),
            CGPoint(x: cx + cos(a - .pi/2) * thin, y: cy + sin(a - .pi/2) * thin),
        ]
        cg.move(to: pts[0])
        pts[1...].forEach { cg.addLine(to: $0) }
        cg.closePath()
        cg.fillPath()
    }

    // Centre dot
    let cr = s * 0.030
    cg.fillEllipse(in: CGRect(x: cx - cr, y: cy - cr, width: cr*2, height: cr*2))

    // 4 small diagonal dots
    cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.82))
    let dotR = s * 0.022
    let dotD = s * 0.108
    for angleDeg in [45.0, 135.0, 225.0, 315.0] {
        let a = angleDeg * .pi / 180
        let dx = cx + cos(a) * dotD
        let dy = cy + sin(a) * dotD
        cg.fillEllipse(in: CGRect(x: dx - dotR, y: dy - dotR, width: dotR*2, height: dotR*2))
    }

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(bitmapRep)
    return image
}
