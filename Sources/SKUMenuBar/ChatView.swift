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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(state.chatTabs.indices, id: \.self) { i in
                    tabButton(index: i)
                }
                // New tab button
                Button {
                    let newTab = ChatTab(title: "Chat \(state.chatTabs.count + 1)")
                    state.chatTabs.append(newTab)
                    state.selectedChatTabIndex = state.chatTabs.count - 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 36)
        .background(theme.windowBg)
        .overlay(Rectangle().fill(theme.cardBorder).frame(height: 0.5), alignment: .bottom)
    }

    private func tabButton(index: Int) -> some View {
        let isSelected = state.selectedChatTabIndex == index
        let tab = state.chatTabs[index]

        return HStack(spacing: 5) {
            if tab.isStreaming {
                ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
            } else {
                Image(systemName: tab.agentId.isEmpty ? "bubble.left" : "cpu")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? accentColor : theme.tertiaryText)
            }
            Text(tab.title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
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
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? accentColor.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? accentColor.opacity(0.3) : Color.clear, lineWidth: 0.5)
        )
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
    @State private var selectedOrchestrators: Set<String> = []
    @State private var showModelPicker    = false
    @State private var showAgentPicker    = false
    @State private var showOrchPicker     = false
    @State private var showSnippetPicker  = false
    @State private var showPermPicker     = false
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

    private func closeAllPickers() {
        showModelPicker   = false
        showAgentPicker   = false
        showOrchPicker    = false
        showSnippetPicker = false
        showPermPicker    = false
    }
    @FocusState private var inputFocused: Bool

    private var orchestratorMode: Bool { !selectedOrchestrators.isEmpty }

    private let models = ["claude-sonnet-4-6", "claude-opus-4-6", "claude-haiku-4-5-20251001"]

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
                    if messages.isEmpty {
                        emptyState.onTapGesture { closeAllPickers() }
                    } else {
                        messagesArea.onTapGesture { closeAllPickers() }
                    }
                    inputBar
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: InputBarHeightKey.self, value: geo.size.height)
                        })
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onAppear {
            inputFocused = true
            // Restore state from tab
            if !tab.inputText.isEmpty { inputText = tab.inputText }
            if let wd = tab.workingDirectory { workingDirectory = wd }
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
        }
        .onChange(of: currentSessionId) { tab.sessionId = currentSessionId }
        .onChange(of: selectedModel) { tab.model = selectedModel }
        .onChange(of: selectedAgent) { tab.agentId = selectedAgent }
        .onChange(of: workingDirectory) { tab.workingDirectory = workingDirectory }
        .onChange(of: state.pendingChatNewProject) {
            guard let path = state.pendingChatNewProject else { return }
            state.pendingChatNewProject = nil
            newSession()
            workingDirectory = path
            tab.title = URL(fileURLWithPath: path).lastPathComponent
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
                // Don't scroll mid-stream (new message added = user sent or placeholder inserted)
                // Streaming scroll handled by isStreaming onChange below
                if !isStreaming { scrollToBottom(proxy) }
            }
            // Only scroll on content change when NOT streaming to avoid
            // calling scrollTo on every single streaming token
            .onChange(of: messages.last?.content) {
                guard !isStreaming else { return }
                scrollToBottom(proxy)
            }
            // Scroll once when streaming ends
            .onChange(of: isStreaming) {
                if !isStreaming { scrollToBottom(proxy) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func errorBubble(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            Text(text).font(.system(size: 12)).foregroundStyle(theme.primaryText)
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

    private var inputBar: some View {
        VStack(spacing: 0) {
            // File attachment chips
            if !attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachedFiles) { file in fileChip(file) }
                    }
                    .padding(.horizontal, 12).padding(.top, 8)
                }
            }

            // Text + send
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Ask Claude…")
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
                        .onKeyPress(.return) {
                            if NSEvent.modifierFlags.contains(.shift) { return .ignored }
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
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
    }

    // Generic upward-opening themed picker button (custom overlay, no system popover)
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
                Image(systemName: isPresented.wrappedValue ? "chevron.down" : "chevron.up")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(theme.tertiaryText.opacity(0.5))
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomLeading) {
            if isPresented.wrappedValue {
                VStack(alignment: .leading, spacing: 0) { content() }
                    .padding(4)
                    .frame(minWidth: 180)
                    .fixedSize()
                    .background(theme.windowBg)
                    .overlay(Rectangle().strokeBorder(theme.cardBorder, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: -3)
                    .offset(y: -28)
            }
        }
        .zIndex(isPresented.wrappedValue ? 100 : 0)
    }

    // Single row for single-select pickers (hover-capable)
    private func pickerRow(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        PickerRowView(label: label, selected: selected, accent: accentColor, fg: theme.primaryText, action: action)
    }

    // Multi-select row for orchestrator (hover-capable)
    private func orchRow(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        OrchRowView(label: label, selected: selected, accent: accentColor, fg: theme.primaryText, secondary: theme.tertiaryText, action: action)
    }

    // Minimal icon row at the very bottom of the input card
    private var controlStrip: some View {
        HStack(spacing: 0) {
            // File panel toggle
            stripButton(icon: "sidebar.left", active: showFilePanel, help: "File Explorer") {
                withAnimation(.spring(response: 0.3)) { showFilePanel.toggle() }
            }

            stripSep

            // Attach file
            stripButton(icon: "paperclip", active: false, help: "Datei anhängen") {
                openFilePicker()
            }

            stripSep

            // Working directory
            stripDirButton

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

            stripSep

            // Model picker
            pickerButton(
                icon: "cpu",
                label: shortModelName,
                active: false,
                isPresented: $showModelPicker
            ) {
                ForEach(models, id: \.self) { m in
                    pickerRow(label: m, selected: m == selectedModel) {
                        selectedModel = m
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
                                    messages[idx].toolCalls.append(ToolCall(name: name, input: ""))
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

    private func buildMessageWithAttachments(text: String) -> String {
        guard !attachedFiles.isEmpty else { return text }

        var parts: [String] = []

        for file in attachedFiles {
            if file.isText, let content = try? String(contentsOf: file.url, encoding: .utf8) {
                let ext = file.url.pathExtension.lowercased()
                let lang = ext.isEmpty ? "" : ext
                parts.append("**\(file.name)**\n```\(lang)\n\(content)\n```")
            } else if file.url.pathExtension.lowercased() == "pdf",
                      let pdf = PDFDocument(url: file.url) {
                // Extract text content from PDF pages
                var pdfText = ""
                for i in 0..<pdf.pageCount {
                    if let page = pdf.page(at: i),
                       let pageText = page.string, !pageText.isEmpty {
                        pdfText += pageText + "\n"
                    }
                }
                if !pdfText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append("**\(file.name)** (PDF, \(pdf.pageCount) Seiten)\n```\n\(pdfText.trimmingCharacters(in: .whitespacesAndNewlines))\n```")
                } else {
                    parts.append("**\(file.name)** (PDF, \(pdf.pageCount) Seiten — kein extrahierbarer Text, Pfad: `\(file.url.path)`)")
                }
            } else if file.isImage {
                // Images: pass path and directory access so Claude can reference the file
                parts.append("**\(file.name)** (Bild, Pfad: `\(file.url.path)`)")
            } else {
                parts.append("**\(file.name)** (Pfad: `\(file.url.path)`)")
            }
        }

        if !text.isEmpty { parts.append(text) }
        return parts.joined(separator: "\n\n")
    }

    private func sendMessage() {
        if orchestratorMode && !selectedOrchestrators.isEmpty {
            sendOrchestrator()
            return
        }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachedFiles.isEmpty, !isStreaming else { return }

        // Prompt for working directory before first message of a new session
        if currentSessionId == nil, workingDirectory == nil {
            openDirectoryPicker()
        }

        let fullMessage = buildMessageWithAttachments(text: text)
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
            // Collect unique directories of image/binary attachments so Claude's tools can access them
            let imageDirs = Array(Set(sentFiles.filter { $0.isImage }.map { $0.url.deletingLastPathComponent().path }))
            await performSend(
                message: fullMessage,
                assistantIndex: assistantIndex,
                model: state.claudeRateLimitActive && state.settings.copilotFallbackEnabled
                    ? state.settings.copilotFallbackModel
                    : selectedModel,
                agentOverride: triggerAgent,
                addDirs: imageDirs
            )
        }
    }

    /// Executes the actual CLI send. Fallback is handled natively by `--fallback-model`.
    private func performSend(
        message: String,
        assistantIndex: Int,
        model: String,
        agentOverride: String? = nil,
        addDirs: [String] = []
    ) async {
        let source: ChatProviderSource = inferredSource(from: model)
        if messages.indices.contains(assistantIndex) {
            messages[assistantIndex].source = source
            if messages[assistantIndex].model == nil || messages[assistantIndex].model?.isEmpty == true {
                messages[assistantIndex].model = model
            }
        }

        // Fallback model for --fallback-model CLI flag (native overload handling)
        let fallback: String? = state.settings.copilotFallbackEnabled
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

        let stream = state.cliService.send(
            message: message,
            sessionId: currentSessionId,
            systemPrompt: agentSystemPrompt,
            model: model,
            fallbackModel: fallback,
            workingDirectory: workingDirectory,
            addDirs: addDirs,
            skipPermissions: autoApprove
        )

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
                                let tool = ToolCall(name: name, input: "")
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

                case "rate_limit_event":
                    state.claudeRateLimitActive = true

                case "result":
                    messages[assistantIndex].costUsd = event.costUsd
                    if let sid = event.sessionId {
                        currentSessionId = sid
                    }

                    // Handle error result (e.g. rate-limit / usage-limit)
                    if event.isError == true {
                        let contentText = messages.indices.contains(assistantIndex)
                            ? messages[assistantIndex].content : ""
                        let eventResult = event.result ?? ""
                        let combined = (contentText + " " + eventResult).lowercased()

                        if combined.contains("limit") || combined.contains("overloaded") ||
                           combined.contains("quota") || combined.contains("529") || combined.contains("429") {
                            state.claudeRateLimitActive = true
                        }

                        errorMessage = contentText.isEmpty ? (eventResult.isEmpty ? "Claude returned an error" : eventResult) : contentText
                        if messages.indices.contains(assistantIndex) {
                            messages[assistantIndex].isStreaming = false
                        }
                        isStreaming = false
                        return
                    }

                    state.lastChatProvider = source
                    // Successful response — clear rate-limit flag
                    if state.claudeRateLimitActive { state.claudeRateLimitActive = false }

                default: break
                }
            }
        } catch {
            print("⚠️ performSend error: \(error.localizedDescription)")
            let errText = error.localizedDescription.lowercased()

            // Track rate-limit for UI
            if errText.contains("limit") || errText.contains("overloaded") ||
               errText.contains("quota") || errText.contains("529") || errText.contains("429") {
                state.claudeRateLimitActive = true
            }

            errorMessage = error.localizedDescription
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
        isStreaming = false

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
        // deltaX: positive = moved right
        let raw = coord.growsRight ? event.deltaX : -event.deltaX
        let newW = max(coord.minWidth, min(coord.maxWidth, coord.width.wrappedValue + raw))
        DispatchQueue.main.async { coord.width.wrappedValue = newW }
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
        resolvedSource == .copilot ? .orange : accentColor
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
                Text(message.content)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(theme.primaryText)
                    .textSelection(.enabled)
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
                } else {
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
        HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 10)).foregroundStyle(.orange)
            Text(tool.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.orange.opacity(0.9))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func toolsSummaryView(_ tools: [ToolCall]) -> some View {
        // Count unique tool names, preserve order of first appearance
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
        return HStack(spacing: 6) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 9)).foregroundStyle(.orange.opacity(0.55))
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.orange.opacity(0.5))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
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

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.orange.opacity(i == 0 ? 0.85 : i == 1 ? 0.5 : 0.25))
                        .frame(width: i == 0 ? 4 : 3, height: i == 0 ? 4 : 3)
                        .offset(y: -9)
                        .rotationEffect(.degrees(rotation + Double(i) * 120))
                }
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.orange)
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
                    .foregroundStyle(Color.orange)
                if !recentTool.isEmpty {
                    Text(recentTool)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.orange.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
