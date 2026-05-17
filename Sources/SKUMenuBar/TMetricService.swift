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

// MARK: - TMetric API Models

private struct TMetricTimeEntry: Codable {
    let id: Int?
    let startTime: String?
    let endTime: String?
    let duration: Int?          // seconds; -1 when timer is running
    // TMetric returns project info in different places depending on endpoint/version
    let details: TMetricDetails?
    // Flat fields (alternative response shape)
    let projectId: Int?
    let projectName: String?

    enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, duration, details, projectId, projectName
    }
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

// MARK: - Public Output Model

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

    static func fetchSummary(token: String, period: TMetricPeriod) async throws -> [TMetricProjectSummary] {
        let now = Date()
        let (from, to) = period.dateRange()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "https://app.tmetric.com/api/v3/accounts/\(accountId)/timeentries")!
        components.queryItems = [
            URLQueryItem(name: "startTime", value: formatter.string(from: from)),
            URLQueryItem(name: "endTime",   value: formatter.string(from: to))
        ]

        guard let url = components.url else { throw TMetricError.badURL }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw TMetricError.http(http.statusCode)
        }

        let entries: [TMetricTimeEntry]
        do {
            entries = try JSONDecoder().decode([TMetricTimeEntry].self, from: data)
        } catch {
            let preview = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
            print("[TMetric] Decode-Fehler: \(error)\nAntwort-Preview: \(preview)")
            throw error
        }
        // Debug: log first entry structure to console if entries exist
        if let first = entries.first {
            print("[TMetric] \(entries.count) Einträge. Erster: id=\(first.id ?? -1) projectId=\(String(describing: first.projectId)) details.projectId=\(String(describing: first.details?.projectId)) details.project.id=\(String(describing: first.details?.project?.id)) duration=\(String(describing: first.duration))")
        } else {
            print("[TMetric] Antwort enthält 0 Einträge für Zeitraum \(formatter.string(from: from))–\(formatter.string(from: to))")
        }
        return aggregate(entries: entries, now: now)
    }

    private static func aggregate(entries: [TMetricTimeEntry], now: Date) -> [TMetricProjectSummary] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]

        func parseDate(_ s: String?) -> Date? {
            guard let s else { return nil }
            return iso.date(from: s) ?? isoBasic.date(from: s)
        }

        var totals: [Int: (name: String, seconds: Int)] = [:]

        for entry in entries {
            // Resolve project ID + name from all known response shapes
            let projectId: Int   = entry.details?.project?.id
                                ?? entry.details?.projectId
                                ?? entry.projectId
                                ?? 0
            let projectName: String = entry.details?.project?.name
                                   ?? entry.details?.projectName
                                   ?? entry.projectName
                                   ?? "Ohne Projekt"

            let seconds: Int
            if let d = entry.duration, d >= 0 {
                seconds = d
            } else if let startStr = entry.startTime, let start = parseDate(startStr) {
                // Running timer — calculate live duration
                seconds = max(0, Int(now.timeIntervalSince(start)))
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
