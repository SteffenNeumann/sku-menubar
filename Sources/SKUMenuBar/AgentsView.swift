import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Agent Avatar (generated character portrait)

private struct AgentAvatarView: View {
    let agent: AgentDefinition
    let size: CGFloat

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [agent.dotColor.opacity(0.85), agent.dotColor.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Subtle noise dots
            AvatarNoiseView(seed: abs(agent.id.hashValue))
                .opacity(0.12)
            // Character figure
            AgentCharacterView(seed: abs(agent.id.hashValue), accent: agent.dotColor, size: size)
        }
        .frame(width: size, height: size)
        .clipShape(Rectangle())
    }
}

// MARK: - Robot Head Icon (Canvas)

private struct RobotHeadIcon: View {
    let size: CGFloat

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width, h = sz.height
            let cx = w / 2, cy = h / 2

            // Antenna stem
            var stem = Path()
            stem.move(to: CGPoint(x: cx, y: cy - h * 0.28))
            stem.addLine(to: CGPoint(x: cx, y: cy - h * 0.42))
            ctx.stroke(stem, with: .color(.white.opacity(0.80)), lineWidth: w * 0.032)
            // Antenna ball
            let aR = w * 0.055
            ctx.fill(Path(ellipseIn: CGRect(x: cx - aR, y: cy - h*0.42 - aR, width: aR*2, height: aR*2)), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - aR*0.4, y: cy - h*0.42 - aR*0.55, width: aR*0.8, height: aR*0.8)), with: .color(.white.opacity(0.5)))

            // Head body
            let hW = w * 0.62, hH = h * 0.50
            let headRect = CGRect(x: cx - hW/2, y: cy - hH/2 + h*0.03, width: hW, height: hH)
            ctx.fill(Path(roundedRect: headRect, cornerRadius: w * 0.09), with: .color(.white.opacity(0.93)))
            ctx.stroke(Path(roundedRect: headRect, cornerRadius: w * 0.09), with: .color(.white.opacity(0.40)), lineWidth: 1.2)

            // Ears
            let eW = w * 0.07, eH = h * 0.22
            let eY = headRect.midY - eH/2
            for xSign in [-1.0, 1.0] {
                let ex = xSign > 0 ? headRect.maxX + 1 : headRect.minX - eW - 1
                ctx.fill(Path(roundedRect: CGRect(x: ex, y: eY, width: eW, height: eH), cornerRadius: 2), with: .color(.white.opacity(0.72)))
            }

            // Eyes
            let eyeY = headRect.minY + hH * 0.33
            let eyeX  = hW * 0.20
            let eyeR  = w * 0.078
            for xOff in [-eyeX, eyeX] {
                ctx.fill(Path(ellipseIn: CGRect(x: cx + xOff - eyeR*1.45, y: eyeY - eyeR*1.45, width: eyeR*2.9, height: eyeR*2.9)), with: .color(.black.opacity(0.07)))
                ctx.fill(Path(ellipseIn: CGRect(x: cx + xOff - eyeR, y: eyeY - eyeR, width: eyeR*2, height: eyeR*2)), with: .color(.black.opacity(0.65)))
                let sR = eyeR * 0.38
                ctx.fill(Path(ellipseIn: CGRect(x: cx + xOff - sR*0.2, y: eyeY - eyeR*0.60, width: sR*2, height: sR*2)), with: .color(.white.opacity(0.95)))
            }

            // Mouth (pixel grid: 3 slots)
            let mW = hW * 0.55, mH = hH * 0.16
            let mX = cx - mW/2, mY = headRect.minY + hH * 0.72
            ctx.fill(Path(roundedRect: CGRect(x: mX, y: mY, width: mW, height: mH), cornerRadius: 2.5), with: .color(.black.opacity(0.22)))
            let gap: CGFloat = 1.8
            let slots = 3
            let slotW = (mW - CGFloat(slots + 1) * gap) / CGFloat(slots)
            for i in 0..<slots {
                let sx = mX + gap + CGFloat(i) * (slotW + gap)
                ctx.fill(Path(roundedRect: CGRect(x: sx, y: mY + 2, width: slotW, height: mH - 4), cornerRadius: 1.2), with: .color(.white.opacity(0.88)))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Deterministic character canvas

private struct AgentCharacterView: View {
    let seed: Int
    let accent: Color
    let size: CGFloat

    // Derive stable personality traits from seed
    private var traits: AvatarTraits { AvatarTraits(seed: seed) }

    var body: some View {
        Canvas { ctx, sz in
            let t = traits
            let cx = sz.width  / 2
            let cy = sz.height / 2

            // ── Body / torso ────────────────────────────────────
            let bodyW = sz.width  * 0.46
            let bodyH = sz.height * 0.30
            let bodyY = cy + sz.height * 0.14
            let bodyRect = CGRect(x: cx - bodyW/2, y: bodyY, width: bodyW, height: bodyH)
            var bodyPath = Path(roundedRect: bodyRect, cornerRadius: bodyW * 0.18)
            ctx.fill(bodyPath, with: .color(.white.opacity(0.22)))

            // Collar / neckline accent
            let collarW = bodyW * 0.38
            let collarRect = CGRect(x: cx - collarW/2, y: bodyY - 2, width: collarW, height: bodyH * 0.28)
            ctx.fill(Path(roundedRect: collarRect, cornerRadius: 3), with: .color(.white.opacity(0.30)))

            // Badge / icon on torso (personality indicator)
            let badgeSize: CGFloat = sz.width * 0.11
            let badgeRect = CGRect(x: cx - badgeSize/2, y: bodyY + bodyH * 0.38, width: badgeSize, height: badgeSize)
            ctx.fill(Path(roundedRect: badgeRect, cornerRadius: 3), with: .color(.white.opacity(0.18)))
            ctx.stroke(Path(roundedRect: badgeRect, cornerRadius: 3), with: .color(.white.opacity(0.35)), lineWidth: 0.8)

            // ── Neck ─────────────────────────────────────────────
            let neckW = sz.width  * 0.13
            let neckH = sz.height * 0.07
            let neckRect = CGRect(x: cx - neckW/2, y: bodyY - neckH, width: neckW, height: neckH + 2)
            ctx.fill(Path(roundedRect: neckRect, cornerRadius: 2), with: .color(.white.opacity(0.25)))

            // ── Head ─────────────────────────────────────────────
            let headR  = sz.width * t.headRadius          // 0.22 – 0.27
            let headCY = cy - sz.height * 0.05
            let headRect = CGRect(x: cx - headR, y: headCY - headR, width: headR*2, height: headR*2)

            // Head shadow
            ctx.fill(
                Path(ellipseIn: headRect.offsetBy(dx: 0, dy: 2).insetBy(dx: -1, dy: -1)),
                with: .color(.black.opacity(0.18))
            )
            // Head fill
            ctx.fill(Path(ellipseIn: headRect), with: .color(.white.opacity(0.92)))
            // Head stroke
            ctx.stroke(Path(ellipseIn: headRect), with: .color(.white.opacity(0.5)), lineWidth: 1.2)

            // ── Hair ─────────────────────────────────────────────
            let hairH = headR * t.hairHeight              // 0.5 – 0.9
            let hairRect = CGRect(x: cx - headR * 0.95, y: headCY - headR, width: headR * 1.9, height: hairH)
            var hairPath = Path()
            hairPath.addRoundedRect(in: hairRect, cornerRadii: .init(
                topLeading:     headR * 0.85,
                bottomLeading:  headR * CGFloat(t.hairStyle == 0 ? 0.1 : (t.hairStyle == 1 ? 0.5 : 0.0)),
                bottomTrailing: headR * CGFloat(t.hairStyle == 0 ? 0.1 : (t.hairStyle == 1 ? 0.5 : 0.0)),
                topTrailing:    headR * 0.85
            ))
            ctx.fill(hairPath, with: .color(.white.opacity(0.55)))

            // ── Eyes ─────────────────────────────────────────────
            let eyeY  = headCY - headR * 0.08
            let eyeSpacing = headR * 0.44
            let eyeR: CGFloat = headR * (t.eyeSize == 0 ? 0.14 : (t.eyeSize == 1 ? 0.105 : 0.125))

            for xOff in [-eyeSpacing, eyeSpacing] {
                let er = CGRect(x: cx + xOff - eyeR, y: eyeY - eyeR, width: eyeR*2, height: eyeR*2)
                ctx.fill(Path(ellipseIn: er), with: .color(.black.opacity(0.75)))
                // Eye shine
                let shineR: CGFloat = eyeR * 0.38
                let shineRect = CGRect(x: cx + xOff - eyeR*0.25, y: eyeY - eyeR*0.55, width: shineR*2, height: shineR*2)
                ctx.fill(Path(ellipseIn: shineRect), with: .color(.white.opacity(0.85)))
            }

            // Eyebrows
            let browThick: CGFloat = headR * 0.07
            let browW = eyeR * (t.eyebrowStyle == 0 ? 2.2 : 1.6)
            let browY = eyeY - eyeR * 1.5
            for xOff in [-eyeSpacing, eyeSpacing] {
                var brow = Path()
                if t.eyebrowStyle == 2 {
                    // Arched
                    brow.move(to: CGPoint(x: cx + xOff - browW/2, y: browY + browThick))
                    brow.addQuadCurve(
                        to: CGPoint(x: cx + xOff + browW/2, y: browY + browThick),
                        control: CGPoint(x: cx + xOff, y: browY - browThick * 0.8)
                    )
                } else {
                    brow.move(to: CGPoint(x: cx + xOff - browW/2, y: browY + (xOff < 0 ? browThick*0.5 : 0)))
                    brow.addLine(to: CGPoint(x: cx + xOff + browW/2, y: browY + (xOff < 0 ? 0 : browThick*0.5)))
                }
                ctx.stroke(brow, with: .color(.black.opacity(0.60)), style: StrokeStyle(lineWidth: browThick, lineCap: .round))
            }

            // ── Nose ─────────────────────────────────────────────
            let noseY = headCY + headR * 0.18
            var nosePath = Path()
            if t.noseStyle == 0 {
                nosePath.move(to: CGPoint(x: cx, y: noseY - headR*0.09))
                nosePath.addCurve(
                    to: CGPoint(x: cx, y: noseY + headR*0.06),
                    control1: CGPoint(x: cx + headR*0.09, y: noseY - headR*0.01),
                    control2: CGPoint(x: cx + headR*0.07, y: noseY + headR*0.06)
                )
            } else {
                nosePath.move(to: CGPoint(x: cx - headR*0.05, y: noseY + headR*0.06))
                nosePath.addLine(to: CGPoint(x: cx, y: noseY - headR*0.08))
                nosePath.addLine(to: CGPoint(x: cx + headR*0.05, y: noseY + headR*0.06))
            }
            ctx.stroke(nosePath, with: .color(.black.opacity(0.28)), style: StrokeStyle(lineWidth: headR*0.06, lineCap: .round, lineJoin: .round))

            // ── Mouth ─────────────────────────────────────────────
            let mouthY = headCY + headR * 0.42
            let mouthW = headR * (t.mouthWidth == 0 ? 0.55 : (t.mouthWidth == 1 ? 0.40 : 0.65))
            var mouth = Path()
            switch t.mouthShape {
            case 0: // smile
                mouth.move(to: CGPoint(x: cx - mouthW/2, y: mouthY))
                mouth.addQuadCurve(
                    to: CGPoint(x: cx + mouthW/2, y: mouthY),
                    control: CGPoint(x: cx, y: mouthY + headR * 0.20)
                )
            case 1: // slight smile
                mouth.move(to: CGPoint(x: cx - mouthW/2, y: mouthY + headR*0.04))
                mouth.addQuadCurve(
                    to: CGPoint(x: cx + mouthW/2, y: mouthY + headR*0.04),
                    control: CGPoint(x: cx, y: mouthY + headR * 0.14)
                )
            default: // straight / serious
                mouth.move(to: CGPoint(x: cx - mouthW/2, y: mouthY + headR*0.05))
                mouth.addLine(to: CGPoint(x: cx + mouthW/2, y: mouthY + headR*0.05))
            }
            ctx.stroke(mouth, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: headR*0.085, lineCap: .round))

            // ── Ears ─────────────────────────────────────────────
            let earR = headR * 0.18
            let earY = headCY + headR * 0.08
            for xOff in [-(headR - earR * 0.4), headR - earR * 0.4] {
                let er = CGRect(x: cx + xOff - earR, y: earY - earR, width: earR*2, height: earR*2)
                ctx.fill(Path(ellipseIn: er), with: .color(.white.opacity(0.80)))
                ctx.stroke(Path(ellipseIn: er), with: .color(.white.opacity(0.4)), lineWidth: 0.7)
            }

            // ── Accessories (glasses / hat) ──────────────────────
            if t.hasGlasses {
                let glassR: CGFloat = eyeR * 1.45
                let glassColor = Color.black.opacity(0.45)
                for xOff in [-eyeSpacing, eyeSpacing] {
                    let gr = CGRect(x: cx + xOff - glassR, y: eyeY - glassR * 0.95, width: glassR*2, height: glassR*2)
                    ctx.stroke(Path(roundedRect: gr, cornerRadius: glassR * 0.3), with: .color(glassColor), lineWidth: headR * 0.07)
                }
                // bridge
                var bridge = Path()
                bridge.move(to: CGPoint(x: cx - eyeSpacing + glassR, y: eyeY - glassR*0.1))
                bridge.addLine(to: CGPoint(x: cx + eyeSpacing - glassR, y: eyeY - glassR*0.1))
                ctx.stroke(bridge, with: .color(glassColor), lineWidth: headR * 0.06)
            }

            if t.hasHat {
                let hatBrimW = headR * 2.1
                let hatBrimH = headR * 0.18
                let hatTopW  = headR * 1.4
                let hatTopH  = headR * t.hatHeight
                let hatBaseY = headCY - headR + hatBrimH * 0.3

                // brim
                let brimRect = CGRect(x: cx - hatBrimW/2, y: hatBaseY - hatBrimH, width: hatBrimW, height: hatBrimH)
                ctx.fill(Path(roundedRect: brimRect, cornerRadius: 2), with: .color(.white.opacity(0.70)))

                // crown
                let crownRect = CGRect(x: cx - hatTopW/2, y: hatBaseY - hatBrimH - hatTopH, width: hatTopW, height: hatTopH)
                ctx.fill(Path(roundedRect: crownRect, cornerRadius: headR * 0.12), with: .color(.white.opacity(0.80)))

                // hat band
                let bandH: CGFloat = hatTopH * 0.18
                let bandRect = CGRect(x: cx - hatTopW/2, y: hatBaseY - hatBrimH - bandH, width: hatTopW, height: bandH)
                ctx.fill(Path(bandRect), with: .color(.black.opacity(0.20)))
            }
        }
    }
}

// MARK: - Avatar personality traits (all derived from seed)

private struct AvatarTraits {
    // head
    let headRadius: CGFloat      // 0.22 – 0.27
    // hair
    let hairHeight: CGFloat      // 0.50 – 0.90
    let hairStyle: Int           // 0=straight-cut, 1=round, 2=spiky
    // eyes
    let eyeSize: Int             // 0=big, 1=small, 2=normal
    let eyebrowStyle: Int        // 0=flat, 1=tilted, 2=arched
    // nose
    let noseStyle: Int           // 0=curve, 1=angular
    // mouth
    let mouthShape: Int          // 0=big smile, 1=slight, 2=straight
    let mouthWidth: Int          // 0=medium, 1=small, 2=wide
    // accessories
    let hasGlasses: Bool
    let hasHat: Bool
    let hatHeight: CGFloat       // 0.40 – 0.65

    init(seed: Int) {
        var s = UInt64(bitPattern: Int64(truncatingIfNeeded: seed))
        func next() -> Int {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Int((s >> 33) & 0xFFFF)
        }
        func frac() -> CGFloat { CGFloat(next() & 0xFFF) / CGFloat(0xFFF) }

        headRadius    = 0.22 + frac() * 0.05
        hairHeight    = 0.50 + frac() * 0.40
        hairStyle     = next() % 3
        eyeSize       = next() % 3
        eyebrowStyle  = next() % 3
        noseStyle     = next() % 2
        mouthShape    = next() % 3
        mouthWidth    = next() % 3
        hasGlasses    = (next() % 4) == 0     // ~25 %
        hasHat        = (next() % 5) == 0     // ~20 %
        hatHeight     = 0.40 + frac() * 0.25
    }
}

// MARK: - Subtle noise background

private struct AvatarNoiseView: View {
    let seed: Int
    var body: some View {
        Canvas { ctx, sz in
            var s = UInt64(bitPattern: Int64(truncatingIfNeeded: seed &+ 99991))
            func rnd(_ max: CGFloat) -> CGFloat {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(s >> 33) / CGFloat(0x7FFFFFFF) * max
            }
            for _ in 0..<28 {
                let x = rnd(sz.width); let y = rnd(sz.height)
                let r: CGFloat = rnd(1.4) + 0.5
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r*2, height: r*2)), with: .color(.white))
            }
        }
    }
}

// MARK: - Baseball Card

private struct AgentBaseballCard: View {
    let agent: AgentDefinition
    let isSelected: Bool
    let theme: AppTheme
    let accentColor: Color
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    @State private var hovered = false

    private var headerGradient: LinearGradient {
        let c1: Color, c2: Color
        switch agent.color?.lowercased() ?? "" {
        case "purple": c1 = Color(red: 0.49, green: 0.23, blue: 0.93); c2 = Color(red: 0.86, green: 0.16, blue: 0.47)
        case "blue":   c1 = Color(red: 0.15, green: 0.39, blue: 0.92); c2 = Color(red: 0.02, green: 0.71, blue: 0.83)
        case "green":  c1 = Color(red: 0.02, green: 0.59, blue: 0.41); c2 = Color(red: 0.29, green: 0.86, blue: 0.56)
        case "orange": c1 = Color(red: 0.92, green: 0.35, blue: 0.05); c2 = Color(red: 0.98, green: 0.75, blue: 0.15)
        case "red":    c1 = Color(red: 0.86, green: 0.15, blue: 0.15); c2 = Color(red: 0.98, green: 0.45, blue: 0.09)
        case "cyan":   c1 = Color(red: 0.04, green: 0.57, blue: 0.70); c2 = Color(red: 0.39, green: 0.40, blue: 0.95)
        default:       c1 = agent.dotColor; c2 = agent.dotColor.opacity(0.45)
        }
        return LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private let φ: CGFloat = 1.618  // goldener Schnitt

    private var simulatedLatency: Int {
        20 + (abs(agent.id.hashValue) % 180)
    }

    var body: some View {
        Button(action: onSelect) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let headerH = h * 0.46
                let iconSize = min(w * 0.52, headerH * 0.72)

                VStack(spacing: 0) {
                    // Header: Gradient + Robot + role tag badge
                    ZStack(alignment: .top) {
                        headerGradient
                        AvatarNoiseView(seed: abs(agent.id.hashValue)).opacity(0.09)
                        RobotHeadIcon(size: iconSize)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Role tag badge top-center
                        Text(agent.id.uppercased())
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(agent.dotColor)
                            .kerning(0.4)
                            .lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(agent.dotColor.opacity(0.18), in: Capsule())
                            .overlay(Capsule().strokeBorder(agent.dotColor.opacity(0.45), lineWidth: 0.5))
                            .padding(.top, 7)
                    }
                    .frame(width: w, height: headerH)
                    .clipped()

                    // Accent divider
                    Rectangle()
                        .fill(agent.dotColor.opacity(0.38))
                        .frame(width: w, height: 1)

                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        Text(agent.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(agent.description.isEmpty ? "—" : agent.description)
                            .font(.system(size: 9))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)

                        // Footer: model + latency
                        HStack(spacing: 0) {
                            modelBadge(agent.model)
                            Spacer(minLength: 4)
                            Text("LATENCY: \(simulatedLatency)ms")
                                .font(.system(size: 7, weight: .medium))
                                .foregroundStyle(theme.tertiaryText)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 7)
                    .frame(width: w, height: h - headerH - 1, alignment: .topLeading)
                }
            }
        }
        .buttonStyle(.plain)
        .aspectRatio(1.0 / φ, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? theme.accent : theme.cardBg))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected ? agent.dotColor.opacity(0.5) : theme.cardBorder,
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .shadow(color: .black.opacity(hovered || isSelected ? 0.10 : 0.04), radius: hovered ? 8 : 3, x: 0, y: 2)
        .scaleEffect(hovered ? 1.01 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: hovered)
        .onHover { hovered = $0 }
    }

    private func modelBadge(_ model: String) -> some View {
        Text(model.lowercased())
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(accentColor.opacity(0.15), in: Capsule())
    }

    private func cardIconButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 20, height: 20)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main View

struct AgentsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @State private var selectedAgent: AgentDefinition?
    @State private var searchText = ""
    @State private var showEditor = false
    @State private var editorDraft = AgentDraft()
    @State private var editingAgentId: String?
    @State private var editorError: String?
    @State private var detailError: String?
    @State private var pendingDeleteAgent: AgentDefinition?

    private var accentColor: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    private var markdownContentType: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }

    var filteredAgents: [AgentDefinition] {
        guard !searchText.isEmpty else { return state.agentService.agents }
        return state.agentService.agents.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var activeAgents: [AgentDefinition]   { filteredAgents.filter { $0.isActive } }
    var inactiveAgents: [AgentDefinition] { filteredAgents.filter { !$0.isActive } }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            agentsHeader

            Divider().foregroundStyle(theme.cardBorder)

            // Content
            if filteredAgents.isEmpty {
                agentPlaceholder
            } else {
                HStack(spacing: 0) {
                    // Card grid
                    GeometryReader { gridProxy in
                        ScrollView {
                            let (cols, rowGap) = tableLayout(for: gridProxy.size.width)
                            VStack(alignment: .leading, spacing: 0) {
                                // Active agents section
                                if !activeAgents.isEmpty {
                                    agentSectionHeader(
                                        title: "Aktive Agents",
                                        count: activeAgents.count,
                                        color: .green
                                    )
                                    LazyVGrid(columns: cols, spacing: rowGap) {
                                        ForEach(activeAgents) { agent in
                                            agentCard(agent)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 18)
                                }

                                // Inactive agents section
                                if !inactiveAgents.isEmpty {
                                    agentSectionHeader(
                                        title: "Inaktive Agents",
                                        count: inactiveAgents.count,
                                        color: theme.tertiaryText
                                    )
                                    LazyVGrid(columns: cols, spacing: rowGap) {
                                        ForEach(inactiveAgents) { agent in
                                            agentCard(agent)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 14)
                                }
                            }
                            .padding(.top, 14)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Detail panel (slides in when agent selected)
                    if let agent = selectedAgent {
                        Divider().foregroundStyle(theme.cardBorder)
                        agentDetail(agent)
                            .frame(minWidth: 380, idealWidth: 460, maxWidth: 560)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selectedAgent?.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if state.agentService.agents.isEmpty {
                await state.agentService.loadAgents()
            }
        }
        .onChange(of: state.agentService.agents) { _, agents in
            syncSelectedAgent(with: agents)
        }
        .sheet(isPresented: $showEditor) {
            AgentEditorSheet(
                draft: $editorDraft,
                title: editingAgentId == nil ? "Neuen Agent anlegen" : "Agent bearbeiten",
                theme: theme,
                errorMessage: editorError,
                previewContent: state.agentService.previewAgentFile(editorDraft),
                onCancel: {
                    editorError = nil
                    showEditor = false
                },
                onCopyPreview: copyEditorPreview,
                onSave: saveAgentDraft
            )
            .frame(minWidth: 680, minHeight: 760)
        }
        .confirmationDialog(
            "Agent loeschen?",
            isPresented: Binding(
                get: { pendingDeleteAgent != nil },
                set: { if !$0 { pendingDeleteAgent = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeleteAgent
        ) { agent in
            Button("Loeschen", role: .destructive) { deleteAgent(agent) }
            Button("Abbrechen", role: .cancel) { pendingDeleteAgent = nil }
        } message: { agent in
            Text("\"\(agent.name)\" wird aus ~/.claude/agents entfernt.")
        }
    }

    // MARK: - Grid helpers

    /// Berechnet Spalten + Abstände so dass Karten (feste Breite) sich wie auf einem Tisch verteilen.
    private func tableLayout(for availableWidth: CGFloat) -> (columns: [GridItem], rowGap: CGFloat) {
        let cardW: CGFloat = 148
        let edgePad: CGFloat = 28          // 14 × 2
        let usable = availableWidth - edgePad
        let minGap: CGFloat = 24
        let count = max(1, Int((usable + minGap) / (cardW + minGap)))
        let gap = count > 1
            ? (usable - CGFloat(count) * cardW) / CGFloat(count - 1)
            : 0
        let colGap = max(minGap, gap)
        return (Array(repeating: GridItem(.fixed(cardW), spacing: colGap), count: count), colGap)
    }

    private func agentCard(_ agent: AgentDefinition) -> some View {
        AgentBaseballCard(
            agent: agent,
            isSelected: selectedAgent?.id == agent.id,
            theme: theme,
            accentColor: accentColor,
            onEdit: { startEditingAgent(agent) },
            onDelete: { detailError = nil; pendingDeleteAgent = agent },
            onSelect: {
                withAnimation(.spring(response: 0.3)) {
                    selectedAgent = selectedAgent?.id == agent.id ? nil : agent
                }
            }
        )
    }

    private func agentSectionHeader(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .kerning(0.3)
            Text("\(count)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(theme.tertiaryText)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(theme.cardBg, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.cardBorder, lineWidth: 0.5))
            Rectangle()
                .fill(theme.cardBorder)
                .frame(height: 0.5)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Header

    private var agentsHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // Hero title + subtitle
                VStack(alignment: .leading, spacing: 3) {
                    Text("Agent Fleet")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                    Text("Manage and orchestrate your deployed autonomous agents.")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(2)
                }

                Spacer()

                // Online badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                        .shadow(color: .green.opacity(0.6), radius: 4)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(activeAgents.count)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                        Text("ONLINE")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(Color.green)
                            .kerning(0.5)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.green.opacity(0.35), lineWidth: 0.5))
            }

            // Search + actions row
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                    TextField("Agent suchen…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder, lineWidth: 0.5))
                .frame(maxWidth: 200)

                Spacer()

                headerButton(icon: "square.and.arrow.down", tooltip: "Importieren") { importAgents() }
                headerButton(icon: "arrow.clockwise", tooltip: "Neu laden") {
                    Task { await state.agentService.loadAgents() }
                }
                Button {
                    startCreatingAgent()
                } label: {
                    Label("Neuer Agent", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .controlSize(.small)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func headerButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Detail Panel

    private func colorDisplayName(_ color: String?) -> String {
        switch color?.lowercased() {
        case "purple": return "Spectral Purple"
        case "blue":   return "Neural Blue"
        case "green":  return "Spectral Green"
        case "orange": return "Amber Core"
        case "red":    return "Alert Red"
        case "cyan":   return "Cyan Stream"
        default:       return "Neutral Gray"
        }
    }

    private func modelDisplayName(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("opus")   { return "Claude Opus" }
        if m.contains("sonnet") { return "Claude Sonnet" }
        if m.contains("haiku")  { return "Claude Haiku" }
        return model.isEmpty ? "Claude Sonnet" : model.capitalized
    }

    private func memoryDisplayName(_ memory: String?) -> String {
        switch memory?.lowercased() {
        case "user":    return "User Session"
        case "project": return "Project Memory"
        case "none", nil: return "None"
        default:        return memory?.capitalized ?? "None"
        }
    }

    private func promptWordCount(_ body: String) -> String {
        let words = body.split(whereSeparator: { $0.isWhitespace }).count
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return (formatter.string(from: NSNumber(value: words)) ?? "\(words)") + " words"
    }

    private func agentDetail(_ agent: AgentDefinition) -> some View {
        VStack(spacing: 0) {
            // Panel header: "Agent Settings"
            HStack(spacing: 6) {
                Text("Agent Settings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.primaryText)

                Spacer()

                Button { startEditingAgent(agent) } label: {
                    Image(systemName: "pencil").font(.system(size: 11))
                        .frame(width: 26, height: 26)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .foregroundStyle(accentColor)
                .help("Bearbeiten")

                Button { duplicateAgent(agent) } label: {
                    Image(systemName: "plus.square.on.square").font(.system(size: 11))
                        .frame(width: 26, height: 26)
                        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText)
                .help("Duplizieren")

                Button {
                    detailError = nil
                    pendingDeleteAgent = agent
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                        .frame(width: 26, height: 26)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Loeschen")

                Button {
                    withAnimation(.spring(response: 0.3)) { selectedAgent = nil }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.tertiaryText)
                .help("Schliessen")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider().foregroundStyle(theme.cardBorder)

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Error banner
                    if let detailError, !detailError.isEmpty {
                        Text(detailError)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5))
                    }

                    // Avatar + name + ID
                    HStack(spacing: 12) {
                        ZStack {
                            LinearGradient(
                                colors: [agent.dotColor, agent.dotColor.opacity(0.45)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                            AvatarNoiseView(seed: abs(agent.id.hashValue)).opacity(0.09)
                            RobotHeadIcon(size: 32)
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(agent.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(theme.primaryText)
                                .lineLimit(2)
                            Text("ID: \(agent.id.uppercased())")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(theme.tertiaryText)
                        }
                    }

                    // 2×2 info tile grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        infoTile(label: "NEURAL MODEL",
                                 value: modelDisplayName(agent.model),
                                 valueColor: accentColor)
                        infoTile(label: "MEMORY POOL",
                                 value: memoryDisplayName(agent.memory),
                                 valueColor: accentColor)
                        infoTile(label: "STATUS COLOR",
                                 value: colorDisplayName(agent.color),
                                 valueIcon: agent.dotColor)
                        infoTile(label: "PROMPT SIZE",
                                 value: promptWordCount(agent.promptBody),
                                 valueColor: theme.primaryText)
                    }

                    // Schedule panel
                    if let sched = agent.schedule, !sched.isEmpty {
                        Divider().foregroundStyle(theme.cardBorder)
                        schedulingInfoPanel(agent: agent, schedule: sched)
                    }

                    Divider().foregroundStyle(theme.cardBorder)

                    // System prompt
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("SYSTEM PROMPT")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.tertiaryText)
                                .kerning(0.6)
                            Spacer()
                            Text("Markdown Enabled")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(accentColor.opacity(0.12), in: Capsule())
                        }

                        Text(agent.promptBody.isEmpty ? "(Kein Prompt)" : agent.promptBody)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.primaryText.opacity(0.85))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Agent memory
                    if let memory = state.agentService.loadAgentMemory(agentId: agent.id) {
                        Divider().foregroundStyle(theme.cardBorder)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AGENT MEMORY")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.tertiaryText)
                                .kerning(0.6)
                            Text(memory)
                                .font(.system(size: 10))
                                .foregroundStyle(theme.secondaryText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Logbook
                    Divider().foregroundStyle(theme.cardBorder)
                    logbookPanel(agent: agent)

                    // Regenerate Credentials button
                    Button {
                        exportAgent(agent)
                    } label: {
                        Text("Regenerate Credentials")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.cardBorder, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Als Markdown exportieren")
                }
                .padding(12)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func infoTile(label: String, value: String, valueColor: Color = .primary, valueIcon: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .kerning(0.5)
            if let dot = valueIcon {
                HStack(spacing: 5) {
                    Circle().fill(dot).frame(width: 7, height: 7)
                    Text(value)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                }
            } else {
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.cardBorder, lineWidth: 0.5))
    }

    // MARK: - Scheduling info panel

    private func schedulingInfoPanel(agent: AgentDefinition, schedule: String) -> some View {
        let isRunning = state.agentService.runningAgents.contains(agent.id)
        let lastEntry = state.agentService.logs[agent.id]?.last

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("SCHEDULE")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
                    .kerning(0.6)
                Spacer()
                if isRunning {
                    Label("Läuft…", systemImage: "clock.badge.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.orange)
                } else {
                    Button {
                        Task { await state.agentService.executeScheduledAgent(agent) }
                    } label: {
                        Label("Jetzt ausführen", systemImage: "play.fill")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(accentColor)
                }
            }

            HStack(spacing: 10) {
                scheduleChip(
                    icon: agent.isActive ? "checkmark.circle.fill" : "pause.circle.fill",
                    label: agent.isActive ? "Aktiv" : "Inaktiv",
                    color: agent.isActive ? .green : theme.tertiaryText
                )
                scheduleChip(icon: "timer", label: schedule, color: accentColor)
                if let last = lastEntry {
                    scheduleChip(
                        icon: last.status.icon,
                        label: relativeTime(last.startedAt),
                        color: last.status.color
                    )
                }
            }
        }
    }

    private func scheduleChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - Logbook panel

    private func logbookPanel(agent: AgentDefinition) -> some View {
        let entries = (state.agentService.logs[agent.id] ?? []).reversed() as [ScheduledTaskLogEntry]

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LOGBUCH")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.tertiaryText)
                    .kerning(0.6)
                Text("\(entries.count)")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.tertiaryText)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(theme.cardBg, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.cardBorder, lineWidth: 0.5))
                Spacer()
                if !entries.isEmpty {
                    Button {
                        state.agentService.clearLog(agentId: agent.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                    }
                    .buttonStyle(.plain)
                    .help("Logbuch leeren")
                }
            }

            if entries.isEmpty {
                Text("Noch keine Ausführungen aufgezeichnet.")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 4) {
                    ForEach(entries.prefix(20)) { entry in
                        logbookRow(entry)
                    }
                }
            }
        }
    }

    private func logbookRow(_ entry: ScheduledTaskLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: entry.status.icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(entry.status.color)
                Text(entry.status.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(entry.status.color)
                Spacer()
                Text(shortDateTime(entry.startedAt))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.tertiaryText)
                if let fin = entry.finishedAt {
                    Text("(\(durationString(from: entry.startedAt, to: fin)))")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            if !entry.output.isEmpty {
                Text(entry.output.prefix(200) + (entry.output.count > 200 ? "…" : ""))
                    .font(.system(size: 9))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            if !entry.error.isEmpty {
                Text(entry.error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(theme.windowBg.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardBorder.opacity(0.6), lineWidth: 0.4))
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60      { return "Gerade eben" }
        if diff < 3600    { return "vor \(Int(diff/60)) Min." }
        if diff < 86400   { return "vor \(Int(diff/3600)) Std." }
        return "vor \(Int(diff/86400)) T."
    }

    private func shortDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM HH:mm"
        return f.string(from: date)
    }

    private func durationString(from start: Date, to end: Date) -> String {
        let sec = Int(end.timeIntervalSince(start))
        if sec < 60 { return "\(sec)s" }
        return "\(sec/60)m \(sec%60)s"
    }

    private func metaTag(_ key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key.uppercased())
                .font(.system(size: 7, weight: .semibold)).foregroundStyle(theme.tertiaryText).kerning(0.4)
            Text(value)
                .font(.system(size: 10)).foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardBorder, lineWidth: 0.5))
    }

    // MARK: - Placeholder

    private var agentPlaceholder: some View {
        VStack(spacing: 14) {
            // Decorative avatar cluster
            HStack(spacing: -16) {
                ForEach(["C", "A", "B"], id: \.self) { letter in
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [theme.tertiaryText.opacity(0.2), theme.tertiaryText.opacity(0.1)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                        Text(letter)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.tertiaryText.opacity(0.5))
                    }
                    .frame(width: 52, height: 52)
                }
            }

            Text("Keine Agents")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.secondaryText)
            Text("Agents werden in\n~/.claude/agents/ gespeichert")
                .font(.system(size: 11)).foregroundStyle(theme.tertiaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button("Importieren") { importAgents() }
                    .buttonStyle(.bordered)
                Button("Neuen Agent anlegen") { startCreatingAgent() }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func startCreatingAgent() {
        editingAgentId = nil
        editorDraft = AgentDraft()
        editorError = nil
        detailError = nil
        showEditor = true
    }

    private func startEditingAgent(_ agent: AgentDefinition) {
        editingAgentId = agent.id
        editorDraft = AgentDraft(agent: agent)
        editorError = nil
        detailError = nil
        showEditor = true
    }

    private func saveAgentDraft() {
        let draft = editorDraft
        let previousId = editingAgentId

        Task { @MainActor in
            do {
                let saved = try await state.agentService.saveAgent(draft, previousId: previousId)
                selectedAgent = saved
                editingAgentId = saved.id
                editorError = nil
                detailError = nil
                showEditor = false
            } catch {
                editorError = error.localizedDescription
            }
        }
    }

    private func copyEditorPreview() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(state.agentService.previewAgentFile(editorDraft), forType: .string)
    }

    private func duplicateAgent(_ agent: AgentDefinition) {
        Task { @MainActor in
            do {
                let duplicated = try await state.agentService.duplicateAgent(agent)
                selectedAgent = duplicated
                detailError = nil
            } catch {
                detailError = error.localizedDescription
            }
        }
    }

    private func importAgents() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [markdownContentType, .plainText]
        panel.prompt = "Importieren"

        guard panel.runModal() == .OK else { return }

        Task { @MainActor in
            do {
                var lastImported: AgentDefinition?
                for url in panel.urls {
                    lastImported = try await state.agentService.importAgent(from: url)
                }
                if let lastImported {
                    selectedAgent = lastImported
                }
                detailError = nil
            } catch {
                detailError = error.localizedDescription
            }
        }
    }

    private func exportAgent(_ agent: AgentDefinition) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(agent.id).md"
        panel.allowedContentTypes = [markdownContentType]
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try state.agentService.exportAgent(agent, to: url)
            detailError = nil
        } catch {
            detailError = error.localizedDescription
        }
    }

    private func deleteAgent(_ agent: AgentDefinition) {
        Task { @MainActor in
            do {
                try await state.agentService.deleteAgent(agentId: agent.id)
                if selectedAgent?.id == agent.id {
                    selectedAgent = state.agentService.agents.first
                }
                detailError = nil
                pendingDeleteAgent = nil
            } catch {
                detailError = error.localizedDescription
                pendingDeleteAgent = nil
            }
        }
    }

    private func syncSelectedAgent(with agents: [AgentDefinition]) {
        guard let selectedId = selectedAgent?.id else { return }
        selectedAgent = agents.first(where: { $0.id == selectedId })
    }
}

// MARK: - Editor Sheet (unchanged)

private struct AgentEditorSheet: View {
    @Binding var draft: AgentDraft
    let title: String
    let theme: AppTheme
    let errorMessage: String?
    let previewContent: String
    let onCancel: () -> Void
    let onCopyPreview: () -> Void
    let onSave: () -> Void

    @State private var showAiPanel = false
    @State private var aiDescription = ""
    @State private var isGenerating = false
    @State private var aiError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                    Text("Bearbeite Frontmatter und System Prompt direkt aus der App.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                Button("Abbrechen", action: onCancel)
                    .buttonStyle(.bordered)

                Button("Speichern", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255))
            }
            .padding(20)

            Divider().foregroundStyle(theme.cardBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5)
                            )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        editorField("Kennung", hint: "Dateiname ohne .md, z. B. code-reviewer") {
                            TextField("code-reviewer", text: $draft.id)
                                .textFieldStyle(.roundedBorder)
                        }

                        editorField("Name", hint: "Anzeigename des Agents") {
                            TextField("Code Reviewer", text: $draft.name)
                                .textFieldStyle(.roundedBorder)
                        }

                        editorField("Beschreibung", hint: "Kurzbeschreibung fuer die Auswahlansicht") {
                            TextField("Wofuer der Agent gedacht ist", text: $draft.description, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...5)
                        }
                    }
                    .padding(16)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                    )

                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            editorField("Model", hint: "z. B. sonnet, opus oder haiku") {
                                TextField("sonnet", text: $draft.model)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            editorField("Color", hint: "Optional, z. B. blue oder orange") {
                                TextField("blue", text: $draft.color)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            editorField("Memory", hint: "Optional, z. B. user") {
                                TextField("user", text: $draft.memory)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding(16)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                    )

                    // Scheduling section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255))
                            Text("Scheduled Task")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                        }

                        HStack(alignment: .top, spacing: 16) {
                            editorField("Schedule", hint: "hourly · daily · weekly · every:N (Minuten)") {
                                TextField("daily", text: $draft.schedule)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("AKTIV".uppercased())
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(theme.tertiaryText)
                                    .kerning(0.5)
                                Toggle("Scheduling aktiv", isOn: $draft.isActive)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                Text("Wenn aktiv, wird der Agent automatisch\ngemäß seinem Schedule ausgeführt.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(theme.tertiaryText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("System Prompt")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)
                                Text("Der Inhalt unterhalb des Frontmatters wird direkt in die Agent-Datei geschrieben.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.secondaryText)
                            }
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.3)) { showAiPanel.toggle() }
                            } label: {
                                Label(showAiPanel ? "Schliessen" : "Mit AI generieren",
                                      systemImage: showAiPanel ? "xmark" : "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255))
                            .controlSize(.small)
                        }

                        if showAiPanel {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AGENT BESCHREIBEN")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(theme.tertiaryText)
                                    .kerning(0.5)

                                TextField(
                                    "z. B. Ein Senior VBA-Entwickler der Excel-Makros schreibt und auf Fehlerbehandlung achtet…",
                                    text: $aiDescription,
                                    axis: .vertical
                                )
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3...5)

                                if let aiError {
                                    Text(aiError)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.red)
                                }

                                HStack {
                                    Spacer()
                                    Button {
                                        generatePromptWithAI()
                                    } label: {
                                        if isGenerating {
                                            ProgressView().controlSize(.small)
                                            Text("Generiere…").font(.system(size: 11))
                                        } else {
                                            Label("Prompt generieren", systemImage: "sparkles")
                                                .font(.system(size: 11, weight: .semibold))
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255))
                                    .controlSize(.small)
                                    .disabled(aiDescription.trimmingCharacters(in: .whitespaces).isEmpty || isGenerating)
                                }
                            }
                            .padding(12)
                            .background(
                                Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255).opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255).opacity(0.25),
                                        lineWidth: 0.5
                                    )
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        TextEditor(text: $draft.promptBody)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(theme.primaryText)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 320, alignment: .topLeading)
                            .background(theme.windowBg.opacity(theme.isLight ? 0.35 : 0.18), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                            )
                    }
                    .padding(16)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rohdatei-Vorschau")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.primaryText)
                                Text("So wird die Agent-Datei inklusive Frontmatter gespeichert.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.secondaryText)
                            }

                            Spacer()

                            Button("Kopieren", action: onCopyPreview)
                                .buttonStyle(.bordered)
                        }

                        ScrollView {
                            Text(previewContent)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(theme.primaryText.opacity(0.9))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(minHeight: 220)
                        .background(theme.windowBg.opacity(theme.isLight ? 0.35 : 0.18), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                        )
                    }
                    .padding(16)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                    )
                }
                .padding(20)
            }
        }
        .background(theme.windowBg)
    }

    private func editorField<Content: View>(_ title: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .kerning(0.5)
            content()
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func generatePromptWithAI() {
        let desc = aiDescription.trimmingCharacters(in: .whitespaces)
        guard !desc.isEmpty else { return }
        isGenerating = true
        aiError = nil

        Task {
            let metaHint: String
            if !draft.name.isEmpty || !draft.description.isEmpty {
                metaHint = " The agent is named \"\(draft.name)\" and is described as: \(draft.description)."
            } else {
                metaHint = ""
            }

            let userPrompt = """
            Write a professional system prompt for an AI agent with the following role:\(metaHint)

            Role description: \(desc)

            Requirements:
            - Start directly with the agent's role and responsibilities
            - Include 4-6 concrete behavioral principles
            - Be specific and actionable, not generic
            - Use markdown headers (###) for sections if helpful
            - Do NOT include any preamble, explanation, or meta-commentary — output only the system prompt text itself
            """

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", "claude -p \(userPrompt.shellQuoted)"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                await MainActor.run {
                    isGenerating = false
                    if process.terminationStatus == 0, let output = String(data: data, encoding: .utf8) {
                        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            draft.promptBody = trimmed
                            withAnimation { showAiPanel = false }
                        } else {
                            aiError = "Keine Antwort von Claude erhalten."
                        }
                    } else {
                        aiError = "Claude CLI Fehler (Exit \(process.terminationStatus))."
                    }
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    aiError = "Fehler: \(error.localizedDescription)"
                }
            }
        }
    }
}

private extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
