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
    let userId: Int?
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
    let userId:    Int?
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
        NSLog("[TMetric GET] \(path) → HTTP \(status) (\(data.count)B): \(String(data: data.prefix(200), encoding: .utf8) ?? "")")
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Fetch current user ID

    static func fetchUserId(token: String) async -> Int? {
        let me: TMetricMe? = await get("users/me", token: token)
        NSLog("[TMetric] userId=\(String(describing: me?.id))")
        return me?.id
    }

    // MARK: Timer control

    /// Returns (entryId, userId) — userId ist aus der API-Antwort, damit wir ihn cachen können.
    static func startTimer(token: String, projectId: Int, userId: Int? = nil) async throws -> (entryId: Int?, userId: Int?) {
        let startStr = localFmt.string(from: Date())
        let base = "https://app.tmetric.com/api/v3/accounts/\(accountId)/timeentries"

        let bodies: [[String: Any]] = userId.map {
            [["startTime": startStr, "userId": $0, "project": ["id": projectId]],
             ["startTime": startStr, "project": ["id": projectId]]]
        } ?? [["startTime": startStr, "project": ["id": projectId]]]

        var lastError = "Kein Versuch"
        for bodyDict in bodies {
            guard let url = URL(string: base) else { continue }
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let bodyStr = String(data: data.prefix(500), encoding: .utf8) ?? ""
            NSLog("[TMetric] POST /timeentries → HTTP \(status): \(bodyStr)")
            if (200...299).contains(status) {
                let json = try? JSONSerialization.jsonObject(with: data)
                let dict = (json as? [String: Any]) ?? (json as? [[String: Any]])?.first
                if let dict = dict {
                    let entryId     = dict["id"]     as? Int
                    let returnedUid = dict["userId"] as? Int
                    NSLog("[TMetric] started entryId=\(String(describing: entryId)) userId=\(String(describing: returnedUid))")
                    return (entryId: entryId, userId: returnedUid)
                }
            }
            lastError = "HTTP \(status): \(bodyStr.prefix(120))"
        }
        throw TMetricError.http(0, lastError)
    }

    // MARK: GET current running timer

    /// Asks TMetric which entry is currently running via GET /timer.
    /// Returns (entryId, rawDict) or nil when no timer is active (404).
    static func fetchCurrentTimer(token: String, userId: Int?) async -> (id: Int, raw: [String: Any])? {
        var comps = URLComponents(string: "https://app.tmetric.com/api/v3/accounts/\(accountId)/timer")!
        if let uid = userId { comps.queryItems = [URLQueryItem(name: "userId", value: "\(uid)")] }
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data.prefix(500), encoding: .utf8) ?? ""
        NSLog("[TMetric] GET /timer → HTTP \(status): \(body)")
        guard status == 200,
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eid = dict["id"] as? Int else { return nil }
        return (id: eid, raw: dict)
    }

    static func stopTimer(token: String, entryId: Int? = nil, userId: Int? = nil) async throws {
        let endStr = localFmt.string(from: Date())
        var diag: [String] = ["cachedEntry=\(entryId.map(String.init) ?? "nil") uid=\(userId.map(String.init) ?? "nil")"]

        // Step 1: GET /timer to find the actually running entry
        let timerEntry = await fetchCurrentTimer(token: token, userId: userId)
        diag.append("GET/timer id=\(timerEntry.map { "\($0.id)" } ?? "nil")")
        let resolvedId: Int? = timerEntry?.id ?? entryId
        diag.append("resolved=\(resolvedId.map(String.init) ?? "nil")")

        // Step 2: PUT /timeentries/{id} with full body + endTime
        if let eid = resolvedId,
           let entryUrl = URL(string: "https://app.tmetric.com/api/v3/accounts/\(accountId)/timeentries/\(eid)") {

            var fullEntry: [String: Any]? = timerEntry?.raw
            if fullEntry == nil {
                var getReq = URLRequest(url: entryUrl, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
                getReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                getReq.setValue("application/json", forHTTPHeaderField: "Accept")
                if let (d, r) = try? await URLSession.shared.data(for: getReq) {
                    let st = (r as? HTTPURLResponse)?.statusCode ?? 0
                    diag.append("GET/entries/\(eid)=\(st)")
                    if st == 200 {
                        fullEntry = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                            ?? (try? JSONSerialization.jsonObject(with: d) as? [[String: Any]])?.first
                    }
                }
            }

            if var body = fullEntry {
                body["endTime"] = endStr
                var putReq = URLRequest(url: entryUrl, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
                putReq.httpMethod = "PUT"
                putReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                putReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                putReq.setValue("application/json", forHTTPHeaderField: "Accept")
                putReq.httpBody = try? JSONSerialization.data(withJSONObject: body)
                let (putData, putResp) = try await URLSession.shared.data(for: putReq)
                let putStatus = (putResp as? HTTPURLResponse)?.statusCode ?? 0
                diag.append("PUT/entries/\(eid)=\(putStatus)")
                NSLog("[TMetric] PUT \(eid) → \(putStatus): \(String(data: putData.prefix(300), encoding: .utf8) ?? "")")
                if (200...299).contains(putStatus) { return }
                diag.append("PUT-body:\(String(data: putData.prefix(120), encoding: .utf8) ?? "")")
            } else {
                diag.append("kein body für PUT")
            }
        }

        // Step 3: Fallback DELETE /timer
        var comps = URLComponents(string: "https://app.tmetric.com/api/v3/accounts/\(accountId)/timer")!
        if let uid = userId { comps.queryItems = [URLQueryItem(name: "userId", value: "\(uid)")] }
        guard let url = comps.url else { return }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let respBody = String(data: data.prefix(300), encoding: .utf8) ?? ""
        diag.append("DELETE/timer=\(status)")
        NSLog("[TMetric] DELETE /timer → \(status): \(respBody)")
        // 404 = kein laufender Timer in TMetric → State war veraltet → gilt als Erfolg
        if status == 404 { return }
        if !(200...299).contains(status) {
            throw TMetricError.http(status, diag.joined(separator: " | "))
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

        NSLog("[TMetric] GET \(url)")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            NSLog("[TMetric] HTTP \(http.statusCode): \(String(data: data.prefix(300), encoding: .utf8) ?? "")")
            throw TMetricError.http(http.statusCode, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }

        let rawPreview = String(data: data.prefix(600), encoding: .utf8) ?? "<binary>"
        NSLog("[TMetric] Raw (\(data.count)B): \(rawPreview)")

        let allEntries = (try? JSONDecoder().decode([TMetricTimeEntry].self, from: data)) ?? []
        NSLog("[TMetric] Decoded \(allEntries.count) total entries")

        // Client-side date filter (server filter unreliable)
        let filtered = allEntries.filter { entry in
            guard let s = entry.startTime,
                  let d = localFmt.date(from: s) ?? ISO8601DateFormatter().date(from: s) else {
                return true
            }
            return d >= from && d <= to
        }
        NSLog("[TMetric] After client filter [\(localFmt.string(from: from))…\(localFmt.string(from: to))]: \(filtered.count) entries")

        let projectNames = Set(allEntries.compactMap { $0.project?.name }).sorted().prefix(5).joined(separator: ", ")
        let firstRaw = "Total:\(allEntries.count) Filtered:\(filtered.count)\nProjekte: [\(projectNames)]"
        let extractedUserId = allEntries.compactMap { $0.userId }.first
        NSLog("[TMetric] extractedUserId=\(String(describing: extractedUserId))")

        return TMetricFetchResult(
            summaries: aggregate(entries: filtered, now: now),
            debugRaw:  firstRaw,
            userId:    extractedUserId
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
        case .http(let c, let b): return "TMetric HTTP \(c)\(b.isEmpty ? "" : ": \(b.prefix(400))")"
        }
    }
}
