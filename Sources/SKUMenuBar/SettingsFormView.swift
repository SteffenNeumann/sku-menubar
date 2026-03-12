import SwiftUI

struct SettingsFormView: View {
    @EnvironmentObject var state: AppState

    @State private var draft = GitHubSettings()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 16) {

            // ── Section header ──────────────────────────────────────
            Label("Einstellungen", systemImage: "gearshape.2.fill")
                .font(.system(size: 13, weight: .semibold))

            // ── GitHub Access ───────────────────────────────────────
            settingsSection(title: "GitHub Zugang") {
                // Info hint
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 11))
                    Text("Fine-grained PAT benötigt:\nUser → Permission: Plan (read)\nOrg → Permission: Administration (read)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.blue.opacity(0.25), lineWidth: 0.5)
                )

                inputField("GitHub Token (Fine-grained PAT)") {
                    SecureField("github_pat_…", text: $draft.token)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 8) {
                    inputField("Account-Typ") {
                        Picker("", selection: $draft.accountType) {
                            Text("User").tag("user")
                            Text("Org").tag("org")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    inputField("Username / Org") {
                        TextField("octocat", text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            // ── Währung ─────────────────────────────────────────────
            settingsSection(title: "Währung") {
                HStack(spacing: 8) {
                    inputField("Anzeige") {
                        Picker("", selection: $draft.currency) {
                            Text("USD ($)").tag("USD")
                            Text("EUR (€)").tag("EUR")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    inputField("EUR/USD Kurs") {
                        TextField("0.92", value: $draft.eurRate, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            // ── Budget & Filter ─────────────────────────────────────
            settingsSection(title: "Budget & Filter") {
                inputField("Produkt-Filter") {
                    Picker("", selection: $draft.product) {
                        Text("Alle Produkte").tag("")
                        Text("Actions").tag("actions")
                        Text("Copilot").tag("copilot")
                        Text("Packages").tag("packages")
                        Text("Shared Storage").tag("shared_storage")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    inputField("Monatsbudget ($)") {
                        TextField("10", value: $draft.budget, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    inputField("Auto-Update") {
                        Picker("", selection: $draft.intervalSeconds) {
                            Text("1 Min").tag(60)
                            Text("5 Min").tag(300)
                            Text("10 Min").tag(600)
                            Text("30 Min").tag(1800)
                        }
                        .pickerStyle(.menu)
                    }
                }
            }

            // ── Claude / Anthropic ──────────────────────────────────
            settingsSection(title: "Claude (Anthropic Admin API)") {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.purple)
                        .font(.system(size: 11))
                    Text("Admin Key von console.anthropic.com → Admin keys\nOrg-ID aus den Organization-Einstellungen")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.purple.opacity(0.25), lineWidth: 0.5))

                inputField("Anthropic Admin Key (sk-ant-admin01-…)") {
                    SecureField("sk-ant-admin01-…", text: $draft.anthropicAdminKey)
                        .textFieldStyle(.roundedBorder)
                }

                inputField("Organisation ID") {
                    TextField("936e48e3-…", text: $draft.anthropicOrgId)
                        .textFieldStyle(.roundedBorder)
                }

                inputField("Claude Wochenbudget in $ (0 = deaktiviert)") {
                    TextField("10", value: $draft.claudeWeeklyCostLimit, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // ── Save ────────────────────────────────────────────────
            Button {
                state.settings = draft
                withAnimation(.spring(response: 0.32)) {
                    state.showSettings = false
                }
                Task { await state.refresh() }
            } label: {
                Label("Speichern & Laden", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.large)
        }
        .font(.system(size: 12))
        .onAppear { draft = state.settings }
        } // ScrollView
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingsSection<C: View>(
        title: String,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.6)

            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func inputField<C: View>(
        _ title: String,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity)
    }
}
