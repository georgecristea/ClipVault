import AppKit
import MacUtilityKit
import SwiftUI

/// `ClipVault --demo` runs on a throwaway history filled with sample clips and never reads the real
/// clipboard. Add `--snapshot out.png` to render the bar offscreen to a PNG and quit — this is how
/// the README screenshot is made.
enum DemoMode {
    static var isEnabled: Bool { CommandLine.arguments.contains("--demo") }

    static var snapshotPath: String? {
        guard let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
              index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    /// Settings that never touch the real preferences.
    static let defaults = UserDefaults(suiteName: "com.georgecristea.ClipVault.demo-\(UUID().uuidString)")!

    /// A fresh store in a temporary folder, seeded oldest-first so the newest sample is on top.
    static func makeStore() async throws -> SQLiteClipStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipVault-demo-\(UUID().uuidString)", isDirectory: true)
        let store = try SQLiteClipStore(rootDirectory: root)

        let minute: TimeInterval = 60
        let samples: [(PasteboardItemData, String?, TimeInterval)] = [
            (text("Meeting moved to Thursday 14:00. Same room, I'll bring the slides."), "com.apple.MobileSMS", 3 * 24 * 60 * minute),
            (file("/Users/demo/Documents/Roadmap 2027.pdf"), "com.apple.finder", 26 * 60 * minute),
            (text("#2E8CF2"), "com.figma.Desktop", 9 * 60 * minute),
            (text("brew install --cask ghostty"), "com.apple.Terminal", 5 * 60 * minute),
            (image(), "com.apple.Preview", 2 * 60 * minute),
            (text("let store = try SQLiteClipStore()\nlet items = try await store.fetchItems(limit: 250)"), "com.apple.dt.Xcode", 40 * minute),
            (text("Tracking number: 1Z 999 AA1 01 2345 6784"), "com.apple.mail", 12 * minute),
            (text("https://github.com/georgecristea/ClipVault"), "com.apple.Safari", 2 * minute),
        ]
        for (item, source, age) in samples {
            guard let capture = ClipboardClassifier.capture(from: PasteboardSnapshot(items: [item], types: Set(item.map(\.type)))) else { continue }
            try await store.save(capture, sourceBundleID: source, at: Date().addingTimeInterval(-age))
        }
        let board = try await store.createPinboard(name: "Snippets")
        if let newest = try await store.fetchItems(limit: 1).first {
            try await store.pin([newest.id], to: board.id)
        }
        return store
    }

    /// Renders the bar offscreen once the history has loaded, writes a PNG, and quits.
    @MainActor
    static func writeSnapshot(of bar: BarController, to path: String) {
        bar.reload(resetCursor: true)
        let images = CardImageCache()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let view = NSHostingView(rootView: BarView(model: bar.model, settings: AppSettings(defaults: defaults), images: images,
                                                       actions: .preview))
            images.store = bar.storeForSnapshot
            let frame = NSRect(x: 0, y: 0, width: 1400, height: BarController.height)
            view.frame = frame
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                view.layoutSubtreeIfNeeded()
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Sample clips

    private static func text(_ string: String) -> PasteboardItemData {
        [PasteboardRepresentation(type: ClipboardClassifier.plainText, data: Data(string.utf8))]
    }

    private static func file(_ path: String) -> PasteboardItemData {
        [PasteboardRepresentation(type: ClipboardClassifier.fileURL, data: URL(fileURLWithPath: path).dataRepresentation)]
    }

    private static func image() -> PasteboardItemData {
        let size = NSSize(width: 1200, height: 800)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.18, green: 0.55, blue: 0.95, alpha: 1),
                                NSColor(red: 0.55, green: 0.35, blue: 0.95, alpha: 1)])?
                .draw(in: rect, angle: 35)
            let config = NSImage.SymbolConfiguration(pointSize: 260, weight: .regular)
                .applying(.init(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: "mountain.2.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let origin = NSPoint(x: (rect.width - symbol.size.width) / 2, y: (rect.height - symbol.size.height) / 2)
                symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 0.9)
            }
            return true
        }
        return [PasteboardRepresentation(type: "public.png", data: image.clipVaultPNGData ?? Data())]
    }
}

extension BarActions {
    /// Actions that do nothing, for rendering the bar offscreen.
    static let preview = BarActions(paste: { _, _ in }, copy: { _ in }, delete: { _ in }, pin: { _, _ in },
                                    newPinboard: { _ in }, rename: { _ in }, renamePinboard: { _ in },
                                    deletePinboard: { _ in }, selectTab: { _ in }, resumeCapture: {}, openSettings: {})
}
