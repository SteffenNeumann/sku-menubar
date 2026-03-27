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
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: state.pendingChatSession) {
            if state.pendingChatSession != nil {
                columnVisibility = .all
                selectedSection = .chat
            }
        }
        // Keep sidebar toggle so users can show sidebar again after collapsing
        .toolbarBackground(.hidden, for: .windowToolbar)
        // Apply frameless window config (transparent title bar + fullSizeContentView)
        .background(WindowConfigurator().frame(width: 0, height: 0))
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .dashboard:  DashboardView()
        case .chat:       ChatView()
        case .history:    HistoryView()
        case .agents:     AgentsView()
        case .mcp:        MCPView()
        case .codeReview: CodeReviewView()
        case .settings:   SettingsFormView().padding(20)
        }
    }
}
