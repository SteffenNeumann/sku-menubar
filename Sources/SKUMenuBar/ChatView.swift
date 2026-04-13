import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - Chat View (Tab Container)

struct ChatView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    private var tabs: [ChatTab] { state.chatTabs }
    private var selectedTabIndex: Int { state.selectedChatTabIndex }

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            // Render ALL tabs in a ZStack; show/hide via opacity to preserve @State on tab switch
            ZStack {
                ForEach(Array(state.chatTabs.enumerated()), id: \.element.id) { index, _ in
                    SingleChatSessionView(
                        tab: Binding(
                            get: { state.chatTabs.indices.contains(index) ? state.chatTabs[index] : ChatTab() },
                            set: { if state.chatTabs.indices.contains(index) { state.chatTabs[index] = $0 } }
                        ),
                        isActive: state.selectedChatTabIndex == index
                    )
                    .opacity(state.selectedChatTabIndex == index ? 1 : 0)
                    .allowsHitTesting(state.selectedChatTabIndex == index)
                    .environmentObject(state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                // Separator here — sits below the accent underline, never covers it
                theme.cardBorder.opacity(0.5).frame(height: 0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            handlePendingSession()
        }
        .onChange(of: state.pendingChatSession) {
            handlePendingSession()
        }
    }

    private func handlePendingSession() {
        if let sid = state.pendingChatSession {
            openSessionInNewTab(sid, title: state.pendingChatSessionTitle, workingDirectory: state.pendingChatWorkingDirectory)
            state.pendingChatSession = nil
            state.pendingChatSessionTitle = nil
            state.pendingChatWorkingDirectory = nil
        }
    }

    private func openSessionInNewTab(_ sessionId: String, title: String?, workingDirectory: String? = nil) {
        var newTab = ChatTab(title: title ?? String(sessionId.prefix(8)))
        newTab.sessionId = sessionId
        newTab.workingDirectory = workingDirectory
        state.chatTabs.append(newTab)
        state.selectedChatTabIndex = state.chatTabs.count - 1
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(state.chatTabs.indices, id: \.self) { i in
                        tabButton(index: i)
                    }
                }
                .padding(.leading, 12)
            }

            // Divider + new tab button pinned to the right
            Rectangle()
                .fill(theme.cardBorder)
                .frame(width: 0.5)
                .padding(.vertical, 8)

            Button {
                let newTab = ChatTab(title: "Chat \(state.chatTabs.count + 1)")
                state.chatTabs.append(newTab)
                state.selectedChatTabIndex = state.chatTabs.count - 1
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 36)
        .background(theme.windowBg)
        // No bottom overlay here — separator lives on the content area
    }

    private func tabButton(index: Int) -> some View {
        let isSelected = state.selectedChatTabIndex == index
        let tab = state.chatTabs[index]

        return HStack(spacing: 5) {
            if tab.isStreaming {
                ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
            } else if isSelected {
                Image(systemName: tab.agentId.isEmpty ? "bubble.left" : "cpu")
                    .font(.system(size: 9))
                    .foregroundStyle(accentColor)
            }
            Text(tab.title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.primaryText : theme.tertiaryText)
                .lineLimit(1)

            // Close button (only if more than 1 tab)
            if state.chatTabs.count > 1 {
                Button {
                    state.chatTabs.remove(at: index)
                    state.selectedChatTabIndex = max(0, min(state.selectedChatTabIndex, state.chatTabs.count - 1))
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 0)
        .frame(height: 36)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            if isSelected {
                accentColor
                    .frame(height: 3)
                    .offset(y: -0.5)
            }
        }
        .opacity(isSelected ? 1.0 : 0.45)
        .onTapGesture { state.selectedChatTabIndex = index }
        .frame(maxWidth: 160)
    }
}

// MARK: - Single Chat Session View (formerly ChatView internals)

struct SingleChatSessionView: View {
    @Binding var tab: ChatTab
    var isActive: Bool = true

    init(tab: Binding<ChatTab>, isActive: Bool = true) {
        self._tab = tab
        self.isActive = isActive
    }

    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var currentSessionId: String?
    @State private var isStreaming: Bool = false
    @State private var selectedModel: String = "claude-sonnet-4-6"
    @State private var selectedAgent: String = ""
    @State private var scrollProxy: ScrollViewProxy?
    @State private var errorMessage: String?
    @State private var attachedFiles: [AttachedFile] = []
    @State private var isDragOver: Bool = false
    @State private var sessionTitle: String = ""
    @State private var workingDirectory: String?
    @State private var gitBranch: String?
    @State private var gitBranches: [String] = []
    @State private var showBranchPicker = false
    @State private var selectedOrchestrators: Set<String> = []
    @State private var showModelPicker    = false
    @State private var showAgentPicker    = false
    @State private var showOrchPicker     = false
    @State private var showSnippetPicker  = false
    @State private var showPermPicker     = false
    @State private var showSlashMenu      = false
    @State private var showSnippetSheet   = false
    @State private var newSnippetTitle    = ""
    @State private var newSnippetText     = ""
    @State private var activeDiff: String?
    @State private var showFilePanel: Bool = false
    @State private var filePanelWidth: CGFloat = 220
    @State private var diffPanelWidth: CGFloat = 500
    @State private var filePreviewNode: ExplorerNode? = nil
    @State private var filePreviewPanelWidth: CGFloat = 380
    @State private var inputBarHeight: CGFloat = 56
    @AppStorage("chat.autoApprove") private var autoApprove: Bool = false
    @State private var isCompacting: Bool = false
    @State private var compactedSummary: String? = nil

    // MCP per-session selection
    @State private var availableMCPs: [MCPServer] = []
    @State private var activeMCPIds: Set<String> = []   // leer = alle aktiv
    @State private var mcpConfigs: [String: MCPServerConfig] = [:]
    @State private var showMCPPicker = false
    @State private var isLoadingMCPs = false

    private func closeAllPickers() {
        showModelPicker   = false
        showAgentPicker   = false
        showOrchPicker    = false
        showSnippetPicker = false
        showPermPicker    = false
        showBranchPicker  = false
        showMCPPicker     = false
    }
    @FocusState private var inputFocused: Bool

    private var orchestratorMode: Bool { !selectedOrchestrators.isEmpty }

    private let models = ["claude-sonnet-4-6", "claude-opus-4-6", "claude-haiku-4-5-20251001"]
    private let copilotModels = KnownModel.all.filter { $0.apiName.hasPrefix("github/") }

    private struct SlashCommand {
        let name: String
        let description: String
    }

    private let slashCommands: [SlashCommand] = [
        .init(name: "/clear",   description: "Chat-Verlauf löschen"),
        .init(name: "/new",     description: "Neue Session starten"),
        .init(name: "/compact", description: "Konversation komprimieren"),
        .init(name: "/files",   description: "Dateien in Kontext laden — z.B. /files *.swift"),
        .init(name: "/model",   description: "Modell wechseln"),
        .init(name: "/help",    description: "Verfügbare Befehle anzeigen"),
    ]

    private var filteredSlashCommands: [SlashCommand] {
        let q = inputText.lowercased()
        if q == "/" { return slashCommands }
        return slashCommands.filter { $0.name.lowercased().hasPrefix(q) }
    }

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var shortModelName: String {
        selectedModel
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20251001", with: "")
    }

    private var currentRouteSource: ChatProviderSource {
        if state.claudeRateLimitActive && state.settings.copilotFallbackEnabled {
            return .copilot
        }
        return inferredSource(from: selectedModel)
    }

    private func inferredSource(from model: String) -> ChatProviderSource {
        model.lowercased().hasPrefix("github/") ? .copilot : .claude
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Left: File Explorer Panel
                if showFilePanel {
                    ChatFilePanel(
                        rootPath: workingDirectory ?? NSHomeDirectory(),
                        onInsertPath: { path in
                            if inputText.isEmpty { inputText = path }
                            else { inputText += " \(path)" }
                            inputFocused = true
                        },
                        onSelectNode: { node in
                            withAnimation(.spring(response: 0.3)) { filePreviewNode = node }
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.3)) { showFilePanel = false }
                        }
                    )
                    .frame(width: filePanelWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    PanelResizeHandle(width: $filePanelWidth, minWidth: 160, maxWidth: 620, growsRight: true)
                        .frame(width: 10)
                }

                // Left: File Preview Panel (appears next to file tree)
                if let node = filePreviewNode, !node.isDirectory {
                    FilePreviewPanel(
                        node: node,
                        bottomGap: inputBarHeight,
                        onInsertPath: { path in
                            if inputText.isEmpty { inputText = path }
                            else { inputText += " \(path)" }
                            inputFocused = true
                        },
                        onClose: {
                            withAnimation(.spring(response: 0.3)) { filePreviewNode = nil }
                        }
                    )
                    .frame(width: filePreviewPanelWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    PanelResizeHandle(width: $filePreviewPanelWidth, minWidth: 240, maxWidth: 800, growsRight: true)
                        .frame(width: 10)
                }

                // Center: Chat area
                VStack(spacing: 0) {
                    // Header strip with panel toggles (right-aligned)
                    HStack(spacing: 2) {
                        Spacer()
                        Button {
                            withAnimation { state.hideSidebar.toggle() }
                        } label: {
                            Image(systemName: "sidebar.squares.left")
                                .font(.system(size: 11))
                                .foregroundStyle(state.hideSidebar ? accentColor : theme.secondaryText)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help(state.hideSidebar ? "Sidebar einblenden" : "Sidebar ausblenden")

                        Button {
                            withAnimation(.spring(response: 0.3)) { showFilePanel.toggle() }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 11))
                                .foregroundStyle(showFilePanel ? accentColor : theme.secondaryText)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help(showFilePanel ? "File Explorer schließen" : "File Explorer öffnen")

                        if activeDiff != nil {
                            Button {
                                withAnimation(.spring(response: 0.3)) { activeDiff = nil }
                            } label: {
                                Image(systemName: "sidebar.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(accentColor)
                                    .frame(width: 26, height: 26)
                            }
                            .buttonStyle(.plain)
                            .help("Diff-Panel schließen")
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 32)
                    .background(theme.windowBg)
                    .overlay(Rectangle().fill(theme.cardBorder).frame(height: 0.5), alignment: .bottom)

                    if messages.isEmpty {
                        emptyState.onTapGesture { closeAllPickers() }
                    } else {
                        messagesArea.onTapGesture { closeAllPickers() }
                    }

                    // Token Counter — direkt über der Texteingabe
                    let totalIn  = messages.filter { $0.role == .assistant }.reduce(0) { $0 + $1.inputTokens }
                    let totalOut = messages.filter { $0.role == .assistant }.reduce(0) { $0 + $1.outputTokens }
                    if totalIn > 0 || totalOut > 0 {
                        let threshold = state.settings.autoCompactThreshold
                        let isWarning  = threshold > 0 && totalIn >= threshold / 2
                        let isCritical = threshold > 0 && totalIn >= threshold
                        let tokenColor: Color = isCritical ? .red : (isWarning ? .orange : theme.secondaryText)
                        let progress: Double = threshold > 0 ? min(1.0, Double(totalIn) / Double(threshold)) : 0
                        let barColor: Color = isCritical ? .red : (isWarning ? .orange : .green)
                        VStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(tokenColor.opacity(0.7))
                                Text(totalIn >= 1000 ? String(format: "%.1fk", Double(totalIn) / 1000) : "\(totalIn)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(tokenColor)
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.tertiaryText.opacity(0.6))
                                Text(totalOut >= 1000 ? String(format: "%.1fk", Double(totalOut) / 1000) : "\(totalOut)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(theme.secondaryText)
                                Text("tokens")
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.tertiaryText.opacity(0.5))
                                if threshold > 0 {
                                    Text("/ \(threshold >= 1000 ? String(format: "%.0fk", Double(threshold) / 1000) : "\(threshold)")")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(theme.tertiaryText.opacity(0.4))
                                }
                                Spacer()
                                if isWarning && !isCompacting && !isStreaming {
                                    Button {
                                        compactSession()
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "scissors")
                                                .font(.system(size: 9, weight: .medium))
                                            Text(isCritical ? "Compact jetzt!" : "Compact")
                                                .font(.system(size: 10, weight: .medium))
                                        }
                                        .foregroundStyle(isCritical ? .red : .orange)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background((isCritical ? Color.red : Color.orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder((isCritical ? Color.red : Color.orange).opacity(0.3), lineWidth: 0.5))
                                    }
                                    .buttonStyle(.plain)
                                    .help(isCritical ? "Kontext-Limit erreicht — Konversation jetzt verdichten" : "Kontext ist halb voll — Konversation verdichten spart Tokens")
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 5)

                            // Context progress bar
                            if threshold > 0 {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        // Track
                                        Rectangle()
                                            .fill(theme.cardBorder.opacity(0.25))
                                            .frame(height: 3)
                                        // Fill
                                        Rectangle()
                                            .fill(barColor.opacity(0.75))
                                            .frame(width: geo.size.width * progress, height: 3)
                                            .animation(.easeInOut(duration: 0.4), value: progress)
                                        // Milestone at 50% — Zusammenfassung empfohlen
                                        Rectangle()
                                            .fill(theme.secondaryText.opacity(0.4))
                                            .frame(width: 1, height: 5)
                                            .offset(x: geo.size.width * 0.5 - 0.5, y: -1)
                                        // Milestone at 80% — dringend
                                        Rectangle()
                                            .fill(theme.secondaryText.opacity(0.4))
                                            .frame(width: 1, height: 5)
                                            .offset(x: geo.size.width * 0.8 - 0.5, y: -1)
                                    }
                                }
                                .frame(height: 3)
                                .help(isCritical ? "Kontext voll (\(Int(progress * 100))%) — Compact dringend empfohlen" : isWarning ? "Kontext halb voll (\(Int(progress * 100))%) — Zusammenfassung sinnvoll" : "Kontext-Auslastung: \(Int(progress * 100))%")
                            }
                        }
                        .background(isCritical ? Color.red.opacity(0.05) : theme.windowBg)
                        .help("Session-Tokens: \(totalIn) Input · \(totalOut) Output\(threshold > 0 ? " · Schwelle: \(threshold)" : "")")
                    }

                    inputBar
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: InputBarHeightKey.self, value: geo.size.height)
                        })
                }
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                .onPreferenceChange(InputBarHeightKey.self) { inputBarHeight = $0 }

                // Right: Diff side panel (resizable)
                if let diff = activeDiff {
                    PanelResizeHandle(width: $diffPanelWidth, minWidth: 320, maxWidth: 900, growsRight: false)
                        .frame(width: 10)
                    diffSidePanel(diff)
                        .frame(width: diffPanelWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isDragOver {
                dropOverlay
            }
        }
        .onDrop(of: [UTType.fileURL, UTType.image, UTType.png, UTType.jpeg], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $showSnippetSheet) { snippetSheet }
        .task { await loadAvailableMCPs() }
        .onAppear {
            inputFocused = true
            // Restore state from tab
            if !tab.inputText.isEmpty { inputText = tab.inputText }
            if let wd = tab.workingDirectory { workingDirectory = wd }
            fetchGitBranch()
            if let sid = tab.sessionId {
                currentSessionId = sid
                sessionTitle = tab.title
                selectedModel = tab.model
                selectedAgent = tab.agentId
                if tab.messages.isEmpty {
                    resumeSession(sid)
                } else {
                    messages = tab.messages
                }
            } else {
                messages = tab.messages
                selectedModel = tab.model
                selectedAgent = tab.agentId
            }
            // Proaktiv: wenn Claude-Limit aktiv + Fallback konfiguriert → Copilot-Modell setzen
            applyFallbackModelIfNeeded()
        }
        // Sync messages back to tab only when NOT streaming to avoid
        // parent re-renders on every streaming token (input lag fix)
        .onChange(of: messages) {
            if !isStreaming { tab.messages = messages }
        }
        .onChange(of: isStreaming) {
            // Sync streaming indicator to tab (shown in tab bar)
            tab.isStreaming = isStreaming
            // Flush final messages when streaming ends
            if !isStreaming { tab.messages = messages }
            // Compact-Abschluss verarbeiten
            if !isStreaming && isCompacting { finishCompact() }
        }
        .onChange(of: currentSessionId) { tab.sessionId = currentSessionId }
        .onChange(of: selectedModel) { tab.model = selectedModel }
        .onChange(of: selectedAgent) { tab.agentId = selectedAgent }
        .onChange(of: workingDirectory) {
            tab.workingDirectory = workingDirectory
            fetchGitBranch()
        }
        // Wenn Rate-Limit-Status sich ändert → Modell live umschalten
        .onChange(of: state.claudeRateLimitActive) {
            applyFallbackModelIfNeeded()
        }
        .onChange(of: state.pendingChatNewProject) {
            guard let path = state.pendingChatNewProject else { return }
            state.pendingChatNewProject = nil
            newSession()
            workingDirectory = path
            tab.title = URL(fileURLWithPath: path).lastPathComponent
            withAnimation(.spring(response: 0.3)) { showFilePanel = true }
        }
        // Save inputText and sync messages when switching away from this tab (opacity approach
        // keeps views alive, so onDisappear won't fire on tab switch)
        .onChange(of: isActive) {
            if !isActive {
                tab.inputText = inputText
                if isStreaming { tab.messages = messages }
            }
        }
        .onDisappear { tab.inputText = inputText }
    }

    private func resumeSession(_ sessionId: String) {
        messages = []
        currentSessionId = sessionId
        sessionTitle = tab.title
        errorMessage = nil

        Task {
            // Ensure projects are loaded before searching
            if state.historyService.projects.isEmpty {
                await state.historyService.loadProjects()
            }
            let allProjects = state.historyService.projects
            for project in allProjects {
                if let session = project.sessions.first(where: { $0.sessionId == sessionId }) {
                    let histMsgs = await state.historyService.loadMessages(for: session)
                    let chatMsgs = histMsgs.compactMap { hm -> ChatMessage? in
                        guard hm.role == .user || hm.role == .assistant else { return nil }
                        return ChatMessage(role: hm.role, content: hm.content)
                    }
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3)) {
                            messages = chatMsgs
                        }
                        inputFocused = true
                    }
                    return
                }
            }
        }
    }

    // MARK: - Drop Overlay

    private var dropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                )
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(accentColor)
                Text("Datei(en) ablegen")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text("Text, Code, Bilder und mehr")
                    .font(.system(size: 12))
                    .foregroundStyle(accentColor.opacity(0.7))
            }
        }
        .padding(12)
        .allowsHitTesting(false)
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        if !attachedFiles.contains(where: { $0.url == url }) {
                            attachedFiles.append(AttachedFile(url: url))
                        }
                    }
                }
                handled = true
            } else {
                // Handle raw image data (e.g. from Safari, Photos, screenshots)
                let imageType: String
                if provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) {
                    imageType = UTType.png.identifier
                } else if provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) {
                    imageType = UTType.jpeg.identifier
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    imageType = UTType.image.identifier
                } else {
                    continue
                }
                provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, _ in
                    guard let data else { return }
                    let ext = imageType == UTType.jpeg.identifier ? "jpg" : "png"
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension(ext)
                    try? data.write(to: tempURL)
                    DispatchQueue.main.async {
                        attachedFiles.append(AttachedFile(url: tempURL))
                    }
                }
                handled = true
            }
        }
        return handled
    }

    // MARK: - Subtle control strip (inside input card, bottom row)

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()

            HStack(spacing: 6) {
                Text(">_")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.tertiaryText)
                Text("Ask Claude anything")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
            }

            HStack(spacing: 8) {
                quickPrompt("Was kann Claude Code?")
                quickPrompt("Erklaere ein Konzept")
                quickPrompt("Hilf beim Debuggen")
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quickPrompt(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(theme.cardBorder, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Messages area

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(messages) { msg in
                        MessageBubbleView(message: msg) { diff in
                            withAnimation(.spring(response: 0.3)) {
                                activeDiff = diff
                            }
                        }
                        .id(msg.id)
                    }
                    if let err = errorMessage {
                        errorBubble(err)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: messages.count) {
                // Always scroll when messages are added (user send + assistant placeholder)
                // Use Task so layout settles before scrollTo fires
                scrollToBottom(proxy)
            }
            // Follow streaming output as it arrives
            .onChange(of: messages.last?.content) {
                scrollToBottom(proxy)
            }
            // Scroll once more when streaming ends (ensures final content visible)
            .onChange(of: isStreaming) {
                if !isStreaming { scrollToBottom(proxy) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        // Defer by one runloop so LazyVStack layout settles before scroll
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @State private var errorExpanded: Bool = false

    private func errorBubble(_ text: String) -> some View {
        let isLong = text.count > 120
        let displayText = isLong && !errorExpanded ? String(text.prefix(120)) + "…" : text
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                    .padding(.top, 1)
                Text(displayText)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isLong {
                Button(errorExpanded ? "Weniger anzeigen" : "Vollständige Fehlermeldung anzeigen") {
                    errorExpanded.toggle()
                }
                .font(.system(size: 11))
                .foregroundStyle(.red.opacity(0.8))
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.red.opacity(0.25), lineWidth: 0.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    // MARK: - Input bar

    private var canSend: Bool {
        let hasContent = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedFiles.isEmpty
        return hasContent && !isStreaming
    }

    // Medium themes (Slate/Pewter/Ash) sit on a mid-grey surface — use a clearly separated solid
    // background so the slash menu has enough contrast. Dark and light themes use their existing cardBg.
    private var slashMenuBg: Color {
        theme.isMedium ? Color(NSColor.windowBackgroundColor).opacity(0.96) : theme.cardBg
    }
    private var slashMenuBorder: Color {
        theme.isMedium ? Color(white: 0, opacity: 0.22) : theme.cardBorder
    }
    // Description text: ensure sufficient contrast on medium themes
    private var slashDescColor: Color {
        theme.isMedium ? Color(white: 0.18) : theme.secondaryText
    }

    private var slashMenuView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredSlashCommands.enumerated()), id: \.offset) { idx, cmd in
                Button {
                    inputText = cmd.name
                    showSlashMenu = false
                    sendMessage()
                } label: {
                    HStack(spacing: 8) {
                        Text(cmd.name)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(accentColor)
                        Text(cmd.description)
                            .font(.system(size: 11))
                            .foregroundStyle(slashDescColor)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                if idx < filteredSlashCommands.count - 1 {
                    Rectangle().fill(slashMenuBorder.opacity(0.6)).frame(height: 0.5)
                        .padding(.horizontal, 6)
                }
            }
        }
        .background(slashMenuBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(slashMenuBorder, lineWidth: 0.5))
        .shadow(color: .black.opacity(theme.isMedium ? 0.18 : 0.25), radius: 6, x: 0, y: -2)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            // MCP pill bar (when servers are configured and some are deactivated)
            if !availableMCPs.isEmpty {
                mcpPillBar
            }

            // File attachment chips
            if !attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachedFiles) { file in fileChip(file) }
                    }
                    .padding(.horizontal, 12).padding(.top, 8)
                }
            }

            // Slash command suggestions
            if showSlashMenu && !filteredSlashCommands.isEmpty {
                slashMenuView
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Text + send
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("let's build some awesome…")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(theme.tertiaryText.opacity(0.6))
                            .padding(.leading, 5).padding(.top, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $inputText)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                        .tint(accentColor)
                        .frame(minHeight: 16, maxHeight: 60)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .focused($inputFocused)
                        .onChange(of: inputText) {
                            let startsWithSlash = inputText.hasPrefix("/")
                            let hasSpace = inputText.contains(" ")
                            showSlashMenu = startsWithSlash && !hasSpace
                        }
                        .onKeyPress(.return) {
                            if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                            if showSlashMenu, let first = filteredSlashCommands.first {
                                // If the typed text exactly matches a command, execute it directly
                                let typed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if typed == first.name || filteredSlashCommands.count == 1 {
                                    inputText = first.name
                                    showSlashMenu = false
                                    sendMessage()
                                } else {
                                    inputText = first.name + " "
                                    showSlashMenu = false
                                }
                                return .handled
                            }
                            guard canSend else { return .handled }
                            sendMessage(); return .handled
                        }
                }

                VStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            messages = []
                            inputText = ""
                            attachedFiles = []
                        }
                    } label: {
                        // Avoid reading messages.isEmpty in inputBar — use isStreaming + inputText instead
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle((!inputText.isEmpty || !isStreaming) ? .red.opacity(0.75) : theme.tertiaryText.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Chat leeren")

                    Button {
                        isStreaming ? stopStreaming() : sendMessage()
                    } label: {
                        Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(isStreaming ? Color.red : (canSend ? accentColor : theme.tertiaryText.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend && !isStreaming)
                }
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            // ─── Subtle control strip ───
            controlStrip
        }
        .overlay(isDragOver ? RoundedRectangle(cornerRadius: 0).strokeBorder(accentColor.opacity(0.6), lineWidth: 1.5) : nil)
        .overlay(Rectangle().fill(theme.cardBorder).frame(height: 0.5), alignment: .top)
        .overlay(alignment: .bottomLeading) {
            // Picker dropdowns rendered HERE (inputBar level) — never clipped by the inner ScrollView
            pickerDropdownPanel
                .padding(.leading, 12)
                .padding(.bottom, 40) // push above control strip + bottom padding
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
    }

    // MARK: - Active picker panel (rendered at inputBar level, not inside ScrollView)

    @ViewBuilder
    private var pickerDropdownPanel: some View {
        let panelStyle = pickerPanelModifier
        if showMCPPicker {
            VStack(alignment: .leading, spacing: 0) {
                // Presets
                pickerSectionHeader("Presets")
                pickerRow(label: "⚡  Alle MCPs aktiv", selected: activeMCPIds.isEmpty) {
                    activeMCPIds = []; showMCPPicker = false
                }
                pickerRow(label: "○  Kein MCP (max. Token-Ersparnis)", selected: activeMCPIds == Set(["__none__"])) {
                    activeMCPIds = Set(["__none__"]); showMCPPicker = false
                }
                // Saved profiles from MCPView
                let savedProfiles: [MCPProfile] = {
                    guard let data = UserDefaults.standard.data(forKey: "mcpProfiles_v1"),
                          let p = try? JSONDecoder().decode([MCPProfile].self, from: data) else { return [] }
                    return p
                }()
                if !savedProfiles.isEmpty {
                    pickerSectionHeader("Profile")
                    ForEach(savedProfiles) { profile in
                        pickerRow(label: "◆  \(profile.name)  (\(profile.servers.count) Server)",
                                  selected: false) {
                            let ids = Set(profile.servers.map(\.name))
                            let matched = Set(availableMCPs.filter { ids.contains($0.name) }.map(\.id))
                            activeMCPIds = matched.isEmpty ? [] : matched
                            showMCPPicker = false
                        }
                    }
                }
                if !availableMCPs.isEmpty {
                    Rectangle().fill(theme.cardBorder).frame(height: 0.5).padding(.horizontal, 6)
                    pickerSectionHeader("Einzeln an/aus")
                    ForEach(availableMCPs) { server in
                        let allActive = activeMCPIds.isEmpty
                        let isActive = allActive || activeMCPIds.contains(server.id)
                        OrchRowView(
                            label: server.name,
                            selected: isActive && activeMCPIds != Set(["__none__"]),
                            accent: accentColor,
                            fg: theme.primaryText,
                            secondary: theme.tertiaryText
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if activeMCPIds == Set(["__none__"]) {
                                    activeMCPIds = [server.id]
                                } else if activeMCPIds.isEmpty {
                                    activeMCPIds = Set(availableMCPs.map(\.id)).subtracting([server.id])
                                } else if activeMCPIds.contains(server.id) {
                                    activeMCPIds.remove(server.id)
                                    if activeMCPIds.isEmpty { activeMCPIds = Set(["__none__"]) }
                                } else {
                                    activeMCPIds.insert(server.id)
                                    if activeMCPIds == Set(availableMCPs.map(\.id)) { activeMCPIds = [] }
                                }
                            }
                        }
                    }
                }
                // Token savings footer
                let disabledCount: Int = {
                    if activeMCPIds == Set(["__none__"]) { return availableMCPs.count }
                    if activeMCPIds.isEmpty { return 0 }
                    return availableMCPs.count - activeMCPIds.count
                }()
                if disabledCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                        Text("~\(disabledCount * 7)k Tokens gespart")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.06))
                }
            }
            .modifier(panelStyle)
        } else if showBranchPicker {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(gitBranches, id: \.self) { b in
                    pickerRow(label: b, selected: b == gitBranch) {
                        switchGitBranch(b); showBranchPicker = false
                    }
                }
            }
            .modifier(panelStyle)
        } else if showPermPicker {
            VStack(alignment: .leading, spacing: 0) {
                pickerRow(label: "🛡  Standard", selected: !autoApprove) {
                    autoApprove = false; showPermPicker = false
                }
                pickerRow(label: "⚡  Auto-Approve", selected: autoApprove) {
                    autoApprove = true; showPermPicker = false
                }
            }
            .modifier(panelStyle)
        } else if showModelPicker {
            VStack(alignment: .leading, spacing: 0) {
                pickerSectionHeader("Claude (Anthropic)")
                ForEach(models, id: \.self) { m in
                    pickerRow(label: m, selected: m == selectedModel) {
                        selectedModel = m; showModelPicker = false
                    }
                }
                pickerSectionHeader("GitHub Copilot")
                ForEach(copilotModels) { m in
                    pickerRow(label: m.name, selected: m.apiName == selectedModel) {
                        selectedModel = m.apiName; showModelPicker = false
                    }
                }
            }
            .modifier(panelStyle)
        } else if showAgentPicker {
            VStack(alignment: .leading, spacing: 0) {
                pickerRow(label: "Kein Agent", selected: selectedAgent.isEmpty) {
                    selectedAgent = ""; showAgentPicker = false
                }
                ForEach(state.agentService.agents) { a in
                    pickerRow(label: a.name, selected: selectedAgent == a.id) {
                        selectedAgent = a.id; showAgentPicker = false
                    }
                }
            }
            .modifier(panelStyle)
        } else if showOrchPicker {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(state.agentService.agents) { a in
                    orchRow(label: a.name, selected: selectedOrchestrators.contains(a.id)) {
                        if selectedOrchestrators.contains(a.id) {
                            selectedOrchestrators.remove(a.id)
                        } else {
                            selectedOrchestrators.insert(a.id)
                        }
                    }
                }
                if !selectedOrchestrators.isEmpty {
                    orchRow(label: "Auswahl aufheben", selected: false) {
                        selectedOrchestrators.removeAll(); showOrchPicker = false
                    }
                }
            }
            .modifier(panelStyle)
        } else if showSnippetPicker {
            VStack(alignment: .leading, spacing: 0) {
                if state.snippets.isEmpty {
                    Text("Keine Snippets")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                } else {
                    ForEach(state.snippets) { snippet in
                        SnippetRowView(
                            snippet: snippet,
                            accent: accentColor,
                            fg: theme.primaryText,
                            secondary: theme.tertiaryText
                        ) {
                            inputText = snippet.text; showSnippetPicker = false; inputFocused = true
                        } onDelete: {
                            state.snippets.removeAll { $0.id == snippet.id }
                        }
                    }
                    Rectangle().fill(theme.cardBorder).frame(height: 0.5).padding(.horizontal, 6)
                }
                pickerRow(label: "+ Snippet hinzufügen", selected: false) {
                    showSnippetPicker = false; newSnippetTitle = ""; newSnippetText = ""; showSnippetSheet = true
                }
            }
            .modifier(panelStyle)
        }
    }

    private var pickerPanelModifier: PickerPanelModifier {
        PickerPanelModifier(bg: theme.windowBg, border: theme.cardBorder)
    }

    // MARK: - MCP Pill Bar

    private var mcpPillBar: some View {
        let allActive = activeMCPIds.isEmpty
        let disabledCount = allActive ? 0 : (availableMCPs.count - activeMCPIds.count)
        let tokenSavings = disabledCount * 7  // rough ~7k tokens per server

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Icon + savings indicator
                HStack(spacing: 4) {
                    if isLoadingMCPs {
                        ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                    } else {
                        Image(systemName: "server.rack")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    if disabledCount > 0 {
                        Text("~\(tokenSavings)k ↓")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.leading, 4)

                // MCP server pills
                ForEach(availableMCPs) { server in
                    let isActive = allActive || activeMCPIds.contains(server.id)
                    mcpPill(server: server, isActive: isActive)
                }

                // Alle / Kein quick toggles
                if !allActive {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { activeMCPIds = [] }
                    } label: {
                        Text("Alle")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(theme.cardBg, in: Capsule())
                            .overlay(Capsule().strokeBorder(theme.cardBorder, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                if allActive || activeMCPIds.count > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            activeMCPIds = [] // will be treated as "deactivate all" below — but we need at least empty set to mean "none"
                            // "Kein MCP" = strict-mcp-config with empty JSON
                            activeMCPIds = Set(["__none__"])
                        }
                    } label: {
                        Text("Kein MCP")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(activeMCPIds == Set(["__none__"]) ? .red : theme.tertiaryText)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(activeMCPIds == Set(["__none__"]) ? Color.red.opacity(0.10) : theme.cardBg, in: Capsule())
                            .overlay(Capsule().strokeBorder(activeMCPIds == Set(["__none__"]) ? Color.red.opacity(0.4) : theme.cardBorder, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(theme.windowBg.opacity(0.6))
        .overlay(Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5), alignment: .bottom)
        .animation(.easeInOut(duration: 0.2), value: activeMCPIds)
    }

    private func mcpPill(server: MCPServer, isActive: Bool) -> some View {
        let isNone = activeMCPIds == Set(["__none__"])
        let effectiveActive = isNone ? false : isActive

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if activeMCPIds == Set(["__none__"]) {
                    // coming from "Kein MCP" → activate only this one
                    activeMCPIds = [server.id]
                } else if activeMCPIds.isEmpty {
                    // all were active → deactivate this one (add all others)
                    activeMCPIds = Set(availableMCPs.map(\.id)).subtracting([server.id])
                } else if activeMCPIds.contains(server.id) {
                    activeMCPIds.remove(server.id)
                    if activeMCPIds.isEmpty { activeMCPIds = Set(["__none__"]) }
                } else {
                    activeMCPIds.insert(server.id)
                    // if all are now active → reset to "all" mode
                    if activeMCPIds == Set(availableMCPs.map(\.id)) { activeMCPIds = [] }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(effectiveActive ? .green : theme.tertiaryText.opacity(0.3))
                    .frame(width: 5, height: 5)
                Text(server.name)
                    .font(.system(size: 10, weight: effectiveActive ? .medium : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(effectiveActive ? theme.primaryText : theme.tertiaryText)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(
                effectiveActive ? theme.cardBg : theme.cardBg.opacity(0.4),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    effectiveActive ? theme.cardBorder : theme.cardBorder.opacity(0.3),
                    lineWidth: 0.5
                )
            )
            .opacity(effectiveActive ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .help(effectiveActive ? "\(server.name) aktiv — klicken zum Deaktivieren" : "\(server.name) deaktiviert — klicken zum Aktivieren")
    }

    // MARK: - MCP Config JSON Builder

    private func buildMCPConfigJSON() async -> String? {
        // activeMCPIds leer = alle aktiv → kein --strict-mcp-config nötig
        guard !activeMCPIds.isEmpty else { return nil }
        // "__none__" = wirklich alle deaktivieren
        if activeMCPIds == Set(["__none__"]) {
            return "{\"mcpServers\":{}}"
        }

        var mcpServers: [String: Any] = [:]
        for server in availableMCPs where activeMCPIds.contains(server.id) {
            // Config lazy laden und cachen
            if mcpConfigs[server.id] == nil {
                if let cfg = await state.cliService.getMCPServerConfig(name: server.name) {
                    mcpConfigs[server.id] = cfg
                }
            }
            guard let config = mcpConfigs[server.id] else {
                // Fallback: HTTP/SSE ohne config → URL aus detail
                if server.type == "http" || server.type == "sse" {
                    mcpServers[server.name] = ["type": server.type, "url": server.detail]
                }
                continue
            }

            if config.transport == "stdio" {
                var entry: [String: Any] = ["type": "stdio", "command": config.commandOrUrl, "args": config.args]
                if !config.envVars.isEmpty {
                    var env: [String: String] = [:]
                    for kv in config.envVars {
                        let parts = kv.split(separator: "=", maxSplits: 1)
                        if parts.count == 2 { env[String(parts[0])] = String(parts[1]) }
                    }
                    entry["env"] = env
                }
                mcpServers[server.name] = entry
            } else {
                var entry: [String: Any] = ["type": config.transport, "url": config.commandOrUrl]
                if !config.headers.isEmpty {
                    var hdrs: [String: String] = [:]
                    for h in config.headers {
                        let parts = h.split(separator: ":", maxSplits: 1)
                        if parts.count == 2 { hdrs[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces) }
                    }
                    entry["headers"] = hdrs
                }
                mcpServers[server.name] = entry
            }
        }

        guard let data = try? JSONSerialization.data(withJSONObject: ["mcpServers": mcpServers]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    // MARK: - Load available MCPs

    private func loadAvailableMCPs() async {
        isLoadingMCPs = true
        defer { isLoadingMCPs = false }
        let servers = await state.cliService.listMCPServers()
        // Nur verbundene oder bekannte Server anzeigen
        availableMCPs = servers.filter {
            if case .error = $0.status { return false }
            return true
        }
    }

    // Generic upward-opening themed picker button — just the button, no overlay (overlay is at inputBar level)
    private func pickerButton<Content: View>(
        icon: String,
        label: String,
        active: Bool,
        isPresented: Binding<Bool>,
        measuredHeight: Binding<CGFloat> = .constant(0),
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Button {
            let wasOpen = isPresented.wrappedValue
            closeAllPickers()
            if !wasOpen { isPresented.wrappedValue = true }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(active ? accentColor : theme.tertiaryText)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(active ? accentColor : theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 80)
                Image(systemName: isPresented.wrappedValue ? "chevron.down" : "chevron.up")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(theme.tertiaryText.opacity(0.5))
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // Single row for single-select pickers (hover-capable)
    private func pickerRow(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        PickerRowView(label: label, selected: selected, accent: accentColor, fg: theme.primaryText, action: action)
    }

    private func pickerSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.tertiaryText)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Multi-select row for orchestrator (hover-capable)
    private func orchRow(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        OrchRowView(label: label, selected: selected, accent: accentColor, fg: theme.primaryText, secondary: theme.tertiaryText, action: action)
    }

    // Minimal icon row at the very bottom of the input card
    private var controlStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {
            // Attach file
            stripButton(icon: "paperclip", active: false, help: "Datei anhängen") {
                openFilePicker()
            }

            stripSep

            // Working directory
            stripDirButton

            // Git branch picker (only when workingDirectory is a git repo)
            if gitBranch != nil {
                stripSep
                pickerButton(
                    icon: "arrow.triangle.branch",
                    label: gitBranch ?? "",
                    active: false,
                    isPresented: $showBranchPicker
                ) {
                    ForEach(gitBranches, id: \.self) { b in
                        pickerRow(label: b, selected: b == gitBranch) {
                            switchGitBranch(b)
                            showBranchPicker = false
                        }
                    }
                }
            }

            stripSep

            // Permission mode
            pickerButton(
                icon: autoApprove ? "shield.slash.fill" : "shield.fill",
                label: autoApprove ? "Auto" : "Standard",
                active: autoApprove,
                isPresented: $showPermPicker
            ) {
                pickerRow(label: "🛡  Standard", selected: !autoApprove) {
                    autoApprove = false
                    showPermPicker = false
                }
                pickerRow(label: "⚡  Auto-Approve", selected: autoApprove) {
                    autoApprove = true
                    showPermPicker = false
                }
            }

            // MCP picker (nur wenn Server konfiguriert)
            if !availableMCPs.isEmpty {
                stripSep
                let mcpActive = !activeMCPIds.isEmpty
                let mcpLabel: String = {
                    if activeMCPIds == Set(["__none__"]) { return "Kein MCP" }
                    if activeMCPIds.isEmpty { return "MCPs (\(availableMCPs.count))" }
                    return "MCPs (\(activeMCPIds.count)/\(availableMCPs.count))"
                }()
                pickerButton(
                    icon: "server.rack",
                    label: mcpLabel,
                    active: mcpActive,
                    isPresented: $showMCPPicker
                ) { EmptyView() }
            }

            stripSep

            // Model picker
            pickerButton(
                icon: "cpu",
                label: shortModelName,
                active: false,
                isPresented: $showModelPicker
            ) {
                // Claude (Anthropic)
                pickerSectionHeader("Claude (Anthropic)")
                ForEach(models, id: \.self) { m in
                    pickerRow(label: m, selected: m == selectedModel) {
                        selectedModel = m
                        showModelPicker = false
                    }
                }
                // GitHub Copilot
                pickerSectionHeader("GitHub Copilot")
                ForEach(copilotModels) { m in
                    pickerRow(label: m.name, selected: m.apiName == selectedModel) {
                        selectedModel = m.apiName
                        showModelPicker = false
                    }
                }
            }
            .disabled(orchestratorMode)

            stripSep

            HStack(spacing: 4) {
                Image(systemName: currentRouteSource.icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(currentRouteSource.label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(currentRouteSource == .copilot ? .orange : accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                (currentRouteSource == .copilot ? Color.orange : accentColor).opacity(0.10),
                in: Capsule()
            )
            .help("Aktuelle Routing-Quelle")

            // Agent picker (single mode only)
            if !orchestratorMode && !state.agentService.agents.isEmpty {
                stripSep
                pickerButton(
                    icon: "person.crop.circle",
                    label: selectedAgent.isEmpty ? "Agent" :
                           (state.agentService.agents.first { $0.id == selectedAgent }?.name ?? "Agent"),
                    active: !selectedAgent.isEmpty,
                    isPresented: $showAgentPicker
                ) {
                    pickerRow(label: "Kein Agent", selected: selectedAgent.isEmpty) {
                        selectedAgent = ""
                        showAgentPicker = false
                    }
                    ForEach(state.agentService.agents) { a in
                        pickerRow(label: a.name, selected: selectedAgent == a.id) {
                            selectedAgent = a.id
                            showAgentPicker = false
                        }
                    }
                }
            }

            // Orchestrator multi-select picker
            if !state.agentService.agents.isEmpty {
                stripSep
                let orchLabel = selectedOrchestrators.isEmpty
                    ? "Orchestrator"
                    : "\(selectedOrchestrators.count) Agents"
                pickerButton(
                    icon: "square.stack.3d.up.fill",
                    label: orchLabel,
                    active: orchestratorMode,
                    isPresented: $showOrchPicker
                ) {
                    ForEach(state.agentService.agents) { a in
                        orchRow(label: a.name, selected: selectedOrchestrators.contains(a.id)) {
                            if selectedOrchestrators.contains(a.id) {
                                selectedOrchestrators.remove(a.id)
                            } else {
                                selectedOrchestrators.insert(a.id)
                            }
                        }
                    }
                    if !selectedOrchestrators.isEmpty {
                        orchRow(label: "Auswahl aufheben", selected: false, action: {
                            selectedOrchestrators.removeAll()
                            showOrchPicker = false
                        })
                    }
                }
            }

            stripSep

            // Snippets
            pickerButton(
                icon: "bolt.fill",
                label: "Snippets",
                active: false,
                isPresented: $showSnippetPicker
            ) {
                if state.snippets.isEmpty {
                    Text("Keine Snippets")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                } else {
                    ForEach(state.snippets) { snippet in
                        SnippetRowView(
                            snippet: snippet,
                            accent: accentColor,
                            fg: theme.primaryText,
                            secondary: theme.tertiaryText
                        ) {
                            inputText = snippet.text
                            showSnippetPicker = false
                            inputFocused = true
                        } onDelete: {
                            state.snippets.removeAll { $0.id == snippet.id }
                        }
                    }
                    Rectangle()
                        .fill(theme.cardBorder)
                        .frame(height: 0.5)
                        .padding(.horizontal, 6)
                }
                pickerRow(label: "+ Snippet hinzufügen", selected: false) {
                    showSnippetPicker = false
                    newSnippetTitle = ""
                    newSnippetText  = ""
                    showSnippetSheet = true
                }
            }

            Spacer()

            // Session resume badge
            if !sessionTitle.isEmpty {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 9))
                    .foregroundStyle(accentColor.opacity(0.5))
                Text(sessionTitle)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
                    .padding(.trailing, 4)
            }

            // New session
            stripButton(icon: "square.and.pencil", active: false, help: "Neue Session") {
                newSession()
            }
        }
        .padding(.horizontal, 8)
        }
        .padding(.bottom, 6)
    }

    private func stripButton(icon: String, active: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(active ? accentColor : theme.secondaryText.opacity(0.75))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var stripDirButton: some View {
        Button {
            openDirectoryPicker()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(workingDirectory != nil ? accentColor : theme.secondaryText.opacity(0.75))
                Text(workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "~")
                    .font(.system(size: 11))
                    .foregroundStyle(workingDirectory != nil ? accentColor : theme.secondaryText.opacity(0.75))
                    .lineLimit(1)
                    .frame(maxWidth: 90)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help("Arbeitsverzeichnis")
    }

    private func openDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"
        if let cwd = workingDirectory {
            panel.directoryURL = URL(fileURLWithPath: cwd)
        }
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }

    private func fetchGitBranch() {
        guard let cwd = workingDirectory, !cwd.isEmpty else {
            gitBranch = nil
            gitBranches = []
            return
        }
        Task.detached(priority: .utility) {
            // Current branch
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            let branch = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let current = (branch?.isEmpty == false && branch != "HEAD") ? branch : nil

            // All local branches
            let proc2 = Process()
            proc2.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc2.arguments = ["-C", cwd, "branch", "--format=%(refname:short)"]
            let pipe2 = Pipe()
            proc2.standardOutput = pipe2
            proc2.standardError = Pipe()
            try? proc2.run()
            proc2.waitUntilExit()
            let branchList = String(data: pipe2.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? []

            await MainActor.run {
                gitBranch = current
                gitBranches = branchList
            }
        }
    }

    private func switchGitBranch(_ branch: String) {
        guard let cwd = workingDirectory, !cwd.isEmpty else { return }
        Task.detached(priority: .utility) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["-C", cwd, "checkout", branch]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            await MainActor.run {
                gitBranch = branch
            }
        }
    }

    private var stripSep: some View {
        Rectangle()
            .fill(theme.cardBorder.opacity(0.6))
            .frame(width: 0.5, height: 12)
            .padding(.horizontal, 2)
    }

    private func fileChip(_ file: AttachedFile) -> some View {
        HStack(spacing: 4) {
            Image(systemName: file.isImage ? "photo" : "doc.text")
                .font(.system(size: 10))
                .foregroundStyle(file.isImage ? Color.blue : accentColor)
            Text(file.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)
            Button {
                attachedFiles.removeAll { $0.id == file.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                if !attachedFiles.contains(where: { $0.url == url }) {
                    attachedFiles.append(AttachedFile(url: url))
                }
            }
        }
    }

    // MARK: - Actions

    private func newSession() {
        withAnimation(.spring(response: 0.3)) {
            messages = []
            currentSessionId = nil
            errorMessage = nil
            attachedFiles = []
            sessionTitle = ""
        }
    }

    /// Setzt selectedModel auf das Copilot-Fallback-Modell wenn Claude-Limit aktiv ist.
    /// Wird bei onAppear und onChange(claudeRateLimitActive) aufgerufen.
    private func applyFallbackModelIfNeeded() {
        guard state.settings.copilotFallbackEnabled else { return }
        if state.claudeRateLimitActive {
            let fallback = state.settings.copilotFallbackModel
            if selectedModel != fallback {
                selectedModel = fallback
            }
        }
    }

    // MARK: - Orchestrator: run multiple agents in parallel

    private func sendOrchestrator() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        inputText = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, content: text))

        let agents = state.agentService.agents.filter { selectedOrchestrators.contains($0.id) }
        guard !agents.isEmpty else { return }

        isStreaming = true

        // Sequential orchestration: each agent receives the previous agents' outputs as context
        Task { @MainActor in
            var previousOutputs: [(name: String, output: String)] = []

            for agent in agents {
                var placeholder = ChatMessage(role: .assistant, content: "", isStreaming: true)
                placeholder.model = agent.name
                messages.append(placeholder)
                let idx = messages.count - 1

                // Build context-enriched message from prior agents
                let contextMessage: String
                if previousOutputs.isEmpty {
                    contextMessage = text
                } else {
                    let prior = previousOutputs
                        .map { "**\($0.name):**\n\($0.output)" }
                        .joined(separator: "\n\n")
                    contextMessage = """
                    Aufgabe: \(text)

                    ---
                    Vorherige Agenten-Analysen:
                    \(prior)

                    ---
                    Baue auf den obigen Ergebnissen auf und ergänze sie aus deiner Perspektive als \(agent.name).
                    """
                }

                messages[idx].content = "**[\(agent.name)]**\n"

                var agentOutput = ""
                var pendingContent = ""
                var tokenCount = 0

                let stream = state.cliService.send(
                    message: contextMessage,
                    sessionId: nil,
                    agentName: agent.id,
                    model: selectedModel,
                    workingDirectory: workingDirectory
                )
                do {
                    for try await event in stream {
                        if event.type == "assistant",
                           let content = event.message?.content {
                            for block in content {
                                switch block.type {
                                case "text":
                                    if let t = block.text, !t.isEmpty {
                                        agentOutput += t
                                        pendingContent += t
                                        tokenCount += 1
                                        if tokenCount >= 50 {
                                            messages[idx].content += pendingContent
                                            pendingContent = ""
                                            tokenCount = 0
                                        }
                                    }
                                case "tool_use":
                                    let name = block.name ?? "tool"
                                    messages[idx].toolCalls.append(ToolCall(
                                        name: name,
                                        input: block.toolInput?.displayText ?? "",
                                        toolUseId: block.id
                                    ))
                                default: break
                                }
                            }
                        }
                    }
                } catch {
                    messages[idx].content += "\n\n⚠️ \(error.localizedDescription)"
                }
                if !pendingContent.isEmpty {
                    messages[idx].content += pendingContent
                }
                messages[idx].isStreaming = false
                previousOutputs.append((name: agent.name, output: agentOutput))
            }

            isStreaming = false
        }
    }

    private var streamingTask: Task<Void, Never>? = nil

    private func stopStreaming() {
        streamingTask?.cancel()
        isStreaming = false
        if var last = messages.last, last.isStreaming {
            last.isStreaming = false
            messages[messages.count - 1] = last
        }
    }

    /// Builds the text message for the AI. Images are handled separately via buildImageAttachments().
    private func buildMessageWithAttachments(text: String, forGitHub: Bool = false) -> String {
        guard !attachedFiles.isEmpty else { return text }

        var parts: [String] = []

        for file in attachedFiles {
            if file.isText, let content = try? String(contentsOf: file.url, encoding: .utf8) {
                let ext = file.url.pathExtension.lowercased()
                let lang = ext.isEmpty ? "" : ext
                parts.append("**\(file.name)**\n```\(lang)\n\(content)\n```")
            } else if file.url.pathExtension.lowercased() == "pdf",
                      let pdf = PDFDocument(url: file.url) {
                var pdfText = ""
                for i in 0..<pdf.pageCount {
                    if let page = pdf.page(at: i),
                       let pageText = page.string, !pageText.isEmpty { pdfText += pageText + "\n" }
                }
                if !pdfText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append("**\(file.name)** (PDF, \(pdf.pageCount) Seiten)\n```\n\(pdfText.trimmingCharacters(in: .whitespacesAndNewlines))\n```")
                } else {
                    parts.append("**\(file.name)** (PDF, \(pdf.pageCount) Seiten — kein extrahierbarer Text, Pfad: `\(file.url.path)`)")
                }
            } else if file.isImage {
                if forGitHub {
                    // GitHub Models: image data sent separately as base64 — just mention name in text
                    parts.append("[Bild: \(file.name)]")
                } else {
                    // Claude CLI: ask Claude to read the image file via its tools
                    parts.append("[Bild angehängt: \(file.name), Pfad: \(file.url.path)\nBitte analysiere dieses Bild.]")
                }
            } else {
                parts.append("**\(file.name)** (Pfad: `\(file.url.path)`)")
            }
        }

        if !text.isEmpty { parts.append(text) }
        return parts.joined(separator: "\n\n")
    }

    /// Encodes all attached images as GitHubImageAttachments for vision-capable APIs.
    private func buildImageAttachments(from files: [AttachedFile]) -> [GitHubImageAttachment] {
        files.compactMap { file in
            guard file.isImage, let data = try? Data(contentsOf: file.url) else { return nil }
            let ext = file.url.pathExtension.lowercased()
            let mime: String
            switch ext {
            case "jpg", "jpeg": mime = "image/jpeg"
            case "gif":         mime = "image/gif"
            case "webp":        mime = "image/webp"
            default:            mime = "image/png"
            }
            return GitHubImageAttachment(mimeType: mime, base64Data: data.base64EncodedString())
        }
    }

    @discardableResult
    private func handleSlashCommand(_ cmd: String) -> Bool {
        let lower = cmd.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""
        showSlashMenu = false
        switch lower {
        case "/clear", "/new":
            newSession()
            return true
        case "/model":
            showModelPicker = true
            return true
        case "/compact":
            compactSession()
            return true
        case _ where lower.hasPrefix("/files"):
            let glob = String(lower.dropFirst("/files".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            loadFilesIntoContext(glob: glob.isEmpty ? "*" : glob)
            return true
        case "/help":
            let helpText = slashCommands
                .map { "**\($0.name)** — \($0.description)" }
                .joined(separator: "\n")
            messages.append(ChatMessage(role: .assistant, content: "**Verfügbare Slash-Befehle:**\n\n\(helpText)"))
            return true
        default:
            // unknown commands pass through to Claude
            return false
        }
    }

    /// Erstellt einen kompakten Dateibaum-String (wie `tree`) für ein Verzeichnis.
    /// Wird synchron aufgerufen — nur beim ersten Send (kurz genug dafür).
    private func buildFileTree(at path: String, maxDepth: Int) -> String {
        let fm = FileManager.default
        let baseURL = URL(fileURLWithPath: path)
        let ignoredNames: Set<String> = [".git", ".build", "node_modules", ".DS_Store",
                                          "build", "DerivedData", ".swp", "xcuserdata",
                                          ".xcworkspace", "Pods", ".gradle", "__pycache__"]
        var lines: [String] = []
        func traverse(_ url: URL, depth: Int, prefix: String) {
            guard depth <= maxDepth else { return }
            guard let children = try? fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles
            ) else { return }
            let sorted = children
                .filter { !ignoredNames.contains($0.lastPathComponent) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for (i, child) in sorted.enumerated() {
                let isLast = i == sorted.count - 1
                let connector = isLast ? "└── " : "├── "
                let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                lines.append("\(prefix)\(connector)\(child.lastPathComponent)\(isDir ? "/" : "")")
                if isDir {
                    let newPrefix = prefix + (isLast ? "    " : "│   ")
                    traverse(child, depth: depth + 1, prefix: newPrefix)
                }
            }
        }
        lines.append(baseURL.lastPathComponent + "/")
        traverse(baseURL, depth: 1, prefix: "")
        return lines.joined(separator: "\n")
    }

    /// Liest alle Dateien die dem Glob im workingDirectory entsprechen und fügt sie als
    /// Text-Attachments in den aktuellen Chat-Kontext ein (für alle Modelle nutzbar).
    private func loadFilesIntoContext(glob: String) {
        guard let cwd = workingDirectory, !cwd.isEmpty else {
            messages.append(ChatMessage(role: .assistant,
                content: "⚠️ Kein Arbeitsverzeichnis gesetzt. Bitte zuerst einen Ordner wählen."))
            return
        }
        inputText = ""
        showSlashMenu = false
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let baseURL = URL(fileURLWithPath: cwd)
            // Rekursiver Dateibaum mit maximal 3 Ebenen Tiefe
            guard let enumerator = fm.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                await MainActor.run {
                    self.messages.append(ChatMessage(role: .assistant,
                        content: "⚠️ Verzeichnis konnte nicht gelesen werden."))
                }
                return
            }

            // Glob-Muster in NSPredicate umwandeln
            let predicate = NSPredicate(format: "SELF LIKE %@", glob)

            var loaded: [(name: String, content: String)] = []
            var skipped = 0
            let maxFileSize = 80_000  // ~80KB pro Datei
            let maxFiles = 20

            for case let fileURL as URL in enumerator {
                guard loaded.count < maxFiles else { skipped += 1; continue }
                guard let vals = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                      vals.isRegularFile == true else { continue }

                let filename = fileURL.lastPathComponent
                // Depth check: maximal 3 Ebenen unter cwd
                let rel = fileURL.path.dropFirst(baseURL.path.count + 1)
                let depth = rel.components(separatedBy: "/").count
                guard depth <= 4 else { skipped += 1; continue }

                guard predicate.evaluate(with: filename) else { continue }

                guard let data = try? Data(contentsOf: fileURL),
                      data.count <= maxFileSize,
                      let text = String(data: data, encoding: .utf8) else {
                    skipped += 1
                    continue
                }
                let ext = fileURL.pathExtension.lowercased()
                loaded.append((name: String(rel), content: "```\(ext)\n\(text)\n```"))
            }

            await MainActor.run {
                if loaded.isEmpty {
                    self.messages.append(ChatMessage(role: .assistant,
                        content: "⚠️ Keine Dateien gefunden für `\(glob)` in `\(cwd)`."))
                    return
                }
                let summary = loaded.map { "**\($0.name)**\n\($0.content)" }.joined(separator: "\n\n")
                let note = skipped > 0 ? "\n\n*\(skipped) Datei(en) übersprungen (zu groß, binär oder Limit \(maxFiles) erreicht).*" : ""
                self.messages.append(ChatMessage(role: .assistant,
                    content: "📂 **\(loaded.count) Datei(en) geladen** (`\(glob)`):\(note)\n\n\(summary)"))
            }
        }
    }

    /// Sendet eine Verdichtungsanfrage an Claude. Nach Abschluss (über isCompacting-Flag)
    /// wird die Session zurückgesetzt und die Zusammenfassung als Kontext gespeichert.
    private func compactSession() {
        guard !messages.isEmpty, !isStreaming else { return }
        inputText = ""
        showSlashMenu = false
        let summaryPrompt = "Fasse unser bisheriges Gespräch in maximal 5 Sätzen zusammen. Antworte NUR mit der kompakten Zusammenfassung, ohne Kommentar oder Einleitung."
        messages.append(ChatMessage(role: .user, content: "⏳ Konversation wird verdichtet…"))
        var assistantMsg = ChatMessage(role: .assistant, content: "", isStreaming: true)
        assistantMsg.model = selectedModel
        messages.append(assistantMsg)
        let idx = messages.count - 1
        isStreaming = true
        isCompacting = true

        Task { @MainActor in
            await performSend(message: summaryPrompt, assistantIndex: idx, model: selectedModel)
        }
    }

    /// Wird nach Ende des Compact-Streams aufgerufen (via onChange(isStreaming)).
    private func finishCompact() {
        isCompacting = false
        guard let summary = messages.last?.content, !summary.isEmpty else { return }
        compactedSummary = summary
        // Neue Session starten — Summary bleibt als Kontext erhalten
        let summaryNote = ChatMessage(
            role: .assistant,
            content: "**Konversation verdichtet.** Zusammenfassung wird als Kontext für weitere Nachrichten verwendet:\n\n\(summary)"
        )
        withAnimation(.spring(response: 0.3)) {
            messages = [summaryNote]
            currentSessionId = nil
            errorMessage = nil
            sessionTitle = ""
        }
    }

    private func sendMessage() {
        if orchestratorMode && !selectedOrchestrators.isEmpty {
            sendOrchestrator()
            return
        }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Handle slash commands before normal send
        if text.hasPrefix("/"), !text.contains(" ") || text == "/compact" || text.hasPrefix("/files") {
            if handleSlashCommand(text) { return }
        }
        guard !text.isEmpty || !attachedFiles.isEmpty, !isStreaming else { return }

        // Prompt for working directory before first message of a new session
        if currentSessionId == nil, workingDirectory == nil {
            openDirectoryPicker()
        }

        let isGitHub = (state.claudeRateLimitActive && state.settings.copilotFallbackEnabled
            ? state.settings.copilotFallbackModel
            : selectedModel).hasPrefix("github/")
        let fullMessage = buildMessageWithAttachments(text: text, forGitHub: isGitHub)
        guard !fullMessage.isEmpty else {
            errorMessage = "Nachricht ist leer — bitte Text eingeben oder Datei anhängen."
            return
        }
        inputText = ""
        let sentFiles = attachedFiles
        attachedFiles = []
        errorMessage = nil

        var displayText = text
        if !sentFiles.isEmpty {
            let names = sentFiles.map { $0.name }.joined(separator: ", ")
            let prefix = "[\(sentFiles.count == 1 ? "Datei" : "\(sentFiles.count) Dateien"): \(names)]"
            displayText = text.isEmpty ? prefix : "\(prefix)\n\(text)"
        }

        // Auto-rename tab on first message
        if messages.isEmpty {
            let titleSource = text.isEmpty ? displayText : text
            let words = titleSource.split(separator: " ").prefix(5).joined(separator: " ")
            let trimmed = String(words.prefix(40))
            if !trimmed.isEmpty {
                tab.title = trimmed
            }
        }

        messages.append(ChatMessage(role: .user, content: displayText))

        let assistantMsg = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMsg)
        let assistantIndex = messages.count - 1

        isStreaming = true

        // Auto-detect agent via trigger keywords if none is manually selected
        let triggerAgent: String? = selectedAgent.isEmpty ? {
            let lower = text.lowercased()
            return state.agentService.agents.first { agent in
                agent.effectiveTriggers.contains { lower.contains($0.lowercased()) }
            }?.id
        }() : nil

        Task { @MainActor in
            let imageDirs = Array(Set(sentFiles.filter { $0.isImage }.map { $0.url.deletingLastPathComponent().path }))
            let imageAttachments = buildImageAttachments(from: sentFiles)
            await performSend(
                message: fullMessage,
                assistantIndex: assistantIndex,
                model: state.claudeRateLimitActive && state.settings.copilotFallbackEnabled
                    ? state.settings.copilotFallbackModel
                    : selectedModel,
                agentOverride: triggerAgent,
                addDirs: imageDirs,
                imageAttachments: imageAttachments
            )
        }
    }

    /// Executes the actual CLI send. Fallback is handled natively by `--fallback-model`.
    private func performSend(
        message: String,
        assistantIndex: Int,
        model: String,
        agentOverride: String? = nil,
        addDirs: [String] = [],
        imageAttachments: [GitHubImageAttachment] = [],
        isFallbackAttempt: Bool = false
    ) async {
        let source: ChatProviderSource = inferredSource(from: model)
        if messages.indices.contains(assistantIndex) {
            messages[assistantIndex].source = source
            if messages[assistantIndex].model == nil || messages[assistantIndex].model?.isEmpty == true {
                messages[assistantIndex].model = model
            }
        }

        // Fallback model for --fallback-model CLI flag (native overload handling)
        // Only pass --fallback-model when the current model is NOT already the fallback model
        let fallback: String? = (state.settings.copilotFallbackEnabled && model != state.settings.copilotFallbackModel)
            ? state.settings.copilotFallbackModel
            : nil

        let effectiveAgent = agentOverride ?? (selectedAgent.isEmpty ? nil : selectedAgent)

        // Inject agent system prompt (memory + write instruction + promptBody) on the first message of a session.
        // On resume (currentSessionId != nil) the session already carries the context — skip.
        let agentSystemPrompt: String? = (currentSessionId == nil)
            ? effectiveAgent.flatMap { agentId in
                state.agentService.agents.first { $0.id == agentId }
              }.map { state.agentService.fullSystemPrompt(for: $0) }
            : nil

        let stream: AsyncThrowingStream<StreamEvent, Error>

        if model.hasPrefix("github/") {
            // Direkt über GitHub Models API (CLI unterstützt github/ Provider nicht)
            // Sliding window: nur die letzten historyWindowSize Turns mitschicken um Input-Tokens zu sparen
            let windowSize = max(1, state.settings.historyWindowSize) * 2  // turns × 2 (user+assistant)
            let allHistory = messages.dropLast(2).filter { $0.role == .user || $0.role == .assistant }
            let windowedHistory = allHistory.count > windowSize ? Array(allHistory.dropFirst(allHistory.count - windowSize)) : Array(allHistory)
            let historyMsgs = windowedHistory.compactMap { msg -> GitHubMessage? in
                return GitHubMessage(role: msg.role == .user ? "user" : "assistant", content: msg.content)
            }
            // Projektkontext in System-Prompt injizieren (GitHub API hat keine --add-dir Option)
            var ghSystemPrompt = agentSystemPrompt ?? compactedSummary.map { "Konversationskontext (verdichtet):\n\($0)" }
            if let wd = workingDirectory, !wd.isEmpty {
                let projectName = URL(fileURLWithPath: wd).lastPathComponent
                // Option A: Dateibaum (max 3 Ebenen, ohne hidden/build) in System-Prompt
                let fileTree = buildFileTree(at: wd, maxDepth: 3)
                let treeSection = fileTree.isEmpty ? "" : "\n\nDateistruktur:\n```\n\(fileTree)\n```"
                let projectCtx = "Du arbeitest im Projekt '\(projectName)' im Verzeichnis: \(wd)\(treeSection)\n\nDu kannst Dateien aus diesem Projekt per /files <glob> in den Kontext laden (z.B. /files *.swift)."
                ghSystemPrompt = ghSystemPrompt.map { "\(projectCtx)\n\n\($0)" } ?? projectCtx
            }
            stream = state.ghModelsService.send(
                message: message,
                model: model,
                systemPrompt: ghSystemPrompt,
                history: Array(historyMsgs),
                githubToken: state.settings.token,
                imageAttachments: imageAttachments
            )
        } else {
            // Always include workingDirectory in --add-dir so Claude CLI can read project files
            var effectiveAddDirs = addDirs
            if let wd = workingDirectory, !wd.isEmpty, !effectiveAddDirs.contains(wd) {
                effectiveAddDirs.insert(wd, at: 0)
            }
            // Inject compacted summary as system prompt if no agent prompt is set
            let effectiveSystemPrompt = agentSystemPrompt ?? compactedSummary.map { "Konversationskontext (verdichtet):\n\($0)" }
            let effectiveMaxTurns = state.settings.maxTurns > 0 ? state.settings.maxTurns : nil
            let mcpJson = await buildMCPConfigJSON()
            stream = state.cliService.send(
                message: message,
                sessionId: currentSessionId,
                systemPrompt: effectiveSystemPrompt,
                model: model,
                fallbackModel: fallback,
                workingDirectory: workingDirectory,
                addDirs: effectiveAddDirs,
                skipPermissions: autoApprove,
                maxTurns: effectiveMaxTurns,
                mcpConfigJSON: mcpJson
            )
        }

        var pendingContent = ""
        var pendingTokenCount = 0

        do {
            for try await event in stream {
                if let sid = event.sessionId, currentSessionId == nil {
                    currentSessionId = sid
                }

                switch event.type {
                case "assistant":
                    if let content = event.message?.content {
                        for block in content {
                            switch block.type {
                            case "text":
                                if let t = block.text, !t.isEmpty {
                                    pendingContent += t
                                    pendingTokenCount += 1
                                    if pendingTokenCount >= 50 {
                                        messages[assistantIndex].content += pendingContent
                                        pendingContent = ""
                                        pendingTokenCount = 0
                                    }
                                }
                            case "tool_use":
                                // Flush buffer before showing tool use
                                if !pendingContent.isEmpty {
                                    messages[assistantIndex].content += pendingContent
                                    pendingContent = ""
                                    pendingTokenCount = 0
                                }
                                let name = block.name ?? "tool"
                                let tool = ToolCall(
                                    name: name,
                                    input: block.toolInput?.displayText ?? "",
                                    toolUseId: block.id
                                )
                                messages[assistantIndex].toolCalls.append(tool)
                            default: break
                            }
                        }
                    }
                    if let m = event.message?.model {
                        messages[assistantIndex].model = m
                    }
                    if let usage = event.message?.usage {
                        messages[assistantIndex].inputTokens = usage.inputTokens ?? 0
                        messages[assistantIndex].outputTokens = usage.outputTokens ?? 0
                    }

                    // Track rate-limit for UI indicator (--fallback-model handles the actual switch)
                    if event.error == "rate_limit" {
                        state.claudeRateLimitActive = true
                    }

                case "user":
                    // Tool result events — match by tool_use_id and store output
                    if let content = event.message?.content {
                        for block in content where block.type == "tool_result" {
                            guard let toolId = block.toolUseId,
                                  let resultText = block.toolResultText,
                                  !resultText.isEmpty else { continue }
                            if let idx = messages[assistantIndex].toolCalls.firstIndex(where: { $0.toolUseId == toolId }) {
                                // Cap output to 4000 chars to avoid blowing up the UI
                                messages[assistantIndex].toolCalls[idx].result = String(resultText.prefix(4000))
                            }
                        }
                    }

                case "rate_limit_event":
                    state.claudeRateLimitActive = true

                case "result":
                    messages[assistantIndex].costUsd = event.costUsd
                    // Token-Zählung aus result-Event übernehmen (GitHub Models liefert sie hier)
                    if let it = event.inputTokens,  it > 0 { messages[assistantIndex].inputTokens  = it }
                    if let ot = event.outputTokens, ot > 0 { messages[assistantIndex].outputTokens = ot }
                    if let sid = event.sessionId {
                        currentSessionId = sid
                    }

                    // Handle error result (e.g. rate-limit / usage-limit)
                    if event.isError == true {
                        let contentText = messages.indices.contains(assistantIndex)
                            ? messages[assistantIndex].content : ""
                        let eventResult = event.result ?? ""
                        let combined = (contentText + " " + eventResult).lowercased()

                        let isRateLimit = combined.contains("limit") || combined.contains("overloaded") ||
                            combined.contains("quota") || combined.contains("529") || combined.contains("429")

                        if isRateLimit {
                            state.claudeRateLimitActive = true
                            // Ablaufdatum aus Fehlermeldung extrahieren und speichern
                            state.parseRateLimitExpiry(from: contentText + " " + eventResult)
                            // Auto-Retry mit Fallback-Modell wenn aktiviert und noch kein Fallback-Versuch
                            if state.settings.copilotFallbackEnabled && !isFallbackAttempt {
                                if messages.indices.contains(assistantIndex) {
                                    messages[assistantIndex].content = ""
                                    messages[assistantIndex].toolCalls = []
                                    messages[assistantIndex].source = inferredSource(from: state.settings.copilotFallbackModel)
                                    messages[assistantIndex].model = nil
                                }
                                await performSend(
                                    message: message,
                                    assistantIndex: assistantIndex,
                                    model: state.settings.copilotFallbackModel,
                                    agentOverride: agentOverride,
                                    addDirs: addDirs,
                                    imageAttachments: imageAttachments,
                                    isFallbackAttempt: true
                                )
                                return
                            }
                        }

                        // Aussagekräftige Fehlermeldung: bevorzuge den tatsächlichen Fehlertext
                        let bestError: String
                        if !contentText.isEmpty {
                            bestError = contentText
                        } else if !eventResult.isEmpty {
                            bestError = eventResult
                        } else if let subtype = event.subtype, !subtype.isEmpty {
                            bestError = "Fehler: \(subtype)"
                        } else {
                            bestError = "Claude hat einen Fehler zurückgegeben (kein Fehlertext vom CLI erhalten)."
                        }
                        errorMessage = bestError
                        if messages.indices.contains(assistantIndex) {
                            messages[assistantIndex].isStreaming = false
                        }
                        isStreaming = false
                        return
                    }

                    // If CLI intercepted the message as a slash command (e.g. unknown skill),
                    // it may return text only in result.result without an assistant event.
                    // Also used by GitHub Models resultSuccess (accumulated full text).
                    // Clear pendingContent to prevent double-flush at end of loop.
                    if let resultText = event.result, !resultText.isEmpty,
                       messages.indices.contains(assistantIndex),
                       messages[assistantIndex].content.isEmpty {
                        // Flush any pending buffered tokens first; if there are any,
                        // they already contain the full text — don't overwrite with resultText.
                        if pendingContent.isEmpty {
                            messages[assistantIndex].content = resultText
                        } else {
                            messages[assistantIndex].content += pendingContent
                            pendingContent = ""
                            pendingTokenCount = 0
                        }
                    }

                    state.lastChatProvider = source
                    // Successful response — clear rate-limit flag
                    if state.claudeRateLimitActive { state.claudeRateLimitActive = false }

                default: break
                }
            }
        } catch {
            // Aussagekräftige Fehlermeldung aus CLIError extrahieren
            let displayError: String
            if let cliErr = error as? CLIError, case .processError(let code, let stderr) = cliErr {
                if !stderr.isEmpty {
                    displayError = "CLI-Fehler (exit \(code)): \(stderr)"
                } else {
                    displayError = "Claude CLI hat mit Exit-Code \(code) beendet. Mögliche Ursachen: Rate-Limit, Netzwerkfehler oder fehlerhafte Konfiguration."
                }
            } else {
                displayError = error.localizedDescription
            }
            print("⚠️ performSend error: \(displayError)")
            let errText = displayError.lowercased()

            let isRateLimit = errText.contains("limit") || errText.contains("overloaded") ||
                errText.contains("quota") || errText.contains("529") || errText.contains("429")

            // Track rate-limit for UI
            if isRateLimit {
                state.claudeRateLimitActive = true
                // Auto-Retry mit Fallback-Modell wenn aktiviert und noch kein Fallback-Versuch
                if state.settings.copilotFallbackEnabled && !isFallbackAttempt {
                    if messages.indices.contains(assistantIndex) {
                        messages[assistantIndex].content = ""
                        messages[assistantIndex].toolCalls = []
                        messages[assistantIndex].source = inferredSource(from: state.settings.copilotFallbackModel)
                        messages[assistantIndex].model = nil
                    }
                    await performSend(
                        message: message,
                        assistantIndex: assistantIndex,
                        model: state.settings.copilotFallbackModel,
                        agentOverride: agentOverride,
                        addDirs: addDirs,
                        imageAttachments: imageAttachments,
                        isFallbackAttempt: true
                    )
                    return
                }
            }

            errorMessage = displayError
            if messages.indices.contains(assistantIndex),
               messages[assistantIndex].content.isEmpty,
               messages[assistantIndex].toolCalls.isEmpty {
                messages.remove(at: assistantIndex)
            } else if messages.indices.contains(assistantIndex) {
                messages[assistantIndex].isStreaming = false
            }
            isStreaming = false
            return
        }

        // Flush any remaining buffered tokens
        if !pendingContent.isEmpty, messages.indices.contains(assistantIndex) {
            messages[assistantIndex].content += pendingContent
        }

        if messages.indices.contains(assistantIndex) {
            messages[assistantIndex].isStreaming = false
        }

        state.lastChatProvider = source
        // Accumulate Copilot / GitHub tokens in sidebar counter (subscription = $0 cost)
        if source == .copilot, messages.indices.contains(assistantIndex) {
            let it = messages[assistantIndex].inputTokens
            let ot = messages[assistantIndex].outputTokens
            if it > 0 || ot > 0 { state.addCopilotUsage(inputTokens: it, outputTokens: ot) }
        }
        isStreaming = false

        // Auto-Compact: wenn Input-Tokens die Schwelle überschreiten, automatisch verdichten
        if !isFallbackAttempt && !isCompacting {
            let threshold = state.settings.autoCompactThreshold
            if threshold > 0 {
                let totalIn = messages.filter { $0.role == .assistant }.reduce(0) { $0 + $1.inputTokens }
                if totalIn >= threshold {
                    compactSession()
                    return
                }
            }
        }

        // Record session learnings in agent memory log
        if let agentId = effectiveAgent,
           messages.indices.contains(assistantIndex) {
            let output = messages[assistantIndex].content
            state.agentService.recordChatSession(agentId: agentId, output: output)
        }

        // If tool calls were made, fetch git diff to show changed files
        if messages.indices.contains(assistantIndex),
           !messages[assistantIndex].toolCalls.isEmpty,
           let cwd = workingDirectory {
            if let diff = await fetchGitDiff(in: cwd), !diff.isEmpty {
                messages[assistantIndex].gitDiff = diff
            }
        }

        // ── History sync ──────────────────────────────────────────────
        if model.hasPrefix("github/") {
            // GitHub Copilot chats bypass the CLI → save to ~/.claude history ourselves
            let sid = currentSessionId ?? UUID().uuidString
            if currentSessionId == nil { currentSessionId = sid }
            let projPath = workingDirectory ?? NSHomeDirectory()
            let snapshot = messages  // capture current state
            state.historyService.saveGitHubChat(
                sessionId: sid,
                projectPath: projPath,
                messages: snapshot,
                model: model
            )
            // Reload after write (on background queue) completes (~300 ms)
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await state.historyService.loadProjects()
            }
        } else {
            // Claude CLI writes to history.jsonl itself; reload after a short delay
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                await state.historyService.loadProjects()
            }
        }
    }

    private func fetchGitDiff(in directory: String) async -> String? {
        await withCheckedContinuation { continuation in
            Task.detached(priority: .utility) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["diff", "HEAD"]
                process.currentDirectoryURL = URL(fileURLWithPath: directory)
                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError  = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(returning: output.isEmpty ? nil : output)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Diff Side Panel (right column)

    private func diffSidePanel(_ diff: String) -> some View {
        let files = parseDiffFiles(diff)
        let added   = diff.components(separatedBy: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
        let removed = diff.components(separatedBy: "\n").filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count

        return VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.mint)
                Text("Codeänderungen")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Spacer()

                Text("+\(added)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.green)
                Text("-\(removed)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)

                // Copy diff
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diff, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Diff kopieren")

                // Close panel
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        activeDiff = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Panel schließen")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(theme.windowBg)

            Rectangle().fill(theme.cardBorder).frame(height: 0.5)

            // File list summary
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.tertiaryText)
                Text("\(files.count) Datei\(files.count == 1 ? "" : "en")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(theme.cardBg.opacity(0.3))

            Rectangle().fill(theme.cardBorder).frame(height: 0.5)

            // Scrollable diff content
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                        diffSideFileSection(file)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(white: theme.isLight ? 0.96 : 0.06))
    }

    private func diffSideFileSection(_ file: DiffFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // File name header
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.tertiaryText)
                Text(file.name)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                Spacer()
                Text("+\(file.additions) -\(file.deletions)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(white: theme.isLight ? 0.88 : 0.12))

            // Diff lines
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(file.lines.enumerated()), id: \.offset) { _, line in
                    diffSideLine(line)
                }
            }
            .padding(.vertical, 4)

            Divider().opacity(0.2)
        }
    }

    private func diffSideLine(_ line: String) -> some View {
        let isAdd    = line.hasPrefix("+") && !line.hasPrefix("+++")
        let isRemove = line.hasPrefix("-") && !line.hasPrefix("---")
        let isHunk   = line.hasPrefix("@@")
        let isMeta   = line.hasPrefix("diff") || line.hasPrefix("index") || line.hasPrefix("---") || line.hasPrefix("+++")

        let bg: Color = isAdd    ? .green.opacity(0.12)
                      : isRemove ? .red.opacity(0.12)
                      : isHunk   ? Color(white: theme.isLight ? 0.82 : 0.15)
                      : .clear
        let fg: Color = isAdd    ? .green
                      : isRemove ? .red
                      : isHunk   ? .blue.opacity(0.7)
                      : isMeta   ? theme.tertiaryText
                      : theme.primaryText

        return Text(line.isEmpty ? " " : line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(fg)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 1)
            .background(bg)
    }
}

// MARK: - Panel Resize Handle

// NSViewRepresentable-based resize handle — survives SwiftUI re-renders during drag
struct PanelResizeHandle: NSViewRepresentable {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    /// true = rechte Kante des linken Panels (drag right → wider)
    /// false = linke Kante des rechten Panels (drag left → wider)
    let growsRight: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(width: $width, minWidth: minWidth, maxWidth: maxWidth, growsRight: growsRight)
    }

    func makeNSView(context: Context) -> ResizeDragNSView {
        ResizeDragNSView(coordinator: context.coordinator)
    }

    func updateNSView(_ nsView: ResizeDragNSView, context: Context) {
        context.coordinator.width    = $width
        context.coordinator.minWidth = minWidth
        context.coordinator.maxWidth = maxWidth
        context.coordinator.growsRight = growsRight
    }

    // MARK: Coordinator — holds mutable state across re-renders
    class Coordinator {
        var width: Binding<CGFloat>
        var minWidth: CGFloat
        var maxWidth: CGFloat
        var growsRight: Bool

        init(width: Binding<CGFloat>, minWidth: CGFloat, maxWidth: CGFloat, growsRight: Bool) {
            self.width = width
            self.minWidth = minWidth
            self.maxWidth = maxWidth
            self.growsRight = growsRight
        }
    }
}

// MARK: AppKit view — mouse events bypass SwiftUI gestures entirely
class ResizeDragNSView: NSView {
    weak var coordinator: PanelResizeHandle.Coordinator?

    init(coordinator: PanelResizeHandle.Coordinator) {
        self.coordinator = coordinator
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) { /* capture mouse */ }

    override func mouseDragged(with event: NSEvent) {
        guard let coord = coordinator else { return }
        let raw = coord.growsRight ? event.deltaX : -event.deltaX
        let newW = max(coord.minWidth, min(coord.maxWidth, coord.width.wrappedValue + raw))
        coord.width.wrappedValue = newW
    }

    override func draw(_ dirtyRect: NSRect) {
        // Subtle center line only
        NSColor.separatorColor.withAlphaComponent(0.25).setFill()
        NSRect(x: (bounds.width - 1) / 2, y: 0, width: 1, height: bounds.height).fill()
    }
}

// MARK: - Chat File Panel

struct ChatFilePanel: View {
    let rootPath: String
    let onInsertPath: (String) -> Void
    let onSelectNode: (ExplorerNode?) -> Void
    let onClose: () -> Void

    @Environment(\.appTheme) var theme
    @State private var rootNode: ExplorerNode?
    @State private var selectedNode: ExplorerNode?
    @State private var showHidden = false
    @State private var currentRoot: String = ""

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(accentColor)
                Text(URL(fileURLWithPath: rootPath).lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Spacer()
                Button {
                    showHidden.toggle()
                    reload()
                } label: {
                    Image(systemName: showHidden ? "eye.fill" : "eye.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(showHidden ? accentColor : theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Versteckte Dateien")

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: rootPath))
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Im Finder öffnen")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Schließen")
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(theme.windowBg)

            Rectangle().fill(theme.cardBorder).frame(height: 0.5)

            // Tree only — preview is shown in the right panel
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if let root = rootNode {
                        ForEach(root.children ?? []) { node in
                            ChatFilePanelRow(
                                node: node,
                                selectedId: selectedNode?.id,
                                showHidden: showHidden,
                                depth: 0,
                                onSelect: selectNode,
                                onInsert: { onInsertPath($0.url.path) }
                            )
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.windowBg)
        .onAppear { load() }
        .onChange(of: rootPath) { load() }
    }

    private func load() {
        guard currentRoot != rootPath else { return }
        currentRoot = rootPath
        let node = ExplorerNode(url: URL(fileURLWithPath: rootPath))
        node.loadChildren(showHidden: showHidden)
        rootNode = node
        selectedNode = nil
        onSelectNode(nil)
    }

    private func reload() {
        currentRoot = ""
        load()
    }

    private func selectNode(_ node: ExplorerNode) {
        selectedNode = node
        onSelectNode(node.isDirectory ? nil : node)
    }
}

// MARK: - PDF Preview

struct PDFPreviewView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = false
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document {
            view.document = document
        }
    }
}

// MARK: - Syntax Highlighter

struct SyntaxHighlighter {
    // One Dark Pro palette
    static func highlight(_ text: String, fileExtension ext: String, isDark: Bool) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = isDark ? Color(white: 0.86) : Color(white: 0.12)
        result.font = .system(size: 11, design: .monospaced)

        // Colors
        let cComment = Color(white: isDark ? 0.46 : 0.52)              // grey
        let cString  = Color(red: 0.60, green: 0.76, blue: 0.47)      // #98c379 green
        let cKeyword = Color(red: 0.78, green: 0.47, blue: 0.87)      // #c678dd purple
        let cNumber  = Color(red: 0.82, green: 0.61, blue: 0.40)      // #d19a66 gold
        let cFunc    = Color(red: 0.38, green: 0.69, blue: 0.94)      // #61afef blue
        let cType    = Color(red: 0.90, green: 0.75, blue: 0.48)      // #e5c07b yellow
        let cAttr    = Color(red: 0.94, green: 0.61, blue: 0.46)      // orange
        let cProp    = Color(red: 0.89, green: 0.55, blue: 0.55)      // red-pink

        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var painted: [NSRange] = []

        func hits(_ r: NSRange) -> Bool { painted.contains { NSIntersectionRange($0, r).length > 0 } }
        func paint(_ c: Color, _ r: NSRange) {
            guard let sr = Range(r, in: text),
                  let lo = AttributedString.Index(sr.lowerBound, within: result),
                  let hi = AttributedString.Index(sr.upperBound, within: result) else { return }
            result[lo..<hi].foregroundColor = c
            painted.append(r)
        }
        func rx(_ pattern: String, _ color: Color, dot: Bool = false, skip: Bool = true) {
            let opts: NSRegularExpression.Options = dot ? [.dotMatchesLineSeparators] : []
            guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return }
            for m in re.matches(in: text, range: full) {
                if skip && hits(m.range) { continue }
                paint(color, m.range)
            }
        }

        // ── Markdown fast path ──────────────────────────────────────────
        if ext == "md" {
            rx("^#{1,6} .+$", cType)
            rx("\\*\\*[^*\\n]+\\*\\*", cKeyword)
            rx("(?<!\\*)\\*(?!\\*)[^*\\n]+\\*(?!\\*)", cComment)
            rx("`[^`\\n]+`", cString)
            rx("^```[\\s\\S]*?^```", cString, dot: true)
            rx("^([-*+]|\\d+\\.) ", cFunc)
            rx("\\[[^\\]]+\\]\\([^)]+\\)", cAttr)
            return result
        }

        // ── 1. Comments (no skip — highest priority) ─────────────────────
        switch ext {
        case "html","htm":        rx("<!--[\\s\\S]*?-->", cComment, dot: true, skip: false)
        case "css","scss":        rx("/\\*[\\s\\S]*?\\*/", cComment, dot: true, skip: false)
        case "py","sh","bash","zsh","yml","yaml","toml","rb":
                                  rx("#[^\n]*", cComment, skip: false)
        default:
            rx("/\\*[\\s\\S]*?\\*/", cComment, dot: true, skip: false)
            rx("//[^\n]*", cComment, skip: false)
        }

        // ── 2. Strings ───────────────────────────────────────────────────
        switch ext {
        case "html","htm":
            rx("\"[^\"\\n]*\"", cString); rx("'[^'\\n]*'", cString)
            rx("</?[a-zA-Z][a-zA-Z0-9-]*", cKeyword)
            rx("\\b[a-z-]+=", cAttr)
        case "json":
            rx("\"(?:[^\"\\\\]|\\\\.)*\"\\s*:", cType)        // keys
            rx(":\\s*\"(?:[^\"\\\\]|\\\\.)*\"", cString)      // string values
        case "css","scss":
            rx("\"[^\"\\n]*\"|'[^'\\n]*'", cString)
            rx("[.#][a-zA-Z][a-zA-Z0-9_-]*", cFunc)
            rx(":[a-zA-Z-]+", cAttr)
            rx("\\b(\\d+)(px|em|rem|vh|vw|%|s|ms|deg)\\b", cNumber)
        default:
            rx("\"\"\"[\\s\\S]*?\"\"\"", cString, dot: true)  // triple-quoted
            rx("\"(?:[^\"\\\\]|\\\\.)*\"", cString)
            rx("'(?:[^'\\\\]|\\\\.)*'", cString)
            if ext != "rs" { rx("`[^`\\n]*`", cString) }
        }

        // ── 3. Keywords ──────────────────────────────────────────────────
        let kws: [String]
        switch ext {
        case "swift":
            kws = ["import","class","struct","enum","protocol","extension","func","var","let",
                   "if","else","guard","return","true","false","nil","self","super","init","deinit",
                   "override","final","static","private","public","internal","open","fileprivate",
                   "mutating","nonmutating","lazy","weak","unowned","throws","rethrows","throw",
                   "try","catch","do","for","in","while","repeat","break","continue","switch",
                   "case","default","where","as","is","any","some","async","await","actor",
                   "nonisolated","typealias","associatedtype","subscript","inout","indirect",
                   "willSet","didSet","get","set","consuming","borrowing"]
        case "py":
            kws = ["import","from","class","def","if","elif","else","for","while","return",
                   "True","False","None","and","or","not","in","is","with","as","try","except",
                   "finally","raise","pass","break","continue","lambda","yield","global",
                   "nonlocal","del","assert","async","await","match","case","print","len","range"]
        case "js","jsx":
            kws = ["import","export","default","from","require","class","extends","const","let",
                   "var","function","return","if","else","for","while","do","switch","case","break",
                   "continue","new","this","typeof","instanceof","in","of","try","catch","finally",
                   "throw","async","await","true","false","null","undefined","void","delete","yield",
                   "static","super","get","set","debugger"]
        case "ts","tsx":
            kws = ["import","export","default","from","class","extends","implements","const","let",
                   "var","function","return","if","else","for","while","do","switch","case","break",
                   "continue","new","this","typeof","instanceof","in","of","try","catch","finally",
                   "throw","async","await","true","false","null","undefined","void","delete","yield",
                   "static","super","type","interface","enum","namespace","declare","abstract",
                   "readonly","as","is","keyof","infer","satisfies","override","accessor"]
        case "go":
            kws = ["import","package","func","var","const","type","struct","interface","map",
                   "chan","go","defer","return","if","else","for","range","switch","case","default",
                   "break","continue","fallthrough","select","true","false","nil","make","new",
                   "len","cap","append","copy","close","delete","panic","recover"]
        case "rs":
            kws = ["use","mod","pub","crate","fn","let","mut","const","static","ref","struct",
                   "enum","impl","trait","type","for","in","if","else","loop","while","match",
                   "return","break","continue","where","as","dyn","move","unsafe","extern",
                   "true","false","self","Self","super","async","await"]
        case "java":
            kws = ["import","package","class","interface","enum","extends","implements","public",
                   "private","protected","static","final","abstract","void","return","if","else",
                   "for","while","do","switch","case","default","break","continue","new","this",
                   "super","throws","throw","try","catch","finally","true","false","null",
                   "synchronized","volatile","instanceof","record","sealed","permits"]
        case "kt":
            kws = ["import","package","class","interface","object","enum","fun","val","var",
                   "return","if","else","when","for","while","do","break","continue","in","is",
                   "as","try","catch","finally","throw","true","false","null","this","super",
                   "companion","data","sealed","open","override","abstract","private","public",
                   "internal","protected","inline","reified","suspend","by","init","constructor",
                   "lazy","lateinit","const","typealias","tailrec"]
        case "sh","bash","zsh":
            kws = ["if","then","else","elif","fi","for","while","until","do","done","case","in",
                   "esac","function","return","exit","break","continue","local","export","readonly",
                   "source","echo","printf","read","true","false","unset"]
        case "json":
            kws = ["true","false","null"]
        default:
            kws = []
        }
        if !kws.isEmpty {
            rx("\\b(" + kws.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")\\b", cKeyword)
        }

        // ── 4. Numbers ───────────────────────────────────────────────────
        rx("\\b0x[0-9A-Fa-f]+\\b", cNumber)
        rx("\\b\\d+\\.\\d+([eE][+-]?\\d+)?[fFdD]?\\b", cNumber)
        rx("\\b\\d+[lLuU]?\\b", cNumber)

        // ── 5. Decorators / compiler directives ─────────────────────────
        if ["swift","py","kt","java","ts","tsx","js","jsx"].contains(ext) {
            rx("@[A-Za-z_][A-Za-z0-9_]*", cAttr)
        }
        if ext == "swift" {
            rx("#(if|else|elseif|endif|available|unavailable|selector|keyPath|warning|error|function|file|line)\\b", cAttr)
        }

        // ── 6. PascalCase types ─────────────────────────────────────────
        if ["swift","kt","java","ts","tsx","rs","go"].contains(ext) {
            rx("\\b[A-Z][A-Za-z0-9]{1,}\\b", cType)
        }

        // ── 7. Function/method calls ─────────────────────────────────────
        if ["swift","py","js","jsx","ts","tsx","kt","java","go","rs"].contains(ext) {
            rx("\\b([a-z_][a-zA-Z0-9_]*)(?=\\s*\\()", cFunc)
        }

        // ── 8. Object properties (dot access) ────────────────────────────
        if ["swift","js","jsx","ts","tsx","kt"].contains(ext) {
            rx("(?<=\\.)([a-z_][a-zA-Z0-9_]*)(?!\\s*\\()", cProp)
        }

        return result
    }
}

// MARK: - File Preview Panel (right side)

private struct InputBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 56
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct FilePreviewPanel: View {
    let node: ExplorerNode
    let bottomGap: CGFloat
    let onInsertPath: (String) -> Void
    let onClose: () -> Void

    @Environment(\.appTheme) var theme
    @State private var previewText: String? = nil
    @State private var highlightedText: AttributedString? = nil
    @State private var pdfDocument: PDFDocument? = nil
    @State private var nsImage: NSImage? = nil
    @State private var isLoading = false

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var isImageFile: Bool {
        ["png","jpg","jpeg","gif","bmp","tiff","tif","webp","heic","ico"].contains(node.fileExtension)
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ───────────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: node.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(node.iconColor)
                Text(node.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Spacer()
                Button { onInsertPath(node.url.path) } label: {
                    Label("Einfügen", systemImage: "text.badge.plus")
                        .font(.system(size: 10))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
                .help("Pfad in Chat einfügen")
                Button { NSWorkspace.shared.open(node.url) } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Im Finder öffnen")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Vorschau schließen")
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(theme.windowBg)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.cardBorder).frame(height: 0.5)
            }

            // ── Content ───────────────────────────────────────────────────
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                ScrollView {
                    Group {
                        if let hl = highlightedText {
                            Text(hl)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        } else {
                            Text(text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: node.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(node.iconColor.opacity(0.4))
                    Text("Keine Vorschau verfügbar")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // ── Bottom gap matching input bar height ──────────────────────
            theme.windowBg
                .frame(height: bottomGap)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.windowBg)
        .onAppear { loadContent() }
        .onChange(of: node.id) { loadContent() }
    }

    private func loadContent() {
        previewText = nil
        highlightedText = nil
        pdfDocument = nil
        nsImage = nil
        isLoading = false
        if node.isPDF {
            pdfDocument = PDFDocument(url: node.url)
        } else if isImageFile {
            isLoading = true
            let url = node.url
            Task.detached(priority: .userInitiated) {
                let img = NSImage(contentsOf: url)
                await MainActor.run { nsImage = img; isLoading = false }
            }
        } else if node.isTextFile {
            isLoading = true
            let ext = node.fileExtension
            let url = node.url
            let isDark = !theme.isLight
            Task.detached(priority: .userInitiated) {
                let text = (try? String(contentsOf: url, encoding: .utf8))
                    ?? (try? String(contentsOf: url, encoding: .isoLatin1))
                let preview = text.map { t in
                    t.components(separatedBy: "\n").prefix(500).joined(separator: "\n")
                }
                let highlighted = preview.map { SyntaxHighlighter.highlight($0, fileExtension: ext, isDark: isDark) }
                await MainActor.run {
                    previewText = preview
                    highlightedText = highlighted
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Chat File Panel Row

struct ChatFilePanelRow: View {
    @ObservedObject var node: ExplorerNode
    let selectedId: UUID?
    let showHidden: Bool
    let depth: Int
    let onSelect: (ExplorerNode) -> Void
    let onInsert: (ExplorerNode) -> Void

    @Environment(\.appTheme) var theme
    @State private var isHovered = false

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }
    private var isSelected: Bool { selectedId == node.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if node.isExpanded, let children = node.children {
                ForEach(children) { child in
                    ChatFilePanelRow(
                        node: child,
                        selectedId: selectedId,
                        showHidden: showHidden,
                        depth: depth + 1,
                        onSelect: onSelect,
                        onInsert: onInsert
                    )
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: CGFloat(depth) * 14)
            if node.isDirectory {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? accentColor.opacity(0.2) : theme.primaryText.opacity(0.06))
                    .frame(width: 26, height: 26)
                Image(systemName: node.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? accentColor : node.iconColor)
            }
            Text(node.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if isHovered && !node.isDirectory {
                Button { onInsert(node) } label: {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 10))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
                .help("In Chat einfügen")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? accentColor.opacity(0.15) : (isHovered ? theme.cardSurface : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onSelect(node)
            if node.isDirectory {
                withAnimation(.easeInOut(duration: 0.12)) { node.isExpanded.toggle() }
                // Load (or retry after failure) when expanding
                if node.isExpanded && (node.children == nil || node.loadFailed) {
                    node.loadChildren(showHidden: showHidden)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Message Row (VS Code Copilot style: flat, left-aligned, dividers)

struct MessageBubbleView: View {
    let message: ChatMessage
    var onDiffTap: ((String) -> Void)?
    @Environment(\.appTheme) var theme
    @State private var toolsExpanded: Bool = false

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var resolvedSource: ChatProviderSource {
        if let source = message.source {
            return source
        }
        if let model = message.model, model.lowercased().hasPrefix("github/") {
            return .copilot
        }
        return .claude
    }

    private var sourceColor: Color {
        guard resolvedSource == .copilot else { return accentColor }
        // Darker burnt-amber for light/medium backgrounds (orange alone fails WCAG contrast)
        return (theme.isLight || theme.isMedium)
            ? Color(red: 0.72, green: 0.35, blue: 0.0)
            : .orange
    }

    private var modelLabel: String {
        guard let model = message.model, !model.isEmpty else {
            return resolvedSource.label
        }
        return model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "github/", with: "")
            .replacingOccurrences(of: "-20251001", with: "")
    }

    var body: some View {
        VStack(spacing: 0) {
            if message.role == .user {
                userRow
            } else {
                assistantRow
                // Compact badge to open diff in side panel
                if let diff = message.gitDiff {
                    diffBadge(diff)
                }
            }
            Divider().opacity(0.15)
        }
    }

    // MARK: - User message row

    private var userRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.secondaryText)
                Text("You")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            if !message.content.isEmpty {
                MarkdownTextView(text: message.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    // MARK: - Assistant message row

    private var assistantRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 18, height: 18)
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                HStack(spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: resolvedSource.icon)
                            .font(.system(size: 8, weight: .semibold))
                        Text(resolvedSource.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(sourceColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(sourceColor.opacity(0.10), in: Capsule())

                    Text(modelLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                if message.isStreaming {
                    ProgressView().scaleEffect(0.5)
                }
            }

            if !message.toolCalls.isEmpty {
                if message.isStreaming {
                    ResearchAnimationView(recentTool: message.toolCalls.last?.name ?? "")
                } else if message.source != .copilot {
                    toolsSummaryView(message.toolCalls)
                }
            }

            if !message.content.isEmpty {
                MarkdownTextView(text: message.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if message.isStreaming && message.content.isEmpty && message.toolCalls.isEmpty {
                streamingDots
            }

            if !message.isStreaming && (message.inputTokens > 0 || message.costUsd != nil) {
                tokenFooter
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    private func toolCallView(_ tool: ToolCall) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row: icon + tool name + command summary
            HStack(spacing: 5) {
                Image(systemName: tool.name == "Bash" ? "terminal.fill" : "wrench.and.screwdriver.fill")
                    .font(.system(size: 9)).foregroundStyle(.orange)
                Text(tool.name)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.orange.opacity(0.85))
                if !tool.input.isEmpty {
                    Text(tool.input)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                if tool.result != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9)).foregroundStyle(.green.opacity(0.7))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            // Output block (shown when expanded)
            if toolsExpanded, let result = tool.result, !result.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(result)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder.opacity(0.4), lineWidth: 0.5))
            }
        }
    }

    private func toolsSummaryView(_ tools: [ToolCall]) -> some View {
        // Compact summary header that toggles the expanded detail list
        var seen = Set<String>()
        var counts: [(name: String, count: Int)] = []
        for t in tools {
            if seen.contains(t.name) {
                if let idx = counts.firstIndex(where: { $0.name == t.name }) {
                    counts[idx].count += 1
                }
            } else {
                seen.insert(t.name)
                counts.append((name: t.name, count: 1))
            }
        }
        let label = counts.map { $0.count > 1 ? "\($0.name) ×\($0.count)" : $0.name }.joined(separator: "  ·  ")
        let hasResults = tools.contains { $0.result != nil }

        return VStack(alignment: .leading, spacing: 6) {
            // Tap to expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { toolsExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 9)).foregroundStyle(.orange.opacity(0.55))
                    Text(label)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.orange.opacity(0.5))
                    if hasResults {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9)).foregroundStyle(.green.opacity(0.6))
                    }
                    Spacer()
                    Image(systemName: toolsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(theme.tertiaryText.opacity(0.5))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Expanded per-tool detail
            if toolsExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tools) { tool in
                        toolCallView(tool)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var streamingDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(theme.secondaryText.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .scaleEffect(1.0)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                        value: message.isStreaming
                    )
            }
        }
        .padding(.vertical, 4)
    }

    private var tokenFooter: some View {
        HStack(spacing: 8) {
            if message.inputTokens > 0 {
                Label("\(message.inputTokens) in", systemImage: "arrow.down")
                    .font(.system(size: 9)).foregroundStyle(theme.tertiaryText)
                Label("\(message.outputTokens) out", systemImage: "arrow.up")
                    .font(.system(size: 9)).foregroundStyle(theme.tertiaryText)
            }
            if let cost = message.costUsd, cost > 0 {
                Text(String(format: "$%.4f", cost))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(theme.tertiaryText)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Git Diff Badge (opens side panel)

    private func diffBadge(_ diff: String) -> some View {
        let files = parseDiffFiles(diff)
        let added   = diff.components(separatedBy: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
        let removed = diff.components(separatedBy: "\n").filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count

        return Button {
            onDiffTap?(diff)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.mint)
                Text("\(files.count) Datei\(files.count == 1 ? "" : "en") geändert")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text("+\(added)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.green)
                Text("-\(removed)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
                Spacer()
                Image(systemName: "sidebar.right")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color(white: theme.isLight ? 0.95 : 0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(white: theme.isLight ? 0.85 : 0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.bottom, 10)
        .onAppear { onDiffTap?(diff) }   // auto-open side panel
    }
}

// MARK: - Diff Parsing Helpers (shared)

struct DiffFile {
    let name: String
    let lines: [String]
    var additions: Int { lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count }
    var deletions: Int { lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count }
}

func parseDiffFiles(_ diff: String) -> [DiffFile] {
    var files: [DiffFile] = []
    var currentName = ""
    var currentLines: [String] = []

    for rawLine in diff.components(separatedBy: "\n") {
        // Trim carriage returns (Windows \r\n endings)
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.hasPrefix("diff --git ") {
            if !currentName.isEmpty {
                files.append(DiffFile(name: currentName, lines: currentLines))
            }
            let parts = line.components(separatedBy: " b/")
            currentName = parts.last ?? line
            currentLines = []
        } else {
            currentLines.append(line)
        }
    }
    if !currentName.isEmpty {
        files.append(DiffFile(name: currentName, lines: currentLines))
    }
    return files
}

// MARK: - Research Animation (shown while Claude uses tools during streaming)

private struct ResearchAnimationView: View {
    let recentTool: String
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 1.0
    @Environment(\.appTheme) var theme

    /// Darker burnt-amber on light/medium backgrounds for WCAG contrast; bright orange on dark.
    private var searchColor: Color {
        (theme.isLight || theme.isMedium)
            ? Color(red: 0.72, green: 0.35, blue: 0.0)
            : Color.orange
    }
    private var bgOpacity: Double { (theme.isLight || theme.isMedium) ? 0.13 : 0.08 }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(searchColor.opacity(i == 0 ? 0.85 : i == 1 ? 0.5 : 0.25))
                        .frame(width: i == 0 ? 4 : 3, height: i == 0 ? 4 : 3)
                        .offset(y: -9)
                        .rotationEffect(.degrees(rotation + Double(i) * 120))
                }
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(searchColor)
                    .scaleEffect(pulse)
            }
            .frame(width: 22, height: 22)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = 1.25
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Searching…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(searchColor)
                if !recentTool.isEmpty {
                    Text(recentTool)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(searchColor.opacity(0.65))
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(searchColor.opacity(bgOpacity), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Picker Panel Style Modifier

private struct PickerPanelModifier: ViewModifier {
    let bg: Color
    let border: Color
    func body(content: Content) -> some View {
        content
            .padding(4)
            .frame(minWidth: 180)
            .fixedSize()
            .background(bg)
            .overlay(Rectangle().strokeBorder(border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: -4)
    }
}

// MARK: - Picker Row Views (hover-capable)

private struct PickerRowView: View {
    let label: String
    let selected: Bool
    let accent: Color
    let fg: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark" : "")
                    .font(.system(size: 10))
                    .foregroundStyle(accent)
                    .frame(width: 12)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(selected || hovered ? accent : fg)
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered in
            hovered = isHovered
            if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct OrchRowView: View {
    let label: String
    let selected: Bool
    let accent: Color
    let fg: Color
    let secondary: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.square.fill" : (label == "Auswahl aufheben" ? "xmark.circle" : "square"))
                    .font(.system(size: 12))
                    .foregroundStyle(label == "Auswahl aufheben" ? .red.opacity(0.7) : (selected || hovered ? accent : secondary))
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(label == "Auswahl aufheben" ? .red.opacity(0.7) : (selected || hovered ? accent : fg))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { isHovered in
            hovered = isHovered
            if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Snippet Sheet (in SingleChatSessionView)

extension SingleChatSessionView {
    var snippetSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Snippet hinzufügen")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            VStack(alignment: .leading, spacing: 6) {
                Text("Titel")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                TextField("z.B. Commit & Push", text: $newSnippetTitle)
                    .font(.system(size: 13))
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Befehl / Prompt")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                TextEditor(text: $newSnippetText)
                    .font(.system(size: 12.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 90, maxHeight: 180)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
            }

            HStack {
                Spacer()
                Button("Abbrechen") { showSnippetSheet = false }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                Button("Speichern") {
                    let title = newSnippetTitle.trimmingCharacters(in: .whitespaces)
                    let text  = newSnippetText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty, !text.isEmpty else { return }
                    state.snippets.append(CommandSnippet(title: title, text: text))
                    showSnippetSheet = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 6))
                .disabled(newSnippetTitle.trimmingCharacters(in: .whitespaces).isEmpty ||
                          newSnippetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(theme.windowBg)
        .environment(\.appTheme, theme)
    }
}

// MARK: - Snippet Row

private struct SnippetRowView: View {
    let snippet:  CommandSnippet
    let accent:   Color
    let fg:       Color
    let secondary: Color
    let onInsert: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9))
                .foregroundStyle(hovered ? accent : secondary.opacity(0.5))
            Text(snippet.title)
                .font(.system(size: 12))
                .foregroundStyle(hovered ? accent : fg)
                .lineLimit(1)
            Spacer()
            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(secondary)
                }
                .buttonStyle(.plain)
                .onHover { if $0 { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onInsert() }
        .onHover { isHovered in
            hovered = isHovered
            if isHovered { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// MARK: - Markdown Text Renderer

// MarkdownTextView is defined in MarkdownTextView.swift
