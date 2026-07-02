import Foundation

// MARK: - Model Catalog (Single Source of Truth)
//
// Zentrale Liste aller Anthropic-Modelle für Chat/CodeReview + Kosten-Lookup.
// Ersetzt die früher verstreuten hartcodierten Modell-Listen (ChatView,
// CodeReviewView) und die Tier-Heuristik in AppState.modelPrice.
//
// Preise = USD pro 1 Mio Token (Input / Output), Stand 2026-07 laut Anthropic
// Docs. Anthropic liefert Preise über KEINE API — sie werden hier gepflegt.
// Der „Modelle aktualisieren"-Button (GET /v1/models) ergänzt nur neu
// entdeckte Modell-IDs; deren Preis fällt auf die Tier-Heuristik zurück, bis
// hier ein exakter Wert eingetragen ist.

struct ModelInfo: Identifiable, Hashable {
    var id: String { apiName }
    let apiName: String          // z.B. "claude-opus-4-8"
    let displayName: String      // z.B. "Opus 4.8"
    let tier: String             // "opus" | "sonnet" | "haiku" | "fable" | "other"
    let inputPrice: Double       // USD pro 1 Mio Input-Token
    let outputPrice: Double      // USD pro 1 Mio Output-Token
    let contextK: Int            // Kontextfenster in K
    let provider: String         // "Anthropic"
    var isDynamic: Bool = false  // true = per API entdeckt, Preis geschätzt (Tier-Fallback)

    /// „$5 / $25" — Preis pro 1 Mio Token (Input / Output), kompakt.
    var priceLabel: String {
        func fmt(_ v: Double) -> String {
            v < 1 ? String(format: "$%.2f", v) : String(format: "$%.0f", v)
        }
        return "\(fmt(inputPrice)) / \(fmt(outputPrice))"
    }
}

enum ModelCatalog {

    // MARK: Kuratierter Basis-Katalog (Anthropic)
    // Preise laut https://platform.claude.com/docs/en/about-claude/models/overview
    static let anthropicBundled: [ModelInfo] = [
        .init(apiName: "claude-fable-5",              displayName: "Fable 5",    tier: "fable",  inputPrice: 10, outputPrice: 50, contextK: 1000, provider: "Anthropic"),
        .init(apiName: "claude-opus-4-8",             displayName: "Opus 4.8",   tier: "opus",   inputPrice: 5,  outputPrice: 25, contextK: 1000, provider: "Anthropic"),
        .init(apiName: "claude-opus-4-7",             displayName: "Opus 4.7",   tier: "opus",   inputPrice: 5,  outputPrice: 25, contextK: 1000, provider: "Anthropic"),
        .init(apiName: "claude-opus-4-6",             displayName: "Opus 4.6",   tier: "opus",   inputPrice: 5,  outputPrice: 25, contextK: 1000, provider: "Anthropic"),
        .init(apiName: "claude-sonnet-5",             displayName: "Sonnet 5",   tier: "sonnet", inputPrice: 3,  outputPrice: 15, contextK: 1000, provider: "Anthropic"),
        .init(apiName: "claude-sonnet-4-6",           displayName: "Sonnet 4.6", tier: "sonnet", inputPrice: 3,  outputPrice: 15, contextK: 1000, provider: "Anthropic"),
        .init(apiName: "claude-haiku-4-5-20251001",   displayName: "Haiku 4.5",  tier: "haiku",  inputPrice: 1,  outputPrice: 5,  contextK: 200,  provider: "Anthropic"),
    ]

    // MARK: Tier-Erkennung + Preis-Fallback

    /// Leitet den Tier aus einer beliebigen Modell-ID ab (für unbekannte Modelle).
    nonisolated static func tier(for apiName: String) -> String {
        let m = apiName.lowercased()
        if m.contains("fable") || m.contains("mythos") { return "fable" }
        if m.contains("opus")   { return "opus" }
        if m.contains("haiku")  { return "haiku" }
        if m.contains("sonnet") { return "sonnet" }
        return "other"
    }

    /// (input, output) pro 1 Mio Token für einen Tier.
    nonisolated static func tierPrice(_ tier: String) -> (Double, Double) {
        switch tier {
        case "fable":  return (10, 50)
        case "opus":   return (5, 25)
        case "haiku":  return (1, 5)
        default:       return (3, 15)   // sonnet / other
        }
    }

    /// Preis pro **Token** (input, output) — kompatibel zur alten AppState.modelPrice.
    /// Exakter Katalog-Wert wenn vorhanden, sonst Tier-Heuristik.
    nonisolated static func price(for apiName: String) -> (Double, Double) {
        if let m = anthropicBundled.first(where: { $0.apiName == apiName }) {
            return (m.inputPrice / 1_000_000, m.outputPrice / 1_000_000)
        }
        let (i, o) = tierPrice(tier(for: apiName))
        return (i / 1_000_000, o / 1_000_000)
    }

    // MARK: Anzeige-Helfer

    /// Klartext-Name für eine ID (Katalog-Name oder aus der ID abgeleitet).
    static func displayName(for apiName: String) -> String {
        if let m = anthropicBundled.first(where: { $0.apiName == apiName }) {
            return m.displayName
        }
        return deriveDisplayName(from: apiName)
    }

    /// „Opus 4.9" aus „claude-opus-4-9" ableiten (für neu entdeckte Modelle).
    static func deriveDisplayName(from apiName: String) -> String {
        var s = apiName
        if s.hasPrefix("claude-") { s = String(s.dropFirst("claude-".count)) }
        // Datums-Suffix (z.B. -20251001) entfernen
        let parts = s.split(separator: "-").map(String.init)
            .filter { !($0.count == 8 && $0.allSatisfy(\.isNumber)) }
        guard let first = parts.first else { return apiName }
        let name = first.prefix(1).uppercased() + first.dropFirst()
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? name : "\(name) \(version)"
    }

    /// Picker-Label mit Preis: „Opus 4.8   ·   $5 / $25".
    static func pickerLabel(for apiName: String) -> String {
        let name = displayName(for: apiName)
        let tier = tier(for: apiName)
        let (i, o) = tierPrice(tier)
        // Exakter Katalog-Preis falls vorhanden
        if let m = anthropicBundled.first(where: { $0.apiName == apiName }) {
            return "\(name)   ·   \(m.priceLabel)"
        }
        let info = ModelInfo(apiName: apiName, displayName: name, tier: tier,
                             inputPrice: i, outputPrice: o, contextK: 200,
                             provider: "Anthropic", isDynamic: true)
        return "\(name)   ·   ~\(info.priceLabel)"   // ~ = geschätzt
    }

    /// Vollständige Anthropic-Modell-IDs: Basis-Katalog + per API entdeckte
    /// (dedupliziert, Reihenfolge: Katalog zuerst, dann neue).
    static func anthropicModelIDs(discovered: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for m in anthropicBundled where seen.insert(m.apiName).inserted {
            result.append(m.apiName)
        }
        for id in discovered where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }
}
