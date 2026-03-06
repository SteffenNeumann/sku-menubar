import SwiftUI
import AppKit

// MARK: - Glassmorphism background

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

// MARK: - Content

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {

                // ── Header ───────────────────────────────────────────────
                HStack(spacing: 8) {
                    Image(systemName: "eurosign.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                    Text("SKU Budget")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if state.isLoading {
                        ProgressView().scaleEffect(0.55).frame(width: 14, height: 14)
                    } else if state.errorMsg != nil {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red).font(.system(size: 12))
                    } else {
                        Circle().fill(.green).frame(width: 7, height: 7)
                    }
                    Button {
                        Task { await state.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Aktualisieren")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

                glassDiv

                // ── Budget bars ──────────────────────────────────────────
                BudgetBarsView()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                // ── Error ────────────────────────────────────────────────
                if let err = state.errorMsg {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.system(size: 11))
                        Text(err)
                            .font(.system(size: 11))
                            .lineLimit(2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                glassDiv

                // ── Habit tracker ────────────────────────────────────────
                // Extra padding-top damit Hover-Popups der 1. Zeile nicht abgeschnitten werden
                HabitGridView(days: state.dailyUsage)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                glassDiv

                // ── Footer ───────────────────────────────────────────────
                HStack {
                    if let t = state.lastUpdate {
                        Label(t.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Noch nicht geladen")
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button { state.showSettings.toggle() } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain).help("Einstellungen")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                // ── Settings ─────────────────────────────────────────────
                if state.showSettings {
                    glassDiv
                    SettingsFormView()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }
        }
        .frame(width: 330)
        .frame(minHeight: 200, maxHeight: 660)
        .background(VisualEffectBackground())
    }

    // Hauch-Trennlinie im Glas-Stil
    private var glassDiv: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
    }
}
