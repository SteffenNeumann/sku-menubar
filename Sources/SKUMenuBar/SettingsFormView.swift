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
                VStack(alignment: .leading, spacing: 24) {

                    // ── 2-column Grid (rows stay aligned) ─────────────────
                    Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 24) {

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
                                    HStack(alignment: .bottom, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
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
                                        VStack(alignment: .leading, spacing: 6) {
                                            fieldLabel("Username / Org")
                                            TextField("octocat", text: $draft.name)
                                                .textFieldStyle(.plain)
                                                .styledInput(theme: theme)
                                        }
                                    }
                                }
                            }

                            configSection(title: "Currency", icon: "creditcard",
                                          hint: "Anzeigewährung und EUR/USD Wechselkurs für die Kostenumrechnung") {
                                configCard {
                                    HStack(alignment: .bottom, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            fieldLabel("Primary Currency")
                                            Picker("", selection: $draft.currency) {
                                                Text("USD ($)").tag("USD")
                                                Text("EUR (€)").tag("EUR")
                                            }
                                            .pickerStyle(.segmented)
                                            .labelsHidden()
                                            .frame(width: 130)
                                            .frame(height: 28)
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
                            configSection(title: "Budget & Filter", icon: "line.3.horizontal.decrease.circle",
                                          hint: "Filtere GitHub-Daten nach Produkt · Monatliches Ausgabenlimit in USD") {
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
                                          hint: "Admin Key · Org-ID aus den Anthropic Organization-Einstellungen") {
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
                            VStack(alignment: .leading, spacing: 16) {
                                // DARK subsection
                                VStack(alignment: .leading, spacing: 10) {
                                    themeGroupHeader(label: "DARK", icon: "moon.fill")
                                    let darkThemes = AppTheme.all.filter { !$0.isLight }
                                    LazyVGrid(
                                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                        alignment: .leading, spacing: 10
                                    ) {
                                        ForEach(darkThemes.prefix(3)) { t in themeSwatchButton(t) }
                                    }
                                    LazyVGrid(
                                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                        alignment: .leading, spacing: 10
                                    ) {
                                        ForEach(darkThemes.dropFirst(3)) { t in themeSwatchButton(t) }
                                    }
                                }

                                Divider().foregroundStyle(theme.cardBorder)

                                // LIGHT subsection
                                VStack(alignment: .leading, spacing: 10) {
                                    themeGroupHeader(label: "LIGHT", icon: "sun.max.fill")
                                    LazyVGrid(
                                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                                        alignment: .leading,
                                        spacing: 10
                                    ) {
                                        ForEach(AppTheme.all.filter { $0.isLight }) { t in
                                            themeSwatchButton(t)
                                        }
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
        .padding(18)
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

    // MARK: - Theme Group Header

    @ViewBuilder
    private func themeGroupHeader(label: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.tertiaryText)
                .kerning(0.5)
        }
    }

    // MARK: - Theme Swatch Button

    @ViewBuilder
    private func themeSwatchButton(_ t: AppTheme) -> some View {
        let isSelected = themeManager.current.id == t.id
        let ac = Color(red: t.acR/255, green: t.acG/255, blue: t.acB/255)
        let winBg = t.isLight
            ? Color(red: 246/255, green: 248/255, blue: 250/255)
            : Color(red: 2/255, green: 6/255, blue: 23/255)
        let sidebarBg = t.isLight
            ? Color(red: 248/255, green: 241/255, blue: 233/255)
            : Color(red: 8/255, green: 12/255, blue: 30/255)
        let cardFill = t.isLight
            ? Color(white: 0, opacity: 0.06)
            : Color(white: 1, opacity: 0.07)
        let navItem = t.isLight
            ? Color(white: 0, opacity: 0.10)
            : Color(white: 1, opacity: 0.10)

        Button {
            themeManager.current = t
        } label: {
            VStack(spacing: 5) {
                // ── Mini App Preview ──────────────────────────────
                ZStack {
                    // Window background
                    RoundedRectangle(cornerRadius: 9)
                        .fill(winBg)

                    HStack(spacing: 0) {
                        // Sidebar
                        VStack(alignment: .leading, spacing: 5) {
                            // Branding dot
                            Circle()
                                .fill(ac)
                                .frame(width: 6, height: 6)
                            // Active nav item
                            RoundedRectangle(cornerRadius: 2)
                                .fill(ac.opacity(0.30))
                                .frame(height: 6)
                            // Inactive nav items
                            ForEach(0..<4, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(navItem)
                                    .frame(height: 5)
                            }
                            Spacer()
                            // Budget bar
                            RoundedRectangle(cornerRadius: 1)
                                .fill(ac.opacity(0.6))
                                .frame(height: 2)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .frame(width: 38)
                        .background(sidebarBg)

                        // Separator
                        Rectangle()
                            .fill(t.isLight ? Color(white:0, opacity:0.08) : Color(white:1, opacity:0.08))
                            .frame(width: 0.5)

                        // Content area
                        VStack(alignment: .leading, spacing: 5) {
                            // Header bar
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(navItem)
                                    .frame(height: 6)
                                    .frame(maxWidth: .infinity)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(ac)
                                    .frame(width: 22, height: 6)
                            }
                            // Two-column cards
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

                    // Selected overlay + checkmark
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

                // Name + dark/light badge
                HStack(spacing: 3) {
                    Text(t.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isSelected ? ac : theme.secondaryText)
                        .lineLimit(1)
                    Image(systemName: t.isLight ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 7))
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
