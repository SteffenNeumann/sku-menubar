import Foundation
import SwiftUI

// MARK: - ConvergenceRunner
// Executes one iteration of the co-design loop: Critic → Designer → Implementor.
// Each agent call appends a JSON-output suffix to the agent's existing system prompt,
// so the .md files themselves are never modified.

@MainActor
final class ConvergenceRunner {

    private let cli: ClaudeCLIService

    init(cli: ClaudeCLIService) {
        self.cli = cli
    }

    // MARK: - Public: run one round

    struct RoundInput {
        let fileContent: String
        let filePath: String
        let critic: AgentDefinition
        let designer: AgentDefinition
        let implementor: AgentDefinition
        let historyContext: String      // compact 1-line-per-round summary
        let lastCritique: CritiqueReport?
    }

    struct RoundOutput {
        let critique: CritiqueReport
        let decision: DesignDecision
        let implementation: ImplementationResult
        let newFileContent: String      // updated file after implementor
    }

    func runRound(
        input: RoundInput,
        onPhase: @escaping (ConvergencePhase) -> Void,
        onText: @escaping (String) -> Void = { _ in }
    ) async throws -> RoundOutput {

        // --- Step 1: Critic ---
        onPhase(.critic)
        let critique = try await callCritic(input: input, onText: onText)

        // Short-circuit if approved — caller checks this but we still return
        // DesignDecision/ImplementationResult are empty placeholders on approve
        if critique.verdict == .approve {
            let noop = DesignDecision(feasible: true, accepted: [], rejected: [], openQuestions: [])
            let noopImpl = ImplementationResult(filesChanged: [], notes: "No changes — persona approved.")
            return RoundOutput(critique: critique, decision: noop, implementation: noopImpl,
                               newFileContent: input.fileContent)
        }

        // --- Step 2: Designer ---
        onPhase(.designer)
        let decision = try await callDesigner(input: input, critique: critique, onText: onText)

        // Short-circuit if infeasible with no alternatives
        if decision.allRejectedWithoutAlternative {
            let noopImpl = ImplementationResult(filesChanged: [], notes: "Designer: no feasible path.")
            return RoundOutput(critique: critique, decision: decision, implementation: noopImpl,
                               newFileContent: input.fileContent)
        }

        // --- Step 3: Implementor ---
        onPhase(.implementor)
        let (implResult, newContent) = try await callImplementor(
            input: input, critique: critique, decision: decision, onText: onText)

        return RoundOutput(critique: critique, decision: decision,
                           implementation: implResult, newFileContent: newContent)
    }

    // MARK: - Critic call

    private func callCritic(input: RoundInput, onText: @escaping (String) -> Void = { _ in }) async throws -> CritiqueReport {
        let jsonSuffix = """

---
WICHTIG: Antworte AUSSCHLIESSLICH mit JSON nach folgendem Schema (kein Freitext davor/danach):
{
  "verdict": "approve" | "revise" | "reject_final",
  "overall_impression": "<string>",
  "issues": [
    { "id": "iss-1", "area": "<hero|nav|typography|color|spacing|content>",
      "severity": "blocker|major|minor",
      "what": "<string>", "why_it_matters_to_me": "<string>" }
  ],
  "suggestions": [
    { "ref_issue": "iss-1", "idea": "<string>", "must_have": true|false }
  ]
}
Verwende "approve" nur wenn du vollständig zufrieden bist und keine must_have-Suggestions offen sind.
Antworte auf Deutsch aus deiner Ich-Perspektive.
"""
        let systemPrompt = input.critic.promptBody + jsonSuffix

        let historyNote = input.historyContext.isEmpty ? "" : "\n\nBisherige Iterationen (Kurzfassung):\n\(input.historyContext)"
        let lastNote: String
        if let last = input.lastCritique {
            lastNote = "\n\nLetzte Runde: Dein Verdict war '\(last.verdict.rawValue)'. Wichtigste Issues: \(last.issues.prefix(3).map { $0.what }.joined(separator: "; ")). Prüfe ob sie umgesetzt wurden."
        } else {
            lastNote = ""
        }

        let message = """
Bewerte diese Webseite aus deiner persönlichen Sicht.\(historyNote)\(lastNote)

Datei: \(input.filePath)

Quellcode:
\(input.fileContent.prefix(6000))
"""
        return try await callAgentJSON(systemPrompt: systemPrompt, message: message,
                                       as: CritiqueReport.self, onText: onText)
    }

    // MARK: - Designer call

    private func callDesigner(input: RoundInput, critique: CritiqueReport, onText: @escaping (String) -> Void = { _ in }) async throws -> DesignDecision {
        let jsonSuffix = """

---
Du bist Designer-Reviewer. Bewertet jeden Issue aus dem CritiqueReport:
- Umsetzbar → accepted[]
- Nicht umsetzbar oder widerspricht Webdesign-Best-Practices → rejected[] mit counter_proposal
- Unklar → open_questions[] (kein Implementor-Lauf)

WICHTIG: Antworte AUSSCHLIESSLICH mit JSON:
{
  "feasible": true|false,
  "accepted": [ { "ref_issue": "iss-1", "implementation_note": "<string>" } ],
  "rejected": [ { "ref_issue": "iss-2", "reason": "<string>", "counter_proposal": "<string|null>" } ],
  "open_questions": [ "<string>" ]
}
Lehne Wünsche ab wenn: (a) bereits umgesetzt laut Quellcode, (b) technisch unsinnig, (c) widerspricht Webdesign-Guidelines.
"""
        let systemPrompt = input.designer.promptBody + jsonSuffix

        let issueList = critique.issues.map { "[\($0.id)] \($0.what) (severity: \($0.severity.rawValue))" }
            .joined(separator: "\n")
        let suggestionList = critique.suggestions.map { "[\($0.refIssue)] \($0.idea) (must_have: \($0.mustHave))" }
            .joined(separator: "\n")

        let message = """
Persona-Feedback zu dieser Webseite:

Overall: \(critique.overallImpression)

Issues:
\(issueList)

Suggestions:
\(suggestionList)

Aktueller Quellcode:
\(input.fileContent.prefix(5000))
"""
        return try await callAgentJSON(systemPrompt: systemPrompt, message: message,
                                       as: DesignDecision.self, onText: onText)
    }

    // MARK: - Implementor call

    private func callImplementor(
        input: RoundInput,
        critique: CritiqueReport,
        decision: DesignDecision,
        onText: @escaping (String) -> Void = { _ in }
    ) async throws -> (ImplementationResult, String) {
        let jsonSuffix = """

---
⚠️ PFLICHT: Deine gesamte Antwort muss ein einziges JSON-Objekt sein. Kein Freitext, keine Erklärung, kein Markdown außer dem JSON selbst.
Format:
{"files_changed":[{"path":"DATEIPFAD","summary":"Was wurde geändert","new_content":"VOLLSTÄNDIGER DATEIINHALT"}],"notes":"Kurzzusammenfassung"}
new_content = kompletter, fertiger Dateiinhalt (kein Diff, kein Auszug).
Nur accepted[]-Items umsetzen.
"""
        let systemPrompt = input.implementor.promptBody + jsonSuffix

        let acceptedList = decision.accepted
            .map { "[\($0.refIssue)] \($0.implementationNote)" }
            .joined(separator: "\n")

        let message = """
Setze folgende Design-Entscheidungen um und antworte NUR mit JSON:

\(acceptedList)

Datei: \(input.filePath)

Aktueller Inhalt:
\(input.fileContent)

ANTWORT = reines JSON-Objekt, beginnend mit { und endend mit }
"""

        // Graceful fallback: if the agent responds in prose instead of JSON,
        // wrap the text as notes and keep current file content unchanged.
        do {
            let result = try await callAgentJSON(systemPrompt: systemPrompt, message: message,
                                                 as: ImplementationResult.self, onText: onText)
            let newContent: String
            if let changed = result.filesChanged.first(where: { $0.newContent != nil && !($0.newContent!.isEmpty) }) {
                newContent = changed.newContent!
            } else {
                newContent = input.fileContent
            }
            return (result, newContent)
        } catch ConvergenceError.parseError(let msg) {
            // Agent replied in prose — keep current content, store prose as notes
            let raw = msg.components(separatedBy: "Raw: ").dropFirst().joined(separator: "Raw: ")
            let prose = raw.isEmpty ? msg : raw
            let fallback = ImplementationResult(
                filesChanged: [],
                notes: "[Prose-Antwort ohne JSON] " + String(prose.prefix(500))
            )
            return (fallback, input.fileContent)
        }
    }

    // MARK: - Generic agent JSON call

    private func callAgentJSON<T: Decodable>(
        systemPrompt: String,
        message: String,
        as type: T.Type,
        onText: @escaping (String) -> Void = { _ in }
    ) async throws -> T {
        var raw = ""
        let stream = cli.send(message: message, systemPrompt: systemPrompt, model: "sonnet")
        for try await event in stream {
            if event.type == "assistant" {
                if let contents = event.message?.content {
                    for c in contents where c.type == "text" {
                        raw += c.text ?? ""
                        onText(raw)
                    }
                }
            } else if event.type == "result", let resultText = event.result, raw.isEmpty {
                raw = resultText
                onText(raw)
            }
        }

        return try parseJSON(raw, as: type)
    }

    // MARK: - JSON extraction helper

    private func parseJSON<T: Decodable>(_ raw: String, as type: T.Type) throws -> T {
        let candidates = extractJSONCandidates(from: raw)
        var lastError: Error?
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8) else { continue }
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                lastError = error
            }
        }
        let errMsg = lastError?.localizedDescription ?? "No JSON found in response"
        throw ConvergenceError.parseError("Could not decode \(T.self): \(errMsg)\nRaw: \(raw.prefix(400))")
    }

    /// Returns JSON candidates in priority order: fenced blocks first, then balanced extraction.
    private func extractJSONCandidates(from raw: String) -> [String] {
        var results: [String] = []

        // 1. ```json ... ``` fenced block
        if let r = raw.range(of: "```json"),
           let end = raw.range(of: "```", range: r.upperBound..<raw.endIndex) {
            let block = String(raw[r.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if block.hasPrefix("{") { results.append(block) }
        }

        // 2. ``` ... ``` fenced block (without language tag)
        if let r = raw.range(of: "```"),
           let end = raw.range(of: "```", range: r.upperBound..<raw.endIndex) {
            let block = String(raw[r.upperBound..<end.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if block.hasPrefix("{") { results.append(block) }
        }

        // 3. Balanced JSON extraction — correctly handles strings and nested braces
        if let balanced = extractBalancedJSON(from: raw) {
            results.append(balanced)
        }

        // 4. Raw trimmed fallback
        results.append(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        return results
    }

    /// Extracts the first balanced `{...}` JSON object, correctly handling string literals.
    private func extractBalancedJSON(from raw: String) -> String? {
        let chars = Array(raw)
        guard let startOffset = chars.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        for i in startOffset..<chars.count {
            let c = chars[i]
            if escaped { escaped = false; continue }
            if c == "\\" && inString { escaped = true; continue }
            if c == "\"" { inString.toggle(); continue }
            if inString { continue }
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 {
                    let start = raw.index(raw.startIndex, offsetBy: startOffset)
                    let end   = raw.index(raw.startIndex, offsetBy: i)
                    return String(raw[start...end])
                }
            }
        }
        return nil
    }
}

// MARK: - Errors

enum ConvergenceError: LocalizedError {
    case parseError(String)
    case noAgentFound(String)
    case fileWriteError(String)

    var errorDescription: String? {
        switch self {
        case .parseError(let msg):     return "Parse error: \(msg)"
        case .noAgentFound(let msg):   return "Agent not found: \(msg)"
        case .fileWriteError(let msg): return "File write error: \(msg)"
        }
    }
}
