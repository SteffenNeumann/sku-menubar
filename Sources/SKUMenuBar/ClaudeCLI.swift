import Foundation

// Auflösung und Fähigkeiten der Claude CLI.
//
// Bis 08-25 stand der Binary-Pfad fest verdrahtet in ClaudeCLIService.claudePath und
// die Version wurde nie geprüft. Fehlte ein Feature (z.B. /design, erst ab 2.1.233),
// passierte still gar nichts — kein Fehler, keine Meldung. Diese Datei beantwortet die
// zwei Fragen zentral: WELCHES Binary und WELCHE Version.

// MARK: - Version

/// Semantische CLI-Version (`2.1.243`) — vergleichbar für Feature-Gates.
struct ClaudeCLIVersion: Comparable, CustomStringConvertible, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parst `2.1.243`, `2.1.243 (Claude Code)`, `v2.1.243` — nil wenn keine Version drin steht.
    init?(parsing text: String) {
        // Erste Zahlenfolge der Form a.b.c herausziehen; alles davor/danach ignorieren.
        var digits: [Int] = []
        var current = ""
        for ch in text {
            if ch.isNumber {
                current.append(ch)
            } else if ch == "." && !current.isEmpty {
                digits.append(Int(current) ?? 0)
                current = ""
            } else if !current.isEmpty {
                digits.append(Int(current) ?? 0)
                break
            } else if !digits.isEmpty {
                break
            }
        }
        if !current.isEmpty { digits.append(Int(current) ?? 0) }
        guard digits.count >= 3 else { return nil }
        self.init(digits[0], digits[1], digits[2])
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: ClaudeCLIVersion, rhs: ClaudeCLIVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

// MARK: - Features

/// CLI-Fähigkeiten, die eine Mindestversion brauchen.
///
/// Neues Feature eintragen statt im UI-Code Versionen zu vergleichen — dann steht
/// die Mindestversion genau einmal und die Hinweistexte bleiben einheitlich.
enum ClaudeFeature: String, CaseIterable {
    /// `/design` — Design-Canvas als Artifact (Claude Design Preview in Claude Code).
    case designCanvas

    var minVersion: ClaudeCLIVersion {
        switch self {
        case .designCanvas: return ClaudeCLIVersion(2, 1, 233)
        }
    }

    var label: String {
        switch self {
        case .designCanvas: return "Design-Canvas (/design)"
        }
    }

    /// Hinweis für die UI, wenn die installierte CLI zu alt ist.
    var upgradeHint: String {
        "\(label) braucht Claude CLI ≥ \(minVersion) — `claude update` ausführen."
    }
}

// MARK: - Auflösung

enum ClaudeCLI {

    /// UserDefaults-Schlüssel für einen manuell gesetzten Binary-Pfad (Einstellungen).
    static let overridePathKey = "claudeCLIPath"

    /// Kandidaten in Prioritätsreihenfolge: Override → Standard-Installation → PATH-Orte.
    ///
    /// Bewusst NICHT dabei: die CLI, die Claude Desktop unter
    /// `~/Library/Application Support/Claude/claude-code/<version>/` mitbringt. Das ist ein
    /// app-interner Pfad ohne Zusage, dass er so bleibt — er würde still brechen.
    static func candidatePaths() -> [String] {
        let home = NSHomeDirectory()
        var paths: [String] = []
        let override = UserDefaults.standard.string(forKey: overridePathKey) ?? ""
        if !override.trimmingCharacters(in: .whitespaces).isEmpty {
            paths.append(override)
        }
        paths += [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return paths
    }

    /// Erster ausführbarer Kandidat. Fällt auf den Standardpfad zurück, damit der
    /// Aufrufer immer einen Pfad bekommt (der Prozess-Start meldet dann den Fehler).
    static func resolvedPath() -> String {
        let fm = FileManager.default
        for path in candidatePaths() where fm.isExecutableFile(atPath: path) {
            return path
        }
        return "\(NSHomeDirectory())/.local/bin/claude"
    }
}
