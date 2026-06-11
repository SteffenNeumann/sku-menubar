import Foundation

// MARK: - Geteilte Orchestrator-Typen (vorher private in ChatView)

enum MasterTodoStatus: Equatable {
    case pending, active, done, skipped, blocked
}

struct MasterTodoItem: Identifiable {
    let id: String
    let number: String
    let title: String
    let assignedAgent: String?
    let level: Int              // 0 = Top-Level Kategorie, 1 = ausführbarer Schritt
    var status: MasterTodoStatus
}

/// Intent einer Follow-Up-Nachricht nach einer Orchestrierung.
enum FollowUpIntent {
    case chat       // Frage/Danke → normaler Einzelagent, kein Orchestrator-Overhead
    case fast       // "go"/"weiter"/"mach das" → Phase 0 überspringen, schnelleres Re-Planning
    case full       // Komplett neues Thema → volle 4-Phasen-Pipeline
}

// MARK: - Zentrale Limits
// Eine Quelle für alle Orchestrator-Grenzwerte — vorher waren z.B. suffix(6) und die
// Zeichen-Caps an drei Stellen dupliziert.

enum OrchestratorLimits {
    /// Anzahl History-Einträge, die als Kontext in Prompts injiziert werden (≈3 Runden).
    static let historyWindow = 6
    /// Obergrenze des orchestratorHistory-Arrays selbst (beim Append getrimmt).
    static let historyMaxEntries = 20
    /// Zeichen-Cap je History-Eintrag im Plan-/Direktantwort-Kontext.
    static let historyEntryCapPlan = 500
    /// Zeichen-Cap je History-Eintrag im Phase-2-Agent-Kontext.
    static let historyEntryCapPhase2 = 800
    /// Zeichen-Cap für Fremd-Agent-Outputs im Phase-2-Kontext (P4).
    static let foreignOutputCap = 1500
    /// Hard-Cap der Agent-Anzahl bei Auto-Orchestrierung.
    static let maxAgents = 4
    /// maxTurns-Default je Orchestrator-Agent, wenn keine Settings greifen.
    static let defaultMaxTurns = 60
    /// Mindest-Turns je Orchestrator-Agent (MCP-lastige Aufgaben brauchen viele Tool-Calls).
    static let minAgentTurns = 30
    /// Idle-Timeout-Default (Sekunden ohne Stream-Event, bis ein Agent abgebrochen wird).
    static let defaultIdleTimeoutSec = 120
}

// MARK: - Pure Orchestrator-Logik (testbar — kein View-/State-/Service-Zugriff)

enum OrchestratorLogic {

    // MARK: Trigger-Matching

    /// Checks whether `input` matches a trigger phrase.
    /// Three tiers:
    ///  1. Full-phrase: "code review" matches trigger "code review"
    ///  2. Word-level: "review" matches trigger "code review" (word in phrase)
    ///  3. Prefix: "review" matches trigger "Reviewer" (input is prefix of trigger word, or vice versa)
    static func inputMatchesTrigger(_ input: String, trigger: String) -> Bool {
        let inputL   = input.lowercased()
        let triggerL = trigger.lowercased()
        // 1. Full phrase match
        if inputL.contains(triggerL) { return true }
        let inputWords   = inputL.components(separatedBy: .whitespacesAndNewlines).filter { $0.count >= 3 }
        let triggerWords = triggerL.components(separatedBy: .whitespacesAndNewlines).filter { $0.count >= 3 }
        // 2. Any trigger word as a substring of the input
        if triggerWords.contains(where: { inputL.contains($0) }) { return true }
        // 3. Bidirectional prefix: "review" matches "reviewer", "reviewing"
        return inputWords.contains { iw in
            triggerWords.contains { tw in tw.hasPrefix(iw) || iw.hasPrefix(tw) }
        }
    }

    // MARK: Komplexitäts-Heuristik

    /// Heuristik: true = Aufgabe ist komplex genug für Orchestrierung.
    /// Berücksichtigt Wortanzahl, mehrere Aufgaben-Verben und Mehrdomain-Konjunktionen.
    /// Dient als schnelle Vorfilterung — bei Auto-Orchestrierung folgt ein LLM-Validation-Check.
    static func isComplexTask(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count > 15 else { return false }   // Kurz → immer einfach
        guard words.count <= 300 else { return true }  // Sehr lang → immer komplex
        if words.count > 40 { return true }            // Mittellang & ausführlich → komplex

        let lower = text.lowercased()
        // Aufgaben-Verben — DE + EN (Word-Set-Matching statt substring um
        // "explanation" → "plan", "findings" → "find" etc. zu vermeiden)
        let taskVerbs: Set<String> = ["erstelle", "entwickle", "implementiere", "analysiere",
                         "überprüfe", "prüfe", "untersuche", "schreibe", "entwerfe",
                         "plane", "optimiere", "recherchiere", "vergleiche", "bewerte",
                         "dokumentiere", "strukturiere", "baue", "konfiguriere",
                         "konzipiere", "stelle", "finde", "erkläre", "beschreibe",
                         "zeige", "führe", "gib", "erstell", "entwickl",
                         "identifiziere", "schlage", "empfehle", "überleg",
                         // English verbs
                         "create", "build", "implement", "analyze", "review",
                         "investigate", "write", "design", "plan", "optimize",
                         "research", "compare", "evaluate", "document", "configure",
                         "find", "explain", "describe", "identify", "recommend"]
        let wordSet = Set(lower.split(separator: " ").map { String($0) })
        let verbCount = taskVerbs.intersection(wordSet).count
        if verbCount >= 2 { return true }
        // Konjunktionen die einen neuen Themenbereich einleiten
        let complexConjunctions = [" sowie ", " außerdem ", " zusätzlich ",
                                   " darüber hinaus ", " einerseits ", " andererseits ",
                                   " zum einen ", " zum anderen ", " gleichzeitig ",
                                   " und auch ", " aber auch ", " und prüfe",
                                   " und analysiere", " und stelle", " und finde",
                                   " furthermore ", " additionally ", " and also "]
        return complexConjunctions.contains { lower.contains($0) }
    }

    // MARK: Follow-Up-Klassifikation

    /// Erkennt Erklär-/Verständnis-/Status-Fragen zum bestehenden Orchestrierungs-Ergebnis.
    /// Solche Nachfragen sollen aus dem vorhandenen Kontext (Plan + Synthese) beantwortet
    /// werden — nicht eine neue Agent-Orchestrierung auslösen.
    static func isExplanationOrQuestion(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.hasSuffix("?") { return true }
        // Verben/Phrasen, die eine Erklärung des Bestehenden anfordern (Prefix-Match am Satzanfang)
        let explainPrefixes = ["erläuter", "erklär", "erklar", "beschreib", "schilder",
                               "fasse", "fass ", "zeig mir", "zeig mal", "nenn mir", "nenne mir",
                               "was ist", "was sind", "was bedeutet", "was genau", "was macht",
                               "wie funktioniert", "wie läuft", "wie wird", "wie sieht",
                               "wieso", "weshalb", "verstehe nicht", "ich verstehe",
                               "kannst du erklär", "kannst du erläuter", "kannst du beschreib",
                               "explain", "describe", "what is", "what are", "what does",
                               "how does", "how do", "tell me"]
        return explainPrefixes.contains { lower.hasPrefix($0) }
    }

    /// M1: Erkennt, ob neben einer Erklärbitte noch eine ZWEITE, eigenständige Handlungsaufgabe
    /// steht (z.B. „Fasse zusammen UND baue dann Tests"). Ein Verbindungswort leitet dabei ein
    /// Handlungsverb ein. Solche Composite-Sätze sind keine reine Erklärfrage.
    static func containsAdditionalActionTask(_ text: String) -> Bool {
        let lower = text.lowercased()
        // (a) Verbindung + Verb direkt verschmolzen → eindeutig eine zweite Aufgabe.
        let verbContinuations = [
            " und baue", " und erstelle", " und erstell", " und implementiere", " und schreibe",
            " und entwickle", " und füge", " und ergänze", " und teste", " und deploy",
            " und aktualisiere", " und ändere", " und optimiere", " und repariere", " und fixe",
            " and build", " and create", " and add", " and implement", " and write",
            " and test", " and update"]
        if verbContinuations.contains(where: { lower.contains($0) }) { return true }
        // (b) Reines Verbindungswort (dann/danach/then) NUR werten, wenn zusätzlich irgendwo ein
        //     Handlungsverb als ganzes Wort steht — sonst ist "…, danach reden wir" ein
        //     False-Positive (temporales Adverb ohne Folgeaufgabe).
        let continuations = [" und dann ", " und danach ", " und anschließend ",
                             " und zusätzlich ", " then ", " and then "]
        guard continuations.contains(where: { lower.contains($0) }) else { return false }
        let actionVerbs: Set<String> = ["baue", "erstelle", "erstell", "implementiere", "schreibe",
            "entwickle", "füge", "ergänze", "teste", "deploy", "aktualisiere", "ändere",
            "optimiere", "repariere", "fixe", "mach", "setze", "lege", "build", "create",
            "add", "implement", "write", "test", "update", "make", "refactor"]
        let wordSet = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        return !actionVerbs.isDisjoint(with: wordSet)
    }

    /// Klassifiziert Follow-Up-Nachrichten nach Intent wenn ein Orchestrierungs-Kontext besteht.
    /// Vermeidet redundantes Re-Planning bei "go" / "ok" / Bestätigungen.
    static func classifyFollowUp(_ text: String) -> FollowUpIntent {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = lower.split(separator: " ")
        let wordSet = Set(words.map { String($0) })

        // 1) Triviale Bestätigungen/Danke → Chat
        //    Exakt-Match ODER Nachricht beginnt mit Trivialem + enthält neue Aufgabe
        let trivialWords: Set<String> = ["danke", "super", "perfekt", "gut", "cool",
                                          "thanks", "great", "nice", "passt", "👍"]
        let trivialPhrases = ["alles klar", "ok danke", "passt danke", "passt soweit",
                              "sieht gut aus", "looks good"]
        if trivials(lower, trivialPhrases) || (words.count == 1 && !trivialWords.isDisjoint(with: wordSet)) {
            return .chat
        }

        // 2) Nachricht beginnt mit Trivialem/Danke + enthält NEUE Anweisung
        //    → Chat (User hat Orchestrierung abgeschlossen, will was Einfaches)
        //    z.B. "Passt danke - bitte aufräumen und commit"
        let startsWithTrivial = trivialWords.contains(where: { lower.hasPrefix($0) })
            || trivialPhrases.contains(where: { lower.hasPrefix($0) })
        let hasNewTask: Set<String> = ["aufräumen", "cleanup", "commit", "push",
                                        "speicher", "save", "memory", "schließ", "close"]
        if startsWithTrivial && !wordSet.isDisjoint(with: hasNewTask) { return .chat }

        // 3) Fragen → Chat (Einzelagent reicht)
        if lower.hasSuffix("?") { return .chat }
        let questionStarts = ["was ", "wie ", "warum ", "wann ", "wo ", "welche ",
                              "wer ", "kannst ", "what ", "how ", "why ", "when ",
                              "where ", "which ", "who ", "can ", "could "]
        if questionStarts.contains(where: { lower.hasPrefix($0) }) { return .chat }

        // 3b) Erklär-/Verständnis-Anfragen zum bestehenden Ergebnis → Chat (direkt beantworten,
        //     nicht neu orchestrieren — auch wenn sie länger sind, z.B. "Erläutere mir noch wie …").
        //     M1-Ausnahme: Steht zusätzlich eine zweite, eigenständige Handlungsaufgabe im Satz
        //     ("Fasse zusammen UND baue dann Tests"), ist es keine reine Erklärfrage → ausführen.
        if isExplanationOrQuestion(text) {
            return containsAdditionalActionTask(text) ? .fast : .chat
        }

        // 4) Reine Ausführungs-Befehle (NUR wenn die Nachricht primär ein Befehl ist)
        //    "go" / "weiter" / "mach das" → fast
        //    Aber NICHT wenn daneben eine neue eigenständige Aufgabe steht
        let pureExecuteWords: Set<String> = ["go", "ja", "weiter", "los",
                               "proceed", "continue", "implementiere", "umsetzen",
                               "loslegen", "ausführen", "run", "einverstanden", "agreed"]
        let executePhrases = ["mach das", "bitte umsetzen", "fang an", "do it",
                              "genau so", "let's go", "bitte machen"]
        if words.count <= 6 {
            if !wordSet.isDisjoint(with: pureExecuteWords) { return .fast }
            if executePhrases.contains(where: { lower.contains($0) }) { return .fast }
        }

        // 5) Längere Nachricht → prüfe ob wirklich komplex
        if isComplexTask(text) { return .full }

        // 6) Default: Chat (sicherer als blind orchestrieren)
        return .chat
    }

    /// Prüft ob der gesamte Text einem trivialen Ausdruck entspricht (exact oder prefix+kurz)
    private static func trivials(_ lower: String, _ phrases: [String]) -> Bool {
        phrases.contains(where: { lower == $0 || (lower.hasPrefix($0) && lower.count <= $0.count + 3) })
    }

    // MARK: Agent-Name-Auflösung (H3)

    /// Löst einen vom LLM geschriebenen Agent-Namen gegen die echten Agents auf.
    /// Exakter Match bevorzugt, dann normalisierter Fuzzy-Contains:
    /// `-`/`_`/Leerzeichen werden normalisiert ("Data Analyst" ↔ "data-analyst"); bei
    /// Mehrdeutigkeit ("Designer" ↔ "ux-designer") gewinnt der LÄNGSTE Kandidatenname
    /// (deterministisch statt abhängig von der Array-Reihenfolge).
    static func resolveAgent(named name: String, in agents: [AgentDefinition]) -> AgentDefinition? {
        if let exact = agents.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) { return exact }
        func norm(_ s: String) -> String {
            s.lowercased()
             .replacingOccurrences(of: "-", with: " ")
             .replacingOccurrences(of: "_", with: " ")
             .trimmingCharacters(in: .whitespaces)
        }
        let target = norm(name)
        guard !target.isEmpty else { return nil }
        let candidates = agents.filter { a in
            guard !a.name.isEmpty else { return false }
            let an = norm(a.name)
            return an.contains(target) || target.contains(an)
        }
        return candidates.max(by: { $0.name.count < $1.name.count })
    }

    /// P4: Löst ein `agent`-Feld auf, das MEHRERE Namen enthalten kann (Trenner: ",", "&", "/",
    /// " und ", " and "). Gibt die eindeutige Liste der getroffenen Agents in Reihenfolge zurück
    /// (leer, wenn keiner matcht). Verhindert den stillen Verlust bei Sammelschritten wie
    /// "data-analyst, excel-vba-developer", die `resolveAgent` sonst auf nur EINEN reduziert.
    static func resolveAgents(named raw: String?, in agents: [AgentDefinition]) -> [AgentDefinition] {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return [] }
        let normalizedSeparators = raw
            .replacingOccurrences(of: " und ", with: ",")
            .replacingOccurrences(of: " and ", with: ",")
        let parts = normalizedSeparators
            .components(separatedBy: CharacterSet(charactersIn: ",&/"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let names = parts.isEmpty ? [raw] : parts
        var result: [AgentDefinition] = []
        for n in names {
            if let a = resolveAgent(named: n, in: agents),
               !result.contains(where: { $0.id == a.id }) {
                result.append(a)
            }
        }
        return result
    }

    // MARK: Phase-0-Parsing (Bulk-Analyse)

    /// Ordnet die gebündelte Domain-Analyse (ein Haiku-Call für alle Agents, P3) je Agent zu.
    /// Erwartet pro Zeile "<AgentName>: <Beitrag>". Fehlt eine Zeile, bleibt die Analyse leer.
    static func parseBulkAnalysis(_ text: String, agents: [AgentDefinition]) -> [(name: String, analysis: String)] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "") }
            .filter { !$0.isEmpty }
        return agents.map { agent in
            let name = agent.name.lowercased()
            var analysis = ""
            if let line = lines.first(where: {
                let l = $0.lowercased()
                return l.hasPrefix(name + ":") || l.hasPrefix("- " + name + ":")
            }), let colon = line.range(of: ":") {
                analysis = String(line[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            return (name: agent.name, analysis: analysis)
        }
    }

    // MARK: Phase-1-Parsing (Master-Plan)

    /// Parses "AGENT: Name\nAUFGABE: ..." blocks from the orchestrator plan (Legacy-Format).
    static func parseOrchestratorPlan(_ plan: String, agents: [AgentDefinition]) -> [String: String] {
        var result: [String: String] = [:]
        let lines = plan.components(separatedBy: .newlines)
        var currentAgentId: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("AGENT:") {
                let name = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "**", with: "")
                currentAgentId = agents.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }?.id
            } else if trimmed.uppercased().hasPrefix("AUFGABE:"), let agentId = currentAgentId {
                result[agentId] = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                currentAgentId = nil
            }
        }
        return result
    }

    /// Parst den hierarchischen Master-Plan (ZIEL: + 1. / 1.1 → Agent Format).
    /// Gibt (goal, todos, agentTasks) zurück.
    ///
    /// Robust gegenüber LLM-Artefakten:
    ///  - Markdown-Fettdruck (**), führende Listenzeichen (-, •, *)
    ///  - Trailing-Interpunktion am Nummerntoken (1.1:, 1.1., 1))
    ///  - Mehrere Sub-Items pro Agent → werden zusammengeführt
    ///  - Canonical Agent-Name gespeichert (nicht roher LLM-String)
    ///  - Exakter Match bevorzugt vor fuzzy Contains (mit -/_-Normalisierung, H3)
    static func parseMasterPlan(_ plan: String, agents: [AgentDefinition])
        -> (goal: String, todos: [MasterTodoItem], agentTasks: [String: String]) {

        var goal = ""
        var todos: [MasterTodoItem] = []
        var agentTasks: [String: String] = [:]
        let trailingPunct = CharacterSet(charactersIn: ".:)")
        let listChars    = CharacterSet(charactersIn: "-•* \t")

        for line in plan.components(separatedBy: .newlines) {
            let raw = line.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }

            // ZIEL: Zeile
            if raw.uppercased().hasPrefix("ZIEL:") {
                goal = String(raw.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                continue
            }

            // Normalisieren: **Markdown** + führende Listenzeichen entfernen
            let normalized = raw
                .replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: listChars)
            guard !normalized.isEmpty else { continue }

            // Nummerierungstoken + Rest extrahieren
            let spaceIdx = normalized.firstIndex(of: " ") ?? normalized.endIndex
            // Trailing-Interpunktion am Token abschneiden ("1.1:" → "1.1", "1." → "1")
            let firstToken = String(normalized[..<spaceIdx])
                .trimmingCharacters(in: trailingPunct)
            let rest = spaceIdx < normalized.endIndex
                ? String(normalized[normalized.index(after: spaceIdx)...])
                    .trimmingCharacters(in: .whitespaces)
                : ""
            guard !rest.isEmpty else { continue }

            let dotParts = firstToken.components(separatedBy: ".")

            // Sub-Item: "1.1" — beide Komponenten nicht leer + beide Int
            if dotParts.count == 2,
               let _ = Int(dotParts[0]),
               !dotParts[1].isEmpty,
               let _ = Int(dotParts[1]) {

                let num = firstToken
                let sep = rest.contains("→") ? "→" : "->"
                let parts = rest.components(separatedBy: sep)
                let title = parts[0].trimmingCharacters(in: .whitespaces)
                let rawAgent: String? = parts.count > 1
                    ? parts[1].trimmingCharacters(in: .whitespaces) : nil

                let resolved = rawAgent.flatMap { resolveAgent(named: $0, in: agents) }
                // Canonical name (aus Agent-Profil, nicht roher LLM-String) für zuverlässige Status-Updates
                let canonicalName = resolved?.name ?? rawAgent

                if let agent = resolved {
                    // Mehrere Sub-Items pro Agent → zusammenführen statt überschreiben
                    if let existing = agentTasks[agent.id] {
                        agentTasks[agent.id] = existing + "\n- " + title
                    } else {
                        agentTasks[agent.id] = title
                    }
                }

                todos.append(MasterTodoItem(id: num, number: num, title: title,
                                            assignedAgent: canonicalName, level: 1, status: .pending))
                continue
            }

            // Top-Level Kategorie: "1." → dotParts = ["1",""] oder "1" (nach trailing strip)
            let isTopLevel = (dotParts.count == 2 && Int(dotParts[0]) != nil && dotParts[1].isEmpty)
                          || (dotParts.count == 1 && Int(dotParts[0]) != nil
                              && (raw.contains(".") || raw.contains(")")))
            if isTopLevel {
                let num = dotParts[0]
                todos.append(MasterTodoItem(id: "\(num).", number: "\(num).", title: rest,
                                            assignedAgent: nil, level: 0, status: .pending))
            }
        }

        return (goal, todos, agentTasks)
    }

    // MARK: Phase-1-Parsing (JSON-Format, V6)

    private struct PlanStepJSON: Decodable {
        let nr: String?
        let titel: String?
        let agent: String?
        // Englische Schlüssel tolerieren (LLM-Drift)
        let id: String?
        let title: String?
    }
    private struct PlanJSON: Decodable {
        let ziel: String?
        let goal: String?
        let schritte: [PlanStepJSON]?
        let steps: [PlanStepJSON]?
    }

    /// Parst den Master-Plan im JSON-Format (primärer Pfad seit V6). Gibt nil zurück, wenn der
    /// Text kein verwertbares JSON enthält — der Caller fällt dann auf parseMasterPlan (Text) zurück.
    static func parsePlanJSON(_ raw: String, agents: [AgentDefinition])
        -> (goal: String, todos: [MasterTodoItem], agentTasks: [String: String])? {
        // Code-Fences/Umgebungstext tolerieren: erstes { bis letztes } extrahieren
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}"),
              start < end,
              let data = String(raw[start...end]).data(using: .utf8),
              let plan = try? JSONDecoder().decode(PlanJSON.self, from: data) else { return nil }

        let goal = (plan.ziel ?? plan.goal ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = plan.schritte ?? plan.steps ?? []
        guard !steps.isEmpty else { return nil }

        // Schritte erst SAMMELN (Titel + Nummer + aufgelöste Agents) und Todos/Tasks danach bauen.
        // So kann bei 0 Treffern eine positionsbasierte Recovery greifen, statt non-nil mit leerem
        // agentTasks zurückzugeben (was im Caller den "alle machen alles"-Fallback auslöste).
        struct ParsedStep { let num: String; let title: String; let resolved: [AgentDefinition] }
        var parsed: [ParsedStep] = []
        for (i, step) in steps.enumerated() {
            let title = (step.titel ?? step.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let rawNum = (step.nr ?? step.id ?? "").trimmingCharacters(in: .whitespaces)
            let num = rawNum.isEmpty ? "\(i + 1)" : rawNum
            // P4: agent-Feld kann mehrere Namen tragen → alle auflösen.
            parsed.append(ParsedStep(num: num, title: title,
                                     resolved: resolveAgents(named: step.agent, in: agents)))
        }
        guard !parsed.isEmpty else { return nil }

        var agentTasks: [String: String] = [:]
        func assign(_ agentId: String, _ title: String) {
            if let existing = agentTasks[agentId] {
                agentTasks[agentId] = existing + "\n- " + title
            } else {
                agentTasks[agentId] = title
            }
        }

        // P2-Recovery: Konnte KEIN Schritt einem Agent zugeordnet werden (agent fehlt, ist ein
        // Platzhalter wie "AgentName" oder ein übersetzter/erfundener Name), die Schritt-Titel
        // positionsbasiert (round-robin) auf die gewählten Agents verteilen — sinnvolle Teil-
        // aufgaben statt eines undifferenzierten Gesamtauftrags an alle.
        let anyResolved = parsed.contains { !$0.resolved.isEmpty }
        let usePositional = !anyResolved && !agents.isEmpty

        var todos: [MasterTodoItem] = []
        for (i, p) in parsed.enumerated() {
            let assignedName: String?
            if usePositional {
                let agent = agents[i % agents.count]
                assign(agent.id, p.title)
                assignedName = agent.name
            } else {
                for a in p.resolved { assign(a.id, p.title) }
                assignedName = p.resolved.first?.name
            }
            // id muss eindeutig sein (Identifiable) — Index anhängen falls Nummer doppelt vorkommt
            let uid = todos.contains(where: { $0.id == p.num }) ? "\(p.num)#\(i)" : p.num
            todos.append(MasterTodoItem(id: uid, number: p.num, title: p.title,
                                        assignedAgent: assignedName, level: 1, status: .pending))
        }

        // P1: Nie non-nil mit leerem agentTasks. Nur nil, wenn wirklich nichts zugeordnet werden
        // konnte (z.B. agents-Liste leer) — dann greift im Caller bewusst der Gesamtauftrag-Fallback.
        guard !todos.isEmpty, !agentTasks.isEmpty else { return nil }
        return (goal, todos, agentTasks)
    }

    // MARK: Plan-Formatierung

    /// Formatiert einen Master-Plan als lesbaren Text (für Panel-Anzeige + Kontext-Injektion).
    static func formatPlan(goal: String, todos: [MasterTodoItem]) -> String {
        var lines: [String] = []
        if !goal.isEmpty {
            lines.append("🎯 ZIEL: \(goal)")
            lines.append("")
        }
        for item in todos {
            let indent = item.level == 1 ? "   " : ""
            let icon: String
            switch item.status {
            case .pending:  icon = "○"
            case .active:   icon = "▶"
            case .done:     icon = "✓"
            case .skipped:  icon = "⏸"
            case .blocked:  icon = "⚠"
            }
            let agent = item.assignedAgent.map { " → \($0)" } ?? ""
            lines.append("\(indent)\(icon) \(item.number) \(item.title)\(agent)")
        }
        return lines.joined(separator: "\n")
    }
}
