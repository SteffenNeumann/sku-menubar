import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state
    @Published var todayCost:   Double = 0
    @Published var monthCost:   Double = 0
    @Published var dailyUsage:  [DailyUsage] = []
    @Published var isLoading:   Bool = false
    @Published var errorMsg:    String?
    @Published var lastUpdate:  Date?
    @Published var showSettings: Bool = false

    // MARK: - Settings
    @Published var settings = GitHubSettings() {
        didSet { persist(); reschedule() }
    }

    // MARK: - Derived
    var remain:    Double { max(0, settings.budget - monthCost) }
    var monthPct:  Double { settings.budget > 0 ? min(1.0, monthCost / settings.budget) : 0 }
    var remainPct: Double { settings.budget > 0 ? remain / settings.budget : 1 }

    // MARK: - Private
    private let service = GitHubService()
    private let ud      = UserDefaults.standard
    private let key     = "gh_sku_settings_v2"
    private var timer:  Timer?

    // MARK: - Init
    init() {
        load()
        reschedule()
        if !settings.token.isEmpty && !settings.name.isEmpty {
            Task { await refresh() }
        }
    }

    // MARK: - Persistence
    private func load() {
        guard
            let d = ud.data(forKey: key),
            let s = try? JSONDecoder().decode(GitHubSettings.self, from: d)
        else { return }
        settings = s
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(settings) {
            ud.set(d, forKey: key)
        }
    }

    // MARK: - Timer
    private func reschedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: Double(settings.intervalSeconds),
            repeats: true
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    // MARK: - Data fetch
    func refresh() async {
        guard !settings.token.isEmpty, !settings.name.isEmpty else {
            errorMsg = "Token und Username in Einstellungen eintragen"
            return
        }

        isLoading = true
        errorMsg  = nil

        do {
            let now  = Date()
            let cal  = Calendar.current
            let y    = cal.component(.year,  from: now)
            let m    = cal.component(.month, from: now)
            let dom  = cal.component(.day,   from: now)

            let prod = settings.product.isEmpty ? nil : settings.product

            // Parallel: separate today-call (day=) + full month (für Grid + Monatssumme)
            async let todayItems = service.fetchUsage(
                token: settings.token, accountType: settings.accountType,
                name: settings.name, product: prod,
                year: y, month: m, day: dom
            )
            async let monthItems = service.fetchUsage(
                token: settings.token, accountType: settings.accountType,
                name: settings.name, product: prod,
                year: y, month: m
            )
            let (fetchedToday, fetchedMonth) = try await (todayItems, monthItems)


            // Today: direkt aus dem day=-Call summieren (identisch zur HTML-Version)
            todayCost = fetchedToday.reduce(0) { $0 + $1.cost }

            // Monat: aus dem Monats-Call
            monthCost = fetchedMonth.reduce(0) { $0 + $1.cost }

            // Habit-Grid: Monats-Items nach Datum gruppieren
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"

            // Datum normalisieren: API liefert ggf. "2026-03-04T00:00:00Z" → nur "2026-03-04"
            func dateKey(_ raw: String) -> String { String(raw.prefix(10)) }

            var byDate: [String: Double] = [:]
            for item in fetchedMonth {
                guard let ds = item.date else { continue }
                byDate[dateKey(ds), default: 0] += item.cost
            }

            // Vormonat nachladen wenn wir noch < 28 Tage im Monat sind
            if dom < 28 {
                let py = m == 1 ? y - 1 : y
                let pm = m == 1 ? 12 : m - 1
                if let prev = try? await service.fetchUsage(
                    token: settings.token, accountType: settings.accountType,
                    name: settings.name, product: prod,
                    year: py, month: pm
                ) {
                    for item in prev {
                        guard let ds = item.date else { continue }
                        byDate[dateKey(ds), default: 0] += item.cost
                    }
                }
            }

            // Build last 28 days for habit grid (oldest → newest)
            dailyUsage = (0..<28).reversed().compactMap { offset -> DailyUsage? in
                guard let d = cal.date(byAdding: .day, value: -offset, to: now) else { return nil }
                let k = df.string(from: d)
                return DailyUsage(id: k, date: d, amount: byDate[k] ?? 0)
            }

            lastUpdate = now

        } catch {
            errorMsg = error.localizedDescription
        }

        isLoading = false
    }
}
