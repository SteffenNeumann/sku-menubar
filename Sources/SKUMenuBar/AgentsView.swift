import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Agent Avatar (SVG-style generated portrait)

private struct AgentAvatarView: View {
    let agent: AgentDefinition
    let size: CGFloat

    private var initials: String {
        let words = agent.name.split(separator: " ").map(String.init)
        if words.count >= 2 {
            let a = words[0].first.map(String.init) ?? ""
            let b = words[1].first.map(String.init) ?? ""
            return (a + b).uppercased()
        }
        return String(agent.name.prefix(2)).uppercased()
    }

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [agent.dotColor.opacity(0.9), agent.dotColor.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Circuit board pattern (deterministic from agent.id)
            CircuitPatternView(seed: abs(agent.id.hashValue))
                .opacity(0.18)

            // Inner glow ring
            Circle()
                .strokeBorder(.white.opacity(0.15), lineWidth: 1.5)
                .frame(width: size * 0.72, height: size * 0.72)

            // CPU icon + initials stack
            VStack(spacing: size * 0.05) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: size * 0.18, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                Text(initials)
                    .font(.system(size: size * 0.3, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Circuit Pattern Canvas

private struct CircuitPatternView: View {
    let seed: Int

    var body: some View {
        Canvas { context, size in
            var s = UInt64(bitPattern: Int64(truncatingIfNeeded: seed))
            func rnd(_ max: CGFloat) -> CGFloat {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(s >> 33) / CGFloat(0x7FFFFFFF) * max
            }

            var path = Path()
            for _ in 0..<10 {
                let x = rnd(size.width)
                let y = rnd(size.height)
                let len = rnd(size.width * 0.45) + size.width * 0.12
                path.move(to: CGPoint(x: x, y: y))
                if rnd(1) > 0.5 {
                    path.addLine(to: CGPoint(x: x + len, y: y))
                    path.addLine(to: CGPoint(x: x + len, y: y + rnd(size.height * 0.3)))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y + len))
                    path.addLine(to: CGPoint(x: x + rnd(size.width * 0.3), y: y + len))
                }
            }
            context.stroke(path, with: .color(.white), lineWidth: 1)

            for _ in 0..<14 {
                let x = rnd(size.width)
                let y = rnd(size.height)
                let r: CGFloat = rnd(2) + 1.5
                context.fill(
                    Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                    with: .color(.white)
                )
            }

            for _ in 0..<4 {
                let x = rnd(size.width - 10) + 4
                let y = rnd(size.height - 10) + 4
                let sz: CGFloat = rnd(6) + 4
                context.stroke(
                    Path(CGRect(x: x, y: y, width: sz, height: sz)),
                    with: .color(.white.opacity(0.6)),
                    lineWidth: 0.8
                )
            }
        }
    }
}

// MARK: - Baseball Card

private struct AgentBaseballCard: View {
    let agent: AgentDefinition
    let isSelected: Bool
    let theme: AppTheme
    let accentColor: Color
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                // Top: Generated avatar (full card width, portrait ratio)
                AgentAvatarView(agent: agent, size: 120)
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .clipped()

                // Thin accent divider
                Rectangle()
                    .fill(agent.dotColor.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)

                // Bottom: Properties
                VStack(alignment: .leading, spacing: 6) {
                    // Name + model badge
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(agent.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        modelBadge(agent.model)
                    }

                    // Description
                    Text(agent.description.isEmpty ? "Kein Beschreibungstext." : agent.description)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)

                    // Bottom row: ID + action icons
                    HStack(alignment: .center, spacing: 0) {
                        Text(agent.id)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(theme.tertiaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 4)

                        HStack(spacing: 4) {
                            cardIconButton(icon: "pencil", color: accentColor, action: onEdit)
                            cardIconButton(icon: "trash", color: .red, action: onDelete)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? theme.accent : theme.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isSelected ? agent.dotColor.opacity(0.5) : theme.cardBorder,
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .shadow(color: .black.opacity(hovered || isSelected ? 0.1 : 0.04), radius: hovered ? 8 : 3, x: 0, y: 2)
        .scaleEffect(hovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovered)
        .onHover { hovered = $0 }
    }

    private func modelBadge(_ model: String) -> some View {
        Text(model.lowercased())
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(accentColor.opacity(0.15), in: Capsule())
    }

    private func cardIconButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main View

struct AgentsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @State private var selectedAgent: AgentDefinition?
    @State private var searchText = ""
    @State private var showEditor = false
    @State private var editorDraft = AgentDraft()
    @State private var editingAgentId: String?
    @State private var editorError: String?
    @State private var detailError: String?
    @State private var pendingDeleteAgent: AgentDefinition?

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var markdownContentType: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }

    var filteredAgents: [AgentDefinition] {
        guard !searchText.isEmpty else { return state.agentService.agents }
        return state.agentService.agents.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            agentsHeader

            Divider().foregroundStyle(theme.cardBorder)

            // Content
            if filteredAgents.isEmpty {
                agentPlaceholder
            } else {
                HStack(spacing: 0) {
                    // Card grid
                    ScrollView {
                        LazyVGrid(
                            columns: selectedAgent != nil
                                ? [GridItem(.flexible(minimum: 180)), GridItem(.flexible(minimum: 180))]
                                : [GridItem(.flexible(minimum: 160)), GridItem(.flexible(minimum: 160)), GridItem(.flexible(minimum: 160))],
                            spacing: 12
                        ) {
                            ForEach(filteredAgents) { agent in
                                AgentBaseballCard(
                                    agent: agent,
                                    isSelected: selectedAgent?.id == agent.id,
                                    theme: theme,
                                    accentColor: accentColor,
                                    onEdit: { startEditingAgent(agent) },
                                    onDelete: { detailError = nil; pendingDeleteAgent = agent },
                                    onSelect: {
                                        withAnimation(.spring(response: 0.3)) {
                                            selectedAgent = selectedAgent?.id == agent.id ? nil : agent
                                        }
                                    }
                                )
                            }
                        }
                        .padding(14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Detail panel (slides in when agent selected)
                    if let agent = selectedAgent {
                        Divider().foregroundStyle(theme.cardBorder)
                        agentDetail(agent)
                            .frame(width: 360)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedAgent?.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if state.agentService.agents.isEmpty {
                await state.agentService.loadAgents()
            }
        }
        .onChange(of: state.agentService.agents) { _, agents in
            syncSelectedAgent(with: agents)
        }
        .sheet(isPresented: $showEditor) {
            AgentEditorSheet(
                draft: $editorDraft,
                title: editingAgentId == nil ? "Neuen Agent anlegen" : "Agent bearbeiten",
                theme: theme,
                errorMessage: editorError,
                previewContent: state.agentService.previewAgentFile(editorDraft),
                onCancel: {
                    editorError = nil
                    showEditor = false
                },
                onCopyPreview: copyEditorPreview,
                onSave: saveAgentDraft
            )
            .frame(minWidth: 680, minHeight: 760)
        }
        .confirmationDialog(
            "Agent loeschen?",
            isPresented: Binding(
                get: { pendingDeleteAgent != nil },
                set: { if !$0 { pendingDeleteAgent = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteAgent
        ) { agent in
            Button("Loeschen", role: .destructive) { deleteAgent(agent) }
            Button("Abbrechen", role: .cancel) { pendingDeleteAgent = nil }
        } message: { agent in
            Text("\"\(agent.name)\" wird aus ~/.claude/agents entfernt.")
        }
    }

    // MARK: - Header

    private var agentsHeader: some View {
        HStack(spacing: 10) {
            Text("Agents")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            Text("\(state.agentService.agents.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(theme.cardBg, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.cardBorder, lineWidth: 0.5))

            // Search
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
                TextField("Agent suchen…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder, lineWidth: 0.5))
            .frame(maxWidth: 220)

            Spacer()

            // Action buttons
            HStack(spacing: 6) {
                headerButton(icon: "square.and.arrow.down", tooltip: "Importieren") { importAgents() }
                headerButton(icon: "arrow.clockwise", tooltip: "Neu laden") {
                    Task { await state.agentService.loadAgents() }
                }

                Button {
                    startCreatingAgent()
                } label: {
                    Label("Neuer Agent", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func headerButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Detail Panel

    private func agentDetail(_ agent: AgentDefinition) -> some View {
        VStack(spacing: 0) {
            // Panel header
            HStack(spacing: 8) {
                AgentAvatarView(agent: agent, size: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                    Text("System Prompt & Speicher")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText)
                }

                Spacer()

                HStack(spacing: 4) {
                    Button { exportAgent(agent) } label: {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.secondaryText)
                    .help("Exportieren")

                    Button { duplicateAgent(agent) } label: {
                        Image(systemName: "plus.square.on.square").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.secondaryText)
                    .help("Duplizieren")

                    Button { startEditingAgent(agent) } label: {
                        Image(systemName: "pencil").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(accentColor)
                    .help("Bearbeiten")

                    Button {
                        withAnimation(.spring(response: 0.3)) { selectedAgent = nil }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.tertiaryText)
                    .help("Schliessen")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider().foregroundStyle(theme.cardBorder)

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Error banner
                    if let detailError, !detailError.isEmpty {
                        Text(detailError)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5))
                    }

                    // Metadata row
                    HStack(spacing: 8) {
                        metaTag("ID", value: agent.id)
                        metaTag("Model", value: agent.model)
                        if let mem = agent.memory { metaTag("Memory", value: mem) }
                        if let col = agent.color { metaTag("Color", value: col) }
                    }
                    .padding(.top, 2)

                    Divider().foregroundStyle(theme.cardBorder)

                    // System prompt
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SYSTEM PROMPT")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)
                            .kerning(0.6)

                        Text(agent.promptBody.isEmpty ? "(Kein Prompt)" : agent.promptBody)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.primaryText.opacity(0.85))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Agent memory
                    if let memory = state.agentService.loadAgentMemory(agentId: agent.id) {
                        Divider().foregroundStyle(theme.cardBorder)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AGENT MEMORY")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.tertiaryText)
                                .kerning(0.6)
                            Text(memory)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.secondaryText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func metaTag(_ key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key.uppercased())
                .font(.system(size: 7, weight: .semibold)).foregroundStyle(theme.tertiaryText).kerning(0.4)
            Text(value)
                .font(.system(size: 10)).foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
    }

    // MARK: - Placeholder

    private var agentPlaceholder: some View {
        VStack(spacing: 14) {
            // Decorative avatar cluster
            HStack(spacing: -16) {
                ForEach(["C", "A", "B"], id: \.self) { letter in
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [theme.tertiaryText.opacity(0.2), theme.tertiaryText.opacity(0.1)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                        Text(letter)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.tertiaryText.opacity(0.5))
                    }
                    .frame(width: 52, height: 52)
                }
            }

            Text("Keine Agents")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.secondaryText)
            Text("Agents werden in\n~/.claude/agents/ gespeichert")
                .font(.system(size: 11)).foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button("Importieren") { importAgents() }
                    .buttonStyle(.bordered)
                Button("Neuen Agent anlegen") { startCreatingAgent() }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func startCreatingAgent() {
        editingAgentId = nil
        editorDraft = AgentDraft()
        editorError = nil
        detailError = nil
        showEditor = true
    }

    private func startEditingAgent(_ agent: AgentDefinition) {
        editingAgentId = agent.id
        editorDraft = AgentDraft(agent: agent)
        editorError = nil
        detailError = nil
        showEditor = true
    }

    private func saveAgentDraft() {
        let draft = editorDraft
        let previousId = editingAgentId

        Task { @MainActor in
            do {
                let saved = try await state.agentService.saveAgent(draft, previousId: previousId)
                selectedAgent = saved
                editingAgentId = saved.id
                editorError = nil
                detailError = nil
                showEditor = false
            } catch {
                editorError = error.localizedDescription
            }
        }
    }

    private func copyEditorPreview() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(state.agentService.previewAgentFile(editorDraft), forType: .string)
    }

    private func duplicateAgent(_ agent: AgentDefinition) {
        Task { @MainActor in
            do {
                let duplicated = try await state.agentService.duplicateAgent(agent)
                selectedAgent = duplicated
                detailError = nil
            } catch {
                detailError = error.localizedDescription
            }
        }
    }

    private func importAgents() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [markdownContentType, .plainText]
        panel.prompt = "Importieren"

        guard panel.runModal() == .OK else { return }

        Task { @MainActor in
            do {
                var lastImported: AgentDefinition?
                for url in panel.urls {
                    lastImported = try await state.agentService.importAgent(from: url)
                }
                if let lastImported {
                    selectedAgent = lastImported
                }
                detailError = nil
            } catch {
                detailError = error.localizedDescription
            }
        }
    }

    private func exportAgent(_ agent: AgentDefinition) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(agent.id).md"
        panel.allowedContentTypes = [markdownContentType]
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try state.agentService.exportAgent(agent, to: url)
            detailError = nil
        } catch {
            detailError = error.localizedDescription
        }
    }

    private func deleteAgent(_ agent: AgentDefinition) {
        Task { @MainActor in
            do {
                try await state.agentService.deleteAgent(agentId: agent.id)
                if selectedAgent?.id == agent.id {
                    selectedAgent = state.agentService.agents.first
                }
                detailError = nil
                pendingDeleteAgent = nil
            } catch {
                detailError = error.localizedDescription
                pendingDeleteAgent = nil
            }
        }
    }

    private func syncSelectedAgent(with agents: [AgentDefinition]) {
        guard let selectedId = selectedAgent?.id else { return }
        selectedAgent = agents.first(where: { $0.id == selectedId })
    }
}

// MARK: - Editor Sheet (unchanged)

private struct AgentEditorSheet: View {
    @Binding var draft: AgentDraft
    let title: String
    let theme: AppTheme
    let errorMessage: String?
    let previewContent: String
    let onCancel: () -> Void
    let onCopyPreview: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text("Bearbeite Frontmatter und System Prompt direkt aus der App.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                Button("Abbrechen", action: onCancel)
                    .buttonStyle(.bordered)

                Button("Speichern", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255))
            }
            .padding(20)

            Divider().foregroundStyle(theme.cardBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5)
                            )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        editorField("Kennung", hint: "Dateiname ohne .md, z. B. code-reviewer") {
                            TextField("code-reviewer", text: $draft.id)
                                .textFieldStyle(.roundedBorder)
                        }

                        editorField("Name", hint: "Anzeigename des Agents") {
                            TextField("Code Reviewer", text: $draft.name)
                                .textFieldStyle(.roundedBorder)
                        }

                        editorField("Beschreibung", hint: "Kurzbeschreibung fuer die Auswahlansicht") {
                            TextField("Wofuer der Agent gedacht ist", text: $draft.description, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...5)
                        }
                    }
                    .padding(16)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                    )

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            editorField("Model", hint: "z. B. sonnet, opus oder haiku") {
                                TextField("sonnet", text: $draft.model)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            editorField("Color", hint: "Optional, z. B. blue oder orange") {
                                TextField("blue", text: $draft.color)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            editorField("Memory", hint: "Optional, z. B. user") {
                                TextField("user", text: $draft.memory)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding(16)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Text("System Prompt")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                        Text("Der Inhalt unterhalb des Frontmatters wird direkt in die Agent-Datei geschrieben.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText)

                        TextEditor(text: $draft.promptBody)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.primaryText)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 320, alignment: .topLeading)
                            .background(theme.windowBg.opacity(theme.isLight ? 0.35 : 0.18), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                            )
                    }
                    .padding(16)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rohdatei-Vorschau")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)
                                Text("So wird die Agent-Datei inklusive Frontmatter gespeichert.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.secondaryText)
                            }

                            Spacer()

                            Button("Kopieren", action: onCopyPreview)
                                .buttonStyle(.bordered)
                        }

                        ScrollView {
                            Text(previewContent)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.primaryText.opacity(0.9))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(minHeight: 220)
                        .background(theme.windowBg.opacity(theme.isLight ? 0.35 : 0.18), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                        )
                    }
                    .padding(16)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                    )
                }
                .padding(20)
            }
        }
        .background(theme.windowBg)
    }

    private func editorField<Content: View>(_ title: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .kerning(0.5)
            content()
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
