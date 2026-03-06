import Foundation

// MARK: - Settings

struct GitHubSettings: Codable {
    var token: String = ""
    var accountType: String = "user"   // "user" | "org"
    var name: String = ""
    var product: String = ""           // "" = all
    var budget: Double = 10.0
    var intervalSeconds: Int = 300
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
