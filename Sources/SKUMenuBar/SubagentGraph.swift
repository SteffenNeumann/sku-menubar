import Foundation
import CoreGraphics

// Reines Modell für das Agent-Flussbild (rechtes Chat-Panel): wer hat wen beauftragt,
// was tut jeder, wie weit ist er. Gefüttert aus dem stream-json der CLI, ohne UI —
// deshalb testbar wie OrchestratorLogic.

/// Ein Subagent, den die CLI per Agent-Tool gestartet hat. id = tool_use-id des Agent-Aufrufs;
/// genau diese id tragen alle Ereignisse des Subagenten als `parent_tool_use_id`.
struct SubagentNode: Identifiable, Equatable {
    enum Status: Equatable {
        case running      // läuft im Vordergrund
        case background   // läuft im Hintergrund (tool_result kam sofort mit async_launched)
        case done
        case failed
        case denied       // per --disallowedTools gesperrt
    }

    let id: String
    let parentId: String?   // nil = vom Haupt-Claude beauftragt
    let type: String
    let task: String
    var status: Status = .running
    var skills: [String] = []
    var todosDone = 0
    var todosTotal = 0
    var toolCount = 0
    var lastTool: String?
    var tokens: Int?
    var finishedAt: Date?

    var isActive: Bool { status == .running || status == .background }
}

struct SubagentGraph: Equatable {
    private(set) var nodes: [SubagentNode] = []

    var isEmpty: Bool { nodes.isEmpty }
    var hasActive: Bool { nodes.contains { $0.isActive } }

    func node(_ id: String) -> SubagentNode? { nodes.first { $0.id == id } }

    func children(of parentId: String?) -> [SubagentNode] {
        nodes.filter { $0.parentId == parentId }
    }

    /// assistant/tool_use mit name "Agent" (früher "Task").
    /// `preloadedSkills`: die per Frontmatter `skills:` vorgeladenen Skills des Agenten — die
    /// CLI meldet sie im Stream nicht, darum kommen sie aus der Agent-Definition.
    mutating func agentStarted(toolUseId: String, parentToolUseId: String?,
                               type: String?, description: String?,
                               preloadedSkills: [String] = []) {
        guard node(toolUseId) == nil else { return }
        // Nur bekannte Eltern übernehmen — so bleibt der Baum zyklenfrei.
        let parent = parentToolUseId.flatMap { node($0) == nil ? nil : $0 }
        let cleanType = type.flatMap { $0.isEmpty ? nil : $0 } ?? "general-purpose"
        nodes.append(SubagentNode(id: toolUseId, parentId: parent, type: cleanType,
                                  task: description ?? "", skills: preloadedSkills))
    }

    /// Jeder andere tool_use, der aus einem Subagenten stammt (parent_tool_use_id gesetzt).
    mutating func toolUsed(byAgent agentId: String, name: String,
                           skill: String?, todoStatuses: [String]?) {
        guard let i = nodes.firstIndex(where: { $0.id == agentId }) else { return }
        nodes[i].toolCount += 1
        nodes[i].lastTool = name
        if name == "Skill", let s = skill?.trimmingCharacters(in: .whitespaces), !s.isEmpty,
           !nodes[i].skills.contains(s) {
            nodes[i].skills.append(s)
        }
        if name == "TodoWrite", let st = todoStatuses, !st.isEmpty {
            nodes[i].todosTotal = st.count
            nodes[i].todosDone = st.filter { $0 == "completed" }.count
        }
    }

    /// user/tool_result zur Agent-id. Bei Hintergrund-Start kommt er sofort mit
    /// status "async_launched" — dann ist der Subagent NICHT fertig.
    mutating func agentReturned(toolUseId: String, isError: Bool, text: String?,
                                resultStatus: String?, tokens: Int?, now: Date = Date()) {
        guard let i = nodes.firstIndex(where: { $0.id == toolUseId }) else { return }
        if isError {
            let denied = text?.contains("denied by permission rule") == true
            nodes[i].status = denied ? .denied : .failed
            nodes[i].finishedAt = now
        } else if resultStatus == "async_launched" {
            nodes[i].status = .background
        } else {
            nodes[i].status = .done
            nodes[i].finishedAt = now
        }
        if let tokens { nodes[i].tokens = tokens }
    }

    /// system/task_notification — Ende eines (Hintergrund-)Subagenten.
    mutating func taskFinished(toolUseId: String, status: String?, tokens: Int?, now: Date = Date()) {
        guard let i = nodes.firstIndex(where: { $0.id == toolUseId }),
              nodes[i].isActive else { return }
        switch status {
        case "completed": nodes[i].status = .done
        case nil:         return
        default:          nodes[i].status = .failed   // failed / killed / error
        }
        nodes[i].finishedAt = now
        if let tokens { nodes[i].tokens = tokens }
    }

    /// Stream zu Ende: was dann noch im Vordergrund „läuft“, ist abgebrochen worden.
    /// Hintergrund-Agenten bleiben stehen — deren Ende kann noch nachkommen.
    mutating func streamEnded(now: Date = Date()) {
        for i in nodes.indices where nodes[i].status == .running {
            nodes[i].status = .failed
            nodes[i].finishedAt = now
        }
    }
}

// MARK: - Layout

/// Baum-Layout, in dem sich Karten nie überlappen: eine Zeile je Ebene, feste Kartengröße,
/// jeder Teilbaum bekommt so viel Breite, wie seine Kinder brauchen. Wird es breiter als
/// das Panel, scrollt das Panel — es wird nichts gestaucht.
enum SubagentLayout {
    static let card = CGSize(width: 200, height: 112)
    static let hGap: CGFloat = 16
    static let vGap: CGFloat = 48
    static let padding: CGFloat = 16
    /// Schlüssel der Haupt-Claude-Karte in `frames`.
    static let rootKey = "__root__"

    static func frames(for graph: SubagentGraph) -> (frames: [String: CGRect], size: CGSize) {
        var widths: [String: CGFloat] = [:]
        func key(_ id: String?) -> String { id ?? rootKey }
        func width(_ id: String?) -> CGFloat {
            if let w = widths[key(id)] { return w }
            let kids = graph.children(of: id)
            let kidsW = kids.map { width($0.id) }.reduce(0, +) + hGap * CGFloat(max(kids.count - 1, 0))
            let w = max(card.width, kidsW)
            widths[key(id)] = w
            return w
        }

        var frames: [String: CGRect] = [:]
        var maxDepth = 0
        func place(_ id: String?, x0: CGFloat, depth: Int) {
            let w = width(id)
            maxDepth = max(maxDepth, depth)
            frames[key(id)] = CGRect(x: x0 + (w - card.width) / 2,
                                     y: padding + CGFloat(depth) * (card.height + vGap),
                                     width: card.width, height: card.height)
            let kids = graph.children(of: id)
            let kidsW = kids.map { width($0.id) }.reduce(0, +) + hGap * CGFloat(max(kids.count - 1, 0))
            var x = x0 + (w - kidsW) / 2
            for kid in kids {
                place(kid.id, x0: x, depth: depth + 1)
                x += width(kid.id) + hGap
            }
        }
        place(nil, x0: padding, depth: 0)
        let size = CGSize(width: width(nil) + padding * 2,
                          height: padding * 2 + CGFloat(maxDepth + 1) * card.height + CGFloat(maxDepth) * vGap)
        return (frames, size)
    }
}
