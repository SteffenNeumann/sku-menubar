import SwiftUI
import AppKit

// MARK: - NSVisualEffect background (blurs the desktop behind the panel)

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = material
        v.blendingMode = blendingMode
        v.state        = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material     = material
        v.blendingMode = blendingMode
    }
}

// MARK: - Reusable Glass Card modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Dashboard View

private struct UsageCardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 300
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @State private var refreshRotation: Double = 0
    @State private var usageCardHeight: CGFloat = 300

    /// Width that makes all 28 HabitGrid cells perfectly square (no wasted space).
    /// Derived from the measured UsageOverviewCard height.
    private var idealHabitGridCardWidth: CGFloat {
        let contentH   = usageCardHeight - 32          // minus .padding(16) top+bottom
        let gridH      = contentH - 28 - 16 - 16       // minus header(28) + legend(16) + spacing(16)
        let cellH      = max(16, (gridH - 12) / 4)     // vGaps = 3 × 4 = 12, rows = 4
        let gridWidth  = cellH * 7 + 24                // 7 cells + 6 × 4pt gaps
        return max(185, gridWidth + 32)                // minimum 185pt so card never collapses
    }

    // MARK: - Accent / KPI helpers

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var dailyRef: Double {
        guard state.settings.budget > 0 else { return 0 }
        let days = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        return state.settings.budget / Double(days)
    }
    private var todayPct: Double { dailyRef > 0 ? min(1, state.todayCost / dailyRef) : 0 }
    private func consumedColor(_ p: Double) -> Color { p > 0.9 ? .red : p > 0.75 ? .orange : accentColor }
    private func remainColor(_ p: Double) -> Color { p < 0.2 ? .red : p < 0.4 ? .orange : .green }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {

                // ── Page title row ─────────────────────────────────────
                HStack(alignment: .bottom, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dashboard")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                        Text("Echtzeit-Verbrauch und Budget-Tracking.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        // System status badge
                        HStack(spacing: 4) {
                            Circle().fill(state.errorMsg != nil ? Color.red : Color.green)
                                .frame(width: 6, height: 6)
                            Text(state.errorMsg != nil ? "FEHLER" : "LIVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(state.errorMsg != nil ? Color.red : Color.green)
                                .kerning(0.8)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(state.errorMsg != nil ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(state.errorMsg != nil ? Color.red.opacity(0.4) : Color.green.opacity(0.4), lineWidth: 1))
                        )

                        // Refresh
                        Button {
                            withAnimation(.linear(duration: 0.6)) { refreshRotation += 360 }
                            Task {
                                await state.refresh()
                                await state.refreshClaude()
                                state.activeSessions = state.cliService.loadActiveSessions()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(theme.secondaryText)
                                .rotationEffect(.degrees(refreshRotation))
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 8).fill(theme.cardSurface)
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.cardBorder, lineWidth: 1)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)

                // Error banner
                if let err = state.errorMsg {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(err).font(.system(size: 11)).foregroundStyle(theme.primaryText).lineLimit(3)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)))
                }

                // ── 3 KPI Cards ────────────────────────────────────────
                HStack(spacing: 12) {
                    kpiCard(label: "HEUTE", icon: "calendar.badge.clock", iconColor: accentColor,
                            value: state.fmt(state.todayCost),
                            badge: "+\(Int(todayPct * 100))%",
                            badgeColor: consumedColor(todayPct),
                            pct: todayPct, barColor: accentColor,
                            sub: dailyRef > 0 ? "Limit: \(state.fmt(dailyRef))" : "Kein Limit")

                    kpiCard(label: "DIESEN MONAT", icon: "calendar", iconColor: .green,
                            value: state.fmt(state.monthCost),
                            badge: "+\(Int(state.monthPct * 100))%",
                            badgeColor: consumedColor(state.monthPct),
                            pct: state.monthPct, barColor: .green,
                            sub: state.settings.budget > 0 ? "von \(state.fmt(state.settings.budget))" : "Kein Limit")

                    kpiCard(label: "VERBLEIBEND", icon: "building.columns.fill", iconColor: .blue,
                            value: state.settings.budget > 0 ? state.fmt(state.remain) : "–",
                            badge: "\(Int(state.remainPct * 100))%",
                            badgeColor: remainColor(state.remainPct),
                            pct: state.remainPct, barColor: remainColor(state.remainPct),
                            sub: state.settings.budget > 0 ? "Ziel: \(state.fmt(state.settings.budget))/Mo." : "Kein Budget")
                }

                // ── Middle row: Habit grid + Usage overview ─────────────
                HStack(alignment: .top, spacing: 12) {
                    // Left: grid sized so cells are exactly square (no wasted space)
                    HabitGridView(days: state.dailyUsage)
                        .padding(16)
                        .frame(width: idealHabitGridCardWidth, height: usageCardHeight)
                        .clipped()
                        .background(RoundedRectangle(cornerRadius: 14).fill(theme.cardSurface)
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.cardBorder, lineWidth: 1)))

                    // Right: natural height is measured, then both cards are pinned to it
                    ZStack(alignment: .top) {
                        UsageOverviewCard()
                            .overlay(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: UsageCardHeightKey.self,
                                        value: geo.size.height
                                    )
                                }
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: usageCardHeight)
                }
                .onPreferenceChange(UsageCardHeightKey.self) { usageCardHeight = $0 }

                // ── Bottom row: Sources + Claude ────────────────────────
                HStack(alignment: .top, spacing: 12) {
                    SourceBreakdownCard(period: .month)
                        .frame(maxWidth: .infinity)
                    if !state.settings.anthropicAdminKey.isEmpty {
                        ClaudeUsageCard()
                            .frame(maxWidth: .infinity)
                    }
                }

                // ── Statistics Section ──────────────────────────────────
                Divider()
                    .opacity(0.2)
                    .padding(.vertical, 4)

                StatisticsDashboardSection()

                // Footer
                HStack {
                    if let t = state.lastUpdate {
                        Label(t.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                            .font(.system(size: 10)).foregroundStyle(theme.tertiaryText)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - KPI Card

    private func kpiCard(label: String, icon: String, iconColor: Color,
                          value: String, badge: String, badgeColor: Color,
                          pct: Double, barColor: Color, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: icon + label + badge pill in one row
            HStack(alignment: .center, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(iconColor)
                }
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
                    .kerning(0.8)
                Spacer()
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(badgeColor.opacity(0.12), in: Capsule())
            }

            // Value
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            // Progress bar + subtitle
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.cardBorder)
                        Capsule().fill(barColor)
                            .frame(width: geo.size.width * max(0, min(1, pct)))
                            .animation(.spring(response: 0.5), value: pct)
                    }
                }
                .frame(height: 3)
                Text(sub)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.cardSurface)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.cardBorder, lineWidth: 1)))
    }
}
