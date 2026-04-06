import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedSection: AppSection = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    // Lazy flags — heavy views are only instantiated when first visited
    @State private var chatLoaded       = false
    @State private var filesLoaded      = false
    @State private var codeReviewLoaded = false

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
        .onChange(of: state.hideSidebar) { _, hidden in
            withAnimation { columnVisibility = hidden ? .detailOnly : .all }
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
            }
            if filesLoaded {
                FileExplorerView()
                    .opacity(selectedSection == .files ? 1 : 0)
                    .allowsHitTesting(selectedSection == .files)
                    .accessibilityHidden(selectedSection != .files)
            }
            if codeReviewLoaded {
                CodeReviewView()
                    .opacity(selectedSection == .codeReview ? 1 : 0)
                    .allowsHitTesting(selectedSection == .codeReview)
                    .accessibilityHidden(selectedSection != .codeReview)
            }

            // Alle anderen Sections werden normal gerendert
            switch selectedSection {
            case .home:       HomeView(selectedSection: $selectedSection)
            case .chat:       EmptyView()
            case .files:      EmptyView()
            case .codeReview: EmptyView()
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
        }
    }
}
