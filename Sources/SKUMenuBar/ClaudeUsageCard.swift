import SwiftUI

/// Shows Claude API usage from Anthropic Admin API
/// (cost per day / week / month / year + token counts)
struct ClaudeUsageCard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    var body: some View {
        Group {
            if let err = state.claudeError {
                errorView(err)
            } else {
                mainView
            }
        }
        .padding(14)
        .mirrorCard()
        .onAppear {
            if state.claudeTodayCost == 0 && !state.claudeIsLoading
                && !state.settings.anthropicAdminKey.isEmpty {
                Task { await state.refreshClaude() }
            }
        }
    }

    // MARK: - Main view

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow.padding(.bottom, 12)

            // ── Cost grid ─────────────────────────────────────────────
            HStack(spacing: 0) {
                costCell(icon: "sun.max.fill",              color: .orange,
                         label: "Heute",  value: state.claudeTodayCost)
                Divider().frame(height: 40).opacity(0.2)
                costCell(icon: "calendar.badge.clock",      color: .blue,
                         label: "Woche",  value: state.claudeWeekCost)
                Divider().frame(height: 40).opacity(0.2)
                costCell(icon: "calendar",                  color: .indigo,
                         label: "Monat",  value: state.claudeMonthCost)
                Divider().frame(height: 40).opacity(0.2)
                costCell(icon: "chart.line.uptrend.xyaxis", color: .purple,
                         label: "Jahr",   value: state.claudeYearCost)
            }

            // ── Token row ─────────────────────────────────────────────
            if state.claudeMonthTokens > 0 {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.vertical, 10)

                HStack(spacing: 12) {
                    tokenPill(label: "Heute", tokens: state.claudeTodayTokens, color: .orange)
                    tokenPill(label: "Monat", tokens: state.claudeMonthTokens, color: .indigo)
                    Spacer()
                    Text("Tokens").font(.system(size: 9)).foregroundStyle(theme.tertiaryText)
                }
            }

        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [Color(hue: 0.76, saturation: 0.7, brightness: 0.9),
                                 Color(hue: 0.82, saturation: 0.65, brightness: 0.85)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Verbrauch")
                    .font(.system(size: 11, weight: .semibold))
                Text("Anthropic Admin API")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.tertiaryText)
            }
            Spacer()
            if state.claudeIsLoading {
                ProgressView().scaleEffect(0.6)
            } else {
                Button { Task { await state.refreshClaude(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 24, height: 24)
                        .background(.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Error view

    private func errorView(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.system(size: 11))
                Text(msg)
                    .font(.system(size: 10)).foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Cost Cell

    private func costCell(icon: String, color: Color, label: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
            Text(fmt(value))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Token Pill

    private func tokenPill(label: String, tokens: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(theme.tertiaryText)
            Text(fmtTokens(tokens))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }

    // MARK: - Helpers

    private func fmt(_ v: Double) -> String { state.fmt(v, decimals: 3) }

    private func fmtTokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000)
        : n >= 1_000   ? String(format: "%.1fK", Double(n) / 1_000)
        : "\(n)"
    }

}
