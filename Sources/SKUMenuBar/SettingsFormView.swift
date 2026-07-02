import SwiftUI

// MARK: - Custom Toggle Style mit Theme-Akzentfarbe
struct AccentToggleStyle: ToggleStyle {
    let accentColor: Color
    @Environment(\.appTheme) var theme

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? accentColor : Color.primary.opacity(0.2))
                    .frame(width: 36, height: 20)
                Circle()
                    .fill(theme.isLight ? Color(white: 0.98) : Color.white)
                    .shadow(color: .black.opacity(theme.isLight ? 0.25 : 0.15), radius: 1.5)
                    .frame(width: 16, height: 16)
                    .offset(x: configuration.isOn ? 8 : -8)
                    .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
            }
            .onTapGesture { configuration.isOn.toggle() }
        }
    }
}

struct SettingsFormView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.appTheme) var theme

    @State private var draft = GitHubSettings()
    @State private var hasDocumentsAccess: Bool? = nil

    @AppStorage(FontKey.chatText)  private var chatFontRaw:  String = AppFontChoice.system.rawValue
    @AppStorage(FontKey.codeBlock) private var codeFontRaw:  String = AppFontChoice.system.rawValue

    private var chatFont:  AppFontChoice { AppFontChoice(rawValue: chatFontRaw)  ?? .system }
    private var codeFont:  AppFontChoice { AppFontChoice(rawValue: codeFontRaw)  ?? .system }

    private var accent: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
    }

    // Variante C: „Modelle aktualisieren"-Button (GET /v1/models).
    // Braucht den Messages API Key; ausgegraut solange keiner hinterlegt ist.
    @ViewBuilder
    private var modelCatalogRow: some View {
        let hasKey = !state.settings.anthropicApiKey.trimmingCharacters(in: .whitespaces).isEmpty
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Modell-Katalog")
            HStack(alignment: .top, spacing: 10) {
                Button {
                    Task { await state.refreshAvailableModels() }
                } label: {
                    HStack(spacing: 5) {
                        if state.modelsRefreshInProgress {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("Modelle aktualisieren")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.15)))
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .disabled(!hasKey || state.modelsRefreshInProgress)
                .opacity(hasKey ? 1 : 0.5)

                VStack(alignment: .leading, spacing: 1) {
                    let total = ModelCatalog.anthropicBundled.count + state.settings.discoveredModelIDs.count
                    let stamp = state.settings.modelsLastRefresh
                        .map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
                    Text("\(total) Modelle\(stamp)")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.tertiaryText)
                    if let r = state.modelsRefreshResult {
                        Text(r)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.secondaryText)
                    } else if !hasKey {
                        Text("API-Key erforderlich")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.tertiaryText)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Page Header ───────────────────────────────────────────────
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Configuration")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.primaryText)
                    Text("Passe deinen myClaude Workspace mit präzisen Einstellungen an.")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Button {
                    state.settings = draft
                    Task { await state.refresh() }
                } label: {
                    Label("Speichern & Laden", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .foregroundStyle(theme.cardBorder)

            // ── Scrollable Content ────────────────────────────────────────
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {

                    // ═══════════════════════════════════════════════════════
                    // CLUSTER: API & Authentifizierung
                    // ═══════════════════════════════════════════════════════
                    VStack(alignment: .leading, spacing: 12) {
                        clusterLabel("API & Authentifizierung")
                        clusterCard {
                            configRow(title: "GitHub Access",
                                      icon: "chevron.left.forwardslash.chevron.right",
                                      hint: "Fine-grained PAT · User → Plan (read)") {
                                VStack(alignment: .leading, spacing: 10) {
                                    SecureField("github_pat_…", text: $draft.token)
                                        .textFieldStyle(.plain)
                                        .styledInput(theme: theme)
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            fieldLabel("Account Type")
                                            Picker("", selection: $draft.accountType) {
                                                Text("User").tag("user")
                                                Text("Org").tag("org")
                                            }
                                            .pickerStyle(.segmented)
                                            .labelsHidden()
                                            .frame(width: 120)
                                            .frame(height: 28)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            fieldLabel("Username / Org")
                                            TextField("octocat", text: $draft.name)
                                                .textFieldStyle(.plain)
                                                .styledInput(theme: theme)
                                        }
                                    }
                                }
                            }
                            rowDivider()
                            configRow(title: "Currency",
                                      icon: "creditcard",
                                      hint: "EUR/USD Wechselkurs") {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        fieldLabel("Währung")
                                        Picker("", selection: $draft.currency) {
                                            Text("USD ($)").tag("USD")
                                            Text("EUR (€)").tag("EUR")
                                        }
                                        .pickerStyle(.segmented)
                                        .labelsHidden()
                                        .frame(width: 130)
                                        .frame(height: 28)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        fieldLabel("EUR/USD Kurs")
                                        TextField("0.92", value: $draft.eurRate, format: .number)
                                            .textFieldStyle(.plain)
                                            .styledInput(theme: theme)
                                    }
                                }
                            }
                        }
                    }

                    // ═══════════════════════════════════════════════════════
                    // CLUSTER: KI-Modelle & Limits
                    // ═══════════════════════════════════════════════════════
                    VStack(alignment: .leading, spacing: 12) {
                        clusterLabel("KI-Modelle & Limits")
                        clusterCard {
                            configRow(title: "Claude Admin API",
                                      icon: "cpu",
                                      hint: "Usage-Tracking mit Admin Key") {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            fieldLabel("Admin Key")
                                            SecureField("sk-ant-admin01-…", text: $draft.anthropicAdminKey)
                                                .textFieldStyle(.plain)
                                                .styledInput(theme: theme)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            fieldLabel("Weekly Token Limit")
                                            TextField("0", value: $draft.claudeWeeklyTokenLimit, format: .number)
                                                .textFieldStyle(.plain)
                                                .styledInput(theme: theme)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        fieldLabel("Messages API Key (optional)")
                                        SecureField("sk-ant-api03-…", text: $draft.anthropicApiKey)
                                            .textFieldStyle(.plain)
                                            .styledInput(theme: theme)
                                    }
                                    modelCatalogRow
                                    VStack(alignment: .leading, spacing: 4) {
                                        fieldLabel("Plan Limits")
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("Session-Token-Limit")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(theme.secondaryText)
                                                TextField("0", value: $draft.claudeSessionTokenLimit, format: .number)
                                                    .textFieldStyle(.plain)
                                                    .styledInput(theme: theme)
                                            }
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("Monats-Limit (€)")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(theme.secondaryText)
                                                TextField("0", value: $draft.claudeMonthlySpendLimit, format: .number)
                                                    .textFieldStyle(.plain)
                                                    .styledInput(theme: theme)
                                            }
                                        }
                                    }
                                }
                            }
                            rowDivider()
                            configRow(title: "Ollama",
                                      icon: "cpu.fill",
                                      hint: "Lokales LLM · kein API-Key nötig") {
                                VStack(alignment: .leading, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        fieldLabel("Base URL")
                                        TextField("http://localhost:11434/v1", text: $draft.ollamaBaseUrl)
                                            .textFieldStyle(.plain)
                                            .styledInput(theme: theme)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        fieldLabel("Modell")
                                        TextField("llama3.2", text: $draft.ollamaModel)
                                            .textFieldStyle(.plain)
                                            .styledInput(theme: theme)
                                    }
                                }
                            }
                            rowDivider()
                            configRow(title: "Copilot Fallback",
                                      icon: "arrow.triangle.2.circlepath",
                                      hint: "Bei Rate-Limit auf Copilot umschalten") {
                                VStack(alignment: .leading, spacing: 10) {
                                    Toggle("Automatisch umschalten", isOn: $draft.copilotFallbackEnabled)
                                        .toggleStyle(AccentToggleStyle(accentColor: theme.accentIcon))
                                        .font(.system(size: 13))
                                        .foregroundStyle(theme.primaryText)
                                    if draft.copilotFallbackEnabled {
                                        Picker("", selection: $draft.copilotFallbackModel) {
                                            ForEach(KnownModel.all.filter { $0.apiName.hasPrefix("github/") }, id: \.apiName) { model in
                                                Text("\(model.name) (\(model.provider))")
                                                    .tag(model.apiName)
                                            }
                                            Divider()
                                            ForEach(KnownModel.all.filter { !$0.apiName.hasPrefix("github/") }, id: \.apiName) { model in
                                                Text("\(model.name) (\(model.provider))")
                                                    .tag(model.apiName)
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                    }
                                }
                            }
                            rowDivider()
                            configRow(title: "Auto-Orchestrierung",
                                      icon: "rectangle.3.group.bubble",
                                      hint: "Lange Nachrichten automatisch auf mehrere Agents verteilen") {
                                Toggle("Auto-Orchestrierung aktiv", isOn: $draft.autoOrchestrationEnabled)
                                    .toggleStyle(AccentToggleStyle(accentColor: theme.accentIcon))
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.primaryText)
                                    .help("Aus: lange Nachrichten lösen nie automatisch eine Multi-Agent-Orchestrierung aus — es bleibt beim Einzel-Agent.")
                            }
                            rowDivider()
                            configRow(title: "Auto-MCP per Stichwort",
                                      icon: "bolt.horizontal.circle",
                                      hint: "MCP-Name im Chat (linear, make.com …) aktiviert den MCP automatisch") {
                                Toggle("Auto-MCP per Stichwort aktiv", isOn: $draft.autoActivateMCPByKeyword)
                                    .toggleStyle(AccentToggleStyle(accentColor: theme.accentIcon))
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.primaryText)
                                    .help("An: Fällt ein MCP-Name im Chat-Text, wird dieser MCP-Server für die Nachricht aktiviert (additiv, nie abgeschaltet). 'make' nur bei klarem Bezug wie 'make.com'.")
                            }
                            rowDivider()
                            configRow(title: "Token-Optimierung",
                                      icon: "slider.horizontal.3",
                                      hint: "History, Max-Turns, Auto-Compact") {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            fieldLabel("History-Fenster")
                                            HStack(spacing: 6) {
                                                TextField("8", value: $draft.historyWindowSize, formatter: NumberFormatter())
                                                    .styledInput(theme: theme)
                                                    .frame(width: 50)
                                                Text("Turns")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(theme.tertiaryText)
                                            }
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            fieldLabel("Max. Turns CLI")
                                            HStack(spacing: 6) {
                                                TextField("10", value: $draft.maxTurns, formatter: NumberFormatter())
                                                    .styledInput(theme: theme)
                                                    .frame(width: 50)
                                                Text("(0 = aus)")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(theme.tertiaryText)
                                            }
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        fieldLabel("Auto-Compact Schwelle")
                                        HStack(spacing: 6) {
                                            TextField("100000", value: $draft.autoCompactThreshold, formatter: NumberFormatter())
                                                .styledInput(theme: theme)
                                                .frame(width: 80)
                                            Text(draft.autoCompactThreshold > 0 ? "≥ \(draft.autoCompactThreshold >= 1000 ? String(format: "%.0fk", Double(draft.autoCompactThreshold) / 1000) : "\(draft.autoCompactThreshold)") Tokens → /compact" : "deaktiviert")
                                                .font(.system(size: 12))
                                                .foregroundStyle(theme.tertiaryText)
                                        }
                                    }
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            fieldLabel("Orchestrator Max. Turns")
                                            HStack(spacing: 6) {
                                                TextField("60", value: $draft.orchestratorMaxTurns, formatter: NumberFormatter())
                                                    .styledInput(theme: theme)
                                                    .frame(width: 50)
                                                Text("je Agent")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(theme.tertiaryText)
                                            }
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            fieldLabel("Orchestrator Idle-Timeout")
                                            HStack(spacing: 6) {
                                                TextField("120", value: $draft.orchestratorIdleTimeout, formatter: NumberFormatter())
                                                    .styledInput(theme: theme)
                                                    .frame(width: 50)
                                                Text("Sek. ohne Event")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(theme.tertiaryText)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═══════════════════════════════════════════════════════
                    // CLUSTER: Integrationen
                    // ═══════════════════════════════════════════════════════
                    VStack(alignment: .leading, spacing: 12) {
                        clusterLabel("Integrationen")
                        clusterCard {
                            configRow(title: "Budget & Filter",
                                      icon: "line.3.horizontal.decrease.circle",
                                      hint: "GitHub-Daten nach Produkt filtern") {
                                VStack(alignment: .leading, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        fieldLabel("Active Product")
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
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            fieldLabel("Monthly Budget ($)")
                                            TextField("50", value: $draft.budget, format: .number)
                                                .textFieldStyle(.plain)
                                                .styledInput(theme: theme)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            fieldLabel("Auto-Update")
                                            Picker("", selection: $draft.intervalSeconds) {
                                                Text("1 Min").tag(60)
                                                Text("5 Min").tag(300)
                                                Text("10 Min").tag(600)
                                                Text("30 Min").tag(1800)
                                            }
                                            .pickerStyle(.menu)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                            rowDivider()
                            configRow(title: "TMetric",
                                      icon: "timer",
                                      hint: "Zeitdaten in der Home-Kachel") {
                                VStack(alignment: .leading, spacing: 4) {
                                    fieldLabel("API Token")
                                    SecureField("Dein TMetric API Token…", text: $draft.tmetricApiToken)
                                        .textFieldStyle(.plain)
                                        .styledInput(theme: theme)
                                }
                            }
                        }
                    }

                    // ═══════════════════════════════════════════════════════
                    // CLUSTER: System
                    // ═══════════════════════════════════════════════════════
                    VStack(alignment: .leading, spacing: 12) {
                        clusterLabel("System")
                        clusterCard {
                            configRow(title: "Datei-Zugriff",
                                      icon: "folder.badge.gearshape",
                                      hint: "~/Documents ohne Bestätigungsdialog") {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 10) {
                                        if let access = hasDocumentsAccess {
                                            Circle()
                                                .fill(access ? theme.statusGreen : theme.statusOrange)
                                                .frame(width: 8, height: 8)
                                            Text(access ? "Zugriff vorhanden" : "Kein Zugriff")
                                                .font(.system(size: 13))
                                                .foregroundStyle(theme.primaryText)
                                        } else {
                                            ProgressView().controlSize(.small)
                                            Text("Prüfe…")
                                                .font(.system(size: 13))
                                                .foregroundStyle(theme.secondaryText)
                                        }
                                        Spacer()
                                        Button {
                                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                                        } label: {
                                            Label("Full Disk Access", systemImage: "gear")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(accent)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                        }
                                        .buttonStyle(.plain)
                                        Button {
                                            checkDocumentsAccess()
                                        } label: {
                                            Image(systemName: "arrow.clockwise")
                                                .font(.system(size: 12))
                                                .foregroundStyle(theme.secondaryText)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // ═══════════════════════════════════════════════════════
                    // CLUSTER: Appearance
                    // ═══════════════════════════════════════════════════════
                    VStack(alignment: .leading, spacing: 12) {
                        clusterLabel("Schrift")
                        clusterCard {
                            VStack(alignment: .leading, spacing: 16) {

                                // Chat-Text
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Chat-Text")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(theme.secondaryText)
                                    HStack(spacing: 8) {
                                        ForEach(AppFontChoice.allCases, id: \.rawValue) { choice in
                                            fontChip(choice, selected: chatFont == choice) {
                                                chatFontRaw = choice.rawValue
                                            }
                                        }
                                    }
                                    fontPreview(choice: chatFont, monospace: false)
                                }

                                Divider().foregroundStyle(theme.cardBorder)

                                // Code-Blöcke
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Code-Blöcke")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(theme.secondaryText)
                                    HStack(spacing: 8) {
                                        ForEach(AppFontChoice.allCases, id: \.rawValue) { choice in
                                            fontChip(choice, selected: codeFont == choice) {
                                                codeFontRaw = choice.rawValue
                                            }
                                        }
                                    }
                                    fontPreview(choice: codeFont, monospace: true)
                                }
                            }
                            .padding(18)
                        }

                        clusterLabel("Appearance")
                        clusterCard {
                            VStack(alignment: .leading, spacing: 16) {
                                let darkThemes = AppTheme.all.filter { !$0.isLight && !$0.isMedium }
                                let mediumThemes = AppTheme.all.filter { $0.isMedium }
                                let lightThemes = AppTheme.all.filter { $0.isLight }

                                VStack(alignment: .leading, spacing: 10) {
                                    themeGroupHeader(label: "DARK", icon: "moon.fill")
                                    LazyVGrid(
                                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                        alignment: .leading, spacing: 10
                                    ) {
                                        ForEach(darkThemes.prefix(4)) { t in themeSwatchButton(t) }
                                    }
                                    LazyVGrid(
                                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                        alignment: .leading, spacing: 10
                                    ) {
                                        ForEach(darkThemes.dropFirst(4)) { t in themeSwatchButton(t) }
                                    }
                                }

                                Divider().foregroundStyle(theme.cardBorder)

                                VStack(alignment: .leading, spacing: 10) {
                                    themeGroupHeader(label: "MEDIUM", icon: "circle.lefthalf.filled")
                                    LazyVGrid(
                                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                        alignment: .leading, spacing: 10
                                    ) {
                                        ForEach(mediumThemes) { t in themeSwatchButton(t) }
                                    }
                                }

                                Divider().foregroundStyle(theme.cardBorder)

                                VStack(alignment: .leading, spacing: 10) {
                                    themeGroupHeader(label: "LIGHT", icon: "sun.max.fill")
                                    LazyVGrid(
                                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                        alignment: .leading,
                                        spacing: 10
                                    ) {
                                        ForEach(lightThemes) { t in themeSwatchButton(t) }
                                    }
                                }
                            }
                            .padding(18)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .font(.system(size: 14))
        .onAppear {
            draft = state.settings
            checkDocumentsAccess()
        }
        .onChange(of: draft.claudeSessionTokenLimit)  { state.settings.claudeSessionTokenLimit  = $0 }
        .onChange(of: draft.claudeMonthlySpendLimit)  { state.settings.claudeMonthlySpendLimit  = $0 }
        .onChange(of: draft.claudeWeeklyTokenLimit)    { state.settings.claudeWeeklyTokenLimit    = $0 }
        .onChange(of: draft.tmetricApiToken) { newToken in
            state.settings.tmetricApiToken = newToken
            if !newToken.isEmpty {
                Task { await state.refreshTMetric(force: true) }
            }
        }
    }

    // MARK: - File Access Check

    private func checkDocumentsAccess() {
        Task.detached(priority: .utility) {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            guard let docs else { await MainActor.run { hasDocumentsAccess = true }; return }
            let accessible = (try? FileManager.default.contentsOfDirectory(atPath: docs.path)) != nil
            await MainActor.run { hasDocumentsAccess = accessible }
        }
    }

    // MARK: - Font Helpers

    @ViewBuilder
    private func fontChip(_ choice: AppFontChoice, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(choice.displayName)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? theme.windowBg : theme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selected ? Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255) : theme.cardBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(theme.cardBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func fontPreview(choice: AppFontChoice, monospace: Bool) -> some View {
        let sample = monospace
            ? "func greet(_ name: String) -> String {\n    return \"Hello, \\(name)!\"\n}"
            : "Die KI analysiert den Kontext und generiert eine präzise Antwort basierend auf deiner Anfrage."
        let font: Font = {
            switch choice {
            case .system:        return monospace ? .system(size: 12, design: .monospaced) : .system(size: 13)
            case .jetbrainsMono: return .custom("JetBrainsMono-Regular", size: 12)
            }
        }()
        Text(sample)
            .font(font)
            .foregroundStyle(theme.secondaryText)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(theme.rowBg))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.cardBorder, lineWidth: 1))
    }

    // MARK: - Cluster Label

    @ViewBuilder
    private func clusterLabel(_ title: String) -> some View {
        HStack(spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.tertiaryText)
                .kerning(1)
            VStack { Divider().foregroundStyle(theme.cardBorder) }
        }
    }

    // MARK: - Cluster Card (one card per cluster)

    @ViewBuilder
    private func clusterCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mirrorCard()
    }

    // MARK: - Config Row (label left, controls right)

    @ViewBuilder
    private func configRow<C: View>(
        title: String,
        icon: String,
        hint: String? = nil,
        @ViewBuilder controls: () -> C
    ) -> some View {
        HStack(alignment: .top, spacing: 24) {
            // Left column: title + hint
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(accent)
                        .frame(width: 16, alignment: .center)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                }
                if let hint {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 23)
                }
            }
            .frame(width: 220, alignment: .leading)

            // Right column: controls
            VStack(alignment: .leading, spacing: 10) {
                controls()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Row Divider

    @ViewBuilder
    private func rowDivider() -> some View {
        Divider()
            .foregroundStyle(theme.cardBorder)
            .padding(.horizontal, 18)
    }

    // MARK: - Field Label

    @ViewBuilder
    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.tertiaryText)
            .kerning(0.5)
    }

    // MARK: - Theme Group Header

    @ViewBuilder
    private func themeGroupHeader(label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .kerning(0.5)
        }
    }

    // MARK: - Theme Swatch Button

    @ViewBuilder
    private func themeSwatchButton(_ t: AppTheme) -> some View {
        let isSelected = themeManager.current.id == t.id
        let ac = Color(red: t.acR/255, green: t.acG/255, blue: t.acB/255)
        let winBg: Color = t.isLight
            ? Color(red: t.bgTopR/255, green: t.bgTopG/255, blue: t.bgTopB/255)
            : (t.glowEnabled
               ? Color(red: 2/255, green: 6/255, blue: 23/255)
               : Color(red: t.bgTopR/255, green: t.bgTopG/255, blue: t.bgTopB/255))
        let sidebarBg: Color = t.isLight
            ? Color(red: 248/255, green: 241/255, blue: 233/255)
            : (t.isMedium
               ? Color(red: t.bgBotR/255, green: t.bgBotG/255, blue: t.bgBotB/255)
               : (t.glowEnabled
                  ? Color(red: 8/255, green: 12/255, blue: 30/255)
                  : Color(red: t.bgBotR/255, green: t.bgBotG/255, blue: t.bgBotB/255)))
        let useDarkElements = t.isLight || t.isMedium
        let cardFill = useDarkElements ? Color(white: 0, opacity: 0.08) : Color(white: 1, opacity: 0.07)
        let navItem  = useDarkElements ? Color(white: 0, opacity: 0.12) : Color(white: 1, opacity: 0.10)

        Button {
            themeManager.current = t
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(winBg)

                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 5) {
                            Circle()
                                .fill(ac)
                                .frame(width: 6, height: 6)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(ac.opacity(0.30))
                                .frame(height: 6)
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(navItem)
                                    .frame(height: 5)
                            }
                            Spacer()
                            RoundedRectangle(cornerRadius: 1)
                                .fill(ac.opacity(0.6))
                                .frame(height: 2)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .frame(width: 38)
                        .background(sidebarBg)

                        Rectangle()
                            .fill(useDarkElements ? Color(white:0, opacity:0.10) : Color(white:1, opacity:0.08))
                            .frame(width: 0.5)

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(navItem)
                                    .frame(height: 6)
                                    .frame(maxWidth: .infinity)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(ac)
                                    .frame(width: 22, height: 6)
                            }
                            HStack(spacing: 4) {
                                ForEach(0..<2, id: \.self) { _ in
                                    VStack(spacing: 3) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(cardFill)
                                            .frame(maxWidth: .infinity)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(navItem.opacity(0.6))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 4)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .padding(7)
                        .frame(maxWidth: .infinity)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                    if isSelected {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(ac.opacity(0.10))
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(ac)
                            .shadow(color: winBg.opacity(0.8), radius: 3)
                    }
                }
                .aspectRatio(1.618, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(isSelected ? ac : theme.cardBorder,
                                      lineWidth: isSelected ? 2 : 1)
                )

                HStack(spacing: 3) {
                    Text(t.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? ac : theme.secondaryText)
                        .lineLimit(1)
                    Image(systemName: t.isLight ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Styled Input Modifier

private struct StyledInput: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        content
            .font(.system(size: 14))
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(theme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(theme.cardBorder, lineWidth: 1)
            )
    }
}

private extension View {
    func styledInput(theme: AppTheme) -> some View {
        modifier(StyledInput(theme: theme))
    }
}
