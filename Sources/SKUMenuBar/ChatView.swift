import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import AppKit
import QuickLookUI

// MARK: - Picker anchor preference key

private struct PickerOriginAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>? = nil
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue() ?? value
    }
}

/// MARK: - Picker interaction tracker (suppresses dismiss when a row was clicked)
// SwiftUI buttons fire on mouseUp; PickerDismissMonitor fires on mouseDown.
// Without suppression the dismiss removes the button before mouseUp → action never fires.
private final class PickerInteractionTracker {
    static let shared = PickerInteractionTracker()
    private init() {}
    private var suppressUntil: Date = .distantPast
    /// Call from every picker-row button action to suppress dismiss for 500 ms.
    func didInteract() { suppressUntil = Date().addingTimeInterval(0.5) }
    var isSuppressed: Bool { Date() < suppressUntil }
}

// MARK: - Outside-click dismiss monitor

private struct PickerDismissMonitor: NSViewRepresentable {
    let isActive: Bool
    let onDismiss: () -> Void

    final class Coordinator {
        var monitor: Any?
        var onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func start() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                // Delay past mouseUp so that button actions (which fire on mouseUp) execute
                // before we tear down the picker panel.  If a picker row was clicked the
                // PickerInteractionTracker will have been set and we skip the dismiss.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard !PickerInteractionTracker.shared.isSuppressed else { return }
                    self?.onDismiss()
                }
                return event
            }
        }
        func stop() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onDismiss = onDismiss
        isActive ? context.coordinator.start() : context.coordinator.stop()
    }
}

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
                    .zIndex(state.selectedChatTabIndex == index ? 1 : 0)
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
                    .font(.system(size: 13, weight: .medium))
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
                    .font(.system(size: 11))
                    .foregroundStyle(accentColor)
            }
            Text(tab.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.primaryText : theme.tertiaryText)
                .lineLimit(1)

            // Close button (only if more than 1 tab)
            if state.chatTabs.count > 1 {
                Button {
                    state.chatTabs.remove(at: index)
                    state.selectedChatTabIndex = max(0, min(state.selectedChatTabIndex, state.chatTabs.count - 1))
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
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
    @State private var streamingStartTime: Date = Date()
    @State private var agentJustFinished: Bool = false
    @State private var chatTimerTick: Date = Date()
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
    @State private var orchestratorHistory: [(role: String, content: String)] = []
    @State private var masterTodos: [MasterTodoItem] = []   // Hierarchische Todo-Liste
    @State private var masterGoal: String = ""              // Sticky Ziel-Header
    @State private var lastAgentTasks: [String: String] = [:]       // Letzter Plan — TODO: für künftigen Execute-only-Reuse-Pfad
    @State private var lastOrchestratorAgents: [AgentDefinition] = []  // Agents des letzten Plans — TODO: dito
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
    @State private var activePlan: String? = nil       // Orchestrator-Plan für rechtes Panel
    @State private var rightPanelShowsPlan: Bool = true // true = Plan-Tab aktiv
    @State private var diffPanelDismissed: Bool = false
    @State private var autoTriggeredAgentName: String? = nil  // zeigt ⚡-Badge wenn Trigger matchte
    @State private var pendingTriggerAgentName: String? = nil // live-Badge beim Tippen (onChange-driven)
    @State private var showFilePanel: Bool = false
    @State private var filePanelWidth: CGFloat = 220
    @State private var diffPanelWidth: CGFloat = 500
    @State private var filePreviewNode: ExplorerNode? = nil
    @State private var changedFilePaths: Set<String> = []
    @State private var newFilePaths: Set<String> = []
    @State private var dismissedChangedPaths: Set<String> = []
    @State private var filePreviewPanelWidth: CGFloat = 380
    @State private var inputBarHeight: CGFloat = 56
    @AppStorage("chat.autoApprove") private var autoApprove: Bool = false
    @State private var isCompacting: Bool = false
    @State private var compactedSummary: String? = nil
    // Streaming timing (for Live-Plan-Panel)
    @State private var streamingStartDate: Date? = nil
    @State private var lastStreamDuration: TimeInterval? = nil
    // Compact-Banner (user decides when to compact)
    @State private var showCompactBanner: Bool = false
    @State private var compactBannerSeenAt: Int = 0
    // Persona validation
    @State private var selectedPersonaId: String = ""
    @State private var showPersonaPicker = false
    @State private var validationResult: PersonaValidationResult? = nil
    @State private var isValidating: Bool = false

    // TMetric: auto-match darf nur einmal laufen (nicht bei jedem Tab-Wechsel)
    @State private var didAutoMatchTMetric: Bool = false

    // MCP per-session selection
    @State private var availableMCPs: [MCPServer] = []
    @State private var activeMCPIds: Set<String> = ["__none__"]   // leer = alle aktiv, __none__ = alle deaktiviert
    @State private var mcpConfigs: [String: MCPServerConfig] = [:]
    @State private var showMCPPicker = false
    @State private var isLoadingMCPs = false

    private var anyPickerOpen: Bool {
        showModelPicker || showAgentPicker || showOrchPicker ||
        showSnippetPicker || showPermPicker || showBranchPicker || showMCPPicker ||
        showPersonaPicker
    }

    /// Checks whether `input` matches a trigger phrase.
    /// Three tiers:
    ///  1. Full-phrase: "code review" matches trigger "code review"
    ///  2. Word-level: "review" matches trigger "code review" (word in phrase)
    ///  3. Prefix: "review" matches trigger "Reviewer" (input is prefix of trigger word, or vice versa)
    private func inputMatchesTrigger(_ input: String, trigger: String) -> Bool {
        let inputL   = input.lowercased()
        let triggerL = trigger.lowercased()
        // 1. Full phrase match
        if inputL.contains(triggerL) { return true }
        let inputWords   = inputL.components(separatedBy: .whitespacesAndNewlines).filter { $0.count >= 3 }
        let triggerWords = triggerL.components(separatedBy: .whitespacesAndNewlines).filter { $0.count >= 3 }
        // 2. Any trigger word as a substring of the input
        if triggerWords.contains(where: { inputL.contains($0) }) { return true }
        // 3. Bidirectional prefix: "review" matches "reviewer", "reviewing"
        return inputWords.contains { iw in
            triggerWords.contains { tw in tw.hasPrefix(iw) || iw.hasPrefix(tw) }
        }
    }

    /// Returns the first agent whose effectiveTriggers match `text`.
    private func autoTriggerAgent(for text: String) -> AgentDefinition? {
        guard selectedAgent.isEmpty, !text.isEmpty else { return nil }
        return state.agentService.agents.first { agent in
            agent.effectiveTriggers.contains { inputMatchesTrigger(text, trigger: $0) }
        }
    }

    /// Heuristik: true = Aufgabe ist komplex genug für Orchestrierung.
    /// Berücksichtigt Wortanzahl, mehrere Aufgaben-Verben und Mehrdomain-Konjunktionen.
    /// Dient als schnelle Vorfilterung — bei Auto-Orchestrierung folgt ein LLM-Validation-Check.
    private func isComplexTask(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count > 15 else { return false }   // Kurz → immer einfach
        guard words.count <= 300 else { return true }  // Sehr lang → immer komplex
        if words.count > 40 { return true }            // Mittellang & ausführlich → komplex

        let lower = text.lowercased()
        // Aufgaben-Verben — DE + EN (Word-Set-Matching statt substring um
        // "explanation" → "plan", "findings" → "find" etc. zu vermeiden)
        let taskVerbs: Set<String> = ["erstelle", "entwickle", "implementiere", "analysiere",
                         "überprüfe", "prüfe", "untersuche", "schreibe", "entwerfe",
                         "plane", "optimiere", "recherchiere", "vergleiche", "bewerte",
                         "dokumentiere", "strukturiere", "baue", "konfiguriere",
                         "konzipiere", "stelle", "finde", "erkläre", "beschreibe",
                         "zeige", "führe", "gib", "erstell", "entwickl",
                         "identifiziere", "schlage", "empfehle", "überleg",
                         // English verbs
                         "create", "build", "implement", "analyze", "review",
                         "investigate", "write", "design", "plan", "optimize",
                         "research", "compare", "evaluate", "document", "configure",
                         "find", "explain", "describe", "identify", "recommend"]
        let wordSet = Set(lower.split(separator: " ").map { String($0) })
        let verbCount = taskVerbs.intersection(wordSet).count
        if verbCount >= 2 { return true }
        // Konjunktionen die einen neuen Themenbereich einleiten
        let complexConjunctions = [" sowie ", " außerdem ", " zusätzlich ",
                                   " darüber hinaus ", " einerseits ", " andererseits ",
                                   " zum einen ", " zum anderen ", " gleichzeitig ",
                                   " und auch ", " aber auch ", " und prüfe",
                                   " und analysiere", " und stelle", " und finde",
                                   " furthermore ", " additionally ", " and also "]
        return complexConjunctions.contains { lower.contains($0) }
    }

    // MARK: - Follow-Up Intent Classification

    /// Klassifiziert Follow-Up-Nachrichten nach Intent wenn orchestratorHistory vorhanden ist.
    /// Vermeidet redundantes Re-Planning bei "go" / "ok" / Bestätigungen.
    private enum FollowUpIntent {
        case chat       // Frage/Danke → normaler Einzelagent, kein Orchestrator-Overhead
        case fast       // "go"/"weiter"/"mach das" → Phase 0 überspringen, schnelleres Re-Planning
        case full       // Komplett neues Thema → volle 4-Phasen-Pipeline
    }

    private func classifyFollowUp(_ text: String) -> FollowUpIntent {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = lower.split(separator: " ")
        let wordSet = Set(words.map { String($0) })

        // 1) Triviale Bestätigungen/Danke → Chat
        //    Exakt-Match ODER Nachricht beginnt mit Trivialem + enthält neue Aufgabe
        let trivialWords: Set<String> = ["danke", "super", "perfekt", "gut", "cool",
                                          "thanks", "great", "nice", "passt", "👍"]
        let trivialPhrases = ["alles klar", "ok danke", "passt danke", "passt soweit",
                              "sieht gut aus", "looks good"]
        if trivials(lower, trivialPhrases) || (words.count == 1 && !trivialWords.isDisjoint(with: wordSet)) {
            return .chat
        }

        // 2) Nachricht beginnt mit Trivialem/Danke + enthält NEUE Anweisung
        //    → Chat (User hat Orchestrierung abgeschlossen, will was Einfaches)
        //    z.B. "Passt danke - bitte aufräumen und commit"
        let startsWithTrivial = trivialWords.contains(where: { lower.hasPrefix($0) })
            || trivialPhrases.contains(where: { lower.hasPrefix($0) })
        let hasNewTask: Set<String> = ["aufräumen", "cleanup", "commit", "push",
                                        "speicher", "save", "memory", "schließ", "close"]
        if startsWithTrivial && !wordSet.isDisjoint(with: hasNewTask) { return .chat }

        // 3) Fragen → Chat (Einzelagent reicht)
        if lower.hasSuffix("?") { return .chat }
        let questionStarts = ["was ", "wie ", "warum ", "wann ", "wo ", "welche ",
                              "wer ", "kannst ", "what ", "how ", "why ", "when ",
                              "where ", "which ", "who ", "can ", "could "]
        if questionStarts.contains(where: { lower.hasPrefix($0) }) { return .chat }

        // 4) Reine Ausführungs-Befehle (NUR wenn die Nachricht primär ein Befehl ist)
        //    "go" / "weiter" / "mach das" → fast
        //    Aber NICHT wenn daneben eine neue eigenständige Aufgabe steht
        let pureExecuteWords: Set<String> = ["go", "ja", "weiter", "los",
                               "proceed", "continue", "implementiere", "umsetzen",
                               "loslegen", "ausführen", "run", "einverstanden", "agreed"]
        let executePhrases = ["mach das", "bitte umsetzen", "fang an", "do it",
                              "genau so", "let's go", "bitte machen"]
        if words.count <= 6 {
            if !wordSet.isDisjoint(with: pureExecuteWords) { return .fast }
            if executePhrases.contains(where: { lower.contains($0) }) { return .fast }
        }

        // 5) Längere Nachricht → prüfe ob wirklich komplex
        if isComplexTask(text) { return .full }

        // 6) Default: Chat (sicherer als blind orchestrieren)
        return .chat
    }

    /// Prüft ob der gesamte Text einem trivialen Ausdruck entspricht (exact oder prefix+kurz)
    private func trivials(_ lower: String, _ phrases: [String]) -> Bool {
        phrases.contains(where: { lower == $0 || (lower.hasPrefix($0) && lower.count <= $0.count + 3) })
    }

    /// LLM-basierte Routing-Validierung: Haiku prüft ob Auto-Orchestrierung wirklich nötig ist.
    /// Verhindert False-Positive-Orchestrierungen bei langen aber einfachen Nachrichten.
    /// Wählt die relevanten Agents für eine Aufgabe aus. Gibt die gefilterte Agent-Liste zurück.
    /// - Bei ≥2 relevanten Agents → Orchestrierung mit nur diesen Agents
    /// - Bei 0–1 relevanten → nil (= Einzelagent, keine Orchestrierung)
    private func selectRelevantAgents(_ text: String, agents: [AgentDefinition]) async -> [AgentDefinition] {
        let workers = agents.filter { !$0.isPersona }
        guard workers.count >= 2 else { return workers }

        let agentList = workers.enumerated().map { "\($0.offset + 1). \($0.element.name): \($0.element.description.prefix(100))" }.joined(separator: "\n")
        let agentNames = workers.map { $0.name }
        let prompt = """
        Which of these specialists are RELEVANT for this task? List ONLY the names of specialists who can meaningfully contribute — not all of them.

        Available specialists:
        \(agentList)

        User request: \(text)

        Reply with ONLY the relevant specialist names, one per line. If only one specialist is needed, reply with just that one name.
        """

        var result = ""
        let stream = state.cliService.send(
            message: prompt,
            systemPrompt: "List relevant specialist names, one per line. Nothing else.",
            model: "claude-haiku-4-5-20251001",
            workingDirectory: workingDirectory
        )
        do {
            for try await event in stream {
                guard !Task.isCancelled else { return [] }
                if case "assistant" = event.type, let content = event.message?.content {
                    for block in content where block.type == "text" {
                        if let t = block.text { result += t }
                    }
                }
            }
        } catch { return workers } // Bei Fehler → alle Agents

        // Parse: Zeilen matchen gegen bekannte Agent-Namen (case-insensitive)
        let lines = result.lowercased().split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let matched = workers.filter { agent in
            let nameLower = agent.name.lowercased()
            return lines.contains { line in
                line.contains(nameLower) || nameLower.contains(line)
            }
        }

        print("🔍 Auto-Orch: Haiku wählte \(matched.map { $0.name }) aus \(agentNames)")

        // Gibt die Treffer zurück (0, 1 oder mehr). Caller entscheidet:
        //   ≥2 → Orchestrierung; ==1 → Einzelagent mit diesem Spezialisten; ==0 → generischer Einzelagent
        return matched
    }

    private func closeAllPickers() {
        showModelPicker   = false
        showAgentPicker   = false
        showOrchPicker    = false
        showSnippetPicker = false
        showPermPicker    = false
        showBranchPicker  = false
        showMCPPicker     = false
        showPersonaPicker = false
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
        .init(name: "/agent",   description: "Agent wählen — z.B. /agent code-reviewer"),
        .init(name: "/model",   description: "Modell wechseln"),
        .init(name: "/help",    description: "Verfügbare Befehle anzeigen"),
    ]

    private var filteredSlashCommands: [SlashCommand] {
        let q = inputText.lowercased()
        // "/agent <name>" — zeige passende Agents als Sub-Commands
        if q.hasPrefix("/agent ") {
            let search = String(q.dropFirst("/agent ".count))
            let agents = state.agentService.agents.filter {
                search.isEmpty || $0.name.lowercased().contains(search)
            }
            let noAgent = SlashCommand(name: "/agent –", description: "Kein Agent (zurücksetzen)")
            return [noAgent] + agents.map { .init(name: "/agent \($0.name)", description: $0.description.isEmpty ? "Agent" : $0.description) }
        }
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
        observedPanel
            .onAppear { handleAppear() }
            .onChange(of: workingDirectory) { syncWorkingDirectoryOnChange() }
            .onChange(of: state.claudeRateLimitActive) { applyFallbackModelIfNeeded() }
            .onChange(of: state.pendingChatNewProject) { handlePendingNewProject() }
            .onChange(of: state.pendingChatMessage) { handlePendingMessage() }
            .onChange(of: isActive) { syncOnActiveChange() }
            .onChange(of: inputText) { syncTriggerOnInputChange() }
            .onChange(of: selectedAgent) { pendingTriggerAgentName = nil }
            .onChange(of: state.tmetricKnownProjects) { _ in tryAutoMatchTMetricProject() }
            .onDisappear { handleDisappear() }
    }

    private var observedPanel: some View {
        mainPanel
            .onChange(of: messages) { syncMessagesOnChange() }
            .onChange(of: isStreaming) { syncStreamingOnChange() }
            .onChange(of: currentSessionId) { tab.sessionId = currentSessionId }
            .onChange(of: selectedModel) { tab.model = selectedModel }
            .onChange(of: selectedAgent) { tab.agentId = selectedAgent }
            .onChange(of: selectedPersonaId) { tab.personaId = selectedPersonaId }
    }

    private var mainPanel: some View {
        ZStack {
            HStack(spacing: 0) {
                // Left: File Explorer Panel
                if showFilePanel {
                    ChatFilePanel(
                        rootPath: workingDirectory ?? NSHomeDirectory(),
                        changedPaths: changedFilePaths,
                        newPaths: newFilePaths,
                        onInsertPath: { path in
                            if inputText.isEmpty { inputText = path }
                            else { inputText += " \(path)" }
                            inputFocused = true
                        },
                        onSelectNode: { node in
                            withAnimation(.spring(response: 0.3)) { filePreviewNode = node }
                            if let n = node {
                                changedFilePaths.remove(n.url.path)
                                newFilePaths.remove(n.url.path)
                                dismissedChangedPaths.insert(n.url.path)
                            }
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
                        // TMetric timer chip (visible when token is configured)
                        if !state.settings.tmetricApiToken.isEmpty {
                            tmetricTimerChip
                                .padding(.leading, 6)
                        }
                        Spacer()
                        Button {
                            withAnimation { state.hideSidebar.toggle() }
                        } label: {
                            Image(systemName: "sidebar.squares.left")
                                .font(.system(size: 13))
                                .foregroundStyle(state.hideSidebar ? accentColor : theme.secondaryText)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help(state.hideSidebar ? "Sidebar einblenden" : "Sidebar ausblenden")

                        Button {
                            withAnimation(.spring(response: 0.3)) { showFilePanel.toggle() }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 13))
                                .foregroundStyle(showFilePanel ? accentColor : theme.secondaryText)
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help(showFilePanel ? "File Explorer schließen" : "File Explorer öffnen")

                        if activeDiff != nil {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    diffPanelDismissed.toggle()
                                }
                            } label: {
                                Image(systemName: "sidebar.right")
                                    .font(.system(size: 13))
                                    .foregroundStyle(diffPanelDismissed ? theme.tertiaryText : accentColor)
                                    .frame(width: 26, height: 26)
                            }
                            .buttonStyle(.plain)
                            .help(diffPanelDismissed ? "Diff-Panel einblenden" : "Diff-Panel ausblenden")
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(height: 32)
                    .background(theme.windowBg)
                    .overlay(Rectangle().fill(theme.cardBorder).frame(height: 0.5), alignment: .bottom)

                    if messages.isEmpty {
                        emptyState
                            .onTapGesture { if !anyPickerOpen { closeAllPickers() } }
                    } else {
                        messagesArea
                            .onTapGesture { if !anyPickerOpen { closeAllPickers() } }
                    }

                    // Token Counter — direkt über der Texteingabe
                    tokenCounterBar

                    // Compact-Bestätigungsbanner
                    if showCompactBanner && !isCompacting {
                        compactConfirmBanner
                    }

                    // ⚡ Auto-Trigger-Badge — shown whenever trigger keywords are typed,
                    // even in empty sessions (independent of the token counter above).
                    // pendingTriggerAgentName is driven by onChange(of: inputText) below.
                    let displayTriggerName = autoTriggeredAgentName ?? pendingTriggerAgentName
                    let isTriggerPending = autoTriggeredAgentName == nil && pendingTriggerAgentName != nil
                    if selectedAgent.isEmpty, let trigName = displayTriggerName {
                        HStack(spacing: 0) {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                Text(trigName)
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(accentColor.opacity(isTriggerPending ? 0.07 : 0.12))
                                    .overlay(
                                        isTriggerPending
                                            ? Capsule().strokeBorder(accentColor.opacity(0.3), style: StrokeStyle(lineWidth: 0.8, dash: [3, 2]))
                                            : nil
                                    )
                            )
                            .opacity(isTriggerPending ? 0.8 : 1.0)
                            .help(isTriggerPending ? "Trigger erkannt — Agent '\(trigName)' wird beim Senden aktiviert" : "Auto-Trigger: Agent '\(trigName)' wurde für diese Nachricht aktiviert")
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 3)
                        .background(theme.windowBg)
                    }

                    // Persona Validation Banner
                    if isValidating {
                        PersonaValidatingBanner(theme: theme)
                    } else if let vr = validationResult {
                        PersonaValidationBanner(result: vr, theme: theme) {
                            validationResult = nil
                        }
                    }

                    // Sticky Banner: "Agent arbeitet" (live) → "Fertig" (3s) → weg
                    if isStreaming {
                        AgentRunningBanner(
                            message: messages.last(where: { $0.isStreaming }),
                            startTime: streamingStartTime,
                            theme: theme
                        )
                        .transition(.opacity)
                    } else if agentJustFinished {
                        AgentDoneBanner(
                            duration: lastStreamDuration,
                            stepCount: messages.last(where: { !$0.toolCalls.isEmpty })?.toolCalls.count,
                            theme: theme
                        )
                        .transition(.opacity)
                    }

                    inputBar
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: InputBarHeightKey.self, value: geo.size.height)
                        })
                }
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                // Picker overlays must be on THIS VStack (not inputBar) so the NSView parent
                // covers the full column height — otherwise buttons above inputBar bounds
                // are outside the NSView hit-test region and can't be clicked.
                .overlayPreferenceValue(PickerOriginAnchorKey.self) { anchor in
                    GeometryReader { proxy in
                        let xOffset = anchor.map { max(12, proxy[$0].x) } ?? 12
                        ZStack(alignment: .bottomLeading) {
                            Color.clear.allowsHitTesting(false)
                            pickerDropdownPanel
                                .padding(.leading, xOffset)
                                .padding(.bottom, 50) // 50 = 40pt above inputBar content + inputBar's 10pt bottom padding
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
                    }
                }
                .onPreferenceChange(InputBarHeightKey.self) { inputBarHeight = $0 }

                // Right: Plan- oder Diff-Panel (resizable) — bleibt geschlossen wenn vom User dismissed
                if (activePlan != nil || activeDiff != nil) && !diffPanelDismissed {
                    PanelResizeHandle(width: $diffPanelWidth, minWidth: 320, maxWidth: 900, growsRight: false)
                        .frame(width: 10)
                    unifiedRightPanel()
                        .frame(width: diffPanelWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isDragOver {
                dropOverlay
            }
        }
        .onDrop(of: [UTType.fileURL, UTType.image, UTType.png, UTType.jpeg, UTType.tiff, UTType.heic,
                     UTType("public.heif"), UTType("com.apple.icns")].compactMap { $0 },
                isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $showSnippetSheet) { snippetSheet }
        .background(PickerDismissMonitor(isActive: anyPickerOpen, onDismiss: { closeAllPickers() }))
        .task { await loadAvailableMCPs(); autoSelectMCPsForProject() }
    }

    private func handleAppear() {
        inputFocused = true
        if isActive, let msg = state.pendingChatMessage {
            state.pendingChatMessage = nil
            inputText = msg
        } else if !tab.inputText.isEmpty {
            inputText = tab.inputText
        }
        if isActive, let dir = state.pendingChatSetDirectory {
            state.pendingChatSetDirectory = nil
            workingDirectory = dir
            if let agentId = detectAgentForProject(dir) { selectedAgent = agentId }
            autoSelectMCPsForProject(dir)
        }
        if let wd = tab.workingDirectory { workingDirectory = wd }
        fetchGitBranch()
        if let sid = tab.sessionId {
            currentSessionId = sid
            sessionTitle = tab.title
            selectedModel = tab.model
            selectedAgent = tab.agentId
            selectedPersonaId = tab.personaId
            if tab.messages.isEmpty { resumeSession(sid) }
            else { messages = tab.messages }
        } else {
            messages = tab.messages
            selectedModel = tab.model
            selectedAgent = tab.agentId
            selectedPersonaId = tab.personaId
        }
        if selectedPersonaId.isEmpty { autoSelectPersonaForProject() }
        applyFallbackModelIfNeeded()
        tryAutoMatchTMetricProject()
    }

    private func handleDisappear() {
        tab.inputText = inputText
        let tabId = tab.id
        Task { await state.stopTMetricTimer(tabId: tabId) }
    }

    private func syncMessagesOnChange() {
        if !isStreaming { tab.messages = messages }
        if let cwd = workingDirectory {
            // ── Pfad-Hilfsfunktion ───────────────────────────────────────
            func resolve(_ raw: String) -> String {
                raw.hasPrefix("/") ? raw : cwd + (cwd.hasSuffix("/") ? "" : "/") + raw
            }

            // Letzter Assistenten-Message-Index — dessen Badges immer zeigen,
            // auch wenn der Pfad bereits dismissed wurde (neuer Agent-Run).
            let lastAssistantIdx = messages.indices.last(where: { messages[$0].role == .assistant })

            for (msgIdx, msg) in messages.enumerated() {
                let isLatestRun = msgIdx == lastAssistantIdx

                // Methode 1: git diff (optional, wenn Git vorhanden)
                if let diff = msg.gitDiff {
                    for file in parseDiffFiles(diff) {
                        let path = resolve(file.name)
                        if isLatestRun || !dismissedChangedPaths.contains(path) {
                            if isLatestRun { dismissedChangedPaths.remove(path) }
                            changedFilePaths.insert(path)
                            if file.isNew { newFilePaths.insert(path) }
                        }
                    }
                }

                // Methode 2: Write / Edit Tool-Calls direkt auswerten
                // Funktioniert auch ohne Git-Repo (z.B. neue Projekte).
                // Neuester Run: dismissedChangedPaths überschreiben → Badge erscheint wieder.
                // (Live-Streaming: Badges werden direkt in performSend gesetzt.)
                for call in msg.toolCalls {
                    let raw = call.input.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !raw.isEmpty else { continue }
                    switch call.name {
                    case "Write":
                        let path = resolve(raw)
                        if isLatestRun || !dismissedChangedPaths.contains(path) {
                            if isLatestRun { dismissedChangedPaths.remove(path) }
                            changedFilePaths.insert(path)
                            newFilePaths.insert(path)
                        }
                    case "Edit", "MultiEdit", "NotebookEdit":
                        let path = resolve(raw)
                        if isLatestRun || !dismissedChangedPaths.contains(path) {
                            if isLatestRun { dismissedChangedPaths.remove(path) }
                            changedFilePaths.insert(path)
                        }
                    default: break
                    }
                }
            }
        }
        let threshold = state.settings.autoCompactThreshold
        let totalIn = messages.filter { $0.role == .assistant }.last?.inputTokens ?? 0
        if threshold > 0 && totalIn >= threshold && !isCompacting && !isStreaming
           && !showCompactBanner && compactBannerSeenAt < threshold {
            showCompactBanner = true
            compactBannerSeenAt = totalIn
        }
    }

    private func syncStreamingOnChange() {
        tab.isStreaming = isStreaming
        if !isStreaming { tab.messages = messages }
        if isStreaming {
            streamingStartDate = Date()
            agentJustFinished = false          // neuer Turn — "Fertig" sofort löschen
        } else if let start = streamingStartDate {
            lastStreamDuration = Date().timeIntervalSince(start)
            streamingStartDate = nil
            // "Fertig"-Banner für 3 s zeigen, dann ausblenden
            withAnimation(.easeIn(duration: 0.2)) { agentJustFinished = true }
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(.easeOut(duration: 0.4)) { agentJustFinished = false }
            }
        }
        if !isStreaming && isCompacting { finishCompact() }
        if !isStreaming && !selectedPersonaId.isEmpty && !isValidating {
            triggerPersonaValidation()
        }
        if !isStreaming {
            Task { await state.historyService.loadProjects() }
        }
    }

    private func syncWorkingDirectoryOnChange() {
        tab.workingDirectory = workingDirectory
        fetchGitBranch()
        autoSelectPersonaForProject()
    }

    private func handlePendingNewProject() {
        guard isActive else { return }
        guard let path = state.pendingChatNewProject else { return }
        state.pendingChatNewProject = nil
        newSession()
        workingDirectory = path
        tab.title = URL(fileURLWithPath: path).lastPathComponent
        withAnimation(.spring(response: 0.3)) { showFilePanel = true }
        if let agentId = detectAgentForProject(path) { selectedAgent = agentId }
        autoSelectMCPsForProject(path)
    }

    private func handlePendingMessage() {
        guard isActive else { return }
        guard let msg = state.pendingChatMessage else { return }
        state.pendingChatMessage = nil
        inputText = msg
    }

    private func syncOnActiveChange() {
        if isActive {
            tryAutoMatchTMetricProject()
            handlePendingMessage()
            // Re-sync timer chip state from TMetric when switching to this tab
            Task { await state.syncTimerStateFromTMetric() }
            if let dir = state.pendingChatSetDirectory {
                state.pendingChatSetDirectory = nil
                workingDirectory = dir
                if let agentId = detectAgentForProject(dir) { selectedAgent = agentId }
                autoSelectMCPsForProject(dir)
            }
        } else {
            tab.inputText = inputText
            if isStreaming { tab.messages = messages }
        }
    }

    private func syncTriggerOnInputChange() {
        pendingTriggerAgentName = (selectedAgent.isEmpty && !inputText.isEmpty)
            ? autoTriggerAgent(for: inputText)?.name
            : nil
    }

    private func tryAutoMatchTMetricProject() {
        guard isActive else { return }                       // nur für aktiven Tab
        guard !didAutoMatchTMetric else { return }          // nur einmal pro Tab-Instanz
        guard tab.tmetricProjectId == nil else { return }   // nicht wenn schon gesetzt
        guard let wd = tab.workingDirectory else { return }
        let folder = URL(fileURLWithPath: wd).lastPathComponent
        guard let match = state.autoMatchTMetricProject(folderName: folder) else { return }
        didAutoMatchTMetric = true
        tab.tmetricProjectId   = match.id
        tab.tmetricProjectName = match.name
    }

    private func resumeSession(_ sessionId: String) {
        messages = []
        currentSessionId = sessionId
        sessionTitle = tab.title
        errorMessage = nil
        isAuthError = false

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
                    .font(.system(size: 14))
                    .foregroundStyle(accentColor.opacity(0.7))
            }
        }
        .padding(12)
        .allowsHitTesting(false)
    }

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard isActive else { return false }   // nie in inaktive Tabs droppen
        var handled = false
        for provider in providers {
            // 1. Prefer file URL — works for Finder drops and image files
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
                // 2. Raw image data — Photos app, Safari, screenshots, etc.
                // Try specific formats first, then use NSImage as universal fallback.
                let knownImageTypes: [String] = [
                    UTType.png.identifier,
                    UTType.jpeg.identifier,
                    UTType.tiff.identifier,
                    UTType.heic.identifier,
                    "public.heif",
                    UTType.image.identifier
                ]
                if let matchedType = knownImageTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) {
                    provider.loadDataRepresentation(forTypeIdentifier: matchedType) { data, _ in
                        guard let data else { return }
                        // Always save as PNG for consistent handling
                        let img = NSImage(data: data)
                        let pngData: Data?
                        if let img, let tiff = img.tiffRepresentation,
                           let rep = NSBitmapImageRep(data: tiff) {
                            pngData = rep.representation(using: .png, properties: [:])
                        } else {
                            pngData = data  // fallback: use raw data as-is
                        }
                        guard let finalData = pngData else { return }
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension("png")
                        try? finalData.write(to: tempURL)
                        DispatchQueue.main.async {
                            attachedFiles.append(AttachedFile(url: tempURL))
                        }
                    }
                    handled = true
                } else if provider.canLoadObject(ofClass: NSImage.self) {
                    // 3. NSImage fallback — handles any remaining image types
                    provider.loadObject(ofClass: NSImage.self) { obj, _ in
                        guard let img = obj as? NSImage,
                              let tiff = img.tiffRepresentation,
                              let rep = NSBitmapImageRep(data: tiff),
                              let pngData = rep.representation(using: .png, properties: [:]) else { return }
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension("png")
                        try? pngData.write(to: tempURL)
                        DispatchQueue.main.async {
                            attachedFiles.append(AttachedFile(url: tempURL))
                        }
                    }
                    handled = true
                }
            }
        }
        return handled
    }

    // MARK: - Subtle control strip (inside input card, bottom row)

    // MARK: - TMetric Timer Chip

    private var tmetricTimerChip: some View {
        HStack(spacing: 4) {
            // Project picker — reads/writes tab-local project only
            Menu {
                Button("Kein Projekt") {
                    tab.tmetricProjectId   = nil
                    tab.tmetricProjectName = ""
                }
                Divider()
                ForEach(state.tmetricKnownProjects) { p in
                    Button(p.name) {
                        tab.tmetricProjectId   = p.id
                        tab.tmetricProjectName = p.name
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if tab.tmetricIsTimerRunning {
                        Circle()
                            .fill(theme.statusGreen)
                            .frame(width: 6, height: 6)
                            .scaleEffect(chatTimerTick.timeIntervalSince1970.truncatingRemainder(dividingBy: 2) < 1 ? 1.0 : 0.65)
                            .animation(.easeInOut(duration: 0.5), value: chatTimerTick)
                    } else {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(tab.tmetricTimerError != nil ? theme.statusRed : theme.tertiaryText)
                    }
                    Text(tab.tmetricProjectName.isEmpty ? "Projekt wählen" : tab.tmetricProjectName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tab.tmetricIsTimerRunning ? theme.statusGreen : (tab.tmetricTimerError != nil ? theme.statusRed : theme.secondaryText))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 130)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            .menuStyle(.borderlessButton)

            // Elapsed time (running) + total booked time for project
            if tab.tmetricIsTimerRunning, let start = tab.tmetricTimerStart {
                Text(tmetricElapsed(from: start))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.statusGreen)
            }
            if let pid = tab.tmetricProjectId,
               let summary = state.tmetricProjects.first(where: { $0.id == pid }),
               summary.totalSeconds > 0 {
                Text("· \(summary.formattedDuration)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(tab.tmetricIsTimerRunning ? theme.statusGreen.opacity(0.7) : theme.tertiaryText)
            }

            // Error (visible, not just tooltip)
            if let err = tab.tmetricTimerError {
                Text(err.prefix(40))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.statusRed)
                    .lineLimit(1)
                    .onTapGesture { tab.tmetricTimerError = nil }
            }

            // Play / Stop
            if tab.tmetricIsTimerRunning {
                Button {
                    let tabId = tab.id
                    Task { await state.stopTMetricTimer(tabId: tabId) }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.statusRed)
                }
                .buttonStyle(.plain)
                .help("Timer stoppen")
            } else if tab.tmetricProjectId != nil {
                Button {
                    let tabId = tab.id
                    Task { await state.startTMetricTimer(tabId: tabId) }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)
                .help("Timer starten")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            tab.tmetricIsTimerRunning ? theme.statusGreen.opacity(0.08)
            : (tab.tmetricTimerError != nil ? theme.statusRed.opacity(0.08) : theme.rowBg),
            in: Capsule()
        )
        .help(tab.tmetricTimerError ?? (tab.tmetricIsTimerRunning ? "Timer läuft" : ""))
        // Timer only runs when TMetric is active — avoids 1s main-thread wakeups at idle
        .background(
            Group {
                if tab.tmetricIsTimerRunning {
                    Color.clear.onReceive(
                        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                    ) { date in chatTimerTick = date }
                }
            }
        )
    }

    private func tmetricElapsed(from start: Date) -> String {
        let s = max(0, Int(chatTimerTick.timeIntervalSince(start)))
        let h = s / 3600; let m = (s % 3600) / 60; let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

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
                .font(.system(size: 13))
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
                        MessageBubbleView(message: msg, onDiffTap: { diff in
                            activeDiff = diff
                        }, onAskForResult: msg.role == .assistant && !msg.toolCalls.isEmpty && !msg.isStreaming ? {
                            sendMessage(text: "Bitte teile dein abschließendes Ergebnis und deine konkreten Empfehlungen mit.")
                        } : nil, onContinue: msg.resultSubtype == "max_turns" ? {
                            sendMessage(text: "Bitte fahre dort fort, wo du aufgehört hast, und schließe die Aufgabe vollständig ab.")
                        } : nil)
                        .equatable()
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
                // New message added — animate only when not streaming (animated scrollTo
                // ist layout-affecting: treibt 60fps-Passes; bei 50 Token/s → Hang).
                scrollToBottom(proxy, animated: !isStreaming)
            }
            // Follow streaming output as it arrives — niemals animiert während Streaming
            .onChange(of: messages.last?.content) {
                scrollToBottom(proxy, animated: false)
            }
            // Streaming ended — jetzt einmal schön animiert ans Ende scrollen
            .onChange(of: isStreaming) {
                if !isStreaming { scrollToBottom(proxy, animated: true) }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        // Defer by one runloop so LazyVStack layout settles before scroll.
        // KRITISCH: animated=false während Streaming — withAnimation(.easeOut) auf scrollTo
        // ist eine layout-affecting Animation: triggert 60fps flushTransactions-Passes.
        // Bei 50 Token/s × 150ms Animation = 7+ überlappende Animationen → Layout-Loop → Hang.
        Task { @MainActor in
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    @State private var errorExpanded: Bool = false
    @State private var isAuthError: Bool = false
    @State private var isLoggingIn: Bool = false
    @State private var loginSucceeded: Bool = false

    private func errorBubble(_ text: String) -> some View {
        let isLong = text.count > 120
        let displayText = isLong && !errorExpanded ? String(text.prefix(120)) + "…" : text
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(theme.statusRed)
                    .padding(.top, 1)
                Text(displayText)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.primaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isLong {
                Button(errorExpanded ? "Weniger anzeigen" : "Vollständige Fehlermeldung anzeigen") {
                    errorExpanded.toggle()
                }
                .font(.system(size: 13))
                .foregroundStyle(theme.statusRed.opacity(0.8))
                .buttonStyle(.plain)
            }

            // Auth-Error: Login-Banner anzeigen
            if isAuthError {
                Divider().opacity(0.3)
                if loginSucceeded {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.statusGreen)
                        Text("Login erfolgreich — neue Nachricht senden.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.statusGreen)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Claude ist nicht eingeloggt.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                        Text("Starte den Login-Prozess — der Browser öffnet sich automatisch für die Authentifizierung.")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText)
                        Button {
                            startLogin()
                        } label: {
                            HStack(spacing: 6) {
                                if isLoggingIn {
                                    ProgressView().scaleEffect(0.7)
                                    Text("Warte auf Browser-Login…")
                                } else {
                                    Image(systemName: "arrow.right.circle.fill")
                                    Text("claude auth login starten")
                                }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(isLoggingIn ? Color.gray : Color.accentColor,
                                        in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoggingIn)
                    }
                }
            }
        }
        .padding(10)
        .background(theme.statusRed.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.statusRed.opacity(0.25), lineWidth: 0.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 6)
    }

    private func detectAuthError(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("authentication_error") || t.contains("invalid auth") ||
               t.contains("not logged in") || t.contains("unauthenticated") ||
               (t.contains("401") && (t.contains("error") || t.contains("auth")))
    }

    private func startLogin() {
        isLoggingIn = true
        loginSucceeded = false
        Task {
            do {
                try await state.cliService.login()
                await MainActor.run {
                    isLoggingIn = false
                    loginSucceeded = true
                    errorMessage = nil
                    isAuthError = false
                }
            } catch {
                await MainActor.run {
                    isLoggingIn = false
                    errorMessage = "Login fehlgeschlagen: \(error.localizedDescription)"
                    isAuthError = false
                }
            }
        }
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
                    // /agent <name> → Agent direkt setzen, nicht senden
                    if cmd.name.hasPrefix("/agent ") {
                        let agentName = String(cmd.name.dropFirst("/agent ".count))
                        if agentName == "–" {
                            selectedAgent = ""
                            autoTriggeredAgentName = nil
                        } else if let agent = state.agentService.agents.first(where: { $0.name == agentName }) {
                            selectedAgent = agent.id
                            autoTriggeredAgentName = nil
                        }
                        inputText = ""
                        showSlashMenu = false
                        return
                    }
                    if cmd.name == "/agent" {
                        inputText = ""; showSlashMenu = false; showAgentPicker = true; return
                    }
                    inputText = cmd.name
                    showSlashMenu = false
                    sendMessage()
                } label: {
                    HStack(spacing: 8) {
                        Text(cmd.name)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(accentColor)
                        Text(cmd.description)
                            .font(.system(size: 13))
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

    // MARK: - Compact-Bestätigungsbanner

    @ViewBuilder
    private var tokenCounterBar: some View {
        let assistantMessages = messages.filter { $0.role == .assistant }
        let totalIn  = assistantMessages.last?.inputTokens ?? 0
        let totalOut = assistantMessages.reduce(0) { $0 + $1.outputTokens }
        if totalIn > 0 || totalOut > 0 {
            let compactThreshold = state.settings.autoCompactThreshold
            let matchedModel     = KnownModel.all.first { $0.apiName == selectedModel }
            let contextWindow    = (matchedModel?.contextK ?? 200) * 1000
            let isWarning        = totalIn >= contextWindow / 2
            let isCritical       = totalIn >= contextWindow
            let tokenColor: Color = isCritical ? theme.statusRed : (isWarning ? theme.statusOrange : theme.secondaryText)
            let progress: Double  = min(1.0, Double(totalIn) / Double(contextWindow))
            let arcColor: Color   = isCritical ? theme.statusRed : (isWarning ? theme.statusOrange : theme.statusGreen)
            let pct = Int(progress * 100)
            let progressHelp: String = isCritical
                ? "Kontext voll (\(pct)%) — Compact dringend empfohlen"
                : isWarning
                    ? "Kontext halb voll (\(pct)%) — Zusammenfassung sinnvoll"
                    : "Kontext-Auslastung: \(pct)% von \(contextWindow / 1000)k"
            let totalInStr  = totalIn  >= 1000 ? String(format: "%.1fk", Double(totalIn)  / 1000) : "\(totalIn)"
            let totalOutStr = totalOut >= 1000 ? String(format: "%.1fk", Double(totalOut) / 1000) : "\(totalOut)"
            let compactStr  = compactThreshold >= 1000 ? String(format: "%.0fk", Double(compactThreshold) / 1000) : "\(compactThreshold)"
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(theme.cardBorder.opacity(0.3), lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(arcColor.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
                .frame(width: 16, height: 16)
                .help(progressHelp)
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(tokenColor.opacity(0.7))
                Text(totalInStr)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(tokenColor)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText.opacity(0.5))
                Text(totalOutStr)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                Text("tokens")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText.opacity(0.5))
                Text("/ \(contextWindow / 1000)k")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.secondaryText.opacity(0.4))
                if compactThreshold > 0 {
                    Text("· compact bei \(compactStr)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.secondaryText.opacity(0.3))
                }
                if !selectedAgent.isEmpty,
                   let agentName = state.agentService.agents.first(where: { $0.id == selectedAgent })?.name {
                    Text("· \(agentName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accentColor.opacity(0.75))
                }
                Spacer()
                if compactThreshold > 0 && totalIn >= compactThreshold && !isCompacting && !isStreaming {
                    compactButton(isCritical: isCritical)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(isCritical ? theme.statusRed.opacity(0.05) : theme.windowBg)
            .help("Session-Tokens: \(totalIn) Input · \(totalOut) Output · Kontext: \(contextWindow / 1000)k")
        }
    }

    @ViewBuilder
    private func compactButton(isCritical: Bool) -> some View {
        let tint: Color = isCritical ? theme.statusRed : theme.statusOrange
        Button { compactSession() } label: {
            HStack(spacing: 3) {
                Image(systemName: "scissors")
                    .font(.system(size: 11, weight: .medium))
                Text(isCritical ? "Compact jetzt!" : "Compact")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(tint.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(isCritical ? "Kontext-Limit erreicht — Konversation jetzt verdichten" : "Kontext ist halb voll — Konversation verdichten spart Tokens")
    }

    private var compactConfirmBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.statusOrange)
            Text("Kontext-Limit fast erreicht — Zusammenfassung empfohlen.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            Spacer()
            Button {
                showCompactBanner = false
                compactSession()
            } label: {
                Text("Jetzt")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(theme.statusOrange, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showCompactBanner = false }
            } label: {
                Text("Später")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(theme.statusOrange.opacity(0.10), in: RoundedRectangle(cornerRadius: 0))
        .overlay(Rectangle().fill(theme.statusOrange.opacity(0.25)).frame(height: 0.5), alignment: .top)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                        .frame(minHeight: 120, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .background(.clear)
                        .focused($inputFocused)
                        .onDrop(of: [UTType.fileURL, UTType.image, UTType.png, UTType.jpeg,
                                     UTType.tiff, UTType.heic, UTType("public.heif")].compactMap { $0 },
                                isTargeted: $isDragOver) { providers in
                            handleDrop(providers: providers)
                        }
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
                            .foregroundStyle((!inputText.isEmpty || !isStreaming) ? theme.statusRed.opacity(0.75) : theme.tertiaryText.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .help("Chat leeren")

                    Button {
                        isStreaming ? stopStreaming() : sendMessage()
                    } label: {
                        Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(isStreaming ? theme.statusRed : (canSend ? accentColor : theme.tertiaryText.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend && !isStreaming)
                }
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            // ─── Word count / routing feedback badge ───
            orchestratorRoutingBadge

            // ─── Subtle control strip ───
            controlStrip
        }
        .overlay(isDragOver ? RoundedRectangle(cornerRadius: 0).strokeBorder(accentColor.opacity(0.6), lineWidth: 1.5) : nil)
        .overlay(Rectangle().fill(theme.cardBorder).frame(height: 0.5), alignment: .top)
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
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(theme.statusGreen)
                        Text("~\(disabledCount * 7)k Tokens gespart")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.statusGreen)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.statusGreen.opacity(0.06))
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
                let autoTrigId = (autoTriggeredAgentName ?? pendingTriggerAgentName).flatMap { n in
                    state.agentService.agents.first { $0.name == n }?.id
                }
                pickerRow(label: "Kein Agent", selected: selectedAgent.isEmpty && autoTrigId == nil) {
                    selectedAgent = ""; showAgentPicker = false
                }
                ForEach(state.agentService.agents) { a in
                    pickerRow(label: a.name, selected: selectedAgent == a.id || (selectedAgent.isEmpty && a.id == autoTrigId)) {
                        selectedAgent = a.id; showAgentPicker = false
                    }
                }
            }
            .modifier(panelStyle)
        } else if showOrchPicker {
            VStack(alignment: .leading, spacing: 0) {
                // Header mit Anzahl aktiver Agents
                HStack(spacing: 6) {
                    Text("AGENTS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                        .kerning(0.5)
                    if !selectedOrchestrators.isEmpty {
                        Text("\(selectedOrchestrators.count) aktiv")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(accentColor.opacity(0.15)))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                Divider().padding(.horizontal, 6)
                ForEach(state.agentService.agents.filter { !$0.isPersona }) { a in
                    orchRow(label: a.name, selected: selectedOrchestrators.contains(a.id)) {
                        if selectedOrchestrators.contains(a.id) {
                            selectedOrchestrators.remove(a.id)
                        } else {
                            selectedOrchestrators.insert(a.id)
                        }
                    }
                }
                if !selectedOrchestrators.isEmpty {
                    Divider().padding(.horizontal, 6)
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
                        .font(.system(size: 13))
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
        } else if showPersonaPicker {
            let personas = state.agentService.agents.filter { $0.isPersona }
            VStack(alignment: .leading, spacing: 0) {
                pickerSectionHeader("KUNDEN-PERSONA")
                pickerRow(label: "Keine Persona", selected: selectedPersonaId.isEmpty) {
                    selectedPersonaId = ""; validationResult = nil; showPersonaPicker = false
                }
                if personas.isEmpty {
                    Text("Noch keine Personas angelegt")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                } else {
                    ForEach(personas) { p in
                        let label = p.customerName.flatMap { $0.isEmpty ? nil : $0 } ?? p.name
                        let sublabel = p.industry.flatMap { $0.isEmpty ? nil : $0 }
                        VStack(alignment: .leading, spacing: 1) {
                            pickerRow(label: label, selected: selectedPersonaId == p.id) {
                                selectedPersonaId = p.id; validationResult = nil; showPersonaPicker = false
                            }
                            if let sub = sublabel {
                                Text(sub)
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.tertiaryText)
                                    .padding(.leading, 30).padding(.bottom, 3)
                            }
                        }
                    }
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
                            .font(.system(size: 11))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    if disabledCount > 0 {
                        Text("~\(tokenSavings)k ↓")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.statusGreen)
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
                            .font(.system(size: 11, weight: .medium))
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
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(activeMCPIds == Set(["__none__"]) ? theme.statusRed : theme.tertiaryText)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(activeMCPIds == Set(["__none__"]) ? theme.statusRed.opacity(0.10) : theme.cardBg, in: Capsule())
                            .overlay(Capsule().strokeBorder(activeMCPIds == Set(["__none__"]) ? theme.statusRed.opacity(0.4) : theme.cardBorder, lineWidth: 0.5))
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
                    .fill(effectiveActive ? theme.statusGreen : theme.tertiaryText.opacity(0.3))
                    .frame(width: 5, height: 5)
                Text(server.name)
                    .font(.system(size: 12, weight: effectiveActive ? .medium : .regular))
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

    // Returns (json, useStrictMode).
    // claude.ai OAuth-MCPs (name prefix "claude.ai ") cannot be included in --mcp-config JSON
    // because `claude mcp get` fails for them — they are managed transparently by the claude.ai
    // session. When they are among the selected servers, --strict-mcp-config must be disabled
    // (strict mode would block them since they can't appear in the JSON).
    private func buildMCPConfigJSON() async -> (String?, Bool) {
        // activeMCPIds leer = alle aktiv → kein --strict-mcp-config nötig
        guard !activeMCPIds.isEmpty else { return (nil, true) }
        // "__none__" = wirklich alle deaktivieren
        if activeMCPIds == Set(["__none__"]) {
            return ("{\"mcpServers\":{}}", true)
        }

        let selectedServers = availableMCPs.filter { activeMCPIds.contains($0.id) }
        // OAuth-MCPs are managed by the claude.ai session — they cannot be configured via JSON
        let hasOAuthMCPs = selectedServers.contains { $0.name.hasPrefix("claude.ai ") }
        let regularServers = selectedServers.filter { !$0.name.hasPrefix("claude.ai ") }

        // If only OAuth MCPs selected: no JSON needed, claude handles them automatically
        if regularServers.isEmpty {
            return (nil, false)
        }

        var mcpServers: [String: Any] = [:]
        for server in regularServers {
            // Config lazy laden und cachen
            if mcpConfigs[server.id] == nil {
                if let cfg = await state.cliService.getMCPServerConfig(name: server.name) {
                    mcpConfigs[server.id] = cfg
                }
            }
            guard let config = mcpConfigs[server.id] else {
                // Fallback: use detail (URL/command) when getMCPServerConfig fails
                let detailUrl = server.detail
                if (server.type == "http" || server.type == "sse") && !detailUrl.isEmpty && detailUrl.hasPrefix("http") {
                    mcpServers[server.name] = ["type": server.type, "url": detailUrl]
                } else if server.type == "unknown" && !detailUrl.isEmpty && detailUrl.hasPrefix("http") {
                    // Unknown type but looks like a URL → try http
                    mcpServers[server.name] = ["type": "http", "url": detailUrl]
                }
                // stdio without config: cannot reconstruct → skip (getMCPServerConfig must succeed)
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
              let json = String(data: data, encoding: .utf8) else { return (nil, true) }
        // Disable strict mode when OAuth MCPs are also selected (strict would block them)
        return (json, !hasOAuthMCPs)
    }

    /// Returns the active MCPServerConfig list for use with the GitHub/Copilot path.
    /// Mirrors buildMCPConfigJSON but returns typed configs instead of JSON.
    private func buildActiveMCPConfigs() async -> [MCPServerConfig] {
        guard !activeMCPIds.isEmpty else {
            // All active — return all available configs
            var configs: [MCPServerConfig] = []
            for server in availableMCPs {
                if mcpConfigs[server.id] == nil,
                   let cfg = await state.cliService.getMCPServerConfig(name: server.name) {
                    mcpConfigs[server.id] = cfg
                }
                if let cfg = mcpConfigs[server.id] { configs.append(cfg) }
            }
            return configs
        }
        if activeMCPIds == Set(["__none__"]) { return [] }

        var configs: [MCPServerConfig] = []
        for server in availableMCPs where activeMCPIds.contains(server.id) {
            if mcpConfigs[server.id] == nil,
               let cfg = await state.cliService.getMCPServerConfig(name: server.name) {
                mcpConfigs[server.id] = cfg
            }
            if let cfg = mcpConfigs[server.id] { configs.append(cfg) }
        }
        return configs
    }

    // MARK: - Load available MCPs

    // Ausgeblendete cloud-Server aus AppStorage (sync mit MCPView)
    @AppStorage("hiddenCloudMCPServers") private var hiddenMCPServersRaw: String = ""
    private var hiddenMCPNames: Set<String> {
        Set(hiddenMCPServersRaw.split(separator: "|").map(String.init))
    }

    private func loadAvailableMCPs() async {
        isLoadingMCPs = true
        defer { isLoadingMCPs = false }
        let servers = await state.cliService.listMCPServers()
        let hidden = hiddenMCPNames
        // Fehlerhafte und lokal ausgeblendete Server nicht anzeigen
        availableMCPs = servers.filter {
            if case .error = $0.status { return false }
            if hidden.contains($0.name) { return false }
            return true
        }
    }

    /// Wählt beim Öffnen eines Projekts passende MCPs vor.
    /// memory + sequential-thinking sind immer aktiv.
    /// Weitere Server werden anhand des Projektpfads erkannt.
    private func autoSelectMCPsForProject(_ path: String? = nil) {
        guard !availableMCPs.isEmpty else { return }

        // Immer aktive Basis-Server
        let alwaysOn: Set<String> = ["memory", "sequential-thinking"]

        // Agent-spezifische MCPs wenn ein Agent erkannt wurde
        var agentMCPs: Set<String> = []
        if !selectedAgent.isEmpty,
           let agent = state.agentService.agents.first(where: { $0.id == selectedAgent }) {
            agentMCPs = Set(agent.requiredMCPs)
        }

        let wanted = alwaysOn.union(agentMCPs)
        let matched = Set(availableMCPs.filter { wanted.contains($0.name) }.map(\.id))

        // Nur setzen wenn aktuell noch im Default-Zustand (alle oder keiner)
        if activeMCPIds.isEmpty || activeMCPIds == Set(["__none__"]) {
            activeMCPIds = matched.isEmpty ? [] : matched
        } else {
            // Basis-Server nachrüsten ohne bestehende Auswahl zu überschreiben
            let baseIds = Set(availableMCPs.filter { alwaysOn.contains($0.name) }.map(\.id))
            activeMCPIds.formUnion(baseIds)
        }
    }

    // Generic upward-opening themed picker button — just the button, no overlay (overlay is at inputBar level)
    private func pickerButton<Content: View>(
        icon: String,
        label: String,
        active: Bool,
        isPresented: Binding<Bool>,
        maxLabelWidth: CGFloat = 80,
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
                    .font(.system(size: 12))
                    .foregroundStyle(active ? accentColor : theme.secondaryText)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(active ? accentColor : theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: maxLabelWidth)
                Image(systemName: isPresented.wrappedValue ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.tertiaryText.opacity(0.70))
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .anchorPreference(key: PickerOriginAnchorKey.self, value: .topLeading) { anchor in
            isPresented.wrappedValue ? anchor : nil
        }
    }

    // Single row for single-select pickers (hover-capable)
    private func pickerRow(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        PickerRowView(label: label, selected: selected, accent: accentColor, fg: theme.primaryText, action: action)
    }

    private func pickerSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
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
    @ViewBuilder
    private var orchestratorRoutingBadge: some View {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let wordCount = trimmed.isEmpty ? 0 : trimmed.split(separator: " ").count

        if wordCount > 0 {
            let info = routingBadgeInfo(wordCount: wordCount, trimmed: trimmed)
            HStack(spacing: 5) {
                Circle()
                    .fill(info.color)
                    .frame(width: 5, height: 5)
                Text(info.label)
                    .font(.system(size: 11))
                    .foregroundStyle(info.color)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.2), value: wordCount)
        }
    }

    private func routingBadgeInfo(wordCount: Int, trimmed: String) -> (color: Color, label: String) {
        let complex = isComplexTask(trimmed)
        let workerCount = state.agentService.agents.filter { !$0.isPersona }.count

        // ── Follow-Up in bestehendem Orchestrator-Kontext (unabhängig von orchestratorMode)
        if !orchestratorHistory.isEmpty {
            let intent = classifyFollowUp(trimmed)
            switch intent {
            case .chat:
                return (theme.tertiaryText, "\(wordCount) Wörter · Chat-Antwort")
            case .fast:
                return (accentColor, "\(wordCount) Wörter · ⚡ Schnell-Orchestrierung")
            case .full:
                return (accentColor, "\(wordCount) Wörter · Volle Orchestrierung")
            }
        }

        // ── Frischer Start ────────────────────────────────────────────────────
        if orchestratorMode {
            let selectedWorkerCount = state.agentService.agents.filter {
                !$0.isPersona && selectedOrchestrators.contains($0.id)
            }.count
            if selectedWorkerCount < 2 {
                return (.red, "\(wordCount) Wörter · ⚠ Nur \(selectedWorkerCount) Agent — min. 2 nötig")
            }
            return (accentColor, "\(wordCount) Wörter · Orchestrierung startet (\(selectedWorkerCount) Agents)")
        } else if complex && workerCount >= 2 {
            return (.orange, "\(wordCount) Wörter · Auto-Orchestrierung (KI wählt Agents)")
        } else {
            return (theme.tertiaryText, "\(wordCount == 1 ? "1 Wort" : "\(wordCount) Wörter")")
        }
    }

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
                    if activeMCPIds.isEmpty { return "Alle MCPs" }
                    let active = availableMCPs.filter { activeMCPIds.contains($0.id) }
                    let maxShow = 3
                    if active.count <= maxShow {
                        return active.map(\.name).joined(separator: " · ")
                    } else {
                        return active.prefix(maxShow).map(\.name).joined(separator: " · ") + " +\(active.count - maxShow)"
                    }
                }()
                pickerButton(
                    icon: "server.rack",
                    label: mcpLabel,
                    active: mcpActive,
                    isPresented: $showMCPPicker,
                    maxLabelWidth: 160
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
                    .font(.system(size: 11, weight: .semibold))
                Text(currentRouteSource.label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(currentRouteSource == .copilot ? theme.statusOrange : accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                (currentRouteSource == .copilot ? theme.statusOrange : accentColor).opacity(0.10),
                in: Capsule()
            )
            .help("Aktuelle Routing-Quelle")

            // Agent picker (single mode only)
            if !orchestratorMode && !state.agentService.agents.isEmpty {
                stripSep
                // Compute both name + id outside the escaping closure so they capture correctly
                let autoTrigName = autoTriggeredAgentName ?? pendingTriggerAgentName
                let autoTrigId: String? = autoTrigName.flatMap { n in
                    state.agentService.agents.first { $0.name == n }?.id
                }
                pickerButton(
                    icon: !selectedAgent.isEmpty ? "person.crop.circle"
                          : (autoTrigId != nil ? "bolt.fill" : "person.crop.circle"),
                    label: !selectedAgent.isEmpty
                           ? (state.agentService.agents.first { $0.id == selectedAgent }?.name ?? "Agent")
                           : (autoTrigName ?? "Agent"),
                    active: !selectedAgent.isEmpty || autoTrigId != nil,
                    isPresented: $showAgentPicker
                ) {
                    pickerRow(label: "Kein Agent", selected: selectedAgent.isEmpty && autoTrigId == nil) {
                        selectedAgent = ""
                        showAgentPicker = false
                    }
                    ForEach(state.agentService.agents) { a in
                        pickerRow(label: a.name, selected: selectedAgent == a.id || (selectedAgent.isEmpty && a.id == autoTrigId)) {
                            selectedAgent = a.id
                            showAgentPicker = false
                        }
                    }
                }
            }

            // Persona validation picker (only personas, teal color)
            let personas = state.agentService.agents.filter { $0.isPersona }
            if !personas.isEmpty {
                let personaColor = Color(red: 0.04, green: 0.57, blue: 0.70)
                let selectedPersona = personas.first { $0.id == selectedPersonaId }
                stripSep
                pickerButton(
                    icon: "person.2.fill",
                    label: selectedPersona?.customerName ?? selectedPersona?.name ?? "Persona",
                    active: !selectedPersonaId.isEmpty,
                    isPresented: $showPersonaPicker
                ) {
                    pickerRow(label: "Keine Persona", selected: selectedPersonaId.isEmpty) {
                        selectedPersonaId = ""
                        validationResult = nil
                        showPersonaPicker = false
                    }
                    ForEach(personas) { p in
                        pickerRow(
                            label: p.customerName.flatMap { $0.isEmpty ? nil : $0 } ?? p.name,
                            selected: selectedPersonaId == p.id
                        ) {
                            selectedPersonaId = p.id
                            validationResult = nil
                            showPersonaPicker = false
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
                    ForEach(state.agentService.agents.filter { !$0.isPersona }) { a in
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
                        .font(.system(size: 13))
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
                    .font(.system(size: 11))
                    .foregroundStyle(accentColor.opacity(0.5))
                Text(sessionTitle)
                    .font(.system(size: 11))
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(workingDirectory != nil ? accentColor : theme.secondaryText.opacity(0.75))
                Text(workingDirectory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "~")
                    .font(.system(size: 13))
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
            if !showFilePanel {
                withAnimation(.spring(response: 0.3)) { showFilePanel = true }
            }
        }
    }

    private func fetchGitBranch() {
        guard let cwd = workingDirectory, !cwd.isEmpty else {
            gitBranch = nil
            gitBranches = []
            return
        }
        // DispatchQueue.global statt Task.detached — waitUntilExit() darf keinen
        // Swift-Concurrency-Thread blockieren (erschöpft den Cooperative Thread Pool).
        DispatchQueue.global(qos: .utility).async {
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

            DispatchQueue.main.async {
                self.gitBranch = current
                self.gitBranches = branchList
            }
        }
    }

    private func switchGitBranch(_ branch: String) {
        guard let cwd = workingDirectory, !cwd.isEmpty else { return }
        // DispatchQueue.global statt Task.detached — waitUntilExit() blockiert sonst Cooperative Thread Pool.
        DispatchQueue.global(qos: .utility).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = ["-C", cwd, "checkout", branch]
            proc.standardOutput = Pipe()
            proc.standardError = Pipe()
            try? proc.run()
            proc.waitUntilExit()
            DispatchQueue.main.async {
                self.gitBranch = branch
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
                .font(.system(size: 12))
                .foregroundStyle(file.isImage ? Color.blue : accentColor)
            Text(file.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)
            Button {
                attachedFiles.removeAll { $0.id == file.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
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

    /// Returns the best matching agent ID for a project directory.
    /// Priority 1: agent whose projectDirectory or associatedProjects contains the path.
    /// Priority 2: file-extension scan for known project types.
    private func detectAgentForProject(_ path: String) -> String? {
        let agents = state.agentService.agents.filter { !$0.isPersona }

        if let exact = agents.first(where: {
            $0.projectDirectory == path || $0.associatedProjects.contains(path)
        }) {
            return exact.id
        }

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: path) else { return nil }
        let exts  = Set(files.map { URL(fileURLWithPath: $0).pathExtension.lowercased() })
        let names = files.map { $0.lowercased() }

        let excelExts: Set<String> = ["xlsm", "xlsb", "bas", "xls", "xlsx"]
        if !exts.isDisjoint(with: excelExts) {
            return agents.first { $0.id.contains("excel") || $0.id.contains("vba") }?.id
        }

        let makeMarkers = ["make.json", "blueprint"]
        if names.contains(where: { n in makeMarkers.contains(where: { n.contains($0) }) }) {
            return agents.first { $0.id.contains("workflow") || $0.id.contains("make") }?.id
        }

        return nil
    }

    private func newSession() {
        // Laufende Orchestrierung/Stream ZUERST abbrechen — sonst schreibt der Hintergrund-Task
        // nach dem Leeren von messages[] auf gecachte Indizes → Index-out-of-bounds Crash.
        // Betrifft nur DIESEN Tab (eigener @State streamingTask); andere Tabs laufen unberührt weiter.
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        withAnimation(.spring(response: 0.3)) {
            messages = []
            currentSessionId = nil
            errorMessage = nil
            isAuthError = false
            attachedFiles = []
            sessionTitle = ""
            orchestratorHistory = []
            masterTodos = []
            masterGoal = ""
            lastAgentTasks = [:]
            lastOrchestratorAgents = []
            autoTriggeredAgentName = nil
            showCompactBanner = false
            compactBannerSeenAt = 0
            activePlan = nil
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

    // MARK: - Auto-Orchestrierung mit LLM-Validierung

    /// Startet Auto-Orchestrierung, prüft aber per Haiku ob wirklich nötig.
    /// Wenn Haiku "SINGLE" sagt → normaler Einzelagent-Pfad.
    private func sendAutoOrchestration() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        // ── Vorarbeit wie im Einzelagent-Pfad — gilt für SINGLE- UND MULTI-Ausgang ──
        // (sendOrchestrator wiederholt diese Schritte nicht; ohne sie läuft der SINGLE-
        //  Fallback im Home- statt Projektverzeichnis und der Tab bleibt unbenannt.)
        let wasEmpty = messages.isEmpty
        state.tmetricActivity()
        if tab.tmetricProjectId != nil, !tab.tmetricIsTimerRunning {
            let tabId = tab.id
            Task { await state.startTMetricTimer(tabId: tabId) }
        }
        if currentSessionId == nil, workingDirectory == nil {
            openDirectoryPicker()
        }

        // User-Nachricht sofort anzeigen
        inputText = ""
        errorMessage = nil
        isAuthError = false

        let sentFiles = attachedFiles
        attachedFiles = []

        var displayText = text
        if !sentFiles.isEmpty {
            let names = sentFiles.map { $0.name }.joined(separator: ", ")
            let prefix = "[\(sentFiles.count == 1 ? "Datei" : "\(sentFiles.count) Dateien"): \(names)]"
            displayText = text.isEmpty ? prefix : "\(prefix)\n\(text)"
        }

        // Tab beim ersten Beitrag automatisch umbenennen
        if wasEmpty {
            let titleSource = text.isEmpty ? displayText : text
            let words = titleSource.split(separator: " ").prefix(5).joined(separator: " ")
            let trimmed = String(words.prefix(40))
            if !trimmed.isEmpty { tab.title = trimmed }
        }

        messages.append(ChatMessage(role: .user, content: displayText))

        // Routing-Hinweis anzeigen während Haiku entscheidet
        var routingMsg = ChatMessage(role: .assistant, content: "🔍 *KI prüft Routing…*", isStreaming: true)
        routingMsg.model = "Haiku 4.5"
        messages.append(routingMsg)
        let routingIdx = messages.count - 1
        isStreaming = true; streamingStartTime = Date()

        let workAgents = state.agentService.agents.filter { !$0.isPersona }

        streamingTask = Task { @MainActor in
            // LLM-basierte Agent-Auswahl: Haiku bestimmt WELCHE Agents relevant sind
            let haikuAgents = await selectRelevantAgents(text, agents: workAgents)
            guard !Task.isCancelled else {
                if messages.indices.contains(routingIdx) { messages.remove(at: routingIdx) }
                isStreaming = false; return
            }

            // Trigger-Keywords als zweites Signal: Trigger-gematchte Agents immer einschließen.
            // Warum: isComplexTask() feuert VOR der Trigger-Prüfung → Trigger-Badge zeigt aber
            // Agent wird ignoriert. Durch Merge wird der Trigger-Agent garantiert berücksichtigt.
            let triggerAgents = workAgents.filter { agent in
                !agent.effectiveTriggers.isEmpty &&
                agent.effectiveTriggers.contains { inputMatchesTrigger(text, trigger: $0) }
            }
            var selectedAgents = haikuAgents
            for ta in triggerAgents where !selectedAgents.contains(where: { $0.id == ta.id }) {
                selectedAgents.insert(ta, at: 0)  // Trigger-Agent vorne → höhere Priorität
            }

            if selectedAgents.count >= 2 {
                // ── ≥2 relevante Agents → Orchestrierung ──────────────────────
                let agentNames = selectedAgents.map { $0.name }.joined(separator: ", ")
                if messages.indices.contains(routingIdx) {
                    messages[routingIdx].content = "🤖 **Auto-Orchestrierung** — \(agentNames)"
                    messages[routingIdx].isStreaming = false
                    messages[routingIdx].finishedCleanly = true
                }
                // User-Msg entfernen (sendOrchestrator fügt sie selbst hinzu)
                if let lastUserIdx = messages.lastIndex(where: { $0.role == .user }) {
                    messages.remove(at: lastUserIdx)
                }
                inputText = text
                attachedFiles = sentFiles
                isStreaming = false
                sendOrchestrator(autoAgentList: selectedAgents)
            } else {
                // ── 0–1 relevante Agents → Einzelagent ────────────────────────
                // Bei genau 1 Treffer DEN Spezialisten verwenden (sein System-Prompt + MCP),
                // sonst generischer Einzelagent.
                let soloAgent = selectedAgents.first
                if messages.indices.contains(routingIdx) {
                    if let solo = soloAgent {
                        messages[routingIdx].content = "👤 **Einzelagent** — \(solo.name) *(ein Spezialist reicht)*"
                        messages[routingIdx].isStreaming = false
                        messages[routingIdx].finishedCleanly = true
                    } else {
                        messages.remove(at: routingIdx)
                    }
                }
                // Spezialist wirklich anwenden: frische Agent-Session erzwingen, damit sein
                // System-Prompt (fullSystemPrompt) injiziert wird — bei laufender Session
                // (currentSessionId != nil) würde performSend den Agent-Prompt sonst überspringen.
                if soloAgent != nil { currentSessionId = nil }

                let assistantMsg = ChatMessage(role: .assistant, content: "", isStreaming: true)
                messages.append(assistantMsg)
                let assistantIndex = messages.count - 1

                let fileDirs = Array(Set(sentFiles.map { $0.url.deletingLastPathComponent().path }))
                let imgPaths = sentFiles.filter { $0.isImage }.map { $0.url.path }

                // MarkItDown: binary files konvertieren, dann Message aufbauen
                let markdownCache = await buildMarkItDownCache(from: sentFiles)
                let fullMessage = buildMessageWithAttachments(text: text, files: sentFiles,
                                                              forGitHub: false,
                                                              markdownCache: markdownCache)

                // Agent-Modell nutzen wenn gesetzt (sonst Default/Fallback)
                let baseModel = state.claudeRateLimitActive && state.settings.copilotFallbackEnabled
                    ? state.settings.copilotFallbackModel
                    : selectedModel
                let effectiveModel = (soloAgent.map { $0.model.isEmpty ? baseModel : $0.model }) ?? baseModel

                await performSend(
                    message: fullMessage.isEmpty ? text : fullMessage,
                    assistantIndex: assistantIndex,
                    model: effectiveModel,
                    agentOverride: soloAgent?.id,
                    addDirs: fileDirs,
                    cliImagePaths: imgPaths
                )
            }
        }
    }

    // MARK: - Orchestrator: Analyse → Master Plan → Execute → Synthesize

    /// - autoAgentList: wenn gesetzt, werden diese Agents verwendet (Auto-Orchestrierung).
    ///   nil = Agents aus selectedOrchestrators (manuell).
    /// - skipAnalysis: true = Phase 0 überspringen (bei Follow-Up mit bestehendem Kontext)
    private func sendOrchestrator(autoAgentList: [AgentDefinition]? = nil, skipAnalysis: Bool = false) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachedFiles.isEmpty, !isStreaming else { return }

        // Agents-Check VOR allen Seiteneffekten (vor inputText-Clear, vor message.append)
        let isAutoOrchestrated = autoAgentList != nil
        let agents = (autoAgentList ?? state.agentService.agents.filter { selectedOrchestrators.contains($0.id) })
            .filter { !$0.isPersona }
        guard agents.count >= 2 else {
            errorMessage = agents.isEmpty
                ? "Orchestrator: Keine Agents ausgewählt — bitte mindestens 2 Worker-Agents wählen."
                : "Orchestrator benötigt mindestens 2 Agents — nur \(agents.count) ausgewählt."
            return
        }

        inputText = ""
        errorMessage = nil
        isAuthError = false

        // Capture & clear attached files before the task runs
        let sentFiles = attachedFiles
        attachedFiles = []
        let imgPaths = sentFiles.filter { $0.isImage }.map { $0.url.path }
        let fileDirs = Array(Set(sentFiles.map { $0.url.deletingLastPathComponent().path }))

        var displayText = text
        if !sentFiles.isEmpty {
            let names = sentFiles.map { $0.name }.joined(separator: ", ")
            let prefix = "[\(sentFiles.count == 1 ? "Datei" : "\(sentFiles.count) Dateien"): \(names)]"
            displayText = text.isEmpty ? prefix : "\(prefix)\n\(text)"
        }

        messages.append(ChatMessage(role: .user, content: displayText))

        isStreaming = true; streamingStartTime = Date()
        orchestratorHistory.append((role: "user", content: displayText))
        lastOrchestratorAgents = agents

        streamingTask = Task { @MainActor in

            // ── Gemeinsame Infrastruktur: MCP + addDirs (Fix A) ──────────
            let (mcpJson, mcpStrict) = await buildMCPConfigJSON()
            var effectiveAddDirs = fileDirs
            if let wd = workingDirectory, !wd.isEmpty, !effectiveAddDirs.contains(wd) {
                effectiveAddDirs.insert(wd, at: 0)
            }
            // Orchestrator-Agents brauchen genug Turns für MCP-Tool-Aufrufe (Make/Linear).
            // settings.maxTurns gilt für normale Einzel-Chats; hier mindestens 15 Turns garantieren.
            let effectiveMaxTurns: Int? = state.settings.maxTurns > 0 ? max(state.settings.maxTurns, 15) : nil

            // ── Kontext aufbauen (Fix B: Chat-History erhalten) ──────────
            let priorContext: String
            if orchestratorHistory.count > 1 {
                // Bisherige Orchestrator-Runden
                let history = orchestratorHistory.dropLast()
                    .map { "\($0.role == "user" ? "Benutzer" : $0.role): \($0.content.prefix(500))" }
                    .joined(separator: "\n\n")
                priorContext = "\n\nBisheriger Konversationsverlauf:\n\(history)\n"
            } else if messages.count > 1 {
                // Erste Orchestrierung, aber vorheriger normaler Chat → injizieren
                let chatHistory = messages.dropLast()
                    .filter { $0.role == .user || $0.role == .assistant }
                    .suffix(10)
                    .map { "\($0.role == .user ? "Benutzer" : "Assistent"): \($0.content.prefix(300))" }
                    .joined(separator: "\n\n")
                let compactPart = compactedSummary.map { "\n\nZusammenfassung der vorherigen Konversation:\n\($0)\n" } ?? ""
                priorContext = "\n\nBisheriger Chat-Verlauf:\n\(chatHistory)\(compactPart)\n"
            } else {
                priorContext = ""
            }

            // Panel sofort öffnen
            diffPanelDismissed = false
            rightPanelShowsPlan = true
            activePlan = ""
            masterTodos = []
            masterGoal = ""

            let headerLine = isAutoOrchestrated
                ? "🤖 **Auto-Orchestrierung** — \(agents.map { $0.name }.joined(separator: ", "))\n\n"
                : skipAnalysis ? "⚡ **Schnell-Orchestrierung** *(Phase 0 übersprungen)*\n\n" : ""

            // ── Phase 0: Domain-Analyse (Haiku 4.5) — übersprungen bei skipAnalysis ──
            var planPlaceholder = ChatMessage(role: .assistant, content: "", isStreaming: true)
            planPlaceholder.model = "📊 Haiku 4.5"
            messages.append(planPlaceholder)
            let planIdx = messages.count - 1

            var agentAnalyses: [(name: String, analysis: String)] = []

            if !skipAnalysis {
                messages[planIdx].content = headerLine + "🔍 **Domain-Analyse** *(Haiku 4.5)*\n"

                for agent in agents {
                    guard !Task.isCancelled else { break }

                    let doneLines   = agentAnalyses.map { "✓ \($0.name)\n" }.joined()
                    let remaining   = agents.dropFirst(agentAnalyses.count + 1).map { "⬜ \($0.name)\n" }.joined()
                    messages[planIdx].content = headerLine
                        + "🔍 **Domain-Analyse** *(Haiku 4.5)*\n"
                        + doneLines + "⏳ \(agent.name)…\n" + remaining

                    let profile = agent.description.isEmpty
                        ? String(agent.promptBody.prefix(150))
                        : agent.description

                    let analysisPrompt = """
                    Agent-Profil: \(agent.name) — \(profile)

                    Aufgabe: \(text)

                    Beschreibe in max. 3 Sätzen: Was kannst du konkret beitragen? Welche Teilschritte und Abhängigkeiten siehst du?
                    """

                    var analysis = ""
                    let aStream = state.cliService.send(
                        message: analysisPrompt,
                        systemPrompt: "Antworte knapp und konkret auf Deutsch.",
                        model: "claude-haiku-4-5-20251001",
                        workingDirectory: workingDirectory,
                        addDirs: effectiveAddDirs,
                        skipPermissions: autoApprove,
                        mcpConfigJSON: mcpJson,
                        mcpStrictMode: mcpStrict,
                        imagePaths: imgPaths
                    )
                    do {
                        for try await event in aStream {
                            guard !Task.isCancelled else { break }
                            if case "assistant" = event.type, let content = event.message?.content {
                                for block in content where block.type == "text" {
                                    if let t = block.text, !t.isEmpty { analysis += t }
                                }
                            }
                        }
                    } catch { analysis = "(Analyse nicht verfügbar)" }

                    agentAnalyses.append((name: agent.name, analysis: analysis))
                }

                messages[planIdx].content = headerLine
                    + "🔍 **Domain-Analyse** *(Haiku 4.5)*\n"
                    + agentAnalyses.map { "✓ \($0.name)\n" }.joined()
            } else {
                messages[planIdx].content = headerLine + "⚡ Phase 0 übersprungen — nutze vorherigen Kontext\n"
            }

            // Abbruch-Check nach Phase 0
            guard !Task.isCancelled else {
                messages[planIdx].isStreaming = false
                messages.append(ChatMessage(role: .assistant,
                    content: "⏹ Orchestrierung abgebrochen."))
                isStreaming = false
                return
            }

            // ── Phase 1: Master Plan (Haiku 4.5) ─────────────────────────
            let analysisBlock = agentAnalyses.isEmpty
                ? "(Keine Analyse — Schnell-Modus mit Kontext aus vorheriger Runde)"
                : agentAnalyses.map { "**\($0.name):** \($0.analysis)" }.joined(separator: "\n")
            let agentNamesList = agents.map { $0.name }.joined(separator: ", ")

            let masterPlanPrompt = """
            Erstelle einen detaillierten, hierarchischen Master-Plan als strukturierte Todo-Liste.
            \(priorContext)
            Agent-Analysen:
            \(analysisBlock)

            Benutzer-Auftrag: \(text)

            Verfügbare Agents: \(agentNamesList)

            Antworte AUSSCHLIESSLICH in diesem Format — kein anderer Text:
            ZIEL: [Hauptziel in einem Satz — was am Ende erreicht sein soll]

            1. [Übergeordnete Phase oder Bereich — kein Agent zugewiesen]
               1.1 [Konkrete Teilaufgabe, max. 1 Satz] → AgentName
               1.2 [Andere Teilaufgabe, max. 1 Satz] → AgentName

            2. [Übergeordnete Phase oder Bereich]
               2.1 [Teilaufgabe] → AgentName

            Regeln:
            - ZIEL: immer als erste Zeile
            - X. = Top-Level Kategorie (kein Agent); X.Y = ausführbarer Schritt mit "→ AgentName"
            - Nur Agents aus der Liste verwenden: \(agentNamesList)
            - Lieber 2-3 fokussierte Schritte als viele oberflächliche
            - Jeder Agent erhält eine ANDERE Aufgabe — keine Wiederholungen
            - Beziehe bisherigen Kontext ein wenn vorhanden
            """

            messages[planIdx].content += "\n**🗂 Master Plan** *(Haiku 4.5)*\n"

            var planText = ""
            let planStream = state.cliService.send(
                message: masterPlanPrompt,
                systemPrompt: "Erstelle strukturierte Pläne. Halte das Format exakt ein.",
                model: "claude-haiku-4-5-20251001",
                workingDirectory: workingDirectory,
                addDirs: effectiveAddDirs,
                skipPermissions: autoApprove,
                mcpConfigJSON: mcpJson,
                mcpStrictMode: mcpStrict,
                imagePaths: imgPaths
            )
            do {
                for try await event in planStream {
                    guard !Task.isCancelled else { break }
                    if case "assistant" = event.type, let content = event.message?.content {
                        for block in content where block.type == "text" {
                            if let t = block.text, !t.isEmpty {
                                planText += t
                                messages[planIdx].content += t
                                activePlan = planText
                            }
                        }
                    }
                }
            } catch {
                messages[planIdx].content += "\n⚠️ Plan-Fehler: \(error.localizedDescription)"
            }
            messages[planIdx].isStreaming = false
            messages[planIdx].finishedCleanly = true
            activePlan = planText

            // Abbruch-Check nach Phase 1
            guard !Task.isCancelled else {
                messages.append(ChatMessage(role: .assistant,
                    content: "⏹ Orchestrierung nach Plan-Phase abgebrochen."))
                isStreaming = false
                return
            }

            // Master Plan parsen → Todos + AgentTasks
            let (parsedGoal, parsedTodos, parsedAgentTasks) = parseMasterPlan(planText, agents: agents)
            masterGoal = parsedGoal

            let agentTasks: [String: String]
            if !parsedAgentTasks.isEmpty {
                masterTodos = parsedTodos
                agentTasks = parsedAgentTasks
            } else {
                let legacyTasks = parseOrchestratorPlan(planText, agents: agents)
                agentTasks = legacyTasks
                masterTodos = legacyTasks.compactMap { (agentId, task) in
                    guard let agent = agents.first(where: { $0.id == agentId }) else { return nil }
                    return MasterTodoItem(id: agentId, number: "•", title: task,
                                         assignedAgent: agent.name, level: 1, status: .pending)
                }
            }

            // Plan für Follow-Up-Reuse speichern (Fix C)
            lastAgentTasks = agentTasks

            // ── Phase 2: Execution mit Master-Plan-Kontext-Anker ──────────
            var agentOutputs: [(name: String, output: String)] = []
            var progressMsg = ChatMessage(role: .assistant, content: "", isStreaming: true)
            progressMsg.model = "⚙️ Agents"
            messages.append(progressMsg)
            let progressIdx = messages.count - 1
            messages[progressIdx].content = ""

            for agent in agents {
                guard !Task.isCancelled else { break }

                guard let specificTask = agentTasks[agent.id] else {
                    setTodoStatus(for: agent.name, to: .skipped)
                    let doneLines = agentOutputs.map { "✓ **\($0.name)** — \($0.output.count) Zeichen\n" }.joined()
                    messages[progressIdx].content = doneLines + "⏸ \(agent.name) — nicht relevant, übersprungen\n"
                    continue
                }

                setTodoStatus(for: agent.name, to: .active)
                let doneLines = agentOutputs.map { "✓ **\($0.name)** — \($0.output.count) Zeichen\n" }.joined()
                messages[progressIdx].content = doneLines + "⏳ \(agent.name)…"

                var contextParts: [String] = []

                let planAnchor = formatMasterPlanText()
                contextParts.append("══════ MASTER PLAN — Kontext-Anker ══════\n\(planAnchor)\n══════════════════════════════════════")

                if orchestratorHistory.count > 1 {
                    let history = orchestratorHistory.dropLast()
                        .map { "\($0.role == "user" ? "Benutzer" : $0.role): \($0.content.prefix(800))" }
                        .joined(separator: "\n\n")
                    contextParts.append("Bisheriger Konversationsverlauf:\n\(history)")
                }
                if !agentOutputs.isEmpty {
                    let prior = agentOutputs
                        .map { "**\($0.name):**\n\($0.output)" }
                        .joined(separator: "\n\n")
                    contextParts.append("Ergebnisse der anderen Agents in dieser Runde:\n\(prior)")
                }

                let contextBlock = contextParts.joined(separator: "\n\n---\n\n") + "\n\n---\n\n"

                let stepLabel = masterTodos
                    .first(where: { $0.assignedAgent?.lowercased() == agent.name.lowercased() && $0.level == 1 })
                    .map { " (Schritt \($0.number))" } ?? ""

                let agentMessage = """
                \(contextBlock)DEINE AUFGABE\(stepLabel): \(specificTask)

                Ursprünglicher Benutzer-Auftrag: \(text)
                Fokussiere dich NUR auf deinen Schritt. Verliere nie das Gesamtziel aus den Augen.
                Wiederhole nicht, was andere Agents bereits geliefert haben.
                """

                let agentSystemPrompt = state.agentService.fullSystemPrompt(for: agent)
                var agentOutput = ""

                let stream = state.cliService.send(
                    message: agentMessage,
                    systemPrompt: agentSystemPrompt,
                    model: agent.model.isEmpty ? selectedModel : agent.model,
                    workingDirectory: agent.projectDirectory ?? workingDirectory,
                    addDirs: effectiveAddDirs,
                    skipPermissions: autoApprove,
                    maxTurns: effectiveMaxTurns,
                    mcpConfigJSON: mcpJson,
                    mcpStrictMode: mcpStrict,
                    imagePaths: imgPaths
                )
                do {
                    for try await event in stream {
                        guard !Task.isCancelled else { break }
                        switch event.type {
                        case "assistant":
                            guard let content = event.message?.content else { break }
                            for block in content where block.type == "text" {
                                if let t = block.text, !t.isEmpty { agentOutput += t }
                            }
                        default: break
                        }
                    }
                } catch {
                    agentOutput += "\n⚠️ \(error.localizedDescription)"
                }
                agentOutputs.append((name: agent.name, output: agentOutput))

                setTodoStatus(for: agent.name, to: .done)

                let allDoneLines = agentOutputs.map { "✓ **\($0.name)** — \($0.output.count) Zeichen\n" }.joined()
                messages[progressIdx].content = allDoneLines
            }
            messages[progressIdx].isStreaming = false
            messages[progressIdx].finishedCleanly = true

            // Abbruch-Check nach Phase 2
            if Task.isCancelled {
                let partial = agentOutputs.map { "✓ \($0.name)" }.joined(separator: ", ")
                messages.append(ChatMessage(role: .assistant,
                    content: "⏹ Orchestrierung abgebrochen nach Phase 2. Fertige Agents: \(partial.isEmpty ? "keine" : partial)"))
                isStreaming = false
                return
            }

            // ── Phase 3: Synthesis ────────────────────────────────────────
            guard !agentOutputs.isEmpty else {
                messages.append(ChatMessage(role: .assistant,
                    content: "⚠️ Kein Agent konnte ausgeführt werden — der Master Plan konnte keinem verfügbaren Agent zugewiesen werden. Bitte Agents prüfen."))
                isStreaming = false
                return
            }

            if agents.count > 1 {
                var synthPlaceholder = ChatMessage(role: .assistant, content: "", isStreaming: true)
                synthPlaceholder.model = "📋 Synthese"
                messages.append(synthPlaceholder)
                let synthIdx = messages.count - 1
                messages[synthIdx].content = "**📋 Synthese**\n"

                let allOutputs = agentOutputs
                    .map { "**\($0.name):**\n\($0.output)" }
                    .joined(separator: "\n\n---\n\n")

                let synthPrompt = """
                Du fasst die Ergebnisse mehrerer Agents zusammen.

                🎯 Gesamtziel: \(masterGoal.isEmpty ? text : masterGoal)

                Master Plan (zur Orientierung):
                \(formatMasterPlanText())

                Benutzer-Auftrag: \(text)

                Agent-Ergebnisse:
                \(allOutputs)

                Erstelle eine zusammenhängende Zusammenfassung:
                1. Kernpunkte aus allen Agent-Beiträgen (bezogen auf das Gesamtziel)
                2. Wie die Teile zusammenspielen
                3. Konkrete nächste Schritte (falls relevant)

                Sei prägnant — kein Wiederholen der Einzelergebnisse, sondern Mehrwert durch Verknüpfung.
                """

                var synthOutput = ""
                let synthStream = state.cliService.send(
                    message: synthPrompt,
                    systemPrompt: "Du fasst Ergebnisse zusammen. Sei prägnant und strukturiert.",
                    model: selectedModel,
                    workingDirectory: workingDirectory,
                    addDirs: effectiveAddDirs,
                    skipPermissions: autoApprove,
                    mcpConfigJSON: mcpJson,
                    mcpStrictMode: mcpStrict,
                    imagePaths: imgPaths
                )
                do {
                    for try await event in synthStream {
                        guard !Task.isCancelled else { break }
                        if case "assistant" = event.type, let content = event.message?.content {
                            for block in content where block.type == "text" {
                                if let t = block.text, !t.isEmpty {
                                    synthOutput += t
                                    messages[synthIdx].content += t
                                }
                            }
                        }
                    }
                } catch {
                    messages[synthIdx].content += "\n⚠️ Synthese-Fehler: \(error.localizedDescription)"
                }
                messages[synthIdx].isStreaming = false
                messages[synthIdx].finishedCleanly = true

                let fullRoundSummary = agentOutputs
                    .map { "[\($0.name)] \($0.output.prefix(500))" }
                    .joined(separator: "\n\n")
                orchestratorHistory.append((role: "orchestrator",
                    content: "Plan:\n\(planText.prefix(300))\n\nAgent-Ergebnisse:\n\(fullRoundSummary)\n\nSynthese:\n\(synthOutput.prefix(800))"))
            } else {
                if let first = agentOutputs.first {
                    var singleMsg = ChatMessage(role: .assistant, content: first.output)
                    singleMsg.model = first.name
                    messages.append(singleMsg)
                    orchestratorHistory.append((role: first.name, content: first.output.prefix(1000).description))
                }
            }

            isStreaming = false
        }
    }

    /// Parses "AGENT: Name\nAUFGABE: ..." blocks from the orchestrator plan (Legacy-Format).
    private func parseOrchestratorPlan(_ plan: String, agents: [AgentDefinition]) -> [String: String] {
        var result: [String: String] = [:]
        let lines = plan.components(separatedBy: .newlines)
        var currentAgentId: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("AGENT:") {
                let name = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "**", with: "")
                currentAgentId = agents.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }?.id
            } else if trimmed.uppercased().hasPrefix("AUFGABE:"), let agentId = currentAgentId {
                result[agentId] = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                currentAgentId = nil
            }
        }
        return result
    }

    /// Parst den hierarchischen Master-Plan (ZIEL: + 1. / 1.1 → Agent Format).
    /// Gibt (goal, todos, agentTasks) zurück.
    ///
    /// Robust gegenüber LLM-Artefakten:
    ///  - Markdown-Fettdruck (**), führende Listenzeichen (-, •, *)
    ///  - Trailing-Interpunktion am Nummerntoken (1.1:, 1.1., 1))
    ///  - Mehrere Sub-Items pro Agent → werden zusammengeführt
    ///  - Canonical Agent-Name gespeichert (nicht roher LLM-String)
    ///  - Exakter Match bevorzugt vor fuzzy Contains
    private func parseMasterPlan(_ plan: String, agents: [AgentDefinition])
        -> (goal: String, todos: [MasterTodoItem], agentTasks: [String: String]) {

        var goal = ""
        var todos: [MasterTodoItem] = []
        var agentTasks: [String: String] = [:]
        let trailingPunct = CharacterSet(charactersIn: ".:)")
        let listChars    = CharacterSet(charactersIn: "-•* \t")

        for line in plan.components(separatedBy: .newlines) {
            let raw = line.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }

            // ZIEL: Zeile
            if raw.uppercased().hasPrefix("ZIEL:") {
                goal = String(raw.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Normalisieren: **Markdown** + führende Listenzeichen entfernen
            let normalized = raw
                .replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: listChars)
            guard !normalized.isEmpty else { continue }

            // Nummerierungstoken + Rest extrahieren
            let spaceIdx = normalized.firstIndex(of: " ") ?? normalized.endIndex
            // Trailing-Interpunktion am Token abschneiden ("1.1:" → "1.1", "1." → "1")
            let firstToken = String(normalized[..<spaceIdx])
                .trimmingCharacters(in: trailingPunct)
            let rest = spaceIdx < normalized.endIndex
                ? String(normalized[normalized.index(after: spaceIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                : ""
            guard !rest.isEmpty else { continue }

            let dotParts = firstToken.components(separatedBy: ".")

            // Sub-Item: "1.1" — beide Komponenten nicht leer + beide Int
            if dotParts.count == 2,
               let _ = Int(dotParts[0]),
               !dotParts[1].isEmpty,
               let _ = Int(dotParts[1]) {

                let num = firstToken
                let sep = rest.contains("→") ? "→" : "->"
                let parts = rest.components(separatedBy: sep)
                let title = parts[0].trimmingCharacters(in: .whitespaces)
                let rawAgent: String? = parts.count > 1
                    ? parts[1].trimmingCharacters(in: .whitespaces) : nil

                // Exakter Match bevorzugt, dann fuzzy Contains
                // → verhindert Kreuz-Matches bei ähnlichen Namen ("Designer" vs "UX-Designer")
                let resolved: AgentDefinition? = rawAgent.flatMap { name in
                    agents.first(where: {
                        $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                    }) ?? agents.first(where: {
                        !$0.name.isEmpty && (
                            $0.name.lowercased().contains(name.lowercased())
                            || name.lowercased().contains($0.name.lowercased())
                        )
                    })
                }
                // Canonical name (aus Agent-Profil, nicht roher LLM-String) für zuverlässige Status-Updates
                let canonicalName = resolved?.name ?? rawAgent

                if let agent = resolved {
                    // Mehrere Sub-Items pro Agent → zusammenführen statt überschreiben
                    if let existing = agentTasks[agent.id] {
                        agentTasks[agent.id] = existing + "\n- " + title
                    } else {
                        agentTasks[agent.id] = title
                    }
                }

                todos.append(MasterTodoItem(id: num, number: num, title: title,
                                            assignedAgent: canonicalName, level: 1, status: .pending))
                continue
            }

            // Top-Level Kategorie: "1." → dotParts = ["1",""] oder "1" (nach trailing strip)
            let isTopLevel = (dotParts.count == 2 && Int(dotParts[0]) != nil && dotParts[1].isEmpty)
                          || (dotParts.count == 1 && Int(dotParts[0]) != nil
                              && (raw.contains(".") || raw.contains(")")))
            if isTopLevel {
                let num = dotParts[0]
                todos.append(MasterTodoItem(id: "\(num).", number: "\(num).", title: rest,
                                            assignedAgent: nil, level: 0, status: .pending))
            }
        }

        return (goal, todos, agentTasks)
    }

    /// Setzt Status aller Todos die einem Agent gehören — nutzt canonical name (exact lowercase).
    private func setTodoStatus(for agentName: String, to status: MasterTodoStatus) {
        let key = agentName.lowercased()
        for j in masterTodos.indices where masterTodos[j].assignedAgent?.lowercased() == key {
            masterTodos[j].status = status
        }
    }

    /// Formatiert den aktuellen Master Plan als lesbaren Text für Kontext-Injektion.
    private func formatMasterPlanText() -> String {
        var lines: [String] = []
        if !masterGoal.isEmpty {
            lines.append("🎯 ZIEL: \(masterGoal)")
            lines.append("")
        }
        for item in masterTodos {
            let indent = item.level == 1 ? "   " : ""
            let icon: String
            switch item.status {
            case .pending:  icon = "○"
            case .active:   icon = "▶"
            case .done:     icon = "✓"
            case .skipped:  icon = "⏸"
            case .blocked:  icon = "⚠"
            }
            let agent = item.assignedAgent.map { " → \($0)" } ?? ""
            lines.append("\(indent)\(icon) \(item.number) \(item.title)\(agent)")
        }
        return lines.joined(separator: "\n")
    }

    @State private var streamingTask: Task<Void, Never>? = nil

    private func stopStreaming() {
        streamingTask?.cancel()
        isStreaming = false
        if var last = messages.last, last.isStreaming {
            last.isStreaming = false
            messages[messages.count - 1] = last
        }
    }

    /// Builds the text message for the AI. Images are handled separately via buildImageAttachments().
    // MARK: - MarkItDown helpers

    /// Runs /opt/homebrew/bin/markitdown on a file in a background thread and returns Markdown.
    private func markItDownConvert(url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/markitdown")
                process.arguments = [url.path]
                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = Pipe()
                do {
                    try process.launch()
                    process.waitUntilExit()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let text = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: text.flatMap { $0.isEmpty ? nil : $0 })
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Pre-converts all MarkItDown-target files in parallel and returns a [URL: Markdown] cache.
    private func buildMarkItDownCache(from files: [AttachedFile]) async -> [URL: String] {
        var cache: [URL: String] = [:]
        await withTaskGroup(of: (URL, String?).self) { group in
            for file in files where file.isMarkItDownTarget {
                group.addTask { (file.url, await self.markItDownConvert(url: file.url)) }
            }
            for await (url, markdown) in group {
                if let md = markdown { cache[url] = md }
            }
        }
        return cache
    }

    private func buildMessageWithAttachments(text: String, files: [AttachedFile],
                                             forGitHub: Bool = false,
                                             markdownCache: [URL: String] = [:]) -> String {
        guard !files.isEmpty else { return text }

        var parts: [String] = []

        // Threshold: text files larger than 10 KB are passed by path reference instead of inline
        // to avoid stdin overflow in long sessions with --resume.
        let inlineLimit = 10_240
        // MarkItDown output is text — allow up to 50 KB inline before truncating
        let markdownLimit = 50_000

        for file in files {
            if file.isText, let content = try? String(contentsOf: file.url, encoding: .utf8) {
                if content.utf8.count <= inlineLimit {
                    let ext = file.url.pathExtension.lowercased()
                    let lang = ext.isEmpty ? "" : ext
                    parts.append("**\(file.name)**\n```\(lang)\n\(content)\n```")
                } else {
                    // Large text file — pass by path so Claude CLI reads it via tools
                    parts.append("**\(file.name)** (Textdatei, \(content.count) Zeichen, Pfad: `\(file.url.path)`)\nBitte lies diese Datei über den Pfad ein.")
                }
            } else if file.url.pathExtension.lowercased() == "pdf",
                      let pdf = PDFDocument(url: file.url) {
                var pdfText = ""
                for i in 0..<pdf.pageCount {
                    if let page = pdf.page(at: i),
                       let pageText = page.string, !pageText.isEmpty { pdfText += pageText + "\n" }
                }
                let pdfTrimmed = pdfText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pdfTrimmed.isEmpty, pdfTrimmed.utf8.count <= inlineLimit {
                    parts.append("**\(file.name)** (PDF, \(pdf.pageCount) Seiten)\n```\n\(pdfTrimmed)\n```")
                } else if !pdfTrimmed.isEmpty {
                    // Large PDF — pass by path reference
                    parts.append("**\(file.name)** (PDF, \(pdf.pageCount) Seiten, Pfad: `\(file.url.path)`)\nBitte lies diese Datei über den Pfad ein.")
                } else {
                    parts.append("**\(file.name)** (PDF, \(pdf.pageCount) Seiten — kein extrahierbarer Text, Pfad: `\(file.url.path)`)")
                }
            } else if file.isImage {
                if forGitHub {
                    parts.append("[Bild: \(file.name)]")
                } else {
                    parts.append("[Bild angehängt: \(file.name), Pfad: \(file.url.path)\nBitte analysiere dieses Bild.]")
                }
            } else if let markdown = markdownCache[file.url] {
                // MarkItDown-konvertierter Inhalt (DOCX, PPTX, XLSX, EPUB, …)
                if markdown.utf8.count <= markdownLimit {
                    parts.append("**\(file.name)** (via MarkItDown):\n\n\(markdown)")
                } else {
                    let truncated = String(markdown.prefix(markdownLimit))
                    parts.append("**\(file.name)** (via MarkItDown, gekürzt auf \(markdownLimit/1000) KB):\n\n\(truncated)\n\n[… weiterer Inhalt unter: `\(file.url.path)`]")
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
        case "/agent":
            showAgentPicker = true
            return true
        case _ where lower.hasPrefix("/agent "):
            let name = String(lower.dropFirst("/agent ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "–" || name == "-" || name == "none" {
                selectedAgent = ""; autoTriggeredAgentName = nil
                messages.append(ChatMessage(role: .assistant, content: "Agent zurückgesetzt."))
            } else if let agent = state.agentService.agents.first(where: { $0.name.lowercased() == name || $0.id.lowercased() == name }) {
                selectedAgent = agent.id; autoTriggeredAgentName = nil
                messages.append(ChatMessage(role: .assistant, content: "Agent gewechselt zu **\(agent.name)**."))
            } else {
                let names = state.agentService.agents.map { "• \($0.name)" }.joined(separator: "\n")
                messages.append(ChatMessage(role: .assistant, content: "Agent **\(name)** nicht gefunden.\n\nVerfügbare Agents:\n\(names)"))
            }
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
        isStreaming = true; streamingStartTime = Date()
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
        // Defense-in-depth: laufenden Task abbrechen bevor messages ersetzt wird (analog newSession)
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        // Neue Session starten — Summary bleibt als Kontext erhalten
        let summaryNote = ChatMessage(
            role: .assistant,
            content: "**Konversation verdichtet.** Zusammenfassung wird als Kontext für weitere Nachrichten verwendet:\n\n\(summary)"
        )
        withAnimation(.spring(response: 0.3)) {
            messages = [summaryNote]
            currentSessionId = nil
            errorMessage = nil
            isAuthError = false
            sessionTitle = ""
            orchestratorHistory = []
            masterTodos = []
            masterGoal = ""
            lastAgentTasks = [:]
            lastOrchestratorAgents = []
            activePlan = nil
        }
    }

    // MARK: - Persona Validation

    /// Auto-selects the persona whose projectDirectory matches the current workingDirectory.
    private func autoSelectPersonaForProject() {
        guard let cwd = workingDirectory, !cwd.isEmpty else { return }
        // Normalize paths (resolve symlinks, trailing slash)
        let normalize: (String) -> String = { path in
            URL(fileURLWithPath: path).standardized.path
        }
        let cwdNorm = normalize(cwd)
        if let match = state.agentService.agents.first(where: {
            $0.isPersona &&
            !($0.projectDirectory ?? "").isEmpty &&
            normalize($0.projectDirectory!) == cwdNorm
        }) {
            if selectedPersonaId != match.id {
                selectedPersonaId = match.id
                validationResult = nil
            }
        }
    }

    private func triggerPersonaValidation() {
        guard !selectedPersonaId.isEmpty,
              let persona = state.agentService.agents.first(where: { $0.id == selectedPersonaId }),
              persona.isPersona else { return }

        // Find last user → assistant exchange
        let lastAssistant = messages.last(where: { $0.role == .assistant && !$0.content.isEmpty })
        guard let assistantMsg = lastAssistant else { return }

        // Find the user message that preceded it
        var userRequest = ""
        if let idx = messages.lastIndex(where: { $0.id == assistantMsg.id }),
           idx > 0 {
            let preceding = messages[..<idx].reversed().first(where: { $0.role == .user })
            userRequest = preceding?.content ?? ""
        }

        isValidating = true
        validationResult = nil

        Task { @MainActor in
            let result = await state.agentService.validateWithPersona(
                persona: persona,
                userRequest: userRequest,
                taskOutput: assistantMsg.content
            )
            isValidating = false
            switch result {
            case .success(let vr): validationResult = vr
            case .failure: break   // Silent fail — don't interrupt workflow
            }
        }
    }

    private func sendMessage(text: String) {
        inputText = text
        sendMessage()
    }

    private func sendMessage() {
        // ── Slash-Commands ZUERST ─────────────────────────────────────────────
        // Muss vor dem Smart-Routing stehen, sonst werden /clear, /new, /compact, /model
        // im orchestratorMode als Aufgabentext an die Pipeline geschickt.
        // Gleiche Gate-Bedingung wie unten: Dateipfade (/Users/...) gehen als Text durch.
        let routingText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if routingText.hasPrefix("/"),
           !routingText.contains(" ") || routingText == "/compact"
               || routingText.hasPrefix("/files") || routingText.hasPrefix("/agent") {
            if handleSlashCommand(routingText) { return }
        }

        // ── Smart Routing ─────────────────────────────────────────────────────
        let workerAgentCount = state.agentService.agents.filter { !$0.isPersona }.count

        if !orchestratorHistory.isEmpty {
            // ── Follow-Up in bestehendem Orchestrator-Kontext ────────────────────
            // Gilt für manuellen UND Auto-Orchestrator-Modus (orchestratorHistory unabhängig von Mode)
            let intent = classifyFollowUp(routingText)
            switch intent {
            case .chat:
                break  // Fall-through zum Einzelagent-Pfad (einfache Antwort/Danke)
            case .fast:
                sendOrchestrator(skipAnalysis: true); return
            case .full:
                sendOrchestrator(); return
            }
        } else if orchestratorMode {
            // ── Frischer Start, manuell ausgewählte Agents ───────────────────────
            sendOrchestrator()
            return
        } else if isComplexTask(routingText) && !routingText.isEmpty && workerAgentCount >= 2 {
            // ── Kein Orchestrator, komplexe Aufgabe → Auto-Orchestrierung ──────
            // Haiku wählt die relevanten Agents aus (nicht MULTI/SINGLE, sondern WELCHE)
            sendAutoOrchestration()
            return
        }

        // ── Normaler Einzel-Agent-Pfad ────────────────────────────────────────
        // Slash-Commands wurden bereits am Anfang der Funktion behandelt.
        let text = routingText
        guard !text.isEmpty || !attachedFiles.isEmpty, !isStreaming else { return }
        state.tmetricActivity()
        if tab.tmetricProjectId != nil, !tab.tmetricIsTimerRunning {
            let tabId = tab.id
            Task { await state.startTMetricTimer(tabId: tabId) }
        }

        // Prompt for working directory before first message of a new session
        if currentSessionId == nil, workingDirectory == nil {
            openDirectoryPicker()
        }

        let isGitHub = (state.claudeRateLimitActive && state.settings.copilotFallbackEnabled
            ? state.settings.copilotFallbackModel
            : selectedModel).hasPrefix("github/")
        inputText = ""
        let sentFiles = attachedFiles
        attachedFiles = []
        errorMessage = nil
        isAuthError = false

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

        isStreaming = true; streamingStartTime = Date()

        // Bei einfacher Anfrage mit Orchestrator-Auswahl → besten gewählten Agent nehmen
        // Sonst: Trigger-Keywords prüfen
        let triggerAgent: String? = orchestratorMode
            ? selectedOrchestrators.first
            : autoTriggerAgent(for: text)?.id
        // ⚡ Trigger-Badge: Name für Token-Counter-Anzeige merken
        if let tid = triggerAgent,
           let agentName = state.agentService.agents.first(where: { $0.id == tid })?.name {
            autoTriggeredAgentName = agentName
        } else if triggerAgent == nil {
            autoTriggeredAgentName = nil
        }

        streamingTask = Task { @MainActor in
            // MarkItDown: binary files (DOCX, XLSX, PPTX, EPUB, …) vor dem Send konvertieren
            let markdownCache = await buildMarkItDownCache(from: sentFiles)
            let fullMessage = buildMessageWithAttachments(text: text, files: sentFiles,
                                                          forGitHub: isGitHub,
                                                          markdownCache: markdownCache)
            // Collect dirs from all attached files (images + large text/PDF files passed by path)
            let fileDirs = Array(Set(sentFiles.map { $0.url.deletingLastPathComponent().path }))
            let imageAttachments = buildImageAttachments(from: sentFiles)
            // Collect actual image file paths for Claude CLI (base64 via stream-json)
            let imgPaths = sentFiles.filter { $0.isImage }.map { $0.url.path }
            await performSend(
                message: fullMessage,
                assistantIndex: assistantIndex,
                model: state.claudeRateLimitActive && state.settings.copilotFallbackEnabled
                    ? state.settings.copilotFallbackModel
                    : selectedModel,
                agentOverride: triggerAgent,
                addDirs: fileDirs,
                imageAttachments: imageAttachments,
                cliImagePaths: imgPaths
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
        cliImagePaths: [String] = [],
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

        // Agent-Anzeigename für den Antwort-Header setzen (statt rohem Modell)
        if let agentId = effectiveAgent,
           let agentDef = state.agentService.agents.first(where: { $0.id == agentId }),
           messages.indices.contains(assistantIndex) {
            messages[assistantIndex].agentName = agentDef.name
        }

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

            // /files-Nachrichten aus der History extrahieren (starten mit "📂") und in System-Prompt
            // injizieren, damit sie nicht durch das History-Window rausfallen und korrekt als
            // Benutzerkontext (nicht als Assistent-Ausgabe) behandelt werden.
            let fileContextBlocks = allHistory
                .filter { $0.content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("📂") }
                .map { $0.content }
            let fileContextSection = fileContextBlocks.isEmpty ? nil
                : "Folgende Dateien wurden vom Benutzer in den Kontext geladen:\n\n" + fileContextBlocks.joined(separator: "\n\n")

            let historyMsgs = windowedHistory.compactMap { msg -> GitHubMessage? in
                // /files-Nachrichten nicht doppelt schicken (sie sind im System-Prompt)
                if msg.content.hasPrefix("📂") { return nil }
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
            // Datei-Kontext an System-Prompt anhängen
            if let fc = fileContextSection {
                ghSystemPrompt = ghSystemPrompt.map { "\($0)\n\n\(fc)" } ?? fc
            }
            stream = state.ghModelsService.send(
                message: message,
                model: model,
                systemPrompt: ghSystemPrompt,
                history: Array(historyMsgs),
                githubToken: state.settings.token,
                imageAttachments: imageAttachments,
                mcpConfigs: await buildActiveMCPConfigs()
            )
        } else {
            // Always include workingDirectory in --add-dir so Claude CLI can read project files
            var effectiveAddDirs = addDirs
            if let wd = workingDirectory, !wd.isEmpty, !effectiveAddDirs.contains(wd) {
                effectiveAddDirs.insert(wd, at: 0)
            }
            // Inject compacted summary as system prompt if no agent prompt is set
            let effectiveSystemPrompt = agentSystemPrompt ?? compactedSummary.map { "Konversationskontext (verdichtet):\n\($0)" }
            // Agents brauchen mehr Turns für Tool-Calls; mindestens 20 wenn ein Agent aktiv ist.
            let rawMaxTurns = state.settings.maxTurns > 0 ? state.settings.maxTurns : nil
            let effectiveMaxTurns: Int? = (effectiveAgent != nil) ? rawMaxTurns.map { max($0, 20) } : rawMaxTurns
            let (mcpJson, mcpStrict) = await buildMCPConfigJSON()
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
                mcpConfigJSON: mcpJson,
                mcpStrictMode: mcpStrict,
                imagePaths: cliImagePaths
            )
        }

        var pendingContent = ""
        var pendingTokenCount = 0

        do {
            for try await event in stream {
                guard messages.indices.contains(assistantIndex) else { break }
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
                                let toolInput = block.toolInput?.displayText ?? ""
                                let tool = ToolCall(
                                    name: name,
                                    input: toolInput,
                                    toolUseId: block.id
                                )
                                messages[assistantIndex].toolCalls.append(tool)
                                // TodoWrite: Todo-Liste sofort in Message speichern
                                if name == "TodoWrite", let todos = block.toolInput?.todos {
                                    messages[assistantIndex].currentTodos = todos
                                }
                                // ── Datei-Badge direkt beim Empfang setzen ────────────
                                // Nicht auf syncMessagesOnChange warten (onChange-Timing
                                // unzuverlässig). Hier live beim Streaming updaten.
                                if !toolInput.isEmpty, let cwd = workingDirectory {
                                    func resolveBadgePath(_ raw: String) -> String {
                                        raw.hasPrefix("/") ? raw : cwd + (cwd.hasSuffix("/") ? "" : "/") + raw
                                    }
                                    switch name {
                                    case "Write":
                                        let p = resolveBadgePath(toolInput)
                                        dismissedChangedPaths.remove(p)
                                        changedFilePaths.insert(p)
                                        newFilePaths.insert(p)
                                    case "Edit", "MultiEdit", "NotebookEdit":
                                        let p = resolveBadgePath(toolInput)
                                        dismissedChangedPaths.remove(p)
                                        changedFilePaths.insert(p)
                                    default: break
                                    }
                                }
                            default: break
                            }
                        }
                    }
                    if let m = event.message?.model {
                        messages[assistantIndex].model = m
                    }
                    if let usage = event.message?.usage {
                        messages[assistantIndex].inputTokens = usage.totalInputTokens
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
                                // Notify LinearView to refresh when a Linear MCP tool completes
                                if messages[assistantIndex].toolCalls[idx].name.hasPrefix("mcp__linear__") {
                                    NotificationCenter.default.post(name: .linearMCPDidChange, object: nil)
                                }
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
                    // Sauberes Ende markieren (kein Fehler)
                    if event.isError != true {
                        messages[assistantIndex].finishedCleanly = true
                    }

                    // Handle error result (e.g. rate-limit / usage-limit)
                    if event.isError == true {
                        let contentText = messages.indices.contains(assistantIndex)
                            ? messages[assistantIndex].content : ""
                        let eventResult = event.result ?? ""
                        let subtype = event.subtype ?? ""
                        let combined = (contentText + " " + eventResult).lowercased()

                        // Non-critical status endings: max_turns or user-interrupted.
                        // Content was already streamed → just finalize normally, no error bubble.
                        let isStatusEnd = subtype == "error_max_turns" || subtype == "interrupted"
                        if isStatusEnd {
                            if !pendingContent.isEmpty, messages.indices.contains(assistantIndex) {
                                messages[assistantIndex].content += pendingContent
                                pendingContent = ""
                                pendingTokenCount = 0
                            }
                            if messages.indices.contains(assistantIndex) {
                                messages[assistantIndex].isStreaming = false
                                // Max-Turns: eigenen Subtype setzen (≠ Fehler, ≠ User-Abbruch)
                                messages[assistantIndex].resultSubtype =
                                    subtype == "error_max_turns" ? "max_turns" : "interrupted"
                            }
                            isStreaming = false
                            return
                        }

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
                                    cliImagePaths: cliImagePaths,
                                    isFallbackAttempt: true
                                )
                                return
                            }
                        }

                        // Fehlermeldung: contentText ist bereits in der Nachrichtenblase sichtbar —
                        // nicht doppelt als Error-Bubble anzeigen. Stattdessen eventResult
                        // (CLI-seitige Fehlerbeschreibung) oder subtype verwenden.
                        let bestError: String
                        if !eventResult.isEmpty && eventResult != contentText {
                            bestError = eventResult
                        } else if !subtype.isEmpty {
                            bestError = "Fehler: \(subtype)"
                        } else {
                            bestError = "Claude hat einen Fehler zurückgegeben (kein Fehlertext vom CLI erhalten)."
                        }
                        errorMessage = bestError
                        isAuthError = detectAuthError(bestError)
                        if messages.indices.contains(assistantIndex) {
                            messages[assistantIndex].isStreaming = false
                        }
                        isStreaming = false
                        return
                    }

                    // If CLI intercepted the message as a slash command (e.g. unknown skill),
                    // it may return text only in result.result without an assistant event.
                    // Also used by GitHub Models resultSuccess (accumulated full text).
                    // GitHub/Copilot: textDeltas are suppressed → always set final content here.
                    // Claude CLI: only set if content is empty (textDeltas may have populated it).
                    if let resultText = event.result, !resultText.isEmpty,
                       messages.indices.contains(assistantIndex) {
                        if source == .copilot {
                            // Finale Antwort immer setzen; <thinking>-Blöcke (o3/o4-mini) herausfiltern
                            messages[assistantIndex].content = Self.stripThinkingTags(resultText)
                        } else if messages[assistantIndex].content.isEmpty {
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
                        cliImagePaths: cliImagePaths,
                        isFallbackAttempt: true
                    )
                    return
                }
            }

            errorMessage = displayError
            isAuthError = detectAuthError(displayError)
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
        state.tmetricActivity()

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

    /// Entfernt <thinking>…</thinking> Blöcke aus dem Antwort-Text (o3/o4-mini Extended Thinking).
    static func stripThinkingTags(_ text: String) -> String {
        var result = text
        while let start = result.range(of: "<thinking>"),
              let end   = result.range(of: "</thinking>", range: start.upperBound..<result.endIndex) {
            let removal = start.lowerBound..<end.upperBound
            result.removeSubrange(removal)
        }
        // Auch führende/abschließende Leerzeilen bereinigen
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchGitDiff(in directory: String) async -> String? {
        // DispatchQueue.global statt Task.detached — waitUntilExit() darf keinen
        // Swift-Concurrency-Thread blockieren (erschöpft den Cooperative Thread Pool).
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                // ── 1. git diff HEAD — modified tracked files ──────────────────
                let diffProcess = Process()
                diffProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                diffProcess.arguments = ["diff", "HEAD"]
                diffProcess.currentDirectoryURL = URL(fileURLWithPath: directory)
                let diffPipe = Pipe()
                diffProcess.standardOutput = diffPipe
                diffProcess.standardError  = Pipe()
                var combined = ""
                do {
                    try diffProcess.run()
                    diffProcess.waitUntilExit()
                    let data = diffPipe.fileHandleForReading.readDataToEndOfFile()
                    combined = String(data: data, encoding: .utf8) ?? ""
                } catch {}

                // ── 2. git ls-files --others — new (untracked) files ───────────
                let lsProcess = Process()
                lsProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                lsProcess.arguments = ["ls-files", "--others", "--exclude-standard"]
                lsProcess.currentDirectoryURL = URL(fileURLWithPath: directory)
                let lsPipe = Pipe()
                lsProcess.standardOutput = lsPipe
                lsProcess.standardError  = Pipe()
                do {
                    try lsProcess.run()
                    lsProcess.waitUntilExit()
                    let data = lsPipe.fileHandleForReading.readDataToEndOfFile()
                    let newFiles = (String(data: data, encoding: .utf8) ?? "")
                        .components(separatedBy: "\n").filter { !$0.isEmpty }
                    let cutoff = Date().addingTimeInterval(-600)
                    let fm = FileManager.default
                    for file in newFiles {
                        let fullPath = (directory as NSString).appendingPathComponent(file)
                        if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                           let modified = attrs[.modificationDate] as? Date,
                           modified > cutoff {
                            combined += "\ndiff --git a/\(file) b/\(file)\nnew file mode 100644\n"
                        }
                    }
                } catch {}

                continuation.resume(returning: combined.isEmpty ? nil : combined)
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.mint)
                Text("Codeänderungen")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Spacer()

                Text("+\(added)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.statusGreen)
                Text("-\(removed)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.statusRed)

                // Copy diff
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(diff, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Diff kopieren")

                // Close panel — bleibt zu bis User manuell wieder öffnet
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        diffPanelDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
                Text("\(files.count) Datei\(files.count == 1 ? "" : "en")")
                    .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
                Text(file.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                Spacer()
                Text("+\(file.additions) -\(file.deletions)")
                    .font(.system(size: 11, design: .monospaced))
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

        let bg: Color = isAdd    ? theme.statusGreen.opacity(0.12)
                      : isRemove ? theme.statusRed.opacity(0.12)
                      : isHunk   ? Color(white: theme.isLight ? 0.82 : 0.15)
                      : .clear
        let fg: Color = isAdd    ? theme.statusGreen
                      : isRemove ? theme.statusRed
                      : isHunk   ? .blue.opacity(0.7)
                      : isMeta   ? theme.tertiaryText
                      : theme.primaryText

        return Text(line.isEmpty ? " " : line)
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(fg)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 1)
            .background(bg)
    }
}

// MARK: - Unified Right Panel (Plan + Diff)

extension SingleChatSessionView {

    // MARK: Unified wrapper

    @ViewBuilder
    func unifiedRightPanel() -> some View {
        let hasBoth = activePlan != nil && activeDiff != nil

        VStack(spacing: 0) {
            // Tab-Leiste nur wenn Plan UND Diff gleichzeitig existieren
            if hasBoth {
                HStack(spacing: 0) {
                    rightPanelTab(label: "Plan", icon: "list.clipboard",
                                  selected: rightPanelShowsPlan) { rightPanelShowsPlan = true }
                    rightPanelTab(label: "Diff", icon: "arrow.left.arrow.right",
                                  selected: !rightPanelShowsPlan) { rightPanelShowsPlan = false }
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3)) { diffPanelDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .help("Panel schließen")
                }
                .frame(height: 36)
                .background(theme.windowBg)
                Rectangle().fill(theme.cardBorder).frame(height: 0.5)
            }

            // Inhalt
            if rightPanelShowsPlan, let plan = activePlan {
                planSidePanel(plan)
            } else if let diff = activeDiff {
                diffSidePanel(diff)
            } else if let plan = activePlan {
                planSidePanel(plan)
            }
        }
    }

    @ViewBuilder
    private func rightPanelTab(label: String, icon: String,
                                selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(label).font(.system(size: 12, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? accentColor : theme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 0)
            .frame(height: 36)
            .overlay(alignment: .bottom) {
                if selected { Rectangle().fill(accentColor).frame(height: 2) }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Master Plan Panel

    // Datenstrukturen
    private enum MasterTodoStatus: Equatable {
        case pending, active, done, skipped, blocked
    }
    private struct MasterTodoItem: Identifiable {
        let id: String
        let number: String
        let title: String
        let assignedAgent: String?
        let level: Int              // 0 = Top-Level Kategorie, 1 = ausführbarer Schritt
        var status: MasterTodoStatus
    }

    func planSidePanel(_ plan: String) -> some View {
        let hasTodos   = !masterTodos.isEmpty
        let hasContent = !plan.isEmpty           // Plan streamt gerade
        let doneCount  = masterTodos.filter { $0.status == .done  }.count
        let totalCount = masterTodos.filter { $0.level == 1       }.count
        let isComplete = totalCount > 0 && doneCount == totalCount

        return VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.orange)
                Text("Master Plan")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                if !hasTodos {
                    ProgressView().scaleEffect(0.55)
                } else if totalCount > 0 {
                    Text("\(doneCount)/\(totalCount)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(isComplete ? .green : theme.tertiaryText)
                        .animation(.easeInOut, value: doneCount)
                }

                Spacer()
                if activeDiff == nil {
                    Button {
                        withAnimation(.spring(response: 0.3)) { diffPanelDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Panel schließen")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(theme.windowBg)

            Rectangle().fill(theme.cardBorder).frame(height: 0.5)

            // ── Sticky Ziel-Header ───────────────────────────────────────
            if !masterGoal.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("🎯")
                        .font(.system(size: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ZIEL")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.orange.opacity(0.65))
                        Text(masterGoal)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.orange.opacity(0.07))

                Rectangle().fill(theme.cardBorder).frame(height: 0.5)
            }

            // ── Todo-Liste ───────────────────────────────────────────────
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    if hasTodos {
                        ForEach(masterTodos) { item in
                            masterTodoRow(item)
                        }
                    } else if hasContent {
                        // Phase 1: Plan streamt gerade
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text("Master Plan wird erstellt…")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.secondaryText)
                        }
                        .padding(12)
                    } else {
                        // Phase 0: Domain-Analyse läuft
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text("Analysiere Domain-Beiträge…")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.secondaryText)
                        }
                        .padding(12)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(white: theme.isLight ? 0.96 : 0.06))
    }

    // MARK: - Master Todo Row

    @ViewBuilder
    private func masterTodoRow(_ item: MasterTodoItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if item.level > 0 {
                Spacer().frame(width: 14)
            }

            // Status-Icon
            Group {
                switch item.status {
                case .pending:
                    Image(systemName: item.level == 0 ? "folder" : "square")
                        .foregroundStyle(item.level == 0
                            ? Color.orange.opacity(0.55) : theme.tertiaryText)
                case .active:
                    ProgressView().scaleEffect(0.48)
                case .done:
                    Image(systemName: "checkmark.square.fill")
                        .foregroundStyle(.green)
                case .skipped:
                    Image(systemName: "minus.square")
                        .foregroundStyle(theme.tertiaryText)
                case .blocked:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .font(.system(size: 12))
            .frame(width: 14, height: 14)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.number)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.tertiaryText)
                    Text(item.title)
                        .font(item.level == 0
                              ? .system(size: 12, weight: .semibold)
                              : .system(size: 12))
                        .foregroundStyle(item.status == .done
                            ? theme.tertiaryText : theme.primaryText)
                        .strikethrough(item.status == .done, color: theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let agent = item.assignedAgent, item.level > 0 {
                    Text("→ \(agent)")
                        .font(.system(size: 10))
                        .foregroundStyle(accentColor.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, item.level == 0 ? 5 : 3)
        .background(
            item.status == .active ? accentColor.opacity(0.06) :
            (item.level == 0 ? theme.cardBorder.opacity(0.25) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.2), value: item.status)
    }

    // MARK: - Legacy Plan Parser (Fallback für AGENT:/AUFGABE: Format)

    private struct PlanPanelEntry { let agent: String; let task: String }

    private func parsePlanForPanel(_ plan: String) -> [PlanPanelEntry] {
        var entries: [PlanPanelEntry] = []
        let lines = plan.components(separatedBy: .newlines)
        var currentAgent: String?
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.uppercased().hasPrefix("AGENT:") {
                currentAgent = String(t.dropFirst(6))
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "**", with: "")
            } else if t.uppercased().hasPrefix("AUFGABE:"), let agent = currentAgent {
                entries.append(PlanPanelEntry(
                    agent: agent,
                    task: String(t.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                ))
                currentAgent = nil
            }
        }
        return entries
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
    var drawsLine: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(width: $width, minWidth: minWidth, maxWidth: maxWidth, growsRight: growsRight)
    }

    func makeNSView(context: Context) -> ResizeDragNSView {
        let v = ResizeDragNSView(coordinator: context.coordinator)
        v.drawsLine = drawsLine
        return v
    }

    func updateNSView(_ nsView: ResizeDragNSView, context: Context) {
        context.coordinator.width    = $width
        context.coordinator.minWidth = minWidth
        context.coordinator.maxWidth = maxWidth
        context.coordinator.growsRight = growsRight
        nsView.drawsLine = drawsLine
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
    var drawsLine = true

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
        guard drawsLine else { return }
        NSColor.separatorColor.withAlphaComponent(0.25).setFill()
        NSRect(x: (bounds.width - 1) / 2, y: 0, width: 1, height: bounds.height).fill()
    }
}

// MARK: - Chat File Panel

struct ChatFilePanel: View {
    let rootPath: String
    var changedPaths: Set<String> = []
    var newPaths: Set<String> = []
    let onInsertPath: (String) -> Void
    let onSelectNode: (ExplorerNode?) -> Void
    let onClose: () -> Void

    @Environment(\.appTheme) var theme
    @State private var rootNode: ExplorerNode?
    @State private var selectedNode: ExplorerNode?
    @State private var showHidden = false
    @AppStorage("fileExplorerSortOrder") private var sortOrder: FileSortOrder = .nameAsc
    @AppStorage("fileExplorerGroupBy")   private var groupBy: FileGroupBy = .foldersFirst
    @State private var currentRoot: String = ""
    @State private var searchText: String = ""
    @State private var dirWatcher: DispatchSourceFileSystemObject? = nil
    @State private var dirReloadTrigger: Int = 0
    @State private var directoryMissing: Bool = false

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private func isValidDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private var filteredChildren: [ExplorerNode] {
        guard !searchText.isEmpty, let root = rootNode else {
            return applySortGroup(rootNode?.children ?? [], sortOrder: sortOrder, groupBy: groupBy)
        }
        let results = flatSearch(in: root.children ?? [], query: searchText.lowercased())
        return applySortGroup(results, sortOrder: sortOrder, groupBy: groupBy)
    }

    private func flatSearch(in nodes: [ExplorerNode], query: String) -> [ExplorerNode] {
        var result: [ExplorerNode] = []
        for node in nodes {
            if node.name.lowercased().contains(query) {
                result.append(node)
            }
            if node.isDirectory, let children = node.children {
                result.append(contentsOf: flatSearch(in: children, query: query))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(accentColor)
                Text(URL(fileURLWithPath: rootPath).lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Spacer()
                Menu {
                    Picker("Sortieren", selection: $sortOrder) {
                        ForEach(FileSortOrder.allCases, id: \.rawValue) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Picker("Gruppieren", selection: $groupBy) {
                        ForEach(FileGroupBy.allCases, id: \.rawValue) { group in
                            Text(group.label).tag(group)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    let isCustom = sortOrder != .nameAsc || groupBy != .foldersFirst
                    Image(systemName: isCustom ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                        .font(.system(size: 12))
                        .foregroundStyle(isCustom ? accentColor : theme.tertiaryText)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Sortieren & Gruppieren")

                Button {
                    showHidden.toggle()
                    reload()
                } label: {
                    Image(systemName: showHidden ? "eye.fill" : "eye.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(showHidden ? accentColor : theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Versteckte Dateien")

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: rootPath))
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Im Finder öffnen")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Schließen")
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(theme.windowBg)

            // Search bar
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
                TextField("Dateiname suchen…", text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .foregroundStyle(theme.primaryText)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder, lineWidth: 0.5))
            .padding(.horizontal, 8)

            Rectangle().fill(theme.cardBorder).frame(height: 0.5)

            // Tree / search results
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if directoryMissing {
                        VStack(spacing: 8) {
                            Image(systemName: "folder.badge.questionmark")
                                .font(.system(size: 28))
                                .foregroundStyle(theme.tertiaryText)
                            Text("Ordner nicht gefunden")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.secondaryText)
                            Text(rootPath)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                        .padding(.horizontal, 12)
                    } else if rootNode == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                    } else {
                        let nodes = filteredChildren
                        if nodes.isEmpty && !searchText.isEmpty {
                            Text("Keine Treffer")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.tertiaryText)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 20)
                        } else if nodes.isEmpty {
                            Text("Ordner ist leer")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.tertiaryText)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 20)
                        } else {
                            ForEach(nodes) { node in
                                ChatFilePanelRow(
                                    node: node,
                                    selectedId: selectedNode?.id,
                                    showHidden: showHidden || !searchText.isEmpty,
                                    depth: 0,
                                    changedPaths: changedPaths,
                                    newPaths: newPaths,
                                    onSelect: selectNode,
                                    onInsert: { onInsertPath($0.url.path) }
                                )
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.fileSortOrder, sortOrder)
            .environment(\.fileGroupBy, groupBy)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.windowBg)
        .onAppear {
            // Always force-load on appear — resets guard so timing issues with animations don't skip the initial tree render
            currentRoot = ""
            load()
            startDirWatcher()
        }
        .onDisappear { stopDirWatcher() }
        .onChange(of: rootPath) { stopDirWatcher(); reload(); startDirWatcher() }
        .onChange(of: dirReloadTrigger) { reload() }
    }

    private func load() {
        guard currentRoot != rootPath else { return }
        currentRoot = rootPath
        guard isValidDirectory(rootPath) else {
            directoryMissing = true
            rootNode = nil
            selectedNode = nil
            onSelectNode(nil)
            return
        }
        directoryMissing = false
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

    private func startDirWatcher() {
        stopDirWatcher()
        let fd = open(rootPath, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        // Only increment trigger flag — .onChange(of: dirReloadTrigger) drives the actual reload.
        source.setEventHandler { [self] in
            dirReloadTrigger += 1
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        dirWatcher = source
    }

    private func stopDirWatcher() {
        dirWatcher?.cancel()
        dirWatcher = nil
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

// MARK: - QuickLook preview (Office, Keynote, etc.)

struct QLFilePreviewView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.previewItem = url as QLPreviewItem
        view.autostarts = true
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url {
            view.previewItem = url as QLPreviewItem
        }
    }
}

// MARK: - Syntax Highlighter

struct SyntaxHighlighter {
    // One Dark Pro palette
    static func highlight(_ text: String, fileExtension ext: String, isDark: Bool) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = isDark ? Color(white: 0.86) : Color(white: 0.12)
        result.font = .system(size: 13, design: .monospaced)

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
    @State private var fullText: String? = nil
    @State private var highlightedText: AttributedString? = nil
    @State private var pdfDocument: PDFDocument? = nil
    @State private var nsImage: NSImage? = nil
    @State private var isLoading = false
    @State private var searchText: String = ""
    @State private var searchMatchCount: Int = 0
    @State private var currentMatchIndex: Int = 0
    @State private var fileWatcher: DispatchSourceFileSystemObject? = nil
    @State private var reloadTrigger: Int = 0
    @State private var watcherNeedsRestart: Bool = false
    @State private var qlPreviewURL: URL? = nil

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
                    .font(.system(size: 12))
                    .foregroundStyle(node.iconColor(theme: theme))
                Text(node.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
                Spacer(minLength: 4)
                if node.isTextFile {
                    Button {
                        let content = fullText ?? previewText ?? ""
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(content, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Datei-Inhalt kopieren")
                    .fixedSize()
                    InlineSearchBar(
                        query: $searchText,
                        currentMatch: $currentMatchIndex,
                        matchCount: searchMatchCount,
                        width: 110,
                        placeholder: "Suchen"
                    )
                    .fixedSize()
                }
                Button { onInsertPath(node.url.path) } label: {
                    Label("Einfügen", systemImage: "text.badge.plus")
                        .font(.system(size: 12))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
                .help("Pfad in Chat einfügen")
                .fixedSize()
                Button { NSWorkspace.shared.open(node.url) } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Im Finder öffnen")
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
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
            } else if let url = qlPreviewURL {
                QLFilePreviewView(url: url)
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
                HighlightedCodeView(
                    code: text,
                    fileURL: node.url,
                    isDark: !theme.isLight,
                    searchText: searchText,
                    currentMatchIndex: currentMatchIndex,
                    onMatchCountChange: { count in
                        if searchMatchCount != count { searchMatchCount = count }
                        if count > 0, currentMatchIndex >= count { currentMatchIndex = 0 }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: node.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(node.iconColor(theme: theme).opacity(0.4))
                    Text("Keine Vorschau verfügbar")
                        .font(.system(size: 14))
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
        .onAppear { loadContent(); startFileWatcher() }
        .onDisappear { stopFileWatcher() }
        .onChange(of: node.id) { stopFileWatcher(); loadContent(); startFileWatcher() }
        .onChange(of: reloadTrigger) {
            if watcherNeedsRestart {
                watcherNeedsRestart = false
                stopFileWatcher()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    loadContent()
                    startFileWatcher()
                }
            } else {
                loadContent()
            }
        }
    }

    private func startFileWatcher() {
        guard node.isTextFile || node.isPDF || isImageFile || node.isOfficeFile else { return }
        stopFileWatcher()
        let fd = open(node.url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        // Only set simple flags — never call SwiftUI methods from a GCD closure
        // (value-type [self] capture doesn't reliably write through @State storage).
        // .onChange(of: reloadTrigger) in the view body handles the actual reload.
        source.setEventHandler { [self] in
            let events = source.data
            if events.contains(.rename) || events.contains(.delete) {
                watcherNeedsRestart = true
            }
            reloadTrigger += 1
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcher = source
    }

    private func stopFileWatcher() {
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    private func loadContent() {
        previewText = nil
        fullText = nil
        highlightedText = nil
        pdfDocument = nil
        nsImage = nil
        qlPreviewURL = nil
        isLoading = false
        searchText = ""
        searchMatchCount = 0
        currentMatchIndex = 0
        if node.isOfficeFile {
            qlPreviewURL = node.url
        } else if node.isPDF {
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
                    fullText = text
                    previewText = preview
                    highlightedText = highlighted
                    isLoading = false
                }
            }
        }
    }

    private func updateMatchCount(in text: String) {
        guard !searchText.isEmpty else { searchMatchCount = 0; return }
        let lower = text.lowercased()
        let query = searchText.lowercased()
        var count = 0
        var idx = lower.startIndex
        while let range = lower.range(of: query, range: idx..<lower.endIndex) {
            count += 1
            idx = range.upperBound
        }
        searchMatchCount = count
    }

    private func buildSearchHighlightedText(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        result.font = .system(size: 13).monospaced()
        result.foregroundColor = theme.primaryText

        guard !searchText.isEmpty else { return result }
        let query = searchText.lowercased()
        let lower = text.lowercased()
        var idx = lower.startIndex
        while let range = lower.range(of: query, range: idx..<lower.endIndex) {
            if let lo = AttributedString.Index(range.lowerBound, within: result),
               let hi = AttributedString.Index(range.upperBound, within: result) {
                result[lo..<hi].backgroundColor = .yellow.opacity(0.45)
                result[lo..<hi].foregroundColor = .black
            }
            idx = range.upperBound
        }
        return result
    }
}

// MARK: - Chat File Panel Row

struct ChatFilePanelRow: View {
    @ObservedObject var node: ExplorerNode
    let selectedId: UUID?
    let showHidden: Bool
    let depth: Int
    var changedPaths: Set<String> = []
    var newPaths: Set<String> = []
    let onSelect: (ExplorerNode) -> Void
    let onInsert: (ExplorerNode) -> Void

    @Environment(\.appTheme) var theme
    @Environment(\.fileSortOrder) private var sortOrder
    @Environment(\.fileGroupBy)   private var groupBy
    @State private var isHovered = false
    @State private var subDirWatcher: DispatchSourceFileSystemObject? = nil
    @State private var subDirTrigger: Int = 0

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }
    private var isSelected: Bool { selectedId == node.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if node.isExpanded, let children = node.children {
                ForEach(applySortGroup(children, sortOrder: sortOrder, groupBy: groupBy)) { child in
                    ChatFilePanelRow(
                        node: child,
                        selectedId: selectedId,
                        showHidden: showHidden,
                        depth: depth + 1,
                        changedPaths: changedPaths,
                        newPaths: newPaths,
                        onSelect: onSelect,
                        onInsert: onInsert
                    )
                }
            }
        }
        .onDisappear { stopSubDirWatcher() }
        .onChange(of: node.isExpanded) {
            if node.isExpanded { startSubDirWatcher() } else { stopSubDirWatcher() }
        }
        .onChange(of: subDirTrigger) {
            guard node.isDirectory && node.isExpanded else { return }
            node.loadChildren(showHidden: showHidden)
        }
    }

    private var isChanged: Bool { !node.isDirectory && changedPaths.contains(node.url.path) }
    private var isNew: Bool { !node.isDirectory && newPaths.contains(node.url.path) }

    private func startSubDirWatcher() {
        guard node.isDirectory else { return }
        stopSubDirWatcher()
        let fd = open(node.url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [self] in subDirTrigger += 1 }
        source.setCancelHandler { close(fd) }
        source.resume()
        subDirWatcher = source
    }

    private func stopSubDirWatcher() {
        subDirWatcher?.cancel()
        subDirWatcher = nil
    }

    private var row: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: CGFloat(depth) * 14)
            if node.isDirectory {
                Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .medium))
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
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? accentColor : node.iconColor(theme: theme))
                // Badge: green "+" for new file, orange dot for modified
                if isNew {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.18, green: 0.72, blue: 0.42))
                            .frame(width: 11, height: 11)
                        Text("+")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 9, y: -9)
                } else if isChanged {
                    Circle()
                        .fill(theme.statusOrange)
                        .frame(width: 7, height: 7)
                        .offset(x: 9, y: -9)
                }
            }
            Text(node.name)
                .font(.system(size: 14, weight: (isChanged || isNew) ? .semibold : .medium))
                .foregroundStyle(isNew ? Color(red: 0.18, green: 0.72, blue: 0.42) : (isChanged ? theme.statusOrange.opacity(0.9) : (isSelected ? theme.primaryText : theme.secondaryText)))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if isHovered && !node.isDirectory {
                Button { onInsert(node) } label: {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 12))
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
                if node.isExpanded && (node.children == nil || node.loadFailed) {
                    node.loadChildren(showHidden: showHidden)
                }
            }
        }
        .contextMenu {
            // ── Datei-Aktionen ─────────────────────────────────────
            if !node.isDirectory {
                Button {
                    if let text = try? String(contentsOf: node.url, encoding: .utf8) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                } label: {
                    Label("Inhalt kopieren", systemImage: "doc.on.clipboard")
                }
                Button { onInsert(node) } label: {
                    Label("In Chat einfügen", systemImage: "text.badge.plus")
                }
                Divider()
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path, forType: .string)
            } label: {
                Label("Pfad kopieren", systemImage: "link")
            }
            Button {
                NSWorkspace.shared.selectFile(node.url.path,
                    inFileViewerRootedAtPath: node.url.deletingLastPathComponent().path)
            } label: {
                Label("Im Finder zeigen", systemImage: "folder")
            }
            Button {
                NSWorkspace.shared.open(node.url)
            } label: {
                Label("Mit Standard-App öffnen", systemImage: "arrow.up.right.square")
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Message Row (VS Code Copilot style: flat, left-aligned, dividers)

struct MessageBubbleView: View, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        // Streaming messages always re-render (content changes on every token batch)
        if lhs.message.isStreaming || rhs.message.isStreaming { return false }
        // Completed messages: skip re-render if nothing meaningful changed.
        // Closures (onDiffTap, onAskForResult) are intentionally ignored — they
        // are stable captures that never change for a finished message.
        return lhs.message == rhs.message
    }
    let message: ChatMessage
    var onDiffTap: ((String) -> Void)?
    var onAskForResult: (() -> Void)?
    var onContinue: (() -> Void)?
    @Environment(\.appTheme) var theme
    @State private var toolsExpanded: Bool = false
    @State private var dot0Up: Bool = false
    @State private var dot1Up: Bool = false
    @State private var dot2Up: Bool = false
    @State private var taskStartTime: Date? = nil
    @State private var completedDuration: TimeInterval? = nil

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
        return theme.statusOrange
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
            if !message.content.isEmpty {
                MarkdownTextView(text: message.content)
                    .equatable()
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
                HStack(spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: resolvedSource.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(resolvedSource.label)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(sourceColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(sourceColor.opacity(0.10), in: Capsule())

                    if let agent = message.agentName, !agent.isEmpty {
                        // Agent-Lauf: Name mit Personen-Icon, Modell dezent dahinter
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(agent)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.10), in: Capsule())
                        Text(modelLabel)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(theme.tertiaryText)
                    } else {
                        Text(modelLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                Spacer()
                if message.isStreaming {
                    ProgressView().scaleEffect(0.5)
                }
            }

            // Todo-Panel (TodoWrite-basiert) — Vorrang vor LivePlanView
            if let todos = message.currentTodos {
                TodoPanel(todos: todos, isStreaming: message.isStreaming,
                          startTime: taskStartTime ?? Date())
            } else if !message.toolCalls.isEmpty {
                if message.isStreaming {
                    LivePlanView(
                        toolCalls: message.toolCalls,
                        startTime: taskStartTime ?? Date(),
                        isStreaming: true
                    )
                } else {
                    toolsSummaryView(message.toolCalls, duration: completedDuration)
                }
            }

            // Während aktiver Recherche Zwischentext leicht gedimmt zeigen —
            // so sieht der User was der Agent gerade schreibt, auch zwischen Tool-Batches
            let allToolsDone = !message.toolCalls.isEmpty
                && message.toolCalls.allSatisfy { $0.result != nil }
            let isResearching = message.isStreaming && !message.toolCalls.isEmpty && !allToolsDone
            if !message.content.isEmpty && !isResearching {
                MarkdownTextView(text: message.content)
                    .equatable()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(allToolsDone && message.isStreaming ? 0.65 : 1.0)
            }

            if message.isStreaming && message.content.isEmpty && message.toolCalls.isEmpty {
                streamingDots
            }

            if !message.isStreaming && message.role == .assistant {
                tokenFooter
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .onAppear {
            if message.isStreaming && !message.toolCalls.isEmpty && taskStartTime == nil {
                taskStartTime = Date()
            }
        }
        .onChange(of: message.toolCalls.count) {
            if message.isStreaming && taskStartTime == nil {
                taskStartTime = Date()
            }
        }
        .onChange(of: message.isStreaming) {
            if !message.isStreaming, let start = taskStartTime, !message.toolCalls.isEmpty {
                completedDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func toolCallView(_ tool: ToolCall) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header row: icon + tool name + command summary
            HStack(spacing: 5) {
                Image(systemName: tool.name == "Bash" ? "terminal.fill" : "wrench.and.screwdriver.fill")
                    .font(.system(size: 11)).foregroundStyle(theme.statusOrange)
                Text(tool.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.statusOrange.opacity(0.85))
                if !tool.input.isEmpty {
                    Text(tool.input)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
                if tool.result != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(theme.statusGreen.opacity(0.7))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(theme.statusOrange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            // Output block (shown when expanded)
            if toolsExpanded, let result = tool.result, !result.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(result)
                        .font(.system(size: 12, design: .monospaced))
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

    private func toolsSummaryView(_ tools: [ToolCall], duration: TimeInterval? = nil) -> some View {
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

        return VStack(alignment: .leading, spacing: 6) {
            // Tap to expand/collapse
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { toolsExpanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11)).foregroundStyle(theme.statusGreen.opacity(0.7))
                        Text("\(tools.count) Schritte abgeschlossen")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.statusGreen.opacity(0.75))
                        Text("· \(label)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.secondaryText.opacity(0.45))
                            .lineLimit(1)
                        if let dur = duration {
                            Text("· \(String(format: "%.1f", dur))s")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.tertiaryText.opacity(0.5))
                        }
                        Spacer()
                        Image(systemName: toolsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.tertiaryText.opacity(0.5))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(theme.statusGreen.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                if message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let ask = onAskForResult {
                    Button {
                        ask()
                    } label: {
                        Label("Ergebnis", systemImage: "arrow.right.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(theme.statusGreen.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("Claude nach dem Ergebnis fragen")
                    .fixedSize()
                }
            }

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
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                BouncingDot(color: accentColor, delay: Double(i) * 0.15)
            }
        }
        .padding(.vertical, 6)
    }

    private var tokenFooter: some View {
        HStack(spacing: 8) {
            // Abschluss-Status
            if message.finishedCleanly {
                // ✓ Sauberes Ende
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.green.opacity(0.65))
                Text("Fertig")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.green.opacity(0.6))
            } else if message.resultSubtype == "max_turns" {
                // Agent hat Turn-Limit erreicht — kein Fehler, Hinweis + Weiter-Button
                Image(systemName: "arrow.trianglehead.2.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.blue.opacity(0.55))
                Text("Max. Turns")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.blue.opacity(0.5))
                if let cont = onContinue {
                    Button {
                        cont()
                    } label: {
                        Text("Weiter →")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("Aufgabe in derselben Session fortsetzen")
                }
            } else if message.resultSubtype == "error" {
                // Echter Fehler
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red.opacity(0.6))
                Text("Fehler")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red.opacity(0.55))
            }
            // "interrupted" (User-Stopp) und unbekannte Enden → kein Label

            if message.inputTokens > 0 {
                if message.finishedCleanly || message.resultSubtype != nil {
                    Text("·").foregroundStyle(theme.tertiaryText)
                }
                Label("\(message.inputTokens) in", systemImage: "arrow.down")
                    .font(.system(size: 11)).foregroundStyle(theme.tertiaryText)
                Label("\(message.outputTokens) out", systemImage: "arrow.up")
                    .font(.system(size: 11)).foregroundStyle(theme.tertiaryText)
            }
            if let cost = message.costUsd, cost > 0 {
                Text("·").foregroundStyle(theme.tertiaryText)
                Text(String(format: "$%.4f", cost))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.tertiaryText)
            }
        }
        .padding(.top, 4)
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
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.mint)
                Text("\(files.count) Datei\(files.count == 1 ? "" : "en") geändert")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text("+\(added)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.statusGreen)
                Text("-\(removed)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.statusRed)
                Spacer()
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12))
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

private struct BouncingDot: View {
    let color: Color
    let delay: Double
    // KRITISCH: kein withAnimation(.repeatForever) hier — treibt 60fps flushTransactions
    // auf der aktiven ChatView-Section (FrozenSectionLayout.isActive=true) → Layout-Loop.
    // TimelineView(.periodic) feuert nur 10fps und triggert KEINE AnimatableAttribute-Knoten.
    private let startDate = Date()

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1.0 / 10.0)) { ctx in
            let raw = ctx.date.timeIntervalSince(startDate) + delay
            let period = 0.76            // 2 × 0.38 s
            let t = raw.truncatingRemainder(dividingBy: period) / (period / 2)
            let tri = t <= 1.0 ? t : 2.0 - t          // Dreieckswelle 0→1→0
            let eased = tri * tri * (3.0 - 2.0 * tri)  // smoothstep
            Circle()
                .fill(color.opacity(0.75))
                .frame(width: 7, height: 7)
                .offset(y: CGFloat(-5.0 * eased))
        }
    }
}

// MARK: - Diff Parsing Helpers (shared)

struct DiffFile {
    let name: String
    let lines: [String]
    var additions: Int { lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count }
    var deletions: Int { lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count }
    var isNew: Bool { lines.contains { $0.hasPrefix("new file mode") } }
    var isDeleted: Bool { lines.contains { $0.hasPrefix("deleted file mode") } }
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
    @Environment(\.appTheme) var theme
    // KRITISCH: withAnimation(.repeatForever) für rotation/pulse → 60fps flushTransactions.
    // Ersetzt durch TimelineView(.periodic): render-only, 10fps, kein AnimatableAttribute-Loop.
    private let startDate = Date()

    private var searchColor: Color { theme.statusOrange }
    private var bgOpacity: Double { (theme.isLight || theme.isMedium) ? 0.13 : 0.08 }

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.periodic(from: startDate, by: 0.1)) { ctx in
                let elapsed = ctx.date.timeIntervalSince(startDate)
                let rotation = (elapsed * (360.0 / 1.2)).truncatingRemainder(dividingBy: 360.0)
                let pulsePhase = elapsed.truncatingRemainder(dividingBy: 0.9) / 0.9
                let pulse = CGFloat(1.0 + 0.25 * abs(sin(.pi * pulsePhase)))
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(searchColor.opacity(i == 0 ? 0.85 : i == 1 ? 0.5 : 0.25))
                            .frame(width: i == 0 ? 4 : 3, height: i == 0 ? 4 : 3)
                            .offset(y: -9)
                            .rotationEffect(.degrees(rotation + Double(i) * 120))
                    }
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(searchColor)
                        .scaleEffect(pulse)
                }
                .frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Searching…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(searchColor)
                if !recentTool.isEmpty {
                    Text(recentTool)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(searchColor.opacity(0.65))
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(searchColor.opacity(bgOpacity), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Live Plan Panel (zeigt Tool-Calls während Streaming als nummerierte Schritte)

private struct LivePlanView: View {
    let toolCalls: [ToolCall]
    let startTime: Date
    var isStreaming: Bool = false
    @Environment(\.appTheme) var theme

    private var accentColor: Color { Color(red: 0.72, green: 0.35, blue: 0.0) }
    private var completedCount: Int { toolCalls.filter { $0.result != nil }.count }
    private var progress: Double {
        toolCalls.isEmpty ? 0 : Double(completedCount) / Double(toolCalls.count)
    }
    // Alle Tools haben Ergebnis, Agent schreibt aber noch (zwischen Tool-Batches)
    private var isThinking: Bool {
        isStreaming && !toolCalls.isEmpty && toolCalls.allSatisfy { $0.result != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: Fortschrittsbalken + Status
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accentColor.opacity(0.15))
                            .frame(height: 4)
                        if isThinking {
                            // Pulsierender Balken: Agent schreibt noch.
                            // KRITISCH: kein .animation(.repeatForever) — treibt 60fps Layout.
                            // TimelineView(.periodic) = 10fps, render-only.
                            TimelineView(.periodic(from: startTime, by: 0.08)) { ctx in
                                let elapsed = ctx.date.timeIntervalSince(startTime)
                                let opacity = 0.2 + 0.35 * abs(sin(.pi * elapsed / 0.75))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(accentColor.opacity(opacity))
                                    .frame(width: geo.size.width, height: 4)
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accentColor.opacity(0.75))
                                .frame(width: geo.size.width * progress, height: 4)
                                .animation(.easeInOut(duration: 0.3), value: progress)
                        }
                    }
                }
                .frame(height: 4)

                if isThinking {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.42).frame(width: 12, height: 12)
                        Text("Schreibt…")
                            .font(.system(size: 11))
                            .foregroundStyle(accentColor.opacity(0.7))
                    }
                }

                TimelineView(.periodic(from: startTime, by: 0.5)) { tl in
                    let elapsed = tl.date.timeIntervalSince(startTime)
                    Text(String(format: "%.0fs", max(0, elapsed)))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(accentColor.opacity(0.6))
                        .frame(width: 30, alignment: .trailing)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            // Schritte-Liste
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(toolCalls.enumerated()), id: \.element.id) { idx, tool in
                    let isDone = tool.result != nil
                    let isCurrent = !isDone && (idx == completedCount)
                    HStack(spacing: 6) {
                        if isDone {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.statusGreen.opacity(0.7))
                        } else if isCurrent {
                            ProgressView().scaleEffect(0.4).frame(width: 10, height: 10)
                        } else {
                            Circle()
                                .fill(accentColor.opacity(0.25))
                                .frame(width: 6, height: 6)
                        }
                        Text(tool.name)
                            .font(.system(size: 11, weight: isCurrent ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(isDone ? theme.secondaryText.opacity(0.5)
                                : isCurrent ? accentColor
                                : theme.tertiaryText.opacity(0.5))
                        if !tool.input.isEmpty {
                            Text(tool.input)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.secondaryText.opacity(0.35))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .background(accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accentColor.opacity(0.15), lineWidth: 0.5))
    }
}

// MARK: - Todo Panel (zeigt TodoWrite-Todos live während und nach dem Streaming)

private struct TodoPanel: View {
    let todos: [TodoItem]
    let isStreaming: Bool
    let startTime: Date
    @State private var expanded: Bool = false
    @Environment(\.appTheme) var theme

    private var accentColor: Color { Color(red: 0.72, green: 0.35, blue: 0.0) }
    private var completedCount: Int { todos.filter(\.isCompleted).count }
    private var allDone: Bool { completedCount == todos.count && !todos.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    // Status icon
                    if isStreaming {
                        ProgressView().scaleEffect(0.45).frame(width: 14, height: 14)
                    } else if allDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.statusGreen.opacity(0.8))
                    } else {
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 12))
                            .foregroundStyle(accentColor.opacity(0.8))
                    }

                    // Counter label
                    Text(isStreaming
                         ? "\(completedCount)/\(todos.count) erledigt"
                         : allDone
                             ? "\(todos.count) Aufgaben abgeschlossen"
                             : "\(completedCount)/\(todos.count) erledigt")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isStreaming ? accentColor : allDone ? theme.statusGreen.opacity(0.7) : accentColor)

                    Spacer()

                    // Elapsed timer during streaming
                    if isStreaming {
                        TimelineView(.periodic(from: startTime, by: 0.5)) { tl in
                            let elapsed = tl.date.timeIntervalSince(startTime)
                            Text(String(format: "%.0fs", max(0, elapsed)))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(accentColor.opacity(0.5))
                        }
                    }

                    Image(systemName: (isStreaming || expanded) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.secondaryText.opacity(0.4))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            // Progress bar (during streaming)
            if isStreaming {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(accentColor.opacity(0.1)).frame(height: 2)
                        let w = todos.isEmpty ? 0.0 : geo.size.width * Double(completedCount) / Double(todos.count)
                        Rectangle()
                            .fill(accentColor.opacity(0.6))
                            .frame(width: w, height: 2)
                            .animation(.easeInOut(duration: 0.3), value: completedCount)
                    }
                }
                .frame(height: 2)
            }

            // Todo list (shown when streaming OR when expanded after done)
            if isStreaming || expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(todos) { todo in
                        HStack(alignment: .top, spacing: 7) {
                            // Status icon
                            Group {
                                if todo.isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(theme.statusGreen.opacity(0.7))
                                } else if todo.isActive {
                                    ProgressView()
                                        .scaleEffect(0.4)
                                        .frame(width: 11, height: 11)
                                } else {
                                    Circle()
                                        .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
                                        .frame(width: 9, height: 9)
                                        .padding(.top, 1)
                                }
                            }
                            .frame(width: 14, alignment: .center)

                            Text(todo.content)
                                .font(.system(size: 12))
                                .foregroundStyle(
                                    todo.isCompleted ? theme.secondaryText.opacity(0.45)
                                    : todo.isActive  ? accentColor
                                    : theme.primaryText.opacity(0.75)
                                )
                                .strikethrough(todo.isCompleted, color: theme.secondaryText.opacity(0.3))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .padding(.top, isStreaming ? 6 : 2)
            }
        }
        .background(accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
            isStreaming ? accentColor.opacity(0.2) : accentColor.opacity(0.12), lineWidth: 0.5))
    }
}

// MARK: - Agent Running Banner (sticky oberhalb InputBar, sichtbar unabhängig von Scroll-Position)

private struct AgentRunningBanner: View {
    let message: ChatMessage?   // aktuelle Streaming-Message (kann nil/leer sein)
    let startTime: Date
    let theme: AppTheme

    private var accentColor: Color { Color(red: 0.72, green: 0.35, blue: 0.0) }

    // Letztes noch laufendes Tool (kein Result)
    private var activeTool: ToolCall? {
        message?.toolCalls.last(where: { $0.result == nil })
    }
    // Letzte abgeschlossene Tools (max. 2) für Kontext
    private var recentDone: [ToolCall] {
        let done = message?.toolCalls.filter { $0.result != nil } ?? []
        return Array(done.suffix(2))
    }
    // Erste Zeile des aktuell geschriebenen Texts
    private var contentPreview: String? {
        guard let c = message?.content, !c.isEmpty else { return nil }
        let line = c.components(separatedBy: .newlines)
            .last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        guard !line.isEmpty else { return nil }
        return line.count > 90 ? String(line.prefix(90)) + "…" : line
    }
    private var hasToolData: Bool {
        !(message?.toolCalls.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Kopfzeile ──────────────────────────────────────────
            HStack(spacing: 7) {
                ProgressView().scaleEffect(0.5).frame(width: 13, height: 13)

                if let tool = activeTool {
                    // Aktiver Tool-Name als primärer Status
                    Group {
                        Text("⟳ ").foregroundStyle(accentColor.opacity(0.6))
                        + Text(tool.name)
                            .fontWeight(.semibold)
                            .foregroundStyle(accentColor)
                        + (tool.input.isEmpty ? Text("") :
                            Text(" · " + tool.input).foregroundStyle(accentColor.opacity(0.6)))
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                } else if hasToolData {
                    Text("Verarbeitet Ergebnisse…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accentColor.opacity(0.75))
                } else {
                    Text("Agent analysiert…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accentColor.opacity(0.75))
                }

                Spacer()

                // Elapsed timer
                TimelineView(.periodic(from: startTime, by: 1)) { tl in
                    let s = max(0, Int(tl.date.timeIntervalSince(startTime)))
                    let label = s < 60
                        ? "\(s)s"
                        : String(format: "%d:%02d", s / 60, s % 60)
                    Text(label)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(accentColor.opacity(0.5))
                }

                // KRITISCH: kein .animation(.repeatForever) → 60fps Layout-Loop.
                TimelineView(.periodic(from: startTime, by: 0.1)) { ctx in
                    let elapsed = ctx.date.timeIntervalSince(startTime)
                    let opacity = 0.2 + 0.55 * abs(sin(.pi * elapsed / 0.75))
                    Circle()
                        .fill(accentColor.opacity(opacity))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)

            // ── Detail-Zeile: letzte erledigte Steps + Content-Preview ──
            if hasToolData || contentPreview != nil {
                Divider().opacity(0.3)
                HStack(spacing: 10) {
                    // Abgeschlossene Steps (letzte 2)
                    if !recentDone.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(recentDone) { tool in
                                HStack(spacing: 3) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(theme.statusGreen.opacity(0.6))
                                    Text(tool.name)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(theme.secondaryText.opacity(0.5))
                                }
                            }
                        }
                    }
                    // Content-Preview (Text den Agent gerade schreibt)
                    if let preview = contentPreview {
                        Text(preview)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.secondaryText.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                    // Schritt-Zähler
                    if let count = message?.toolCalls.count, count > 0 {
                        let done = message?.toolCalls.filter { $0.result != nil }.count ?? 0
                        Text("\(done)/\(count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(accentColor.opacity(0.45))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
        }
        .background(accentColor.opacity(0.07))
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(accentColor.opacity(0.2)), alignment: .top)
    }
}

// MARK: - Agent Done Banner (erscheint 3 s nach Ende des Streams, dann Fade-out)

private struct AgentDoneBanner: View {
    let duration: TimeInterval?
    let stepCount: Int?
    let theme: AppTheme

    private var durationLabel: String {
        guard let d = duration, d > 0 else { return "" }
        let s = Int(d)
        return s < 60 ? " · \(s)s" : String(format: " · %d:%02d", s / 60, s % 60)
    }
    private var stepsLabel: String {
        guard let n = stepCount, n > 0 else { return "" }
        return " · \(n) Schritte"
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(theme.statusGreen.opacity(0.8))

            Text("Fertig\(durationLabel)\(stepsLabel)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.statusGreen.opacity(0.75))

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(theme.statusGreen.opacity(0.07))
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(theme.statusGreen.opacity(0.2)), alignment: .top)
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
        Button {
            // Suppress PickerDismissMonitor so the picker isn't torn down before this action
            PickerInteractionTracker.shared.didInteract()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark" : "")
                    .font(.system(size: 12))
                    .foregroundStyle(accent)
                    .frame(width: 12)
                Text(label)
                    .font(.system(size: 14))
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
    @Environment(\.appTheme) private var theme
    let label: String
    let selected: Bool
    let accent: Color
    let fg: Color
    let secondary: Color
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button {
            PickerInteractionTracker.shared.didInteract()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.square.fill" : (label == "Auswahl aufheben" ? "xmark.circle" : "square"))
                    .font(.system(size: 14))
                    .foregroundStyle(label == "Auswahl aufheben" ? theme.statusRed.opacity(0.7) : (selected || hovered ? accent : secondary))
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(label == "Auswahl aufheben" ? theme.statusRed.opacity(0.7) : (selected || hovered ? accent : fg))
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
                    .font(.system(size: 13, weight: .medium))
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
                    .font(.system(size: 13, weight: .medium))
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
                    .font(.system(size: 14))
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
                .font(.system(size: 14, weight: .semibold))
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
                .font(.system(size: 11))
                .foregroundStyle(hovered ? accent : secondary.opacity(0.5))
            Text(snippet.title)
                .font(.system(size: 14))
                .foregroundStyle(hovered ? accent : fg)
                .lineLimit(1)
            Spacer()
            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
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

// MARK: - Persona Validation Banner (validating…)

private struct PersonaValidatingBanner: View {
    let theme: AppTheme
    // KRITISCH: kein @State pulse + withAnimation(.repeatForever) → 60fps Layout-Loop.
    // TimelineView(.periodic) = 10fps, render-only.
    private let startDate = Date()
    private let personaColor = Color(red: 0.04, green: 0.57, blue: 0.70)

    var body: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: startDate, by: 0.1)) { ctx in
                let elapsed = ctx.date.timeIntervalSince(startDate)
                let scale = CGFloat(1.0 + 0.08 * abs(sin(.pi * elapsed / 0.8)))
                ZStack {
                    Circle().fill(personaColor.opacity(0.15)).frame(width: 26, height: 26)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11)).foregroundStyle(personaColor)
                }
                .scaleEffect(scale)
            }

            ProgressView().controlSize(.mini)

            Text("Persona analysiert Ergebnis…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(personaColor)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(personaColor.opacity(0.07))
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(personaColor.opacity(0.2)), alignment: .top)
    }
}

// MARK: - Persona Validation Banner (result)

private struct PersonaValidationBanner: View {
    let result: PersonaValidationResult
    let theme: AppTheme
    let onDismiss: () -> Void

    @EnvironmentObject var state: AppState
    @State private var expanded = false
    @State private var fixSent = false
    private let personaColor = Color(red: 0.04, green: 0.57, blue: 0.70)

    var body: some View {
        VStack(spacing: 0) {
            // Top divider
            Rectangle().fill(result.verdict.color(theme: theme).opacity(0.30)).frame(height: 1)

            // Header row (always visible)
            HStack(spacing: 8) {
                // Persona icon
                ZStack {
                    Circle().fill(personaColor.opacity(0.12)).frame(width: 28, height: 28)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 11)).foregroundStyle(personaColor)
                }

                // Persona name
                Text(result.personaName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)

                // Score badge
                ZStack {
                    Circle().fill(result.scoreColor(theme: theme).opacity(0.18)).frame(width: 30, height: 30)
                    Text("\(result.score)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(result.scoreColor(theme: theme))
                }

                // Verdict chip
                HStack(spacing: 4) {
                    Image(systemName: result.verdict.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(result.verdict.label)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(result.verdict.color(theme: theme))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(result.verdict.color(theme: theme).opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(result.verdict.color(theme: theme).opacity(0.3), lineWidth: 0.5))

                Spacer()

                // Expand/collapse
                Button {
                    withAnimation(.spring(response: 0.3)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help(expanded ? "Einklappen" : "Details anzeigen")

                // Dismiss
                Button {
                    withAnimation(.spring(response: 0.25)) { onDismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Bewertung schließen")
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(result.verdict.color(theme: theme).opacity(0.05))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) { expanded.toggle() }
            }

            // Expanded details
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Summary
                    if !result.summary.isEmpty {
                        Text(result.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        // Strengths
                        if !result.strengths.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Überzeugt", systemImage: "hand.thumbsup.fill")
                                    .font(.system(size: 10, weight: .bold)).kerning(0.3)
                                    .foregroundStyle(theme.statusGreen.opacity(0.8))
                                ForEach(result.strengths, id: \.self) { s in
                                    HStack(alignment: .top, spacing: 5) {
                                        Text("·").foregroundStyle(theme.statusGreen.opacity(0.6))
                                        Text(s).font(.system(size: 11)).foregroundStyle(theme.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }

                        // Weaknesses
                        if !result.weaknesses.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Fehlt / stört", systemImage: "hand.thumbsdown.fill")
                                    .font(.system(size: 10, weight: .bold)).kerning(0.3)
                                    .foregroundStyle(theme.statusOrange.opacity(0.8))
                                ForEach(result.weaknesses, id: \.self) { w in
                                    HStack(alignment: .top, spacing: 5) {
                                        Text("·").foregroundStyle(theme.statusOrange.opacity(0.6))
                                        Text(w).font(.system(size: 11)).foregroundStyle(theme.secondaryText)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }

                    // Recommendation
                    if !result.recommendation.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(personaColor)
                            Text(result.recommendation)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(personaColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(personaColor.opacity(0.20), lineWidth: 0.5))
                    }

                    // Fix-Handoff Actions
                    if !result.weaknesses.isEmpty || !result.recommendation.isEmpty {
                        Divider().opacity(0.3)
                        HStack(spacing: 8) {
                            Button {
                                state.pendingChatMessage = buildFixPrompt()
                                fixSent = true
                            } label: {
                                Label("Issues beheben", systemImage: "wrench.and.screwdriver")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(personaColor))
                            }
                            .buttonStyle(.plain)
                            .help("Issues als Fix-Prompt in den Chat laden")

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(buildFixPrompt(), forType: .string)
                                fixSent = true
                            } label: {
                                Label("Kopieren", systemImage: "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(personaColor)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(personaColor.opacity(0.10)))
                                    .overlay(Capsule().strokeBorder(personaColor.opacity(0.3), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .help("Fix-Prompt in die Zwischenablage kopieren")

                            if fixSent {
                                Label("Gesendet", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.statusGreen)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 10).padding(.top, 4)
                .background(result.verdict.color(theme: theme).opacity(0.04))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func buildFixPrompt() -> String {
        var lines: [String] = ["Bitte behebe die folgenden Issues aus dem \(result.personaName)-Review:\n"]
        if !result.weaknesses.isEmpty {
            lines.append("## Gefundene Probleme")
            for w in result.weaknesses { lines.append("- \(w)") }
            lines.append("")
        }
        if !result.recommendation.isEmpty {
            lines.append("## Empfehlung")
            lines.append(result.recommendation)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Markdown Text Renderer

// MarkdownTextView is defined in MarkdownTextView.swift

// MARK: - Inline expandable search bar (used by file preview headers)

/// Always-visible inline search field with match counter and ↑↓ navigation.
/// Used in file preview headers (Chat + Files section).
struct InlineSearchBar: View {
    @Binding var query: String
    @Binding var currentMatch: Int
    let matchCount: Int
    var width: CGFloat = 160
    var placeholder: String = "Suchen"

    @Environment(\.appTheme) var theme
    @FocusState private var focused: Bool

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.primaryText)
                .focused($focused)
                .frame(width: width)
                .onSubmit { advance(+1) }
            if !query.isEmpty {
                Text(matchCount > 0 ? "\(currentMatch + 1)/\(matchCount)" : "0")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(matchCount > 0 ? accentColor : theme.statusRed)
                Button { advance(-1) } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(matchCount > 0 ? theme.primaryText : theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .disabled(matchCount == 0)
                .help("Vorheriger Treffer (⇧⌘G)")
                .keyboardShortcut("g", modifiers: [.command, .shift])
                Button { advance(+1) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(matchCount > 0 ? theme.primaryText : theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .disabled(matchCount == 0)
                .help("Nächster Treffer (⌘G)")
                .keyboardShortcut("g", modifiers: .command)
                Button {
                    query = ""
                    currentMatch = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .help("Suche zurücksetzen")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.cardBorder, lineWidth: 0.5)
        )
        .onKeyPress(.escape) {
            query = ""
            focused = false
            return .handled
        }
    }

    private func advance(_ delta: Int) {
        guard matchCount > 0 else { return }
        currentMatch = ((currentMatch + delta) % matchCount + matchCount) % matchCount
    }
}
