import Foundation

// MARK: - TMetric API Models

private struct TMetricTimeEntry: Codable {
    let id: Int?
    let startTime: String?
    let endTime: String?
    let duration: Int?          // seconds; -1 when timer is running
    let details: TMetricDetails?

    enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, duration, details
    }
}

private struct TMetricDetails: Codable {
    let projectId: Int?
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

    static func fetchTodaySummary(token: String) async throws -> [TMetricProjectSummary] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let startStr = formatter.string(from: startOfDay)
        let endStr   = formatter.string(from: now)

        var components = URLComponents(string: "https://app.tmetric.com/api/v3/accounts/\(accountId)/timeentries")!
        components.queryItems = [
            URLQueryItem(name: "startTime", value: startStr),
            URLQueryItem(name: "endTime",   value: endStr)
        ]

        guard let url = components.url else { throw TMetricError.badURL }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw TMetricError.http(http.statusCode)
        }

        let entries = try JSONDecoder().decode([TMetricTimeEntry].self, from: data)
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
            let projectId   = entry.details?.project?.id ?? entry.details?.projectId ?? 0
            let projectName = entry.details?.project?.name ?? "Ohne Projekt"

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
