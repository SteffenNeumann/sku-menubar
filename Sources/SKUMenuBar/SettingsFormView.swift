import SwiftUI

struct SettingsFormView: View {
    @EnvironmentObject var state: AppState

    // Local copy – only applied on "Speichern"
    @State private var draft = GitHubSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Info hint
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 11))
                Text("Fine-grained PAT benötigt:\nUser → Permission: Plan (read)\nOrg → Permission: Administration (read)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            field("GitHub Token (Fine-grained PAT)") {
                SecureField("github_pat_…", text: $draft.token)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    label("Account-Typ")
                    Picker("", selection: $draft.accountType) {
                        Text("User").tag("user")
                        Text("Org").tag("org")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    label("Username / Org")
                    TextField("octocat", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                }
            }

            field("Produkt-Filter") {
                Picker("", selection: $draft.product) {
                    Text("Alle Produkte").tag("")
                    Text("Actions").tag("actions")
                    Text("Copilot").tag("copilot")
                    Text("Packages").tag("packages")
                    Text("Shared Storage").tag("shared_storage")
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    label("Monatsbudget (€)")
                    TextField("10", value: $draft.budget, format: .number)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    label("Auto-Update")
                    Picker("", selection: $draft.intervalSeconds) {
                        Text("1 Min").tag(60)
                        Text("5 Min").tag(300)
                        Text("10 Min").tag(600)
                        Text("30 Min").tag(1800)
                    }
                    .pickerStyle(.menu)
                }
            }

            Button("Speichern & Laden") {
                state.settings = draft
                state.showSettings = false
                Task { await state.refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .frame(maxWidth: .infinity)
            .font(.system(size: 12, weight: .semibold))
        }
        .font(.system(size: 12))
        .onAppear { draft = state.settings }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func field<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(title)
            content()
                .textFieldStyle(.roundedBorder)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
