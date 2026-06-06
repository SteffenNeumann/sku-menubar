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
    case "bas", "cls", "frm", "vba", "vbs": return "vbscript"
    default:                             return nil
    }
}

// MARK: - Code text view with gutter + line highlight

/// NSTextView subclass that draws a line-number gutter and current-line highlight
/// entirely inside drawBackground — no NSRulerView needed, no layout side-effects.
final class CodeTextView: NSTextView {
    var isDark: Bool = true

    /// Called when the mouse hovers a different line (nil = mouse left).
    var onHoverLine: ((Int?) -> Void)?
    /// Line number highlighted by the live preview (orange tint).
    var hoveredLine: Int? { didSet { if hoveredLine != oldValue { needsDisplay = true } } }

    /// Ranges where a search-highlight background is currently applied (so we can clear it).
    var appliedSearchRanges: [NSRange] = []

    private var _lastHoveredLine: Int? = nil

    // Width of the line-number gutter (left of the text area).
    static let gutterWidth: CGFloat = 48

    // MARK: Mouse tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let line = lineAt(event: event)
        if line != _lastHoveredLine {
            _lastHoveredLine = line
            onHoverLine?(line)
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if _lastHoveredLine != nil {
            _lastHoveredLine = nil
            onHoverLine?(nil)
        }
    }

    // MARK: Plain-text copy/paste

    override func copy(_ sender: Any?) {
        let sel = selectedRange()
        let text: String
        if sel.length > 0, let s = textStorage?.string {
            text = (s as NSString).substring(with: sel)
        } else {
            text = string
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        guard let plain = pb.string(forType: .string) else { return }
        let range = selectedRange()
        if shouldChangeText(in: range, replacementString: plain) {
            textStorage?.replaceCharacters(in: range, with: plain)
            didChangeText()
        }
    }

    private func lineAt(event: NSEvent) -> Int? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let pt = convert(event.locationInWindow, from: nil)
        let textPt = NSPoint(x: pt.x - textContainerOrigin.x,
                             y: pt.y - textContainerOrigin.y)
        var frac: CGFloat = 0
        let charIdx = lm.characterIndex(for: textPt, in: tc,
                                        fractionOfDistanceBetweenInsertionPoints: &frac)
        if charIdx >= string.count { return nil }
        var line = 1
        (string as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: charIdx),
            options: [.byLines, .substringNotRequired]
        ) { _, _, _, _ in line += 1 }
        return line
    }

    // MARK: drawBackground

    override func drawBackground(in rect: NSRect) {
        // 1. Let AppKit fill the main code background.
        super.drawBackground(in: rect)

        // 2. Draw current-line highlight (full width so it shows under gutter too).
        drawCurrentLineHighlight(in: rect)

        // 2b. Draw preview-hover line highlight.
        drawHoveredLineHighlight(in: rect)

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

    /// Draws an orange glow on the line that the live preview is currently hovering.
    private func drawHoveredLineHighlight(in rect: NSRect) {
        guard let targetLine = hoveredLine,
              let lm = layoutManager,
              let tc = textContainer,
              lm.numberOfGlyphs > 0,
              !string.isEmpty else { return }

        // Find the char range of the target line.
        var currentLine = 1
        var targetRange: NSRange? = nil
        (string as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: (string as NSString).length),
            options: [.byLines, .substringNotRequired]
        ) { _, _, enclosing, stop in
            if currentLine == targetLine { targetRange = enclosing; stop.pointee = true }
            currentLine += 1
        }
        guard let charRange = targetRange, charRange.length > 0 else { return }

        let glyphRange = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        var lineRect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
        lineRect.origin.y += textContainerInset.height
        lineRect.origin.x  = bounds.minX
        lineRect.size.width = max(bounds.width, lineRect.maxX)

        guard lineRect.intersects(rect) else { return }

        let color: NSColor = isDark
            ? NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.14)
            : NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 0.11)
        color.setFill()
        lineRect.fill()
    }

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
            guard self != nil else { stop.pointee = true; return }

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
    /// Called when the mouse hovers over a different line (nil = mouse left view).
    var onHoverLine: ((Int?) -> Void)? = nil
    /// Line to highlight (orange) — driven by live preview hover.
    var hoveredLine: Int? = nil

    /// Search query — when non-empty, all case-insensitive matches are
    /// background-highlighted (yellow) and the current match (orange).
    var searchText: String = ""
    /// Index of the active match (scrolled into view, drawn in orange).
    var currentMatchIndex: Int = 0
    /// Reports the total number of matches whenever the text / search changes.
    var onMatchCountChange: ((Int) -> Void)? = nil

    private static let highlightr: Highlightr? = {
        let fm = FileManager.default
        let bundleName = "Highlightr_Highlightr.bundle"
        let candidates = [
            (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent(bundleName).path,
            Bundle.main.bundleURL.appendingPathComponent(bundleName).path,
        ]
        guard let bundlePath = candidates.first(where: { fm.fileExists(atPath: $0) }),
              let bundle = Bundle(path: bundlePath),
              let jsPath = bundle.path(forResource: "highlight.min", ofType: "js")
        else { return nil }
        return Highlightr(highlightPath: jsPath)
    }()

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onTextChange: ((String) -> Void)?
        var onHoverLine: ((Int?) -> Void)?

        /// Ausstehender Highlight-Auftrag — wird bei jedem updateNSView gecancelt und
        /// neu geplant (0.1s Debounce). Verhindert den Streaming-Hang:
        /// highlight() ruft JSCore auf (10–50ms). Bei 50 Tokens/s × 50ms = 2500ms/s
        /// main-thread-Blocking → SwiftUI-Transaction-Queue akkumuliert hunderte Einträge
        /// → nach Streaming-Ende verarbeitet flushTransactions() sie alle → 25s Hang.
        /// Mit 0.1s Debounce: 0 Aufrufe während Streaming, 1 Aufruf danach. (Fix 11)
        var pendingHighlightItem: DispatchWorkItem?

        init(onTextChange: ((String) -> Void)?, onHoverLine: ((Int?) -> Void)?) {
            self.onTextChange = onTextChange
            self.onHoverLine = onHoverLine
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            onTextChange?(tv.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // Retrigger drawBackground so the current-line highlight updates.
            (notification.object as? NSTextView)?.needsDisplay = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTextChange: onTextChange, onHoverLine: onHoverLine) }

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
        textView.allowsUndo       = true
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
        let coordinator = context.coordinator
        textView.onHoverLine = { line in coordinator.onHoverLine?(line) }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CodeTextView else { return }
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onHoverLine = onHoverLine
        textView.onHoverLine = { line in context.coordinator.onHoverLine?(line) }
        textView.hoveredLine = hoveredLine

        // Always keep isDark in sync.
        textView.isDark = isDark

        if textView.string == code {
            textView.isEditable = isEditable
            applySearchHighlights(in: textView)
            return
        }

        // FIX 11 — Debounce-Highlighting: verhindert den Streaming-Hang.
        //
        // PROBLEM: highlight() ruft JavaScript (JSCore) auf, was 10–50 ms dauert.
        // Beim Streaming trifft ein Token alle ~20 ms ein → updateNSView 50×/s.
        // 50 Aufrufe × 50 ms = 2500 ms Blocking pro Sekunde > 1000 ms verfügbar
        // → SwiftUI-Transaction-Queue akkumuliert hunderte Einträge
        // → nach Streaming-Ende verarbeitet flushTransactions() alle auf einmal
        // → App hängt für 10–30 Sekunden.
        //
        // LÖSUNG: highlight() erst 0.1 s nach letzter Code-Änderung aufrufen.
        // Während Streaming: 0 JS-Aufrufe (jedes Update cancelt den Timer).
        // Nach Streaming: genau 1 JS-Aufruf, 100 ms nach letztem Token.
        // Sofort: plain Text (Monospace, keine Farben) als visuelles Feedback.

        let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // 1. Sofort plain text setzen (kein JS, < 1 ms)
        let plain = NSAttributedString(
            string: code,
            attributes: [
                .font: codeFont,
                .foregroundColor: NSColor.labelColor
            ]
        )
        textView.textStorage?.setAttributedString(plain)
        textView.undoManager?.removeAllActions()

        // Background schon mal setzen (kein JS nötig)
        let bg: NSColor = isDark
            ? NSColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1)
            : NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        textView.backgroundColor = bg
        scrollView.backgroundColor = bg
        scrollView.contentView.backgroundColor = bg
        textView.isEditable = isEditable
        applySearchHighlights(in: textView)

        // 2. Vorherigen Highlight-Auftrag abbrechen und neuen einplanen (0.1 s Debounce)
        context.coordinator.pendingHighlightItem?.cancel()

        let capturedCode  = code
        let capturedLang  = language ?? fileURL.flatMap { detectLanguage(for: $0) }
        let capturedTheme = isDark ? "atom-one-dark" : "xcode"
        let capturedDark  = isDark
        let tv = textView
        let sv = scrollView

        let item = DispatchWorkItem {
            // highlight() läuft auf dem main thread (JSContext ist main-thread-bound),
            // aber erst 0.1 s nach letzter Code-Änderung — kein Blocking mehr während Streaming.
            let highlightr = HighlightedCodeView.highlightr
            highlightr?.setTheme(to: capturedTheme)

            let attributed: NSAttributedString?
            if let lang = capturedLang, !lang.isEmpty {
                attributed = highlightr?.highlight(capturedCode, as: lang, fastRender: true)
            } else {
                attributed = highlightr?.highlight(capturedCode, fastRender: true)
            }

            if let attr = attributed {
                let mutable = NSMutableAttributedString(attributedString: attr)
                mutable.addAttribute(.font, value: codeFont,
                                     range: NSRange(location: 0, length: mutable.length))
                tv.textStorage?.setAttributedString(mutable)
            }
            // (kein else nötig — plain text ist schon gesetzt)

            // Nur Hintergrund nochmal setzen falls isDark geändert hat
            let bgFresh: NSColor = capturedDark
                ? NSColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1)
                : NSColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
            tv.backgroundColor = bgFresh
            sv.backgroundColor = bgFresh
            sv.contentView.backgroundColor = bgFresh

            // Defer one run-loop turn so SwiftUI commits the final frame before
            // we force a display.
            DispatchQueue.main.async {
                tv.layoutManager?.ensureLayout(for: tv.textContainer ?? NSTextContainer())
                tv.needsDisplay = true
                sv.needsDisplay = true
            }
        }

        context.coordinator.pendingHighlightItem = item
        // 0.1 s Debounce: während Streaming (20 ms/Token) feuert dieser Timer nie.
        // Nach dem letzten Token wartet er 100 ms und highlighted dann einmal.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    /// Removes any prior search-highlight backgrounds and applies the current
    /// `searchText` / `currentMatchIndex` to the given text view.
    private func applySearchHighlights(in textView: CodeTextView) {
        guard let storage = textView.textStorage else { return }
        let total = storage.length

        // Clear previously applied search backgrounds.
        for r in textView.appliedSearchRanges {
            let safe = NSRange(location: min(r.location, total),
                               length: min(r.length, max(0, total - min(r.location, total))))
            if safe.length > 0 { storage.removeAttribute(.backgroundColor, range: safe) }
        }
        textView.appliedSearchRanges = []

        guard !searchText.isEmpty, total > 0 else {
            // Nur dispachen wenn wirklich ein Callback registriert ist (spart GCD-Blöcke
            // in den vielen Chat-Code-Blöcken ohne Suchfunktion).
            if let cb = onMatchCountChange {
                DispatchQueue.main.async { cb(0) }
            }
            return
        }

        let ns = storage.string as NSString
        var ranges: [NSRange] = []
        var loc = 0
        while loc < ns.length {
            let r = ns.range(of: searchText,
                             options: .caseInsensitive,
                             range: NSRange(location: loc, length: ns.length - loc))
            if r.location == NSNotFound { break }
            ranges.append(r)
            loc = r.location + max(1, r.length)
        }

        let yellow = NSColor.systemYellow.withAlphaComponent(0.45)
        let orange = NSColor.systemOrange.withAlphaComponent(0.85)
        for r in ranges {
            storage.addAttribute(.backgroundColor, value: yellow, range: r)
        }
        if !ranges.isEmpty {
            let idx = min(max(0, currentMatchIndex), ranges.count - 1)
            let cur = ranges[idx]
            storage.addAttribute(.backgroundColor, value: orange, range: cur)
            textView.scrollRangeToVisible(cur)
        }
        textView.appliedSearchRanges = ranges

        let count = ranges.count
        let cb = onMatchCountChange
        DispatchQueue.main.async { cb?(count) }
    }
}
