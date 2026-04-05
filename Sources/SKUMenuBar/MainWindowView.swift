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
            // ChatView und FileExplorerView bleiben immer im View-Baum (State-Erhalt)
            ChatView()
                .opacity(selectedSection == .chat ? 1 : 0)
                .allowsHitTesting(selectedSection == .chat)
                .accessibilityHidden(selectedSection != .chat)

            FileExplorerView()
                .opacity(selectedSection == .files ? 1 : 0)
                .allowsHitTesting(selectedSection == .files)
                .accessibilityHidden(selectedSection != .files)

            // Alle anderen Sections werden normal gerendert
            switch selectedSection {
            case .chat:       EmptyView()
            case .files:      EmptyView()
            case .dashboard:  DashboardView()
            case .history:    HistoryView()
            case .agents:     AgentsView()
            case .mcp:        MCPView()
            case .codeReview: CodeReviewView()
            case .notes:      NotesView(lockedType: .note)
            case .tasks:      NotesView(lockedType: .task)
            case .settings:   SettingsFormView().padding(20)
            }
        }
    }
}
