import Foundation

// MARK: - Settings

struct GitHubSettings: Codable {
    var token: String = ""
    var accountType: String = "user"   // "user" | "org"
    var name: String = ""
    var product: String = ""           // "" = all
    var budget: Double = 10.0
    var intervalSeconds: Int = 300
    // Claude / Anthropic
    var anthropicAdminKey: String = ""
    var anthropicOrgId:    String = ""
    // Currency
    var currency: String = "USD"       // "USD" | "EUR"
    var eurRate:  Double = 0.92        // USD → EUR exchange rate
    // Claude cost limit
    var claudeWeeklyCostLimit: Double = 0  // 0 = deaktiviert (USD pro Woche)

    init() {}

    // Custom decoder: use decodeIfPresent so missing keys fall back to defaults
    // (needed when loading settings saved by an older version of the app)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token             = (try? c.decodeIfPresent(String.self, forKey: .token))            ?? ""
        accountType       = (try? c.decodeIfPresent(String.self, forKey: .accountType))      ?? "user"
        name              = (try? c.decodeIfPresent(String.self, forKey: .name))             ?? ""
        product           = (try? c.decodeIfPresent(String.self, forKey: .product))          ?? ""
        budget            = (try? c.decodeIfPresent(Double.self, forKey: .budget))           ?? 10.0
        intervalSeconds   = (try? c.decodeIfPresent(Int.self,    forKey: .intervalSeconds))  ?? 300
        anthropicAdminKey = (try? c.decodeIfPresent(String.self, forKey: .anthropicAdminKey)) ?? ""
        anthropicOrgId    = (try? c.decodeIfPresent(String.self, forKey: .anthropicOrgId))   ?? ""
        currency          = (try? c.decodeIfPresent(String.self, forKey: .currency))         ?? "USD"
        eurRate           = (try? c.decodeIfPresent(Double.self, forKey: .eurRate))          ?? 0.92
        claudeWeeklyCostLimit  = (try? c.decodeIfPresent(Double.self, forKey: .claudeWeeklyCostLimit)) ?? 0
    }
}

// MARK: - Anthropic API Models

/// Top-level response: array of time buckets (paginated)
struct AnthropicUsageResponse: Codable {
    let data:     [AnthropicUsageBucket]?
    let hasMore:  Bool?
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore  = "has_more"
        case nextPage = "next_page"
    }
}

/// One time bucket (e.g. 1-hour or 1-day window)
struct AnthropicUsageBucket: Codable {
    let startingAt: String?
    let endingAt:   String?
    let results:    [AnthropicUsageResult]?

    enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt   = "ending_at"
        case results
    }

    var totalTokens: Int { (results ?? []).map(\.totalTokens).reduce(0, +) }
}

/// Per-model/key usage within a bucket
struct AnthropicUsageResult: Codable {
    let uncachedInputTokens:  Int?
    let cacheReadInputTokens: Int?
    let outputTokens:         Int?
    let cacheCreation:        AnthropicCacheCreation?

    enum CodingKeys: String, CodingKey {
        case uncachedInputTokens  = "uncached_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens         = "output_tokens"
        case cacheCreation        = "cache_creation"
    }

    var totalTokens: Int {
        (uncachedInputTokens ?? 0) +
        (cacheReadInputTokens ?? 0) +
        (outputTokens ?? 0) +
        (cacheCreation?.total ?? 0)
    }

    /// Approximate USD cost using Sonnet list prices (no model field in response)
    /// Input (uncached) $3/MTok, cache-read $0.30/MTok, cache-write $3.75/MTok, output $15/MTok
    var estimatedCostUsd: Double {
        let inp  = Double(uncachedInputTokens  ?? 0) * 3.00   / 1_000_000
        let cr   = Double(cacheReadInputTokens ?? 0) * 0.30   / 1_000_000
        let cw   = Double(cacheCreation?.total ?? 0) * 3.75   / 1_000_000
        let out  = Double(outputTokens         ?? 0) * 15.00  / 1_000_000
        return inp + cr + cw + out
    }
}

struct AnthropicCacheCreation: Codable {
    let ephemeral1hInputTokens: Int?
    let ephemeral5mInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
        case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
    }

    var total: Int { (ephemeral1hInputTokens ?? 0) + (ephemeral5mInputTokens ?? 0) }
}

// MARK: - API Response

struct UsageResponse: Codable {
    let usageItems: [UsageItem]?
}

struct UsageItem: Codable {
    let date: String?
    let product: String?
    let sku: String?
    let quantity: Double?
    let unitType: String?
    let pricePerUnit: Double?
    let grossAmount: Double?
    let discountAmount: Double?
    let netAmount: Double?

    var cost: Double { netAmount ?? grossAmount ?? 0 }
}

// MARK: - Daily Aggregation

struct DailyUsage: Identifiable {
    let id: String    // "yyyy-MM-dd"
    let date: Date
    let amount: Double

    var shortLabel: String {
        let f = DateFormatter()
        f.dateFormat = "d.M."
        f.locale = Locale(identifier: "de_DE")
        return f.string(from: date)
    }

    var fullLabel: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.locale = Locale(identifier: "de_DE")
        return f.string(from: date)
    }
}

// MARK: - Monthly Aggregation

struct MonthlyUsage: Identifiable {
    let id: String          // "yyyy-MM"
    let year: Int
    let month: Int
    let total: Double
    let byProduct: [String: Double]
    let byDay: [String: Double]     // "yyyy-MM-dd" -> amount

    var shortName: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        return df.shortMonthSymbols[month - 1]
    }

    var monthName: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        return df.monthSymbols[month - 1]
    }
}

// MARK: - Weekly / Daily (drill-down)

struct WeeklyUsage: Identifiable {
    let id: Int         // weekOfYear
    let weekOfYear: Int
    let total: Double
    var label: String { "KW \(weekOfYear)" }
}

struct DayUsage: Identifiable {
    let id: String      // "yyyy-MM-dd"
    let date: Date
    let amount: Double

    var weekdayShort: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "EEE"
        return String(df.string(from: date).prefix(2))
    }

    var dateShort: String {
        let df = DateFormatter()
        df.dateFormat = "d."
        return df.string(from: date)
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case badURL
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badURL:         return "Ungültige URL"
        case .http(let c, let m): return "HTTP \(c): \(m)"
        }
    }
}
