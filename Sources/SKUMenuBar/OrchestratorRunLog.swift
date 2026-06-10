import Foundation

// MARK: - Orchestrator Run-Log (V4)
// Strukturiertes Protokoll jedes Orchestrierungs-Laufs als JSON-Zeile (JSONL).
// Zweck: Fehlerdiagnose ohne Nachstellen — Phasen-Timing, Plan-Parse-Pfad und
// per-Agent-Ergebnis (Dauer/failed/Subtyp/Idle-Timeout) sind nachlesbar.

struct OrchestratorRunLog: Codable {
    struct AgentEntry: Codable {
        let name: String
        let model: String
        let durationSec: Double
        let outputChars: Int
        let failed: Bool
        let resultSubtype: String      // "" wenn kein result-Event kam
        let hitMaxTurns: Bool
        let idleTimeout: Bool          // Idle-Watchdog hat diesen Agent abgebrochen
    }

    let runId: String                  // UUID des Laufs
    let startedAt: Date
    var mode: String                   // "auto" | "manual" | "fast"
    var agentNames: [String] = []
    var phase0Sec: Double? = nil       // Domain-Analyse (nil = übersprungen)
    var phase1Sec: Double? = nil       // Master-Plan
    var phase2Sec: Double? = nil       // Agent-Execution
    var phase3Sec: Double? = nil       // Synthese
    var planParsedVia: String = ""     // "json" | "text" | "legacy" | "fallback" | "none"
    var agents: [AgentEntry] = []
    var outcome: String = ""           // "ok" | "solo" | "aborted" | "plan-empty" | "plan-cancelled" | "all-failed"

    init(mode: String) {
        self.runId = UUID().uuidString
        self.startedAt = Date()
        self.mode = mode
    }
}

enum OrchestratorRunLogger {
    /// Serielle Queue — verhindert verschränkte Zeilen, wenn zwei Tabs gleichzeitig
    /// eine Orchestrierung abschließen (seekToEnd+write ist nicht atomar).
    private static let writeQueue = DispatchQueue(label: "myClaude.orchestratorRunLog", qos: .utility)

    /// Zielpfad: ~/Library/Application Support/myClaude/orchestrator-runs.jsonl
    static var logFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
            .appendingPathComponent("myClaude", isDirectory: true)
        return base.appendingPathComponent("orchestrator-runs.jsonl")
    }

    /// Hängt einen abgeschlossenen Lauf als eine JSON-Zeile an. Fehler werden bewusst
    /// verschluckt — Logging darf die Pipeline niemals beeinträchtigen.
    static func append(_ log: OrchestratorRunLog) {
        writeQueue.async {
            do {
                let dir = logFileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                var data = try encoder.encode(log)
                data.append(0x0A)   // newline → JSONL
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    let handle = try FileHandle(forWritingTo: logFileURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } else {
                    try data.write(to: logFileURL)
                }
            } catch {
                // bewusst still — Logging ist Best-Effort
            }
        }
    }
}
