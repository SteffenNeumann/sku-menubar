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
        // ISO 8601 calendar: week always starts on Monday
        var cal = Calendar(identifier: .iso8601)
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
            var gcal = Calendar(identifier: .gregorian)
            gcal.timeZone = TimeZone.current
            let startOfMonth = gcal.date(from: gcal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
            return (startOfMonth, now)
        case .lastMonth:
            var gcal = Calendar(identifier: .gregorian)
            gcal.timeZone = TimeZone.current
            let thisMonthStart = gcal.date(from: gcal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
            let lastMonthStart = gcal.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            let lastMonthEnd   = gcal.date(byAdding: .second, value: -1, to: thisMonthStart) ?? now
            return (lastMonthStart, lastMonthEnd)
        }
    }
}

// MARK: - TMetric API Models

// Actual structure returned by TMetric v3 timeentries endpoint
private struct TMetricTimeEntry: Codable {
    let id: Int?
    let startTime: String?
    let endTime: String?
    let project: TMetricEntryProject?   // nested directly in entry
}

private struct TMetricEntryProject: Codable {
    let id: Int?
    let name: String?
}

private struct TMetricMe: Codable {
    let id: Int?
}

// MARK: - Public Output

struct TMetricFetchResult {
    let summaries: [TMetricProjectSummary]
    let debugRaw:  String
}

struct TMetricProjectSummary: Identifiable, Equatable {
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

    // TMetric timestamps are local time without timezone offset
    private static let localFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.timeZone   = TimeZone.current
        return f
    }()

    // MARK: Helpers

    private static func get<T: Decodable>(_ path: String, token: String) async -> T? {
        guard let url = URL(string: "https://app.tmetric.com/api/v3/\(path)") else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",  forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        print("[TMetric GET] \(path) → HTTP \(status) (\(data.count)B): \(String(data: data.prefix(200), encoding: .utf8) ?? "")")
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Fetch current user ID

    static func fetchUserId(token: String) async -> Int? {
        let me: TMetricMe? = await get("users/me", token: token)
        print("[TMetric] userId=\(String(describing: me?.id))")
        return me?.id
    }

    // MARK: Timer control

    static func startTimer(token: String, projectId: Int) async throws {
        guard let url = URL(string: "https://app.tmetric.com/api/v3/accounts/\(accountId)/timer") else {
            throw TMetricError.badURL
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["projectId": projectId])
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            print("[TMetric] startTimer HTTP \(http.statusCode): \(body)")
            throw TMetricError.http(http.statusCode, body)
        }
    }

    static func stopTimer(token: String) async throws {
        guard let url = URL(string: "https://app.tmetric.com/api/v3/accounts/\(accountId)/timer") else {
            throw TMetricError.badURL
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw TMetricError.http(http.statusCode, "")
        }
    }

    // MARK: Main fetch

    static func fetchSummary(token: String, from: Date, to: Date) async throws -> TMetricFetchResult {
        let now = Date()

        let userId = await fetchUserId(token: token)

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

        print("[TMetric] GET \(url)")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            print("[TMetric] HTTP \(http.statusCode): \(String(data: data.prefix(300), encoding: .utf8) ?? "")")
            throw TMetricError.http(http.statusCode, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }

        let rawPreview = String(data: data.prefix(600), encoding: .utf8) ?? "<binary>"
        print("[TMetric] Raw (\(data.count)B): \(rawPreview)")

        let allEntries = (try? JSONDecoder().decode([TMetricTimeEntry].self, from: data)) ?? []
        print("[TMetric] Decoded \(allEntries.count) total entries")

        // Client-side date filter (server filter unreliable)
        let filtered = allEntries.filter { entry in
            guard let s = entry.startTime,
                  let d = localFmt.date(from: s) ?? ISO8601DateFormatter().date(from: s) else {
                return true
            }
            return d >= from && d <= to
        }
        print("[TMetric] After client filter [\(localFmt.string(from: from))…\(localFmt.string(from: to))]: \(filtered.count) entries")

        // Debug: show decoded project names
        let firstRaw: String
        let projectNames = Set(allEntries.compactMap { $0.project?.name }).sorted().prefix(5).joined(separator: ", ")
        firstRaw = "Total:\(allEntries.count) Filtered:\(filtered.count)\nProjekte: [\(projectNames)]"

        return TMetricFetchResult(
            summaries: aggregate(entries: filtered, now: now),
            debugRaw:  firstRaw
        )
    }

    // MARK: Aggregate by project

    private static func aggregate(entries: [TMetricTimeEntry], now: Date) -> [TMetricProjectSummary] {
        func parse(_ s: String?) -> Date? {
            guard let s else { return nil }
            return localFmt.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }

        var totals: [Int: (name: String, seconds: Int)] = [:]

        for entry in entries {
            let projectId   = entry.project?.id   ?? 0
            let projectName = entry.project?.name ?? (projectId == 0 ? "Ohne Projekt" : "Projekt \(projectId)")

            let seconds: Int
            if let s = parse(entry.startTime), let e = parse(entry.endTime) {
                seconds = max(0, Int(e.timeIntervalSince(s)))
            } else if let s = parse(entry.startTime), entry.endTime == nil {
                // Running timer
                seconds = max(0, Int(now.timeIntervalSince(s)))
            } else {
                continue
            }

            guard seconds > 0 else { continue }

            if var existing = totals[projectId] {
                existing.seconds += seconds
                totals[projectId] = existing
            } else {
                totals[projectId] = (name: projectName, seconds: seconds)
            }
        }

        return totals
            .map { id, v in TMetricProjectSummary(id: id, name: v.name, totalSeconds: v.seconds) }
            .sorted { $0.totalSeconds > $1.totalSeconds }
    }
}

// MARK: - Error

enum TMetricError: LocalizedError {
    case badURL
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL:             return "Ungültige TMetric URL"
        case .http(let c, let b): return "TMetric HTTP \(c)\(b.isEmpty ? "" : ": \(b.prefix(120))")"
        }
    }
}
