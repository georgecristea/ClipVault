import AppKit
import MacUtilityKit
import SwiftUI

/// Screens of the settings window.
enum SettingsScreen {
    case settings
    case about
    case exclusions
}

/// The app's shared state and the actions on clips. The bar and the settings window both go
/// through it.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var lastMessage: MUKStatusMessage?
    @Published var settingsScreen: SettingsScreen = .settings

    let settings: AppSettings
    let launchAtLoginManager: MUKLaunchAtLoginManager
    let store: ClipStore
    /// Called after the history changes (a new copy, a deletion, a pin…).
    var onHistoryChanged: (() -> Void)?

    private var monitor: ClipboardMonitor?

    init(store: ClipStore, settings: AppSettings = AppSettings()) {
        self.store = store
        self.settings = settings
        self.launchAtLoginManager = MUKLaunchAtLoginManager(label: "com.georgecristea.ClipVault")
    }

    func start() {
        monitor = ClipboardMonitor(store: store, settings: settings) { [weak self] in
            self?.onHistoryChanged?()
        }
        monitor?.start()
        cleanupExpired()
    }

    func stop() {
        monitor?.stop()
    }

    // MARK: - Clips

    /// Puts the clips on the clipboard (tagged so they are not captured again) and moves them to
    /// the front of history.
    func writeToClipboard(_ items: [ClipboardItem], plainText: Bool) async -> Bool {
        do {
            var sources: [(kind: ClipboardKind, items: [PasteboardItemData])] = []
            for item in items { sources.append((item.kind, try await store.payloadItems(for: item))) }
            PasteboardWriter.write(PasteboardWriter.plan(sources, plainText: plainText || settings.alwaysPlainText), to: .general)
            try await store.touch(items.map(\.id))
            return true
        } catch {
            showMessage("Could not copy: \(error.localizedDescription)", tone: .error)
            return false
        }
    }

    func delete(_ items: [ClipboardItem]) async {
        await perform("delete") { try await self.store.delete(items.map(\.id)) }
    }

    func pin(_ items: [ClipboardItem], to pinboardID: Int64?) async {
        await perform("update the pinboard") { try await self.store.pin(items.map(\.id), to: pinboardID) }
    }

    /// Pins to the "Pinned" pinboard (created when missing), or unpins when all are pinned.
    func togglePinned(_ items: [ClipboardItem]) async {
        guard !items.isEmpty else { return }
        if items.allSatisfy(\.pinned) {
            await pin(items, to: nil)
            return
        }
        await perform("pin") {
            let boards = try await self.store.pinboards()
            var board = boards.first { $0.name == "Pinned" }
            if board == nil { board = try await self.store.createPinboard(name: "Pinned") }
            try await self.store.pin(items.map(\.id), to: board!.id)
        }
    }

    func createPinboard(name: String, pinning items: [ClipboardItem]) async {
        await perform("create the pinboard") {
            let board = try await self.store.createPinboard(name: name)
            if !items.isEmpty { try await self.store.pin(items.map(\.id), to: board.id) }
        }
    }

    func renamePinboard(_ board: Pinboard, to name: String) async {
        await perform("rename the pinboard") { try await self.store.renamePinboard(id: board.id, name: name) }
    }

    func deletePinboard(_ board: Pinboard) async {
        await perform("delete the pinboard") { try await self.store.deletePinboard(id: board.id) }
    }

    func setTitle(_ title: String?, for item: ClipboardItem) async {
        await perform("rename") { try await self.store.setTitle(title, for: item.id) }
    }

    @discardableResult
    func eraseHistory() async -> Int {
        var erased = 0
        await perform("erase the history") { erased = try await self.store.eraseHistory() }
        return erased
    }

    // MARK: - Settings actions

    /// How many clips a retention change to `days`/`keepForever` would delete.
    func clipsAffected(days: Int, keepForever: Bool) async -> Int {
        guard let cutoff = RetentionPolicy.cutoff(days: days, keepForever: keepForever, now: Date()) else { return 0 }
        return (try? await store.countItems(olderThan: cutoff)) ?? 0
    }

    func updateRetention(days: Int, keepForever: Bool) {
        settings.setRetention(days: days, keepForever: keepForever)
        cleanupExpired()
    }

    func pause(until date: Date?) {
        settings.pause(until: date)
        onHistoryChanged?()
    }

    /// Pauses capture until resumed, or resumes it.
    func setCapturePaused(_ paused: Bool) {
        pause(until: paused ? .distantFuture : nil)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func cleanupExpired() {
        guard let expirationDate = settings.expirationDate else { return }
        Task { [weak self] in
            await self?.perform("clean old items") { _ = try await self?.store.deleteItems(olderThan: expirationDate) }
        }
    }

    private func perform(_ what: String, _ action: @escaping () async throws -> Void) async {
        do {
            try await action()
            onHistoryChanged?()
        } catch {
            showMessage("Could not \(what): \(error.localizedDescription)", tone: .error)
        }
    }

    func showMessage(_ text: String, tone: MUKStatusMessage.Tone = .neutral) {
        lastMessage = MUKStatusMessage(text, tone: tone)
    }
}
