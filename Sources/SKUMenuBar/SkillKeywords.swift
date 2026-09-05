import Foundation

/// Stichwort → Skill.
///
/// Hintergrund (gemessen 18.08.2026): Skills lösen NICHT von selbst aus. In 17 CLI-Läufen mit
/// identischer Design-Aufgabe kam 0× ein Skill-Aufruf — auch dann nicht, wenn der System-Prompt
/// des Agenten den Skill namentlich mit Tool-Aufruf verlangte. Dieselbe Anweisung in der
/// NACHRICHT platziert: 3 von 3 Läufen riefen den Skill auf.
/// Deshalb hängt `performSend` bei einem Stichwort-Treffer eine kurze Zeile ans Prompt-Ende.
enum SkillKeywords {

    /// Bewusst konservativ: lieber ein Treffer weniger als ein Skill, der ständig falsch feuert.
    static let map: [(skill: String, triggers: [String])] = [
        ("10k-website-checklist", ["website", "webseite", "landingpage", "landing page",
                                   "startseite", "homepage", "webdesign", "web-design", "relaunch"]),
        ("ui-ux-pro-max",         ["ui/ux", "ux-design", "mockup", "designsystem", "design-system"]),
        ("web-design-guidelines", ["barrierefrei", "barrierefreiheit", "accessibility", "wcag"]),
        ("excel-vba",             ["excel", "vba", "makro", "arbeitsmappe", "xlsm"]),
        ("shadcn",                ["shadcn"]),
        ("docuseal:docuseal-code", ["docuseal"]),
    ]

    /// Alle vom Modell aufrufbaren Skills aus drei Quellen. Gemessen am CLI-Inventar
    /// (20.08.2026: 25 Skills, dreimal identisch) — ein reiner Scan von ~/.claude/skills
    /// kennt davon nur 9 und filtert alles andere stumm weg.
    static func installedSkills(fileManager: FileManager = .default) -> Set<String> {
        localSkills(fileManager: fileManager)
            .union(pluginSkills(fileManager: fileManager))
            .union(builtInSkills)
    }

    /// `~/.claude/skills/<name>/SKILL.md`
    static func localSkills(fileManager: FileManager = .default) -> Set<String> {
        let dir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")
        guard let entries = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return [] }
        return Set(entries.filter { name in
            fileManager.fileExists(atPath: dir.appendingPathComponent("\(name)/SKILL.md").path)
        })
    }

    /// Skills aktivierter Plugins. `settings.json` listet sie als `"plugin@marketplace": true`,
    /// die Dateien liegen unter `~/.claude/plugins/marketplaces/<marketplace>/skills/<name>/`.
    /// Aufrufbar sind sie als `plugin:name` — genau so müssen sie auch in `map` stehen.
    static func pluginSkills(fileManager: FileManager = .default) -> Set<String> {
        let home = fileManager.homeDirectoryForCurrentUser
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".claude/settings.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enabled = root["enabledPlugins"] as? [String: Any] else { return [] }

        var result: Set<String> = []
        for (key, value) in enabled where (value as? Bool) == true {
            let parts = key.split(separator: "@", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let dir = home.appendingPathComponent(
                ".claude/plugins/marketplaces/\(parts[1])/skills")
            guard let entries = try? fileManager.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in entries
            where fileManager.fileExists(atPath: dir.appendingPathComponent("\(name)/SKILL.md").path) {
                result.insert("\(parts[0]):\(name)")
            }
        }
        return result
    }

    /// Von der Claude-CLI mitgelieferte Skills. Sie liegen nicht auf der Platte, sind also nicht
    /// scannbar, sondern nur messbar. Hier stehen ausschließlich die fachlich nutzbaren, deren
    /// Aufruf bestätigt ist. `debug` fehlt bewusst: gelistet, aber `disable-model-invocation`.
    static let builtInSkills: Set<String> = [
        "code-review", "simplify", "verify", "deep-research", "claude-api",
    ]

    /// Erster Treffer in Reihenfolge von `map`, oder nil.
    /// Matcht nur an Wortgrenzen — „excel" darf nicht in „excellent" anschlagen.
    static func match(in text: String, availableSkills: Set<String>) -> String? {
        let haystack = text.lowercased()
        for entry in map where availableSkills.contains(entry.skill) {
            if entry.triggers.contains(where: { containsWord($0, in: haystack) }) {
                return entry.skill
            }
        }
        return nil
    }

    /// Die Zeile, die ans Prompt-ENDE gehängt wird (Recency).
    static func hint(for skill: String) -> String {
        "Nutze für diese Aufgabe zuerst den Skill \"\(skill)\" (Skill-Tool)."
    }

    // MARK: - Pflicht-Skills (⭐ Hauptskills des Agenten)

    /// Präfix, mit dem eine Nachricht die Pflicht-Skills für genau diesen einen Aufruf abwählt.
    /// Bewusst als Ausstieg statt als Einstieg: vergisst man ihn, lädt der Agent die Skills —
    /// der sichere Zustand ist der Default.
    static let skipPrefix = "kurz:"

    static func hasSkipPrefix(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix(skipPrefix)
    }

    /// Entfernt den Präfix samt folgendem Leerraum. Ohne Treffer unverändert.
    static func stripSkipPrefix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(skipPrefix) else { return text }
        return String(trimmed.dropFirst(skipPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let mainSkillMarker = "⭐ Hauptskills"
    /// Nur vom Main-Thread benutzt (performSend + Banner-Render). Spart das Zerlegen des
    /// Blocks bei jedem Render-Pass — Hangs in dieser App sind kosten-, nicht frequenzgetrieben.
    private static var mainSkillCache: [Int: [String]] = [:]

    /// Die mit ⭐ markierten Pflicht-Skills aus der Agent-Definition, in Reihenfolge der Datei.
    ///
    /// Gelesen wird der Block `### ⭐ Hauptskills …` bis zur nächsten Überschrift; je
    /// Aufzählungszeile zählt der erste Backtick-Name. Bewusst aus der Datei gelesen statt im
    /// Code gepflegt: ändert sich die Liste im Agenten, zieht die App ohne Build nach.
    static func mainSkills(inAgentBody body: String) -> [String] {
        // Cache vor allem anderen: der Banner ruft das im Render-Pfad auf, und auch das
        // erfolglose Suchen nach der Überschrift kostet sonst bei jedem Durchlauf.
        let key = body.hashValue
        if let cached = mainSkillCache[key] { return cached }
        // Nur eine ÜBERSCHRIFT zählt als Blockanfang. Der Researcher erwähnt „⭐ Hauptskills"
        // in seinen Arbeitsanweisungen im Fließtext; ohne diese Prüfung begann der Block dort
        // und der Backtick-Parser las Bruchstücke wie `## Active Skills` als Skill-Namen.
        guard let marker = headingRange(of: mainSkillMarker, in: body) else {
            mainSkillCache[key] = []
            return []
        }

        let rest = body[marker.upperBound...]
        // Nächste Überschrift beendet den Block — egal welcher Ebene.
        let block = rest.range(of: "\n#").map { String(rest[..<$0.lowerBound]) } ?? String(rest)

        var found: [String] = []
        for line in block.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else { continue }
            guard let open = trimmed.range(of: "`"),
                  let close = trimmed.range(of: "`", range: open.upperBound..<trimmed.endIndex)
            else { continue }
            let name = String(trimmed[open.upperBound..<close.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !found.contains(name) { found.append(name) }
        }
        mainSkillCache[key] = found
        return found
    }

    /// Bereich des `marker` in der ersten Markdown-ÜBERSCHRIFT, die ihn enthält — also einer
    /// Zeile, die (nach optionalen Leerzeichen) mit `#` beginnt. Erwähnungen im Fließtext
    /// werden übersprungen.
    private static func headingRange(of marker: String, in body: String) -> Range<String.Index>? {
        guard !marker.isEmpty else { return nil }   // sonst käme die Schleife nie voran
        var searchStart = body.startIndex
        while let found = body.range(of: marker, range: searchStart..<body.endIndex) {
            let lineStart = body[..<found.lowerBound].lastIndex(of: "\n")
                .map { body.index(after: $0) } ?? body.startIndex
            if body[lineStart..<found.lowerBound]
                .trimmingCharacters(in: .whitespaces)
                .hasPrefix("#") {
                return found
            }
            searchStart = found.upperBound
        }
        return nil
    }

    /// Der Pflicht-Block ans Nachrichten-ENDE. Steht bewusst in der NACHRICHT: dieselbe
    /// Anweisung im System-Prompt blieb messbar wirkungslos (0/17 Läufe), in der Nachricht wirkt
    /// sie (3/3). Ohne Ausnahme-Halbsatz — wer aussetzen will, nutzt `kurz:` oder den Knopf.
    static func mainSkillsHint(for skills: [String]) -> String {
        let list = skills.map { "`\($0)`" }.joined(separator: ", ")
        return "Pflicht für diese Aufgabe: Rufe ZUERST das Skill-Tool auf — je ein eigener "
            + "Aufruf für \(list). Vor jeder Analyse, vor jedem Read, vor dem ersten Satz "
            + "Antwort. Ein Read der SKILL.md lädt einen Skill NICHT."
    }

    private static var installedCache: Set<String>?

    /// Wie `installedSkills()`, aber gecacht — für Aufrufe, die pro Render-Pass laufen.
    /// Der Bestand ändert sich während eines Chats nicht; neu installierte Skills sieht die
    /// App nach einem Neustart.
    static func installedSkillsCached() -> Set<String> {
        if let c = installedCache { return c }
        let fresh = installedSkills()
        installedCache = fresh
        return fresh
    }

    /// Wortgrenzen-Prüfung ohne Regex: Nachbarzeichen dürfen nicht alphanumerisch sein.
    private static func containsWord(_ needle: String, in haystack: String) -> Bool {
        var searchStart = haystack.startIndex
        while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            let beforeOK = range.lowerBound == haystack.startIndex
                || !haystack[haystack.index(before: range.lowerBound)].isLetterOrDigit
            let afterOK = range.upperBound == haystack.endIndex
                || !haystack[range.upperBound].isLetterOrDigit
            if beforeOK && afterOK { return true }
            searchStart = range.upperBound
        }
        return false
    }
}

private extension Character {
    var isLetterOrDigit: Bool { isLetter || isNumber }
}
