import SwiftUI
import AppKit

// MARK: - Review Mode

enum ReviewMode: String, CaseIterable, Identifiable {
    case general      = "Allgemein"
    case security     = "Sicherheit"
    case performance  = "Performance"
    case refactoring  = "Refactoring"
    case tests        = "Tests generieren"
    case explain      = "Erklären"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general:     return "doc.text.magnifyingglass"
        case .security:    return "shield.lefthalf.filled"
        case .performance: return "gauge.open.with.lines.needle.33percent"
        case .refactoring: return "arrow.triangle.2.circlepath"
        case .tests:       return "testtube.2"
        case .explain:     return "lightbulb.fill"
        }
    }

    var color: Color {
        switch self {
        case .general:     return .blue
        case .security:    return .red
        case .performance: return .orange
        case .refactoring: return .purple
        case .tests:       return .green
        case .explain:     return .yellow
        }
    }

    /// Foreground color for the active pill — dark text on light colors (yellow), white on dark colors.
    var activeForeground: Color {
        switch self {
        case .explain: return Color.black.opacity(0.75)
        default:       return .white
        }
    }

    var prompt: String {
        switch self {
        case .general:
            return "Please review the following code. Identify bugs, code quality issues, and suggest concrete improvements. Be specific and actionable."
        case .security:
            return "Please perform a security review of the following code. Look for vulnerabilities like injection risks, authentication issues, insecure data handling, exposed secrets, and other security concerns. Rate severity (High/Medium/Low) for each finding."
        case .performance:
            return "Please analyze the following code for performance issues. Identify inefficiencies, unnecessary computations, memory leaks, blocking operations, and suggest concrete optimizations."
        case .refactoring:
            return "Please suggest refactoring improvements for the following code. Focus on clean code principles, DRY, SOLID, reducing complexity, improving readability and maintainability. Show concrete before/after examples."
        case .tests:
            return "Please generate comprehensive unit tests for the following code. Cover happy paths, edge cases, and error scenarios. Use the appropriate testing framework for the language."
        case .explain:
            return "Please explain the following code in detail. Describe what it does, how it works, the design decisions made, and any non-obvious aspects."
        }
    }
}

// MARK: - File Tree Node

struct FileNode: Identifiable {
    let id = UUID()
    let url: URL
    var children: [FileNode]?
    var isExpanded: Bool = true

    var name: String { url.lastPathComponent }
    var isDirectory: Bool { children != nil }
    var depth: Int = 0

    var icon: String {
        if isDirectory { return "folder.fill" }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift":           return "swift"
        case "py":              return "chevron.left.forwardslash.chevron.right"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "json", "yaml", "yml", "toml": return "doc.text"
        case "md":              return "doc.richtext"
        case "sh", "bash", "zsh": return "terminal"
        case "html", "css", "scss": return "globe"
        case "go", "rs", "rb", "java", "kt", "c", "cpp", "h": return "chevron.left.forwardslash.chevron.right"
        default:                return "doc"
        }
    }

    var iconColor: Color {
        if isDirectory { return .blue }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "swift":           return .orange
        case "py":              return .yellow
        case "js", "jsx":       return Color(red: 0.97, green: 0.80, blue: 0.15)
        case "ts", "tsx":       return .blue
        case "json":            return .green
        case "md":              return .secondary
        case "go":              return .cyan
        case "rs":              return .orange
        default:                return .secondary
        }
    }
}

// MARK: - Main View

struct CodeReviewView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedDirectory: URL?
    @State private var fileTree: [FileNode] = []
    @State private var selectedFiles: Set<URL> = []
    @State private var reviewMode: ReviewMode = .general
    @State private var selectedModel: String = "claude-sonnet-4-6"
    @State private var customPrompt: String = ""
    @State private var useCustomPrompt: Bool = false
    @State private var reviewOutput: String = ""
    @State private var isReviewing: Bool = false
    @State private var errorMessage: String?
    @State private var inputTokens: Int = 0
    @State private var outputTokens: Int = 0
    @State private var costUsd: Double = 0
    @State private var showFilePanel: Bool = true
    @State private var previewFile: URL?
    @State private var previewContent: String = ""
    @State private var isApplying: Bool = false
    @State private var showApplySheet: Bool = false
    @State private var pendingAppliedFiles: [(url: URL, newContent: String)] = []
    @State private var applyError: String?
    @State private var applySuccess: Bool = false

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private let models = ["claude-sonnet-4-6", "claude-opus-4-6", "claude-haiku-4-5"]

    var body: some View {
        VStack(spacing: 0) {
            codeReviewHeader

            HSplitView {
                // Left: File picker + tree (collapsible)
                if showFilePanel {
                    leftPanel
                        .frame(minWidth: 160, idealWidth: 240, maxWidth: 400, maxHeight: .infinity)
                }

                // Right: Config + output
                rightPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                theme.cardBorder.opacity(0.5).frame(height: 0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await state.agentService.loadAgents()
        }
    }

    // MARK: - Unified Header

    private var codeReviewHeader: some View {
        HStack(spacing: 0) {
            if showFilePanel {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(accentColor)
                    Text("Dateien")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                    Button { pickDirectory() } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Verzeichnis öffnen")
                }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .frame(minWidth: 160, idealWidth: 240, maxWidth: 400)

                Rectangle().fill(theme.cardBorder).frame(width: 0.5)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass.source.code")
                    .font(.system(size: 12))
                    .foregroundStyle(accentColor)
                Text("Code Review")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Rectangle().fill(theme.cardBorder).frame(width: 0.5, height: 16)

                Menu {
                    ForEach(models, id: \.self) { m in
                        Button(m) { selectedModel = m }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(selectedModel.replacingOccurrences(of: "claude-", with: ""))
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.cardBorder, lineWidth: 0.5))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Toggle(isOn: $useCustomPrompt) {
                    Text("Eigener Prompt")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showFilePanel.toggle() }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 11))
                            .foregroundStyle(showFilePanel ? theme.secondaryText : accentColor)
                    }
                    .buttonStyle(.plain)
                    .help(showFilePanel ? "Dateien ausblenden" : "Dateien einblenden")

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { state.hideSidebar.toggle() }
                    } label: {
                        Image(systemName: "sidebar.squares.left")
                            .font(.system(size: 11))
                            .foregroundStyle(state.hideSidebar ? accentColor : theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help(state.hideSidebar ? "Sidebar einblenden" : "Sidebar ausblenden")
                }

                if !reviewOutput.isEmpty {
                    Button {
                        reviewOutput = ""
                        inputTokens = 0
                        outputTokens = 0
                        costUsd = 0
                        errorMessage = nil
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Ergebnis löschen")
                }

                Button { startReview() } label: {
                    HStack(spacing: 5) {
                        if isReviewing {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.mini)
                                .tint(.white)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 10))
                        }
                        Text(isReviewing ? "Analysiere…" : "Review starten")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(canReview ? .white : theme.tertiaryText)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(
                        canReview
                            ? LinearGradient(colors: [accentColor, accentColor.opacity(0.8)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [theme.cardBorder, theme.cardBorder],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 7)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canReview || isReviewing)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
        }
        .background(theme.windowBg)
    }

    // MARK: - Left panel

    private var leftPanel: some View {
        VStack(spacing: 0) {
            if fileTree.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(theme.tertiaryText)
                    Text("Verzeichnis öffnen")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                    Button("Auswählen…") { pickDirectory() }
                        .buttonStyle(.borderedProminent)
                        .tint(accentColor)
                        .controlSize(.small)
                }
                Spacer()
            } else {
                // Selected dir label
                if let dir = selectedDirectory {
                    HStack(spacing: 5) {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(accentColor)
                        Text(dir.lastPathComponent)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                        Spacer()
                        Text("\(selectedFiles.count) ausgewählt")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(0.06))
                }

                // File tree
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(flattenedTree(fileTree)) { node in
                            fileRow(node)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Rectangle().fill(theme.cardBorder).frame(height: 0.5)

                // Select all / clear
                HStack(spacing: 8) {
                    Button("Alle") { selectAllFiles(in: fileTree) }
                        .font(.system(size: 10))
                        .foregroundStyle(accentColor)
                        .buttonStyle(.plain)
                    Button("Keine") { selectedFiles.removeAll() }
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                        .buttonStyle(.plain)
                    Spacer()
                    let totalKB = estimatedSizeKB()
                    Text("~\(totalKB) KB")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    private func fileRow(_ node: FileNode) -> some View {
        let isSelected = selectedFiles.contains(node.url)
        let indent = CGFloat(node.depth) * 14

        return Button {
            if node.isDirectory {
                // toggle all files in folder
                toggleDirectory(node)
            } else {
                if isSelected {
                    selectedFiles.remove(node.url)
                } else {
                    selectedFiles.insert(node.url)
                }
                loadPreview(node.url)
            }
        } label: {
            HStack(spacing: 5) {
                // Indent
                Color.clear.frame(width: indent, height: 1)

                // Checkbox (files only)
                if !node.isDirectory {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? accentColor : theme.tertiaryText)
                }

                Image(systemName: node.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(node.iconColor)
                    .frame(width: 14)

                Text(node.name)
                    .font(.system(size: 11, weight: node.isDirectory ? .medium : .regular))
                    .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                isSelected && !node.isDirectory
                    ? accentColor.opacity(0.1)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            // Review mode pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ReviewMode.allCases) { mode in
                        modePill(mode)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .background(theme.cardBg.opacity(0.3))

            Rectangle().fill(theme.cardBorder).frame(height: 0.5)

            // Custom prompt toggle
            if useCustomPrompt {
                customPromptField
                Rectangle().fill(theme.cardBorder).frame(height: 0.5)
            }

            // Main content: source viewer left + review output right
            HSplitView {
                sourceViewerPanel
                    .frame(minWidth: 200, idealWidth: 400, maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 0) {
                    if reviewOutput.isEmpty && !isReviewing {
                        reviewPlaceholder
                    } else {
                        reviewOutputArea
                    }
                }
                .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Stats footer
            if outputTokens > 0 {
                statsFooter
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var reviewToolbar: some View {
        EmptyView()
    }

    private var canReview: Bool {
        !selectedFiles.isEmpty && !isReviewing
    }

    private func modePill(_ mode: ReviewMode) -> some View {
        let isActive = reviewMode == mode
        return Button { reviewMode = mode } label: {
            HStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? mode.activeForeground : mode.color)
                Text(mode.rawValue)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? mode.activeForeground : theme.secondaryText)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isActive ? mode.color : theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(isActive ? Color.clear : theme.cardBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var customPromptField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Eigener Review-Prompt")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
            TextEditor(text: $customPrompt)
                .font(.system(size: 11))
                .foregroundStyle(theme.primaryText)
                .scrollContentBackground(.hidden)
                .background(theme.cardBg)
                .frame(height: 60)
                .padding(6)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var reviewPlaceholder: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.08))
                    .frame(width: 64, height: 64)
                Image(systemName: "magnifyingglass.source.code")
                    .font(.system(size: 28))
                    .foregroundStyle(accentColor.opacity(0.6))
            }
            VStack(spacing: 6) {
                Text("Bereit für Code Review")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text(selectedFiles.isEmpty
                     ? "Wähle Dateien links aus, dann klicke \"Review starten\""
                     : "\(selectedFiles.count) Datei(en) ausgewählt – Modus wählen und starten")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)
                    .multilineTextAlignment(.center)
            }

            if !selectedFiles.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(selectedFiles.prefix(4)), id: \.self) { url in
                        Text(url.lastPathComponent)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    }
                    if selectedFiles.count > 4 {
                        Text("+\(selectedFiles.count - 4) mehr")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var reviewOutputArea: some View {
        VStack(spacing: 0) {
            if let err = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.red.opacity(0.08))
            }

            // Apply toolbar (only after review completed)
            if !isReviewing && !reviewOutput.isEmpty {
                HStack(spacing: 8) {
                    if applySuccess {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                        Text("Änderungen gespeichert")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                    } else if let err = applyError {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        applyError = nil
                        applySuccess = false
                        applyReview()
                    } label: {
                        HStack(spacing: 5) {
                            if isApplying {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.mini)
                                    .tint(.white)
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 10))
                            }
                            Text(isApplying ? "Wird umgesetzt…" : "Vorschläge umsetzen")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(
                            LinearGradient(colors: [.purple, .purple.opacity(0.8)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isApplying)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(theme.cardBg.opacity(0.5))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.cardBorder).frame(height: 0.5)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        MarkdownTextView(text: reviewOutput)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .onChange(of: reviewOutput) {
                    if isReviewing {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .sheet(isPresented: $showApplySheet) {
            applyConfirmationSheet
        }
    }

    private var applyConfirmationSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16))
                    .foregroundStyle(.purple)
                Text("Vorschläge umsetzen")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("\(pendingAppliedFiles.count) Datei(en)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(16)

            Rectangle().fill(theme.cardBorder).frame(height: 0.5)

            Text("Die folgenden Dateien werden überschrieben:")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(pendingAppliedFiles, id: \.url) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.badge.arrow.up")
                                .font(.system(size: 11))
                                .foregroundStyle(.purple)
                            Text(item.url.lastPathComponent)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(theme.primaryText)
                            Spacer()
                            let lines = item.newContent.components(separatedBy: "\n").count
                            Text("\(lines) Zeilen")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 200)

            Rectangle().fill(theme.cardBorder).frame(height: 0.5)
                .padding(.top, 8)

            HStack(spacing: 10) {
                Spacer()
                Button("Abbrechen") {
                    showApplySheet = false
                    pendingAppliedFiles = []
                }
                .keyboardShortcut(.escape)
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText)

                Button("Dateien überschreiben") {
                    commitAppliedFiles()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
            .padding(16)
        }
        .frame(width: 420)
        .background(theme.windowBg)
    }

    private func statChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(color.opacity(0.85))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Source Viewer Panel

    private var sourceViewerPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(accentColor)
                if let f = previewFile {
                    Text(f.lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text(f.deletingLastPathComponent().lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                } else {
                    Text("Quellcode")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                if previewFile != nil {
                    let lineCount = previewContent.components(separatedBy: "\n").count
                    Text("\(lineCount) Zeilen")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.cardBg.opacity(0.4))

            Rectangle().fill(theme.cardBorder).frame(height: 0.5)

            if previewFile == nil {
                VStack(spacing: 10) {
                    Image(systemName: "cursortext")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.tertiaryText.opacity(0.5))
                    Text("Datei anklicken")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                    Text("Klicke eine Datei in der Liste\num den Quellcode anzuzeigen")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HighlightedCodeView(
                    code: previewContent,
                    fileURL: previewFile,
                    isDark: !theme.isLight
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func loadPreview(_ url: URL) {
        previewFile = url
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            previewContent = content
        } else {
            previewContent = "(Datei konnte nicht gelesen werden)"
        }
    }

    // MARK: - Stats Footer

    private var statsFooter: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 9))
                .foregroundStyle(theme.tertiaryText)

            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.blue)
                Text("\(formatTokens(inputTokens)) Input")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                Text("\(formatTokens(outputTokens)) Output")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
            }

            if costUsd > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(accentColor)
                    Text(String(format: "$%.5f", costUsd))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                }
            }

            Spacer()

            Text(selectedModel.replacingOccurrences(of: "claude-", with: ""))
                .font(.system(size: 9))
                .foregroundStyle(theme.tertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(theme.cardBg.opacity(0.5))
        .overlay(alignment: .top) {
            Rectangle().fill(theme.cardBorder).frame(height: 0.5)
        }
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n)/1_000_000)
        : n >= 1_000   ? String(format: "%.0fK", Double(n)/1_000)
        : "\(n)"
    }

    // MARK: - Actions

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Öffnen"
        if panel.runModal() == .OK, let url = panel.url {
            selectedDirectory = url
            selectedFiles = []
            fileTree = buildFileTree(at: url, depth: 0)
        }
    }

    private func startReview() {
        guard !selectedFiles.isEmpty, !isReviewing else { return }

        isReviewing = true
        reviewOutput = ""
        errorMessage = nil
        inputTokens = 0
        outputTokens = 0
        costUsd = 0

        let prompt = useCustomPrompt && !customPrompt.isEmpty
            ? customPrompt
            : reviewMode.prompt

        Task {
            // Build file content string
            var fileContent = ""
            let sortedFiles = selectedFiles.sorted { $0.path < $1.path }
            for url in sortedFiles {
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    let ext = url.pathExtension
                    fileContent += "### \(url.lastPathComponent)\n```\(ext)\n\(text)\n```\n\n"
                }
            }

            let fullPrompt = """
            \(prompt)

            \(fileContent)
            """

            let stream = state.cliService.send(
                message: fullPrompt,
                sessionId: nil,
                agentName: nil,
                model: selectedModel,
                workingDirectory: selectedDirectory?.path
            )

            do {
                for try await event in stream {
                    await MainActor.run {
                        switch event.type {
                        case "assistant":
                            if let content = event.message?.content {
                                for block in content where block.type == "text" {
                                    if let t = block.text, !t.isEmpty {
                                        reviewOutput += t
                                    }
                                }
                            }
                        case "result":
                            inputTokens  = event.inputTokens ?? 0
                            outputTokens = event.outputTokens ?? 0
                            costUsd      = event.costUsd ?? 0
                        default: break
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                isReviewing = false
            }
        }
    }

    // MARK: - Apply Review

    private func applyReview() {
        guard !selectedFiles.isEmpty, !reviewOutput.isEmpty else { return }
        isApplying = true

        Task {
            // Build original file contents
            var fileContent = ""
            let sortedFiles = selectedFiles.sorted { $0.path < $1.path }
            for url in sortedFiles {
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    let ext = url.pathExtension
                    fileContent += "### \(url.lastPathComponent)\n```\(ext)\n\(text)\n```\n\n"
                }
            }

            let applyPrompt = """
            Below are the original source files and a code review with suggested improvements.
            Apply ALL the suggested changes from the review to each file.
            Return ONLY the complete modified file contents — no explanations, no commentary.
            Use this exact format for each file:
            ### <filename>
            ```<extension>
            <complete modified code>
            ```

            --- ORIGINAL FILES ---
            \(fileContent)
            --- REVIEW ---
            \(reviewOutput)
            """

            let stream = state.cliService.send(
                message: applyPrompt,
                sessionId: nil,
                agentName: nil,
                model: selectedModel,
                workingDirectory: selectedDirectory?.path
            )

            var applyOutput = ""
            do {
                for try await event in stream {
                    if event.type == "assistant",
                       let content = event.message?.content {
                        for block in content where block.type == "text" {
                            if let t = block.text { applyOutput += t }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    applyError = error.localizedDescription
                    isApplying = false
                }
                return
            }

            // Parse returned files
            let parsed = parseAppliedFiles(from: applyOutput, knownFiles: sortedFiles)
            await MainActor.run {
                isApplying = false
                if parsed.isEmpty {
                    applyError = "Keine Änderungen erkannt"
                } else {
                    pendingAppliedFiles = parsed
                    showApplySheet = true
                }
            }
        }
    }

    private func parseAppliedFiles(from output: String, knownFiles: [URL]) -> [(url: URL, newContent: String)] {
        var results: [(url: URL, newContent: String)] = []
        // Match blocks: ### filename\n```ext\n<code>\n```
        let pattern = #"###\s+(.+?)\n```[^\n]*\n([\s\S]*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(output.startIndex..., in: output)
        let matches = regex.matches(in: output, range: range)
        for match in matches {
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: output),
                  let codeRange = Range(match.range(at: 2), in: output) else { continue }
            let name = String(output[nameRange]).trimmingCharacters(in: .whitespaces)
            let code = String(output[codeRange])
            // Find matching URL among known files
            if let url = knownFiles.first(where: { $0.lastPathComponent == name }) {
                results.append((url: url, newContent: code))
            }
        }
        return results
    }

    private func commitAppliedFiles() {
        showApplySheet = false
        var failed = false
        for item in pendingAppliedFiles {
            do {
                try item.newContent.write(to: item.url, atomically: true, encoding: .utf8)
                // Refresh preview if this file is currently shown
                if previewFile == item.url {
                    previewContent = item.newContent
                }
            } catch {
                failed = true
            }
        }
        pendingAppliedFiles = []
        if failed {
            applyError = "Einige Dateien konnten nicht gespeichert werden"
        } else {
            applySuccess = true
        }
    }

    // MARK: - File Tree Helpers

    private func buildFileTree(at url: URL, depth: Int) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let textExtensions: Set<String> = [
            "swift", "py", "js", "ts", "jsx", "tsx", "go", "rs", "rb", "java",
            "kt", "c", "cpp", "h", "hpp", "cs", "php", "m", "mm",
            "json", "yaml", "yml", "toml", "xml", "plist",
            "md", "txt", "sh", "bash", "zsh", "makefile", "dockerfile",
            "html", "css", "scss", "sass", "sql", "env", "gitignore", "lock",
            "bas", "cls", "frm", "vba", "vbs"
        ]

        var nodes: [FileNode] = []
        let sorted = contents.sorted {
            let aIsDir = (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let bIsDir = (try? $1.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if aIsDir != bIsDir { return aIsDir }
            return $0.lastPathComponent < $1.lastPathComponent
        }

        for item in sorted {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = item.lastPathComponent

            // Skip common noise directories
            let skipDirs: Set<String> = [".git", ".build", ".swiftpm", "node_modules",
                                          "__pycache__", ".venv", "venv", "dist", "build",
                                          ".DS_Store", "DerivedData", "Pods"]
            if skipDirs.contains(name) { continue }

            if isDir && depth < 4 {
                let children = buildFileTree(at: item, depth: depth + 1)
                if !children.isEmpty {
                    let node = FileNode(url: item, children: children, depth: depth)
                    nodes.append(node)
                }
            } else if !isDir {
                let ext = item.pathExtension.lowercased()
                let nameLC = name.lowercased()
                let isText = textExtensions.contains(ext) ||
                             textExtensions.contains(nameLC) ||
                             item.pathExtension.isEmpty
                if isText {
                    nodes.append(FileNode(url: item, children: nil, depth: depth))
                }
            }
        }
        return nodes
    }

    private func flattenedTree(_ nodes: [FileNode]) -> [FileNode] {
        var result: [FileNode] = []
        for node in nodes {
            result.append(node)
            if node.isDirectory, node.isExpanded, let children = node.children {
                result.append(contentsOf: flattenedTree(children))
            }
        }
        return result
    }

    private func selectAllFiles(in nodes: [FileNode]) {
        for node in nodes {
            if node.isDirectory, let children = node.children {
                selectAllFiles(in: children)
            } else {
                selectedFiles.insert(node.url)
            }
        }
    }

    private func toggleDirectory(_ node: FileNode) {
        guard let children = node.children else { return }
        let allFiles = allLeafFiles(in: children)
        let allSelected = allFiles.allSatisfy { selectedFiles.contains($0) }
        if allSelected {
            allFiles.forEach { selectedFiles.remove($0) }
        } else {
            allFiles.forEach { selectedFiles.insert($0) }
        }
    }

    private func allLeafFiles(in nodes: [FileNode]) -> [URL] {
        var result: [URL] = []
        for node in nodes {
            if node.isDirectory, let children = node.children {
                result.append(contentsOf: allLeafFiles(in: children))
            } else {
                result.append(node.url)
            }
        }
        return result
    }

    private func estimatedSizeKB() -> Int {
        let fm = FileManager.default
        var total = 0
        for url in selectedFiles {
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            total += size
        }
        return total / 1024
    }
}
