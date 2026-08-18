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
    ]

    /// Tatsächlich installierte Skills (~/.claude/skills/<name>/SKILL.md).
    static func installedSkills(fileManager: FileManager = .default) -> Set<String> {
        let dir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills")
        guard let entries = try? fileManager.contentsOfDirectory(atPath: dir.path) else { return [] }
        return Set(entries.filter { name in
            fileManager.fileExists(atPath: dir.appendingPathComponent("\(name)/SKILL.md").path)
        })
    }

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
