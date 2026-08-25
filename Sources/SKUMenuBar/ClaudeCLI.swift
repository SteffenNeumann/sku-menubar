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

    /// Parst `2.1.243`, `2.1.243 (Claude Code)`, `v2.1.243`, `Claude Code v2 build 2.1.243`
    /// — nil, wenn keine vollständige a.b.c-Gruppe drin steht.
    ///
    /// Bewusst per Regex auf ASCII-Ziffern und mit Längenbegrenzung: ein handgeschriebener
    /// Scanner brach bei einer einzelnen Zahl vor der Version ab, nahm arabisch-indische
    /// Ziffern als `isNumber` an (die `Int()` nicht parst) und machte aus einem
    /// Integer-Overflow still eine 0 — also eine plausible, falsche Version statt nil.
    init?(parsing text: String) {
        // Nicht `\b`: zwischen "v" und "1" in "v10.0.7" gibt es keine Wortgrenze.
        // Stattdessen: davor und danach darf weder Ziffer noch Punkt stehen — das
        // schließt zugleich abgeschnittene Teilstücke einer längeren Zahlenfolge aus.
        guard let match = text.range(of: #"(?<![\d.])\d{1,9}\.\d{1,9}\.\d{1,9}(?![\d.])"#,
                                     options: .regularExpression) else { return nil }
        let parts = text[match].split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(parts[0], parts[1], parts[2])
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

/// Ergebnis einer Feature-Prüfung. `unknown` ist kein „nein" — die Version steht beim
/// Start kurz nicht fest, und ein nicht gefundenes Binary meldet sie nie.
enum CLIFeatureSupport: Equatable {
    case yes
    case tooOld(ClaudeCLIVersion)
    case unknown
}

// MARK: - Auflösung

enum ClaudeCLI {

    /// UserDefaults-Schlüssel für einen manuell gesetzten Binary-Pfad (Einstellungen).
    static let overridePathKey = "claudeCLIPath"

    /// Manuell gesetzter Pfad aus den Einstellungen — getrimmt und mit aufgelöstem `~`.
    /// Ohne beides scheitert ein aus dem Terminal kopierter Pfad still an der
    /// Ausführbarkeitsprüfung und die App fällt wortlos auf die Standardorte zurück.
    static func overridePath() -> String? {
        let raw = (UserDefaults.standard.string(forKey: overridePathKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return (raw as NSString).expandingTildeInPath
    }

    /// Kandidaten in Prioritätsreihenfolge: Override → Standardinstallation → gängige
    /// Präfixe → jedes Verzeichnis aus `$PATH` (deckt nvm/fnm/bun/mise/asdf ab).
    ///
    /// Bewusst NICHT dabei: die CLI, die Claude Desktop unter
    /// `~/Library/Application Support/Claude/claude-code/<version>/` mitbringt. Das ist ein
    /// app-interner Pfad ohne Zusage, dass er so bleibt — er würde still brechen.
    static func candidatePaths() -> [String] {
        let home = NSHomeDirectory()
        var paths: [String] = []
        if let override = overridePath() { paths.append(override) }
        paths += [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        paths += envPath.split(separator: ":")
            .map { "\($0)/claude" }
            .filter { !paths.contains($0) }
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

    /// Ob ein vom Nutzer eingetragener Pfad tatsächlich benutzbar ist — für den
    /// Hinweis in den Einstellungen. nil = kein Override gesetzt.
    static func overrideIsUsable() -> Bool? {
        guard let path = overridePath() else { return nil }
        return FileManager.default.isExecutableFile(atPath: path)
    }
}
