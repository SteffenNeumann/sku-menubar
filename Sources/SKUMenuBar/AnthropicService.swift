import Foundation

final class AnthropicService {

    private let base = "https://api.anthropic.com/v1"

    /// Fetch usage entries for the given org and time window.
    /// Granularity: "day" | "hour"
    func fetchUsage(
        adminKey: String,
        orgId:    String,
        start:    Date,
        end:      Date,
        granularity: String = "day"
    ) async throws -> [AnthropicUsageEntry] {

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let startStr = iso.string(from: start)
        let endStr   = iso.string(from: end)

        var comps = URLComponents(string: "\(base)/organizations/\(orgId)/usage_report/messages")!
        comps.queryItems = [
            .init(name: "granularity",  value: granularity),
            .init(name: "start_time",   value: startStr),
            .init(name: "end_time",     value: endStr),
        ]
        guard let url = comps.url else { throw APIError.badURL }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue(adminKey,     forHTTPHeaderField: "anthropic-admin-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = extractMessage(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APIError.http(http.statusCode, msg)
        }

        return (try JSONDecoder().decode(AnthropicUsageResponse.self, from: data)).data ?? []
    }

    private func extractMessage(from data: Data) -> String? {
        // Try {"error": {"message": "..."}} and {"message": "..."}
        if let top = try? JSONDecoder().decode([String: AnthropicErrorWrapper].self, from: data) {
            return top["error"]?.message
        }
        return (try? JSONDecoder().decode([String: String].self, from: data))?["message"]
    }
}

private struct AnthropicErrorWrapper: Codable { let message: String? }
