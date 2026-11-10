import AppKit

@MainActor
final class ClipboardMonitor {
    private let store: ClipStore
    private let settings: AppSettings
    private let onChange: () -> Void
    private var timer: Timer?
    private var lastChangeCount: Int

    private let maxPayloadBytes = 100 * 1024 * 1024

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

    func restore(_ item: ClipboardItem) async throws {
        let data = try await store.payloadData(for: item)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            guard let value = String(data: data, encoding: .utf8) else {
                throw ClipVaultError.invalidPayload("Text payload is not valid UTF-8.")
            }
            pasteboard.setString(value, forType: .string)

        case .image:
            if let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            } else {
                pasteboard.setData(data, forType: .png)
            }

        case .files:
            let paths = try JSONDecoder().decode([String].self, from: data)
            let urls = paths.map { NSURL(fileURLWithPath: $0) }
            pasteboard.writeObjects(urls)
        }

        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard !settings.capturePaused else { return }
        let reader = NSPasteboardReader(pasteboard: pasteboard)
        guard !ClipboardClassifier.shouldIgnore(reader) else { return }
        guard let capture = makeCapture(from: pasteboard, reader: reader) else { return }
        guard capture.data.count <= maxPayloadBytes else { return }

        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if let sourceBundleID, settings.excludedBundleIDs.contains(sourceBundleID) { return }
        let expirationDate = settings.expirationDate

        Task { [weak self] in
            guard let self else { return }
            do {
                let saved = try await self.store.save(capture, sourceBundleID: sourceBundleID)
                if saved {
                    if let expirationDate {
                        try await self.store.deleteItems(olderThan: expirationDate)
                    }
                    self.onChange()
                }
            } catch {
                self.onChange()
            }
        }
    }

    private func makeCapture(from pasteboard: NSPasteboard, reader: NSPasteboardReader) -> ClipboardCapture? {
        if let capture = ClipboardClassifier.capture(from: reader) {
            return capture
        }
        // Fallback for image formats only reachable via NSImage(pasteboard:).
        if let image = NSImage(pasteboard: pasteboard), let data = image.clipVaultPNGData {
            return ClipboardCapture(kind: .image, data: data, preview: image.clipVaultDescription, fileExtension: "png")
        }
        return nil
    }
}
