import Foundation
import UserNotifications

// MARK: - CustomerInquiryWorkflow
// Orchestrates the full 5-phase lifecycle of an automated customer inquiry:
// 1. Receive & analyze email  →  2. Clarification (if needed)  →  3. Autonomous work
// 4. Document in Linear       →  5. Notify user

@MainActor
final class CustomerInquiryWorkflow: ObservableObject {

    @Published var recentInquiries: [CustomerInquiry] = []

    weak var cliService: ClaudeCLIService?
    weak var agentService: AgentService?
    weak var linearService: LinearService?
    weak var emailPollingService: EmailPollingService?

    var anthropicApiKey: String = ""
    private let anthropicAPI = AnthropicService()

    var linearTeamId: String = ""
    private var teamStates: [LinearIssueState] = []

    private func log(_ msg: String) {
        let path = NSHomeDirectory() + "/.claude/inquiry_debug.log"
        let line = "[\(Date())] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if let fh = FileHandle(forWritingAtPath: path) { fh.seekToEndOfFile(); fh.write(data); fh.closeFile() }
            else { FileManager.default.createFile(atPath: path, contents: data) }
        }
    }

    private let ud = UserDefaults(suiteName: "SKUMenuBar") ?? .standard
    private let inquiriesKey = "customer_inquiries_v1"
    private let maxStored = 200

    init(cliService: ClaudeCLIService, agentService: AgentService) {
        self.cliService   = cliService
        self.agentService = agentService
        loadInquiries()
    }

    // MARK: - Linear setup (called after services are configured)

    func configureLinear(_ service: LinearService) async {
        linearService = service
        await service.loadTeams()
        log("[Inquiry] Linear teams loaded: \(service.teams.map(\.name)), error: \(service.error ?? "none")")
        if linearTeamId.isEmpty { linearTeamId = service.teams.first?.id ?? "" }
        if !linearTeamId.isEmpty {
            teamStates = await service.loadIssueStates(teamId: linearTeamId)
            log("[Inquiry] Linear configured: team=\(linearTeamId), states=\(teamStates.map(\.name))")
        } else {
            log("[Inquiry] Linear: no team found — issue creation will be skipped")
        }
    }

    // MARK: - Phase 1: New email received

    func processNewEmail(_ inquiry: CustomerInquiry) async {
        log("processNewEmail: \(inquiry.subject) from \(inquiry.senderAddress)")
        var inquiry = inquiry
        inquiry.status = .analyzing
        upsert(inquiry)

        // Route to persona
        let persona = routePersona(for: inquiry)
        inquiry.matchedPersonaId = persona?.id
        upsert(inquiry)

        // Analyze
        let result = await analyzeEmail(inquiry: inquiry, persona: persona)
        switch result {
        case .failure(let e):
            fail(&inquiry, "Analyse-Fehler: \(e.localizedDescription)")
            return
        case .success(let analysis):
            inquiry.priority            = analysis.priority
            inquiry.analysisSummary     = analysis.summary
            inquiry.missingInfo         = analysis.missingInfo
            inquiry.suggestedLinearTitle = analysis.suggestedLinearTitle
        }

        // Create Linear issue
        let issueId = await createLinearIssue(for: &inquiry)
        inquiry.linearIssueId = issueId

        if !inquiry.missingInfo.isEmpty {
            // Phase 2: needs clarification
            inquiry.status = .waitingForCustomer
            upsert(inquiry)
            await sendClarificationDraft(for: inquiry, persona: persona)
            await updateLinearStatus(issueId: issueId, to: "started")  // "Waiting for Customer"
            await addLinearComment(issueId: issueId, body: clarificationComment(inquiry))
        } else {
            // Phase 3: enough info → work on it immediately
            inquiry.status = .inProgress
            upsert(inquiry)
            await updateLinearStatus(issueId: issueId, to: "started")
            await executeTask(inquiry: &inquiry, persona: persona)
        }

        notify(for: inquiry)
    }

    // MARK: - Re-process existing inquiry

    func reprocess(_ inquiry: CustomerInquiry) async {
        log("reprocess: \(inquiry.subject), linearTeamId=\(linearTeamId), linearSvc=\(linearService != nil)")
        var inquiry = inquiry
        inquiry.status = .analyzing
        inquiry.completionSummary = nil
        inquiry.errorMessage = nil
        upsert(inquiry)

        let persona = routePersona(for: inquiry)
        inquiry.matchedPersonaId = persona?.id

        // Re-analyze if no summary yet
        if inquiry.analysisSummary == nil {
            let result = await analyzeEmail(inquiry: inquiry, persona: persona)
            switch result {
            case .failure(let e):
                fail(&inquiry, "Analyse-Fehler: \(e.localizedDescription)")
                return
            case .success(let analysis):
                inquiry.priority            = analysis.priority
                inquiry.analysisSummary     = analysis.summary
                inquiry.missingInfo         = analysis.missingInfo
                inquiry.suggestedLinearTitle = analysis.suggestedLinearTitle
            }
        }

        // Create Linear issue if missing
        if inquiry.linearIssueId == nil {
            let issueId = await createLinearIssue(for: &inquiry)
            inquiry.linearIssueId = issueId
        }
        upsert(inquiry)

        // Execute
        inquiry.status = .inProgress
        upsert(inquiry)
        await updateLinearStatus(issueId: inquiry.linearIssueId, to: "started")
        await executeTask(inquiry: &inquiry, persona: persona)
        notify(for: inquiry)
    }

    // MARK: - Phase 2→3: Customer replied with clarification

    func handleCustomerReply(for inquiry: CustomerInquiry, replyBody: String) async {
        var inquiry = inquiry
        // replyMessageIds already updated by caller before this method is invoked
        let combined = """
Original inquiry:
\(inquiry.body)

Customer reply:
\(replyBody)
"""
        inquiry.body = combined
        inquiry.missingInfo = []
        inquiry.status = .inProgress
        upsert(inquiry)

        await addLinearComment(issueId: inquiry.linearIssueId,
                               body: "**Antwort vom Kunden erhalten:**\n\n\(replyBody.prefix(2000))")
        await updateLinearStatus(issueId: inquiry.linearIssueId, to: "started")

        let persona = routePersona(for: inquiry)
        await executeTask(inquiry: &inquiry, persona: persona)
        notify(for: inquiry)
    }

    // MARK: - Phase 3: Autonomous task execution

    private func executeTask(inquiry: inout CustomerInquiry, persona: AgentDefinition?) async {
        guard !anthropicApiKey.isEmpty else {
            fail(&inquiry, "Kein Anthropic API Key konfiguriert")
            return
        }

        let systemPrompt = buildExecutionPrompt(inquiry: inquiry, persona: persona)
        let userMessage   = buildExecutionMessage(inquiry: inquiry)

        let modelId: String
        if let m = persona?.model, !m.isEmpty {
            modelId = resolveModelId(m)
        } else {
            modelId = "claude-sonnet-4-6-20250514"
        }

        do {
            log("executeTask: starting direct API call (model=\(modelId))")
            let output = try await anthropicAPI.sendMessage(
                apiKey: anthropicApiKey,
                model: modelId,
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                maxTokens: 8192
            )
            log("executeTask: API completed, output length=\(output.count)")

            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            inquiry.completionSummary = String(trimmed.prefix(1000))
            inquiry.status = .completed
            upsert(inquiry)

            let finalComment = buildCompletionComment(inquiry: inquiry, output: trimmed)
            await addLinearComment(issueId: inquiry.linearIssueId, body: finalComment)
            await updateLinearStatus(issueId: inquiry.linearIssueId, to: "completed")

            if let emailSvc = emailPollingService, !inquiry.senderAddress.isEmpty {
                let body = buildCompletionEmail(inquiry: inquiry, output: trimmed, persona: persona)
                try? await emailSvc.createDraftReply(
                    to: inquiry.senderAddress,
                    subject: "Re: \(inquiry.subject)",
                    body: body
                )
            }
        } catch {
            log("executeTask ERROR: \(error)")
            fail(&inquiry, "Ausführungsfehler: \(error.localizedDescription)")
            await addLinearComment(issueId: inquiry.linearIssueId,
                                   body: "❌ **Fehler bei Ausführung:**\n\n\(error.localizedDescription)")
            await updateLinearStatus(issueId: inquiry.linearIssueId, to: "started")
        }
    }

    private func resolveModelId(_ shortName: String) -> String {
        switch shortName.lowercased() {
        case "haiku":  return "claude-haiku-4-5-20251001"
        case "sonnet": return "claude-sonnet-4-6-20250514"
        case "opus":   return "claude-opus-4-6-20250514"
        default:       return shortName
        }
    }

    // MARK: - Routing

    func routePersona(for inquiry: CustomerInquiry) -> AgentDefinition? {
        guard let agents = agentService?.agents else { return nil }
        let personas = agents.filter { $0.isPersona }
        let addr   = inquiry.senderAddress.lowercased()
        let domain = addr.components(separatedBy: "@").last ?? ""

        // Priority 1: exact address
        if let match = personas.first(where: {
            let a = ($0.emailAddress ?? "").lowercased()
            return !a.isEmpty && a == addr
        }) { return match }

        // Priority 2: domain
        if let match = personas.first(where: {
            let d = ($0.emailDomain ?? "").lowercased()
            return !d.isEmpty && d == domain
        }) { return match }

        // Priority 3: agent named "support"
        if let match = agents.first(where: { $0.id.lowercased().contains("support") }) {
            return match
        }

        // Priority 4: first agent
        return agents.first
    }

    // MARK: - Claude analysis (Phase 1 triage)

    private struct EmailAnalysis {
        let priority: Int
        let summary: String
        let missingInfo: [String]
        let suggestedLinearTitle: String
    }

    private func analyzeEmail(
        inquiry: CustomerInquiry,
        persona: AgentDefinition?
    ) async -> Result<EmailAnalysis, Error> {
        guard !anthropicApiKey.isEmpty else {
            return .failure(NSError(domain: "Workflow", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Kein Anthropic API Key konfiguriert — bitte in Settings hinterlegen"]))
        }

        let personaCtx: String
        if let p = persona {
            personaCtx = """
Matching customer persona: \(p.name)
Industry: \(p.industry ?? "unknown")
Tech level: \(p.techLevel ?? "medium")
Tone: \(p.tone ?? "formal")
Priorities: \(p.priorities.joined(separator: ", "))
Dealbreakers: \(p.dealbreakers.joined(separator: ", "))
"""
        } else {
            personaCtx = "No matching persona. Treat as a general business inquiry."
        }

        let system = "You are an expert customer service triage analyst. Always respond with a single valid JSON object — no markdown fences, no preamble."

        let userPrompt = """
Analyze the following customer email and return this exact JSON:
{
  "priority": <1=urgent|2=high|3=medium|4=low>,
  "summary": "<1-2 sentence summary of what the customer needs>",
  "missingInfo": ["<item 1>", "<item 2>"],
  "suggestedLinearTitle": "<concise Linear issue title, max 80 chars, starts with verb>"
}

Rules:
- priority 1 = production outage, data loss, security issue
- priority 2 = blocked workflow or time-sensitive deadline
- priority 3 = feature request, question, general issue (DEFAULT)
- priority 4 = compliments, FYI, newsletter
- missingInfo: list what info is still needed. Return [] if request is complete and actionable.
- suggestedLinearTitle: e.g. "Investigate login failure for Mueller GmbH"

\(personaCtx)

Subject: \(inquiry.subject)
From: \(inquiry.senderName) <\(inquiry.senderAddress)>

\(inquiry.body.prefix(6000))
"""

        do {
            log("analyzeEmail: starting direct API call (model=haiku)")
            let raw = try await anthropicAPI.sendMessage(
                apiKey: anthropicApiKey,
                model: "claude-haiku-4-5-20251001",
                systemPrompt: system,
                userMessage: userPrompt,
                maxTokens: 1024
            )
            log("analyzeEmail: API completed, raw=\(raw.prefix(300))")

            let jsonStr: String
            if let start = raw.range(of: "{"), let end = raw.range(of: "}", options: .backwards) {
                jsonStr = String(raw[start.lowerBound...end.upperBound])
            } else { jsonStr = raw }

            struct AnalysisJSON: Decodable {
                let priority: Int
                let summary: String
                let missingInfo: [String]
                let suggestedLinearTitle: String
            }
            guard let data = jsonStr.data(using: .utf8),
                  let obj  = try? JSONDecoder().decode(AnalysisJSON.self, from: data) else {
                return .failure(NSError(domain: "Workflow", code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "JSON-Parsing fehlgeschlagen: \(raw.prefix(200))"]))
            }
            return .success(EmailAnalysis(
                priority: max(1, min(4, obj.priority)),
                summary: obj.summary,
                missingInfo: obj.missingInfo,
                suggestedLinearTitle: obj.suggestedLinearTitle
            ))
        } catch {
            log("analyzeEmail ERROR: \(error)")
            return .failure(error)
        }
    }

    // MARK: - Linear helpers

    @discardableResult
    private func createLinearIssue(for inquiry: inout CustomerInquiry) async -> String? {
        guard !linearTeamId.isEmpty else {
            log("[Inquiry] Linear: skipped — no teamId configured")
            return nil
        }
        guard let svc = linearService else {
            log("[Inquiry] Linear: skipped — service not available")
            return nil
        }
        do {
            let title  = inquiry.suggestedLinearTitle ?? "Kundenanfrage: \(inquiry.subject)"
            let desc   = buildLinearDescription(for: inquiry)
            let raw    = try await svc.createIssue(
                teamId: linearTeamId,
                title: title,
                description: desc,
                priority: inquiry.priority ?? 3
            )
            log("[Inquiry] Linear createIssue raw: \(raw.prefix(500))")
            if let result = extractIssueId(from: raw) {
                inquiry.linearIssueIdentifier = result.identifier
                log("[Inquiry] Linear issue created: \(result.id), identifier: \(result.identifier ?? "nil")")
                return result.id
            }
            log("[Inquiry] Linear: could not extract issue ID from response")
            return nil
        } catch {
            log("[Inquiry] Linear createIssue error: \(error)")
            return nil
        }
    }

    private func updateLinearStatus(issueId: String?, to stateType: String) async {
        guard let id = issueId, !id.isEmpty, let svc = linearService else { return }
        if let stateId = svc.stateId(for: stateType, in: teamStates) {
            try? await svc.updateIssueStatus(issueId: id, stateId: stateId)
        }
    }

    private func addLinearComment(issueId: String?, body: String) async {
        guard let id = issueId, !id.isEmpty, let svc = linearService else { return }
        try? await svc.addComment(issueId: id, body: body)
    }

    // MARK: - Prompt builders

    private func buildExecutionPrompt(inquiry: CustomerInquiry, persona: AgentDefinition?) -> String {
        var parts: [String] = []

        if let p = persona {
            parts.append(agentService?.fullSystemPrompt(for: p) ?? p.promptBody)
        }

        parts.append("""
## Customer Inquiry Task

You are handling a real customer request. Execute the work — do NOT just describe what you would do.

Rules:
1. READ the customer's email carefully and identify the concrete deliverable they need.
2. DO the work: write the text, create the document, draft the response, research the answer — whatever is needed.
3. PRODUCE the actual output in your response (not a plan or promise).
4. End with a brief "## Ergebnis" section (2-3 sentences) summarizing what you delivered.

Bad example: "I will create a professional email template..." — this is just a description.
Good example: Actually writing the email template, then summarizing "Created responsive HTML email template with header, 3-column layout, and footer."

If you cannot complete the task (missing access, unclear scope), explain specifically what is blocking you.
""")
        return parts.joined(separator: "\n\n")
    }

    private func buildExecutionMessage(inquiry: CustomerInquiry) -> String {
        """
Customer: \(inquiry.senderName.isEmpty ? inquiry.senderAddress : "\(inquiry.senderName) <\(inquiry.senderAddress)>")
Subject: \(inquiry.subject)

Triage: \(inquiry.analysisSummary ?? "N/A")

Full email:
---
\(inquiry.body.prefix(6000))
---

Execute this request now. Produce the actual deliverable the customer needs — not a description of what you would do.
"""
    }

    private func buildLinearDescription(for inquiry: CustomerInquiry) -> String {
        var parts: [String] = ["## Kundenanfrage"]
        parts.append("**Von:** \(inquiry.senderName) <\(inquiry.senderAddress)>")
        parts.append("**Betreff:** \(inquiry.subject)")
        parts.append("**Empfangen:** \(inquiry.receivedAt.formatted(date: .abbreviated, time: .shortened))")
        if let pid = inquiry.matchedPersonaId { parts.append("**Persona:** \(pid)") }
        if let s = inquiry.analysisSummary { parts.append("\n## Zusammenfassung\n\(s)") }
        if !inquiry.missingInfo.isEmpty {
            let items = inquiry.missingInfo.map { "- \($0)" }.joined(separator: "\n")
            parts.append("\n## Fehlende Informationen\n\(items)")
        }
        parts.append("\n## Original-E-Mail\n```\n\(inquiry.body.prefix(3000))\n```")
        return parts.joined(separator: "\n")
    }

    private func clarificationComment(_ inquiry: CustomerInquiry) -> String {
        let items = inquiry.missingInfo.map { "- \($0)" }.joined(separator: "\n")
        return "📬 **Rückfrage-Entwurf erstellt.** Warte auf Antwort des Kunden.\n\n**Fehlende Infos:**\n\(items)"
    }

    private func buildCompletionComment(inquiry: CustomerInquiry, output: String) -> String {
        let summary = String(output.prefix(1500))
        return """
✅ **Anfrage abgeschlossen**

**Ergebnis:**
\(summary)

---
*Automatisch bearbeitet von Agent: \(inquiry.matchedPersonaId ?? "unbekannt")*
"""
    }

    private func buildCompletionEmail(inquiry: CustomerInquiry, output: String, persona: AgentDefinition?) -> String {
        let tone = persona?.tone ?? "formal"
        let greeting: String
        if inquiry.senderName.isEmpty {
            greeting = "Sehr geehrte Damen und Herren,"
        } else if tone == "informal" {
            greeting = "Hallo \(inquiry.senderName.components(separatedBy: " ").first ?? inquiry.senderName),"
        } else {
            greeting = "Sehr geehrte/r \(inquiry.senderName),"
        }
        let summary = String(output.prefix(800))
        return """
\(greeting)

vielen Dank für Ihre Anfrage zu "\(inquiry.subject)".

Hier ist unsere Rückmeldung:

\(summary)

Bei weiteren Fragen stehen wir Ihnen gerne zur Verfügung.

Mit freundlichen Grüßen
[Ihr Team]

---
[ENTWURF — bitte vor dem Senden prüfen]
"""
    }

    private func sendClarificationDraft(for inquiry: CustomerInquiry, persona: AgentDefinition?) async {
        guard let emailSvc = emailPollingService, !inquiry.senderAddress.isEmpty else { return }
        let tone = persona?.tone ?? "formal"
        let greeting: String
        if inquiry.senderName.isEmpty {
            greeting = "Sehr geehrte Damen und Herren,"
        } else if tone == "informal" {
            greeting = "Hallo \(inquiry.senderName.components(separatedBy: " ").first ?? inquiry.senderName),"
        } else {
            greeting = "Sehr geehrte/r \(inquiry.senderName),"
        }
        let items = inquiry.missingInfo.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let body = """
\(greeting)

vielen Dank für Ihre Anfrage zu "\(inquiry.subject)".

Um Ihre Anfrage optimal bearbeiten zu können, benötigen wir noch folgende Informationen:

\(items)

Bitte antworten Sie auf diese E-Mail mit den entsprechenden Details.

Mit freundlichen Grüßen
[Ihr Team]

---
[ENTWURF — bitte vor dem Senden prüfen]
"""
        try? await emailSvc.createDraftReply(
            to: inquiry.senderAddress,
            subject: "Re: \(inquiry.subject)",
            body: body
        )
    }

    // MARK: - Notification

    private func notify(for inquiry: CustomerInquiry) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        switch inquiry.status {
        case .waitingForCustomer:
            content.title = "Rückfrage-Entwurf bereit"
            content.subtitle = inquiry.suggestedLinearTitle ?? inquiry.subject
            content.body = "Von: \(inquiry.senderName.isEmpty ? inquiry.senderAddress : inquiry.senderName)"
        case .completed:
            content.title = "Anfrage abgeschlossen ✓"
            content.subtitle = inquiry.suggestedLinearTitle ?? inquiry.subject
            content.body = "Linear aktualisiert · Abschluss-Entwurf erstellt"
        case .blocked, .failed:
            content.title = "Anfrage blockiert ⚠️"
            content.subtitle = inquiry.suggestedLinearTitle ?? inquiry.subject
            content.body = inquiry.errorMessage ?? "Manuelle Überprüfung erforderlich"
        default:
            content.title = "Neue Kundenanfrage"
            content.subtitle = inquiry.suggestedLinearTitle ?? inquiry.subject
            content.body = "Von: \(inquiry.senderName.isEmpty ? inquiry.senderAddress : inquiry.senderName)"
        }
        let req = UNNotificationRequest(identifier: inquiry.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    // MARK: - Persistence

    private func upsert(_ inquiry: CustomerInquiry) {
        if let idx = recentInquiries.firstIndex(where: { $0.id == inquiry.id }) {
            recentInquiries[idx] = inquiry
        } else {
            recentInquiries.insert(inquiry, at: 0)
            if recentInquiries.count > maxStored {
                recentInquiries = Array(recentInquiries.prefix(maxStored))
            }
        }
        persist()
    }

    private func fail(_ inquiry: inout CustomerInquiry, _ msg: String) {
        inquiry.status = .failed
        inquiry.errorMessage = msg
        upsert(inquiry)
    }

    private func loadInquiries() {
        guard let d = ud.data(forKey: inquiriesKey),
              let items = try? JSONDecoder().decode([CustomerInquiry].self, from: d) else { return }
        recentInquiries = items
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(recentInquiries) {
            ud.set(d, forKey: inquiriesKey)
        }
    }

    // MARK: - Helpers

    private func extractIssueId(from raw: String) -> (id: String, identifier: String?)? {
        // Linear MCP returns text like:
        // "Successfully created issue\nIssue: INT-240\nTitle: ...\nURL: ..."
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Issue:") {
                let identifier = trimmed.dropFirst("Issue:".count).trimmingCharacters(in: .whitespaces)
                if !identifier.isEmpty {
                    return (identifier, identifier)
                }
            }
        }
        // Fallback: try JSON (issueCreate.issue.id)
        if let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let issue = (json["issueCreate"] as? [String: Any])?["issue"] as? [String: Any],
           let id = issue["id"] as? String {
            return (id, issue["identifier"] as? String)
        }
        return nil
    }
}
