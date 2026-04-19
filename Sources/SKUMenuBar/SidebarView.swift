import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @Binding var selection: AppSection

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var accentDark: Color {
        let ns = NSColor(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255, alpha: 1)
        return Color(nsColor: ns.blended(withFraction: 0.3, of: .black) ?? ns)
    }

    var body: some View {
        ZStack {
            theme.windowBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Traffic-light spacer + current date & time
                HStack(spacing: 6) {
                    Text(Date(), style: .date)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                    Text(Date(), style: .time)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                }
                .padding(.leading, 12)
                .frame(height: 28)

                // Navigation
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        sectionGroup(title: nil, items: [.home])

                        sectionDivider

                        sectionGroup(title: "Übersicht", items: [.dashboard])

                        sectionDivider

                        sectionGroup(title: "Claude CLI", items: [.chat, .history, .agents, .mcp, .codeReview])

                        sectionDivider

                        sectionGroup(title: "Dateien", items: [.files])

                        if !state.historyService.projects.isEmpty {
                            sectionDivider
                            recentProjectsSection
                        }

                        sectionDivider

                        sectionGroup(title: "Workspace", items: [.notes, .tasks])
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }

                Spacer(minLength: 0)

                VStack(spacing: 2) {
                    sectionGroup(title: nil, items: [.settings])
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)

                Divider().foregroundStyle(theme.cardBorder)

                // Claude usage widget
                claudeUsageWidget
                Divider().foregroundStyle(theme.cardBorder)

                // Limit Flow Bar (nur wenn kritisch)
                limitFlowBar

                // Footer
                sidebarFooter
            }
        }
    }

    // MARK: - Recent Projects

    @ViewBuilder
    private var recentProjectsSection: some View {
        Text("LETZTE PROJEKTE")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.tertiaryText)
            .kerning(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)

        ForEach(state.historyService.projects.prefix(5)) { project in
            Button {
                state.pendingChatNewProject = project.path
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selection = .chat
                }
            } label: {
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.primaryText.opacity(0.06))
                            .frame(width: 26, height: 26)
                        Image(systemName: "folder")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                    }
                    Text(project.displayName)
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .contextMenu {
                Button {
                    state.pendingChatNewProject = project.path
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = .chat
                    }
                } label: {
                    Label("In Chat öffnen", systemImage: "bubble.left.and.bubble.right")
                }
                Button {
                    state.pendingFilesPath = project.path
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = .files
                    }
                } label: {
                    Label("In Explorer öffnen", systemImage: "folder")
                }
                Divider()
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: project.path))
                } label: {
                    Label("Im Finder öffnen", systemImage: "arrow.up.forward.square")
                }
            }
        }
    }

    // MARK: - Divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(theme.cardBorder)
            .frame(height: 0.5)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    // MARK: - Section group

    @ViewBuilder
    private func sectionGroup(title: String?, items: [AppSection]) -> some View {
        if let title {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .kerning(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
        }

        ForEach(items, id: \.self) { section in
            navItem(section)
        }
    }

    // MARK: - Nav item

    private func navItem(_ section: AppSection) -> some View {
        let isSelected = selection == section

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                selection = section
            }
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected
                              ? accentColor.opacity(0.30)
                              : theme.primaryText.opacity(0.06))
                        .frame(width: 26, height: 26)
                    Image(systemName: section.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? accentColor : theme.secondaryText)
                }

                Text(section.rawValue)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? accentColor : theme.secondaryText)

                Spacer()

                // Badges
                if section == .agents, !state.agentService.agents.isEmpty {
                    badge("\(state.agentService.agents.count)")
                }
                if section == .history, !state.historyService.projects.isEmpty {
                    badge("\(state.historyService.projects.count)")
                }
                if section == .notes {
                    let noteCount = state.notes.filter { $0.type == .note }.count
                    if noteCount > 0 { badge("\(noteCount)") }
                }
                if section == .tasks {
                    let openTasks = state.notes.filter { note in
                        guard note.type == .task else { return false }
                        if note.taskLines.isEmpty { return !note.done }
                        return note.taskLines.contains { !$0.done }
                    }.count
                    if openTasks > 0 { badge("\(openTasks)") }
                }
                if section == .chat, !state.activeSessions.isEmpty {
                    liveDot
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.clear)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
    }

    // MARK: - Helpers

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accentColor)
    }

    private var liveDot: some View {
        ZStack {
            Circle().fill(.green.opacity(0.3)).frame(width: 8, height: 8)
            Circle().fill(.green).frame(width: 5, height: 5)
        }
    }

    // MARK: - Claude Usage Widget

    private var claudeUsageWidget: some View {
        let weekTokenLimit = state.settings.claudeWeeklyTokenLimit
        let weekTokens     = state.localWeekTokens
        let todayCost      = state.localTodayCost
        let weekPct        = weekTokenLimit > 0 ? min(1.0, Double(weekTokens) / Double(weekTokenLimit)) : 0
        let barColor: Color = accentColor
        let fallbackActive = state.claudeRateLimitActive && state.settings.copilotFallbackEnabled
        let lastProvider = state.lastChatProvider

        return VStack(alignment: .leading, spacing: 8) {
            // Copilot Fallback Banner
            if fallbackActive {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.isLight ? Color.black.opacity(0.7) : .white)
                    Text("Copilot Fallback aktiv")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.isLight ? Color.black.opacity(0.7) : .white)
                    Spacer()
                    Button {
                        state.claudeRateLimitActive = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.isLight ? Color.black.opacity(0.5) : Color.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Fallback zurücksetzen")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.orange.opacity(0.85), in: RoundedRectangle(cornerRadius: 7))
            }

            if let lastProvider {
                HStack(spacing: 5) {
                    Image(systemName: lastProvider.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(lastProvider == .copilot ? .orange : accentColor)
                    Text("Letzte Antwort: \(lastProvider.label)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                }
            }

            HStack {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(accentColor)
                Text("Heute")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Text("\(state.fmt(todayCost))  ·  \(formatTokens(state.localTodayTokens + state.copilotTodayTokens)) tok")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondaryText)
            }

            // Weekly
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 11))
                        .foregroundStyle(barColor)
                    Text("Diese Woche")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    if weekTokenLimit > 0 {
                        Text("\(formatTokens(weekTokens)) / \(formatTokens(weekTokenLimit)) tok")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(barColor)
                    } else {
                        Text("\(formatTokens(weekTokens)) tok")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                if weekTokenLimit > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.cardBorder)
                            Capsule()
                                .fill(barColor)
                                .frame(width: geo.size.width * weekPct)
                                .animation(.spring(response: 0.4), value: weekPct)
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func formatTokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n)/1_000_000)
        : n >= 1_000   ? String(format: "%.0fK", Double(n)/1_000)
        : "\(n)"
    }

    // MARK: - Limit Flow Bar

    @ViewBuilder
    private var limitFlowBar: some View {
        let sessionLimit = state.settings.claudeSessionTokenLimit
        let weekLimit    = state.settings.claudeWeeklyTokenLimit
        let monthLimit   = state.settings.claudeMonthlySpendLimit

        let sessionUsed  = state.localSessionTokens
        let weekUsed     = state.localWeekTokens
        // Monthly: prefer Anthropic Admin API cost if available, else local estimate
        let monthUsed    = state.claudeMonthCost > 0 ? state.claudeMonthCost : state.localMonthCost

        let sessionPct   = sessionLimit  > 0 ? min(1.0, Double(sessionUsed) / Double(sessionLimit)) : 0
        let weekPct      = weekLimit     > 0 ? min(1.0, Double(weekUsed) / Double(weekLimit))  : 0
        // Monthly: claudeMonthCost is USD, limit is EUR — convert if needed
        let monthLimitUSD = monthLimit > 0 ? monthLimit / state.settings.eurRate : 0
        let monthPct     = monthLimitUSD > 0 ? min(1.0, monthUsed / monthLimitUSD) : 0

        let hasAnyLimit  = sessionLimit > 0 || weekLimit > 0 || monthLimit > 0
        let rateLimitOn  = state.claudeRateLimitActive
        let hasAnyUsage  = sessionUsed > 0 || weekUsed > 0 || monthUsed > 0

        // Show bar when limits are configured, rate-limited, or when there's usage (even without limits)
        if hasAnyLimit || rateLimitOn || hasAnyUsage {
            VStack(spacing: 0) {
                // Session row: rate-limit banner > limit progress > usage-only
                if rateLimitOn, let expiry = state.claudeRateLimitExpiry {
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        planLimitRow(
                            icon: "exclamationmark.octagon.fill",
                            label: "Current session",
                            detail: rateLimitCountdown(expiry),
                            pct: rateLimitProgress(expiry),
                            color: .red,
                            resetLabel: nil
                        )
                    }
                } else if sessionLimit > 0 {
                    planLimitRow(
                        icon: "clock.arrow.circlepath",
                        label: "Current session",
                        detail: "\(formatTokens(sessionUsed)) / \(formatTokens(sessionLimit)) tok",
                        pct: sessionPct,
                        color: accentColor,
                        resetLabel: sessionResetLabel()
                    )
                } else if sessionUsed > 0 {
                    // No limit set — show token count with open-ended bar (fills to 50% at ~44K tok, caps at 100%)
                    let openPct = min(1.0, Double(sessionUsed) / 88_000.0)
                    planLimitRow(
                        icon: "clock.arrow.circlepath",
                        label: "Current session",
                        detail: "\(formatTokens(sessionUsed)) tok",
                        pct: openPct,
                        color: accentColor,
                        resetLabel: sessionResetLabel()
                    )
                }

                // Weekly row (token-based)
                if weekLimit > 0 {
                    planLimitRow(
                        icon: "calendar.badge.clock",
                        label: "Weekly limits",
                        detail: "\(formatTokens(weekUsed)) / \(formatTokens(weekLimit)) tok",
                        pct: weekPct,
                        color: accentColor,
                        resetLabel: weekResetLabel()
                    )
                } else if weekUsed > 0 {
                    // No limit — show week tokens with open-ended bar (ref: 500K tok/week)
                    let openPct  = min(1.0, Double(weekUsed) / 500_000.0)
                    planLimitRow(
                        icon: "calendar.badge.clock",
                        label: "Weekly limits",
                        detail: "\(formatTokens(weekUsed)) tok",
                        pct: openPct,
                        color: accentColor,
                        resetLabel: weekResetLabel()
                    )
                }

                // Monthly / Extra usage row
                if monthLimit > 0 {
                    planLimitRow(
                        icon: "eurosign.circle",
                        label: "Extra usage",
                        detail: String(format: "€%.0f / €%.0f", monthUsed * state.settings.eurRate, monthLimit),
                        pct: monthPct,
                        color: accentColor,
                        resetLabel: "Reset Mai 1"
                    )
                } else if monthUsed > 0 {
                    planLimitRow(
                        icon: "eurosign.circle",
                        label: "Extra usage",
                        detail: String(format: "€%.2f", monthUsed * state.settings.eurRate),
                        pct: 0,
                        color: accentColor,
                        resetLabel: nil
                    )
                }

            }
            .padding(.vertical, 4)
            Divider().foregroundStyle(theme.cardBorder)
        }
    }

    private func planLimitRow(icon: String, label: String, detail: String, pct: Double, color: Color, resetLabel: String?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(detail)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let reset = resetLabel {
                Text("· \(reset)")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private func rateLimitCountdown(_ expiry: Date) -> String {
        let remaining = max(0, expiry.timeIntervalSinceNow)
        if remaining <= 0 { return "bereit" }
        let h = Int(remaining / 3600)
        let m = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
        return h > 0 ? "noch \(h)h \(m)min" : "noch \(m)min"
    }

    private func rateLimitProgress(_ expiry: Date) -> Double {
        let remaining = max(0, expiry.timeIntervalSinceNow)
        let elapsed   = max(0, 5 * 3600 - remaining)
        return min(1.0, elapsed / (5 * 3600))
    }

    private func sessionResetLabel() -> String {
        // Session resets 5h after first message — we show time until +5h from now as proxy
        "alle 5h"
    }

    private func weekResetLabel() -> String {
        var comps = DateComponents()
        comps.weekday = 4  // Mittwoch
        comps.hour    = 7; comps.minute = 0
        guard let next = Calendar.current.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) else { return "" }
        let h = Int(next.timeIntervalSinceNow / 3600)
        return h >= 48 ? "Reset Mi" : "Reset in \(h)h"
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        VStack(spacing: 0) {
            Button {
                NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/limits")!)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 10))
                    Text("Plan usage limits")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                }
                .foregroundStyle(theme.secondaryText.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Plan usage limits auf claude.ai öffnen")

            Divider().foregroundStyle(theme.cardBorder)

            HStack(spacing: 4) {
                Text(BuildInfo.buildDate)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryText.opacity(0.5))
                Text("·")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondaryText.opacity(0.3))
                Text(BuildInfo.commitHash)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.secondaryText.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
    }
}
