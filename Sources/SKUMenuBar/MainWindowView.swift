import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedSection: AppSection = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
            .ignoresSafeArea(.all, edges: .top)
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
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(WindowConfigurator().frame(width: 0, height: 0))
    }

    @ViewBuilder
    private var detailView: some View {
        ZStack {
            // ChatView bleibt immer im View-Baum, damit Tabs & Nachrichten erhalten bleiben
            ChatView()
                .opacity(selectedSection == .chat ? 1 : 0)
                .allowsHitTesting(selectedSection == .chat)
                .accessibilityHidden(selectedSection != .chat)

            // Alle anderen Sections werden normal gerendert
            switch selectedSection {
            case .chat:       EmptyView()
            case .dashboard:  DashboardView()
            case .history:    HistoryView()
            case .agents:     AgentsView()
            case .mcp:        MCPView()
            case .codeReview: CodeReviewView()
            case .files:      FileExplorerView()
            case .notes:      NotesView(lockedType: .note)
            case .tasks:      NotesView(lockedType: .task)
            case .settings:   SettingsFormView().padding(20)
            }
        }
    }
}
