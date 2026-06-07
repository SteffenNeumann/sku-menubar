import SwiftUI

// MARK: - FrozenSectionLayout
//
// PROBLEM: frame(0,0) verhindert NICHT die Kind-Messung durch _FlexFrameLayout.sizeThatFits —
// SwiftUI ruft trotzdem child.sizeThatFits() auf (für Placement), was die gesamte Kaskade
// (NavigationStackLayout → _ZStackLayout → MessageBubble × N → QLFilePreviewView …) bei JEDEM
// 60fps-AnimationsFrame triggert (z.B. SidebarView-Pulse, BouncingDot).
// Mit 3+ GB Speicher / hunderten MessageBubbleViews dauert ein Layout-Pass länger als 16 ms →
// Frames stauen sich auf → 100 % CPU → Hang.
//
// LÖSUNG: Swift Layout-Protokoll. FrozenSectionLayout.sizeThatFits() liest bei isActive=false
// die Subviews NICHT → kein AttributeGraph-Dependency auf das Kind → Layout-Kaskade entfällt.
// Das Kind bleibt in der Hierarchie (gleiche Identität, @State bleibt erhalten).
// Intern (nicht private) — wird auch von ChatView für Tab-Isolation verwendet.
struct FrozenSectionLayout: Layout {
    var isActive: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // KRITISCH: bei isActive=false keine Kind-Messung → O(1) Layout-Cost statt O(N×Messages).
        // Das unterbricht die AttributeGraph-Abhängigkeit zwischen dem teuren Kind und dem
        // umgebenden ZStack, sodass 60fps-Animationen keinen Layout-Loop auslösen.
        guard isActive, let child = subviews.first else { return .zero }
        return child.sizeThatFits(proposal)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        if isActive {
            child.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        } else {
            // Platzierung mit .zero-Proposal hält das Kind im Graph (State erhalten),
            // ohne einen teuren Placement-Pass zu erzwingen.
            child.place(at: bounds.origin, proposal: .zero)
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedSection: AppSection = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var previousSection: AppSection? = nil
    @State private var sectionMonitor: Any? = nil
    // Lazy flags — heavy views are only instantiated when first visited
    @State private var chatLoaded       = false
    @State private var filesLoaded      = false
    @State private var codeReviewLoaded = false
    @State private var linearLoaded     = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedSection)
                .navigationSplitViewColumnWidth(min: 160, ideal: 210, max: 280)
        } detail: {
            ZStack {
                GlowBackground()
                    .ignoresSafeArea()

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("")
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: state.pendingChatSession) {
            if state.pendingChatSession != nil {
                columnVisibility = .all
                selectedSection = .chat
            }
        }
        .onChange(of: state.pendingNavigateToChat) { _, navigate in
            if navigate {
                state.pendingNavigateToChat = false
                columnVisibility = .all
                selectedSection = .chat
            }
        }
        .onChange(of: state.hideSidebar) { _, hidden in
            withAnimation { columnVisibility = hidden ? .detailOnly : .all }
        }
        .onChange(of: selectedSection) { old, _ in
            previousSection = old
        }
        .onAppear {
            sectionMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let flags = event.modifierFlags
                guard flags.contains(.command), flags.contains(.control),
                      event.keyCode == 123 || event.keyCode == 124,
                      let prev = previousSection else { return event }
                // Kein withAnimation — Spring-Animation beim ZStack-Switch mit hidden Views
                // führt zu Layout-Loop (jeder Frame misst ALLE ZStack-Kinder inkl. ChatView).
                selectedSection = prev
                return nil
            }
        }
        .onDisappear {
            if let monitor = sectionMonitor {
                NSEvent.removeMonitor(monitor)
                sectionMonitor = nil
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(WindowConfigurator().frame(width: 0, height: 0))
    }

    @ViewBuilder
    private var detailView: some View {
        ZStack {
            // Schwere Views: FrozenSectionLayout bricht die AttributeGraph-Abhängigkeit
            // zwischen dem inaktiven Kind und dem äußeren ZStack. Bei isActive=false wird
            // sizeThatFits() des Kindes NICHT aufgerufen → kein Layout-Loop bei Animationen.
            if chatLoaded {
                FrozenSectionLayout(isActive: selectedSection == .chat) {
                    ChatView()
                        .opacity(selectedSection == .chat ? 1 : 0)
                        .allowsHitTesting(selectedSection == .chat)
                        .accessibilityHidden(selectedSection != .chat)
                }
            }
            if filesLoaded {
                FrozenSectionLayout(isActive: selectedSection == .files) {
                    FileExplorerView()
                        .opacity(selectedSection == .files ? 1 : 0)
                        .allowsHitTesting(selectedSection == .files)
                        .accessibilityHidden(selectedSection != .files)
                }
            }
            if codeReviewLoaded {
                FrozenSectionLayout(isActive: selectedSection == .codeReview) {
                    CodeReviewView()
                        .opacity(selectedSection == .codeReview ? 1 : 0)
                        .allowsHitTesting(selectedSection == .codeReview)
                        .accessibilityHidden(selectedSection != .codeReview)
                }
            }
            if linearLoaded {
                FrozenSectionLayout(isActive: selectedSection == .linear) {
                    LinearView()
                        .opacity(selectedSection == .linear ? 1 : 0)
                        .allowsHitTesting(selectedSection == .linear)
                        .accessibilityHidden(selectedSection != .linear)
                }
            }

            // Alle anderen Sections werden normal gerendert
            switch selectedSection {
            case .home:       HomeView(selectedSection: $selectedSection)
            case .chat:       EmptyView()
            case .files:      EmptyView()
            case .codeReview: EmptyView()
            case .linear:     EmptyView()
            case .dashboard:  DashboardView()
            case .history:    HistoryView()
            case .agents:     AgentsView()
            case .mcp:        MCPView()
            case .notes:      NotesView(lockedType: .note)
            case .tasks:      NotesView(lockedType: .task)
            case .settings:   SettingsFormView().padding(20)
            }
        }
        .onChange(of: selectedSection) { _, section in
            if section == .chat       { chatLoaded       = true }
            if section == .files      { filesLoaded      = true }
            if section == .codeReview { codeReviewLoaded = true }
            if section == .linear {
                linearLoaded = true
                NotificationCenter.default.post(name: .linearViewBecameVisible, object: nil)
            }
        }
    }
}
