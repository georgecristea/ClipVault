import AppKit
import Carbon.HIToolbox
import MacUtilityKit
import SwiftUI

/// Shows and hides the bar, handles its keys, and carries out what the user picks.
@MainActor
final class BarController {
    let model = BarModel()
    private let appState: AppState
    private let panel = BarPanel()
    private let images = CardImageCache()
    private let preview = ClipPreviewPresenter()
    /// The app that was active when the bar opened; pastes go there.
    private var targetApp: NSRunningApplication?
    private var mouseMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var loadGeneration = 0
    private var askedForAccessibility = false
    private(set) var isVisible = false
    var openSettings: () -> Void = {}

    static let height: CGFloat = 320

    /// The store, for rendering the demo snapshot.
    var storeForSnapshot: ClipStore { appState.store }

    init(appState: AppState) {
        self.appState = appState
        images.store = appState.store
        preview.store = appState.store
        let actions = BarActions(
            paste: { [weak self] in self?.paste($0, plainText: $1) },
            copy: { [weak self] in self?.copy($0) },
            delete: { [weak self] items in self?.run { await $0.appState.delete(items) } },
            pin: { [weak self] items, board in self?.run { await $0.appState.pin(items, to: board) } },
            newPinboard: { [weak self] in self?.newPinboard(pinning: $0) },
            rename: { [weak self] in self?.rename($0) },
            renamePinboard: { [weak self] in self?.renamePinboard($0) },
            deletePinboard: { [weak self] board in
                self?.run { controller in
                    await controller.appState.deletePinboard(board)
                    if controller.model.tab == .pinboard(board.id) { controller.model.tab = .history }
                }
            },
            selectTab: { [weak self] in self?.select(tab: $0) },
            resumeCapture: { [weak self] in self?.appState.setCapturePaused(false) },
            openSettings: { [weak self] in self?.hide(); self?.openSettings() })
        panel.contentView = NSHostingView(rootView: BarView(model: model, settings: appState.settings, images: images, actions: actions))
        panel.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
    }

    // MARK: - Loading

    /// Reloads the shown tab. The cursor stays where it was unless `resetCursor`.
    func reload(resetCursor: Bool = false) {
        loadGeneration += 1
        let generation = loadGeneration
        let query = model.query
        let pinboardID = model.pinboardID
        let store = appState.store
        model.beginLoading()
        Task { [weak self] in
            let boards = (try? await store.pinboards()) ?? []
            let shownBoard = pinboardID.flatMap { id in boards.contains { $0.id == id } ? id : nil }
            let items = (try? await store.fetchItems(limit: 300, query: query, pinboardID: shownBoard)) ?? []
            guard let self, generation == self.loadGeneration else { return }
            if pinboardID != nil, shownBoard == nil { self.model.tab = .history }
            self.model.apply(items: items, pinboards: boards, resetCursor: resetCursor)
            if self.preview.isVisible { self.preview.show(item: self.model.cursorItem, above: self.panel) }
        }
    }

    private func select(tab: BarTab) {
        guard model.tab != tab else { return }
        model.tab = tab
        reload(resetCursor: true)
    }

    private func setQuery(_ query: String) {
        model.query = query
        reload(resetCursor: true)
    }

    // MARK: - Showing and hiding

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard !isVisible else { return }
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { targetApp = front }
        model.query = ""
        reload(resetCursor: true)

        let screen = ScreenLocator.workingScreen(for: targetApp)
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: Self.height)
        panel.setFrame(frame.offsetBy(dx: 0, dy: -Self.height), display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        isVisible = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            Task { @MainActor in
                if pid != self?.targetApp?.processIdentifier { self?.hide() }
            }
        }
    }

    func hide(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard isVisible else { completion?(); return }
        isVisible = false
        preview.hide()
        // Give up keyboard focus before leaving the screen, so it returns to the app underneath.
        panel.resignKey()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        guard animated else {
            panel.orderOut(nil)
            completion?()
            return
        }
        let target = panel.frame.offsetBy(dx: 0, dy: -panel.frame.height)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel.orderOut(nil)
                completion?()
            }
        })
    }

    /// Called when the history changed.
    func historyChanged() {
        if isVisible { reload() }
    }

    // MARK: - Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        switch Int(event.keyCode) {
        case kVK_Escape:
            if preview.isVisible { preview.hide() } else if model.query.isEmpty { hide() } else { setQuery("") }
        case kVK_LeftArrow:
            if command { model.switchTab(by: -1); reload(resetCursor: true) } else { moveCursor(by: -1, extend: shift) }
        case kVK_RightArrow:
            if command { model.switchTab(by: 1); reload(resetCursor: true) } else { moveCursor(by: 1, extend: shift) }
        case kVK_Home:
            moveCursor(by: -model.items.count, extend: false)
        case kVK_End:
            moveCursor(by: model.items.count, extend: false)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            paste(model.actionableItems, plainText: shift)
        case kVK_Space where !command && model.query.isEmpty:
            if preview.isVisible { preview.hide() } else { preview.show(item: model.cursorItem, above: panel) }
        case kVK_Delete, kVK_ForwardDelete:
            if command {
                let items = model.actionableItems
                run { await $0.appState.delete(items) }
            } else if !model.query.isEmpty {
                setQuery(String(model.query.dropLast()))
            }
        default:
            if command, let chars = event.charactersIgnoringModifiers {
                return handleCommand(chars.lowercased(), shift: shift)
            }
            if flags.contains(.control) { return false }
            guard let chars = event.characters, !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return false }
            setQuery(model.query + chars)
        }
        return true
    }

    private func moveCursor(by delta: Int, extend: Bool) {
        model.move(by: delta, extend: extend)
        if preview.isVisible { preview.show(item: model.cursorItem, above: panel) }
    }

    private func handleCommand(_ chars: String, shift: Bool) -> Bool {
        if let digit = Int(chars), (1...9).contains(digit) {
            if let item = model.quickItem(at: digit) { paste([item], plainText: shift) }
            return true
        }
        switch chars {
        case "c": copy(model.actionableItems)
        case "a": model.selection = Set(model.items.map(\.id))
        case "p":
            let items = model.actionableItems
            run { await $0.appState.togglePinned(items) }
        case ",": hide(); openSettings()
        case "w": hide()
        default: return false
        }
        return true
    }

    // MARK: - Actions

    /// Puts the clips on the clipboard and, when allowed, pastes them into the target app.
    func paste(_ items: [ClipboardItem], plainText: Bool) {
        guard !items.isEmpty else { return }
        let target = targetApp
        Task { [weak self] in
            guard let self, await self.appState.writeToClipboard(items, plainText: plainText) else { return }
            self.hide(animated: false) {
                guard self.appState.settings.pasteIntoActiveApp else { return }
                guard AXIsProcessTrusted() else {
                    if !self.askedForAccessibility {
                        self.askedForAccessibility = true
                        AccessibilityAccess.request()
                    }
                    return
                }
                self.returnFocus(to: target)
            }
        }
    }

    /// Hands keyboard focus back to the target app, waits until it really has it, then sends ⌘V.
    /// Sending too early lands the keystroke in ClipVault itself, which beeps.
    private func returnFocus(to target: NSRunningApplication?) {
        if let target {
            // macOS 14 cooperative activation: hand activation to the target explicitly.
            NSApp.yieldActivation(to: target)
            target.activate()
        }
        if NSApp.isActive { NSApp.hide(nil) }
        let deadline = Date().addingTimeInterval(1.0)
        func attempt() {
            let ready = Self.readyToPaste(frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                          targetPID: target?.processIdentifier,
                                          clipVaultIsActive: NSApp.isActive,
                                          clipVaultHasKeyWindow: NSApp.keyWindow != nil)
            if ready {
                // A short settle so the target's own window is key, not just its app frontmost.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { PasteKeystroke.send() }
            } else if Date() < deadline {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { attempt() }
            }
            // Past the deadline the clip is still on the clipboard; the user can press ⌘V.
        }
        attempt()
    }

    /// The target app is frontmost (when known) and ClipVault holds no focus.
    nonisolated static func readyToPaste(frontmostPID: pid_t?, targetPID: pid_t?, clipVaultIsActive: Bool, clipVaultHasKeyWindow: Bool) -> Bool {
        guard !clipVaultIsActive, !clipVaultHasKeyWindow else { return false }
        guard let targetPID else { return true }
        return frontmostPID == targetPID
    }

    private func copy(_ items: [ClipboardItem]) {
        guard !items.isEmpty else { return }
        Task {
            if await appState.writeToClipboard(items, plainText: false) { hide() }
        }
    }

    private func run(_ action: @escaping (BarController) async -> Void) {
        Task { [weak self] in
            guard let self else { return }
            await action(self)
        }
    }

    private func newPinboard(pinning items: [ClipboardItem]) {
        prompt(title: "New Pinboard", message: "Name the pinboard.", initial: "") { [weak self] name in
            self?.run { await $0.appState.createPinboard(name: name, pinning: items) }
        }
    }

    private func rename(_ item: ClipboardItem) {
        prompt(title: "Rename Clip", message: "Leave empty to remove the title.", initial: item.title ?? "", allowEmpty: true) { [weak self] title in
            self?.run { await $0.appState.setTitle(title, for: item) }
        }
    }

    private func renamePinboard(_ board: Pinboard) {
        prompt(title: "Rename Pinboard", message: "", initial: board.name) { [weak self] name in
            self?.run { await $0.appState.renamePinboard(board, to: name) }
        }
    }

    /// Asks for a line of text. The bar hides while the dialog is up and comes back after.
    private func prompt(title: String, message: String, initial: String, allowEmpty: Bool = false,
                        completion: @escaping (String) -> Void) {
        let target = targetApp
        let tab = model.tab
        hide(animated: false) { [weak self] in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            let field = NSTextField(string: initial)
            field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
            alert.accessoryView = field
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            alert.window.initialFirstResponder = field
            NSApp.activate()
            let response = alert.runModal()
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if response == .alertFirstButtonReturn, allowEmpty || !text.isEmpty { completion(text) }
            target?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self?.show()
                self?.model.tab = tab
                self?.reload(resetCursor: true)
            }
        }
    }
}
