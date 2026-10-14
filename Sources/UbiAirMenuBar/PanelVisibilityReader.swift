import AppKit
import SwiftUI

/// The hosting controller keeps its SwiftUI hierarchy alive after closing the popover.
/// Read actual NSWindow visibility so polling stops while no panel is visible.
struct PanelVisibilityReader: NSViewRepresentable {
    var onChange: (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView {
        let view = VisibilityView()
        view.onChange = onChange
        return view
    }
    func updateNSView(_ view: VisibilityView, context: Context) { view.onChange = onChange }
    static func dismantleNSView(_ view: VisibilityView, coordinator: ()) { view.stop() }

    @MainActor final class VisibilityView: NSView {
        var onChange: ((Bool) -> Void)?
        private var observation: Task<Void, Never>?
        private var previous = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            observation = Task { [weak self] in
                while !Task.isCancelled {
                    if let self {
                        let visible = self.window?.isVisible == true
                        if visible != self.previous { self.previous = visible; self.onChange?(visible) }
                    } else { break }
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { break }
                }
            }
        }
        func stop() {
            observation?.cancel()
            observation = nil
            if previous { previous = false; onChange?(false) }
        }
    }
}
