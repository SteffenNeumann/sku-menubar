import SwiftUI
import AppKit
import Highlightr

// MARK: - Language detection

private func detectLanguage(for url: URL) -> String? {
    switch url.pathExtension.lowercased() {
    case "swift":                        return "swift"
    case "py":                           return "python"
    case "js":                           return "javascript"
    case "ts":                           return "typescript"
    case "jsx":                          return "javascript"
    case "tsx":                          return "typescript"
    case "go":                           return "go"
    case "rs":                           return "rust"
    case "rb":                           return "ruby"
    case "java":                         return "java"
    case "kt":                           return "kotlin"
    case "c", "h":                       return "c"
    case "cpp", "cc", "cxx", "hpp":      return "cpp"
    case "cs":                           return "csharp"
    case "php":                          return "php"
    case "sh", "bash", "zsh":           return "bash"
    case "html", "htm":                  return "html"
    case "css":                          return "css"
    case "scss", "sass":                 return "scss"
    case "json":                         return "json"
    case "yaml", "yml":                  return "yaml"
    case "toml":                         return "ini"
    case "xml", "plist":                 return "xml"
    case "sql":                          return "sql"
    case "md":                           return "markdown"
    case "dockerfile":                   return "dockerfile"
    case "makefile":                     return "makefile"
    default:                             return nil
    }
}

// MARK: - NSViewRepresentable wrapper

struct HighlightedCodeView: NSViewRepresentable {
    let code: String
    /// Explicit language override (e.g. "swift", "python"). Takes priority over fileURL detection.
    var language: String? = nil
    var fileURL: URL? = nil
    let isDark: Bool
    /// When true the view fills its container without a scroll view (for inline code blocks).
    var scrollable: Bool = true
    /// When true the text view is editable.
    var isEditable: Bool = false
    /// Called whenever the user changes the text (only when isEditable = true).
    var onTextChange: ((String) -> Void)? = nil

    private static let highlightr: Highlightr? = {
        // Guard against missing Highlightr_Highlightr.bundle.
        // NSBundle.module accessor checks Bundle.main.bundleURL first,
        // then a hardcoded .build/ path. If neither exists it calls fatalError.
        let bundleInApp = Bundle.main.bundleURL
            .appendingPathComponent("Highlightr_Highlightr.bundle").path
        let bundleInResources = (Bundle.main.resourceURL ?? Bundle.main.bundleURL)
            .appendingPathComponent("Highlightr_Highlightr.bundle").path
        let fm = FileManager.default
        guard fm.fileExists(atPath: bundleInApp) || fm.fileExists(atPath: bundleInResources) else {
            return nil
        }
        return Highlightr()
    }()

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onTextChange: ((String) -> Void)?
        init(onTextChange: ((String) -> Void)?) { self.onTextChange = onTextChange }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            onTextChange?(tv.string)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTextChange: onTextChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                        height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Update coordinator callback in case it changed
        context.coordinator.onTextChange = onTextChange
        // Don't overwrite what the user is currently typing
        if textView.string == code {
            textView.isEditable = isEditable
            return
        }

        let theme = isDark ? "atom-one-dark" : "xcode"
        let highlightr = Self.highlightr
        highlightr?.setTheme(to: theme)

        // Language priority: explicit > URL detection > auto
        let lang = language ?? fileURL.flatMap { detectLanguage(for: $0) }
        let attributed: NSAttributedString?

        if let lang, !lang.isEmpty {
            attributed = highlightr?.highlight(code, as: lang, fastRender: true)
        } else {
            attributed = highlightr?.highlight(code, fastRender: true)
        }

        if let attr = attributed {
            let mutable = NSMutableAttributedString(attributedString: attr)
            // Apply monospaced font at size 11
            let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            mutable.addAttribute(.font, value: font,
                                 range: NSRange(location: 0, length: mutable.length))
            textView.textStorage?.setAttributedString(mutable)
        } else {
            // Fallback: plain text
            let plain = NSAttributedString(
                string: code,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            textView.textStorage?.setAttributedString(plain)
        }

        // Match background to theme
        let bg: NSColor = isDark
            ? NSColor(red: 0.17, green: 0.18, blue: 0.21, alpha: 1)  // atom-one-dark bg
            : NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)  // xcode light bg
        textView.backgroundColor = bg
        scrollView.backgroundColor = bg
        scrollView.contentView.backgroundColor = bg
        textView.isEditable = isEditable
    }
}
