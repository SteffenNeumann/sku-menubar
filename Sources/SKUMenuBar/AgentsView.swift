import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Flow Layout (wrapping chip row)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            rowH = max(rowH, s.height); x += s.width + spacing
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            rowH = max(rowH, s.height); x += s.width + spacing
        }
    }
}

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
    let theme: AppTheme
    let accentColor: Color
    let lastRun: Date?
    let lastOutput: String?
    let lastStatus: ScheduledTaskStatus?
    let lastError: String?
    let isRunning: Bool
    let liveText: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onLogbook: () -> Void
    let onMemory: () -> Void
    let onRerun: () -> Void

    @State private var hovered = false
    @State private var hoveredAction: String? = nil

    private var headerGradient: LinearGradient {
        let c1: Color, c2: Color
        switch agent.color?.lowercased() ?? "" {
        case "purple": c1 = Color(red: 0.49, green: 0.23, blue: 0.93); c2 = Color(red: 0.86, green: 0.16, blue: 0.47)
        case "blue":   c1 = Color(red: 0.15, green: 0.39, blue: 0.92); c2 = Color(red: 0.02, green: 0.71, blue: 0.83)
        case "green":  c1 = Color(red: 0.02, green: 0.59, blue: 0.41); c2 = Color(red: 0.29, green: 0.86, blue: 0.56)
        case "orange": c1 = Color(red: 0.92, green: 0.35, blue: 0.05); c2 = Color(red: 0.98, green: 0.75, blue: 0.15)
        case "red":    c1 = Color(red: 0.86, green: 0.15, blue: 0.15); c2 = Color(red: 0.98, green: 0.45, blue: 0.09)
        case "cyan":   c1 = Color(red: 0.04, green: 0.57, blue: 0.70); c2 = Color(red: 0.39, green: 0.40, blue: 0.95)
        case "yellow": c1 = Color(red: 0.95, green: 0.75, blue: 0.00); c2 = Color(red: 0.98, green: 0.50, blue: 0.05)
        case "pink":   c1 = Color(red: 0.95, green: 0.20, blue: 0.55); c2 = Color(red: 0.75, green: 0.10, blue: 0.80)
        case "indigo": c1 = Color(red: 0.29, green: 0.14, blue: 0.80); c2 = Color(red: 0.49, green: 0.23, blue: 0.93)
        case "teal":   c1 = Color(red: 0.00, green: 0.60, blue: 0.60); c2 = Color(red: 0.02, green: 0.71, blue: 0.83)
        default:       c1 = agent.dotColor; c2 = agent.dotColor.opacity(0.45)
        }
        return LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private let φ: CGFloat = 1.618  // goldener Schnitt

    private var lastRunLabel: String {
        guard let date = lastRun else { return "Never run" }
        let diff = Date().timeIntervalSince(date)
        switch diff {
        case ..<60:        return "Just now"
        case ..<3600:      return "\(Int(diff / 60))m ago"
        case ..<86400:     return "\(Int(diff / 3600))h ago"
        default:           return "\(Int(diff / 86400))d ago"
        }
    }

    private let actionBarH: CGFloat = 36

    private let headerH: CGFloat = 170

    var body: some View {
        VStack(spacing: 0) {

            // ── Header: gradient + avatar + ID badge ─────────
            ZStack(alignment: .top) {
                headerGradient
                AvatarNoiseView(seed: abs(agent.id.hashValue)).opacity(0.09)
                if let portrait = agent.portrait,
                   let img = Self.loadBundlePortrait(portrait) {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: headerH)
                        .clipped()
                } else {
                    RobotHeadIcon(size: min(headerH * 0.75, 120))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // ID badge – top left
                Text(agent.id.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .kerning(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.black.opacity(0.28), in: Capsule())
                    .padding(.top, 9).padding(.leading, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Status dot – top right
                Circle()
                    .fill(agent.isActive ? Color.green : Color.gray.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .shadow(color: agent.isActive ? .green.opacity(0.7) : .clear, radius: 4)
                    .padding(.top, 11).padding(.trailing, 11)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: headerH)
            .clipped()

            // Accent divider
            Rectangle()
                .fill(agent.dotColor.opacity(0.50))
                .frame(height: 1)

            // ── Body: name + description + content ───────────
            VStack(alignment: .leading, spacing: 7) {
                Text(agent.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(2)

                Text(agent.description.isEmpty ? "No description." : agent.description)
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // ── Trigger words section ─────────────────────
                VStack(alignment: .leading, spacing: 5) {
                    sectionLabel(icon: "bolt.fill", title: "TRIGGERS")
                    if agent.effectiveTriggers.isEmpty {
                        Text("—")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.secondaryText.opacity(0.4))
                    } else {
                        FlowLayout(spacing: 4) {
                            ForEach(agent.effectiveTriggers.prefix(6), id: \.self) { word in
                                Text(word)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(agent.dotColor)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(agent.dotColor.opacity(0.14), in: Capsule())
                                    .overlay(Capsule().strokeBorder(agent.dotColor.opacity(0.35), lineWidth: 0.5))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(.top, 5)

                // ── Research badge (non-researcher agents) ────
                if agent.id != "researcher forweb and ui  design trends",
                   let resDate = agent.researchUpdatedAt {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.filled.head.profile")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.purple.opacity(0.85))
                        Text("Wissen: \(resDate)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.purple.opacity(0.85))
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.purple.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.purple.opacity(0.30), lineWidth: 0.5))
                    .padding(.top, 2)
                }

                // ── Scheduled-only: output, status, last run ──
                if !(agent.schedule ?? "").isEmpty {
                    if let output = lastOutput, !output.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            sectionLabel(icon: "text.bubble", title: "LAST OUTPUT")
                            Text(output)
                                .font(.system(size: 10.5))
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(5)
                                .truncationMode(.tail)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(agent.dotColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(agent.dotColor.opacity(0.22), lineWidth: 0.5))
                        }
                        .padding(.top, 5)
                    }

                    statusSection

                    HStack(spacing: 6) {
                        modelBadge(agent.model)
                        Spacer(minLength: 0)
                        HStack(spacing: 3) {
                            Image(systemName: lastRun == nil ? "clock.badge.xmark" : "clock.badge.checkmark")
                                .font(.system(size: 9))
                                .foregroundStyle(lastRun == nil ? theme.secondaryText.opacity(0.4) : agent.dotColor.opacity(0.9))
                            Text(lastRunLabel)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(lastRun == nil ? theme.secondaryText.opacity(0.4) : theme.secondaryText)
                        }
                    }
                } else {
                    modelBadge(agent.model)
                }
            }
            .padding(.horizontal, 13)
            .padding(.top, 11)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // ── Action bar ────────────────────────────────────
            Rectangle()
                .fill(theme.cardBorder.opacity(0.5))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                let isScheduled = !(agent.schedule ?? "").isEmpty
                actionBarButton(id: "edit",    icon: "wand.and.stars",      action: onEdit)
                if isScheduled {
                    Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(width: 0.5, height: 16)
                    rerunButton
                    Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(width: 0.5, height: 16)
                    actionBarButton(id: "logbook", icon: "book.pages",       action: onLogbook)
                }
                Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(width: 0.5, height: 16)
                actionBarButton(id: "memory",  icon: "memorychip",           action: onMemory)
                Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(width: 0.5, height: 16)
                actionBarButton(id: "copy",    icon: "doc.on.clipboard",     action: onDuplicate)
                Rectangle().fill(theme.cardBorder.opacity(0.5)).frame(width: 0.5, height: 16)
                actionBarButton(id: "delete",  icon: "flame",                action: onDelete)
            }
            .frame(height: actionBarH)
            .background(theme.cardBg.opacity(0.7))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background(RoundedRectangle(cornerRadius: 12).fill(theme.cardBg))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(hovered ? agent.dotColor.opacity(0.55) : theme.cardBorder,
                              lineWidth: hovered ? 1.5 : 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(hovered ? 0.15 : 0.05), radius: hovered ? 14 : 4, x: 0, y: hovered ? 5 : 3)
        .zIndex(hovered ? 1 : 0)
        .animation(.easeInOut(duration: 0.18), value: hovered)
        .onHover { hovered = $0 }
    }

    private static func loadBundlePortrait(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    @ViewBuilder
    private var statusSection: some View {
        let (dot, label, color): (String, String, Color) = {
            if isRunning {
                let preview = liveText.trimmingCharacters(in: .whitespacesAndNewlines)
                let snippet = preview.isEmpty ? "Arbeitet…" : String(preview.prefix(120))
                return ("circle.fill", snippet, .green)
            }
            switch lastStatus {
            case .success:
                return ("checkmark.circle.fill", "Erfolgreich abgeschlossen", agent.dotColor)
            case .failed:
                let errMsg = lastError.flatMap { $0.isEmpty ? nil : String($0.prefix(140)) }
                    ?? "Fehler beim letzten Lauf"
                return ("xmark.circle.fill", errMsg, .red)
            case .running:
                return ("circle.fill", "Läuft…", .green)
            case nil:
                return ("minus.circle", "Noch nie ausgeführt", theme.secondaryText.opacity(0.35))
            }
        }()

        HStack(spacing: 5) {
            Image(systemName: dot)
                .font(.system(size: 8))
                .foregroundStyle(color)
                .opacity(isRunning ? 1 : 0.85)
                .scaleEffect(isRunning ? 1.15 : 1.0)
                .animation(isRunning
                    ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                    : .default, value: isRunning)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(color.opacity(isRunning ? 0.4 : 0.18), lineWidth: 0.5))
        .padding(.bottom, 6)
        .animation(.easeInOut(duration: 0.3), value: isRunning)
        .animation(.easeInOut(duration: 0.2), value: lastStatus)
    }

    @ViewBuilder
    private var rerunButton: some View {
        let isHovered = hoveredAction == "rerun"
        Button(action: onRerun) {
            ZStack {
                if isRunning {
                    // Pulsing green ring
                    Circle()
                        .stroke(Color.green.opacity(0.35), lineWidth: 6)
                        .frame(width: 22, height: 22)
                        .scaleEffect(isRunning ? 1.3 : 1.0)
                        .opacity(isRunning ? 0 : 1)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: isRunning)
                }
                Image(systemName: isRunning ? "stop.circle.fill" : "play.circle")
                    .font(.system(size: 13, weight: isHovered || isRunning ? .semibold : .regular))
                    .foregroundStyle(isRunning ? Color.green : (isHovered ? accentColor : theme.secondaryText.opacity(0.55)))
                    .shadow(color: isRunning ? Color.green.opacity(0.9) : (isHovered ? accentColor.opacity(0.85) : .clear), radius: 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .help(isRunning ? "Agent läuft…" : "Agent jetzt ausführen")
        .onHover { hoveredAction = $0 ? "rerun" : nil }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.3), value: isRunning)
    }

    private func sectionLabel(icon: String, title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(theme.secondaryText.opacity(0.6))
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.secondaryText.opacity(0.6))
                .kerning(0.5)
        }
    }

    private func modelBadge(_ model: String) -> some View {
        let label: String = {
            let m = model.lowercased()
            if m.contains("opus")   { return "Opus" }
            if m.contains("sonnet") { return "Sonnet" }
            if m.contains("haiku")  { return "Haiku" }
            return model.isEmpty ? "Sonnet" : model.capitalized
        }()
        return Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(accentColor)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(accentColor.opacity(0.13), in: Capsule())
            .overlay(Capsule().strokeBorder(accentColor.opacity(0.3), lineWidth: 0.5))
    }

    private static let tooltips: [String: String] = [
        "edit":    "Agent bearbeiten",
        "rerun":   "Agent jetzt ausführen",
        "logbook": "Logbook in Sublime Text öffnen",
        "memory":  "Agent Memory anzeigen",
        "copy":    "Agent duplizieren",
        "delete":  "Agent löschen",
    ]

    private func actionBarButton(id: String, icon: String, action: @escaping () -> Void) -> some View {
        let isHovered = hoveredAction == id
        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: isHovered ? .semibold : .regular))
                .foregroundStyle(isHovered ? accentColor : theme.secondaryText.opacity(0.55))
                .shadow(color: isHovered ? accentColor.opacity(0.85) : .clear, radius: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(Self.tooltips[id] ?? "")
        .onHover { hoveredAction = $0 ? id : nil }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Main View

struct AgentsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.appTheme) var theme
    @State private var searchText = ""
    @State private var showEditor = false
    @State private var editorDraft = AgentDraft()
    @State private var editingAgentId: String?
    @State private var editorError: String?
    @State private var pendingDeleteAgent: AgentDefinition?
    @State private var memoryAgent: AgentDefinition?

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
                GeometryReader { gridProxy in
                    ScrollView {
                        let (cols, rowGap, gridWidth) = tableLayout(for: gridProxy.size.width - 128)
                        VStack(spacing: 0) {
                            // Active agents section
                            if !activeAgents.isEmpty {
                                agentSectionHeader(
                                    title: "Aktive Agents",
                                    count: activeAgents.count,
                                    color: .green,
                                    gridWidth: gridWidth
                                )
                                LazyVGrid(columns: cols, spacing: rowGap) {
                                    ForEach(activeAgents) { agent in
                                        agentCard(agent)
                                    }
                                }
                                .frame(width: gridWidth)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 22)
                            }

                            // Inactive agents section
                            if !inactiveAgents.isEmpty {
                                agentSectionHeader(
                                    title: "Inaktive Agents",
                                    count: inactiveAgents.count,
                                    color: theme.tertiaryText,
                                    gridWidth: gridWidth
                                )
                                LazyVGrid(columns: cols, spacing: rowGap) {
                                    ForEach(inactiveAgents) { agent in
                                        agentCard(agent)
                                    }
                                }
                                .frame(width: gridWidth)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 18)
                            }
                        }
                        .padding(.top, 18)
                        .padding(.horizontal, 64)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if state.agentService.agents.isEmpty {
                await state.agentService.loadAgents()
            }
        }
        .onChange(of: state.agentService.agents) { _, _ in }
        .onReceive(state.agentService.objectWillChange) { _ in }
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
        .sheet(item: $memoryAgent) { agent in
            AgentMemorySheet(agent: agent, theme: theme)
                .frame(minWidth: 600, minHeight: 500)
        }
    }

    // MARK: - Grid helpers

    private let cardW: CGFloat = 345

    /// Returns columns + row gap + total grid width for centered layout.
    private func tableLayout(for availableWidth: CGFloat) -> (columns: [GridItem], rowGap: CGFloat, gridWidth: CGFloat) {
        let minGap: CGFloat = 28
        let count = max(1, Int((availableWidth + minGap) / (cardW + minGap)))
        let gap = count > 1
            ? (availableWidth - CGFloat(count) * cardW) / CGFloat(count - 1)
            : 0
        let colGap = max(minGap, gap)
        let gridWidth = CGFloat(count) * cardW + CGFloat(max(0, count - 1)) * colGap
        return (Array(repeating: GridItem(.fixed(cardW), spacing: colGap), count: count), colGap, gridWidth)
    }

    private func agentCard(_ agent: AgentDefinition) -> some View {
        AgentBaseballCard(
            agent: agent,
            theme: theme,
            accentColor: accentColor,
            lastRun: state.agentService.logs[agent.id]?.last?.startedAt,
            lastOutput: state.agentService.logs[agent.id]?.reversed().first(where: { $0.status != .running })?.output,
            lastStatus: state.agentService.logs[agent.id]?.last?.status,
            lastError: {
                let last = state.agentService.logs[agent.id]?.last
                return last?.status == .failed ? last?.error : nil
            }(),
            isRunning: state.agentService.runningAgents.contains(agent.id),
            liveText: state.agentService.liveOutput[agent.id] ?? "",
            onEdit: { startEditingAgent(agent) },
            onDelete: { pendingDeleteAgent = agent },
            onDuplicate: { duplicateAgent(agent) },
            onLogbook: { openLogbook(for: agent) },
            onMemory: { memoryAgent = agent },
            onRerun: { Task { await state.agentService.executeScheduledAgent(agent) } }
        )
    }

    private func openLogbook(for agent: AgentDefinition) {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        // Agent may write to agent-memory/{name}/ or agent-memory/{id}/
        let reportByName = URL(fileURLWithPath: "\(home)/.claude/agent-memory/\(agent.name)/daily_report.txt")
        let reportById   = URL(fileURLWithPath: "\(home)/.claude/agent-memory/\(agent.id)/daily_report.txt")
        let mdURL        = URL(fileURLWithPath: "\(home)/.claude/agents/\(agent.id)/logbook.md")
        let jsonURL      = URL(fileURLWithPath: "\(home)/.claude/agent-logs/\(agent.id).json")
        let targetURL: URL
        if fm.fileExists(atPath: reportByName.path) {
            targetURL = reportByName
        } else if fm.fileExists(atPath: reportById.path) {
            targetURL = reportById
        } else if fm.fileExists(atPath: mdURL.path) {
            targetURL = mdURL
        } else if fm.fileExists(atPath: jsonURL.path) {
            targetURL = jsonURL
        } else {
            try? FileManager.default.createDirectory(at: mdURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "# Logbook — \(agent.name)\n\n_(No entries yet)_\n".write(to: mdURL, atomically: true, encoding: .utf8)
            targetURL = mdURL
        }
        let sublimeURL = URL(fileURLWithPath: "/Applications/Sublime Text.app")
        if FileManager.default.fileExists(atPath: sublimeURL.path) {
            NSWorkspace.shared.open([targetURL], withApplicationAt: sublimeURL, configuration: .init(), completionHandler: nil)
        } else {
            NSWorkspace.shared.open(targetURL)
        }
    }

    private func agentSectionHeader(title: String, count: Int, color: Color, gridWidth: CGFloat) -> some View {
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
        .frame(width: gridWidth)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
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
        showEditor = true
    }

    private func startEditingAgent(_ agent: AgentDefinition) {
        editingAgentId = agent.id
        editorDraft = AgentDraft(agent: agent)
        editorError = nil
        showEditor = true
    }

    private func saveAgentDraft() {
        let draft = editorDraft
        let previousId = editingAgentId

        Task { @MainActor in
            do {
                let saved = try await state.agentService.saveAgent(draft, previousId: previousId)
                editingAgentId = saved.id
                editorError = nil
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
            _ = try? await state.agentService.duplicateAgent(agent)
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
            for url in panel.urls {
                _ = try? await state.agentService.importAgent(from: url)
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
        try? state.agentService.exportAgent(agent, to: url)
    }

    private func deleteAgent(_ agent: AgentDefinition) {
        Task { @MainActor in
            try? await state.agentService.deleteAgent(agentId: agent.id)
            pendingDeleteAgent = nil
        }
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

    private let portraitIds = (1...17).map { String(format: "ap%02d", $0) }

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
                            editorField("Color", hint: "purple, blue, green, orange, red, cyan, yellow, pink, indigo, teal") {
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

                        VStack(alignment: .leading, spacing: 12) {
                            editorField("Triggers", hint: "Kommagetrennte Schlüsselwörter") {
                                TextField("code review, API, bug", text: $draft.triggers)
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

                        Divider().foregroundStyle(theme.cardBorder)

                        HStack(spacing: 8) {
                            Text("TIMEOUT")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.tertiaryText)
                                .kerning(0.5)
                            TextField("30", text: $draft.timeoutMinutes)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                            Text("Minuten (Standard: 30)")
                                .font(.system(size: 10))
                                .foregroundStyle(theme.tertiaryText)
                        }
                    }
                    .padding(16)
                    .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.cardBorder, lineWidth: 0.5)
                    )

                    // Portrait section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.square")
                                .font(.system(size: 11))
                                .foregroundStyle(Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255))
                            Text("Portrait")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.primaryText)
                            if !draft.portrait.isEmpty {
                                Button {
                                    draft.portrait = ""
                                } label: {
                                    Text("Entfernen")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(80), spacing: 10), count: 5), spacing: 10) {
                            ForEach(portraitIds, id: \.self) { pid in
                                portraitThumb(pid)
                            }
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

    private func portraitThumb(_ pid: String) -> some View {
        let isSelected = draft.portrait == pid
        let accentColor = Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
        return Button {
            draft.portrait = isSelected ? "" : pid
        } label: {
            Group {
                if let url = Bundle.module.url(forResource: pid, withExtension: "png"),
                   let img = NSImage(contentsOf: url) {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.2))
                        .overlay(Text(pid).font(.system(size: 8)).foregroundStyle(.secondary))
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? accentColor : Color.clear, lineWidth: 2)
            )
            .overlay(
                isSelected ?
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(3)
                : nil
            )
        }
        .buttonStyle(.plain)
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

// MARK: - Agent Memory Sheet

private struct AgentMemorySheet: View {
    let agent: AgentDefinition
    let theme: AppTheme
    @Environment(\.dismiss) private var dismiss
    @State private var memoryFiles: [MemoryFileEntry] = []
    @State private var selectedFile: MemoryFileEntry?
    @State private var fileContent: String = ""
    @State private var isLoading = true

    private struct MemoryFileEntry: Identifiable, Hashable {
        let id: String
        let name: String
        let url: URL
        let size: Int64
        let modified: Date
    }

    private var memoryDirs: [URL] {
        let home = NSHomeDirectory()
        return [
            URL(fileURLWithPath: "\(home)/.claude/agent-memory/\(agent.name)"),
            URL(fileURLWithPath: "\(home)/.claude/agent-memory/\(agent.id)")
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 14))
                            .foregroundStyle(agent.dotColor)
                        Text("Memory — \(agent.name)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                    }
                    Text("~/.claude/agent-memory/\(agent.name)/")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(theme.tertiaryText)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Divider().foregroundStyle(theme.cardBorder)

            if isLoading {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            } else if memoryFiles.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "brain")
                        .font(.system(size: 32))
                        .foregroundStyle(theme.tertiaryText.opacity(0.4))
                    Text("Keine Memory-Dateien")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                    Text("Dieser Agent hat noch keine Dateien in\n~/.claude/agent-memory/ gespeichert.")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                HSplitView {
                    // File list sidebar
                    VStack(spacing: 0) {
                        List(memoryFiles, selection: $selectedFile) { entry in
                            HStack(spacing: 6) {
                                Image(systemName: fileIcon(for: entry.name))
                                    .font(.system(size: 10))
                                    .foregroundStyle(agent.dotColor)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(theme.primaryText)
                                        .lineLimit(1)
                                    Text(formatSize(entry.size) + " · " + formatDate(entry.modified))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(theme.tertiaryText)
                                }
                            }
                            .padding(.vertical, 2)
                            .tag(entry)
                        }
                        .listStyle(.sidebar)
                    }
                    .frame(minWidth: 160, idealWidth: 190, maxWidth: 240)

                    // File content viewer
                    VStack(spacing: 0) {
                        if let selected = selectedFile {
                            HStack(spacing: 6) {
                                Text(selected.name)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(theme.primaryText)
                                Spacer()
                                Button {
                                    openInEditor(selected.url)
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .help("In Editor öffnen")
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(theme.cardBg)

                            Divider().foregroundStyle(theme.cardBorder)

                            ScrollView {
                                Text(fileContent)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(theme.primaryText)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .padding(12)
                            }
                        } else {
                            Spacer()
                            Text("Datei auswählen")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.tertiaryText)
                            Spacer()
                        }
                    }
                    .frame(minWidth: 300)
                }
            }
        }
        .background(theme.windowBg)
        .task { loadMemoryFiles() }
        .onChange(of: selectedFile) { _, newFile in
            guard let file = newFile else { fileContent = ""; return }
            fileContent = (try? String(contentsOf: file.url, encoding: .utf8)) ?? "(Datei konnte nicht gelesen werden)"
        }
    }

    private func loadMemoryFiles() {
        let fm = FileManager.default
        var entries: [MemoryFileEntry] = []
        var seenPaths = Set<String>()

        for dir in memoryDirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
            for item in items {
                guard !item.lastPathComponent.hasPrefix("."),
                      seenPaths.insert(item.lastPathComponent).inserted else { continue }
                let attrs = try? item.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                entries.append(MemoryFileEntry(
                    id: item.path,
                    name: item.lastPathComponent,
                    url: item,
                    size: Int64(attrs?.fileSize ?? 0),
                    modified: attrs?.contentModificationDate ?? Date.distantPast
                ))
            }
        }

        memoryFiles = entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        isLoading = false

        // Auto-select first file
        if selectedFile == nil, let first = memoryFiles.first {
            selectedFile = first
        }
    }

    private func fileIcon(for name: String) -> String {
        if name.hasSuffix(".md") { return "doc.richtext" }
        if name.hasSuffix(".txt") { return "doc.text" }
        if name.hasSuffix(".json") { return "curlybraces" }
        return "doc"
    }

    private func formatSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        return String(format: "%.1f KB", Double(bytes) / 1024)
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "dd.MM.yy HH:mm"
        return fmt.string(from: date)
    }

    private func openInEditor(_ url: URL) {
        let sublimeURL = URL(fileURLWithPath: "/Applications/Sublime Text.app")
        if FileManager.default.fileExists(atPath: sublimeURL.path) {
            NSWorkspace.shared.open([url], withApplicationAt: sublimeURL, configuration: .init(), completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
