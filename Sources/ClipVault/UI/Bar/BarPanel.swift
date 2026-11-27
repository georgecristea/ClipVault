import AppKit

/// The window that holds the bar. A non-activating panel: it takes keyboard input while the
/// app the user was working in stays active, so a synthesized ⌘V goes back to that app.
final class BarPanel: NSPanel {
    /// Gets every key press while the panel is key. Return true if handled.
    var keyHandler: ((NSEvent) -> Bool)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true
        // Set after `isFloatingPanel`, which resets the level to `.floating` (below the Dock).
        // The main-menu level sits above the Dock, so the bar covers it.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)))
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}
