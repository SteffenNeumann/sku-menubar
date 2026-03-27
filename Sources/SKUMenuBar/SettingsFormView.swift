import SwiftUI

struct SettingsFormView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.appTheme) var theme

    @State private var draft = GitHubSettings()

    private var accent: Color {
        Color(red: theme.acR/255, green: theme.acG/255, blue: theme.acB/255)
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
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer()
                Button {
                    state.settings = draft
                    Task { await state.refresh() }
                } label: {
                    Label("Speichern & Laden", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
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
                VStack(alignment: .leading, spacing: 20) {

                    // ── 2-column Grid (rows stay aligned) ─────────────────
                    Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 20) {

                        // Row 1: GitHub Access | Currency
                        GridRow(alignment: .top) {
                            configSection(title: "GitHub Access", icon: "chevron.left.forwardslash.chevron.right",
                                          hint: "Fine-grained PAT · User → Plan (read) · Org → Administration (read)") {
                                configCard {
                                    VStack(alignment: .leading, spacing: 14) {
                                        fieldLabel("Personal Access Token")
                                        SecureField("github_pat_…", text: $draft.token)
                                            .textFieldStyle(.plain)
                                            .styledInput(theme: theme)
                                    }
                                    Divider().foregroundStyle(theme.cardBorder).padding(.vertical, 2)
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            fieldLabel("Account Type")
                                            Picker("", selection: $draft.accountType) {
                                                Text("User").tag("user")
                                                Text("Org").tag("org")
                                            }
                                            .pickerStyle(.segmented)
                                            .labelsHidden()
                                            .frame(width: 120)
                                        }
                                        VStack(alignment: .leading, spacing: 6) {
                                            fieldLabel("Username / Org")
                                            TextField("octocat", text: $draft.name)
                                                .textFieldStyle(.plain)
                                                .styledInput(theme: theme)
                                        }
                                    }
                                }
                            }

                            configSection(title: "Currency", icon: "creditcard") {
                                configCard {
                                    HStack(alignment: .top, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            fieldLabel("Primary Currency")
                                            Picker("", selection: $draft.currency) {
                                                Text("USD ($)").tag("USD")
                                                Text("EUR (€)").tag("EUR")
                                            }
                                            .pickerStyle(.segmented)
                                            .labelsHidden()
                                            .frame(width: 130)
                                        }
                                        VStack(alignment: .leading, spacing: 6) {
                                            fieldLabel("EUR/USD Kurs")
                                            TextField("0.92", value: $draft.eurRate, format: .number)
                                                .textFieldStyle(.plain)
                                                .styledInput(theme: theme)
                                        }
                                    }
                                }
                            }
                        }

                        // Row 2: Budget & Filter | Claude Admin API
                        GridRow(alignment: .top) {
                            configSection(title: "Budget & Filter", icon: "line.3.horizontal.decrease.circle") {
                                configCard {
                                    VStack(alignment: .leading, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
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
                                        HStack(alignment: .top, spacing: 12) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                fieldLabel("Monthly Budget ($)")
                                                TextField("10", value: $draft.budget, format: .number)
                                                    .textFieldStyle(.plain)
                                                    .styledInput(theme: theme)
                                            }
                                            VStack(alignment: .leading, spacing: 6) {
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
                            }

                            configSection(title: "Claude (Anthropic Admin API)", icon: "cpu",
                                          hint: "Admin Key von console.anthropic.com → Admin keys · Org-ID aus den Organization-Einstellungen") {
                                configCard {
                                    VStack(alignment: .leading, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            fieldLabel("Admin Key")
                                            SecureField("sk-ant-admin01-…", text: $draft.anthropicAdminKey)
                                                .textFieldStyle(.plain)
                                                .styledInput(theme: theme)
                                        }
                                        HStack(alignment: .top, spacing: 12) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                fieldLabel("Organization ID")
                                                TextField("936e48e3-…", text: $draft.anthropicOrgId)
                                                    .textFieldStyle(.plain)
                                                    .styledInput(theme: theme)
                                            }
                                            VStack(alignment: .leading, spacing: 6) {
                                                fieldLabel("Weekly Budget ($)")
                                                TextField("0", value: $draft.claudeWeeklyCostLimit, format: .number)
                                                    .textFieldStyle(.plain)
                                                    .styledInput(theme: theme)
                                            }
                                        }
                                    }
                                }
                            }
                        } // end GridRow 2
                    } // end Grid

                    // ── Appearance — full width ────────────────────────────
                    configSection(title: "Appearance", icon: "paintpalette") {
                        configCard {
                            VStack(alignment: .leading, spacing: 10) {
                                fieldLabel("Theme Presets")
                                LazyVGrid(
                                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                                    spacing: 10
                                ) {
                                    ForEach(AppTheme.all) { t in
                                        themeSwatchButton(t)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .font(.system(size: 12))
        .onAppear { draft = state.settings }
    }

    // MARK: - Section Header

    @ViewBuilder
    private func configSection<C: View>(
        title: String,
        icon: String,
        hint: String? = nil,
        @ViewBuilder content: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(accent)
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                }
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.tertiaryText)
                        .padding(.leading, 22)
                }
            }
            content()
        }
    }

    // MARK: - Card Container

    @ViewBuilder
    private func configCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mirrorCard()
    }

    // MARK: - Field Label

    @ViewBuilder
    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.tertiaryText)
            .kerning(0.5)
    }

    // MARK: - Theme Swatch Button

    @ViewBuilder
    private func themeSwatchButton(_ t: AppTheme) -> some View {
        let isSelected = themeManager.current.id == t.id
        let swatchColor = Color(red: t.acR/255, green: t.acG/255, blue: t.acB/255)

        Button {
            themeManager.current = t
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(swatchColor)
                        .frame(height: 44)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                Text(t.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? accent : theme.cardBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
                    .padding(-4)
            )
            .padding(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Styled Input Modifier

private struct StyledInput: ViewModifier {
    let theme: AppTheme

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12))
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
