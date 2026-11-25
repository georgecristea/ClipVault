import AppKit

@MainActor
final class ClipboardMonitor {
    private let store: ClipStore
    private let settings: AppSettings
    private let onChange: () -> Void
    private var timer: Timer?
    private var lastChangeCount: Int

    static let maxPayloadBytes = 100 * 1024 * 1024

    init(store: ClipStore, settings: AppSettings, onChange: @escaping () -> Void) {
        self.store = store
        self.settings = settings
        self.onChange = onChange
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        stop()
        let newTimer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        timer = newTimer
        RunLoop.main.add(newTimer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard !settings.isCapturePaused else { return }

        let snapshot = PasteboardSnapshot.read(pasteboard, maxBytes: Self.maxPayloadBytes)
        guard !ClipboardClassifier.shouldIgnore(snapshot) else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let excluded = Set(settings.excludedBundleIDs)
        if [frontmost, snapshot.declaredSource].contains(where: { $0.map(excluded.contains) ?? false }) { return }
        guard let capture = ClipboardClassifier.capture(from: snapshot) else { return }
        let source = snapshot.declaredSource ?? frontmost

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.store.save(capture, sourceBundleID: source, at: Date())
                if let expirationDate = self.settings.expirationDate {
                    try await self.store.deleteItems(olderThan: expirationDate)
                }
            } catch {}
            self.onChange()
        }
    }
}
