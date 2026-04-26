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
        VStack(alignment: .leading, spacing: 14) {
            // Roles
            VStack(alignment: .leading, spacing: 8) {
                Label("Critic (Persona)", systemImage: "theatermasks.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                Text(critic.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
            }

            agentPicker(label: "Designer", icon: "paintbrush.fill",
                        agents: allDesigners, selection: $selectedDesigner)

            agentPicker(label: "Implementor", icon: "hammer.fill",
                        agents: allImplementors, selection: $selectedImplementor)

            Divider().opacity(0.3)

            // Config
            HStack {
                Text("Max. Runden")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Stepper("\(maxIterations)", value: $maxIterations, in: 1...12)
                    .labelsHidden()
                Text("\(maxIterations)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 24)
            }

            Toggle("Autorun (ohne Pause)", isOn: $autorun)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)
                .toggleStyle(.switch)

            Spacer()

            Button(action: onStart) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Co-Design Loop starten")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(accentColor)
                .foregroundStyle(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(selectedDesigner == nil || selectedImplementor == nil)
        }
        .padding(16)
    }

    @ViewBuilder
    private func agentPicker(label: String, icon: String,
                             agents: [AgentDefinition],
                             selection: Binding<AgentDefinition?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryText)
            if agents.isEmpty {
                Text("Kein passender Agent gefunden")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.tertiaryText)
            } else {
                Menu {
                    ForEach(agents) { agent in
                        Button(agent.name) { selection.wrappedValue = agent }
                    }
                } label: {
                    HStack {
                        Text(selection.wrappedValue?.name ?? "Wählen…")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.cardSurface)
                    .cornerRadius(6)
                }
                .menuStyle(.borderlessButton)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Phase header
                PhaseHeaderView(session: session, accentColor: accentColor, theme: theme)

                Divider().opacity(0.3)

                // Snapshot timeline
                if !session.snapshots.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Verlauf")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                        ForEach(session.snapshots) { snap in
                            SnapshotRow(snap: snap, accentColor: accentColor, theme: theme) {
                                session.restore(snapshot: snap)
                                onFileUpdated(snap.fileContent)
                            }
                        }
                    }
                }

                // Error
                if let err = session.errorMessage {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(6)
                }

                // Action buttons
                actionButtons
            }
            .padding(14)
        }
    }

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
                Text(escalationText)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
                Button("Schließen") { onClose() }
                    .buttonStyle(ConvergenceButtonStyle(color: theme.secondaryText))

            case .cancelled:
                Button("Schließen") { onClose() }
                    .buttonStyle(ConvergenceButtonStyle(color: theme.secondaryText))
            }
        }
    }

    private var escalationText: String {
        switch session.escalationReason {
        case .capReached:                      return "Maximale Rundenzahl erreicht."
        case .stalemate:                       return "Susanne wiederholt dieselben Issues (Patt)."
        case .rejectFinal:                     return "Persona hat die Richtung grundsätzlich abgelehnt."
        case .designerInfeasibleNoAlternative: return "Designer hält Wünsche für nicht umsetzbar."
        case nil:                              return "Loop beendet."
        }
    }
}

// MARK: - Phase Header

private struct PhaseHeaderView: View {
    @ObservedObject var session: ConvergenceSession
    let accentColor: Color
    let theme: AppTheme

    var body: some View {
        HStack(spacing: 10) {
            // Spinner or check
            Group {
                if [ConvergencePhase.critic, .designer, .implementor].contains(session.phase) {
                    ProgressView().controlSize(.small)
                } else if session.phase == .converged {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if session.phase == .escalation {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    Image(systemName: "circle").foregroundStyle(theme.tertiaryText)
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(phaseLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text("Runde \(session.iteration) von \(6)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
            }
        }
    }

    private var phaseLabel: String {
        switch session.phase {
        case .idle:        return "Bereit"
        case .critic:      return "Persona bewertet…"
        case .designer:    return "Designer prüft…"
        case .implementor: return "Implementor setzt um…"
        case .converged:   return "Konsens erreicht ✓"
        case .escalation:  return "Eskalation ⚠"
        case .cancelled:   return "Abgebrochen"
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
        HStack(spacing: 8) {
            // Verdict badge
            if let c = snap.critique {
                verdictBadge(c.verdict)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Runde \(snap.iteration)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                if let c = snap.critique {
                    Text(c.overallImpression.prefix(60))
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("Wiederherstellen") { onRestore() }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundStyle(accentColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(theme.cardSurface.opacity(0.5))
        .cornerRadius(6)
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
