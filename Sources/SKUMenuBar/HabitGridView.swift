import SwiftUI

/// 28-day contribution-style heat map grid (4 weeks × 7 days).
struct HabitGridView: View {
    let days: [DailyUsage]
    @EnvironmentObject var state: AppState

    @State private var hoveredId: String?

    private var maxAmount: Double { days.map(\.amount).max() ?? 0 }
    private var total28: Double { days.reduce(0) { $0 + $1.amount } }

    // Cell size tuned for 308 px available width inside the glass card
    // (360 window – 24 outer padding – 28 card padding = 308)
    // 7 × 40 + 6 × 4 = 304  ✓
    private let cellSize: CGFloat = 40
    private let cols = Array(repeating: GridItem(.fixed(40), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── Header ─────────────────────────────────────────────
            HStack {
                Label("Letzte 28 Tage", systemImage: "chart.bar.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(fmt(total28))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Gesamt")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            // ── Grid ───────────────────────────────────────────────
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(days) { day in
                    cell(day)
                }
            }

            // ── Legend ─────────────────────────────────────────────
            HStack(spacing: 5) {
                Text("weniger")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                ForEach([0.07, 0.25, 0.5, 0.75, 1.0], id: \.self) { v in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(cellColor(v))
                        .frame(width: 10, height: 10)
                }
                Text("mehr")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer()
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
        .frame(width: cellSize, height: cellSize)
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
