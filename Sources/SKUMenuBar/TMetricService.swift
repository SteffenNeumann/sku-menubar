import Foundation

// MARK: - Time Period

enum TMetricPeriod: String, CaseIterable, Codable {
    case today        = "today"
    case thisWeek     = "thisWeek"
    case thisMonth    = "thisMonth"
    case lastMonth    = "lastMonth"
    case thisQuarter  = "thisQuarter"
    case thisYear     = "thisYear"

    var label: String {
        switch self {
        case .today:       return "Heute"
        case .thisWeek:    return "Woche"
        case .thisMonth:   return "Monat"
        case .lastMonth:   return "Vormonat"
        case .thisQuarter: return "Quartal"
        case .thisYear:    return "Jahr"
        }
    }

    var emptyText: String {
        switch self {
        case .today:       return "Heute noch keine Zeit gebucht."
        case .thisWeek:    return "Diese Woche noch keine Zeit gebucht."
        case .thisMonth:   return "Diesen Monat noch keine Zeit gebucht."
        case .lastMonth:   return "Im Vormonat keine Zeit gefunden."
        case .thisQuarter: return "Dieses Quartal noch keine Zeit gebucht."
        case .thisYear:    return "Dieses Jahr noch keine Zeit gebucht."
        }
    }

    func previousPeriodRange() -> (from: Date, to: Date) {
        var gcal = Calendar(identifier: .gregorian)
        gcal.timeZone = TimeZone.current
        var isoCal = Calendar(identifier: .iso8601)
        isoCal.timeZone = TimeZone.current
        let (curFrom, _) = dateRange()
        switch self {
        case .today:
            let prev = gcal.date(byAdding: .day, value: -1, to: curFrom)!
            return (prev, curFrom)
        case .thisWeek:
            let prev = isoCal.date(byAdding: .weekOfYear, value: -1, to: curFrom)!
            return (prev, curFrom)
        case .thisMonth:
            let prev = gcal.date(byAdding: .month, value: -1, to: curFrom)!
            return (prev, curFrom)
        case .lastMonth:
            let prev = gcal.date(byAdding: .month, value: -1, to: curFrom)!
            return (prev, curFrom)
        case .thisQuarter:
            let prev = gcal.date(byAdding: .month, value: -3, to: curFrom)!
            return (prev, curFrom)
        case .thisYear:
            let prev = gcal.date(byAdding: .year, value: -1, to: curFrom)!
            return (prev, curFrom)
        }
    }

    func dateRange() -> (from: Date, to: Date) {
        var gcal = Calendar(identifier: .gregorian)
        gcal.timeZone = TimeZone.current
        var isoCal = Calendar(identifier: .iso8601)
        isoCal.timeZone = TimeZone.current
        let now = Date()
        switch self {
        case .today:
            return (gcal.startOfDay(for: now), now)
        case .thisWeek:
            let comps = isoCal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            let startOfWeek = isoCal.date(from: comps) ?? gcal.startOfDay(for: now)
            return (startOfWeek, now)
        case .thisMonth:
            let startOfMonth = gcal.date(from: gcal.dateComponents([.year, .month], from: now)) ?? gcal.startOfDay(for: now)
            return (startOfMonth, now)
        case .lastMonth:
            let thisMonthStart = gcal.date(from: gcal.dateComponents([.year, .month], from: now)) ?? gcal.startOfDay(for: now)
            let lastMonthStart = gcal.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            let lastMonthEnd   = gcal.date(byAdding: .second, value: -1, to: thisMonthStart) ?? now
            return (lastMonthStart, lastMonthEnd)
        case .thisQuarter:
            let month = gcal.component(.month, from: now)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var comps = gcal.dateComponents([.year], from: now)
            comps.month = quarterStartMonth; comps.day = 1
            let startOfQuarter = gcal.date(from: comps) ?? gcal.startOfDay(for: now)
            return (startOfQuarter, now)
        case .thisYear:
            var comps = gcal.dateComponents([.year], from: now)
            comps.month = 1; comps.day = 1
            let startOfYear = gcal.date(from: comps) ?? gcal.startOfDay(for: now)
            return (startOfYear, now)
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
    let project: TMetricEntryProject?
}

private struct TMetricEntryProject: Codable {
    let id: Int?
    let name: String?
    let client: TMetricEntryClient?
}

private struct TMetricEntryClient: Codable {
    let id: Int?
    let name: String?
}

private struct TMetricMe: Codable {
    let id: Int?
}

// Full project list from GET /timeentries/projects (includes projects w/o time entries)
private struct TMetricProjectListItem: Codable {
    let id: Int?
    let name: String?
    let status: String?
    let client: TMetricEntryClient?
}

// MARK: - Public Output

struct TMetricTimelineEntry: Identifiable {
    let id: Int
    let projectId: Int
    let projectName: String
    let start: Date
    let end: Date?  // nil = running
}

struct TMetricFetchResult {
    let summaries:       [TMetricProjectSummary]
    let timelineEntries: [TMetricTimelineEntry]
    let debugRaw:        String
    let userId:          Int?
}

struct TMetricProjectSummary: Identifiable, Equatable {
    let id: Int
    let name: String
    let clientName: String
    var totalSeconds: Int
    var entryCount: Int
    var lastEntryDate: Date?

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

    // MARK: Fetch full project list

    /// Returns ALL projects (including brand-new ones without any time entries) so the
    /// picker isn't limited to projects that already have tracked time. Time fields are 0.
    static func fetchProjects(token: String) async -> [TMetricProjectSummary] {
        let list: [TMetricProjectListItem]? = await get("accounts/\(accountId)/timeentries/projects", token: token)
        guard let list else { return [] }
        let projects = list.compactMap { p -> TMetricProjectSummary? in
            guard let id = p.id, id != 0, let name = p.name else { return nil }
            // Keep active (and status-less) projects; skip archived/deleted
            if let s = p.status, s != "active" { return nil }
            return TMetricProjectSummary(id: id, name: name, clientName: p.client?.name ?? "",
                                         totalSeconds: 0, entryCount: 0, lastEntryDate: nil)
        }
        NSLog("[TMetric] fetchProjects: \(projects.count) active projects")
        return projects
    }

    // MARK: Timer control

    /// Starts a running timer via POST /timeentries WITHOUT endTime.
    /// TMetric auto-stops any previously running entry.
    /// Response is an array — we pick the entry where endTime == null.
    static func startTimer(token: String, projectId: Int, userId: Int? = nil) async throws -> (entryId: Int?, userId: Int?) {
        let startStr = localFmt.string(from: Date())
        var body: [String: Any] = [
            "startTime": startStr,
            "project": ["id": projectId]
        ]
        if let uid = userId { body["userId"] = uid }

        guard let url = URL(string: "https://app.tmetric.com/api/v3/accounts/\(accountId)/timeentries") else {
            throw TMetricError.badURL
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let respStr = String(data: data.prefix(600), encoding: .utf8) ?? ""
        NSLog("[TMetric] POST /timeentries (start) → HTTP \(status): \(respStr)")

        guard (200...299).contains(status) else {
            throw TMetricError.http(status, respStr)
        }

        // Response is array of affected entries; the NEW running one has endTime == null
        let entries = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        let running = entries.first(where: { e in
            let et = e["endTime"]
            return et == nil || et is NSNull
        })
        let entryId     = running.flatMap { $0["id"]     as? Int }
        let returnedUid = running.flatMap { $0["userId"] as? Int }
        NSLog("[TMetric] start: entryId=\(String(describing: entryId)) userId=\(String(describing: returnedUid)) affected=\(entries.count)")
        return (entryId: entryId, userId: returnedUid)
    }

    // MARK: GET current running timer

    /// Finds the currently running entry by querying today's timeentries for one with endTime == null.
    /// (GET /timer is not available on this account.)
    static func fetchCurrentTimer(token: String, userId: Int?) async -> (id: Int, raw: [String: Any])? {
        var gcal = Calendar(identifier: .gregorian)
        gcal.timeZone = TimeZone.current
        let now = Date()
        let startOfDay = gcal.startOfDay(for: now)

        var comps = URLComponents(string: "https://app.tmetric.com/api/v3/accounts/\(accountId)/timeentries")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "startTime", value: localFmt.string(from: startOfDay)),
            URLQueryItem(name: "endTime",   value: localFmt.string(from: now))
        ]
        if let uid = userId { items.append(URLQueryItem(name: "userIds", value: "\(uid)")) }
        comps.queryItems = items
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        NSLog("[TMetric] fetchCurrentTimer GET /timeentries → HTTP \(status) (\(data.count)B)")
        guard status == 200,
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

        // Running entry = endTime is missing or null
        guard let running = entries.first(where: { e in
            let et = e["endTime"]
            return et == nil || et is NSNull
        }), let eid = running["id"] as? Int else {
            NSLog("[TMetric] fetchCurrentTimer: no running entry in \(entries.count) entries today")
            return nil
        }
        NSLog("[TMetric] fetchCurrentTimer: running id=\(eid) project=\((running["project"] as? [String: Any])?["name"] ?? "?")")
        return (id: eid, raw: running)
    }

    /// Stops the running entry by setting endTime via PUT /timeentries/{id}.
    static func stopTimer(token: String, entryId: Int? = nil, userId: Int? = nil) async throws {
        let endStr = localFmt.string(from: Date())

        // Always fetch from TMetric — don't trust cached entryId alone
        let timerEntry = await fetchCurrentTimer(token: token, userId: userId)
        let resolvedId = timerEntry?.id ?? entryId
        NSLog("[TMetric] stopTimer: resolvedId=\(String(describing: resolvedId)) (fromAPI=\(String(describing: timerEntry?.id)) cached=\(String(describing: entryId)))")

        guard let eid = resolvedId else {
            NSLog("[TMetric] stopTimer: nothing to stop")
            return
        }
        guard let entryUrl = URL(string: "https://app.tmetric.com/api/v3/accounts/\(accountId)/timeentries/\(eid)") else { return }

        // Use raw entry from fetchCurrentTimer; if missing, GET it separately
        var body: [String: Any] = timerEntry?.raw ?? [:]
        if body.isEmpty {
            var getReq = URLRequest(url: entryUrl, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            getReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            getReq.setValue("application/json", forHTTPHeaderField: "Accept")
            if let (d, r) = try? await URLSession.shared.data(for: getReq),
               (r as? HTTPURLResponse)?.statusCode == 200,
               let dict = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                body = dict
                NSLog("[TMetric] stopTimer: fetched entry body separately")
            }
        }
        guard !body.isEmpty else {
            throw TMetricError.http(0, "stopTimer: no entry body for id=\(eid)")
        }

        body["endTime"] = endStr
        var putReq = URLRequest(url: entryUrl, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        putReq.httpMethod = "PUT"
        putReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        putReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        putReq.setValue("application/json", forHTTPHeaderField: "Accept")
        putReq.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (putData, putResp) = try await URLSession.shared.data(for: putReq)
        let putStatus = (putResp as? HTTPURLResponse)?.statusCode ?? 0
        NSLog("[TMetric] stopTimer PUT /timeentries/\(eid) → HTTP \(putStatus): \(String(data: putData.prefix(300), encoding: .utf8) ?? "")")
        if !(200...299).contains(putStatus) {
            throw TMetricError.http(putStatus, String(data: putData.prefix(300), encoding: .utf8) ?? "")
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

        let timelineEntries: [TMetricTimelineEntry] = filtered.compactMap { e in
            guard let id = e.id,
                  let startStr = e.startTime,
                  let start = localFmt.date(from: startStr) ?? ISO8601DateFormatter().date(from: startStr)
            else { return nil }
            let end = e.endTime.flatMap { localFmt.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return TMetricTimelineEntry(
                id: id,
                projectId:   e.project?.id   ?? 0,
                projectName: e.project?.name ?? "Ohne Projekt",
                start: start,
                end:   end
            )
        }.sorted { $0.start < $1.start }

        return TMetricFetchResult(
            summaries:       aggregate(entries: filtered, now: now),
            timelineEntries: timelineEntries,
            debugRaw:        firstRaw,
            userId:          extractedUserId
        )
    }

    // MARK: Aggregate by project

    private static func aggregate(entries: [TMetricTimeEntry], now: Date) -> [TMetricProjectSummary] {
        func parse(_ s: String?) -> Date? {
            guard let s else { return nil }
            return localFmt.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }

        var totals: [Int: (name: String, client: String, seconds: Int, count: Int, lastDate: Date?)] = [:]

        for entry in entries {
            let projectId   = entry.project?.id   ?? 0
            let projectName = entry.project?.name ?? (projectId == 0 ? "Ohne Projekt" : "Projekt \(projectId)")
            let clientName  = entry.project?.client?.name ?? ""

            let seconds: Int
            if let s = parse(entry.startTime), let e = parse(entry.endTime) {
                seconds = max(0, Int(e.timeIntervalSince(s)))
            } else if let s = parse(entry.startTime), entry.endTime == nil {
                seconds = max(0, Int(now.timeIntervalSince(s)))
            } else {
                continue
            }

            guard seconds > 0 else { continue }

            let entryStart = parse(entry.startTime)
            if var existing = totals[projectId] {
                existing.seconds  += seconds
                existing.count    += 1
                if let d = entryStart, (existing.lastDate == nil || d > existing.lastDate!) {
                    existing.lastDate = d
                }
                totals[projectId] = existing
            } else {
                totals[projectId] = (name: projectName, client: clientName, seconds: seconds, count: 1, lastDate: entryStart)
            }
        }

        return totals
            .map { id, v in TMetricProjectSummary(id: id, name: v.name, clientName: v.client, totalSeconds: v.seconds, entryCount: v.count, lastEntryDate: v.lastDate) }
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
