import Foundation

// MARK: - Entwicklerkosten
//
// Reine Rechen- und Formatier-Funktionen (Vorbild: OrchestratorLogic.swift) —
// kein State, keine Views, damit unit-testbar.
//
// Grundsatz: Kosten NIE aus gerundeten Einzelwerten aufsummieren. Der Gesamtwert
// wird immer aus der Sekundensumme berechnet, sonst driften Zeilen und Summe
// auseinander (bei 6 Projekten schon 1 €).
//
// Währung ist fest EUR: Der Stundensatz wird vom Nutzer in Euro eingegeben.
// AppState.fmt() darf hier NICHT verwendet werden — das rechnet USD → EUR um.

enum DevCost {

    /// Kosten für eine Dauer in Sekunden bei gegebenem Stundensatz (EUR/h).
    static func cost(seconds: Int, rate: Double) -> Double {
        guard seconds > 0, rate > 0, rate.isFinite else { return 0 }
        return Double(seconds) / 3600.0 * rate
    }

    /// Gesamtkosten — aus der Sekundensumme, nicht aus gerundeten Einzelwerten.
    static func total(seconds: [Int], rate: Double) -> Double {
        cost(seconds: seconds.reduce(0, +), rate: rate)
    }

    /// Kompakte Anzeige für Badges: ganze Euro mit Tausenderpunkt ("4.617 €").
    static func formatCompact(_ amount: Double) -> String {
        format(amount, fractionDigits: 0)
    }

    /// Exakter Wert für Tooltips und zum Kopieren ("4.616,92 €").
    static func formatExact(_ amount: Double) -> String {
        format(amount, fractionDigits: 2)
    }

    private static func format(_ amount: Double, fractionDigits: Int) -> String {
        guard amount.isFinite else { return "–" }
        let f = NumberFormatter()
        f.locale                = Locale(identifier: "de_DE")
        f.numberStyle           = .decimal
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        let s = f.string(from: NSNumber(value: amount)) ?? "0"
        return "\(s) €"
    }

    /// Stundensatz für die Kapsel in der Kachel ("85,00 €/h").
    static func formatRate(_ amount: Double) -> String {
        format(amount, fractionDigits: 2) + "/h"
    }
}
