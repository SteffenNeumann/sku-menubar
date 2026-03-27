import SwiftUI

/// Shows costs broken down by GitHub billing product (Copilot, Actions, etc.)
/// with individual subtotals, a progress bar and a grand total.
struct SourceBreakdownCard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme

    enum Period { case today, month }
    var period: Period = .month

    private var data: [String: Double] {
        var d = period == .today ? state.todayByProduct : state.monthByProduct
        // Add Claude/Anthropic costs as a virtual product
        let claudeCost = period == .today ? state.claudeTodayCost : state.claudeMonthCost
        if claudeCost > 0 { d["__claude__"] = claudeCost }
        return d
    }

    private var total: Double { data.values.reduce(0, +) }

    private var sorted: [(product: String, amount: Double)] {
        data.map { (product: $0.key, amount: $0.value) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }

    // MARK: - Product metadata

    private func icon(for product: String) -> String {
        switch product {
        case "__claude__":                         return "sparkles"
        default: switch product.lowercased() {
        case let p where p.contains("copilot"):    return "person.fill.checkmark"
        case let p where p.contains("action"):     return "bolt.fill"
        case let p where p.contains("package"):    return "shippingbox.fill"
        case let p where p.contains("codespace"):  return "desktopcomputer"
        case let p where p.contains("storage"):    return "internaldrive.fill"
        case let p where p.contains("lfs"):        return "cylinder.split.1x2.fill"
        default:                                   return "square.grid.2x2.fill"
        }}
    }

    private func color(for product: String) -> Color {
        switch product {
        case "__claude__":                         return .purple
        default: switch product.lowercased() {
        case let p where p.contains("copilot"):    return .blue
        case let p where p.contains("action"):     return .orange
        case let p where p.contains("package"):    return .teal
        case let p where p.contains("codespace"):  return .cyan
        case let p where p.contains("storage"):    return .green
        case let p where p.contains("lfs"):        return .mint
        default:                                   return .secondary
        }}
    }

    private func displayName(for product: String) -> String {
        switch product {
        case "__claude__":                         return "Claude (Anthropic API)"
        default: switch product.lowercased() {
        case let p where p.contains("copilot"):    return "GitHub Copilot"
        case let p where p.contains("action"):     return "GitHub Actions"
        case let p where p.contains("package"):    return "Packages"
        case let p where p.contains("codespace"):  return "Codespaces"
        case let p where p.contains("storage"):    return "Storage"
        case let p where p.contains("lfs"):        return "Git LFS"
        default:                                   return product
        }}
    }

    private func subtitle(for product: String) -> String {
        switch product {
        case "__claude__": return "anthropic admin api"
        default:           return product
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Title row
            HStack(spacing: 6) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                Text(period == .today ? "Quellen \u{2013} Heute" : "Quellen \u{2013} Dieser Monat")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if state.isLoading {
                    ProgressView().scaleEffect(0.55)
                }
            }
            .padding(.bottom, 12)

            if sorted.isEmpty {
                Text(state.isLoading ? "Wird geladen\u{2026}" : "Keine Daten")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(sorted, id: \.product) { entry in
                        productRow(entry.product, amount: entry.amount)
                    }
                }

                // Divider + grand total
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 0.5)
                    .padding(.vertical, 10)

                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "sum")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.secondaryText)
                        Text("Gesamt")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                    Spacer()
                    Text(fmt(total))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                }
            }
        }
        .padding(14)
        .mirrorCard()
    }

    // MARK: - Product Row

    private func productRow(_ product: String, amount: Double) -> some View {
        let pct   = total > 0 ? amount / total : 0
        let clr   = color(for: product)

        return VStack(spacing: 5) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(clr.opacity(0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon(for: product))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(clr)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayName(for: product))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(subtitle(for: product))
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(fmt(amount))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.primaryText)
                    if sorted.count > 1 {
                        Text("\(Int(pct * 100))%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(clr.opacity(0.85))
                    }
                }
            }

            // Progress bar — only useful with multiple products
            if sorted.count > 1 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [clr.opacity(0.55), clr.opacity(0.9)],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * max(0, min(1, pct)))
                            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: pct)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private func fmt(_ v: Double) -> String { state.fmt(v) }
}
