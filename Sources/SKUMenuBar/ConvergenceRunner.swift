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
Du bist Implementor. Setze NUR die accepted[]-Items aus der DesignDecision um. Berühre keine anderen Files.

WICHTIG: Antworte AUSSCHLIESSLICH mit JSON:
{
  "files_changed": [
    { "path": "<string>", "summary": "<was geändert wurde>", "new_content": "<vollständiger neuer Dateiinhalt>" }
  ],
  "notes": "<string>"
}
Liefere in new_content den kompletten, fertigen Dateiinhalt (nicht nur den Diff).
"""
        let systemPrompt = input.implementor.promptBody + jsonSuffix

        let acceptedList = decision.accepted
            .map { "[\($0.refIssue)] \($0.implementationNote)" }
            .joined(separator: "\n")

        let message = """
Setze folgende Design-Entscheidungen um:

\(acceptedList)

Datei: \(input.filePath)

Aktueller Inhalt:
\(input.fileContent)
"""
        let result = try await callAgentJSON(systemPrompt: systemPrompt, message: message,
                                             as: ImplementationResult.self, onText: onText)

        // Extract new file content if implementor provided it
        let newContent: String
        if let changed = result.filesChanged.first(where: { $0.newContent != nil && !($0.newContent!.isEmpty) }) {
            newContent = changed.newContent!
        } else {
            newContent = input.fileContent
        }

        return (result, newContent)
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
        // Extract first {...} block (handles markdown code fences and surrounding text)
        let jsonStr: String
        if let start = raw.range(of: "{"), let end = raw.range(of: "}", options: .backwards) {
            jsonStr = String(raw[start.lowerBound..<end.upperBound])
        } else {
            jsonStr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let data = jsonStr.data(using: .utf8) else {
            throw ConvergenceError.parseError("Invalid UTF-8 in agent response")
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ConvergenceError.parseError("Could not decode \(T.self): \(error.localizedDescription)\nRaw: \(raw.prefix(300))")
        }
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
