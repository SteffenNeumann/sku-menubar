import Foundation

/// Merkt sich pro CLI-Session, welcher Agent sie zuletzt beantwortet hat.
///
/// Das CLI-Transcript (`~/.claude/projects/…/<sessionId>.jsonl`) kennt keinen Agentennamen —
/// der steckt nur im `--system-prompt`, und der landet nicht in der Datei. Ohne diesen Store
/// verlor jeder wieder geöffnete Chat (also nach jedem Neustart/Deploy) sein Agent-Badge.
///
/// Grenze: pro Session nur EIN Eintrag (der letzte Agent). Wer mitten in der Session den
/// Agenten wechselt, sieht beim Wiederöffnen alle Antworten mit dem letzten Agenten.
struct SessionAgentStore {
    struct Entry: Codable, Equatable {
        var agentId: String
        var agentName: String
        var updatedAt: Date
    }

    static let shared = SessionAgentStore()

    /// Obergrenze, damit die Map nicht unbegrenzt wächst — die ältesten fliegen raus.
    static let maxEntries = 1000

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = UserDefaults(suiteName: "SKUMenuBar") ?? .standard,
         key: String = "sessionAgentMap") {
        self.defaults = defaults
        self.key = key
    }

    func entry(for sessionId: String) -> Entry? {
        load()[sessionId]
    }

    func remember(sessionId: String, agentId: String, agentName: String, at date: Date = Date()) {
        guard !sessionId.isEmpty, !agentId.isEmpty else { return }
        var map = load()
        if let existing = map[sessionId], existing.agentId == agentId, existing.agentName == agentName {
            return   // unverändert → kein Schreibzugriff bei jeder Folge-Nachricht
        }
        map[sessionId] = Entry(agentId: agentId, agentName: agentName, updatedAt: date)
        if map.count > Self.maxEntries {
            let overflow = map.count - Self.maxEntries
            for (sid, _) in map.sorted(by: { $0.value.updatedAt < $1.value.updatedAt }).prefix(overflow) {
                map.removeValue(forKey: sid)
            }
        }
        save(map)
    }

    /// Session lief zuletzt ohne Agent → Eintrag entfernen.
    func forget(sessionId: String) {
        var map = load()
        guard map.removeValue(forKey: sessionId) != nil else { return }
        save(map)
    }

    private func save(_ map: [String: Entry]) {
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: key)
        }
    }

    private func load() -> [String: Entry] {
        guard let data = defaults.data(forKey: key),
              let map = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return map
    }
}
