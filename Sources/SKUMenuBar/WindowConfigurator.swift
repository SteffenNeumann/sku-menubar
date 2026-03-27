import SwiftUI
import AppKit

/// Configures the host NSWindow for a seamless frameless look:
/// - Transparent title bar (inherits the sidebar's visual-effect material)
/// - Content extends behind the traffic lights via fullSizeContentView
/// - Title text hidden — identity lives in the sidebar branding
///
/// Applied as a zero-size background so it fires as soon as the window exists.
struct WindowConfigurator: NSViewRepresentable {

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Defer until the view is in a window
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            Self.style(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        Self.style(window)
    }

    // MARK: - Window styling

    static func style(_ window: NSWindow) {
        guard window.styleMask.contains(.titled) else { return }

        // 1. Transparent title bar — the sidebar blur extends into this area
        window.titlebarAppearsTransparent = true
        window.titleVisibility            = .hidden

        // 2. Content fills the entire window frame including the title bar strip
        window.styleMask.insert(.fullSizeContentView)

        // 3. Remove the toolbar so no extra strip appears above the sidebar
        //    (The sidebar toggle is handled inside our own SidebarView)
        if let toolbar = window.toolbar, toolbar.items.isEmpty {
            window.toolbar = nil
        }

        // 4. Allow minimum size
        window.minSize = NSSize(width: 900, height: 600)
    }
}
