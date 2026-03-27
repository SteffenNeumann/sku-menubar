import SwiftUI

/// 28-day contribution-style heat map grid (4 weeks × 7 days).
struct HabitGridView: View {
    let days: [DailyUsage]
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    @State private var hoveredId: String?

    private var maxAmount: Double { days.map(\.amount).max() ?? 0 }
    private var total28: Double { days.reduce(0) { $0 + $1.amount } }

    // Fixed layout constants
    private let rows = 4
    private let cols = 7
    private let cellSpacing: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let headerH:  CGFloat = 28
            let legendH:  CGFloat = 16
            let vGaps:    CGFloat = CGFloat(rows - 1) * cellSpacing
            let hGaps:    CGFloat = CGFloat(cols - 1) * cellSpacing
            let gridH     = geo.size.height - headerH - legendH - 16 // 8+8 spacing
            let cellH     = max(10, (gridH - vGaps) / CGFloat(rows))
            let cellW     = (geo.size.width - hGaps) / CGFloat(cols)
            let cellSize  = min(cellH, cellW)

            VStack(alignment: .leading, spacing: 8) {
                // ── Header ──────────────────────────────────────────
                HStack {
                    Label("Letzte 28 Tage", systemImage: "chart.bar.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(fmt(total28))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.primaryText)
                        Text("Gesamt")
                            .font(.system(size: 9))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
                .frame(height: headerH)

                // ── Grid ────────────────────────────────────────────
                VStack(spacing: cellSpacing) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: cellSpacing) {
                            ForEach(0..<cols, id: \.self) { col in
                                let idx = row * cols + col
                                if idx < days.count {
                                    cell(days[idx])
                                        .frame(width: cellSize, height: cellSize)
                                } else {
                                    Color.clear
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }
                }

                // ── Legend ──────────────────────────────────────────
                HStack(spacing: 5) {
                    Text("weniger")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText)
                    ForEach([0.07, 0.25, 0.5, 0.75, 1.0], id: \.self) { v in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(cellColor(v))
                            .frame(width: 8, height: 8)
                    }
                    Text("mehr")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText)
                    Spacer()
                }
                .frame(height: legendH)
            }
        }
    }

    // MARK: - Cell

    @ViewBuilder
    private func cell(_ day: DailyUsage) -> some View {
        let intensity = maxAmount > 0 ? day.amount / maxAmount : 0.0
        let isToday   = Calendar.current.isDateInToday(day.date)
        let isHovered = hoveredId == day.id

        ZStack {
            // Base fill
            RoundedRectangle(cornerRadius: 6)
                .fill(cellColor(intensity))
                .shadow(
                    color: intensity > 0.5 ? cellColor(intensity).opacity(0.4) : .clear,
                    radius: isHovered ? 5 : 2, y: 1
                )

            // Border
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isToday
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color.white.opacity(0.12)),
                    lineWidth: isToday ? 1.5 : 0.5
                )

            // Hover overlay with blur glass + text
            if isHovered {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.black.opacity(0.35))

                VStack(spacing: 2) {
                    Text(day.shortLabel)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(day.amount > 0 ? fmt(day.amount) : "-")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
        .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
        .scaleEffect(isHovered ? 1.12 : 1.0)
        .zIndex(isHovered ? 1 : 0)
        .animation(.spring(response: 0.2, dampingFraction: 0.68), value: isHovered)
        .onHover { over in
            hoveredId = over ? day.id : nil
        }
    }

    // MARK: - Color

    private func cellColor(_ intensity: Double) -> Color {
        guard intensity > 0 else {
            return Color.primary.opacity(0.07)
        }
        // Green-teal gradient: low saturation + dark → high saturation + bright
        return Color(
            hue:        0.38,
            saturation: 0.45 + intensity * 0.45,
            brightness: 0.30 + intensity * 0.52
        )
    }

    private func fmt(_ v: Double) -> String { state.fmt(v) }
}
