import AppKit
import MacUtilityKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let appState: AppState
    private var outsideClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        // We manage dismissal ourselves (outside-click + app-resign). .transient would
        // auto-dismiss whenever the preview panel orders in or focus shifts on navigation,
        // which made the gear button "close" the popover instead of opening Settings.
        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: MUKTheme.popoverWidth, height: MUKTheme.popoverHeight)
        popover.contentViewController = NSHostingController(rootView: MainPopoverView(appState: appState))
        popover.delegate = self

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipVault")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    @objc func togglePopover(_ sender: AnyObject? = nil) {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func closePopover() {
        guard popover.isShown else { return }
        appState.preview.hide() // hide the preview at the same instant, not after the popover closes
        popover.performClose(nil)
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        appState.popoverScreen = .history
        appState.isPopoverOpen = true
        appState.reload()

        // An LSUIElement app must activate to receive key events and outside clicks.
        // activate(ignoringOtherApps:) is deprecated and ignored on macOS 26, which left the popover
        // inactive with dead header buttons; the status-item click is user interaction, so the
        // cooperative activate() succeeds.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        let popoverWindow = popover.contentViewController?.view.window
        popoverWindow?.makeKeyAndOrderFront(nil)
        // AppKit auto-focuses the first text field (search) as the window's initial first
        // responder, putting it in edit mode — which "eats" the first click on header buttons.
        // Clear it so a single click on the gear/pause/quit works; the search field still
        // focuses normally when the user clicks it.
        popoverWindow?.makeFirstResponder(nil)

        // Close on an outside click...
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
        // ...and whenever ClipVault stops being the active app (clicking another app, ⌘-Tab, etc.).
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main)
        { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
    }

    private func teardownMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        appState.isPopoverOpen = false
        teardownMonitor()
        appState.preview.hide()
        // Return focus to whatever the user was working in (so they can paste).
        previousApp?.activate()
    }
}
