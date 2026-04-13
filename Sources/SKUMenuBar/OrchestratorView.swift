import SwiftUI

struct OrchestratorView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    @State private var masterTask: String = ""
    @State private var selectedAgentIds: Set<String> = []
    @State private var lanes: [OrchestratorLane] = []
    @State private var isRunning: Bool = false

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Multi-Agent Orchestrator")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                    Text("Weise Aufgaben an mehrere Agents gleichzeitig zu")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                if isRunning {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("\(lanes.filter { $0.isStreaming }.count) aktiv")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .padding(20)

            Divider().foregroundStyle(theme.cardBorder)

            if lanes.isEmpty {
                setupPanel
            } else {
                lanesPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Setup Panel

    private var setupPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Task input
                VStack(alignment: .leading, spacing: 8) {
                    Text("AUFGABE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                        .kerning(0.8)
                    ZStack(alignment: .topLeading) {
                        if masterTask.isEmpty {
                            Text("Beschreibe den komplexen Task, der auf mehrere Agents aufgeteilt werden soll...")
                                .foregroundStyle(theme.tertiaryText)
                                .font(.system(size: 13))
                                .padding(.horizontal, 4).padding(.vertical, 8)
                        }
                        TextEditor(text: $masterTask)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.primaryText)
                            .scrollContentBackground(.hidden)
                            .background(.clear)
                            .frame(minHeight: 80, maxHeight: 150)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(theme.cardSurface)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.cardBorder, lineWidth: 1)))
                }

                // Agent selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("AGENTS AUSWÄHLEN")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                        .kerning(0.8)

                    if state.agentService.agents.isEmpty {
                        Text("Keine Agents gefunden. Erstelle Agents in ~/.claude/agents/")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.tertiaryText)
                            .padding(12)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            // Option: No specific agent (plain claude)
                            agentToggle(id: "", name: "Claude (kein Agent)", desc: "Standard ohne Agent", icon: "bubble.left")
                            ForEach(state.agentService.agents) { agent in
                                agentToggle(id: agent.id, name: agent.name, desc: agent.description, icon: "cpu")
                            }
                        }
                    }
                }

                // Run button
                Button {
                    startOrchestration()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 14))
                        Text("Orchestration starten (\(selectedAgentIds.count) Agents)")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(masterTask.isEmpty || selectedAgentIds.isEmpty
                                  ? AnyShapeStyle(Color.gray.opacity(0.3))
                                  : AnyShapeStyle(LinearGradient(
                                      colors: [accentColor, accentColor.opacity(0.7)],
                                      startPoint: .leading, endPoint: .trailing)))
                    )
                }
                .buttonStyle(.plain)
                .disabled(masterTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAgentIds.isEmpty)
            }
            .padding(20)
        }
    }

    private func agentToggle(id: String, name: String, desc: String, icon: String) -> some View {
        let isSelected = selectedAgentIds.contains(id)
        return Button {
            if isSelected { selectedAgentIds.remove(id) }
            else { selectedAgentIds.insert(id) }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? accentColor.opacity(0.2) : theme.cardBorder.opacity(0.5))
                        .frame(width: 28, height: 28)
                    Image(systemName: isSelected ? "checkmark" : icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? accentColor : theme.secondaryText)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(theme.cardSurface)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? accentColor.opacity(0.4) : theme.cardBorder, lineWidth: isSelected ? 1.5 : 1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lanes Panel

    private var lanesPanel: some View {
        VStack(spacing: 0) {
            // Control bar
            HStack {
                Text(masterTask)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                Spacer()
                Button {
                    lanes = []
                    isRunning = false
                } label: {
                    Label("Neue Orchestration", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(theme.cardSurface)

            Divider().foregroundStyle(theme.cardBorder)

            // Agent lanes side by side
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(lanes.indices, id: \.self) { index in
                        OrchestratorLaneView(lane: $lanes[index])
                            .frame(width: 380)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func startOrchestration() {
        let task = masterTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty else { return }

        lanes = selectedAgentIds.map { agentId in
            let agentName = agentId.isEmpty ? "Claude" :
                (state.agentService.agents.first { $0.id == agentId }?.name ?? agentId)
            return OrchestratorLane(agentId: agentId, agentName: agentName, task: task)
        }
        isRunning = true
    }
}

// MARK: - Lane Model

struct OrchestratorLane: Identifiable {
    let id = UUID()
    let agentId: String
    let agentName: String
    let task: String
    var output: String = ""
    var isStreaming: Bool = false
    var isDone: Bool = false
    var error: String?
}

// MARK: - Lane View

struct OrchestratorLaneView: View {
    @Binding var lane: OrchestratorLane
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Lane header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(lane.isDone ? Color.green.opacity(0.2) : accentColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    if lane.isStreaming {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Image(systemName: lane.isDone ? "checkmark" : "cpu")
                            .font(.system(size: 13))
                            .foregroundStyle(lane.isDone ? .green : accentColor)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(lane.agentName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(lane.isDone ? "Fertig" : lane.isStreaming ? "Läuft..." : "Bereit")
                        .font(.system(size: 11))
                        .foregroundStyle(lane.isDone ? .green : lane.isStreaming ? accentColor : theme.tertiaryText)
                }
                Spacer()
                if let err = lane.error {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .help(err)
                }
            }
            .padding(12)
            .background(theme.cardSurface)

            Divider().foregroundStyle(theme.cardBorder)

            // Output
            ScrollView {
                Text(lane.output.isEmpty ? "Warte auf Ausgabe..." : lane.output)
                    .font(.system(size: 14))
                    .foregroundStyle(lane.output.isEmpty ? theme.tertiaryText : theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.cardSurface)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.cardBorder, lineWidth: 1)))
        .task {
            await runLane()
        }
    }

    @MainActor
    private func runLane() async {
        lane.isStreaming = true
        let stream = state.cliService.send(
            message: lane.task,
            sessionId: nil,
            agentName: lane.agentId.isEmpty ? nil : lane.agentId,
            model: "claude-sonnet-4-6"
        )
        do {
            for try await event in stream {
                if let content = event.message?.content {
                    for block in content {
                        if block.type == "text", let t = block.text, !t.isEmpty {
                            lane.output += t
                        }
                    }
                }
                if event.type == "result" {
                    lane.isDone = true
                }
            }
        } catch {
            lane.error = error.localizedDescription
        }
        lane.isStreaming = false
        lane.isDone = true
    }
}
