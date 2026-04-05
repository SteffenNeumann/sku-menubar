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

// MARK: - Code text view with gutter + line highlight

/// NSTextView subclass that draws a line-number gutter and current-line highlight
/// entirely inside drawBackground — no NSRulerView needed, no layout side-effects.
final class CodeTextView: NSTextView {
    var isDark: Bool = true

    // Width of the line-number gutter (left of the text area).
    static let gutterWidth: CGFloat = 48

    // MARK: drawBackground

    override func drawBackground(in rect: NSRect) {
        // 1. Let AppKit fill the main code background.
        super.drawBackground(in: rect)

        // 2. Draw current-line highlight (full width so it shows under gutter too).
        drawCurrentLineHighlight(in: rect)

        // 3. Draw gutter background (solid, on top of highlight in gutter area).
        let gutterRect = NSRect(x: bounds.minX, y: rect.minY,
                                width: Self.gutterWidth, height: rect.height)
        if gutterRect.intersects(rect) {
            let gutterBg: NSColor = isDark
                ? NSColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1)
                : NSColor(red: 0.91, green: 0.91, blue: 0.92, alpha: 1)
            gutterBg.setFill()
            gutterRect.fill()
        }

        // 4. Separator between gutter and code.
        let sepColor: NSColor = isDark
            ? NSColor(white: 0.20, alpha: 1)
            : NSColor(white: 0.74, alpha: 1)
        sepColor.setFill()
        NSRect(x: Self.gutterWidth - 0.5, y: rect.minY, width: 0.5, height: rect.height).fill()

        // 5. Draw line numbers.
        drawLineNumbers(in: rect)
    }

    // MARK: Private helpers

    private func drawCurrentLineHighlight(in rect: NSRect) {
        guard let lm = layoutManager,
              lm.numberOfGlyphs > 0,
              !string.isEmpty else { return }
        guard let selRange = selectedRanges.first as? NSRange,
              selRange.length == 0 else { return }

        let safeChar  = min(selRange.location, max(0, string.count - 1))
        let glyphIdx  = lm.glyphIndexForCharacter(at: safeChar)
        let safeGlyph = min(glyphIdx, lm.numberOfGlyphs - 1)

        var lineRect = lm.lineFragmentRect(forGlyphAt: safeGlyph, effectiveRange: nil)
        lineRect.origin.y    += textContainerInset.height
        lineRect.origin.x     = bounds.minX
        lineRect.size.width   = max(bounds.width, lineRect.maxX)

        guard lineRect.intersects(rect) else { return }

        let color: NSColor = isDark
            ? NSColor(white: 1, alpha: 0.055)
            : NSColor(white: 0, alpha: 0.045)
        color.setFill()
        lineRect.fill()
    }

    private func drawLineNumbers(in rect: NSRect) {
        guard let lm = layoutManager,
              let tc = textContainer,
              lm.numberOfGlyphs > 0 else { return }

        let lineFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .light)
        let numColor: NSColor = isDark
            ? NSColor(white: 0.40, alpha: 1)
            : NSColor(white: 0.50, alpha: 1)
        let attrs: [NSAttributedString.Key: Any] = [.font: lineFont, .foregroundColor: numColor]

        let text  = string as NSString
        let inset = textContainerInset

        // Determine which character range is visible.
        let glyphRange = lm.glyphRange(forBoundingRect: rect, in: tc)
        var charRange  = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Count lines before the visible range.
        var lineNum = 1
        if charRange.location > 0 {
            text.enumerateSubstrings(
                in: NSRange(location: 0, length: charRange.location),
                options: [.byLines, .substringNotRequired]
            ) { _, _, _, _ in lineNum += 1 }
        }

        let maxLen = text.length
        guard charRange.location < maxLen else { return }
        charRange.length = min(charRange.length, maxLen - charRange.location)

        text.enumerateSubstrings(in: charRange, options: [.byLines, .substringNotRequired]) { [weak self] _, _, enclosing, stop in
            guard let self = self else { stop.pointee = true; return }

            let gi  = lm.glyphIndexForCharacter(at: enclosing.location)
            var lfr = lm.lineFragmentRect(forGlyphAt: gi, effectiveRange: nil)
            lfr.origin.y += inset.height

            if lfr.minY > rect.maxY + 2 { stop.pointee = true; return }
            if lfr.maxY < rect.minY - 2  { lineNum += 1; return }

            let label = "\(lineNum)" as NSString
            let size  = label.size(withAttributes: attrs)
            let x     = Self.gutterWidth - size.width - 8
            let y     = lfr.minY + (lfr.height - size.height) / 2
            label.draw(at: NSPoint(x: max(2, x), y: y), withAttributes: attrs)
            lineNum += 1
        }
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

        func textViewDidChangeSelection(_ notification: Notification) {
            // Retrigger drawBackground so the current-line highlight updates.
            (notification.object as? NSTextView)?.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTextChange: onTextChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers    = true
        scrollView.borderType            = .noBorder
        scrollView.backgroundColor       = .clear

        let textView = CodeTextView()
        textView.isDark           = isDark
        textView.isEditable       = false
        textView.isSelectable     = true
        textView.backgroundColor  = .clear
        textView.drawsBackground  = true   // must be true so drawBackground is called
        textView.isRichText       = true
        textView.isVerticallyResizable   = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask        = [.width]
        textView.textContainer?.widthTracksTextView  = false
        textView.textContainer?.containerSize = CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                       height: CGFloat.greatestFiniteMagnitude)
        // Left inset = gutter width + code margin; top/bottom = comfortable padding.
        textView.textContainerInset = NSSize(width: CodeTextView.gutterWidth + 10, height: 14)
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        context.coordinator.onTextChange = onTextChange

        // Always keep isDark in sync.
        textView.isDark = isDark

        if textView.string == code {
            textView.isEditable = isEditable
            return
        }

        let theme = isDark ? "atom-one-dark" : "xcode"
        let highlightr = Self.highlightr
        highlightr?.setTheme(to: theme)

        let lang = language ?? fileURL.flatMap { detectLanguage(for: $0) }
        let attributed: NSAttributedString?

        if let lang, !lang.isEmpty {
            attributed = highlightr?.highlight(code, as: lang, fastRender: true)
        } else {
            attributed = highlightr?.highlight(code, fastRender: true)
        }

        let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        if let attr = attributed {
            let mutable = NSMutableAttributedString(attributedString: attr)
            mutable.addAttribute(.font, value: codeFont,
                                 range: NSRange(location: 0, length: mutable.length))
            textView.textStorage?.setAttributedString(mutable)
        } else {
            let plain = NSAttributedString(
                string: code,
                attributes: [
                    .font: codeFont,
                    .foregroundColor: NSColor.labelColor
                ]
            )
            textView.textStorage?.setAttributedString(plain)
        }

        // Slightly darker background for better contrast vs the tree panel.
        let bg: NSColor = isDark
            ? NSColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1)
            : NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        textView.backgroundColor = bg
        scrollView.backgroundColor = bg
        scrollView.contentView.backgroundColor = bg

        textView.isEditable = isEditable
    }
}
