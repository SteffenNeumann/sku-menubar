import SwiftUI

@main
struct SKUMenuBarApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(state)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: state.isLoading
                    ? "arrow.clockwise"
                    : state.errorMsg != nil
                        ? "exclamationmark.circle.fill"
                        : "eurosign.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(state.errorMsg != nil ? .red : .primary)

                if state.todayCost > 0.005 {
                    Text(String(format: "€%.2f", state.todayCost))
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
