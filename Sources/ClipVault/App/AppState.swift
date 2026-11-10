import AppKit
import MacUtilityKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    @Published private(set) var lastMessage: MUKStatusMessage?
    @Published var popoverScreen: PopoverScreen = .history

    let settings: AppSettings
    let launchAtLoginManager: MUKLaunchAtLoginManager
    let preview = ClipPreviewPresenter()

    /// True only while the popover is on screen. The popover's SwiftUI view stays alive when
    /// closed, so item changes (e.g. a new copy) still fire .onChange — without this gate the
    /// preview would pop up with no popover open.
    var isPopoverOpen = false

    /// Wired by AppDelegate to the status-bar popover.
    var requestClosePopover: (() -> Void)?

    private let store: ClipStore
    private var monitor: ClipboardMonitor?

    init(store: ClipStore) {
        self.store = store
        self.settings = AppSettings()
        self.launchAtLoginManager = MUKLaunchAtLoginManager(label: "com.georgecristea.ClipVault")
        preview.appState = self
    }

    func start() {
        monitor = ClipboardMonitor(store: store, settings: settings) { [weak self] in
            self?.reload()
        }
        monitor?.start()
        cleanupExpired()
        reload()
    }

    func stop() {
        monitor?.stop()
    }

    func reload(query: String? = nil) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let fetched = try await store.fetchItems(limit: 250, query: query)
                self.items = fetched
                self.loadThumbnails(for: fetched)
            } catch {
                self.showMessage("Could not load history: \(error.localizedDescription)", tone: .error)
            }
        }
    }

    /// Selecting a clip copies it to the clipboard and dismisses the popover; the user pastes
    /// it themselves with ⌘V. (ClipVault requires no Accessibility permission.)
    func select(_ item: ClipboardItem) {
        Task { [weak self] in
            guard let self, let monitor = self.monitor else { return }
            do {
                try await monitor.restore(item)
                self.requestClosePopover?()
            } catch {
                self.showMessage("Could not copy item: \(error.localizedDescription)", tone: .error)
            }
        }
    }

    func setPinned(_ pinned: Bool, for item: ClipboardItem) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await store.setPinned(pinned, for: item)
                self.reload()
            } catch {
                self.showMessage("Could not update pin: \(error.localizedDescription)", tone: .error)
            }
        }
    }

    func delete(_ item: ClipboardItem) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await store.delete(item)
                self.thumbnails[item.id] = nil
                self.reload()
            } catch {
                self.showMessage("Could not delete item: \(error.localizedDescription)", tone: .error)
            }
        }
    }

    func updateRetention(days: Int, keepForever: Bool) {
        settings.setRetention(days: days, keepForever: keepForever)
        cleanupExpired()
        reload()
    }

    func setCapturePaused(_ paused: Bool) {
        settings.setCapturePaused(paused)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func thumbnail(for item: ClipboardItem) -> NSImage? {
        thumbnails[item.id]
    }

    func payloadData(for item: ClipboardItem) async -> Data? {
        try? await store.payloadData(for: item)
    }

    private func loadThumbnails(for items: [ClipboardItem]) {
        for item in items where item.kind == .image && thumbnails[item.id] == nil {
            Task { [weak self] in
                guard let self else { return }
                if let data = try? await store.payloadData(for: item),
                   let image = NSImage(data: data) {
                    self.thumbnails[item.id] = image
                }
            }
        }
    }

    private func cleanupExpired() {
        guard let expirationDate = settings.expirationDate else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await store.deleteItems(olderThan: expirationDate)
            } catch {
                self.showMessage("Could not clean old items: \(error.localizedDescription)", tone: .error)
            }
        }
    }

    private func showMessage(_ text: String, tone: MUKStatusMessage.Tone = .neutral) {
        lastMessage = MUKStatusMessage(text, tone: tone)
    }
}
