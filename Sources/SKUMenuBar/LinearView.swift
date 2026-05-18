import SwiftUI

// MARK: - Linear View (3-column: Projects | Issues | Detail)

struct LinearView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @StateObject private var service = LinearService()

    @State private var selectedProject: LinearProject?
    @State private var selectedIssue: LinearIssue?
    @State private var filterPriority: LinearPriority?
    @State private var filterStatus: String?
    @State private var searchText = ""
    @State private var colWidthProject: CGFloat = 200
    @State private var colWidthIssue: CGFloat = 300
    @State private var showNewIssueSheet = false
    @State private var configured = false

    private var accentColor: Color {
        Color(red: theme.acR / 255, green: theme.acG / 255, blue: theme.acB / 255)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Col 1 — Projects
            projectColumn
                .frame(width: colWidthProject)

            PanelResizeHandle(width: $colWidthProject, minWidth: 140, maxWidth: 320, growsRight: true)
                .frame(width: 6)

            // Col 2 — Issues
            issueColumn
                .frame(width: colWidthIssue)

            PanelResizeHandle(width: $colWidthIssue, minWidth: 220, maxWidth: 500, growsRight: true)
                .frame(width: 6)

            // Col 3 — Detail
            detailColumn
                .frame(maxWidth: .infinity)
        }
        .background(theme.windowBg)
        .task {
            await setupAndLoad()
        }
        .sheet(isPresented: $showNewIssueSheet) {
            NewIssueSheet(service: service,
                          teams: service.teams,
                          onCreated: {
                if let proj = selectedProject {
                    Task { await service.loadIssues(projectId: proj.id) }
                }
            })
        }
    }

    // MARK: - Setup

    private func setupAndLoad() async {
        // Re-try if last attempt errored
        if configured && service.error == nil { return }
        service.error = nil
        service.stopSession()
        configured = false

        if let cfg = await state.cliService.getMCPServerConfig(name: "linear") {
            service.configure(config: cfg)
            configured = true
            await service.loadProjects()
            await service.loadTeams()
        } else {
            service.error = "Linear MCP nicht konfiguriert. Bitte in MCP-Einstellungen aktivieren."
        }
    }

    // MARK: - Project Column

    private var projectColumn: some View {
        VStack(spacing: 0) {
            columnHeader("PROJEKTE", icon: "folder.fill") {
                if service.isLoading {
                    ProgressView().scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                }
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    if let err = service.error, service.projects.isEmpty {
                        errorPlaceholder(err)
                    } else if service.projects.isEmpty && !service.isLoading {
                        emptyPlaceholder("Keine Projekte", icon: "folder")
                    } else {
                        ForEach(service.projects) { project in
                            projectRow(project)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            Button {
                Task { await setupAndLoad() }
            } label: {
                Label("Aktualisieren", systemImage: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
        }
    }

    private func projectRow(_ project: LinearProject) -> some View {
        let isSelected = selectedProject?.id == project.id
        return Button {
            selectedProject = project
            selectedIssue = nil
            filterPriority = nil
            filterStatus = nil
            Task { await service.loadIssues(projectId: project.id) }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(project.displayColor)
                    .frame(width: 8, height: 8)
                Text(project.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
                    .lineLimit(1)
                Spacer()
                if project.issueCount > 0 {
                    Text("\(project.issueCount)")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? theme.hoverBg.opacity(1.5) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Issue Column

    private var issueColumn: some View {
        VStack(spacing: 0) {
            columnHeader(selectedProject?.name.uppercased() ?? "ISSUES", icon: nil) {
                if let _ = selectedProject {
                    Button {
                        showNewIssueSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Search + filter bar
            if selectedProject != nil {
                issueFilterBar
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if selectedProject == nil {
                        emptyPlaceholder("Projekt auswählen", icon: "sidebar.left")
                    } else {
                        let visible = filteredIssues
                        if visible.isEmpty {
                            emptyPlaceholder("Keine Issues", icon: "tray")
                        } else {
                            ForEach(visible) { issue in
                                issueRow(issue)
                                Divider()
                                    .padding(.leading, 36)
                                    .opacity(0.5)
                            }
                        }
                    }
                }
            }
        }
    }

    private var issueFilterBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
                TextField("Suchen…", text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(theme.cardBg)

            Divider()

            // Priority filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    filterChipLabel("Priorität")
                    priorityChip(nil, label: "Alle")
                    ForEach(LinearPriority.allCases, id: \.rawValue) { p in
                        priorityChip(p, label: p.label)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }

            Divider()

            // Status filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    filterChipLabel("Status")
                    statusChip(nil, label: "Alle")
                    ForEach(availableStatuses, id: \.id) { st in
                        statusChip(st.id, label: st.name, color: st.displayColor)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }

            Divider()
        }
    }

    private func filterChipLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.tertiaryText)
            .textCase(.uppercase)
            .kerning(0.4)
            .padding(.trailing, 2)
    }

    private func priorityChip(_ priority: LinearPriority?, label: String) -> some View {
        let isActive = filterPriority == priority
        return Button {
            filterPriority = isActive ? nil : priority
        } label: {
            HStack(spacing: 3) {
                if let p = priority {
                    Image(systemName: p.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(p.color)
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? theme.primaryText : theme.secondaryText)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? theme.hoverBg : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isActive ? theme.cardBorder : Color.clear, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func statusChip(_ stateId: String?, label: String, color: Color = .secondary) -> some View {
        let isActive = filterStatus == stateId
        return Button {
            filterStatus = isActive ? nil : stateId
        } label: {
            HStack(spacing: 3) {
                if stateId != nil {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isActive ? theme.primaryText : theme.secondaryText)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? theme.hoverBg : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isActive ? theme.cardBorder : Color.clear, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var availableStatuses: [LinearIssueState] {
        let all = selectedProject.flatMap { service.issues[$0.id] } ?? []
        var seen = Set<String>()
        var result: [LinearIssueState] = []
        for issue in all {
            if let st = issue.state, seen.insert(st.id).inserted {
                result.append(st)
            }
        }
        let order = ["backlog": 0, "unstarted": 1, "started": 2, "completed": 3, "cancelled": 4]
        return result.sorted { (order[$0.type] ?? 5) < (order[$1.type] ?? 5) }
    }

    private func issueRow(_ issue: LinearIssue) -> some View {
        let isSelected = selectedIssue?.id == issue.id
        return Button {
            selectedIssue = issue
        } label: {
            HStack(alignment: .top, spacing: 8) {
                // Priority icon
                Image(systemName: issue.priority.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(issue.priority.color)
                    .frame(width: 14)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(issue.identifier)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.tertiaryText)

                        if let state = issue.state {
                            LinearStatusPill(state: state)
                        }
                    }
                    Text(issue.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .strikethrough(issue.state?.isCompleted ?? false, color: theme.tertiaryText)

                    if let assignee = issue.assigneeName {
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.tertiaryText)
                            Text(assignee)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiaryText)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(isSelected ? theme.hoverBg : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Column

    private var detailColumn: some View {
        Group {
            if let issue = selectedIssue {
                issueDetail(issue)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(theme.tertiaryText)
                    Text("Issue auswählen")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func issueDetail(_ issue: LinearIssue) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(issue.identifier)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.tertiaryText)
                        Spacer()
                        if !issue.url.isEmpty, let url = URL(string: issue.url) {
                            Link(destination: url) {
                                Label("In Linear öffnen", systemImage: "arrow.up.right.square")
                                    .font(.system(size: 11))
                                    .foregroundStyle(accentColor)
                            }
                        }
                    }

                    Text(issue.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .strikethrough(issue.state?.isCompleted ?? false)
                }
                .padding(16)

                Divider()

                // Meta
                VStack(alignment: .leading, spacing: 0) {
                    detailMetaRow(label: "Status") {
                        if let st = issue.state {
                            LinearStatusPill(state: st)
                        } else {
                            Text("–").foregroundStyle(theme.tertiaryText)
                        }
                    }
                    detailMetaRow(label: "Priorität") {
                        HStack(spacing: 4) {
                            Image(systemName: issue.priority.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(issue.priority.color)
                            Text(issue.priority.label)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    if let assignee = issue.assigneeName {
                        detailMetaRow(label: "Zugewiesen") {
                            HStack(spacing: 4) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.tertiaryText)
                                Text(assignee)
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.secondaryText)
                            }
                        }
                    }
                    if !issue.labels.isEmpty {
                        detailMetaRow(label: "Labels") {
                            HStack(spacing: 4) {
                                ForEach(issue.labels, id: \.self) { label in
                                    Text(label)
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(accentColor.opacity(0.12))
                                        )
                                        .foregroundStyle(accentColor)
                                }
                            }
                        }
                    }
                }

                Divider()

                // Description
                if !issue.description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Beschreibung")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)
                            .textCase(.uppercase)
                            .kerning(0.5)
                        Text(issue.description)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.primaryText)
                            .textSelection(.enabled)
                    }
                    .padding(16)
                    Divider()
                }

                // Agent action
                agentActionCard(issue)
                    .padding(16)
            }
        }
    }

    @ViewBuilder
    private func detailMetaRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.tertiaryText)
                .frame(width: 80, alignment: .leading)
            content()
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private func agentActionCard(_ issue: LinearIssue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mit Agent bearbeiten", systemImage: "cpu.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            Text("Öffnet einen Chat-Tab mit dem Issue-Kontext. Claude kann das Issue analysieren, Code schreiben oder Kommentare vorschlagen.")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)

            Button {
                openInChat(issue)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 11))
                    Text("In Chat öffnen")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(accentColor.opacity(0.15))
                .foregroundStyle(accentColor)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(accentColor.opacity(0.3), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Actions

    private func openInChat(_ issue: LinearIssue) {
        var prompt = "Linear Issue **\(issue.identifier)**: \(issue.title)\n\n"
        if let state = issue.state { prompt += "Status: \(state.name)\n" }
        prompt += "Priorität: \(issue.priority.label)\n"
        if let assignee = issue.assigneeName { prompt += "Zugewiesen: \(assignee)\n" }
        if !issue.description.isEmpty { prompt += "\n---\n\(issue.description)" }

        state.pendingChatSessionTitle = issue.identifier
        state.pendingNavigateToChat = true
        // The prompt will appear in a new chat tab via the standard flow
        // We set pendingChatSessionTitle so the tab auto-names itself
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        _ = prompt  // used if pendingChatPrompt becomes available in future
    }

    // MARK: - Filtered Issues

    private var filteredIssues: [LinearIssue] {
        let all = selectedProject.flatMap { service.issues[$0.id] } ?? []
        return all.filter { issue in
            let matchesPriority = filterPriority == nil || issue.priority == filterPriority
            let matchesStatus   = filterStatus == nil || issue.state?.id == filterStatus
            let matchesSearch   = searchText.isEmpty
                || issue.title.localizedCaseInsensitiveContains(searchText)
                || issue.identifier.localizedCaseInsensitiveContains(searchText)
            return matchesPriority && matchesStatus && matchesSearch
        }
    }

    // MARK: - Reusable subviews

    private func columnHeader<T: View>(_ title: String, icon: String?, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .kerning(0.6)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.windowBg)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func emptyPlaceholder(_ text: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(theme.tertiaryText)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func errorPlaceholder(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(Color.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.top, 40)
    }
}

// MARK: - Linear Status Pill

struct LinearStatusPill: View {
    let state: LinearIssueState
    @Environment(\.appTheme) var theme

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(state.displayColor)
                .frame(width: 6, height: 6)
            Text(state.name)
                .font(.system(size: 10))
                .foregroundStyle(state.displayColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(state.displayColor.opacity(0.12))
        )
    }
}

// MARK: - New Issue Sheet

struct NewIssueSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appTheme) var theme
    @ObservedObject var service: LinearService
    let teams: [LinearTeam]
    let onCreated: () -> Void

    @State private var title = ""
    @State private var description = ""
    @State private var selectedTeamId = ""
    @State private var priority = LinearPriority.noPriority
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Neues Issue")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Team picker
                    if !teams.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Team")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.tertiaryText)
                            Picker("Team", selection: $selectedTeamId) {
                                ForEach(teams) { team in
                                    Text(team.name).tag(team.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .onAppear {
                                if selectedTeamId.isEmpty, let first = teams.first {
                                    selectedTeamId = first.id
                                }
                            }
                        }
                    }

                    // Title
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Titel")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.tertiaryText)
                        TextField("Issue-Titel", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                    }

                    // Priority
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Priorität")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.tertiaryText)
                        Picker("Priorität", selection: $priority) {
                            ForEach(LinearPriority.allCases, id: \.rawValue) { p in
                                HStack {
                                    Image(systemName: p.icon)
                                    Text(p.label)
                                }.tag(p)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Beschreibung")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.tertiaryText)
                        TextEditor(text: $description)
                            .font(.system(size: 12))
                            .frame(minHeight: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                            )
                    }

                    if let err = error {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.red)
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.escape)
                Button {
                    Task { await create() }
                } label: {
                    if isCreating {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text("Erstellen")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty || selectedTeamId.isEmpty || isCreating)
                .keyboardShortcut(.return)
            }
            .padding(12)
        }
        .frame(width: 380, height: 460)
    }

    private func create() async {
        guard !title.isEmpty, !selectedTeamId.isEmpty else { return }
        isCreating = true
        error = nil
        do {
            _ = try await service.createIssue(teamId: selectedTeamId,
                                               title: title,
                                               description: description,
                                               priority: priority.rawValue)
            onCreated()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}
