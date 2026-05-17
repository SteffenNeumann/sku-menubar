import Foundation

// MARK: - Time Period

enum TMetricPeriod: String, CaseIterable, Codable {
    case today     = "today"
    case thisWeek  = "thisWeek"
    case thisMonth = "thisMonth"
    case lastMonth = "lastMonth"

    var label: String {
        switch self {
        case .today:     return "Heute"
        case .thisWeek:  return "Woche"
        case .thisMonth: return "Monat"
        case .lastMonth: return "Vormonat"
        }
    }

    var emptyText: String {
        switch self {
        case .today:     return "Heute noch keine Zeit gebucht."
        case .thisWeek:  return "Diese Woche noch keine Zeit gebucht."
        case .thisMonth: return "Diesen Monat noch keine Zeit gebucht."
        case .lastMonth: return "Im Vormonat keine Zeit gefunden."
        }
    }

    func dateRange() -> (from: Date, to: Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let now = Date()
        switch self {
        case .today:
            return (cal.startOfDay(for: now), now)
        case .thisWeek:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            let startOfWeek = cal.date(from: comps) ?? cal.startOfDay(for: now)
            return (startOfWeek, now)
        case .thisMonth:
            let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
            return (startOfMonth, now)
        case .lastMonth:
            let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
            let lastMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            let lastMonthEnd   = cal.date(byAdding: .second, value: -1, to: thisMonthStart) ?? now
            return (lastMonthStart, lastMonthEnd)
        }
    }
}

// MARK: - TMetric API Models (flexible — handles multiple response shapes)

// We use AnyCodable-style decoding via a custom init so unknown keys don't break parsing
private struct TMetricTimeEntry: Codable {
    let id: Int?
    let startTime: String?
    let endTime: String?
    let duration: Int?
    let details: TMetricDetails?
    // flat fallbacks
    let projectId: Int?
    let projectName: String?
}

private struct TMetricDetails: Codable {
    let projectId: Int?
    let projectName: String?
    let project: TMetricProject?
}

private struct TMetricProject: Codable {
    let id: Int?
    let name: String?
}

private struct TMetricMe: Codable {
    let id: Int?
}

// MARK: - Public Output

struct TMetricFetchResult {
    let summaries: [TMetricProjectSummary]
    let debugRaw:  String   // first raw entry for diagnosis
}

struct TMetricProjectSummary: Identifiable {
    let id: Int
    let name: String
    var totalSeconds: Int

    var formattedDuration: String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Service

enum TMetricService {
    static let accountId = 276655

    // TMetric stores timestamps as local time without timezone
    private static let localFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.timeZone   = TimeZone.current
        return f
    }()

    // MARK: Fetch userId

    private static func fetchUserId(token: String) async -> Int? {
        guard let url = URL(string: "https://app.tmetric.com/api/v3/users/me") else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",  forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        let uid = (try? JSONDecoder().decode(TMetricMe.self, from: data))?.id
        print("[TMetric] /users/me → id=\(String(describing: uid))")
        return uid
    }

    // MARK: Main fetch

    static func fetchSummary(token: String, period: TMetricPeriod) async throws -> TMetricFetchResult {
        let now = Date()
        let (from, to) = period.dateRange()

        let userId = await fetchUserId(token: token)

        // Send both the server-side filter params AND filter client-side as fallback
        var items: [URLQueryItem] = [
            URLQueryItem(name: "startTime", value: localFmt.string(from: from)),
            URLQueryItem(name: "endTime",   value: localFmt.string(from: to))
        ]
        if let uid = userId {
            items.append(URLQueryItem(name: "userIds", value: "\(uid)"))
        }

        var components = URLComponents(string: "https://app.tmetric.com/api/v3/accounts/\(accountId)/timeentries")!
        components.queryItems = items
        guard let url = components.url else { throw TMetricError.badURL }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        print("[TMetric] GET \(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            print("[TMetric] HTTP \(http.statusCode): \(String(data: data.prefix(300), encoding: .utf8) ?? "")")
            throw TMetricError.http(http.statusCode)
        }

        let rawPreview = String(data: data.prefix(800), encoding: .utf8) ?? "<binary>"
        print("[TMetric] Raw (\(data.count)B): \(rawPreview)")

        let decoder = JSONDecoder()
        let allEntries: [TMetricTimeEntry]
        if let arr = try? decoder.decode([TMetricTimeEntry].self, from: data) {
            allEntries = arr
        } else {
            allEntries = try decoder.decode([TMetricTimeEntry].self, from: data)
        }

        print("[TMetric] Total decoded: \(allEntries.count) — now filtering client-side to [\(localFmt.string(from: from)), \(localFmt.string(from: to))]")

        // Client-side date filter: keep only entries whose startTime falls within the period
        let filtered = allEntries.filter { entry in
            guard let s = entry.startTime, let entryStart = localFmt.date(from: s) ?? ISO8601DateFormatter().date(from: s) else {
                return true // keep if we can't parse (fail-open)
            }
            return entryStart >= from && entryStart <= to
        }

        print("[TMetric] After client filter: \(filtered.count) entries")

        // Build debug string from first raw entry
        let debugRaw: String
        if let first = allEntries.first,
           let d = try? JSONEncoder().encode(first),
           let s = String(data: d, encoding: .utf8) {
            debugRaw = "Total:\(allEntries.count) Filtered:\(filtered.count)\nErster Eintrag: \(s)"
        } else {
            debugRaw = "0 Einträge vom Server"
        }

        return TMetricFetchResult(summaries: aggregate(entries: filtered, now: now), debugRaw: debugRaw)
    }

    // MARK: Aggregate by project

    private static func aggregate(entries: [TMetricTimeEntry], now: Date) -> [TMetricProjectSummary] {
        func parse(_ s: String?) -> Date? {
            guard let s else { return nil }
            return localFmt.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }

        var totals: [Int: (name: String, seconds: Int)] = [:]

        for entry in entries {
            let projectId: Int = entry.details?.project?.id
                              ?? entry.details?.projectId
                              ?? entry.projectId
                              ?? 0
            let projectName: String = entry.details?.project?.name
                                   ?? entry.details?.projectName
                                   ?? entry.projectName
                                   ?? "Ohne Projekt"

            let dur = entry.duration ?? -1
            let seconds: Int
            if dur > 0 {
                seconds = dur
            } else if let s = parse(entry.startTime), let e = parse(entry.endTime) {
                seconds = max(0, Int(e.timeIntervalSince(s)))
            } else if let s = parse(entry.startTime), entry.endTime == nil {
                seconds = max(0, Int(now.timeIntervalSince(s)))
            } else {
                continue
            }

            if var existing = totals[projectId] {
                existing.seconds += seconds
                totals[projectId] = existing
            } else {
                totals[projectId] = (name: projectName, seconds: seconds)
            }
        }

        return totals
            .map { id, v in TMetricProjectSummary(id: id, name: v.name, totalSeconds: v.seconds) }
            .filter { $0.totalSeconds > 0 }
            .sorted { $0.totalSeconds > $1.totalSeconds }
    }
}

// MARK: - Error

enum TMetricError: LocalizedError {
    case badURL
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .badURL:      return "Ungültige TMetric URL"
        case .http(let c): return "TMetric API Fehler (HTTP \(c))"
        }
    }
}
