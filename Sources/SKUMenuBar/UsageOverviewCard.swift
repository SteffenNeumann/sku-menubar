import SwiftUI

/// Mirrors the layout of claude.ai/settings/usage:
/// Current Session (Today) · Weekly Limits · Day / Month / Year totals
struct UsageOverviewCard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    // MARK: - Derived

    private var claudeMode: Bool {
        state.settings.claudeWeeklyTokenLimit > 0
    }

    // GitHub mode
    private var dailyBudget: Double {
        guard state.settings.budget > 0 else { return 0 }
        let days = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
        return state.settings.budget / Double(days)
    }
    private var todayPct:   Double { dailyBudget > 0 ? min(1, state.todayCost / dailyBudget) : 0 }
    private var weekPct:    Double { state.weekPct }
    private var weekBudget: Double { state.weekBudget }

    // Claude mode – weekly is token-based
    private var claudeWeeklyTokenLimit: Int    { state.settings.claudeWeeklyTokenLimit }
    private var claudeWeekTokenPct:     Double { state.claudeWeekTokenPct }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Title ────────────────────────────────────────────────
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.yellow)
                Text("Verbrauchsübersicht")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if claudeMode {
                    Text("Claude")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.purple.opacity(0.8))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.purple.opacity(0.12), in: Capsule())
                }
            }

            // ── Current Session (Today) ───────────────────────────────
            usageRow(
                label:  "Heute",
                icon:   "sun.max.fill",
                tint:   .orange,
                amount: state.todayCost,
                limit:  dailyBudget,
                pct:    todayPct
            )

            // ── Weekly Limits (Token-based) ───────────────────────────
            if claudeMode {
                tokenRow(
                    label:  "Diese Woche (Di–Mo)",
                    icon:   "calendar.badge.clock",
                    tint:   .blue,
                    used:   state.claudeWeekTokens,
                    limit:  claudeWeeklyTokenLimit,
                    pct:    claudeWeekTokenPct
                )
            } else {
                usageRow(
                    label:  "Diese Woche (Di–Mo)",
                    icon:   "calendar.badge.clock",
                    tint:   .blue,
                    amount: state.weekCost,
                    limit:  weekBudget,
                    pct:    weekPct
                )
            }

        }
        .padding(14)
        .mirrorCard()
    }

    // MARK: - Usage Row (label + amount + bar + limit)

    private func usageRow(
        label: String, icon: String, tint: Color,
        amount: Double, limit: Double, pct: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Text(fmt(amount))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [barTint(pct, tint).opacity(0.65), barTint(pct, tint)],
                            startPoint: .leading,
                            endPoint:   .trailing
                        ))
                        .frame(width: geo.size.width * max(0, min(1, pct)))
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: pct)
                }
            }
            .frame(height: 5)

            HStack {
                if limit > 0 {
                    Text("Limit \(fmt(limit))  ·  verbleibend \(fmt(max(0, limit - amount)))")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                } else {
                    Text("Kein Limit konfiguriert")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(barTint(pct, tint).opacity(0.85))
            }
        }
    }

    // MARK: - Token Row

    private func tokenRow(
        label: String, icon: String, tint: Color,
        used: Int, limit: Int, pct: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Text(fmtTok(used))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.primaryText)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [barTint(pct, tint).opacity(0.65), barTint(pct, tint)],
                            startPoint: .leading,
                            endPoint:   .trailing
                        ))
                        .frame(width: geo.size.width * max(0, min(1, pct)))
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: pct)
                }
            }
            .frame(height: 5)

            HStack {
                if limit > 0 {
                    Text("Limit \(fmtTok(limit))  ·  verbleibend \(fmtTok(max(0, limit - used)))")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                } else {
                    Text("Kein Limit konfiguriert")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer()
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(barTint(pct, tint).opacity(0.85))
            }
        }
    }

    // MARK: - Helpers

    private func fmt(_ v: Double) -> String { state.fmt(v) }

    private func fmtTok(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM tok", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.0fK tok", Double(n) / 1_000) }
        return "\(n) tok"
    }

    private func barTint(_ pct: Double, _ base: Color) -> Color {
        pct > 0.9 ? .red : pct > 0.75 ? .orange : base
    }
}
