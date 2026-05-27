import SwiftUI

// MARK: - Linear Logo Shape (4 stacked bars — official Linear logo)

struct LinearLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let barH = h * 0.13
        let gap = h * 0.09
        let r = barH * 0.35
        let totalH = 4 * barH + 3 * gap
        let startY = (h - totalH) / 2

        let widths: [CGFloat] = [0.45, 0.65, 0.85, 1.0]
        for (i, frac) in widths.enumerated() {
            let y = startY + CGFloat(i) * (barH + gap)
            let bw = w * frac
            let x = (w - bw) / 2
            p.addRoundedRect(in: CGRect(x: x, y: y, width: bw, height: barH),
                             cornerSize: CGSize(width: r, height: r))
        }
        return p
    }
}

// MARK: - Linear Status Icon (state-specific Canvas-drawn icons)

struct LinearStateIcon: View {
    let type: String
    let color: Color
    var size: CGFloat = 14

    var body: some View {
        Canvas { ctx, sz in
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let r = min(sz.width, sz.height) / 2 - 1
            let lw: CGFloat = 1.6

            switch type {
            case "backlog":
                // Dashed circle
                let dashCircle = Path { p in
                    p.addArc(center: c, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                }
                ctx.stroke(dashCircle, with: .color(color), style: StrokeStyle(lineWidth: lw, dash: [3.5, 2.5]))

            case "unstarted":
                // Empty circle
                let circle = Path { p in
                    p.addArc(center: c, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                }
                ctx.stroke(circle, with: .color(color), lineWidth: lw)

            case "started":
                // Circle with right half fill
                let bg = Path { p in
                    p.addArc(center: c, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                }
                ctx.stroke(bg, with: .color(color), lineWidth: lw)
                let half = Path { p in
                    p.move(to: CGPoint(x: c.x, y: c.y - r + 0.5))
                    p.addArc(center: c, radius: r - 0.5, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
                    p.closeSubpath()
                }
                ctx.fill(half, with: .color(color))

            case "completed":
                // Filled circle with checkmark
                let filled = Path { p in
                    p.addArc(center: c, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                }
                ctx.fill(filled, with: .color(color))
                var check = Path()
                check.move(to: CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.03))
                check.addLine(to: CGPoint(x: c.x - r * 0.05, y: c.y + r * 0.35))
                check.addLine(to: CGPoint(x: c.x + r * 0.40, y: c.y - r * 0.30))
                ctx.stroke(check, with: .color(.white), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

            case "cancelled":
                // Circle with X
                let circle = Path { p in
                    p.addArc(center: c, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                }
                ctx.stroke(circle, with: .color(color), lineWidth: lw)
                let cross = r * 0.35
                var x1 = Path()
                x1.move(to: CGPoint(x: c.x - cross, y: c.y - cross))
                x1.addLine(to: CGPoint(x: c.x + cross, y: c.y + cross))
                var x2 = Path()
                x2.move(to: CGPoint(x: c.x + cross, y: c.y - cross))
                x2.addLine(to: CGPoint(x: c.x - cross, y: c.y + cross))
                ctx.stroke(x1, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                ctx.stroke(x2, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

            default:
                let circle = Path { p in
                    p.addArc(center: c, radius: r, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                }
                ctx.stroke(circle, with: .color(color), lineWidth: lw)
            }
        }
        .frame(width: size, height: size)
    }
}

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
    @State private var colWidthProject: CGFloat = 220
    @State private var colWidthIssue: CGFloat = 340
    @State private var showNewIssueSheet = false
    @State private var showNewProjectSheet = false
    @State private var configured = false
    @State private var hoveredIssueId: String?
    @State private var showStatusPopover = false
    @State private var showPriorityPopover = false
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var newCommentText = ""
    @State private var isLoadingComments = false
    @State private var collapsedStatusGroups: Set<String> = []
    @State private var copiedIdentifier = false
    @State private var issueToDelete: LinearIssue? = nil
    @State private var showDeleteConfirmation = false

    private var accentColor: Color {
        Color(red: theme.acR / 255, green: theme.acG / 255, blue: theme.acB / 255)
    }

    private let linearPurple = Color(red: 0.37, green: 0.42, blue: 0.82)

    var body: some View {
        HStack(spacing: 0) {
            // Col 1 — Projects
            projectColumn
                .frame(width: colWidthProject)

            PanelResizeHandle(width: $colWidthProject, minWidth: 140, maxWidth: 320, growsRight: true, drawsLine: false)
                .frame(width: 1)

            // Col 2 — Issues
            issueColumn
                .frame(width: colWidthIssue)

            PanelResizeHandle(width: $colWidthIssue, minWidth: 220, maxWidth: 500, growsRight: true, drawsLine: false)
                .frame(width: 1)

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
        .sheet(isPresented: $showNewProjectSheet) {
            NewProjectSheet(service: service, onCreated: {
                Task { await setupAndLoad() }
            })
        }
        .confirmationDialog(
            "Issue \(issueToDelete?.identifier ?? "") löschen?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                if let issue = issueToDelete { Task { await performDeleteIssue(issue) } }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("\"\(issueToDelete?.title ?? "")\" wird unwiderruflich gelöscht.")
        }
    }

    // MARK: - Setup

    private func setupAndLoad() async {
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
            // Header with Linear logo
            HStack(spacing: 7) {
                LinearLogoShape()
                    .fill(linearPurple)
                    .frame(width: 12, height: 12)
                Text("Projects")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Button {
                    showNewProjectSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(theme.primaryText.opacity(0.05)))
                }
                .buttonStyle(.plain)
                if service.isLoading {
                    ProgressView().scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    if let err = service.error, service.projects.isEmpty {
                        errorPlaceholder(err)
                    } else if service.projects.isEmpty && !service.isLoading {
                        emptyPlaceholder("Keine Projekte", icon: "folder")
                    } else {
                        ForEach(groupedProjects, id: \.header) { group in
                            Text(group.header.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.tertiaryText)
                                .kerning(0.3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.top, group.header == groupedProjects.first?.header ? 4 : 12)
                                .padding(.bottom, 2)

                            ForEach(group.projects) { project in
                                projectRow(project)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)

            // Refresh button at bottom
            HStack {
                Button {
                    Task { await setupAndLoad() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Aktualisieren")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(alignment: .top) {
                Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5)
            }
        }
    }

    private func projectRow(_ project: LinearProject) -> some View {
        let isSelected = selectedProject?.id == project.id
        let issues = service.issues[project.id] ?? []
        let completedCount = issues.filter { $0.state?.type == "completed" }.count
        let inProgressCount = issues.filter { $0.state?.type == "started" }.count
        let total = max(issues.count, project.issueCount)
        let completedFrac = total > 0 ? CGFloat(completedCount) / CGFloat(total) : 0
        let inProgressFrac = total > 0 ? CGFloat(inProgressCount) / CGFloat(total) : 0

        return Button {
            selectedProject = project
            selectedIssue = nil
            filterPriority = nil
            filterStatus = nil
            Task { await service.loadIssues(projectId: project.id) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(project.displayColor)
                        .frame(width: 9, height: 9)
                    Text(project.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
                        .lineLimit(1)
                    Spacer()
                    if total > 0 {
                        Text("\(total)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }

                // Progress bar
                if total > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.primaryText.opacity(0.06))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.95, green: 0.65, blue: 0.15).opacity(0.7))
                                .frame(width: geo.size.width * (completedFrac + inProgressFrac))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.12, green: 0.62, blue: 0.35))
                                .frame(width: geo.size.width * completedFrac)
                        }
                    }
                    .frame(height: 3)
                    .padding(.leading, 17)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? linearPurple.opacity(0.12) : Color.clear)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(linearPurple)
                        .frame(width: 3)
                        .padding(.vertical, 4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Issue Column

    private var issueColumn: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Text(selectedProject?.name ?? "Issues")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Spacer()
                if let _ = selectedProject {
                    Button {
                        showNewIssueSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 5).fill(theme.primaryText.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5)
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
                        let grouped = groupedFilteredIssues
                        if grouped.isEmpty {
                            emptyPlaceholder("Keine Issues", icon: "tray")
                        } else {
                            ForEach(grouped, id: \.state.id) { group in
                                // Header inline (kein Section/pinnedViews — LazyVStack+Section+pinnedViews
                                // cached die Section-Struktur und updated sie nicht korrekt beim Gruppen-Wechsel)
                                statusGroupHeader(group.state, count: group.issues.count)
                                if !collapsedStatusGroups.contains(group.state.id) {
                                    ForEach(group.issues) { issue in
                                        issueRow(issue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var issueFilterBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Search field
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                    TextField("Suchen…", text: $searchText)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Priority dropdown
                Menu {
                    Button {
                        filterPriority = nil
                    } label: {
                        HStack {
                            Text("Alle")
                            if filterPriority == nil { Image(systemName: "checkmark") }
                        }
                    }
                    Divider()
                    ForEach(LinearPriority.allCases, id: \.rawValue) { p in
                        Button {
                            filterPriority = (filterPriority == p) ? nil : p
                        } label: {
                            HStack {
                                Image(systemName: p.icon)
                                Text(p.label)
                                if filterPriority == p { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        if let p = filterPriority {
                            Image(systemName: p.icon)
                                .font(.system(size: 9))
                                .foregroundStyle(p.color)
                            Text(p.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                        } else {
                            Image(systemName: "flag")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.tertiaryText)
                            Text("Priorität")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(filterPriority != nil ? theme.primaryText.opacity(0.08) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(theme.cardBorder.opacity(0.6), lineWidth: 0.5)
                            )
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Status dropdown
                Menu {
                    Button {
                        filterStatus = nil
                    } label: {
                        HStack {
                            Text("Alle")
                            if filterStatus == nil { Image(systemName: "checkmark") }
                        }
                    }
                    Divider()
                    ForEach(availableStatuses, id: \.id) { st in
                        Button {
                            filterStatus = (filterStatus == st.id) ? nil : st.id
                        } label: {
                            HStack {
                                Text(st.name)
                                if filterStatus == st.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        if let activeStatus = availableStatuses.first(where: { $0.id == filterStatus }) {
                            LinearStateIcon(type: activeStatus.type, color: activeStatus.displayColor, size: 10)
                            Text(activeStatus.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                        } else {
                            Image(systemName: "circle.dotted")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.tertiaryText)
                            Text("Status")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(filterStatus != nil ? theme.primaryText.opacity(0.08) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(theme.cardBorder.opacity(0.6), lineWidth: 0.5)
                            )
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Rectangle().fill(theme.cardBorder.opacity(0.3)).frame(height: 0.5)
        }
        .background(theme.windowBg)
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func issueRow(_ issue: LinearIssue) -> some View {
        let isSelected = selectedIssue?.id == issue.id
        let isHovered = hoveredIssueId == issue.id

        let isSubtask = issue.parentId != nil

        return Button {
            let target = issue
            showStatusPopover = false
            showPriorityPopover = false
            DispatchQueue.main.async { selectedIssue = target }
        } label: {
            HStack(alignment: .center, spacing: 0) {
                // Subtask indent + vertical bar
                if isSubtask {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(linearPurple.opacity(0.35))
                        .frame(width: 2)
                        .padding(.trailing, 8)
                }

                HStack(alignment: .center, spacing: 10) {
                // Status icon as leading element
                if let st = issue.state {
                    LinearStateIcon(type: st.type, color: st.displayColor, size: isSubtask ? 14 : 16)
                } else {
                    LinearStateIcon(type: "unstarted", color: theme.tertiaryText, size: isSubtask ? 14 : 16)
                }

                VStack(alignment: .leading, spacing: 3) {
                    // Title first — primary element
                    Text(issue.title)
                        .font(.system(size: isSubtask ? 12 : 13, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .strikethrough(issue.state?.isCompleted ?? false, color: theme.tertiaryText)

                    // Identifier + Priority + Parent badge — secondary
                    HStack(spacing: 5) {
                        Text(issue.identifier)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.tertiaryText)
                        Image(systemName: issue.priority.icon)
                            .font(.system(size: 10))
                            .foregroundStyle(issue.priority.color)
                        if let parentIdent = issue.parentIdentifier {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.turn.right.up")
                                    .font(.system(size: 8))
                                Text(parentIdent)
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .foregroundStyle(linearPurple.opacity(0.7))
                        }
                        if issue.subIssueCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "list.bullet.indent")
                                    .font(.system(size: 9))
                                Text("\(issue.subIssueCount)")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(theme.tertiaryText)
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    // Avatar initials
                    if let assignee = issue.assigneeName {
                        Text(assignee.components(separatedBy: " ").compactMap(\.first).prefix(2).map(String.init).joined())
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(theme.primaryText.opacity(0.07)))
                    }
                    // Updated-at timestamp
                    if let updated = issue.updatedAt {
                        Text(Self.relativeFormatter.localizedString(for: updated, relativeTo: Date()))
                            .font(.system(size: 9))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
                } // inner HStack
            } // outer HStack
            .padding(.leading, isSubtask ? 6 : 12)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .background(
                isSelected ? linearPurple.opacity(0.10)
                : isHovered ? theme.primaryText.opacity(0.03) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredIssueId = $0 ? issue.id : nil }
        .contextMenu {
            Button(role: .destructive) {
                issueToDelete = issue
                showDeleteConfirmation = true
            } label: {
                Label("Issue löschen", systemImage: "trash")
            }
        }
    }

    // MARK: - Detail Column

    private var detailColumn: some View {
        Group {
            if let issue = selectedIssue {
                issueDetail(issue)
            } else {
                VStack(spacing: 12) {
                    LinearLogoShape()
                        .fill(theme.tertiaryText.opacity(0.3))
                        .frame(width: 40, height: 40)
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
                // Header with identifier badge + actions
                HStack(spacing: 6) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(issue.identifier, forType: .string)
                        copiedIdentifier = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            copiedIdentifier = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(copiedIdentifier ? "Kopiert!" : issue.identifier)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(copiedIdentifier ? .green : theme.tertiaryText)
                            if !copiedIdentifier {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                                    .foregroundStyle(theme.tertiaryText.opacity(0.5))
                            }
                        }
                        .animation(.easeInOut(duration: 0.2), value: copiedIdentifier)
                    }
                    .buttonStyle(.plain)
                    .help("Identifier kopieren")
                    Spacer()

                    // Agent button as colored pill
                    Button {
                        openInChat(issue)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu.fill")
                                .font(.system(size: 11))
                            Text("Agent")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(linearPurple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(linearPurple.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .help("Mit Agent bearbeiten")

                    if !issue.url.isEmpty, let url = URL(string: issue.url) {
                        Link(destination: url) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.secondaryText)
                                .frame(width: 28, height: 28)
                                .background(RoundedRectangle(cornerRadius: 6).fill(theme.primaryText.opacity(0.05)))
                        }
                        .help("In Linear öffnen")
                    }

                    Button {
                        issueToDelete = issue
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.statusRed.opacity(0.8))
                            .frame(width: 28, height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(theme.primaryText.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help("Issue löschen")
                }
                .padding(16)

                // Parent issue breadcrumb
                if let parentIdent = issue.parentIdentifier, let parentTitle = issue.parentTitle {
                    Button {
                        if let parentId = issue.parentId,
                           let projId = selectedProject?.id,
                           let parent = service.issues[projId]?.first(where: { $0.id == parentId }) {
                            let target = parent
                            showStatusPopover = false
                            showPriorityPopover = false
                            DispatchQueue.main.async { selectedIssue = target }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.right.up")
                                .font(.system(size: 9))
                            Text(parentIdent)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            Text(parentTitle)
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .foregroundStyle(linearPurple)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                    }
                    .buttonStyle(.plain)
                    .help("Zum übergeordneten Issue")
                }

                // Title — prominent, double-click to edit
                if isEditingTitle {
                    TextField("Titel", text: $editedTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .textFieldStyle(.plain)
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .onSubmit {
                            commitTitleEdit(issueId: issue.id)
                        }
                        .onExitCommand {
                            isEditingTitle = false
                        }
                } else {
                    Text(issue.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .strikethrough(issue.state?.isCompleted ?? false)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                        .onTapGesture(count: 2) {
                            editedTitle = issue.title
                            isEditingTitle = true
                        }
                }

                // Properties grid with subtle dividers
                propertiesSection(issue)

                Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5)
                    .padding(.vertical, 2)

                // Description — rendered as Markdown (no label, like Linear)
                if !issue.description.isEmpty {
                    MarkdownTextView(text: issue.description)
                        .padding(16)
                }

                // Sub-Issues section (inline to avoid ViewBuilder issues)
                let subs = subIssuesOf(issue)
                if !subs.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Rectangle().fill(theme.cardBorder.opacity(0.4)).frame(height: 0.5)
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet.indent")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.tertiaryText)
                            Text("Sub-Issues")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.tertiaryText)
                            Text("\(subs.count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(theme.tertiaryText.opacity(0.7))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(theme.primaryText.opacity(0.06)))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 6)

                        ForEach(subs) { sub in
                            Button {
                                let target = sub
                                showStatusPopover = false
                                showPriorityPopover = false
                                DispatchQueue.main.async { selectedIssue = target }
                            } label: {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(linearPurple.opacity(0.35))
                                        .frame(width: 2, height: 24)
                                    if let st = sub.state {
                                        LinearStateIcon(type: st.type, color: st.displayColor, size: 14)
                                    } else {
                                        LinearStateIcon(type: "unstarted", color: theme.tertiaryText, size: 14)
                                    }
                                    Text(sub.identifier)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(theme.tertiaryText)
                                    Text(sub.title)
                                        .font(.system(size: 12))
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(1)
                                        .strikethrough(sub.state?.isCompleted ?? false, color: theme.tertiaryText)
                                    Spacer(minLength: 0)
                                    Image(systemName: sub.priority.icon)
                                        .font(.system(size: 9))
                                        .foregroundStyle(sub.priority.color)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 8)
                }

                Rectangle().fill(theme.cardBorder.opacity(0.4)).frame(height: 0.5)

                // Activity / Comments
                commentsSection(issue: issue)
            }
        }
    }

    // MARK: - Sub-Issues Section

    private func subIssuesOf(_ issue: LinearIssue) -> [LinearIssue] {
        guard issue.subIssueCount > 0, let projId = selectedProject?.id else { return [] }
        return (service.issues[projId] ?? []).filter { $0.parentId == issue.id }
    }


    // MARK: - Comments Section

    @ViewBuilder
    private func commentsSection(issue: LinearIssue) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aktivität")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)

            if let comments = service.comments[issue.id], !comments.isEmpty {
                ForEach(comments) { comment in
                    commentRow(comment)
                }
            } else if isLoadingComments {
                HStack { Spacer(); ProgressView().scaleEffect(0.7); Spacer() }
                    .padding(.vertical, 8)
            } else if service.comments[issue.id] != nil {
                Text("Keine Kommentare")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }

            // New comment input
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Kommentar schreiben…", text: $newCommentText, axis: .vertical)
                    .font(.system(size: 12))
                    .lineLimit(1...5)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                    )

                Button {
                    guard !newCommentText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    let text = newCommentText
                    newCommentText = ""
                    Task {
                        try? await service.addComment(issueId: issue.id, body: text)
                        await service.loadComments(issueId: issue.id, identifier: issue.identifier)
                    }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? theme.tertiaryText : linearPurple)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(theme.primaryText.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .task(id: issue.id) {
            isLoadingComments = true
            await service.loadComments(issueId: issue.id, identifier: issue.identifier)
            isLoadingComments = false
        }
    }

    private func commentRow(_ comment: LinearComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(comment.authorName.components(separatedBy: " ").compactMap(\.first).prefix(2).map(String.init).joined())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(theme.primaryText.opacity(0.08)))
                Text(comment.authorName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                if let date = comment.createdAt {
                    Text(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer()
            }
            MarkdownTextView(text: comment.body)
                .padding(.leading, 26)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Properties Section (Linear-style grid)

    private func propertiesSection(_ issue: LinearIssue) -> some View {
        VStack(spacing: 0) {
            // Status — clickable with popover
            propertyRow(label: "Status") {
                if let st = issue.state {
                    Button {
                        showStatusPopover = true
                    } label: {
                        HStack(spacing: 5) {
                            LinearStateIcon(type: st.type, color: st.displayColor, size: 14)
                            Text(st.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.primaryText)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(theme.primaryText.opacity(0.04)))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showStatusPopover, arrowEdge: .bottom) {
                        statusPopoverContent(issue: issue)
                    }
                }
            }

            // Priority — clickable with popover
            propertyRow(label: "Priorität") {
                Button {
                    showPriorityPopover = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: issue.priority.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(issue.priority.color)
                        Text(issue.priority.label)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.primaryText)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(theme.primaryText.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPriorityPopover, arrowEdge: .bottom) {
                    priorityPopoverContent(issue: issue)
                }
            }
            if let assignee = issue.assigneeName {
                propertyRow(label: "Zugewiesen") {
                    HStack(spacing: 6) {
                        Text(assignee.components(separatedBy: " ").compactMap(\.first).prefix(2).map(String.init).joined())
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(theme.primaryText.opacity(0.08)))
                        Text(assignee)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.primaryText)
                    }
                }
            }
            if !issue.labels.isEmpty {
                propertyRow(label: "Labels") {
                    HStack(spacing: 4) {
                        ForEach(issue.labels, id: \.self) { label in
                            Text(label)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(linearPurple.opacity(0.10))
                                )
                                .foregroundStyle(linearPurple)
                        }
                    }
                }
            }
            if let dueDate = issue.dueDate {
                propertyRow(label: "Fällig") {
                    HStack(spacing: 5) {
                        Image(systemName: dueDate < Date() ? "exclamationmark.circle.fill" : "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(dueDate < Date() ? .red : theme.secondaryText)
                        Text(dueDate, style: .date)
                            .font(.system(size: 12))
                            .foregroundStyle(dueDate < Date() ? .red : theme.primaryText)
                    }
                }
            }
            if let cycleName = issue.cycleName {
                propertyRow(label: "Cycle") {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText)
                        Text(cycleName)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.primaryText)
                    }
                }
            }
            if issue.subIssueCount > 0 {
                propertyRow(label: "Sub-Issues") {
                    HStack(spacing: 5) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText)
                        Text("\(issue.subIssueCount)")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.primaryText)
                    }
                }
            }
            if let created = issue.createdAt {
                propertyRow(label: "Erstellt") {
                    Text(created, style: .date)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func propertyRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText)
                .frame(width: 72, alignment: .leading)
            content()
            Spacer()
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.cardBorder.opacity(0.2)).frame(height: 0.5)
        }
    }

    // MARK: - Popovers

    @ViewBuilder
    private func statusPopoverContent(issue: LinearIssue) -> some View {
        let team = service.teams.first { $0.id == issue.teamId }
        let states = team?.states ?? []
        let order = ["backlog": 0, "unstarted": 1, "started": 2, "completed": 3, "cancelled": 4]
        let ordered = states.sorted { (order[$0.type] ?? 5) < (order[$1.type] ?? 5) }

        VStack(spacing: 2) {
            ForEach(ordered) { st in
                Button {
                    showStatusPopover = false
                    applyLocalStateChange(issueId: issue.id, newState: st)
                    Task {
                        try? await service.updateIssueStatus(issueId: issue.id, stateId: st.id)
                        // Kein refreshCurrentIssue — optimistischer State bleibt erhalten
                    }
                } label: {
                    HStack(spacing: 6) {
                        LinearStateIcon(type: st.type, color: st.displayColor, size: 14)
                        Text(st.name)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        if issue.state?.id == st.id {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(linearPurple)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(issue.state?.id == st.id ? linearPurple.opacity(0.10) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 200)
        .background(theme.windowBg)
        .preferredColorScheme(theme.isLight ? .light : .dark)
    }

    @ViewBuilder
    private func priorityPopoverContent(issue: LinearIssue) -> some View {
        VStack(spacing: 2) {
            ForEach(LinearPriority.allCases, id: \.rawValue) { p in
                Button {
                    showPriorityPopover = false
                    applyLocalPriorityChange(issueId: issue.id, newPriority: p)
                    Task {
                        try? await service.updateIssuePriority(issueId: issue.id, priority: p.rawValue)
                        // Kein refreshCurrentIssue — optimistischer State bleibt erhalten
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: p.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(p.color)
                            .frame(width: 16)
                        Text(p.label)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        if issue.priority == p {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(linearPurple)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(issue.priority == p ? linearPurple.opacity(0.10) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 180)
        .background(theme.windowBg)
        .preferredColorScheme(theme.isLight ? .light : .dark)
    }

    // MARK: - Inline Edit Helpers

    private func commitTitleEdit(issueId: String) {
        let newTitle = editedTitle.trimmingCharacters(in: .whitespaces)
        guard !newTitle.isEmpty else {
            isEditingTitle = false
            return
        }
        Task {
            try? await service.updateIssueTitle(issueId: issueId, title: newTitle)
            await refreshCurrentIssue()
            isEditingTitle = false
        }
    }

    /// Optimistic local update: Status sofort in UI aktualisieren
    private func applyLocalStateChange(issueId: String, newState: LinearIssueState) {
        guard let projId = selectedProject?.id,
              let idx = service.issues[projId]?.firstIndex(where: { $0.id == issueId }) else { return }
        let old = service.issues[projId]![idx]
        let updated = LinearIssue(id: old.id, identifier: old.identifier, title: old.title,
                                  description: old.description, priority: old.priority,
                                  state: newState, teamId: old.teamId, projectId: old.projectId,
                                  assigneeName: old.assigneeName, labels: old.labels,
                                  createdAt: old.createdAt, updatedAt: old.updatedAt,
                                  dueDate: old.dueDate, cycleName: old.cycleName, url: old.url,
                                  parentId: old.parentId, parentIdentifier: old.parentIdentifier,
                                  parentTitle: old.parentTitle, subIssueCount: old.subIssueCount)
        // Copy → mutate → reassign so @Published setter fires objectWillChange correctly
        var snapshot = service.issues
        snapshot[projId]![idx] = updated
        service.issues = snapshot
        if selectedIssue?.id == issueId { selectedIssue = updated }
    }

    /// Optimistic local update: Priority sofort in UI aktualisieren
    private func applyLocalPriorityChange(issueId: String, newPriority: LinearPriority) {
        guard let projId = selectedProject?.id,
              let idx = service.issues[projId]?.firstIndex(where: { $0.id == issueId }) else { return }
        let old = service.issues[projId]![idx]
        let updated = LinearIssue(id: old.id, identifier: old.identifier, title: old.title,
                                  description: old.description, priority: newPriority,
                                  state: old.state, teamId: old.teamId, projectId: old.projectId,
                                  assigneeName: old.assigneeName, labels: old.labels,
                                  createdAt: old.createdAt, updatedAt: old.updatedAt,
                                  dueDate: old.dueDate, cycleName: old.cycleName, url: old.url,
                                  parentId: old.parentId, parentIdentifier: old.parentIdentifier,
                                  parentTitle: old.parentTitle, subIssueCount: old.subIssueCount)
        // Copy → mutate → reassign so @Published setter fires objectWillChange correctly
        var snapshot = service.issues
        snapshot[projId]![idx] = updated
        service.issues = snapshot
        if selectedIssue?.id == issueId { selectedIssue = updated }
    }

    private func refreshCurrentIssue() async {
        if let projId = selectedProject?.id {
            await service.loadIssues(projectId: projId)
            if let currentId = selectedIssue?.id {
                selectedIssue = service.issues[projId]?.first { $0.id == currentId }
            }
        }
    }

    // MARK: - Actions

    private func openInChat(_ issue: LinearIssue) {
        var prompt = ""
        if let project = selectedProject {
            prompt += "Linear Projekt: **\(project.name)**\n"
        }
        prompt += "Issue **\(issue.identifier)**: \(issue.title)\n\n"
        if let st = issue.state { prompt += "Status: \(st.name)\n" }
        prompt += "Priorität: \(issue.priority.label)\n"
        if let assignee = issue.assigneeName { prompt += "Zugewiesen: \(assignee)\n" }
        if !issue.description.isEmpty { prompt += "\n---\n\(issue.description)" }

        state.pendingChatMessage = prompt
        state.pendingChatSessionTitle = issue.identifier

        if let linearProjectName = selectedProject?.name.lowercased() {
            let match = state.historyService.projects.first {
                let local = $0.displayName.lowercased()
                return local.contains(linearProjectName) || linearProjectName.contains(local)
            }
            if let matched = match {
                state.pendingChatSetDirectory = matched.path
            }
        }

        state.pendingNavigateToChat = true
    }

    private func performDeleteIssue(_ issue: LinearIssue) async {
        do {
            try await service.deleteIssue(identifier: issue.identifier)
            // Optimistisch aus lokaler Liste entfernen
            if let projId = selectedProject?.id {
                var snapshot = service.issues
                snapshot[projId]?.removeAll { $0.id == issue.id }
                service.issues = snapshot
            }
            if selectedIssue?.id == issue.id {
                DispatchQueue.main.async { self.selectedIssue = nil }
            }
        } catch { /* silently ignore — issue may already be deleted */ }
    }

    // MARK: - Grouped Projects

    private var groupedProjects: [(header: String, projects: [LinearProject])] {
        let stateLabels: [(key: String, label: String)] = [
            ("inProgress", "In Progress"),
            ("planned", "Planned"),
            ("paused", "Paused"),
            ("completed", "Completed"),
            ("cancelled", "Cancelled")
        ]

        var groups: [(String, [LinearProject])] = []
        var usedIds = Set<String>()

        for (key, label) in stateLabels {
            let matching = service.projects.filter { $0.state == key && !usedIds.contains($0.id) }
            if !matching.isEmpty {
                groups.append((label, matching))
                matching.forEach { usedIds.insert($0.id) }
            }
        }

        let ungrouped = service.projects.filter { !usedIds.contains($0.id) }
        if !ungrouped.isEmpty {
            groups.append(("Sonstige", ungrouped))
        }

        return groups
    }

    // MARK: - Filtered & Grouped Issues

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

    private var groupedFilteredIssues: [(state: LinearIssueState, issues: [LinearIssue])] {
        let issues = filteredIssues
        let order = ["backlog": 0, "unstarted": 1, "started": 2, "completed": 3, "cancelled": 4]

        var groups: [String: (state: LinearIssueState, issues: [LinearIssue])] = [:]
        for issue in issues {
            let key = issue.state?.type ?? "unstarted"
            let st = issue.state ?? LinearIssueState(id: "unknown", name: "Unknown", type: "unstarted", color: "#aaa")
            if groups[key] != nil {
                groups[key]!.issues.append(issue)
            } else {
                groups[key] = (state: st, issues: [issue])
            }
        }
        return groups.values.sorted { (order[$0.state.type] ?? 5) < (order[$1.state.type] ?? 5) }
    }

    private func statusGroupHeader(_ st: LinearIssueState, count: Int) -> some View {
        let isCollapsed = collapsedStatusGroups.contains(st.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isCollapsed {
                    collapsedStatusGroups.remove(st.id)
                } else {
                    collapsedStatusGroups.insert(st.id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(width: 12)
                LinearStateIcon(type: st.type, color: st.displayColor, size: 12)
                Text(st.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Text("\(count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.tertiaryText)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.windowBg)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reusable subviews

    private func emptyPlaceholder(_ text: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(theme.tertiaryText.opacity(0.5))
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
                .foregroundStyle(theme.statusOrange)
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
        HStack(spacing: 4) {
            LinearStateIcon(type: state.type, color: state.displayColor, size: 10)
            Text(state.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(state.displayColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(state.displayColor.opacity(0.10))
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
    @State private var projectSelection = "none"
    @State private var newProjectName = ""
    @State private var isCreating = false
    @State private var error: String?

    private let linearPurple = Color(red: 0.37, green: 0.42, blue: 0.82)

    private var availableProjects: [LinearProject] {
        guard !selectedTeamId.isEmpty else { return service.projects }
        return service.projects.filter { $0.teamIds.contains(selectedTeamId) }
    }

    private var selectedTeamStates: [LinearIssueState] {
        let order = ["backlog": 0, "unstarted": 1, "started": 2, "completed": 3, "cancelled": 4]
        let states = teams.first { $0.id == selectedTeamId }?.states ?? []
        return states.sorted { (order[$0.type] ?? 5) < (order[$1.type] ?? 5) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────
            HStack(spacing: 8) {
                LinearLogoShape()
                    .fill(linearPurple)
                    .frame(width: 13, height: 13)
                Text("Neues Issue")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                if let err = error {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.statusRed)
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(theme.primaryText.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5)

            // ── 2-column body ───────────────────────────────────
            HStack(spacing: 0) {

                // Left: Title + Description
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Issue-Titel…", text: $title)
                        .font(.system(size: 15, weight: .semibold))
                        .textFieldStyle(.plain)
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    Rectangle().fill(theme.cardBorder.opacity(0.25)).frame(height: 0.5)
                        .padding(.horizontal, 18)

                    ZStack(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("Beschreibung hinzufügen…")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.tertiaryText.opacity(0.7))
                                .padding(.top, 10)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $description)
                            .font(.system(size: 12))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Vertical divider
                Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(width: 0.5)

                // Right: Properties
                VStack(spacing: 0) {
                    // Team
                    propRow(label: "Team") {
                        Picker("", selection: $selectedTeamId) {
                            ForEach(teams) { t in Text(t.name).tag(t.id) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .onAppear {
                            if selectedTeamId.isEmpty, let first = teams.first {
                                selectedTeamId = first.id
                            }
                        }
                    }
                    propDivider()

                    // Projekt
                    propRow(label: "Projekt") {
                        VStack(alignment: .leading, spacing: 4) {
                            Picker("", selection: $projectSelection) {
                                Text("Kein Projekt").tag("none")
                                if !availableProjects.isEmpty {
                                    Divider()
                                    ForEach(availableProjects) { p in
                                        Text(p.name).tag(p.id)
                                    }
                                    Divider()
                                }
                                Text("+ Neues Projekt…").tag("new")
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            if projectSelection == "new" {
                                TextField("Projektname", text: $newProjectName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11))
                            }
                        }
                    }
                    propDivider()

                    // Priorität
                    propRow(label: "Priorität") {
                        Picker("", selection: $priority) {
                            ForEach(LinearPriority.allCases, id: \.rawValue) { p in
                                Label(p.label, systemImage: p.icon).tag(p)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    propDivider()

                    Spacer(minLength: 0)
                }
                .frame(width: 210)
                .padding(.top, 4)
            }
            .frame(maxHeight: .infinity)

            Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5)

            // ── Footer ──────────────────────────────────────────
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.escape)
                    .foregroundStyle(theme.secondaryText)
                Button {
                    Task { await create() }
                } label: {
                    if isCreating {
                        ProgressView().scaleEffect(0.7).frame(width: 60)
                    } else {
                        Text("Erstellen")
                            .frame(width: 60)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(linearPurple)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                          || selectedTeamId.isEmpty
                          || isCreating
                          || (projectSelection == "new" && newProjectName.trimmingCharacters(in: .whitespaces).isEmpty))
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 680, height: 400)
        .background(theme.windowBg)
    }

    @ViewBuilder
    private func propRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
                .frame(width: 62, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func propDivider() -> some View {
        Rectangle().fill(theme.cardBorder.opacity(0.3)).frame(height: 0.5)
            .padding(.horizontal, 14)
    }

    private func create() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty, !selectedTeamId.isEmpty else { return }
        isCreating = true
        error = nil
        do {
            var projectId: String? = nil
            if projectSelection == "new" {
                let trimmed = newProjectName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    let result = try await service.createProject(teamId: selectedTeamId, name: trimmed)
                    if !result.id.isEmpty { projectId = result.id }
                    await service.loadProjects()
                }
            } else if projectSelection != "none" {
                projectId = projectSelection
            }
            _ = try await service.createIssue(
                teamId: selectedTeamId,
                title: trimmedTitle,
                description: description,
                priority: priority.rawValue,
                projectId: projectId)
            onCreated()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}

// MARK: - New Project Sheet

struct NewProjectSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appTheme) var theme
    @ObservedObject var service: LinearService
    let onCreated: () -> Void

    @State private var name = ""
    @State private var projectDescription = ""
    @State private var selectedTeamId = ""
    @State private var isCreating = false
    @State private var error: String?

    private let linearPurple = Color(red: 0.37, green: 0.42, blue: 0.82)

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────
            HStack(spacing: 8) {
                LinearLogoShape()
                    .fill(linearPurple)
                    .frame(width: 13, height: 13)
                Text("Neues Projekt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                if let err = error {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.statusRed)
                }
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(theme.primaryText.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5)

            // ── Content ─────────────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                TextField("Projektname…", text: $name)
                    .font(.system(size: 15, weight: .semibold))
                    .textFieldStyle(.plain)
                    .foregroundStyle(theme.primaryText)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Rectangle().fill(theme.cardBorder.opacity(0.25)).frame(height: 0.5)
                    .padding(.horizontal, 18)

                ZStack(alignment: .topLeading) {
                    if projectDescription.isEmpty {
                        Text("Beschreibung hinzufügen…")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.tertiaryText.opacity(0.7))
                            .padding(.top, 10)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $projectDescription)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(maxHeight: .infinity)

                Rectangle().fill(theme.cardBorder.opacity(0.3)).frame(height: 0.5)

                // Team row
                HStack(spacing: 10) {
                    Text("Team")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                        .frame(width: 50, alignment: .leading)
                    if !service.teams.isEmpty {
                        Picker("", selection: $selectedTeamId) {
                            ForEach(service.teams) { t in Text(t.name).tag(t.id) }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .onAppear {
                            if selectedTeamId.isEmpty, let first = service.teams.first {
                                selectedTeamId = first.id
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: .infinity)

            Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5)

            // ── Footer ──────────────────────────────────────────
            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .keyboardShortcut(.escape)
                    .foregroundStyle(theme.secondaryText)
                Button {
                    Task { await create() }
                } label: {
                    if isCreating {
                        ProgressView().scaleEffect(0.7).frame(width: 60)
                    } else {
                        Text("Erstellen").frame(width: 60)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(linearPurple)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                          || selectedTeamId.isEmpty || isCreating)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 500, height: 340)
        .background(theme.windowBg)
    }

    private func create() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !selectedTeamId.isEmpty else { return }
        isCreating = true
        error = nil
        do {
            _ = try await service.createProject(
                teamId: selectedTeamId,
                name: trimmed,
                description: projectDescription)
            await service.loadProjects()
            onCreated()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isCreating = false
    }
}
