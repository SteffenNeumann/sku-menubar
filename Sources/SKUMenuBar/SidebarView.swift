import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @Binding var selection: AppSection

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    var body: some View {
        ZStack {
            theme.windowBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Traffic-light spacer
                Color.clear.frame(height: 10)

                // App branding
                brandingHeader

                Divider().foregroundStyle(theme.cardBorder)

                // Navigation
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        sectionGroup(title: "Übersicht", items: [.dashboard])

                        sectionDivider

                        sectionGroup(title: "Claude CLI", items: [.chat, .history, .agents, .mcp, .codeReview])

                        sectionDivider

                        sectionGroup(title: nil, items: [.settings])
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }

                Divider().foregroundStyle(theme.cardBorder)

                // Claude usage widget
                claudeUsageWidget
                Divider().foregroundStyle(theme.cardBorder)

                // Footer
                sidebarFooter
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(theme.cardBorder)
            .frame(height: 0.5)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    // MARK: - App header

    private var brandingHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [accentColor, accentColor.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 30, height: 30)
                    .shadow(color: accentColor.opacity(0.35), radius: 4, y: 2)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("myClaude")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                Text("AI Command Center")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    // MARK: - Section group

    @ViewBuilder
    private func sectionGroup(title: String?, items: [AppSection]) -> some View {
        if let title {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
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
                              ? accentColor.opacity(0.20)
                              : theme.primaryText.opacity(0.06))
                        .frame(width: 26, height: 26)
                    Image(systemName: section.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? accentColor : theme.secondaryText)
                }

                Text(section.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)

                Spacer()

                // Badges
                if section == .agents, !state.agentService.agents.isEmpty {
                    badge("\(state.agentService.agents.count)")
                }
                if section == .history, !state.historyService.projects.isEmpty {
                    badge("\(state.historyService.projects.count)")
                }
                if section == .chat, !state.activeSessions.isEmpty {
                    liveDot
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? theme.accent : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? theme.accentBorder : .clear, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                Capsule().fill(accentColor.opacity(0.75))
            )
    }

    private var liveDot: some View {
        ZStack {
            Circle().fill(.green.opacity(0.3)).frame(width: 8, height: 8)
            Circle().fill(.green).frame(width: 5, height: 5)
        }
    }

    // MARK: - Claude Usage Widget

    private var claudeUsageWidget: some View {
        let weekLimit  = state.settings.claudeWeeklyCostLimit
        let weekCost   = state.localWeekCost
        let todayCost  = state.localTodayCost
        let weekPct    = weekLimit > 0 ? min(1, weekCost / weekLimit) : 0
        let barColor: Color = weekPct > 0.9 ? .red : weekPct > 0.7 ? .orange : accentColor

        return VStack(alignment: .leading, spacing: 8) {
            // Today
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(accentColor)
                Text("Heute")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(state.fmt(todayCost))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    Text("\(formatTokens(state.localTodayTokens)) tok")
                        .font(.system(size: 8))
                        .foregroundStyle(theme.tertiaryText)
                }
            }

            // Weekly
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 9))
                        .foregroundStyle(barColor)
                    Text("Diese Woche")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                    Spacer()
                    if weekLimit > 0 {
                        Text("\(state.fmt(weekCost)) / \(state.fmt(weekLimit))")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(barColor)
                    } else {
                        Text(state.fmt(weekCost))
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                if weekLimit > 0 {
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

    // MARK: - Footer

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            if let t = state.lastUpdate {
                Image(systemName: "clock").font(.system(size: 9))
                Text(t.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
            } else {
                Text("Nicht geladen").font(.system(size: 10))
            }
            Spacer()
        }
        .foregroundStyle(theme.tertiaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
