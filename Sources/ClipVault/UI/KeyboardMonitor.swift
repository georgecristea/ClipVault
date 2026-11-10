import AppKit
import SwiftUI

/// Installs an AppKit local key-down monitor for as long as it's in the view tree, routing
/// events to `handler`. Returns true from the handler to consume the event. This drives keyboard
/// navigation independent of SwiftUI focus (a focused text field's field editor would otherwise
/// swallow the first click on buttons, so we deliberately don't auto-focus anything).
struct KeyboardMonitor: NSViewRepresentable {
    var handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        context.coordinator.handler = handler
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var handler: (NSEvent) -> Bool = { _ in false }
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                (self?.handler(event) ?? false) ? nil : event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }

        deinit { remove() }
    }
}
