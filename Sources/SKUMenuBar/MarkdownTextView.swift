import SwiftUI
import AppKit

// MARK: - Markdown renderer with syntax-highlighted code blocks

struct MarkdownTextView: View {
    let text: String
    @Environment(\.appTheme) var theme
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let segments = parseSegments(text)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let t):
                    if let attributed = try? AttributedString(markdown: t,
                        options: AttributedString.MarkdownParsingOptions(
                            interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributed)
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(theme.primaryText)
                            .textSelection(.enabled)
                    } else {
                        Text(t).font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(theme.primaryText)
                            .textSelection(.enabled)
                    }
                case .code(let lang, let code):
                    codeBlock(language: lang, code: code)
                }
            }
        }
    }

    // MARK: - Code block (syntax highlighted)

    private func codeBlock(language: String, code: String) -> some View {
        let isDark = colorScheme == .dark
        let trimmed = code.hasSuffix("\n") ? String(code.dropLast()) : code
        let lineCount = trimmed.components(separatedBy: "\n").count
        // ~17pt per line, capped at 380pt
        let blockHeight = min(CGFloat(lineCount) * 17 + 8, 380)

        return VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 6) {
                if !language.isEmpty {
                    Text(language.lowercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isDark
                            ? Color(red: 0.56, green: 0.74, blue: 0.98)
                            : Color(red: 0.2,  green: 0.4,  blue: 0.8))
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(trimmed, forType: .string)
                } label: {
                    Label("Kopieren", systemImage: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(isDark ? Color.white.opacity(0.45) : Color.black.opacity(0.4))
                }
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isDark
                ? Color(red: 0.13, green: 0.14, blue: 0.16)
                : Color(red: 0.88, green: 0.88, blue: 0.90))

            HighlightedCodeView(
                code: trimmed,
                language: language.isEmpty ? nil : language,
                isDark: isDark
            )
            .frame(height: blockHeight)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
    }

    // MARK: - Parse text/code segments

    enum TextSegment {
        case text(String)
        case code(language: String, code: String)
    }

    private func parseSegments(_ input: String) -> [TextSegment] {
        var segments: [TextSegment] = []
        var remaining = input
        let fence = "```"

        while !remaining.isEmpty {
            if let fenceRange = remaining.range(of: fence) {
                let before = String(remaining[..<fenceRange.lowerBound])
                if !before.isEmpty { segments.append(.text(before)) }

                let afterFence = String(remaining[fenceRange.upperBound...])
                let firstNewline = afterFence.firstIndex(of: "\n")
                let lang = firstNewline.map {
                    String(afterFence[..<$0]).trimmingCharacters(in: .whitespaces)
                } ?? ""
                let codeStart = firstNewline.map {
                    afterFence.index(after: $0)
                } ?? afterFence.startIndex
                let codeContent = String(afterFence[codeStart...])

                if let closingFence = codeContent.range(of: fence) {
                    let code = String(codeContent[..<closingFence.lowerBound])
                    segments.append(.code(language: lang, code: code))
                    remaining = String(codeContent[closingFence.upperBound...])
                } else {
                    segments.append(.text(fence + afterFence))
                    remaining = ""
                }
            } else {
                segments.append(.text(remaining))
                remaining = ""
            }
        }
        return segments
    }
}
