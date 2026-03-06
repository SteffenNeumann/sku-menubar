import SwiftUI
import AppKit

// MARK: - NSVisualEffect background (blurs the desktop behind the panel)

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material     = material
        v.blendingMode = blendingMode
        v.state        = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material     = material
        v.blendingMode = blendingMode
    }
}

// MARK: - Reusable Glass Card modifier

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Content

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var refreshRotation: Double = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {

                // ── Header ──────────────────────────────────────────────
                headerCard

                // ── Budget ──────────────────────────────────────────────
                BudgetBarsView()

                // ── Error ───────────────────────────────────────────────
                if let err = state.errorMsg {
                    errorCard(err)
                }

                // ── Habit grid ──────────────────────────────────────────
                HabitGridView(days: state.dailyUsage)
                    .padding(14)
                    .glassCard()

                // ── Settings (inline expandable) ────────────────────────
                if state.showSettings {
                    SettingsFormView()
                        .padding(14)
                        .glassCard()
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal:   .move(edge: .top).combined(with: .opacity)
                        ))
                }

                // ── Footer ──────────────────────────────────────────────
                footerRow
            }
            .padding(12)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: state.showSettings)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: state.errorMsg != nil)
        }
        .frame(width: 360)
        .frame(minHeight: 220, maxHeight: 740)
        .background(VisualEffectBackground())
    }

    // MARK: - Header Card

    private var headerCard: some View {
        HStack(spacing: 12) {

            // Gradient icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(
                        LinearGradient(
                            colors: [.blue, Color(hue: 0.62, saturation: 0.8, brightness: 0.9)],
                            startPoint: .topLeading,
                            endPoint:   .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                    .shadow(color: .blue.opacity(0.45), radius: 6, y: 3)

                Image(systemName: "dollarsign")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }

            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text("SKU Budget")
                    .font(.system(size: 14, weight: .semibold))
                Text("GitHub Billing Monitor")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Status indicator
            statusIndicator

            // Refresh button
            Button {
                withAnimation(.linear(duration: 0.6)) { refreshRotation += 360 }
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(refreshRotation))
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Aktualisieren")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard()
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if state.isLoading {
            ProgressView()
                .scaleEffect(0.65)
                .frame(width: 18, height: 18)
        } else if state.errorMsg != nil {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 14))
        } else {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.25))
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: .green.opacity(0.7), radius: 4)
            }
        }
    }

    // MARK: - Error Card

    private func errorCard(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 13))
            Text(msg)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.orange.opacity(0.35), lineWidth: 0.5)
        )
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack {
            if let t = state.lastUpdate {
                Label(
                    t.formatted(date: .omitted, time: .shortened),
                    systemImage: "clock"
                )
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            } else {
                Text("Noch nicht geladen")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    state.showSettings.toggle()
                }
            } label: {
                Image(systemName: state.showSettings ? "xmark.circle.fill" : "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(state.showSettings ? .red.opacity(0.75) : .secondary)
                    .frame(width: 28, height: 28)
                    .background(.primary.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .help(state.showSettings ? "Schließen" : "Einstellungen")
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }
}
