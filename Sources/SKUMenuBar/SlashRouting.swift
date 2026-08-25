import Foundation

// Reine Routing-Logik für Slash-Befehle — bewusst außerhalb der View, damit sie
// testbar ist. Der Fehler, der das nötig machte: `/design <langer Auftrag>` wurde
// vom Gate durchgelassen, `handleSlashCommand` leerte `inputText`, und die
// Orchestrator-Pfade lesen `inputText` neu → stiller Abbruch mit Textverlust.
enum SlashRouting {

    /// Befehlswort einer Eingabe, kleingeschrieben — `"/Design  Login-Screen"` → `"/design"`.
    /// Trennt an jedem Whitespace, nicht nur am Leerzeichen (Shift+Enter erzeugt `\n`).
    static func commandWord(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        guard let word = trimmed.split(whereSeparator: { $0.isWhitespace }).first else { return nil }
        return word.lowercased()
    }

    /// Argumente hinter dem Befehlswort, ungetrimmt in der Schreibweise des Nutzers.
    static func arguments(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let word = commandWord(of: trimmed) else { return "" }
        return String(trimmed.dropFirst(word.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Befehle, die die App selbst bearbeitet (statt sie an die CLI zu geben).
    /// `/design` steht hier, weil es ein Versions-Gate braucht — bestanden wird es
    /// trotzdem durchgereicht.
    private static let locallyHandled: Set<String> = [
        "/clear", "/new", "/model", "/agent", "/compact", "/files", "/help", "/design",
    ]

    /// Ob `handleSlashCommand` überhaupt gefragt werden muss.
    ///
    /// Dateipfade (`/Users/…`) sind keine Befehle und müssen als Text durchgehen —
    /// deshalb die Prüfung gegen die feste Liste statt „beginnt mit / und hat kein Leerzeichen".
    static func needsLocalHandling(_ text: String) -> Bool {
        guard let word = commandWord(of: text) else { return false }
        return locallyHandled.contains(word)
    }
}

// Wann ein Agent automatisch per Trigger-Wort einspringen darf.
//
// „Kein Agent" setzte bisher nur `selectedAgent = ""` — genau den Zustand, in dem der
// Auto-Trigger greift. Beim nächsten Tastendruck war der Agent wieder da, und der Haken
// im Menü sprang zurück. Es fehlte ein Zustand für „ausdrücklich keinen".
enum AgentTriggering {

    /// - Parameters:
    ///   - selectedAgent: manuell gewählter Agent ("" = keiner)
    ///   - suppressed: Nutzer hat „Kein Agent" gewählt
    ///   - text: aktuelle Eingabe
    ///   - orchestratorActive: läuft eine Orchestrierung? Dann würde ein Folge-Stichwort
    ///     („Status") einen zufälligen Agent einspringen lassen.
    static func mayAutoTrigger(selectedAgent: String,
                               suppressed: Bool,
                               text: String,
                               orchestratorActive: Bool) -> Bool {
        guard !suppressed else { return false }
        guard selectedAgent.isEmpty, !text.isEmpty, !orchestratorActive else { return false }
        return true
    }
}
