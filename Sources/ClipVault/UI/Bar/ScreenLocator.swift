import AppKit
import ApplicationServices

/// Finds the screen the user is working on.
enum ScreenLocator {
    /// The screen holding the focused window of `app` (read through Accessibility, when
    /// granted), else the screen under the mouse pointer, else the main screen.
    @MainActor
    static func workingScreen(for app: NSRunningApplication?) -> NSScreen {
        if let app, AXIsProcessTrusted(), let rect = focusedWindowFrame(pid: app.processIdentifier) {
            let center = CGPoint(x: rect.midX, y: rect.midY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return screen }
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The focused window's frame in AppKit coordinates (origin at the bottom-left).
    @MainActor
    private static func focusedWindowFrame(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return nil }
        let window = windowRef as! AXUIElement // swiftlint:disable:this force_cast
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &position), // swiftlint:disable:this force_cast
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil } // swiftlint:disable:this force_cast
        // Accessibility uses a top-left origin relative to the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: position.x, y: primaryHeight - position.y - size.height, width: size.width, height: size.height)
    }
}
