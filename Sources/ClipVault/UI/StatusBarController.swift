import AppKit
import MacUtilityKit

/// The menu-bar icon and its menu: show the bar, pause, settings, about, quit.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let appState: AppState
    private let showBar: () -> Void
    private let showSettings: (SettingsScreen) -> Void
    private var handlers: [MenuAction] = []

    init(appState: AppState, showBar: @escaping () -> Void, showSettings: @escaping (SettingsScreen) -> Void) {
        self.appState = appState
        self.showBar = showBar
        self.showSettings = showSettings
        super.init()
        statusItem.autosaveName = "ClipVault"
        statusItem.isVisible = true
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
    }

    /// Refreshes the icon (paused or not).
    func updateIcon() {
        statusItem.button?.image = Self.statusImage(paused: appState.settings.isCapturePaused)
    }

    /// The ClipVault clipboard glyph, with a small pause badge while capture is paused, so the
    /// icon stays recognisable in both states.
    static func statusImage(paused: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let base = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage(size: NSSize(width: 18, height: 18))
        guard paused else {
            base.isTemplate = true
            base.accessibilityDescription = "ClipVault"
            return base
        }
        let badgeConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        let badge = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(badgeConfig)
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            if let badge {
                let size = badge.size
                let frame = NSRect(x: rect.maxX - size.width, y: rect.minY, width: size.width, height: size.height)
                // Clear a ring around the badge so it reads against the glyph.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: frame.insetBy(dx: -1, dy: -1)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                badge.draw(in: frame)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "ClipVault (capture paused)"
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        handlers.removeAll()
        let settings = appState.settings

        let show = item("Show Clipboard") { [weak self] in self?.showBar() }
        if let keyCode = settings.shortcut.keyCode, let key = MUKKeyboardLayout.character(for: CGKeyCode(keyCode)) {
            show.keyEquivalent = key
            show.keyEquivalentModifierMask = Self.flags(settings.shortcut.modifiers)
        }
        menu.addItem(show)
        menu.addItem(.separator())

        if settings.isCapturePaused {
            let until = settings.pausedUntil.flatMap { $0 == .distantFuture ? nil : $0 }
            let title = until.map { "Resume Capture (paused until \($0.formatted(date: .omitted, time: .shortened)))" } ?? "Resume Capture"
            menu.addItem(item(title) { [weak self] in self?.pause(until: nil) })
        } else {
            let pause = NSMenuItem(title: "Pause Capture", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for (title, minutes) in [("For 15 Minutes", 15.0), ("For 1 Hour", 60.0), ("For 8 Hours", 480.0)] {
                sub.addItem(item(title) { [weak self] in self?.pause(until: Date().addingTimeInterval(minutes * 60)) })
            }
            sub.addItem(item("Until Resumed") { [weak self] in self?.pause(until: .distantFuture) })
            pause.submenu = sub
            menu.addItem(pause)
        }
        menu.addItem(.separator())
        let settingsItem = item("Settings…") { [weak self] in self?.showSettings(.settings) }
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        menu.addItem(item("About ClipVault") { [weak self] in self?.showSettings(.about) })
        menu.addItem(.separator())
        let quit = item("Quit ClipVault") { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func pause(until date: Date?) {
        appState.pause(until: date)
        updateIcon()
        if let date, date != .distantFuture {
            DispatchQueue.main.asyncAfter(deadline: .now() + date.timeIntervalSinceNow + 1) { [weak self] in self?.updateIcon() }
        }
    }

    private func item(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        handlers.append(action)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        item.target = action
        return item
    }

    private static func flags(_ modifiers: MUKHotkey.Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }
}

private final class MenuAction: NSObject {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run() { handler() }
}
