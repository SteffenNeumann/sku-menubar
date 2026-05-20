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
    @State private var colWidthProject: CGFloat = 200
    @State private var colWidthIssue: CGFloat = 300
    @State private var showNewIssueSheet = false
    @State private var configured = false
    @State private var hoveredIssueId: String?

    private var accentColor: Color {
        Color(red: theme.acR / 255, green: theme.acG / 255, blue: theme.acB / 255)
    }

    private let linearPurple = Color(red: 0.37, green: 0.42, blue: 0.82)

    var body: some View {
        HStack(spacing: 0) {
            // Col 1 — Projects
            projectColumn
                .frame(width: colWidthProject)

            PanelResizeHandle(width: $colWidthProject, minWidth: 140, maxWidth: 320, growsRight: true)
                .frame(width: 1)
                .background(theme.cardBorder.opacity(0.5))

            // Col 2 — Issues
            issueColumn
                .frame(width: colWidthIssue)

            PanelResizeHandle(width: $colWidthIssue, minWidth: 220, maxWidth: 500, growsRight: true)
                .frame(width: 1)
                .background(theme.cardBorder.opacity(0.5))

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
                        ForEach(service.projects) { project in
                            projectRow(project)
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
                                .fill(Color(red: 0.35, green: 0.50, blue: 0.98).opacity(0.5))
                                .frame(width: geo.size.width * (completedFrac + inProgressFrac))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.20, green: 0.75, blue: 0.45))
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
                        let visible = filteredIssues
                        if visible.isEmpty {
                            emptyPlaceholder("Keine Issues", icon: "tray")
                        } else {
                            ForEach(visible) { issue in
                                issueRow(issue)
                            }
                        }
                    }
                }
            }
        }
    }

    private var issueFilterBar: some View {
        VStack(spacing: 0) {
            // Search
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
            .padding(.horizontal, 14)
            .padding(.vertical, 7)

            Rectangle().fill(theme.cardBorder.opacity(0.3)).frame(height: 0.5)

            // Priority filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    filterChip(label: "Alle", isActive: filterPriority == nil) {
                        filterPriority = nil
                    }
                    ForEach(LinearPriority.allCases, id: \.rawValue) { p in
                        filterChip(label: p.label, icon: p.icon, iconColor: p.color,
                                   isActive: filterPriority == p) {
                            filterPriority = (filterPriority == p) ? nil : p
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }

            Rectangle().fill(theme.cardBorder.opacity(0.3)).frame(height: 0.5)

            // Status filter with state icons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    filterChip(label: "Alle", isActive: filterStatus == nil) {
                        filterStatus = nil
                    }
                    ForEach(availableStatuses, id: \.id) { st in
                        statusFilterChip(st)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }

            Rectangle().fill(theme.cardBorder.opacity(0.3)).frame(height: 0.5)
        }
        .background(theme.windowBg)
    }

    private func filterChip(label: String, icon: String? = nil, iconColor: Color = .secondary,
                             isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                        .foregroundStyle(iconColor)
                }
                Text(label)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.primaryText : theme.tertiaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? theme.primaryText.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isActive ? theme.cardBorder : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func statusFilterChip(_ st: LinearIssueState) -> some View {
        let isActive = filterStatus == st.id
        return Button {
            filterStatus = isActive ? nil : st.id
        } label: {
            HStack(spacing: 4) {
                LinearStateIcon(type: st.type, color: st.displayColor, size: 10)
                Text(st.name)
                    .font(.system(size: 10, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.primaryText : theme.tertiaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? theme.primaryText.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isActive ? theme.cardBorder : Color.clear, lineWidth: 0.5)
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
        let isHovered = hoveredIssueId == issue.id

        return Button {
            selectedIssue = issue
        } label: {
            HStack(alignment: .center, spacing: 10) {
                // Status icon as leading element
                if let st = issue.state {
                    LinearStateIcon(type: st.type, color: st.displayColor, size: 16)
                } else {
                    LinearStateIcon(type: "unstarted", color: theme.tertiaryText, size: 16)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(issue.identifier)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.tertiaryText)

                        // Priority indicator
                        Image(systemName: issue.priority.icon)
                            .font(.system(size: 9))
                            .foregroundStyle(issue.priority.color)
                    }
                    Text(issue.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .strikethrough(issue.state?.isCompleted ?? false, color: theme.tertiaryText)
                }

                Spacer(minLength: 0)

                // Avatar initials
                if let assignee = issue.assigneeName {
                    Text(assignee.components(separatedBy: " ").compactMap(\.first).prefix(2).map(String.init).joined())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(theme.primaryText.opacity(0.07)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? linearPurple.opacity(0.10)
                : isHovered ? theme.primaryText.opacity(0.03) : Color.clear
            )
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.cardBorder.opacity(0.3)).frame(height: 0.5)
                    .padding(.leading, 38)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoveredIssueId = $0 ? issue.id : nil }
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
                    Text(issue.identifier)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.primaryText.opacity(0.05))
                        )
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
                }
                .padding(16)

                // Title — prominent
                Text(issue.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .strikethrough(issue.state?.isCompleted ?? false)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

                // Properties grid with subtle dividers
                propertiesSection(issue)

                Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5)
                    .padding(.vertical, 2)

                // Description — rendered as Markdown
                if !issue.description.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Beschreibung")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.tertiaryText)

                        MarkdownTextView(text: issue.description)
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Properties Section (Linear-style grid)

    private func propertiesSection(_ issue: LinearIssue) -> some View {
        VStack(spacing: 0) {
            propertyRow(label: "Status") {
                if let st = issue.state {
                    HStack(spacing: 5) {
                        LinearStateIcon(type: st.type, color: st.displayColor, size: 14)
                        Text(st.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                    }
                }
            }
            propertyRow(label: "Priorität") {
                HStack(spacing: 5) {
                    Image(systemName: issue.priority.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(issue.priority.color)
                    Text(issue.priority.label)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.primaryText)
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
                .frame(width: 90, alignment: .leading)
            content()
            Spacer()
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.cardBorder.opacity(0.2)).frame(height: 0.5)
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
    @State private var isCreating = false
    @State private var error: String?

    private let linearPurple = Color(red: 0.37, green: 0.42, blue: 0.82)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with Linear logo
            HStack {
                HStack(spacing: 6) {
                    LinearLogoShape()
                        .fill(linearPurple)
                        .frame(width: 14, height: 14)
                    Text("Neues Issue")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(theme.primaryText.opacity(0.05)))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Team picker
                    if !teams.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Team")
                                .font(.system(size: 11, weight: .medium))
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
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.tertiaryText)
                        TextField("Issue-Titel", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                    }

                    // Priority
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Priorität")
                            .font(.system(size: 11, weight: .medium))
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
                            .font(.system(size: 11, weight: .medium))
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
                            .foregroundStyle(theme.statusRed)
                    }
                }
                .padding(16)
            }

            Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(height: 0.5)

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
                .tint(linearPurple)
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
