import SwiftUI
import Foundation

// MARK: - Phase

enum OrchestrationPhase: Equatable {
    case setup
    case planning
    case planReady
    case executing
    case synthesizing
    case reflecting
    case done
}

// MARK: - Subtask Model

struct OrchestratorSubtask: Identifiable {
    let id: String
    let agentId: String
    let agentName: String
    let task: String
    let rationale: String
    var output: String = ""
    var isStreaming: Bool = false
    var isDone: Bool = false
    var error: String?
}

// MARK: - Reflection Status

enum ReflectionStatus: Equatable {
    case pending
    case running
    case done
    case skipped   // plain Claude — no file to write to
    case error(String)
}

// MARK: - Main View

struct OrchestratorView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    // Setup
    @State private var masterTask: String = ""
    @State private var selectedAgentIds: Set<String> = []

    // Runtime
    @State private var phase: OrchestrationPhase = .setup
    @State private var plannerOutput: String = ""
    @State private var planDescription: String = ""
    @State private var subtasks: [OrchestratorSubtask] = []
    @State private var finalOutput: String = ""
    @State private var orchestrationError: String?

    // Reflections: subtask.id → status
    @State private var reflectionStatus: [String: ReflectionStatus] = [:]

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    /// Agent-IDs deren Trigger-Keywords im masterTask vorkommen
    private var triggerMatchedIds: Set<String> {
        guard !masterTask.isEmpty else { return [] }
        let lower = masterTask.lowercased()
        var matched: Set<String> = []
        for agent in state.agentService.agents {
            let hits = agent.effectiveTriggers.filter { lower.contains($0.lowercased()) }
            if !hits.isEmpty { matched.insert(agent.id) }
        }
        return matched
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().foregroundStyle(theme.cardBorder)

            switch phase {
            case .setup:        setupPanel
            case .planning:     planningPanel
            case .planReady:    planReadyPanel
            case .executing:    executingPanel
            case .synthesizing: synthesizingPanel
            case .reflecting:   reflectingPanel
            case .done:         donePanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { preselectAllAgents() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Multi-Agent Orchestrator")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text(headerSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .animation(.easeInOut, value: phase)
            }
            Spacer()

            if phase != .setup {
                phaseStepIndicator
                    .padding(.trailing, 12)
                Button { reset() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(.plain)
                .help("Neue Orchestration")
            }
        }
        .padding(20)
    }

    private var headerSubtitle: String {
        switch phase {
        case .setup:        return "Weise Aufgaben intelligent an mehrere Agents"
        case .planning:     return "Planner analysiert und verteilt den Task..."
        case .planReady:    return "Plan bereit — \(subtasks.count) Subtasks erkannt"
        case .executing:
            let active = subtasks.filter { $0.isStreaming }.count
            let done   = subtasks.filter { $0.isDone }.count
            return "\(active) aktiv · \(done)/\(subtasks.count) fertig"
        case .synthesizing: return "Synthesizer fasst alle Ergebnisse zusammen..."
        case .reflecting:
            let done = reflectionStatus.values.filter { $0 == .done || $0 == .skipped }.count
            return "Agents schreiben Lessons Learned (\(done)/\(reflectionStatus.count))..."
        case .done:         return "Orchestration abgeschlossen"
        }
    }

    private var phaseStepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Array(["Plan", "Exec", "Synth", "Reflect"].enumerated()), id: \.offset) { i, label in
                let stepIndex = i + 1
                let isActive  = currentPhaseIndex >= stepIndex
                let isCurrent = currentPhaseIndex == stepIndex
                HStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(isActive ? accentColor : theme.cardBorder.opacity(0.5))
                            .frame(width: 7, height: 7)
                        if isCurrent {
                            Circle().fill(Color.white.opacity(0.7)).frame(width: 3, height: 3)
                        }
                    }
                    Text(label)
                        .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isActive ? accentColor : theme.tertiaryText)
                }
                if i < 3 {
                    Rectangle()
                        .fill(currentPhaseIndex > stepIndex
                              ? accentColor.opacity(0.5)
                              : theme.cardBorder.opacity(0.3))
                        .frame(width: 12, height: 1)
                }
            }
        }
    }

    private var currentPhaseIndex: Int {
        switch phase {
        case .setup:        return 0
        case .planning:     return 1
        case .planReady:    return 1
        case .executing:    return 2
        case .synthesizing: return 3
        case .reflecting:   return 4
        case .done:         return 4
        }
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
                    .background(
                        RoundedRectangle(cornerRadius: 10).fill(theme.cardSurface)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.cardBorder, lineWidth: 1))
                    )
                }

                // Agent pool
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("AGENT-POOL")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)
                            .kerning(0.8)
                        // Count-Badge: zeigt wie viele aktiv sind
                        if selectedAgentIds.count > 0 {
                            Text("\(selectedAgentIds.count) aktiv")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(accentColor.opacity(0.12)))
                        }
                        Spacer()
                        if !state.agentService.agents.isEmpty {
                            Button {
                                if selectedAgentIds.count == state.agentService.agents.count + 1 {
                                    selectedAgentIds = []
                                } else {
                                    preselectAllAgents()
                                }
                            } label: {
                                Text(selectedAgentIds.count == state.agentService.agents.count + 1
                                     ? "Alle abwählen" : "Alle auswählen")
                                    .font(.system(size: 11))
                                    .foregroundStyle(accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if state.agentService.agents.isEmpty {
                        emptyAgentState
                    } else {
                        let matched = triggerMatchedIds
                        if !masterTask.isEmpty && !matched.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(accentColor)
                                Text("\(matched.count) Agent\(matched.count == 1 ? "" : "s") durch Trigger erkannt")
                                    .font(.system(size: 12))
                                    .foregroundStyle(accentColor)
                            }
                            .padding(.bottom, 2)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            agentToggle(id: "", name: "Claude", desc: "Standard ohne Agent",
                                        icon: "bubble.left", triggers: [], isMatched: false)
                            ForEach(state.agentService.agents) { agent in
                                agentToggle(id: agent.id, name: agent.name, desc: agent.description,
                                            icon: "cpu", triggers: agent.effectiveTriggers,
                                            isMatched: matched.contains(agent.id))
                            }
                        }
                    }
                }

                // Start button
                Button { startPlanning() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars").font(.system(size: 14))
                        Text("Orchestration planen (\(selectedAgentIds.count) Agents)")
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

    // Empty state with onboarding info
    private var emptyAgentState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(accentColor)
                Text("Noch keine Agents vorhanden")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.primaryText)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("So erstellst du Agents:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)

                ForEach([
                    ("1", "Öffne den **Agents**-Tab in der Sidebar"),
                    ("2", "Klicke auf **+** um einen neuen Agent anzulegen"),
                    ("3", "Gib Name, Beschreibung und System-Prompt ein"),
                    ("4", "Der Agent wird als `.md`-Datei unter `~/.claude/agents/` gespeichert")
                ], id: \.0) { step, text in
                    HStack(alignment: .top, spacing: 8) {
                        Text(step)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(accentColor)
                            .frame(width: 14, height: 14)
                            .background(Circle().fill(accentColor.opacity(0.15)))
                        Text(LocalizedStringKey(text))
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(theme.cardSurface)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.cardBorder, lineWidth: 1))
            )

            Text("Du kannst den Orchestrator auch mit **Claude (kein Agent)** als einzigem Pool-Member starten.")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText)
        }
    }

    private func agentToggle(id: String, name: String, desc: String,
                             icon: String, triggers: [String], isMatched: Bool) -> some View {
        let isSelected = selectedAgentIds.contains(id)
        let borderColor: Color = isMatched ? accentColor.opacity(0.6)
                                : isSelected ? accentColor.opacity(0.35)
                                : theme.cardBorder
        let borderWidth: CGFloat = (isMatched || isSelected) ? 1.5 : 1

        return Button {
            if isSelected { selectedAgentIds.remove(id) }
            else          { selectedAgentIds.insert(id) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? accentColor.opacity(0.25) : theme.cardBorder.opacity(0.4))
                            .frame(width: 30, height: 30)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : icon)
                            .font(.system(size: isSelected ? 15 : 13, weight: .medium))
                            .foregroundStyle(isSelected ? accentColor : theme.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(name)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? accentColor : theme.primaryText)
                                .lineLimit(1)
                            if isMatched {
                                HStack(spacing: 2) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 9))
                                    Text("Match")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(accentColor.opacity(0.15)))
                            }
                        }
                        Text(desc)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.tertiaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                // Trigger chips
                if !triggers.isEmpty {
                    let taskLower = masterTask.lowercased()
                    FlexTriggerRow(
                        triggers: triggers,
                        highlight: triggers.filter { taskLower.contains($0.lowercased()) },
                        accentColor: accentColor,
                        theme: theme
                    )
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? accentColor.opacity(0.08) : (isMatched ? accentColor.opacity(0.04) : theme.cardSurface))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(borderColor, lineWidth: borderWidth))
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // MARK: - Planning Panel

    private var planningPanel: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(accentColor.opacity(0.1)).frame(width: 56, height: 56)
                    ProgressView().scaleEffect(1.1)
                }
                Text("Planner analysiert deinen Task...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                Text("Claude wählt die besten Agents und verteilt die Aufgaben optimal")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            if !plannerOutput.isEmpty {
                ScrollView {
                    Text(plannerOutput)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(theme.tertiaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 140)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.cardSurface))
                .padding(.horizontal, 24)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Plan Ready Panel

    private var planReadyPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !planDescription.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PLAN")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.tertiaryText)
                                .kerning(0.8)
                            Text(planDescription)
                                .font(.system(size: 14))
                                .foregroundStyle(theme.secondaryText)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(accentColor.opacity(0.07))
                                        .overlay(RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(accentColor.opacity(0.2), lineWidth: 1))
                                )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUBTASKS (\(subtasks.count))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)
                            .kerning(0.8)
                        ForEach(subtasks.indices, id: \.self) { i in
                            planSubtaskCard(subtasks[i], index: i)
                        }
                    }
                }
                .padding(20)
            }

            Divider().foregroundStyle(theme.cardBorder)

            HStack(spacing: 12) {
                Button { reset() } label: {
                    Text("Zurück")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryText)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8).fill(theme.cardSurface)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(theme.cardBorder, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                Spacer()
                Button { startExecution() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill").font(.system(size: 13))
                        Text("Agents starten").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .leading, endPoint: .trailing))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
    }

    private func planSubtaskCard(_ subtask: OrchestratorSubtask, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(accentColor.opacity(0.15)).frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(subtask.agentName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text(subtask.task)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.primaryText)
                if !subtask.rationale.isEmpty {
                    Text(subtask.rationale)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                        .italic()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(theme.cardSurface)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.cardBorder, lineWidth: 1))
        )
    }

    // MARK: - Executing Panel

    private var executingPanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(subtasks.indices, id: \.self) { i in
                    executingLaneView(index: i).frame(width: 360)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func executingLaneView(index: Int) -> some View {
        let subtask = subtasks[index]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(subtask.isDone ? Color.green.opacity(0.2) : accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    if subtask.isStreaming {
                        ProgressView().scaleEffect(0.65)
                    } else {
                        Image(systemName: subtask.isDone ? "checkmark"
                              : subtask.error != nil ? "exclamationmark" : "clock")
                            .font(.system(size: 14))
                            .foregroundStyle(subtask.isDone ? .green
                                             : subtask.error != nil ? .red : accentColor)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(subtask.agentName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                    Text(subtask.isDone ? "Fertig"
                         : subtask.isStreaming ? "Läuft..."
                         : subtask.error != nil ? "Fehler" : "Wartet")
                        .font(.system(size: 11))
                        .foregroundStyle(subtask.isDone ? .green
                                         : subtask.isStreaming ? accentColor
                                         : subtask.error != nil ? .red : theme.tertiaryText)
                }
                Spacer()
                if let err = subtask.error {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red).font(.system(size: 14))
                        .help(err)
                }
            }
            .padding(12)
            .background(theme.cardSurface)

            Text(subtask.task)
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(2)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(theme.cardSurface)

            Divider().foregroundStyle(theme.cardBorder)

            ScrollView {
                Text(subtask.output.isEmpty ? "Warte auf Ausgabe..." : subtask.output)
                    .font(.system(size: 14))
                    .foregroundStyle(subtask.output.isEmpty ? theme.tertiaryText : theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: .infinity)
        }
        .background(
            RoundedRectangle(cornerRadius: 12).fill(theme.cardSurface)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.cardBorder, lineWidth: 1))
        )
    }

    // MARK: - Synthesizing Panel

    private var synthesizingPanel: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(accentColor.opacity(0.1)).frame(width: 56, height: 56)
                    ProgressView().scaleEffect(1.1)
                }
                Text("Synthesizer fasst zusammen...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                Text("Alle Agent-Ergebnisse werden zu einem kohärenten Gesamtergebnis zusammengeführt")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            if !finalOutput.isEmpty {
                ScrollView {
                    Text(finalOutput)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 180)
                .background(RoundedRectangle(cornerRadius: 10).fill(theme.cardSurface))
                .padding(.horizontal, 24)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Reflecting Panel

    private var reflectingPanel: some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(accentColor.opacity(0.1)).frame(width: 56, height: 56)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 22))
                        .foregroundStyle(accentColor)
                }
                Text("Agents schreiben Lessons Learned...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                Text("Jeder Agent reflektiert seine Arbeit und dokumentiert Erkenntnisse in seiner Memory")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            VStack(spacing: 8) {
                ForEach(subtasks) { subtask in
                    let status = reflectionStatus[subtask.id] ?? .pending
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(statusColor(status).opacity(0.15))
                                .frame(width: 26, height: 26)
                            if status == .running {
                                ProgressView().scaleEffect(0.55)
                            } else {
                                Image(systemName: statusIcon(status))
                                    .font(.system(size: 12))
                                    .foregroundStyle(statusColor(status))
                            }
                        }
                        Text(subtask.agentName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        Text(statusLabel(status))
                            .font(.system(size: 12))
                            .foregroundStyle(statusColor(status))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(theme.cardSurface)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(theme.cardBorder, lineWidth: 1))
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusColor(_ s: ReflectionStatus) -> Color {
        switch s {
        case .pending:  return theme.tertiaryText
        case .running:  return accentColor
        case .done:     return .green
        case .skipped:  return theme.tertiaryText
        case .error:    return .red
        }
    }

    private func statusIcon(_ s: ReflectionStatus) -> String {
        switch s {
        case .pending:  return "clock"
        case .running:  return "pencil"
        case .done:     return "checkmark"
        case .skipped:  return "minus"
        case .error:    return "exclamationmark"
        }
    }

    private func statusLabel(_ s: ReflectionStatus) -> String {
        switch s {
        case .pending:  return "Wartet"
        case .running:  return "Schreibt..."
        case .done:     return "Gespeichert"
        case .skipped:  return "Übersprungen"
        case .error(let e): return "Fehler: \(e)"
        }
    }

    // MARK: - Done Panel

    private var donePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Final result
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green).font(.system(size: 14))
                        Text("FINALES ERGEBNIS")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)
                            .kerning(0.8)
                    }
                    Text(finalOutput)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.primaryText)
                        .textSelection(.enabled)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10).fill(theme.cardSurface)
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(accentColor.opacity(0.25), lineWidth: 1))
                        )
                }

                // Agent outputs — prominent headers
                VStack(alignment: .leading, spacing: 8) {
                    Text("AGENT-AUSGABEN")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                        .kerning(0.8)

                    ForEach(subtasks) { subtask in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                if let status = reflectionStatus[subtask.id], status == .done {
                                    HStack(spacing: 4) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 11))
                                            .foregroundStyle(accentColor)
                                        Text("Lessons Learned gespeichert")
                                            .font(.system(size: 11))
                                            .foregroundStyle(accentColor)
                                    }
                                    .padding(.top, 4)
                                }
                                Text(subtask.output.isEmpty ? "Keine Ausgabe" : subtask.output)
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.secondaryText)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 4)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                // Agent status dot
                                Circle()
                                    .fill(subtask.error != nil ? Color.red : Color.green)
                                    .frame(width: 7, height: 7)
                                // Agent name — prominent
                                Text(subtask.agentName)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(theme.primaryText)
                                // Subtask label
                                Text("·")
                                    .foregroundStyle(theme.tertiaryText)
                                Text(subtask.task)
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.tertiaryText)
                                    .lineLimit(1)
                                Spacer()
                                // Memory badge
                                if let status = reflectionStatus[subtask.id], status == .done {
                                    Label("Memory", systemImage: "brain.head.profile")
                                        .font(.system(size: 11))
                                        .foregroundStyle(accentColor)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(accentColor.opacity(0.1)))
                                }
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10).fill(theme.cardSurface)
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(theme.cardBorder, lineWidth: 1))
                        )
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - FlexTriggerRow (inline helper, no Layout required)

    // MARK: - Logic: Reset + Preselect

    private func reset() {
        phase = .setup
        plannerOutput = ""
        planDescription = ""
        subtasks = []
        finalOutput = ""
        orchestrationError = nil
        reflectionStatus = [:]
    }

    private func preselectAllAgents() {
        var ids: Set<String> = [""]  // plain Claude immer dabei
        for agent in state.agentService.agents {
            ids.insert(agent.id)
        }
        selectedAgentIds = ids
    }

    // MARK: - Logic: Phase 1 — Planning

    private func startPlanning() {
        let task = masterTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, !selectedAgentIds.isEmpty else { return }
        phase = .planning
        plannerOutput = ""
        Task { await runPlanner(task: task) }
    }

    @MainActor
    private func runPlanner(task: String) async {
        let agentLines = selectedAgentIds.sorted().compactMap { id -> String? in
            if id.isEmpty {
                return "- id: \"\", name: \"Claude\", description: \"Standard Claude, geeignet für allgemeine Aufgaben\""
            }
            guard let a = state.agentService.agents.first(where: { $0.id == id }) else { return nil }
            let triggerStr = a.effectiveTriggers.isEmpty ? "" : " | triggers: \(a.effectiveTriggers.joined(separator: ", "))"
            return "- id: \"\(a.id)\", name: \"\(a.name)\", description: \"\(a.description)\"\(triggerStr)"
        }.joined(separator: "\n")

        let prompt = """
Du bist ein präziser Task-Planner. Analysiere den Task und teile ihn in 2-5 sinnvolle, \
unabhängig ausführbare Subtasks auf. Jeder Subtask geht an den am besten geeigneten Agent. \
Nutze jeden Agent höchstens einmal.

Verfügbare Agents:
\(agentLines)

Master-Task: \(task)

Antworte AUSSCHLIESSLICH mit validem JSON, kein Markdown, kein erklärender Text:
{
  "plan": "Kurze Beschreibung des Gesamtansatzes (1-2 Sätze)",
  "subtasks": [
    {
      "id": "1",
      "agentId": "agent-id-oder-leer-für-plain-claude",
      "agentName": "Agent Name",
      "task": "Spezifischer, detaillierter Subtask für diesen Agent",
      "rationale": "Warum dieser Agent für diesen Subtask ideal ist"
    }
  ]
}
"""
        let stream = state.cliService.send(
            message: prompt,
            systemPrompt: "Du bist ein präziser Task-Planner. Antworte ausschließlich mit validem JSON.",
            model: "claude-sonnet-4-6"
        )
        var raw = ""
        do {
            for try await event in stream {
                if event.type == "assistant", let content = event.message?.content {
                    for block in content where block.type == "text" {
                        if let t = block.text, !t.isEmpty { raw += t; plannerOutput = raw }
                    }
                }
            }
        } catch {
            orchestrationError = error.localizedDescription
            phase = .setup
            return
        }
        parsePlan(raw)
    }

    private func parsePlan(_ raw: String) {
        var json = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = json.range(of: "```json") { json = String(json[r.upperBound...]) }
        else if let r = json.range(of: "```") { json = String(json[r.upperBound...]) }
        if let r = json.range(of: "```", options: .backwards) { json = String(json[..<r.lowerBound]) }
        if let s = json.firstIndex(of: "{"), let e = json.lastIndex(of: "}") {
            json = String(json[s...e])
        }

        guard
            let data = json.data(using: .utf8),
            let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let arr  = obj["subtasks"] as? [[String: Any]]
        else {
            subtasks = [OrchestratorSubtask(id: "1", agentId: "", agentName: "Claude",
                                            task: masterTask, rationale: "Direktausführung")]
            planDescription = "Direkte Ausführung (Planner-Output konnte nicht geparst werden)"
            phase = .planReady
            return
        }

        planDescription = obj["plan"] as? String ?? ""
        subtasks = arr.compactMap { d in
            guard let id = d["id"] as? String, let agentId = d["agentId"] as? String,
                  let agentName = d["agentName"] as? String, let task = d["task"] as? String
            else { return nil }
            return OrchestratorSubtask(id: id, agentId: agentId, agentName: agentName,
                                       task: task, rationale: d["rationale"] as? String ?? "")
        }
        if subtasks.isEmpty {
            subtasks = [OrchestratorSubtask(id: "1", agentId: "", agentName: "Claude",
                                            task: masterTask, rationale: "Fallback")]
        }
        phase = .planReady
    }

    // MARK: - Logic: Phase 2 — Executing

    private func startExecution() {
        phase = .executing
        for i in subtasks.indices {
            Task { await runSubtask(index: i) }
        }
        Task { await waitForAllThenSynthesize() }
    }

    @MainActor
    private func runSubtask(index: Int) async {
        guard index < subtasks.count else { return }
        subtasks[index].isStreaming = true
        let subtask = subtasks[index]
        let stream  = state.cliService.send(
            message:   subtask.task,
            agentName: subtask.agentId.isEmpty ? nil : subtask.agentId,
            model:     "claude-sonnet-4-6"
        )
        do {
            for try await event in stream {
                if event.type == "assistant", let content = event.message?.content {
                    for block in content where block.type == "text" {
                        if let t = block.text, !t.isEmpty { subtasks[index].output += t }
                    }
                }
                if event.type == "result" { subtasks[index].isDone = true }
            }
        } catch {
            subtasks[index].error = error.localizedDescription
        }
        subtasks[index].isStreaming = false
        subtasks[index].isDone = true
    }

    @MainActor
    private func waitForAllThenSynthesize() async {
        while subtasks.contains(where: { !$0.isDone }) {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        phase = .synthesizing
        finalOutput = ""
        await runSynthesizer()
    }

    // MARK: - Logic: Phase 3 — Synthesizing

    @MainActor
    private func runSynthesizer() async {
        let sections = subtasks.enumerated().map { i, s in
            "## \(s.agentName) — Subtask \(i + 1)\nAufgabe: \(s.task)\n\n\(s.output)"
        }.joined(separator: "\n\n---\n\n")

        let prompt = """
Ich habe den folgenden Master-Task an mehrere spezialisierte Agents delegiert:

**Master-Task:** \(masterTask)

Hier sind die Ergebnisse der einzelnen Agents:

\(sections)

Fasse alle Ergebnisse zu einem kohärenten, vollständigen Gesamtergebnis zusammen. \
Strukturiere die Antwort klar, hebe die wichtigsten Erkenntnisse hervor und stelle sicher, \
dass das Ergebnis als geschlossenes Ganzes lesbar ist.
"""
        let stream = state.cliService.send(message: prompt, model: "claude-sonnet-4-6")
        do {
            for try await event in stream {
                if event.type == "assistant", let content = event.message?.content {
                    for block in content where block.type == "text" {
                        if let t = block.text, !t.isEmpty { finalOutput += t }
                    }
                }
            }
        } catch {
            finalOutput = "Fehler beim Synthesieren: \(error.localizedDescription)"
        }

        // Init reflection status, then start reflecting
        for s in subtasks {
            reflectionStatus[s.id] = s.agentId.isEmpty ? .skipped : .pending
        }
        phase = .reflecting
        await runAllReflections()
    }

    // MARK: - Logic: Phase 4 — Reflecting

    @MainActor
    private func runAllReflections() async {
        await withTaskGroup(of: Void.self) { group in
            for subtask in subtasks {
                guard !subtask.agentId.isEmpty else { continue }
                group.addTask { await self.runReflection(for: subtask) }
            }
        }
        phase = .done
    }

    @MainActor
    private func runReflection(for subtask: OrchestratorSubtask) async {
        reflectionStatus[subtask.id] = .running

        let dateStr: String = {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            return fmt.string(from: Date())
        }()

        let prompt = """
Du hast gerade diese Aufgabe im Rahmen einer Multi-Agent-Orchestrierung bearbeitet:

**Dein Subtask:** \(subtask.task)

**Dein Output:**
\(subtask.output)

**Gesamtergebnis der Orchestrierung:**
\(finalOutput)

Schreibe eine kurze Reflexion als "Lessons Learned" Eintrag. \
Antworte NUR mit dem folgenden Markdown-Block (kein zusätzlicher Text):

### Lessons Learned — \(dateStr)
**Aufgabe:** \(subtask.task.prefix(80))
- ✅ [Was gut lief]
- ⚠️ [Was verbessert werden könnte]
- 💡 [Erkenntnis für das nächste Mal]
"""

        var reflection = ""
        let stream = state.cliService.send(
            message:   prompt,
            agentName: subtask.agentId,
            model:     "claude-sonnet-4-6"
        )
        do {
            for try await event in stream {
                if event.type == "assistant", let content = event.message?.content {
                    for block in content where block.type == "text" {
                        if let t = block.text, !t.isEmpty { reflection += t }
                    }
                }
            }
        } catch {
            reflectionStatus[subtask.id] = .error(error.localizedDescription)
            return
        }

        // Append to agent's .md file
        guard let agentDef = state.agentService.agents.first(where: { $0.id == subtask.agentId }) else {
            reflectionStatus[subtask.id] = .error("Agent-Datei nicht gefunden")
            return
        }

        let entry = "\n\n---\n\n" + reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        let filePath = agentDef.filePath

        do {
            let existing = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
            let updated  = existing + entry
            try updated.write(toFile: filePath, atomically: true, encoding: .utf8)
            reflectionStatus[subtask.id] = .done
        } catch {
            reflectionStatus[subtask.id] = .error(error.localizedDescription)
        }
    }
}

// MARK: - FlexTriggerRow

private struct FlexTriggerRow: View {
    let triggers: [String]
    let highlight: [String]
    let accentColor: Color
    let theme: AppTheme

    var body: some View {
        // Simple wrapping row using a fixed-width approach
        ZStack(alignment: .topLeading) {
            // Invisible spacer to size the ZStack
            Color.clear.frame(height: 1)

            FlowLayout(spacing: 4) {
                ForEach(triggers, id: \.self) { trigger in
                    let isHit = highlight.contains(where: { $0.lowercased() == trigger.lowercased() })
                    Text(trigger)
                        .font(.system(size: 10, weight: isHit ? .semibold : .regular))
                        .foregroundStyle(isHit ? accentColor : theme.tertiaryText)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isHit ? accentColor.opacity(0.18) : theme.cardBorder.opacity(0.4))
                        )
                }
            }
        }
    }
}
