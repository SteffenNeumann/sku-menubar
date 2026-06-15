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
//
// FIX 13b — Proposal-Cache:
// VStack ruft sizeThatFits pro Layout-Pass bis zu 3× auf (prioritize, resize, placeChildren1).
// Bei gleicher Proposal (z.B. resize == placeChildren1) liefert der Cache sofort zurück.
// updateCache() setzt den Cache zurück wenn SwiftUI neue Subviews meldet (neue Nachrichten).
struct FrozenSectionLayout: Layout {
    var isActive: Bool

    struct SizeCache {
        var isSet = false
        var w: CGFloat? = nil
        var h: CGFloat? = nil
        var size: CGSize = .zero
    }
    typealias Cache = SizeCache

    func makeCache(subviews: Subviews) -> SizeCache { SizeCache() }

    func updateCache(_ cache: inout SizeCache, subviews: Subviews) {
        // Zurücksetzen wenn sich Subviews ändern (neue Nachrichten → andere Größe möglich).
        cache = SizeCache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout SizeCache) -> CGSize {
        // KRITISCH: bei isActive=false keine Kind-Messung → O(1) Layout-Cost statt O(N×Messages).
        // Das unterbricht die AttributeGraph-Abhängigkeit zwischen dem teuren Kind und dem
        // umgebenden ZStack, sodass 60fps-Animationen keinen Layout-Loop auslösen.
        guard isActive, let child = subviews.first else { return .zero }

        // Cache-Hit: gleiche Proposal wie letzter Aufruf in diesem Layout-Pass → sofort zurück.
        // Schützt vor dem 3× Messen durch VStack (prioritize + resize + placeChildren1).
        if cache.isSet && proposal.width == cache.w && proposal.height == cache.h {
            return cache.size
        }
        let size = child.sizeThatFits(proposal)
        cache.isSet = true
        cache.w = proposal.width
        cache.h = proposal.height
        cache.size = size
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout SizeCache) {
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
    // Chat wird einmalig „scharf geschaltet" und bleibt dann persistent gemountet
    // (Streaming + Per-Tab-State). Files/CodeReview/Linear brauchen keine Lade-Flags
    // mehr — sie werden nur noch aktiv gemountet (siehe detailView, SCHRITT 0).
    @State private var chatLoaded = false

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
            // SCHRITT 0 (Struktur-Hang-Fix): NUR Chat bleibt persistent gemountet.
            // Grund: Chat trägt das laufende Streaming + schweren Per-Tab-State, der bei
            // Section-Wechsel NICHT verloren gehen darf (sonst bricht eine laufende Antwort ab).
            // FrozenSectionLayout unterdrückt die Messung, solange Chat nicht aktiv ist.
            //
            // FileExplorer/CodeReview/Linear werden NICHT mehr dauergemountet — sie hingen
            // sonst zu viert im selben ZStack und blähten jeden Layout-Pass auf (alle Sections
            // × alle Tabs). Sie wandern ins switch unten und werden nur gemountet, wenn aktiv;
            // beim Verlassen werden sie abgebaut (ihre Watcher/Timer/States werden freigegeben)
            // und laden beim nächsten Erscheinen aus ihren Services neu.
            if chatLoaded {
                FrozenSectionLayout(isActive: selectedSection == .chat) {
                    ChatView()
                        .opacity(selectedSection == .chat ? 1 : 0)
                        .allowsHitTesting(selectedSection == .chat)
                        .accessibilityHidden(selectedSection != .chat)
                }
            }

            // Nur die AKTIVE Nicht-Chat-Section wird gerendert (kein Persistenz-ZStack mehr).
            switch selectedSection {
            case .home:       HomeView(selectedSection: $selectedSection)
            case .chat:       EmptyView()   // wird oben persistent gerendert
            case .files:      FileExplorerView()
            case .codeReview: CodeReviewView()
            case .linear:     LinearView(service: state.linearService)
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
            // Chat einmalig „scharf schalten" — danach bleibt es persistent gemountet.
            if section == .chat { chatLoaded = true }
            // Hinweis: LinearView lädt jetzt via eigenem `.task` beim Frisch-Mount;
            // die frühere .linearViewBecameVisible-Benachrichtigung (für den Persistenz-Fall)
            // entfällt, weil die View bei jedem Wechsel neu erscheint.
        }
    }
}
