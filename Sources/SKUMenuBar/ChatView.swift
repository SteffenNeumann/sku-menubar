import SwiftUI
import UniformTypeIdentifiers

// MARK: - Chat View (Tab Container)

struct ChatView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    @State private var tabs: [ChatTab] = [ChatTab(title: "Chat 1")]
    @State private var selectedTabIndex: Int = 0

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            // Render selected tab content, keyed by tab id to force recreation on switch
            if tabs.indices.contains(selectedTabIndex) {
                SingleChatSessionView(tab: Binding(
                    get: { tabs.indices.contains(selectedTabIndex) ? tabs[selectedTabIndex] : ChatTab() },
                    set: { if tabs.indices.contains(selectedTabIndex) { tabs[selectedTabIndex] = $0 } }
                ))
                .id(tabs[selectedTabIndex].id)
                .environmentObject(state)
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
            openSessionInNewTab(sid, title: state.pendingChatSessionTitle)
            state.pendingChatSession = nil
            state.pendingChatSessionTitle = nil
        }
    }

    private func openSessionInNewTab(_ sessionId: String, title: String?) {
        var newTab = ChatTab(title: title ?? String(sessionId.prefix(8)))
        newTab.sessionId = sessionId
        tabs.append(newTab)
        selectedTabIndex = tabs.count - 1
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs.indices, id: \.self) { i in
                    tabButton(index: i)
                }
                // New tab button
                Button {
                    let newTab = ChatTab(title: "Chat \(tabs.count + 1)")
                    tabs.append(newTab)
                    selectedTabIndex = tabs.count - 1
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
        .background(theme.cardSurface)
        .overlay(Rectangle().fill(theme.cardBorder).frame(height: 0.5), alignment: .bottom)
    }

    private func tabButton(index: Int) -> some View {
        let isSelected = selectedTabIndex == index
        let tab = tabs[index]

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
            if tabs.count > 1 {
                Button {
                    tabs.remove(at: index)
                    selectedTabIndex = max(0, min(selectedTabIndex, tabs.count - 1))
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
        .onTapGesture { selectedTabIndex = index }
        .frame(maxWidth: 160)
    }
}

// MARK: - Single Chat Session View (formerly ChatView internals)

struct SingleChatSessionView: View {
    @Binding var tab: ChatTab

    init(tab: Binding<ChatTab>) {
        self._tab = tab
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
    @State private var orchestratorMode: Bool = false
    @State private var selectedOrchestrators: Set<String> = []
    @FocusState private var inputFocused: Bool

    private let models = ["claude-sonnet-4-6", "claude-opus-4-6", "claude-haiku-4-5-20251001"]

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var shortModelName: String {
        selectedModel
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20251001", with: "")
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    emptyState
                } else {
                    messagesArea
                }
                inputBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isDragOver {
                dropOverlay
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            inputFocused = true
            // Restore state from tab if resuming a session
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
            }
        }
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
                        MessageBubbleView(message: msg)
                            .id(msg.id)
                    }
                    if let err = errorMessage {
                        errorBubble(err)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: messages.count) { scrollToBottom(proxy) }
            .onChange(of: messages.last?.content) { scrollToBottom(proxy) }
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
        let orchValid = !orchestratorMode || !selectedOrchestrators.isEmpty
        return hasContent && !isStreaming && orchValid
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Orchestrator agent chips (inside card, above input)
            if orchestratorMode && !state.agentService.agents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(state.agentService.agents) { agent in
                            let on = selectedOrchestrators.contains(agent.id)
                            Button {
                                if on { selectedOrchestrators.remove(agent.id) }
                                else  { selectedOrchestrators.insert(agent.id) }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 10))
                                        .foregroundStyle(on ? accentColor : theme.tertiaryText)
                                    Text(agent.name)
                                        .font(.system(size: 10, weight: on ? .semibold : .regular))
                                        .foregroundStyle(on ? theme.primaryText : theme.secondaryText)
                                }
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(on ? accentColor.opacity(0.1) : theme.cardBg.opacity(0.5),
                                            in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(on ? accentColor.opacity(0.3) : theme.cardBorder, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
                }
                Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5)
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

            // Text + send
            HStack(alignment: .bottom, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    if inputText.isEmpty {
                        Text("Ask Claude…")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.tertiaryText.opacity(0.6))
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $inputText)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.primaryText)
                        .frame(minHeight: 24, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .focused($inputFocused)
                        .onKeyPress(.return) {
                            if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                            guard canSend else { return .handled }
                            sendMessage(); return .handled
                        }
                }

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
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            // ─── Subtle control strip ───
            controlStrip
        }
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isDragOver ? accentColor.opacity(0.6) : theme.cardBorder,
                              lineWidth: isDragOver ? 1.5 : 0.5)
        )
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    // Minimal icon row at the very bottom of the input card
    private var controlStrip: some View {
        HStack(spacing: 0) {
            // Attach file
            stripButton(icon: "paperclip", active: false, help: "Datei anhängen") {
                openFilePicker()
            }

            stripSep

            // Working directory
            stripDirButton

            stripSep

            // Model
            Menu {
                ForEach(models, id: \.self) { m in Button(m) { selectedModel = m } }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                    Text(shortModelName)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(theme.tertiaryText.opacity(0.5))
                }
                .padding(.horizontal, 6).padding(.vertical, 4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(orchestratorMode)

            // Agent (single mode)
            if !orchestratorMode && !state.agentService.agents.isEmpty {
                stripSep
                Menu {
                    Button("Kein Agent") { selectedAgent = "" }
                    Divider()
                    ForEach(state.agentService.agents) { a in
                        Button(a.name) { selectedAgent = a.id }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(selectedAgent.isEmpty ? theme.tertiaryText : accentColor)
                        Text(selectedAgent.isEmpty ? "Agent" :
                             (state.agentService.agents.first { $0.id == selectedAgent }?.name ?? "Agent"))
                            .font(.system(size: 10))
                            .foregroundStyle(selectedAgent.isEmpty ? theme.tertiaryText : accentColor)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(theme.tertiaryText.opacity(0.5))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 4)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Orchestrator toggle
            if !state.agentService.agents.isEmpty {
                stripSep
                stripButton(
                    icon: "square.stack.3d.up.fill",
                    active: orchestratorMode,
                    help: "Mehrere Agents parallel"
                ) {
                    orchestratorMode.toggle()
                    if orchestratorMode && selectedOrchestrators.isEmpty {
                        selectedOrchestrators = Set(state.agentService.agents.prefix(2).map { $0.id })
                    }
                }
                if orchestratorMode {
                    Text("Orchestrator")
                        .font(.system(size: 9))
                        .foregroundStyle(accentColor.opacity(0.7))
                        .padding(.leading, 2)
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
                .font(.system(size: 11))
                .foregroundStyle(active ? accentColor : theme.tertiaryText.opacity(0.6))
                .frame(width: 26, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var stripDirButton: some View {
        Button {
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
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(workingDirectory != nil ? accentColor : theme.tertiaryText.opacity(0.6))
                Text(workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "~")
                    .font(.system(size: 10))
                    .foregroundStyle(workingDirectory != nil ? accentColor : theme.tertiaryText.opacity(0.6))
                    .lineLimit(1)
                    .frame(maxWidth: 90)
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help("Arbeitsverzeichnis")
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

        // Create one assistant placeholder per agent
        var agentIndices: [String: Int] = [:]
        for agent in agents {
            var placeholder = ChatMessage(role: .assistant, content: "", isStreaming: true)
            placeholder.model = agent.name   // reuse model field as agent label
            messages.append(placeholder)
            agentIndices[agent.id] = messages.count - 1
        }

        isStreaming = true
        var remaining = agents.count

        for agent in agents {
            let agentId = agent.id
            let agentName = agent.name
            Task { @MainActor in
                guard let idx = agentIndices[agentId] else { return }
                // prepend agent header to output
                messages[idx].content = "**[\(agentName)]**\n"

                let stream = state.cliService.send(
                    message: text,
                    sessionId: nil,
                    agentName: agentId,
                    model: selectedModel,
                    workingDirectory: workingDirectory
                )
                do {
                    for try await event in stream {
                        if event.type == "assistant",
                           let content = event.message?.content {
                            for block in content where block.type == "text" {
                                if let t = block.text, !t.isEmpty {
                                    messages[idx].content += t
                                }
                            }
                        }
                    }
                } catch {
                    messages[idx].content += "\n\n⚠️ \(error.localizedDescription)"
                }
                messages[idx].isStreaming = false
                remaining -= 1
                if remaining == 0 { isStreaming = false }
            }
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
        messages.append(ChatMessage(role: .user, content: displayText))

        let assistantMsg = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMsg)
        let assistantIndex = messages.count - 1

        isStreaming = true

        Task { @MainActor in
            let stream = state.cliService.send(
                message: fullMessage,
                sessionId: currentSessionId,
                agentName: selectedAgent.isEmpty ? nil : selectedAgent,
                model: selectedModel,
                workingDirectory: workingDirectory
            )

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
                                        messages[assistantIndex].content += t
                                    }
                                case "tool_use":
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

                    case "result":
                        messages[assistantIndex].costUsd = event.costUsd
                        if let sid = event.sessionId {
                            currentSessionId = sid
                        }

                    default: break
                    }
                }
            } catch {
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

            messages[assistantIndex].isStreaming = false
            isStreaming = false

            // If tool calls were made, fetch git diff to show changed files
            if !messages[assistantIndex].toolCalls.isEmpty, let cwd = workingDirectory {
                if let diff = await fetchGitDiff(in: cwd), !diff.isEmpty {
                    messages[assistantIndex].gitDiff = diff
                }
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
}

// MARK: - Message Row (VS Code Copilot style: flat, left-aligned, dividers)

struct MessageBubbleView: View {
    let message: ChatMessage
    @Environment(\.appTheme) var theme
    @State private var diffExpanded: Bool = false

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        VStack(spacing: 0) {
            if message.role == .user {
                userRow
            } else {
                assistantRow
                // Diff panel – shown when tool calls modified files
                if let diff = message.gitDiff {
                    diffPanel(diff)
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
                    .font(.system(size: 13))
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
                Text(message.model?.replacingOccurrences(of: "claude-", with: "") ?? "Claude")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                if message.isStreaming {
                    ProgressView().scaleEffect(0.5)
                }
            }

            if !message.toolCalls.isEmpty {
                ForEach(message.toolCalls) { tool in toolCallView(tool) }
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

    // MARK: - Git Diff Panel

    private func diffPanel(_ diff: String) -> some View {
        let files = parseDiffFiles(diff)

        return VStack(alignment: .leading, spacing: 0) {
            // Header row — toggle to expand/collapse
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    diffExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.mint)
                    Text("\(files.count) Datei\(files.count == 1 ? "" : "en") geändert")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    // Summarize additions/deletions
                    let added   = diff.components(separatedBy: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
                    let removed = diff.components(separatedBy: "\n").filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
                    Text("+\(added)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.green)
                    Text("-\(removed)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red)
                    Spacer()
                    // Copy full diff
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

                    Image(systemName: diffExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color(white: theme.isLight ? 0.93 : 0.08))
            }
            .buttonStyle(.plain)

            // Diff content (collapsible)
            if diffExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                            diffFileSection(file)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .background(Color(white: theme.isLight ? 0.95 : 0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(white: theme.isLight ? 0.85 : 0.18), lineWidth: 0.5))
        .padding(.horizontal, 16).padding(.bottom, 10)
        .onAppear { diffExpanded = true }   // auto-expand on first show
    }

    private func diffFileSection(_ file: DiffFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // File name header
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.tertiaryText)
                Text(file.name)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
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
                    diffLine(line)
                }
            }
            .padding(.vertical, 4)

            if file.name != files(from: file).last?.name ?? "" {
                Divider().opacity(0.2)
            }
        }
    }

    private func diffLine(_ line: String) -> some View {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 1)
            .background(bg)
    }

    // MARK: - Diff parsing helpers

    struct DiffFile {
        let name: String
        let lines: [String]
        var additions: Int { lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count }
        var deletions: Int { lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count }
    }

    private func parseDiffFiles(_ diff: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var currentName = ""
        var currentLines: [String] = []

        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git ") {
                if !currentName.isEmpty {
                    files.append(DiffFile(name: currentName, lines: currentLines))
                }
                // Extract file name: "diff --git a/path b/path" → "path"
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

    // Helper to suppress compile warning about unused parameter
    private func files(from file: DiffFile) -> [DiffFile] { [] }
}

// MARK: - Markdown Text Renderer

// MarkdownTextView is defined in MarkdownTextView.swift
