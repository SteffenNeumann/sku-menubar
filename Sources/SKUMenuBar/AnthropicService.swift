import Foundation

final class AnthropicService {

    private let base = "https://api.anthropic.com/v1/organizations"

    // MARK: - Usage Report (buckets with token counts)

    /// Returns all time-bucketed usage for the given period, handling API pagination.
    func fetchUsage(
        adminKey: String,
        start: Date,
        end: Date,
        bucketWidth: String = "1d"
    ) async throws -> [AnthropicUsageBucket] {
        var all: [AnthropicUsageBucket] = []
        var nextPage: String? = nil

        repeat {
            var items = dateItems(start: start, end: end) + [
                .init(name: "bucket_width", value: bucketWidth)
            ]
            if let page = nextPage {
                items.append(.init(name: "page", value: page))
            }
            var comps = URLComponents(string: "\(base)/usage_report/messages")!
            comps.queryItems = items
            guard let url = comps.url else { throw APIError.badURL }

            let data = try await perform(url: url, adminKey: adminKey)
            let resp = try JSONDecoder().decode(AnthropicUsageResponse.self, from: data)
            all.append(contentsOf: resp.data ?? [])
            nextPage = (resp.hasMore == true) ? resp.nextPage : nil
        } while nextPage != nil

        return all
    }

    // MARK: - Shared

    private func dateItems(start: Date, end: Date) -> [URLQueryItem] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        fmt.timeZone   = TimeZone(identifier: "UTC")
        fmt.locale     = Locale(identifier: "en_US_POSIX")
        return [
            .init(name: "starting_at", value: fmt.string(from: start)),
            .init(name: "ending_at",   value: fmt.string(from: end))
        ]
    }

    private func perform(url: URL, adminKey: String) async throws -> Data {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue(adminKey.trimmingCharacters(in: .whitespacesAndNewlines),
                     forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = extractError(from: data)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APIError.http(http.statusCode, msg)
        }
        return data
    }

    private func extractError(from data: Data) -> String? {
        struct Wrapper: Codable { struct E: Codable { let message: String? }; let error: E? }
        return (try? JSONDecoder().decode(Wrapper.self, from: data))?.error?.message
    }
}
