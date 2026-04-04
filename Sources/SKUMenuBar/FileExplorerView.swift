import SwiftUI
import AppKit

// MARK: - File Node Model

final class ExplorerNode: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    @Published var children: [ExplorerNode]? = nil   // nil = not yet loaded
    @Published var isExpanded: Bool = false
    weak var parent: ExplorerNode?

    init(url: URL, parent: ExplorerNode? = nil) {
        self.url = url
        self.name = url.lastPathComponent
        self.parent = parent
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }

    func loadChildren(showHidden: Bool) {
        guard isDirectory else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: showHidden ? [] : .skipsHiddenFiles
        ) else {
            children = []
            return
        }
        children = contents
            .sorted { a, b in
                let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if aDir != bDir { return aDir }
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }
            .map { ExplorerNode(url: $0, parent: self) }
    }

    var fileSize: Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map { Int64($0) } ?? 0
    }

    var modifiedAt: Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    var fileExtension: String { url.pathExtension.lowercased() }

    var isPDF: Bool { fileExtension == "pdf" }

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
            "makefile", "readme", "license", "podfile", "gemfile"
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
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "ico": return "photo"
        case "pdf":                            return "doc.fill"
        case "zip", "tar", "gz", "7z":        return "archivebox"
        default:                               return "doc.text"
        }
    }

    var iconColor: Color {
        if isDirectory { return .indigo }
        switch fileExtension {
        case "swift":        return Color(red: 0.98, green: 0.45, blue: 0.20)
        case "py":           return .blue
        case "js", "jsx":   return .yellow
        case "ts", "tsx":   return Color(red: 0.17, green: 0.51, blue: 0.90)
        case "json":         return .orange
        case "md":           return .teal
        case "sh", "bash", "zsh": return .green
        case "html":         return Color(red: 0.90, green: 0.35, blue: 0.2)
        case "css", "scss": return .purple
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
    @State private var isLoadingPreview: Bool = false
    @State private var renamingNode: ExplorerNode? = nil
    @State private var renameText: String = ""
    @State private var confirmDeleteNode: ExplorerNode? = nil
    @State private var newItemParent: ExplorerNode? = nil
    @State private var newItemName: String = ""
    @State private var newItemIsDir: Bool = false
    @State private var errorMsg: String? = nil

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: tree panel
            VStack(spacing: 0) {
                toolbar
                Divider().foregroundStyle(theme.cardBorder)
                treePanel
            }
            .frame(minWidth: 280, idealWidth: 340, maxWidth: 440)

            Rectangle().fill(theme.cardBorder).frame(width: 0.5)

            // Right: preview / info panel
            previewPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadInitialDirectory() }
        .onChange(of: showHidden) { reload() }
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
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            // Current root (truncated)
            Button {
                pickDirectory()
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
                .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
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
                    .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
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
                    .background(theme.cardSurface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Im Finder öffnen")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(theme.windowBg)
    }

    // MARK: - Tree Panel

    private var treePanel: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
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
                        Image(systemName: node.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(node.iconColor)
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
                            if !node.isDirectory {
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
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(theme.cardSurface)

                    Divider().foregroundStyle(theme.cardBorder)

                    // File info row
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
                    .background(theme.cardSurface.opacity(0.5))

                    Divider().foregroundStyle(theme.cardBorder)

                    // Content area
                    if node.isDirectory {
                        directoryContentsView(node: node)
                    } else if isLoadingPreview {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let text = previewText {
                        ScrollView {
                            Text(text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .textSelection(.enabled)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: node.icon)
                                .font(.system(size: 36))
                                .foregroundStyle(node.iconColor.opacity(0.5))
                            Text("Keine Vorschau verfügbar")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
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
        .background(theme.windowBg)
    }

    private func infoChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .kerning(0.5)
            Text(value)
                .font(.system(size: 11, weight: .medium))
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
                                    Image(systemName: child.icon)
                                        .font(.system(size: 12))
                                        .foregroundStyle(child.iconColor)
                                        .frame(width: 18)
                                    Text(child.name)
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.primaryText)
                                    Spacer()
                                    if !child.isDirectory {
                                        Text(formatSize(child.fileSize))
                                            .font(.system(size: 10))
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

    // MARK: - Actions

    private func loadInitialDirectory() {
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
        if panel.runModal() == .OK, let url = panel.url {
            loadRoot(path: url.path)
        }
    }

    private func selectNode(_ node: ExplorerNode) {
        selectedNode = node
        previewText = nil

        if node.isDirectory {
            if node.children == nil {
                node.loadChildren(showHidden: showHidden)
            }
        } else if node.isTextFile {
            isLoadingPreview = true
            Task.detached(priority: .userInitiated) {
                let text = (try? String(contentsOf: node.url, encoding: .utf8))
                    ?? (try? String(contentsOf: node.url, encoding: .isoLatin1))
                let preview = text.map { t -> String in
                    let lines = t.components(separatedBy: "\n")
                    return lines.prefix(500).joined(separator: "\n")
                }
                await MainActor.run {
                    previewText = preview
                    isLoadingPreview = false
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
            if selectedNode?.id == node.id { selectedNode = nil; previewText = nil }
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

            // Icon (matching Verlauf: 11pt inside 26×26 rounded box)
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accentColor.opacity(0.2) : theme.primaryText.opacity(0.06))
                    .frame(width: 26, height: 26)
                Image(systemName: node.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? accentColor : node.iconColor)
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
                    .font(.system(size: 12, weight: .medium))
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
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? accentColor.opacity(0.15) : (isHovered ? theme.cardSurface : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect(node)
            if node.isDirectory {
                withAnimation(.easeInOut(duration: 0.15)) {
                    node.isExpanded.toggle()
                }
                if node.isExpanded && node.children == nil {
                    node.loadChildren(showHidden: showHidden)
                }
            }
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
