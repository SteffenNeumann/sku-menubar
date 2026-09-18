import Foundation

/// TEMPORÄRE Diagnose: Wo gehen `model`/`agentName` einer Antwort verloren?
/// Schreibt nach ~/Library/Logs/myClaude-badge.log. Nach dem Fund wieder entfernen.
enum BadgeDiag {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/myClaude-badge.log")
    private static let queue = DispatchQueue(label: "BadgeDiag")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static func log(_ line: String) {
        let stamp = formatter.string(from: Date())
        let data = Data("\(stamp) \(line)\n".utf8)
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    static func describe(_ msg: ChatMessage?) -> String {
        guard let msg else { return "—" }
        return "id=\(msg.id.uuidString.prefix(8)) model=\(msg.model ?? "nil") agent=\(msg.agentName ?? "nil") streaming=\(msg.isStreaming) len=\(msg.content.count) skills=\(msg.usedSkills.count)"
    }
}

extension BadgeDiag {
    // Nur MainActor-Zugriffe (ChatView) — kein Lock nötig.
    nonisolated(unsafe) private static var seenFirst = Set<String>()
    nonisolated(unsafe) private static var lastSync = [UUID: String]()

    static func firstEvent(_ idx: Int, _ tab: UUID) -> Bool {
        seenFirst.insert("\(tab)-\(idx)").inserted
    }

    static func changed(_ tab: UUID, _ desc: String) -> Bool {
        guard lastSync[tab] != desc else { return false }
        lastSync[tab] = desc
        return true
    }
}
