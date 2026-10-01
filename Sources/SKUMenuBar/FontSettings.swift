import SwiftUI
import CoreText

// MARK: - Font Choice

enum AppFontChoice: String, CaseIterable {
    case system        = "system"
    case jetbrainsMono = "jetbrains-mono"

    var displayName: String {
        switch self {
        case .system:        return "SF Pro / SF Mono"
        case .jetbrainsMono: return "JetBrains Mono"
        }
    }
}

// MARK: - AppStorage Keys

enum FontKey {
    static let chatText  = "appFont_chatText"
    static let codeBlock = "appFont_codeBlock"
}

// MARK: - Font Manager

enum FontManager {

    // Im .app liegt das Bundle unter Contents/Resources (nur dort ist es mitsigniert).
    // Bundle.module sucht nur in der App-Wurzel → erst Resources prüfen, dann Fallback.
    private static let resourceBundle: Bundle = {
        let name = "SKUMenuBar_myClaude.bundle"
        for case let url? in [Bundle.main.resourceURL?.appendingPathComponent(name),
                              Bundle.main.bundleURL.appendingPathComponent(name)] {
            if let bundle = Bundle(url: url) { return bundle }
        }
        return Bundle.module
    }()

    static func registerBundledFonts() {
        let names = [
            "JetBrainsMono-Regular",
            "JetBrainsMono-Bold",
            "JetBrainsMono-Italic",
            "JetBrainsMono-BoldItalic"
        ]
        for name in names {
            // SPM .process() places files flat in the bundle resources
            guard let url = resourceBundle.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // SwiftUI Font for prose text
    static func swiftUIFont(choice: AppFontChoice, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch choice {
        case .system:
            return .system(size: size, weight: weight)
        case .jetbrainsMono:
            let postScript = weight == .bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Regular"
            return .custom(postScript, size: size)
        }
    }

    // NSFont for AppKit (HighlightedCodeView)
    static func nsFont(choice: AppFontChoice, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        switch choice {
        case .system:
            let candidate = (NSFont.monospacedSystemFont(ofSize: size, weight: weight) as AnyObject) as? NSFont
            return candidate
                ?? NSFont(name: "Menlo", size: size)
                ?? NSFont(name: "Monaco", size: size)
                ?? NSFont.systemFont(ofSize: size)
        case .jetbrainsMono:
            let name = weight == .bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Regular"
            return NSFont(name: name, size: size)
                ?? (NSFont.monospacedSystemFont(ofSize: size, weight: weight) as AnyObject as? NSFont)
                ?? NSFont(name: "Menlo", size: size)
                ?? NSFont.systemFont(ofSize: size)
        }
    }
}
