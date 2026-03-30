import SwiftUI
import AppKit

// MARK: - Markdown renderer with syntax-highlighted code blocks

struct MarkdownTextView: View {
    let text: String
    @Environment(\.appTheme) var theme
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let segments = parseSegments(text)
        let hasCode = segments.contains { if case .code = $0 { return true }; return false }

        if hasCode {
            // Two-column layout: text left, code blocks right
            HStack(alignment: .top, spacing: 0) {
                // Left: text segments only
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        if case .text(let t) = segment {
                            textSegmentView(t)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                // Divider
                Rectangle()
                    .fill(theme.cardBorder.opacity(0.6))
                    .frame(width: 0.5)
                    .padding(.horizontal, 8)

                // Right: code blocks only
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        if case .code(let lang, let code) = segment {
                            codeBlock(language: lang, code: code)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            // Single-column layout when no code
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if case .text(let t) = segment {
                        textSegmentView(t)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func textSegmentView(_ t: String) -> some View {
        // Convert single newlines to markdown hard line breaks (two spaces + \n)
        // so that \n in CLI output is rendered as a visual line break.
        let processed = t.replacingOccurrences(
            of: "(?<!\n)\n(?!\n)", with: "  \n", options: .regularExpression)
        if let attributed = try? AttributedString(markdown: processed,
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
    }

    // MARK: - Code block (syntax highlighted)

    @ViewBuilder
    private func codeBlock(language: String, code: String) -> some View {
        let isDark = colorScheme == .dark
        let trimmed = code.hasSuffix("\n") ? String(code.dropLast()) : code
        let lang = language.lowercased()

        if lang == "diff" || lang == "patch" {
            diffCodeBlock(code: trimmed, isDark: isDark)
        } else {
            regularCodeBlock(language: language, code: trimmed, isDark: isDark)
        }
    }

    private func regularCodeBlock(language: String, code: String, isDark: Bool) -> some View {
        let lineCount = code.components(separatedBy: "\n").count
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
                    NSPasteboard.general.setString(code, forType: .string)
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
                code: code,
                language: language.isEmpty ? nil : language,
                isDark: isDark
            )
            .frame(height: blockHeight)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
    }

    // MARK: - Diff code block (git-style red/green highlighting)

    private func diffCodeBlock(code: String, isDark: Bool) -> some View {
        let lines = code.components(separatedBy: "\n")
        let additions = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
        let deletions = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
        let blockHeight = min(CGFloat(lines.count) * 17 + 8, 380)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("diff")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.orange.opacity(0.85))
                Text("+\(additions)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.green)
                Text("-\(deletions)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.red)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(isDark ? Color.white.opacity(0.4) : Color.black.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isDark
                ? Color(red: 0.13, green: 0.14, blue: 0.16)
                : Color(red: 0.88, green: 0.88, blue: 0.90))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        diffLine(line, isDark: isDark)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: blockHeight)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
            isDark ? Color(white: 0.18) : Color(white: 0.82),
            lineWidth: 0.5
        ))
    }

    private func diffLine(_ line: String, isDark: Bool) -> some View {
        let isAdd    = line.hasPrefix("+") && !line.hasPrefix("+++")
        let isRemove = line.hasPrefix("-") && !line.hasPrefix("---")
        let isHunk   = line.hasPrefix("@@")
        let isMeta   = line.hasPrefix("diff") || line.hasPrefix("index")
                    || line.hasPrefix("---") || line.hasPrefix("+++")

        let bg: Color = isAdd    ? .green.opacity(isDark ? 0.18 : 0.12)
                      : isRemove ? .red.opacity(isDark ? 0.18 : 0.12)
                      : isHunk   ? Color(white: isDark ? 0.15 : 0.88)
                      : .clear
        let fg: Color = isAdd    ? .green
                      : isRemove ? .red
                      : isHunk   ? Color(red: 0.4, green: 0.6, blue: 0.95)
                      : isMeta   ? Color(white: isDark ? 0.5 : 0.55)
                      : isDark ? Color.white.opacity(0.85) : Color.black.opacity(0.8)

        return Text(line.isEmpty ? " " : line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 1.5)
            .background(bg)
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
