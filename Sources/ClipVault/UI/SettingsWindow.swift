import AppKit
import MacUtilityKit
import SwiftUI

/// The settings window: Settings, App Exclusions and About, in the MacUtilityKit shell.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let appState: AppState
    private let onShortcutChange: (MUKHotkey) -> Bool

    init(appState: AppState, onShortcutChange: @escaping (MUKHotkey) -> Bool) {
        self.appState = appState
        self.onShortcutChange = onShortcutChange
    }

    func show(_ screen: SettingsScreen = .settings) {
        appState.settingsScreen = screen
        if window == nil {
            let size = NSSize(width: MUKTheme.popoverWidth, height: MUKTheme.popoverHeight + 60)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "ClipVault"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsRootView(appState: appState, onShortcutChange: onShortcutChange))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsRootView: View {
    @ObservedObject var appState: AppState
    let onShortcutChange: (MUKHotkey) -> Bool

    var body: some View {
        MUKPopoverShell(message: appState.lastMessage) {
            header
        } content: {
            switch appState.settingsScreen {
            case .settings:
                SettingsView(appState: appState, onShortcutChange: onShortcutChange,
                             onShowAbout: { navigate(to: .about) }, onShowExclusions: { navigate(to: .exclusions) })
            case .about:
                AboutView()
            case .exclusions:
                ExclusionsView(appState: appState)
            }
        }
    }

    @ViewBuilder private var header: some View {
        switch appState.settingsScreen {
        case .settings:
            MUKHeader(title: "ClipVault", subtitle: "Settings", systemImage: "doc.on.clipboard") { EmptyView() }
        case .about:
            MUKBackHeader(title: "About", onBack: { navigate(to: .settings) })
        case .exclusions:
            MUKBackHeader(title: "App Exclusions", onBack: { navigate(to: .settings) })
        }
    }

    private func navigate(to screen: SettingsScreen) {
        withAnimation(.easeInOut(duration: 0.18)) { appState.settingsScreen = screen }
    }
}
