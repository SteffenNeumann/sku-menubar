import SwiftUI

// MARK: - ConvergenceView
// Shown as a sheet from PersonaReviewOverlay when user clicks "Co-Design Loop starten".
// Owns the ConvergenceSession and drives it.

struct ConvergenceView: View {

    // Setup inputs
    let fileNode: ExplorerNode
    let initialContent: String
    let critic: AgentDefinition
    let allDesigners: [AgentDefinition]
    let allImplementors: [AgentDefinition]
    let onFileUpdated: (String) -> Void   // called when implementor writes new content
    let onClose: () -> Void

    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    // Session (created on Start)
    @State private var session: ConvergenceSession? = nil

    // Config state (setup screen)
    @State private var selectedDesigner: AgentDefinition? = nil
    @State private var selectedImplementor: AgentDefinition? = nil
    @State private var maxIterations: Int = 6
    @State private var autorun: Bool = false

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(accentColor)
                Text("Co-Design Loop")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(theme.cardBg.opacity(0.6))

            Divider().opacity(0.3)

            if let session {
                SessionStatusView(
                    session: session,
                    accentColor: accentColor,
                    theme: theme,
                    onFileUpdated: onFileUpdated,
                    onClose: onClose
                )
            } else {
                SetupView(
                    critic: critic,
                    allDesigners: allDesigners,
                    allImplementors: allImplementors,
                    selectedDesigner: $selectedDesigner,
                    selectedImplementor: $selectedImplementor,
                    maxIterations: $maxIterations,
                    autorun: $autorun,
                    accentColor: accentColor,
                    theme: theme,
                    onStart: startSession
                )
            }
        }
        .background(theme.cardBg)
        .cornerRadius(12)
        .onAppear {
            selectedDesigner = allDesigners.first
            selectedImplementor = allImplementors.first
        }
    }

    private func startSession() {
        guard let designer = selectedDesigner, let implementor = selectedImplementor else { return }
        let cli = state.cliService
        let config = ConvergenceSession.Config(
            maxIterations: maxIterations,
            autorun: autorun,
            filePath: fileNode.url.path,
            fileContent: initialContent,
            critic: critic,
            designer: designer,
            implementor: implementor
        )
        let s = ConvergenceSession(config: config, cli: cli)
        session = s
        s.start()
    }
}

// MARK: - Setup Screen

private struct SetupView: View {
    let critic: AgentDefinition
    let allDesigners: [AgentDefinition]
    let allImplementors: [AgentDefinition]
    @Binding var selectedDesigner: AgentDefinition?
    @Binding var selectedImplementor: AgentDefinition?
    @Binding var maxIterations: Int
    @Binding var autorun: Bool
    let accentColor: Color
    let theme: AppTheme
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Roles section
                VStack(alignment: .leading, spacing: 12) {
                    Text("AGENTEN")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.tertiaryText)
                        .tracking(1.2)

                    // Critic (read-only)
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Critic (Persona)", systemImage: "theatermasks.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.purple.opacity(0.85))
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.purple.opacity(0.15))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Text(String(critic.name.prefix(1)))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.purple)
                                )
                            VStack(alignment: .leading, spacing: 1) {
                                Text(critic.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)
                                Text("Bewertet aus Nutzerperspektive")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.purple.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.purple.opacity(0.15), lineWidth: 0.5))

                    agentPicker(label: "Designer", icon: "paintbrush.fill",
                                color: accentColor,
                                agents: allDesigners, selection: $selectedDesigner)

                    agentPicker(label: "Implementor", icon: "hammer.fill",
                                color: .orange,
                                agents: allImplementors, selection: $selectedImplementor)
                }

                Divider().opacity(0.3)

                // Config section
                VStack(alignment: .leading, spacing: 12) {
                    Text("KONFIGURATION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.tertiaryText)
                        .tracking(1.2)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Max. Runden")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.primaryText)
                            Text("Maximale Iterations-Anzahl")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            Stepper("", value: $maxIterations, in: 1...12)
                                .labelsHidden()
                            Text("\(maxIterations)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                                .frame(width: 28, alignment: .center)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(theme.cardSurface)
                                .cornerRadius(6)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Toggle(isOn: $autorun) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Autorun")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(theme.primaryText)
                                Text("Runden ohne Pause automatisch fortsetzen")
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }

                Spacer(minLength: 8)

                Button(action: onStart) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                        Text("Co-Design Loop starten")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .cornerRadius(9)
                }
                .buttonStyle(.plain)
                .disabled(selectedDesigner == nil || selectedImplementor == nil)
                .opacity(selectedDesigner == nil || selectedImplementor == nil ? 0.5 : 1)
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func agentPicker(label: String, icon: String, color: Color,
                             agents: [AgentDefinition],
                             selection: Binding<AgentDefinition?>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color.opacity(0.85))
            if agents.isEmpty {
                Text("Kein passender Agent gefunden")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.cardSurface)
                    .cornerRadius(7)
            } else {
                Menu {
                    ForEach(agents) { agent in
                        Button(agent.name) { selection.wrappedValue = agent }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(color.opacity(0.15))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(String((selection.wrappedValue?.name ?? "?").prefix(1)))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(color)
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(selection.wrappedValue?.name ?? "Wählen…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.primaryText)
                            Text(label == "Designer" ? "Prüft Design-Machbarkeit" : "Setzt Änderungen um")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(color.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.15), lineWidth: 0.5))
                }
                .menuStyle(.automatic)
                .buttonStyle(.plain)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Live Status Screen

private struct SessionStatusView: View {
    @ObservedObject var session: ConvergenceSession
    let accentColor: Color
    let theme: AppTheme
    let onFileUpdated: (String) -> Void
    let onClose: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.5

    private var isRunning: Bool {
        [ConvergencePhase.critic, .designer, .implementor].contains(session.phase)
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            Divider().opacity(0.15)

            // Pipeline
            agentPipeline
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)

            Divider().opacity(0.10)

            // Scrollable content area
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    liveOutputArea
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 12)

                    if session.iteration > 0, let critique = session.lastCritique {
                        critiqueSummarySection(critique)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    }
                }
            }
            .frame(maxHeight: .infinity)

            if !session.snapshots.isEmpty {
                Divider().opacity(0.15)
                snapshotHistorySection
            }

            if let err = session.errorMessage {
                Divider().opacity(0.15)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 12))
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.07))
            }

            Divider().opacity(0.15)
            actionButtons.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulseScale = 1.35
                pulseOpacity = 1.0
            }
        }
    }

    // MARK: Progress header

    private var progressHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(phaseColor.opacity(0.25))
                    .frame(width: 28, height: 28)
                    .scaleEffect(isRunning ? pulseScale : 1)
                    .opacity(isRunning ? (pulseOpacity * 0.6) : 0)
                Circle()
                    .fill(phaseColor)
                    .frame(width: 12, height: 12)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(phaseLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .animation(.default, value: session.phase)
                Text(session.iteration > 0
                     ? "Runde \(session.iteration) von \(session.maxIterations)"
                     : "Initialisierung…")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            if session.maxIterations > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(phaseProgress * 100))%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accentColor)
                        .animation(.spring(duration: 0.4), value: phaseProgress)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.cardSurface).frame(height: 5)
                            Capsule()
                                .fill(accentColor)
                                .frame(width: geo.size.width * CGFloat(phaseProgress), height: 5)
                                .animation(.spring(duration: 0.4), value: phaseProgress)
                        }
                    }
                    .frame(width: 110, height: 5)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(phaseColor.opacity(0.07))
    }

    // MARK: Agent pipeline

    private var agentPipeline: some View {
        HStack(spacing: 0) {
            agentNode(targetPhase: .critic, icon: "theatermasks.fill",
                      name: session.criticName, color: .purple)
            connectionLine(lit: phaseIndex > 0)
            agentNode(targetPhase: .designer, icon: "paintbrush.fill",
                      name: session.designerName, color: accentColor)
            connectionLine(lit: phaseIndex > 1)
            agentNode(targetPhase: .implementor, icon: "hammer.fill",
                      name: session.implementorName, color: .orange)
        }
    }

    private var phaseIndex: Int {
        switch session.phase {
        case .critic:     return 0
        case .designer:   return 1
        case .implementor: return 2
        case .converged, .escalation, .cancelled: return 3
        default: return -1
        }
    }

    private func agentNode(targetPhase: ConvergencePhase, icon: String, name: String, color: Color) -> some View {
        let isActive = session.phase == targetPhase
        let pIdx = phaseIndex
        let nodeIdx: Int = {
            switch targetPhase {
            case .critic: return 0
            case .designer: return 1
            case .implementor: return 2
            default: return 0
            }
        }()
        let isDone = pIdx > nodeIdx

        let progress = nodeProgress(targetPhase: targetPhase)

        return VStack(spacing: 6) {
            ZStack {
                if isActive {
                    Circle()
                        .fill(color.opacity(0.22))
                        .frame(width: 56, height: 56)
                        .scaleEffect(pulseScale)
                }
                Circle()
                    .fill(isActive ? color : (isDone ? color.opacity(0.18) : theme.cardSurface))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle().strokeBorder(
                            isActive ? color : color.opacity(isDone ? 0.45 : 0.18),
                            lineWidth: isActive ? 1.5 : 1
                        )
                    )
                    .shadow(color: isActive ? color.opacity(0.45) : .clear, radius: 8)

                if isDone && !isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color.opacity(0.85))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(isActive ? .white : color.opacity(isDone ? 0.6 : 0.3))
                }
            }
            .animation(.spring(duration: 0.35), value: session.phase)

            Text(shortName(name))
                .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? theme.primaryText : theme.tertiaryText)
                .lineLimit(1)

            // Per-agent progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.12))
                        .frame(height: 3)
                    Capsule()
                        .fill(color.opacity(isDone ? 0.5 : 0.85))
                        .frame(width: geo.size.width * CGFloat(progress), height: 3)
                        .animation(.linear(duration: 0.15), value: progress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 4)
            .opacity(isDone || isActive ? 1 : 0.25)
        }
        .frame(maxWidth: .infinity)
    }

    private func connectionLine(lit: Bool) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(lit ? accentColor.opacity(0.5) : theme.secondaryText.opacity(0.12))
                .frame(height: 1.5)
                .animation(.easeInOut(duration: 0.4), value: lit)
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 5))
                .foregroundStyle(lit ? accentColor.opacity(0.5) : theme.secondaryText.opacity(0.12))
        }
        .frame(width: 24)
        .offset(y: -9)
    }

    private func shortName(_ name: String) -> String {
        let s = name.components(separatedBy: CharacterSet(charactersIn: " -")).first ?? name
        return s.count > 13 ? String(s.prefix(12)) + "…" : s
    }

    private var phaseProgress: Double {
        guard session.maxIterations > 0 else { return 0 }
        let done = Double(max(session.iteration - 1, 0))
        let step: Double = {
            switch session.phase {
            case .critic:      return 0.33
            case .designer:    return 0.67
            case .implementor: return 0.99
            case .converged, .escalation, .cancelled: return 1.0
            default: return 0
            }
        }()
        return min((done + step) / Double(session.maxIterations), 1.0)
    }

    private func nodeProgress(targetPhase: ConvergencePhase) -> Double {
        let nodeIdx: Int = { switch targetPhase {
            case .critic: return 0; case .designer: return 1; case .implementor: return 2; default: return 0
        }}()
        if phaseIndex > nodeIdx { return 1.0 }
        guard session.phase == targetPhase else { return 0.0 }
        let typical: Double = targetPhase == .critic ? 900 : targetPhase == .designer ? 500 : 6000
        return min(Double(session.phaseOutputLen) / typical, 0.95)
    }

    // MARK: Live output area

    private var liveOutputArea: some View {
        let raw = session.liveOutput
        let hasOutput = !raw.isEmpty
        let display = (raw.count > 500 ? "…" + raw.suffix(500) : raw)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if isRunning {
                    Circle()
                        .fill(phaseColor)
                        .frame(width: 6, height: 6)
                        .opacity(pulseOpacity)
                }
                Text(isRunning ? "Agent arbeitet…" : (session.phase == .converged ? "✓ Abgeschlossen" : "Warte…"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isRunning ? phaseColor : theme.secondaryText)
                Spacer()
                if isRunning && session.phaseOutputLen > 0 {
                    Text("\(session.phaseOutputLen) Zeichen")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            if hasOutput {
                Text(display)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.primaryText.opacity(0.85))
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: display)
            } else {
                Text("Warte auf Agent-Antwort…")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(theme.cardSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(phaseColor.opacity(isRunning ? 0.35 : 0.12), lineWidth: 0.5)
        )
    }

    // MARK: Critique Summary

    @ViewBuilder
    private func critiqueSummarySection(_ critique: CritiqueReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "list.clipboard.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
                Text("Letzte Bewertung")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                verdictPill(critique.verdict)
                Spacer()
                Text(critiqueSeverityLabel(critique))
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
            }

            if !critique.overallImpression.isEmpty {
                Text(critique.overallImpression)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.primaryText.opacity(0.75))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !critique.issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(critique.issues.prefix(5)) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            severityDot(issue.severity)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(issue.what)
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.primaryText)
                                    .lineLimit(2)
                                HStack(spacing: 4) {
                                    Text(issue.area.uppercased())
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(theme.tertiaryText)
                                    Text("·")
                                        .font(.system(size: 9))
                                        .foregroundStyle(theme.tertiaryText)
                                    Text(issue.severity.rawValue)
                                        .font(.system(size: 9))
                                        .foregroundStyle(severityColor(issue.severity).opacity(0.8))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if critique.issues.count > 5 {
                        Text("+\(critique.issues.count - 5) weitere Issues")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                            .padding(.leading, 14)
                    }
                }
            }
        }
        .padding(14)
        .background(theme.cardSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(phaseColor.opacity(0.18), lineWidth: 0.5)
        )
    }

    private func verdictPill(_ verdict: CritiqueVerdict) -> some View {
        let (label, color): (String, Color) = {
            switch verdict {
            case .approve:     return ("✓ Approved", .green)
            case .revise:      return ("↻ Überarbeiten", .orange)
            case .rejectFinal: return ("✗ Abgelehnt", .red)
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .cornerRadius(5)
    }

    @ViewBuilder
    private func severityDot(_ severity: IssueSeverity) -> some View {
        Circle()
            .fill(severityColor(severity))
            .frame(width: 7, height: 7)
            .padding(.top, 3)
    }

    private func severityColor(_ severity: IssueSeverity) -> Color {
        switch severity {
        case .blocker: return .red
        case .major:   return .orange
        case .minor:   return Color(red: 0.9, green: 0.75, blue: 0.2)
        }
    }

    private func critiqueSeverityLabel(_ critique: CritiqueReport) -> String {
        let blockers = critique.issues.filter { $0.severity == .blocker }.count
        let majors   = critique.issues.filter { $0.severity == .major }.count
        let minors   = critique.issues.filter { $0.severity == .minor }.count
        var parts: [String] = []
        if blockers > 0 { parts.append("\(blockers) Blocker") }
        if majors   > 0 { parts.append("\(majors) Major") }
        if minors   > 0 { parts.append("\(minors) Minor") }
        return parts.isEmpty ? "0 Issues" : parts.joined(separator: " · ")
    }

    // MARK: Snapshot History

    private var snapshotHistorySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Verlauf — \(session.snapshots.count) Runden")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(session.snapshots.reversed()) { snap in
                        SnapshotRow(snap: snap, accentColor: accentColor, theme: theme) {
                            session.restore(snapshot: snap)
                            onFileUpdated(snap.fileContent)
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 140)
        }
    }

    // MARK: Helpers

    private var phaseColor: Color {
        switch session.phase {
        case .critic:      return .purple
        case .designer:    return accentColor
        case .implementor: return .orange
        case .converged:   return .green
        case .escalation:  return .orange
        default:           return theme.secondaryText
        }
    }

    private var phaseLabel: String {
        switch session.phase {
        case .idle:         return "Bereit"
        case .critic:       return "\(shortName(session.criticName)) bewertet…"
        case .designer:     return "\(shortName(session.designerName)) prüft…"
        case .implementor:  return "\(shortName(session.implementorName)) setzt um…"
        case .converged:    return "Konsens erreicht ✓"
        case .escalation:   return escalationLabel
        case .cancelled:    return "Abgebrochen"
        }
    }

    private var escalationLabel: String {
        switch session.escalationReason {
        case .capReached:                      return "Max. Runden erreicht"
        case .stalemate:                       return "Patt — gleiche Issues"
        case .rejectFinal:                     return "Persona lehnt grundsätzlich ab"
        case .designerInfeasibleNoAlternative: return "Designer: keine Alternative"
        case nil:                              return "Loop beendet"
        }
    }

    // MARK: Action buttons

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 8) {
            switch session.phase {
            case .idle, .critic, .designer, .implementor:
                if session.awaitingNextRound {
                    Button("▶ Nächste Runde") { session.continueRound() }
                        .buttonStyle(ConvergenceButtonStyle(color: accentColor))
                }
                Button("⏹ Abbrechen") { session.cancel() }
                    .buttonStyle(ConvergenceButtonStyle(color: theme.secondaryText))
            case .converged:
                Button("✓ Übernehmen & schließen") {
                    onFileUpdated(session.currentFileContent)
                    onClose()
                }
                .buttonStyle(ConvergenceButtonStyle(color: .green))
                Button("↻ Weitere Runde") {
                    session.phase = .idle
                    session.start()
                }
                .buttonStyle(ConvergenceButtonStyle(color: accentColor))
            case .escalation:
                Text(escalationLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                Button("Schließen") { onClose() }
                    .buttonStyle(ConvergenceButtonStyle(color: theme.secondaryText))
            case .cancelled:
                Button("Schließen") { onClose() }
                    .buttonStyle(ConvergenceButtonStyle(color: theme.secondaryText))
            }
        }
    }
}

// MARK: - Snapshot Row

private struct SnapshotRow: View {
    let snap: ConvergenceSnapshot
    let accentColor: Color
    let theme: AppTheme
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Verdict badge
            if let c = snap.critique {
                verdictBadge(c.verdict)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Runde \(snap.iteration)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    if let c = snap.critique {
                        let blockers = c.issues.filter { $0.severity == .blocker }.count
                        let majors   = c.issues.filter { $0.severity == .major }.count
                        if blockers > 0 {
                            Text("\(blockers)B")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.red)
                        }
                        if majors > 0 {
                            Text("\(majors)M")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    if let impl = snap.implementation {
                        let changed = impl.filesChanged.count
                        if changed > 0 {
                            Label("\(changed) Datei\(changed == 1 ? "" : "en")", systemImage: "doc.badge.plus")
                                .font(.system(size: 9))
                                .foregroundStyle(accentColor.opacity(0.8))
                        }
                    }
                }
                if let c = snap.critique, !c.overallImpression.isEmpty {
                    Text(c.overallImpression.prefix(80))
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Button("↩") { onRestore() }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(accentColor)
                .help("Auf diesen Stand zurücksetzen")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(theme.cardSurface.opacity(0.5))
        .cornerRadius(7)
    }

    @ViewBuilder
    private func verdictBadge(_ verdict: CritiqueVerdict) -> some View {
        let (label, color): (String, Color) = {
            switch verdict {
            case .approve:     return ("✓", .green)
            case .revise:      return ("↻", .orange)
            case .rejectFinal: return ("✗", .red)
            }
        }()
        Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 20)
    }
}

// MARK: - Button Style

private struct ConvergenceButtonStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundStyle(.white)
            .cornerRadius(7)
    }
}
