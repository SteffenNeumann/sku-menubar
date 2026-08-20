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
