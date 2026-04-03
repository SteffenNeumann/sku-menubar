import SwiftUI
import AppKit

/// Configures the host NSWindow for a seamless frameless look.
/// Uses a persistent Coordinator with KVO observers so SwiftUI's
/// NavigationSplitView cannot re-inject a visible title after we clear it.
struct WindowConfigurator: NSViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        context.coordinator.attach(to: window)
    }

    // MARK: - Coordinator (persistent KVO owner)

    class Coordinator: NSObject {
        private var titleObs: NSKeyValueObservation?
        private var visObs:   NSKeyValueObservation?
        private var attached  = false

        func attach(to window: NSWindow) {
            Self.style(window)
            guard !attached else { return }
            attached = true

            // Watch title — SwiftUI NavigationSplitView may set it after we clear it.
            titleObs = window.observe(\.title, options: [.new]) { win, _ in
                guard win.title != "" else { return }
                DispatchQueue.main.async { win.title = "" }
            }
            // Watch titleVisibility — NavigationSplitView resets it to .visible.
            visObs = window.observe(\.titleVisibility, options: [.new]) { win, _ in
                guard win.titleVisibility != .hidden else { return }
                DispatchQueue.main.async { win.titleVisibility = .hidden }
            }
        }

        static func style(_ window: NSWindow) {
            guard window.styleMask.contains(.titled) else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility            = .hidden
            window.titlebarSeparatorStyle     = .none
            window.title                      = ""
            window.styleMask.insert(.fullSizeContentView)
            window.minSize = NSSize(width: 900, height: 600)
        }

        deinit { titleObs = nil; visObs = nil }
    }
}
