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
    var anthropicApiKey:   String = ""   // Messages API key (sk-ant-api03-…) for inquiry automation
    // Currency
    var currency: String = "USD"       // "USD" | "EUR"
    var eurRate:  Double = 0.92        // USD → EUR exchange rate
    // Claude weekly token limit
    var claudeWeeklyTokenLimit: Int = 0  // 0 = deaktiviert (Tokens pro Woche)
    // Claude.ai Plan Limits (manuell aus claude.ai/settings/usage eintragen)
    var claudeSessionTokenLimit: Int    = 0  // 0 = deaktiviert, z.B. 88000 für Pro
    var claudeMonthlySpendLimit: Double = 0  // 0 = deaktiviert (EUR, z.B. 100.0)
    // Copilot Fallback
    var copilotFallbackEnabled: Bool   = false
    var copilotFallbackModel:   String = "github/claude-sonnet-4-5"
    // Token Optimierung
    var historyWindowSize: Int = 8   // Anzahl Turns (= Nachrichten-Paare) die im GitHub-Models-Verlauf mitgesendet werden
    var maxTurns: Int = 10           // --max-turns für Claude CLI (0 = deaktiviert)
    var autoCompactThreshold: Int = 100000  // Input-Token-Schwelle für Auto-Compact (0 = deaktiviert)
    // Orchestrator
    var orchestratorMaxTurns: Int = 60      // --max-turns je Orchestrator-Agent (0 = Fallback auf maxTurns/Default)
    var orchestratorIdleTimeout: Int = 120  // Sekunden ohne Stream-Event bis Agent-Abbruch (0 = Default 120)
    var autoOrchestrationEnabled: Bool = true  // false = lange Nachrichten lösen NIE automatisch eine Orchestrierung aus
    var autoActivateMCPByKeyword: Bool = true  // true = MCP-Stichwort im Chat (linear, make.com …) aktiviert den MCP automatisch
    // TMetric time tracking
    var tmetricApiToken: String = ""
    // Ollama / lokales LLM (kostenlos, kein API-Key nötig)
    var ollamaBaseUrl: String = "http://localhost:11434/v1"
    var ollamaModel:   String = "llama3.2"

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
        anthropicApiKey   = (try? c.decodeIfPresent(String.self, forKey: .anthropicApiKey))  ?? ""
        currency          = (try? c.decodeIfPresent(String.self, forKey: .currency))         ?? "USD"
        eurRate           = (try? c.decodeIfPresent(Double.self, forKey: .eurRate))          ?? 0.92
        // Migrate old claudeWeeklyCostLimit (Double, USD) → no-op; new field is token-based
        claudeWeeklyTokenLimit  = (try? c.decodeIfPresent(Int.self,    forKey: .claudeWeeklyTokenLimit))  ?? 0
        claudeSessionTokenLimit  = (try? c.decodeIfPresent(Int.self,    forKey: .claudeSessionTokenLimit))  ?? 0
        claudeMonthlySpendLimit  = (try? c.decodeIfPresent(Double.self, forKey: .claudeMonthlySpendLimit))  ?? 0
        copilotFallbackEnabled = (try? c.decodeIfPresent(Bool.self,   forKey: .copilotFallbackEnabled)) ?? false
        var savedModel = (try? c.decodeIfPresent(String.self, forKey: .copilotFallbackModel)) ?? "github/claude-sonnet-4-5"
        // Migrate old saved value that was missing github/ prefix
        if savedModel == "claude-sonnet-4-5" { savedModel = "github/claude-sonnet-4-5" }
        copilotFallbackModel = savedModel
        historyWindowSize       = (try? c.decodeIfPresent(Int.self, forKey: .historyWindowSize))       ?? 8
        maxTurns                = (try? c.decodeIfPresent(Int.self, forKey: .maxTurns))                ?? 10
        let savedThreshold = (try? c.decodeIfPresent(Int.self, forKey: .autoCompactThreshold)) ?? 100000
        autoCompactThreshold = savedThreshold == 50000 ? 100000 : savedThreshold
        orchestratorMaxTurns    = (try? c.decodeIfPresent(Int.self, forKey: .orchestratorMaxTurns))    ?? 60
        orchestratorIdleTimeout = (try? c.decodeIfPresent(Int.self, forKey: .orchestratorIdleTimeout)) ?? 120
        autoOrchestrationEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .autoOrchestrationEnabled)) ?? true
        autoActivateMCPByKeyword = (try? c.decodeIfPresent(Bool.self, forKey: .autoActivateMCPByKeyword)) ?? true
        tmetricApiToken = (try? c.decodeIfPresent(String.self, forKey: .tmetricApiToken)) ?? ""
        ollamaBaseUrl   = (try? c.decodeIfPresent(String.self, forKey: .ollamaBaseUrl)) ?? "http://localhost:11434/v1"
        ollamaModel     = (try? c.decodeIfPresent(String.self, forKey: .ollamaModel))   ?? "llama3.2"
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
