import SwiftUI

struct AgentsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @State private var selectedAgent: AgentDefinition?
    @State private var showRunSheet = false
    @State private var runTask = ""
    @State private var runOutput = ""
    @State private var isRunning = false
    @State private var runSessionId: String?
    @State private var searchText = ""

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var filteredAgents: [AgentDefinition] {
        guard !searchText.isEmpty else { return state.agentService.agents }
        return state.agentService.agents.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            agentList
                .frame(width: 260)

            Divider().foregroundStyle(theme.cardBorder)

            if let agent = selectedAgent {
                agentDetail(agent)
            } else {
                agentPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if state.agentService.agents.isEmpty {
                await state.agentService.loadAgents()
            }
        }
    }

    // MARK: - Agent list

    private var agentList: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Agents")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("\(state.agentService.agents.count)")
                    .font(.system(size: 11)).foregroundStyle(theme.tertiaryText)
                Button {
                    Task { await state.agentService.loadAgents() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText)
            }
            .padding(12)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(theme.tertiaryText)
                TextField("Agent suchen…", text: $searchText)
                    .textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(8)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder, lineWidth: 0.5))
            .padding(.horizontal, 10).padding(.bottom, 8)

            Divider().foregroundStyle(theme.cardBorder)

            if filteredAgents.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "cpu").font(.system(size: 28)).foregroundStyle(theme.tertiaryText)
                    Text("Keine Agents gefunden")
                        .font(.system(size: 12)).foregroundStyle(theme.secondaryText)
                    Text("Agents werden in\n~/.claude/agents/ gespeichert")
                        .font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredAgents) { agent in
                            agentRow(agent)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private func agentRow(_ agent: AgentDefinition) -> some View {
        let isSelected = selectedAgent?.id == agent.id

        return Button {
            withAnimation(.spring(response: 0.3)) { selectedAgent = agent }
        } label: {
            HStack(spacing: 10) {
                // Color dot + icon
                ZStack {
                    Circle()
                        .fill(agent.dotColor.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(agent.dotColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(agent.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                        Spacer()
                        modelBadge(agent.model, color: accentColor)
                    }
                    Text(agent.description)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? theme.accent : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? theme.accentBorder : .clear, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func modelBadge(_ model: String, color: Color) -> some View {
        Text(model.lowercased())
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Agent detail

    private func agentDetail(_ agent: AgentDefinition) -> some View {
        VStack(spacing: 0) {
            // Agent header
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(agent.dotColor.opacity(0.2)).frame(width: 44, height: 44)
                    Image(systemName: "cpu.fill").font(.system(size: 18)).foregroundStyle(agent.dotColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.name).font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(agent.description)
                        .font(.system(size: 11)).foregroundStyle(theme.secondaryText).lineLimit(2)
                }

                Spacer()

                HStack(spacing: 8) {
                    modelBadge(agent.model, color: accentColor)

                    Button {
                        runTask = ""
                        runOutput = ""
                        showRunSheet = true
                    } label: {
                        Label("Ausführen", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                    .controlSize(.regular)
                }
            }
            .padding(16)

            Divider().foregroundStyle(theme.cardBorder)

            // Run panel (inline when active)
            if showRunSheet {
                runPanel(agent)
                Divider().foregroundStyle(theme.cardBorder)
            }

            // Prompt body
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Metadata
                    HStack(spacing: 12) {
                        metaTag("Model", value: agent.model)
                        if let mem = agent.memory { metaTag("Memory", value: mem) }
                        if let col = agent.color { metaTag("Color", value: col) }
                    }

                    Divider().foregroundStyle(theme.cardBorder)

                    Text("SYSTEM PROMPT")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                        .kerning(0.6)

                    Text(agent.promptBody.isEmpty ? "(Kein Prompt)" : agent.promptBody)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.primaryText.opacity(0.8))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Memory
                    if let memory = state.agentService.loadAgentMemory(agentId: agent.id) {
                        Divider().foregroundStyle(theme.cardBorder)
                        Text("AGENT MEMORY")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)
                            .kerning(0.6)
                        Text(memory)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Run panel

    private func runPanel(_ agent: AgentDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Aufgabe ausführen")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Button {
                    showRunSheet = false
                    isRunning = false
                    runOutput = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14)).foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Beschreibe die Aufgabe…", text: $runTask, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .font(.system(size: 12))

                Button {
                    executeAgent(agent)
                } label: {
                    Image(systemName: isRunning ? "stop.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(isRunning ? .red : accentColor, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(runTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRunning)
            }

            if !runOutput.isEmpty {
                ScrollView {
                    Text(runOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.primaryText.opacity(0.85))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 200)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(theme.cardBorder, lineWidth: 0.5))
            }
        }
        .padding(12)
        .background(theme.primaryText.opacity(0.03))
    }

    private func executeAgent(_ agent: AgentDefinition) {
        let task = runTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        runOutput = ""
        isRunning = true

        Task { @MainActor in
            let stream = state.cliService.send(
                message: task,
                sessionId: runSessionId,
                agentName: agent.id
            )

            do {
                for try await event in stream {
                    if let sid = event.sessionId { runSessionId = sid }

                    if event.type == "assistant",
                       let content = event.message?.content {
                        for block in content {
                            if block.type == "text", let text = block.text {
                                runOutput += text
                            }
                        }
                    }
                }
            } catch {
                runOutput += "\n[Fehler: \(error.localizedDescription)]"
            }
            isRunning = false
        }
    }

    private func metaTag(_ key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key.uppercased())
                .font(.system(size: 8, weight: .semibold)).foregroundStyle(theme.tertiaryText).kerning(0.4)
            Text(value)
                .font(.system(size: 11)).foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
    }

    // MARK: - Placeholder

    private var agentPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 36)).foregroundStyle(theme.tertiaryText)
            Text("Agent auswählen")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.secondaryText)
            Text("Wähle einen Agent aus der Liste\num Details zu sehen und ihn auszuführen.")
                .font(.system(size: 12)).foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
