import Foundation

// MARK: - Convergence Loop Schemas
// Codable structs for the three agent outputs in the co-design loop.
// System-prompt suffixes instruct each agent to respond with these exact JSON shapes.

// MARK: CritiqueReport — output of Persona agent (Critic role)

struct CritiqueIssue: Codable, Identifiable {
    var id: String          // e.g. "iss-1"
    var area: String        // hero|nav|typography|color|spacing|content|…
    var severity: IssueSeverity
    var what: String
    var whyItMattersTome: String

    enum CodingKeys: String, CodingKey {
        case id, area, severity, what
        case whyItMattersTome = "why_it_matters_to_me"
    }
}

enum IssueSeverity: String, Codable {
    case blocker, major, minor
}

struct CritiqueSuggestion: Codable {
    var refIssue: String    // matches CritiqueIssue.id
    var idea: String
    var mustHave: Bool

    enum CodingKeys: String, CodingKey {
        case idea
        case refIssue    = "ref_issue"
        case mustHave    = "must_have"
    }
}

enum CritiqueVerdict: String, Codable {
    case approve
    case revise
    case rejectFinal = "reject_final"
}

struct CritiqueReport: Codable {
    var verdict: CritiqueVerdict
    var overallImpression: String
    var issues: [CritiqueIssue]
    var suggestions: [CritiqueSuggestion]

    enum CodingKeys: String, CodingKey {
        case verdict, issues, suggestions
        case overallImpression = "overall_impression"
    }

    var hasMustHaveOpen: Bool {
        suggestions.contains { $0.mustHave }
    }
}

// MARK: DesignDecision — output of frontend-webdesigner agent (Designer role)

struct AcceptedItem: Codable {
    var refIssue: String
    var implementationNote: String

    enum CodingKeys: String, CodingKey {
        case refIssue           = "ref_issue"
        case implementationNote = "implementation_note"
    }
}

struct RejectedItem: Codable {
    var refIssue: String
    var reason: String
    var counterProposal: String?

    enum CodingKeys: String, CodingKey {
        case refIssue       = "ref_issue"
        case reason
        case counterProposal = "counter_proposal"
    }
}

struct DesignDecision: Codable {
    var feasible: Bool
    var accepted: [AcceptedItem]
    var rejected: [RejectedItem]
    var openQuestions: [String]

    enum CodingKeys: String, CodingKey {
        case feasible, accepted, rejected
        case openQuestions = "open_questions"
    }

    var allRejectedWithoutAlternative: Bool {
        !feasible && rejected.allSatisfy { $0.counterProposal == nil || $0.counterProposal!.isEmpty }
    }
}

// MARK: ImplementationResult — output of backend-developer agent (Implementor role)

struct FileChange: Codable {
    var path: String
    var summary: String
    var newContent: String?     // optional: full new file content (written to disk)

    enum CodingKeys: String, CodingKey {
        case path, summary
        case newContent = "new_content"
    }
}

struct ImplementationResult: Codable {
    var filesChanged: [FileChange]
    var notes: String

    enum CodingKeys: String, CodingKey {
        case notes
        case filesChanged = "files_changed"
    }
}

// MARK: - Session State

enum ConvergencePhase: String, Equatable {
    case idle
    case critic         // Persona reviewing
    case designer       // frontend-webdesigner deciding
    case implementor    // backend-developer writing
    case converged
    case escalation
    case cancelled
}

enum EscalationReason: String {
    case capReached                     = "cap_reached"
    case stalemate                      = "stalemate"
    case rejectFinal                    = "reject_final"
    case designerInfeasibleNoAlternative = "designer_infeasible"
}

// MARK: - Iteration Snapshot

struct ConvergenceSnapshot: Identifiable {
    let id = UUID()
    let iteration: Int
    let fileContent: String         // file state after this iteration
    let critique: CritiqueReport?
    let decision: DesignDecision?
    let implementation: ImplementationResult?
    let createdAt: Date
}
