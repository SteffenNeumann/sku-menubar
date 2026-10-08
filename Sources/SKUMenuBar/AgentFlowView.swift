import SwiftUI

/// Agent-Flussbild im rechten Chat-Panel: Haupt-Claude oben, darunter die Subagenten als Karten,
/// Verbindungen zeigen, wer wen beauftragt hat. Laufende Aufträge: Punkt wandert zum Helfer;
/// gerade fertig gewordene: Punkt wandert zurück. Layout aus SubagentLayout (überlappt nie).
struct AgentFlowView: View {
    let graph: SubagentGraph
    let accent: Color
    let onClose: () -> Void
    @Environment(\.appTheme) var theme

    var body: some View {
        let layout = SubagentLayout.frames(for: graph)
        VStack(spacing: 0) {
            header
            Rectangle().fill(theme.cardBorder).frame(height: 0.5)
            if graph.isEmpty {
                emptyState
            } else {
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            edges(layout.frames)
                            rootCard.frame(width: SubagentLayout.card.width, height: SubagentLayout.card.height)
                                .offset(origin(layout.frames[SubagentLayout.rootKey]))
                            ForEach(graph.nodes) { node in
                                AgentFlowCard(node: node, accent: accent)
                                    .frame(width: SubagentLayout.card.width, height: SubagentLayout.card.height)
                                    .offset(origin(layout.frames[node.id]))
                            }
                        }
                        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                        // Schmaler Baum: mittig im Panel statt links angeklebt.
                        .frame(minWidth: geo.size.width, alignment: .top)
                    }
                }
            }
        }
        .background(theme.windowBg)
    }

    private func origin(_ r: CGRect?) -> CGSize {
        CGSize(width: r?.minX ?? 0, height: r?.minY ?? 0)
    }

    // MARK: Kopf

    private var header: some View {
        let active = graph.nodes.filter(\.isActive).count
        return HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
            Text("Agenten")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.primaryText)
            if !graph.isEmpty {
                Text(active > 0 ? "\(active) aktiv" : "\(graph.nodes.count) fertig")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(active > 0 ? accent : theme.tertiaryText)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.tertiaryText)
            }
            .buttonStyle(.plain)
            .help("Agenten-Panel ausblenden")
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 26))
                .foregroundStyle(theme.tertiaryText)
            Text("Noch keine Helfer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            Text("Sobald Claude in dieser Antwort einen Agenten beauftragt, erscheint er hier als Karte.")
                .font(.system(size: 12))
                .foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: Haupt-Claude

    private var rootCard: some View {
        let active = graph.hasActive
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Haupt-Claude")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.primaryText)
                Spacer(minLength: 4)
                AgentFlowPill(text: active ? "verteilt" : "fertig",
                              color: active ? accent : theme.statusGreen)
            }
            Text("Beauftragt \(graph.children(of: nil).count) Agent\(graph.children(of: nil).count == 1 ? "" : "en")")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.cardSurface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? accent : theme.cardBorder, lineWidth: 1))
    }

    // MARK: Verbindungen

    @ViewBuilder
    private func edges(_ frames: [String: CGRect]) -> some View {
        if graph.nodes.contains(where: { $0.status == .running }) {
            // Konvention (siehe BouncingDot): TimelineView .periodic mit 10 fps, render-only,
            // und nur solange ein Vordergrund-Agent läuft — danach steht das Bild still
            // (Hintergrund-Agenten können den Stream überdauern, sie animieren nicht).
            TimelineView(.periodic(from: .now, by: 1.0 / 10.0)) { ctx in
                Canvas { gc, _ in drawEdges(gc, frames: frames, time: ctx.date) }
            }
        } else {
            Canvas { gc, _ in drawEdges(gc, frames: frames, time: nil) }
        }
    }

    private func drawEdges(_ gc: GraphicsContext, frames: [String: CGRect], time: Date?) {
        for node in graph.nodes {
            guard let to = frames[node.id],
                  let from = frames[node.parentId ?? SubagentLayout.rootKey] else { continue }
            let p0 = CGPoint(x: from.midX, y: from.maxY)
            let p3 = CGPoint(x: to.midX, y: to.minY)
            let midY = (p0.y + p3.y) / 2
            let p1 = CGPoint(x: p0.x, y: midY), p2 = CGPoint(x: p3.x, y: midY)
            var path = Path()
            path.move(to: p0)
            path.addCurve(to: p3, control1: p1, control2: p2)

            let color = edgeColor(node.status)
            let dashed = node.isActive
            let phase = time.map { CGFloat($0.timeIntervalSinceReferenceDate * 20).truncatingRemainder(dividingBy: 10) } ?? 0
            gc.stroke(path, with: .color(color.opacity(dashed ? 0.9 : 0.6)),
                      style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                         dash: dashed ? [4, 6] : [], dashPhase: -phase))

            // Wandernder Punkt: Auftrag hin (läuft) oder Ergebnis zurück (vor < 3 s fertig).
            guard let time else { continue }
            var t: CGFloat?
            let cycle = CGFloat(time.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4)
            if node.status == .running {
                t = cycle
            } else if let f = node.finishedAt, time.timeIntervalSince(f) < 3 {
                t = 1 - cycle
            }
            if let t {
                let pt = bezier(p0, p1, p2, p3, t)
                gc.fill(Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                        with: .color(color))
            }
        }
    }

    private func edgeColor(_ s: SubagentNode.Status) -> Color {
        switch s {
        case .running, .background: return accent
        case .done:                 return theme.statusGreen
        case .failed, .denied:      return theme.statusRed
        }
    }

    private func bezier(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let x = u*u*u*a.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*d.x
        let y = u*u*u*a.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*d.y
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Karte

private struct AgentFlowCard: View {
    let node: SubagentNode
    let accent: Color
    @Environment(\.appTheme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(node.type)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                AgentFlowPill(text: statusText, color: statusColor)
            }
            Text(node.task.isEmpty ? "–" : node.task)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(2)
                .help(node.task)
            if !node.skills.isEmpty {
                HStack(spacing: 4) {
                    ForEach(node.skills.prefix(2), id: \.self) { s in
                        Text(s)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(accent.opacity(0.14)))
                            .foregroundStyle(accent)
                    }
                    if node.skills.count > 2 {
                        Text("+\(node.skills.count - 2)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
                .help(node.skills.joined(separator: ", "))
            }
            Spacer(minLength: 0)
            progress
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(theme.cardSurface))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(statusColor.opacity(node.isActive ? 1 : 0.7), lineWidth: 1))
    }

    @ViewBuilder
    private var progress: some View {
        HStack(spacing: 6) {
            if node.status == .done {
                bar(1, color: theme.statusGreen)
                Text("100 %")
            } else if node.todosTotal > 0 {
                bar(CGFloat(node.todosDone) / CGFloat(node.todosTotal), color: statusColor)
                Text("\(node.todosDone)/\(node.todosTotal)")
            } else if node.isActive {
                // Ohne Todo-Liste gibt es keinen ehrlichen Prozentwert — nur den Schritt-Zähler.
                Text("läuft · \(node.toolCount) Schritte" + (node.lastTool.map { " · \($0)" } ?? ""))
                    .lineLimit(1)
            } else {
                Text(node.status == .denied ? "kein App-Agent / gesperrt" : "abgebrochen")
            }
            if let tk = node.tokens, !node.isActive {
                Spacer(minLength: 0)
                Text("\(tk / 1000)k Tok.")
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(theme.tertiaryText)
    }

    private func bar(_ f: CGFloat, color: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.cardBorder)
                Capsule().fill(color).frame(width: g.size.width * min(max(f, 0), 1))
            }
        }
        .frame(height: 5)
    }

    private var statusText: String {
        switch node.status {
        case .running:    return "läuft"
        case .background: return "Hintergrund"
        case .done:       return "fertig"
        case .failed:     return "Fehler"
        case .denied:     return "gesperrt"
        }
    }

    private var statusColor: Color {
        switch node.status {
        case .running, .background: return accent
        case .done:                 return theme.statusGreen
        case .failed, .denied:      return theme.statusRed
        }
    }
}

private struct AgentFlowPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
