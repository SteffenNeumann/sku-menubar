import SwiftUI

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
            // Schwere Views erst beim ersten Besuch in den Baum aufnehmen (Lazy Init)
            if chatLoaded {
                ChatView()
                    .opacity(selectedSection == .chat ? 1 : 0)
                    .allowsHitTesting(selectedSection == .chat)
                    .accessibilityHidden(selectedSection != .chat)
                    // frame(0,0) verhindert ZStack-Layout-Messung der schweren View
                    // wenn sie nicht aktiv ist (Fix: Layout-Loop beim Panel-Switch).
                    .frame(
                        width:  selectedSection == .chat ? nil : 0,
                        height: selectedSection == .chat ? nil : 0
                    )
                    .clipped()
            }
            if filesLoaded {
                FileExplorerView()
                    .opacity(selectedSection == .files ? 1 : 0)
                    .allowsHitTesting(selectedSection == .files)
                    .accessibilityHidden(selectedSection != .files)
                    .frame(
                        width:  selectedSection == .files ? nil : 0,
                        height: selectedSection == .files ? nil : 0
                    )
                    .clipped()
            }
            if codeReviewLoaded {
                CodeReviewView()
                    .opacity(selectedSection == .codeReview ? 1 : 0)
                    .allowsHitTesting(selectedSection == .codeReview)
                    .accessibilityHidden(selectedSection != .codeReview)
                    .frame(
                        width:  selectedSection == .codeReview ? nil : 0,
                        height: selectedSection == .codeReview ? nil : 0
                    )
                    .clipped()
            }
            if linearLoaded {
                LinearView()
                    .opacity(selectedSection == .linear ? 1 : 0)
                    .allowsHitTesting(selectedSection == .linear)
                    .accessibilityHidden(selectedSection != .linear)
                    .frame(
                        width:  selectedSection == .linear ? nil : 0,
                        height: selectedSection == .linear ? nil : 0
                    )
                    .clipped()
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
            if section == .linear     { linearLoaded     = true }
        }
    }
}
