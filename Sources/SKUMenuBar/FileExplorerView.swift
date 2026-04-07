import SwiftUI
import AppKit
import WebKit
import PDFKit

// MARK: - File Node Model

final class ExplorerNode: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    @Published var children: [ExplorerNode]? = nil   // nil = not yet loaded
    @Published var isExpanded: Bool = false
    @Published var loadFailed: Bool = false   // true = last loadChildren failed (allow retry)
    weak var parent: ExplorerNode?

    init(url: URL, parent: ExplorerNode? = nil) {
        self.url = url
        self.name = url.lastPathComponent
        self.parent = parent
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }

    @discardableResult
    func loadChildren(showHidden: Bool) -> Bool {
        guard isDirectory else { return false }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: showHidden ? [] : .skipsHiddenFiles
        ) else {
            // Show as expanded but empty so the folder doesn't snap back shut.
            // loadFailed = true lets the tap handler retry on next click.
            children = []
            loadFailed = true
            return false
        }
        loadFailed = false
        children = contents
            .sorted { a, b in
                let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if aDir != bDir { return aDir }
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }
            .map { ExplorerNode(url: $0, parent: self) }
        return true
    }

    var fileSize: Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) } ?? 0
    }

    var modifiedAt: Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    var workspaceIcon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    var fileExtension: String { url.pathExtension.lowercased() }

    var isPDF: Bool { fileExtension == "pdf" }

    var isImage: Bool {
        ["png", "jpg", "jpeg", "gif", "bmp", "ico", "tiff", "tif", "webp", "heic"].contains(fileExtension)
    }

    var isWebPreviewable: Bool {
        ["html", "htm", "svg"].contains(fileExtension)
    }

    var isTextFile: Bool {
        let binaryExtensions: Set<String> = [
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "png", "jpg", "jpeg", "gif", "bmp", "ico", "tiff", "tif", "webp", "heic",
            "zip", "tar", "gz", "7z", "rar", "dmg", "pkg", "deb",
            "mp3", "mp4", "mov", "avi", "m4v", "wav", "aac", "flac",
            "ttf", "otf", "woff", "woff2", "eot",
            "sqlite", "db", "bin", "exe", "dylib", "so", "o", "a"
        ]
        if binaryExtensions.contains(fileExtension) { return false }
        let textExtensions: Set<String> = [
            "swift", "kt", "java", "py", "js", "ts", "jsx", "tsx", "go", "rs",
            "c", "cpp", "h", "m", "rb", "php", "sh", "bash", "zsh", "fish",
            "json", "yaml", "yml", "toml", "xml", "html", "htm", "css", "scss",
            "md", "txt", "csv", "log", "env", "gitignore", "dockerfile",
            "makefile", "readme", "license", "podfile", "gemfile",
            "bas", "cls", "frm", "vba", "vbs"
        ]
        return textExtensions.contains(fileExtension) || (fileSize > 0 && fileSize < 500_000)
    }

    var icon: String {
        if isDirectory { return isExpanded ? "folder.fill" : "folder.fill" }
        switch fileExtension {
        case "swift":                          return "swift"
        case "py":                             return "terminal"
        case "js", "ts", "jsx", "tsx":        return "curlybraces"
        case "json", "yaml", "yml", "toml":   return "doc.badge.gearshape"
        case "md":                             return "doc.richtext"
        case "html", "htm", "css", "scss":    return "globe"
        case "sh", "bash", "zsh":             return "terminal.fill"
        case "bas", "cls", "frm", "vba", "vbs": return "tablecells.fill"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "ico": return "photo"
        case "pdf":                            return "doc.fill"
        case "zip", "tar", "gz", "7z":        return "archivebox"
        default:                               return "doc.text"
        }
    }

    var iconColor: Color {
        if isDirectory { return .indigo }  // overridden in view with accentColor
        switch fileExtension {
        case "swift":        return Color(red: 0.98, green: 0.45, blue: 0.20)
        case "py":           return .blue
        case "js", "jsx":   return .yellow
        case "ts", "tsx":   return Color(red: 0.17, green: 0.51, blue: 0.90)
        case "json":         return .orange
        case "md":           return Color(red: 0.72, green: 0.52, blue: 0.35)  // warm braun
        case "sh", "bash", "zsh": return .green
        case "html":         return Color(red: 0.90, green: 0.35, blue: 0.2)
        case "css", "scss": return .purple
        case "bas", "cls", "frm", "vba", "vbs": return Color(red: 0.13, green: 0.55, blue: 0.13)
        case "png", "jpg", "jpeg", "gif", "svg": return .pink
        case "pdf":          return .red
        default:             return .secondary
        }
    }
}

// MARK: - File Explorer View

struct FileExplorerView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    @State private var rootNode: ExplorerNode?
    @State private var selectedNode: ExplorerNode?
    @State private var showHidden: Bool = false
    @State private var rootPath: String = NSHomeDirectory()
    @State private var previewText: String? = nil
    @State private var pdfDocument: PDFDocument? = nil
    @State private var nsImage: NSImage? = nil
    @State private var isLoadingPreview: Bool = false
    @State private var renamingNode: ExplorerNode? = nil
    @State private var renameText: String = ""
    @State private var confirmDeleteNode: ExplorerNode? = nil
    @State private var newItemParent: ExplorerNode? = nil
    @State private var newItemName: String = ""
    @State private var newItemIsDir: Bool = false
    @State private var errorMsg: String? = nil

    // Live preview
    @State private var showLivePreview: Bool = false
    @State private var livePreviewPanelWidth: CGFloat = 480
    /// Line hovered in the code editor → highlight element in preview (blue)
    @State private var editorHoveredLine: Int? = nil
    /// Line sent back from preview hover → highlight in editor (orange)
    @State private var previewHoveredLine: Int? = nil

    // Panel visibility (focus mode)
    @State private var showFileTree: Bool = true

    // Edit mode
    @State private var isEditing: Bool = false
    @State private var editText: String = ""
    @State private var isDirty: Bool = false
    @State private var showUnsavedAlert: Bool = false
    @State private var pendingNode: ExplorerNode? = nil
    @State private var showSaveToast: Bool = false

    // Commit sheet
    @State private var showCommitSheet: Bool = false
    @State private var commitMessage: String = ""
    @State private var doPush: Bool = true
    @State private var gitLog: String = ""
    @State private var isGitRunning: Bool = false
    @State private var gitDone: Bool = false
    @State private var gitHadError: Bool = false
    @State private var gitRepoURL: URL? = nil
    @State private var gitBranch: String = ""
    @State private var gitPRURL: URL? = nil

    private let gitService = GitShellService()

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    /// Option C: Ordner → Theme-Akzentfarbe, Dateien → semantische Extension-Farbe
    private func resolvedIconColor(_ node: ExplorerNode) -> Color {
        node.isDirectory ? accentColor : node.iconColor
    }

    @State private var treePanelWidth: CGFloat = 300
    private let treePanelMinWidth: CGFloat = 180
    private let treePanelMaxWidth: CGFloat = 600

    var body: some View {
        HStack(spacing: 0) {
            // Left: tree panel (collapsible)
            if showFileTree {
                VStack(spacing: 0) {
                    toolbar
                    treePanel
                }
                .frame(width: treePanelWidth)
                .background(theme.windowBg)
                .transition(.move(edge: .leading))

                // Draggable divider
                PanelResizeHandle(width: $treePanelWidth, minWidth: treePanelMinWidth, maxWidth: treePanelMaxWidth, growsRight: true)
                    .frame(width: 10)
            }

            // Right: preview / info panel
            previewPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if showSaveToast {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Gespeichert")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.primaryText)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.cardBorder, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.25), value: showSaveToast)
                .background {
                    // Hidden Cmd+S button — active only while editing
                    if isEditing, let node = selectedNode {
                        Button("") { quickSaveFile(node: node) }
                            .keyboardShortcut("s", modifiers: .command)
                            .frame(width: 0, height: 0)
                            .opacity(0)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.windowBg)
        .onAppear { loadInitialDirectory() }
        .onChange(of: showHidden) { reload() }
        .onChange(of: state.pendingFilesPath) {
            guard let path = state.pendingFilesPath else { return }
            state.pendingFilesPath = nil
            rootPath = path
            reload()
        }
        .alert("Ungespeicherte Änderungen", isPresented: $showUnsavedAlert) {
            Button("Verwerfen", role: .destructive) {
                isEditing = false; isDirty = false
                if let n = pendingNode { pendingNode = nil; selectNode(n) }
            }
            Button("Abbrechen", role: .cancel) { pendingNode = nil }
        } message: {
            Text("Die Datei hat ungespeicherte Änderungen. Wirklich wechseln?")
        }
        .alert("Löschen bestätigen", isPresented: Binding(
            get: { confirmDeleteNode != nil },
            set: { if !$0 { confirmDeleteNode = nil } }
        )) {
            Button("Löschen", role: .destructive) { performDelete() }
            Button("Abbrechen", role: .cancel) { confirmDeleteNode = nil }
        } message: {
            if let node = confirmDeleteNode {
                Text("\"\(node.name)\" wirklich löschen?")
            }
        }
        .sheet(isPresented: $showCommitSheet) { commitSheetView }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            // Current root (truncated) — menu with recent projects
            Menu {
                let projects = state.historyService.projects
                if !projects.isEmpty {
                    Section("Letzte Projekte") {
                        ForEach(projects.prefix(8)) { project in
                            Button {
                                rootPath = project.path
                                reload()
                            } label: {
                                Label(project.displayName, systemImage: "folder")
                            }
                        }
                    }
                    Divider()
                }
                Button {
                    pickDirectory()
                } label: {
                    Label("Anderer Ordner…", systemImage: "folder.badge.plus")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accentColor)
                    Text(URL(fileURLWithPath: rootPath).lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(theme.tertiaryText)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.clear)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Verzeichnis wählen")

            Spacer()

            // Hidden files toggle
            Button {
                showHidden.toggle()
            } label: {
                Image(systemName: showHidden ? "eye.fill" : "eye.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(showHidden ? accentColor : theme.tertiaryText)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Versteckte Dateien")

            // Open in Finder
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: rootPath))
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Im Finder öffnen")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(minHeight: 40)
        .background(theme.cardBg.opacity(0.4))
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.cardBorder).frame(height: 0.5)
        }
    }

    // MARK: - Tree Panel

    private var treePanel: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                if let root = rootNode {
                    ForEach(root.children ?? []) { node in
                        ExplorerTreeRow(
                            node: node,
                            selectedNode: $selectedNode,
                            renamingNode: $renamingNode,
                            renameText: $renameText,
                            showHidden: showHidden,
                            depth: 0,
                            onSelect: selectNode,
                            onNewItem: { parent, isDir in
                                newItemParent = parent
                                newItemIsDir = isDir
                                newItemName = ""
                            },
                            onDelete: { node in confirmDeleteNode = node },
                            onRename: commitRename,
                            onReveal: { NSWorkspace.shared.activateFileViewerSelecting([$0.url]) }
                        )
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }

                // New item input
                if let parent = newItemParent {
                    newItemRow(parent: parent)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.windowBg)
    }

    private func newItemRow(parent: ExplorerNode) -> some View {
        HStack(spacing: 6) {
            Image(systemName: newItemIsDir ? "folder.badge.plus" : "doc.badge.plus")
                .font(.system(size: 11))
                .foregroundStyle(accentColor)
            TextField(newItemIsDir ? "Ordnername…" : "Dateiname…", text: $newItemName)
                .font(.system(size: 11))
                .foregroundStyle(theme.primaryText)
                .textFieldStyle(.plain)
                .onSubmit { commitNewItem(parent: parent) }
            Button {
                newItemParent = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(accentColor.opacity(0.06))
    }

    // MARK: - Preview Panel

    private var previewPanel: some View {
        Group {
            if let node = selectedNode {
                VStack(spacing: 0) {
                    // Preview header
                    HStack(spacing: 8) {
                        Image(nsImage: node.workspaceIcon)
                            .resizable()
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(node.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                            Text(node.url.path)
                                .font(.system(size: 9))
                                .foregroundStyle(theme.tertiaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        // Action buttons
                        HStack(spacing: 6) {
                            if !node.isDirectory && node.isWebPreviewable {
                                Button {
                                    showLivePreview.toggle()
                                } label: {
                                    Label("Live Preview", systemImage: showLivePreview ? "eye.fill" : "eye")
                                        .font(.system(size: 10))
                                        .foregroundStyle(showLivePreview ? accentColor : theme.secondaryText)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(
                                            showLivePreview ? accentColor.opacity(0.12) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 5)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .strokeBorder(showLivePreview ? accentColor.opacity(0.3) : Color.clear, lineWidth: 0.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            if !node.isDirectory && node.isTextFile {
                                if isEditing {
                                    Button {
                                        saveFile(node: node)
                                    } label: {
                                        Label(isDirty ? "Speichern *" : "Speichern", systemImage: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.green)
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        isEditing = false; isDirty = false
                                        editText = previewText ?? ""
                                    } label: {
                                        Label("Abbrechen", systemImage: "xmark.circle")
                                            .font(.system(size: 10))
                                            .foregroundStyle(theme.secondaryText)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Button {
                                        enterEditMode(node: node)
                                    } label: {
                                        Label("Bearbeiten", systemImage: "pencil")
                                            .font(.system(size: 10))
                                            .foregroundStyle(accentColor)
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        NSWorkspace.shared.open(node.url)
                                    } label: {
                                        Label("Öffnen", systemImage: "arrow.up.forward.square")
                                            .font(.system(size: 10))
                                            .foregroundStyle(accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else if !node.isDirectory {
                                Button {
                                    NSWorkspace.shared.open(node.url)
                                } label: {
                                    Label("Öffnen", systemImage: "arrow.up.forward.square")
                                        .font(.system(size: 10))
                                        .foregroundStyle(accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(node.url.path, forType: .string)
                            } label: {
                                Label("Pfad kopieren", systemImage: "doc.on.clipboard")
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.secondaryText)
                            }
                            .buttonStyle(.plain)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([node.url])
                            } label: {
                                Label("Im Finder", systemImage: "folder")
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.secondaryText)
                            }
                            .buttonStyle(.plain)

                            Divider().frame(height: 14)

                            // Focus mode toggles
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showFileTree.toggle() }
                            } label: {
                                Image(systemName: showFileTree ? "sidebar.left" : "sidebar.left")
                                    .font(.system(size: 11))
                                    .foregroundStyle(showFileTree ? theme.secondaryText : accentColor)
                                    .help(showFileTree ? "Dateibaum ausblenden" : "Dateibaum einblenden")
                            }
                            .buttonStyle(.plain)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { state.hideSidebar.toggle() }
                            } label: {
                                Image(systemName: state.hideSidebar ? "sidebar.squares.left" : "sidebar.squares.left")
                                    .font(.system(size: 11))
                                    .foregroundStyle(state.hideSidebar ? accentColor : theme.secondaryText)
                                    .help(state.hideSidebar ? "Sidebar einblenden" : "Sidebar ausblenden")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(theme.cardBg.opacity(0.4))

                    Rectangle().fill(theme.cardBorder).frame(height: 0.5)

                    // File info row — tinted like Code Review mode pills
                    HStack(spacing: 20) {
                        if !node.isDirectory {
                            infoChip(label: "Größe", value: formatSize(node.fileSize))
                        }
                        if let mod = node.modifiedAt {
                            infoChip(label: "Geändert", value: mod.formatted(date: .abbreviated, time: .shortened))
                        }
                        infoChip(label: "Typ", value: node.isDirectory ? "Ordner" : (node.fileExtension.isEmpty ? "Datei" : node.fileExtension.uppercased()))
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(theme.cardBg.opacity(0.5))

                    Rectangle().fill(theme.cardBorder).frame(height: 0.5)

                    // Content area
                    if node.isDirectory {
                        directoryContentsView(node: node)
                    } else if isLoadingPreview {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if node.isPDF, let pdf = pdfDocument {
                        PDFPreviewView(document: pdf)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let img = nsImage {
                        ScrollView([.vertical, .horizontal]) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let text = previewText {
                        if showLivePreview && node.isWebPreviewable {
                            livePreviewSplitView(node: node, text: text)
                        } else if isEditing {
                            HighlightedCodeView(
                                code: editText,
                                fileURL: node.url,
                                isDark: !theme.isLight,
                                isEditable: true,
                                onTextChange: { newText in
                                    editText = newText
                                    isDirty = true
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            HighlightedCodeView(
                                code: text,
                                fileURL: node.url,
                                isDark: !theme.isLight
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(nsImage: node.workspaceIcon)
                                .resizable()
                                .frame(width: 48, height: 48)
                                .opacity(0.5)
                            Text("Keine Vorschau verfügbar")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    // Empty state header — same pattern as file header
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.tertiaryText)
                        Text("Vorschau")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(theme.cardBg.opacity(0.4))

                    Rectangle().fill(theme.cardBorder).frame(height: 0.5)

                    VStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(accentColor.opacity(0.3))
                        Text("Datei oder Ordner auswählen")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(theme.windowBg)
    }

    private func infoChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .kerning(0.5)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.primaryText)
        }
    }

    private func directoryContentsView(node: ExplorerNode) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if let children = node.children {
                    if children.isEmpty {
                        Text("Leeres Verzeichnis")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.tertiaryText)
                            .padding(16)
                    } else {
                        ForEach(children) { child in
                            Button {
                                selectNode(child)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(nsImage: child.workspaceIcon)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                        .frame(width: 20)
                                    Text(child.name)
                                        .font(.system(size: 12))
                                        .foregroundStyle(theme.primaryText)
                                    Spacer()
                                    if !child.isDirectory {
                                        Text(formatSize(child.fileSize))
                                            .font(.system(size: 11))
                                            .foregroundStyle(theme.tertiaryText)
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Live Preview Split View

    private func livePreviewSplitView(node: ExplorerNode, text: String) -> some View {
        let liveCode = isEditing ? editText : text
        let htmlContent: String = {
            if node.fileExtension == "svg" {
                return "<!DOCTYPE html><html><body style='margin:0;background:#fff;display:flex;align-items:center;justify-content:center;min-height:100vh;'>\(liveCode)</body></html>"
            }
            return liveCode
        }()

        return HStack(spacing: 0) {
            // Code editor
            HighlightedCodeView(
                code: isEditing ? editText : text,
                fileURL: node.url,
                isDark: !theme.isLight,
                isEditable: isEditing,
                onTextChange: { newText in
                    editText = newText
                    isDirty = true
                },
                onHoverLine: { line in editorHoveredLine = line },
                hoveredLine: previewHoveredLine
            )
            .frame(minWidth: 200, idealWidth: livePreviewPanelWidth, maxWidth: livePreviewPanelWidth, maxHeight: .infinity)

            // Draggable divider (editor | preview)
            ResizeDividerHandle(onDrag: { delta in
                livePreviewPanelWidth = max(200, min(1400, livePreviewPanelWidth + delta))
            })
            .frame(width: 8)

            // Live web preview
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundStyle(accentColor)
                    Text("Live Preview")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    if isEditing && isDirty {
                        HStack(spacing: 4) {
                            Circle().fill(.orange).frame(width: 6, height: 6)
                            Text("Ungespeichert")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.tertiaryText)
                        }
                    }
                    Button {
                        // Open in default browser
                        if isEditing && isDirty {
                            // Write temp file and open
                            let tmp = FileManager.default.temporaryDirectory
                                .appendingPathComponent(node.name)
                            try? editText.write(to: tmp, atomically: true, encoding: .utf8)
                            NSWorkspace.shared.open(tmp)
                        } else {
                            NSWorkspace.shared.open(node.url)
                        }
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Im Browser öffnen")
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(theme.cardSurface)

                Divider()

                WebPreviewView(
                    htmlContent: htmlContent,
                    sourceURL: node.url,
                    accessRoot: URL(fileURLWithPath: rootPath),
                    highlightLine: editorHoveredLine,
                    onPreviewHover: { line in previewHoveredLine = line }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func enterEditMode(node: ExplorerNode) {
        editText = previewText ?? ""
        isDirty = false
        isEditing = true
    }

    private func saveFile(node: ExplorerNode) {
        do {
            try editText.write(to: node.url, atomically: true, encoding: .utf8)
            previewText = editText
            isDirty = false
            isEditing = false
            // Prepare commit sheet values, then show immediately
            commitMessage = "Edit: \(node.name)"
            gitLog = ""
            gitDone = false
            gitHadError = false
            gitRepoURL = nil
            gitBranch = ""
            gitPRURL = nil
            showCommitSheet = true
            // Detect repo + branch in background (non-blocking)
            let svc = gitService
            let fileURL = node.url
            Task.detached(priority: .userInitiated) {
                let repo = svc.repoRoot(for: fileURL)
                let branch = repo.map { svc.currentBranch(in: $0) } ?? ""
                let prURL = repo.flatMap { svc.prURL(in: $0) }
                await MainActor.run {
                    self.gitRepoURL = repo
                    self.gitBranch = branch
                    self.gitPRURL = prURL
                }
            }
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func quickSaveFile(node: ExplorerNode) {
        do {
            try editText.write(to: node.url, atomically: true, encoding: .utf8)
            previewText = editText
            isDirty = false
            showSaveToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { showSaveToast = false }
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    // MARK: - Commit sheet view

    @ViewBuilder
    private var commitSheetView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14))
                    .foregroundStyle(accentColor)
                Text("Commit & Push")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                if !gitBranch.isEmpty {
                    Text(gitBranch)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 4))
                } else {
                    ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Commit message
                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMMIT-NACHRICHT")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)
                            .kerning(0.5)
                        TextField("Commit-Nachricht…", text: $commitMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.primaryText)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder))
                    }

                    // Options
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $doPush) {
                            Text("Nach Commit pushen (git push)")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.secondaryText)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(gitDone || isGitRunning)
                        Text("Vor dem Commit wird automatisch git pull ausgeführt.")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                    }

                    // Log output
                    if !gitLog.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OUTPUT")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.tertiaryText)
                                .kerning(0.5)
                            ScrollView {
                                Text(gitLog)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(gitHadError ? Color.red : theme.primaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                            }
                            .frame(maxHeight: 140)
                            .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    // PR button (shown after successful push)
                    if gitDone && !gitHadError && doPush, let prURL = gitPRURL {
                        Button {
                            NSWorkspace.shared.open(prURL)
                        } label: {
                            Label("Pull Request erstellen", systemImage: "arrow.triangle.pull")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(accentColor, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer buttons
            HStack(spacing: 10) {
                if isGitRunning {
                    ProgressView().scaleEffect(0.7)
                    Text("Läuft…")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer()
                Button("Schließen") {
                    showCommitSheet = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)

                if !gitDone {
                    Button {
                        runCommit()
                    } label: {
                        Text(doPush ? "Commit & Push" : "Commit")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(commitMessage.isEmpty ? Color.gray : accentColor,
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(commitMessage.isEmpty || isGitRunning)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 440, alignment: .leading)
        .background(theme.windowBg)
        .environment(\.appTheme, theme)
    }

    @MainActor
    private func runCommit() {
        guard let repo = gitRepoURL, let node = selectedNode else { return }
        isGitRunning = true
        gitLog = ""
        gitHadError = false

        // Capture values needed inside the detached task
        let doPushNow = doPush
        let message = commitMessage
        let fileURL = node.url
        let svc = gitService

        Task.detached(priority: .userInitiated) {
            var log = "Git: \(GitShellService.gitPath)\nRepo: \(repo.path)\n\n"

            func append(_ r: GitShellService.GitResult, label: String) {
                log += "→ \(label)\n"
                let out = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let err = r.error.trimmingCharacters(in: .whitespacesAndNewlines)
                if !out.isEmpty { log += out + "\n" }
                if !err.isEmpty { log += err + "\n" }
                log += "\n"
            }

            // Pull (always)
            let r = svc.run(["pull"], in: repo)
            append(r, label: "git pull")
            if !r.success { await self.finish(log: log, error: true); return }

            // Add
            let addR = svc.run(["add", fileURL.path], in: repo)
            append(addR, label: "git add")
            if !addR.success { await self.finish(log: log, error: true); return }

            // Commit
            let commitR = svc.run(["commit", "-m", message], in: repo)
            append(commitR, label: "git commit")
            if !commitR.success { await self.finish(log: log, error: true); return }

            // Push
            if doPushNow {
                let pushR = svc.run(["push"], in: repo)
                append(pushR, label: "git push")
                if !pushR.success { await self.finish(log: log, error: true); return }
            }

            await self.finish(log: log, error: false)
        }
    }

    @MainActor
    private func finish(log: String, error: Bool) {
        gitLog = log
        gitHadError = error
        gitDone = !error
        isGitRunning = false
    }

    private func loadInitialDirectory() {
        // Restore last used directory (simple path storage; no sandbox so no security-scope needed)
        if let saved = UserDefaults.standard.string(forKey: "fileExplorerLastPath"),
           FileManager.default.fileExists(atPath: saved) {
            loadRoot(path: saved)
            return
        }
        // Prefer the working directory of the current chat tab
        let chatWd = state.chatTabs.indices.contains(state.selectedChatTabIndex)
            ? state.chatTabs[state.selectedChatTabIndex].workingDirectory
            : nil
        let path = chatWd ?? NSHomeDirectory()
        loadRoot(path: path)
    }

    private func loadRoot(path: String) {
        rootPath = path
        let url = URL(fileURLWithPath: path)
        let node = ExplorerNode(url: url)
        node.loadChildren(showHidden: showHidden)
        rootNode = node
        selectedNode = nil
        previewText = nil
        pdfDocument = nil
        nsImage = nil
    }

    private func reload() {
        loadRoot(path: rootPath)
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"
        panel.directoryURL = URL(fileURLWithPath: rootPath)
        // Request persistent access so macOS stops asking every session
        if #available(macOS 13.0, *) {
            panel.allowsMultipleSelection = false
        }
        if panel.runModal() == .OK, let url = panel.url {
            // Persist path for next launch (app is not sandboxed, no security-scope needed)
            UserDefaults.standard.set(url.path, forKey: "fileExplorerLastPath")
            loadRoot(path: url.path)
        }
    }

    private func selectNode(_ node: ExplorerNode) {
        // Guard unsaved changes
        if isDirty, selectedNode?.id != node.id {
            pendingNode = node
            showUnsavedAlert = true
            return
        }
        isEditing = false
        isDirty = false
        showLivePreview = false
        selectedNode = node
        previewText = nil
        pdfDocument = nil
        nsImage = nil

        if node.isDirectory {
            if node.children == nil {
                node.loadChildren(showHidden: showHidden)
            }
        } else if node.isPDF {
            pdfDocument = PDFDocument(url: node.url)
        } else if node.isImage {
            isLoadingPreview = true
            let targetURL = node.url
            Task.detached(priority: .userInitiated) {
                let img = NSImage(contentsOf: targetURL)
                await MainActor.run {
                    if self.selectedNode?.url == targetURL {
                        self.nsImage = img
                        self.isLoadingPreview = false
                    }
                }
            }
        } else if node.isTextFile {
            isLoadingPreview = true
            let targetURL = node.url
            Task.detached(priority: .userInitiated) {
                let text = (try? String(contentsOf: targetURL, encoding: .utf8))
                    ?? (try? String(contentsOf: targetURL, encoding: .isoLatin1))
                await MainActor.run {
                    // Only apply if this node is still selected
                    if self.selectedNode?.url == targetURL {
                        self.previewText = text
                        self.editText = text ?? ""
                        self.isEditing = true
                        self.isDirty = false
                        self.isLoadingPreview = false
                    }
                }
            }
        }
    }

    private func commitRename() {
        guard let node = renamingNode, !renameText.isEmpty, renameText != node.name else {
            renamingNode = nil
            return
        }
        let newURL = node.url.deletingLastPathComponent().appendingPathComponent(renameText)
        do {
            try FileManager.default.moveItem(at: node.url, to: newURL)
            renamingNode = nil
            // Reload parent
            if let parent = node.parent {
                parent.loadChildren(showHidden: showHidden)
                parent.objectWillChange.send()
            } else {
                reload()
            }
        } catch {
            errorMsg = error.localizedDescription
            renamingNode = nil
        }
    }

    private func performDelete() {
        guard let node = confirmDeleteNode else { return }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
            if selectedNode?.id == node.id { selectedNode = nil; previewText = nil; pdfDocument = nil; nsImage = nil }
            if let parent = node.parent {
                parent.loadChildren(showHidden: showHidden)
                parent.objectWillChange.send()
            } else {
                reload()
            }
        } catch {
            errorMsg = error.localizedDescription
        }
        confirmDeleteNode = nil
    }

    private func commitNewItem(parent: ExplorerNode) {
        guard !newItemName.isEmpty else { newItemParent = nil; return }
        let newURL = parent.url.appendingPathComponent(newItemName)
        do {
            if newItemIsDir {
                try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
            } else {
                FileManager.default.createFile(atPath: newURL.path, contents: nil)
            }
            parent.loadChildren(showHidden: showHidden)
            parent.objectWillChange.send()
            newItemParent = nil
        } catch {
            errorMsg = error.localizedDescription
            newItemParent = nil
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - File Tree Row

struct ExplorerTreeRow: View {
    @ObservedObject var node: ExplorerNode
    @Binding var selectedNode: ExplorerNode?
    @Binding var renamingNode: ExplorerNode?
    @Binding var renameText: String
    var showHidden: Bool
    var depth: Int
    var onSelect: (ExplorerNode) -> Void
    var onNewItem: (ExplorerNode, Bool) -> Void
    var onDelete: (ExplorerNode) -> Void
    var onRename: () -> Void
    var onReveal: (ExplorerNode) -> Void

    @Environment(\.appTheme) var theme
    @State private var isHovered = false
    @State private var showContextMenu = false

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private func resolvedIconColor(_ node: ExplorerNode) -> Color {
        node.isDirectory ? accentColor : node.iconColor
    }

    private var isSelected: Bool { selectedNode?.id == node.id }
    private var isRenaming: Bool { renamingNode?.id == node.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowContent
            // Children
            if node.isExpanded, let children = node.children {
                ForEach(children) { child in
                    ExplorerTreeRow(
                        node: child,
                        selectedNode: $selectedNode,
                        renamingNode: $renamingNode,
                        renameText: $renameText,
                        showHidden: showHidden,
                        depth: depth + 1,
                        onSelect: onSelect,
                        onNewItem: onNewItem,
                        onDelete: onDelete,
                        onRename: onRename,
                        onReveal: onReveal
                    )
                }
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            // Indent
            Color.clear.frame(width: CGFloat(depth) * 14)

            // Expand arrow (directories only)
            if node.isDirectory {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }

            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? accentColor.opacity(0.15) : Color.clear)
                    .frame(width: 22, height: 22)
                Image(nsImage: node.workspaceIcon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }

            // Name / rename field
            if isRenaming {
                TextField("", text: $renameText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .textFieldStyle(.plain)
                    .onSubmit { onRename() }
                    .onExitCommand { renamingNode = nil }
            } else {
                Text(node.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Hover actions
            if isHovered && !isRenaming {
                HStack(spacing: 2) {
                    if node.isDirectory {
                        toolbarIconBtn("doc.badge.plus", help: "Neue Datei") { onNewItem(node, false) }
                        toolbarIconBtn("folder.badge.plus", help: "Neuer Ordner") { onNewItem(node, true) }
                    }
                    toolbarIconBtn("pencil", help: "Umbenennen") {
                        renameText = node.name
                        renamingNode = node
                    }
                    toolbarIconBtn("trash", help: "Löschen", color: .red) { onDelete(node) }
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? accentColor.opacity(0.15) : (isHovered ? theme.hoverBg : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if node.isDirectory {
                withAnimation(.easeInOut(duration: 0.15)) {
                    node.isExpanded.toggle()
                }
                // Load (or retry after failure) when expanding
                if node.isExpanded && (node.children == nil || node.loadFailed) {
                    node.loadChildren(showHidden: showHidden)
                }
            }
            onSelect(node)
        }
        .padding(.horizontal, 4)
    }

    private func toolbarIconBtn(_ icon: String, help: String, color: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Web Preview View

struct WebPreviewView: NSViewRepresentable {
    let htmlContent: String
    /// The original source file URL (temp preview file is written next to it)
    let sourceURL: URL
    /// Root of the project — WKWebView gets read access to this entire tree
    let accessRoot: URL
    /// Line hovered in the code editor — the matching element is outlined blue in the preview.
    var highlightLine: Int? = nil
    /// Called when the mouse hovers an element in the preview (line number, nil = left).
    var onPreviewHover: ((Int?) -> Void)? = nil

    private static let tmpFileName = ".myClaude_livepreview.html"

    // Injected at documentEnd — adds hover outlines and the __highlightEditorLine bridge.
    private static let hoverScript = """
    (function() {
        var hovered = null;
        var editorMark = null;
        document.addEventListener('mouseover', function(e) {
            if (hovered) { hovered.style.outline = hovered.__prevOutline || ''; }
            hovered = e.target;
            hovered.__prevOutline = hovered.style.outline || '';
            hovered.style.outline = '2px solid rgba(0,120,255,0.55)';
            var node = hovered;
            while (node && node.nodeType === 1) {
                var line = node.getAttribute('data-source-line');
                if (line) { window.webkit.messageHandlers.previewHover.postMessage(parseInt(line)); return; }
                node = node.parentElement;
            }
        }, true);
        document.addEventListener('mouseout', function(e) {
            if (e.relatedTarget === null) {
                if (hovered) { hovered.style.outline = hovered.__prevOutline || ''; hovered = null; }
                window.webkit.messageHandlers.previewHover.postMessage(0);
            }
        }, true);
        window.__highlightEditorLine = function(lineNum) {
            if (editorMark) { editorMark.style.outline = editorMark.__editorPrev || ''; editorMark = null; }
            if (lineNum <= 0) return;
            var el = document.querySelector('[data-source-line="' + lineNum + '"]');
            if (!el) {
                for (var n = lineNum - 1; n >= 1 && !el; n--) {
                    el = document.querySelector('[data-source-line="' + n + '"]');
                }
            }
            if (el) {
                editorMark = el;
                editorMark.__editorPrev = el.style.outline || '';
                el.style.outline = '2px solid rgba(255,140,0,0.75)';
                el.scrollIntoView({behavior:'smooth', block:'nearest'});
            }
        };
    })();
    """

    // Weak wrapper to break WKUserContentController → Coordinator retain cycle.
    private final class WeakMsgHandler: NSObject, WKScriptMessageHandler {
        weak var coordinator: Coordinator?
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            coordinator?.userContentController(ucc, didReceive: message)
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onPreviewHover: ((Int?) -> Void)?
        var lastContent: String = ""
        var lastHighlightLine: Int? = nil

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "previewHover" else { return }
            let line = message.body as? Int ?? 0
            DispatchQueue.main.async { self.onPreviewHover?(line > 0 ? line : nil) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let weakHandler = WeakMsgHandler()
        weakHandler.coordinator = context.coordinator
        config.userContentController.add(weakHandler, name: "previewHover")
        let script = WKUserScript(source: Self.hoverScript,
                                  injectionTime: .atDocumentEnd,
                                  forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        let webView = WKWebView(frame: .zero, configuration: config)
        if #available(macOS 14.0, *) {
            webView.underPageBackgroundColor = .clear
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onPreviewHover = onPreviewHover

        // Preprocess HTML to tag each element with its source line number.
        let processed = injectSourceLineAttributes(htmlContent)
        if processed != context.coordinator.lastContent {
            context.coordinator.lastContent = processed
            context.coordinator.lastHighlightLine = nil
            let dir = sourceURL.deletingLastPathComponent()
            let tmpURL = dir.appendingPathComponent(Self.tmpFileName)
            do {
                try processed.write(to: tmpURL, atomically: true, encoding: .utf8)
                webView.loadFileURL(tmpURL, allowingReadAccessTo: accessRoot)
            } catch {
                webView.loadHTMLString(processed, baseURL: dir)
            }
        }

        // Drive editor→preview highlight via JS (only when value changed).
        let line = highlightLine ?? 0
        if line != (context.coordinator.lastHighlightLine ?? -999) {
            context.coordinator.lastHighlightLine = highlightLine
            webView.evaluateJavaScript("if(window.__highlightEditorLine)window.__highlightEditorLine(\(line));",
                                       completionHandler: nil)
        }
    }

    /// Adds data-source-line="N" to every opening HTML tag so the JS can map
    /// elements back to source lines.
    private func injectSourceLineAttributes(_ html: String) -> String {
        let lines = html.components(separatedBy: "\n")
        var result = [String]()
        result.reserveCapacity(lines.count)
        for (i, line) in lines.enumerated() {
            let n = i + 1
            // Inject into opening tags that don't already carry the attribute.
            // Pattern: <tagname optionalAttrs> or <tagname optionalAttrs/>
            // We skip DOCTYPE, comments (<!--), processing instructions (<?).
            let modified = line.replacingOccurrences(
                of: #"<([a-zA-Z][a-zA-Z0-9]*)(\s[^>]*)?(/?>\s*)"#,
                with: "<$1 data-source-line=\"\(n)\"$2$3",
                options: .regularExpression
            )
            result.append(modified)
        }
        return result.joined(separator: "\n")
    }
}

// MARK: - Resize Divider Handle (NSViewRepresentable for reliable cursor)

struct ResizeDividerHandle: NSViewRepresentable {
    let onDrag: (CGFloat) -> Void

    func makeNSView(context: Context) -> _ResizeDividerNSView {
        _ResizeDividerNSView(onDrag: onDrag)
    }

    func updateNSView(_ nsView: _ResizeDividerNSView, context: Context) {
        nsView.onDrag = onDrag
    }
}

final class _ResizeDividerNSView: NSView {
    var onDrag: (CGFloat) -> Void
    private var lastX: CGFloat = 0

    init(onDrag: @escaping (CGFloat) -> Void) {
        self.onDrag = onDrag
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // Draw a single 1px separator line in the center of the hit area
        let midX = floor(bounds.midX) + 0.5
        let line = NSBezierPath()
        line.move(to: NSPoint(x: midX, y: bounds.minY))
        line.line(to: NSPoint(x: midX, y: bounds.maxY))
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        line.lineWidth = 1
        line.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseExited(with event: NSEvent)  { NSCursor.arrow.set() }

    override func mouseDown(with event: NSEvent) {
        lastX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        let currentX = event.locationInWindow.x
        let delta = currentX - lastX
        lastX = currentX
        DispatchQueue.main.async { self.onDrag(delta) }
    }

    override func mouseUp(with event: NSEvent) {}

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
