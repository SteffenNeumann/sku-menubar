import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published state
    @Published var todayCost:        Double = 0
    @Published var weekCost:         Double = 0
    @Published var monthCost:        Double = 0
    @Published var yearCost:         Double = 0
    @Published var dailyUsage:       [DailyUsage] = []
    @Published var isLoading:        Bool = false
    @Published var errorMsg:         String?
    @Published var lastUpdate:       Date?
    @Published var showSettings:     Bool = false
    @Published var showStats:        Bool = false
    @Published var historicalMonths: [MonthlyUsage] = []
    @Published var todayByProduct:  [String: Double] = [:]
    @Published var monthByProduct:  [String: Double] = [:]
    @Published var isLoadingHistory: Bool = false

    // MARK: - Claude / Anthropic state
    @Published var claudeTodayCost:  Double = 0
    @Published var claudeWeekCost:   Double = 0
    @Published var claudeMonthCost:  Double = 0
    @Published var claudeYearCost:   Double = 0
    @Published var claudeTodayTokens:  Int = 0
    @Published var claudeWeekTokens:   Int = 0
    @Published var claudeMonthTokens:  Int = 0
    @Published var claudeIsLoading:  Bool = false
    @Published var claudeError:      String?
    @Published var claudeLastUpdate: Date?

    // MARK: - Settings
    @Published var settings = GitHubSettings() {
        didSet { persist(); reschedule() }
    }

    // MARK: - Currency formatting
    var currencySymbol: String { settings.currency == "EUR" ? "€" : "$" }

    func fmt(_ usd: Double, decimals: Int = 2) -> String {
        let v = settings.currency == "EUR" ? usd * settings.eurRate : usd
        let spec = "%.\(decimals)f"
        return currencySymbol + String(format: spec, v)
    }

    // MARK: - Derived
    var remain:    Double { max(0, settings.budget - monthCost) }
    var monthPct:  Double { settings.budget > 0 ? min(1.0, monthCost / settings.budget) : 0 }
    var remainPct: Double { settings.budget > 0 ? remain / settings.budget : 1 }

    /// Weekly reference: budget / avg weeks per month
    var weekBudget: Double { settings.budget > 0 ? settings.budget / 4.33 : 0 }
    var weekPct:    Double { weekBudget > 0 ? min(1.0, weekCost / weekBudget) : 0 }

    // MARK: - Private
    private let service = GitHubService()
    // Use named suite so settings persist across binary vs .app bundle changes
    private let ud      = UserDefaults(suiteName: "SKUMenuBar") ?? .standard
    private let key     = "gh_sku_settings_v2"
    private var timer:  Timer?

    // MARK: - Init
    init() {
        load()
        reschedule()
        if !settings.token.isEmpty && !settings.name.isEmpty {
            Task { await refresh() }
        }
        if !settings.anthropicAdminKey.isEmpty && !settings.anthropicOrgId.isEmpty {
            Task { await refreshClaude() }
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

            // By-product for today
            var todayProd: [String: Double] = [:]
            for item in fetchedToday {
                let p = item.product ?? "Sonstige"
                todayProd[p, default: 0] += item.cost
            }
            todayByProduct = todayProd

            // By-product for month
            var monthProd: [String: Double] = [:]
            for item in fetchedMonth {
                let p = item.product ?? "Sonstige"
                monthProd[p, default: 0] += item.cost
            }
            monthByProduct = monthProd

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

            // Week cost: sum days in the current ISO week (Mon–today)
            weekCost = dailyUsage.filter { du in
                cal.isDate(du.date, equalTo: now, toGranularity: .weekOfYear)
            }.reduce(0) { $0 + $1.amount }

            lastUpdate = now

            // Year cost in background (non-blocking)
            let _y = y; let _m = m
            Task { await self.fetchYearCost(year: _y, upToMonth: _m) }

        } catch {
            errorMsg = "GitHub: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - History fetch (for Statistics view)

    func loadHistory(year: Int) async {
        guard !settings.token.isEmpty, !settings.name.isEmpty else { return }

        isLoadingHistory = true
        historicalMonths = []

        let token       = settings.token
        let accountType = settings.accountType
        let name        = settings.name
        let product     = settings.product.isEmpty ? nil : settings.product

        let cal          = Calendar.current
        let currentYear  = cal.component(.year,  from: Date())
        let currentMonth = cal.component(.month, from: Date())
        let maxMonth     = (year == currentYear) ? currentMonth : 12

        var results: [MonthlyUsage] = []

        await withTaskGroup(of: MonthlyUsage.self) { group in
            for m in 1...maxMonth {
                group.addTask {
                    do {
                        let items = try await GitHubService().fetchUsage(
                            token: token, accountType: accountType,
                            name: name, product: product,
                            year: year, month: m
                        )
                        let total = items.reduce(0) { $0 + $1.cost }
                        var byProduct: [String: Double] = [:]
                        var byDay:     [String: Double] = [:]
                        func dk(_ raw: String) -> String { String(raw.prefix(10)) }
                        for item in items {
                            let p = item.product ?? "Sonstige"
                            byProduct[p, default: 0] += item.cost
                            if let ds = item.date { byDay[dk(ds), default: 0] += item.cost }
                        }
                        return MonthlyUsage(
                            id: "\(year)-\(String(format: "%02d", m))",
                            year: year, month: m,
                            total: total, byProduct: byProduct, byDay: byDay
                        )
                    } catch {
                        return MonthlyUsage(
                            id: "\(year)-\(String(format: "%02d", m))",
                            year: year, month: m,
                            total: 0, byProduct: [:], byDay: [:]
                        )
                    }
                }
            }
            for await result in group {
                results.append(result)
            }
        }

        historicalMonths = results.sorted { $0.month < $1.month }
        isLoadingHistory = false
    }

    // MARK: - Year cost (background, non-blocking)

    private func fetchYearCost(year: Int, upToMonth: Int) async {
        guard !settings.token.isEmpty, !settings.name.isEmpty else { return }
        let tok = settings.token
        let at  = settings.accountType
        let n   = settings.name
        let p   = settings.product.isEmpty ? nil : settings.product

        var total = 0.0
        await withTaskGroup(of: Double.self) { group in
            for m in 1...upToMonth {
                group.addTask {
                    let items = try? await GitHubService().fetchUsage(
                        token: tok, accountType: at, name: n, product: p,
                        year: year, month: m
                    )
                    return items?.reduce(0) { $0 + $1.cost } ?? 0
                }
            }
            for await v in group { total += v }
        }
        yearCost = total
    }

    // MARK: - Claude usage fetch

    func refreshClaude(force: Bool = false) async {
        let key   = settings.anthropicAdminKey
        let orgId = settings.anthropicOrgId
        guard !key.isEmpty, !orgId.isEmpty else {
            claudeError = "Anthropic Admin Key und Org-ID in Einstellungen eintragen"
            return
        }
        // Rate-limit guard: max once per 15 minutes (Anthropic Admin API limit)
        if let last = claudeLastUpdate, Date().timeIntervalSince(last) < 900, !force {
            return
        }

        claudeIsLoading = true
        claudeError     = nil

        let svc = AnthropicService()
        let now = Date()

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!

        let startOfDay   = utcCal.startOfDay(for: now)
        let endNow       = now   // API only accepts past timestamps as ending_at
        // Claude weekly limits reset on Tuesdays – find the most recent Tuesday (UTC)
        let weekday = utcCal.component(.weekday, from: now) // 1=Sun 2=Mon 3=Tue...
        let daysFromTuesday = (weekday - 3 + 7) % 7
        let startOfWeek  = utcCal.date(byAdding: .day, value: -daysFromTuesday, to: startOfDay) ?? startOfDay
        let startOfMonth = utcCal.date(from: utcCal.dateComponents([.year, .month], from: now)) ?? startOfDay
        let startOfYear  = utcCal.date(from: utcCal.dateComponents([.year], from: now)) ?? startOfDay

        // Use usage_report for both cost (costUsd) and token counts –
        // avoids the cost_report endpoint which rejects same-day date ranges.
        do {
            async let uToday = svc.fetchUsage(adminKey: key, start: startOfDay,   end: endNow, bucketWidth: "1h")
            async let uWeek  = svc.fetchUsage(adminKey: key, start: startOfWeek,  end: endNow, bucketWidth: "1d")
            async let uMonth = svc.fetchUsage(adminKey: key, start: startOfMonth, end: endNow, bucketWidth: "1d")
            async let uYear  = svc.fetchUsage(adminKey: key, start: startOfYear,  end: endNow, bucketWidth: "1d")

            let (today, week, month, year) = try await (uToday, uWeek, uMonth, uYear)

            func cost(_ buckets: [AnthropicUsageBucket]) -> Double {
                buckets.flatMap { $0.results ?? [] }.map(\.estimatedCostUsd).reduce(0, +)
            }
            func tokens(_ buckets: [AnthropicUsageBucket]) -> Int {
                buckets.map(\.totalTokens).reduce(0, +)
            }

            claudeTodayCost   = cost(today)
            claudeWeekCost    = cost(week)
            claudeMonthCost   = cost(month)
            claudeYearCost    = cost(year)
            claudeTodayTokens = tokens(today)
            claudeWeekTokens  = tokens(week)
            claudeMonthTokens = tokens(month)

        } catch {
            claudeError = "Anthropic: \(error.localizedDescription)"
        }

        claudeLastUpdate = Date()
        claudeIsLoading = false
    }
}
