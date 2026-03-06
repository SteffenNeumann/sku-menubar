import SwiftUI

/// 28-day contribution-style grid (4 weeks × 7 days).
struct HabitGridView: View {
    let days: [DailyUsage]

    @State private var hoveredId: String?

    private var maxAmount: Double { days.map(\.amount).max() ?? 0 }
    private let cellSize: CGFloat = 38
    private let cols = Array(repeating: GridItem(.fixed(38), spacing: 4), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack {
                Text("Letzte 28 Tage")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                if maxAmount > 0 {
                    Text("Max €\(String(format: "%.2f", maxAmount))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(days) { day in
                    cell(day)
                }
            }

            // Legende
            HStack(spacing: 4) {
                Text("weniger")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                ForEach([0.07, 0.25, 0.5, 0.75, 1.0], id: \.self) { v in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(cellColor(v))
                        .frame(width: 12, height: 12)
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
            // Hintergrundfarbe
            RoundedRectangle(cornerRadius: 5)
                .fill(cellColor(intensity))

            // Rahmen
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(
                    isToday ? Color.accentColor : Color.white.opacity(0.12),
                    lineWidth: isToday ? 1.5 : 0.5
                )

            // Text-Overlay: sanft eingeblendet beim Hover
            VStack(spacing: 2) {
                Text(day.shortLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                Text(day.amount > 0
                     ? String(format: "€%.2f", day.amount)
                     : "–")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.5), radius: 2)
            .opacity(isHovered ? 1 : 0)
            .scaleEffect(isHovered ? 1 : 0.6)
            .blur(radius: isHovered ? 0 : 3)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isHovered)
        }
        .frame(width: cellSize, height: cellSize)
        .onHover { over in
            hoveredId = over ? day.id : nil
        }
    }

    // MARK: - Color

    private func cellColor(_ intensity: Double) -> Color {
        guard intensity > 0 else { return Color.primary.opacity(0.08) }
        return Color(hue: 0.38,
                     saturation: 0.55 + intensity * 0.35,
                     brightness: 0.35 + intensity * 0.45)
    }
}
