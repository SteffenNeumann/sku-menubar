import Foundation

final class GitHubService {

    func fetchUsage(
        token: String,
        accountType: String,
        name: String,
        product: String?,
        year: Int,
        month: Int,
        day: Int? = nil
    ) async throws -> [UsageItem] {

        let prefix = accountType == "org"
            ? "/organizations/\(name)/settings/billing/usage"
            : "/users/\(name)/settings/billing/usage"

        var query = "?year=\(year)&month=\(month)"
        if let d = day                  { query += "&day=\(d)" }
        if let p = product, !p.isEmpty  { query += "&product=\(p)" }

        guard let url = URL(string: "https://api.github.com\(prefix)\(query)") else {
            throw APIError.badURL
        }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue("Bearer \(token)",                   forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json",       forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28",                        forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: req)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["message"]
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APIError.http(http.statusCode, msg)
        }

        return (try JSONDecoder().decode(UsageResponse.self, from: data)).usageItems ?? []
    }
}
