import SwiftUI
import AppKit

// MARK: - Markdown renderer with syntax-highlighted code blocks

struct MarkdownTextView: View {
    let text: String
    @Environment(\.appTheme) var theme
    @Environment(\.colorScheme) var colorScheme

    private var accentColor: Color {
        Color(red: theme.acR / 255, green: theme.acG / 255, blue: theme.acB / 255)
    }

    var body: some View {
        let segments = parseSegments(text)

        // Single-column layout: text and code blocks appear in order
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let t):
                    textSegmentView(t)
                case .code(let lang, let code):
                    codeBlock(language: lang, code: code)
                }
            }
        }
    }

    // MARK: - Block-level Markdown types

    private enum MarkdownBlock {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case bulletItem(indent: Int, text: String)
        case numberedItem(number: Int, text: String)
        case blockquote(text: String)
        case hr
    }

    // MARK: - Block parser

    private func parseMarkdownBlocks(_ raw: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var paraLines: [String] = []

        func flush() {
            let joined = paraLines.joined(separator: "\n")
            let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { result.append(.paragraph(text: trimmed)) }
            paraLines.removeAll()
        }

        for line in raw.components(separatedBy: "\n") {
            let tr = line.trimmingCharacters(in: .whitespaces)

            if tr.hasPrefix("### ") { flush(); result.append(.heading(level: 3, text: String(tr.dropFirst(4)))); continue }
            if tr.hasPrefix("## ")  { flush(); result.append(.heading(level: 2, text: String(tr.dropFirst(3)))); continue }
            if tr.hasPrefix("# ")   { flush(); result.append(.heading(level: 1, text: String(tr.dropFirst(2)))); continue }

            if (tr == "---" || tr == "***" || tr == "___") { flush(); result.append(.hr); continue }

            if tr.hasPrefix("> ") { flush(); result.append(.blockquote(text: String(tr.dropFirst(2)))); continue }
            if tr == ">"          { flush(); result.append(.blockquote(text: "")); continue }

            if tr.count >= 2 && (tr.hasPrefix("- ") || tr.hasPrefix("* ") || tr.hasPrefix("+ ")) {
                flush()
                let indent = line.prefix(while: { $0 == " " }).count / 2
                result.append(.bulletItem(indent: indent, text: String(tr.dropFirst(2))))
                continue
            }

            if let m = tr.range(of: "^[0-9]+\\. ", options: [.regularExpression]) {
                flush()
                let prefix = String(tr[..<m.upperBound])
                let numStr = prefix.components(separatedBy: ".").first ?? "1"
                let num = Int(numStr.trimmingCharacters(in: .whitespaces)) ?? 1
                result.append(.numberedItem(number: num, text: String(tr[m.upperBound...])))
                continue
            }

            if tr.isEmpty { flush(); continue }
            paraLines.append(line)
        }
        flush()
        return result
    }

    // MARK: - Block segment view

    @ViewBuilder
    private func textSegmentView(_ t: String) -> some View {
        let blocks = parseMarkdownBlocks(t)
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                markdownBlockView(block)
            }
        }
    }

    @ViewBuilder
    private func markdownBlockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineMarkdown(text)
                .font(.system(size: level == 1 ? 18 : level == 2 ? 15 : 13.5,
                               weight: level == 1 ? .bold : .semibold))
                .foregroundStyle(theme.primaryText)
                .padding(.top, level == 1 ? 6 : 2)
                .padding(.bottom, 1)

        case .paragraph(let text):
            inlineMarkdown(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.primaryText)
                .lineSpacing(2)

        case .bulletItem(let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.leading, CGFloat(indent) * 14)
                inlineMarkdown(text)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.primaryText)
            }

        case .numberedItem(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(number).")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(theme.tertiaryText)
                    .frame(minWidth: 20, alignment: .trailing)
                inlineMarkdown(text)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.primaryText)
            }

        case .blockquote(let text):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(accentColor.opacity(0.55))
                    .frame(width: 3)
                inlineMarkdown(text)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .background(accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            .clipShape(RoundedRectangle(cornerRadius: 4))

        case .hr:
            Rectangle()
                .fill(theme.cardBorder)
                .frame(maxWidth: .infinity, maxHeight: 1)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func inlineMarkdown(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed).textSelection(.enabled)
        } else {
            Text(text).textSelection(.enabled)
        }
    }

    // MARK: - Code block (syntax highlighted)

    @ViewBuilder
    private func codeBlock(language: String, code: String) -> some View {
        let isDark = !theme.isLight
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
