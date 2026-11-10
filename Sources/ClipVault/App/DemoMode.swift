import AppKit
import MacUtilityKit
import SwiftUI

/// `ClipVault --demo` runs on a throwaway history filled with sample clips and never reads the real
/// clipboard. Add `--snapshot out.png` to render the popover offscreen to a PNG and quit — this is
/// how the README screenshot is made.
enum DemoMode {
    static var isEnabled: Bool { CommandLine.arguments.contains("--demo") }

    static var snapshotPath: String? {
        guard let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
              index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    /// A fresh store in a temporary folder, seeded oldest-first so the newest sample is on top.
    static func makeStore() async throws -> SQLiteClipStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipVault-demo-\(UUID().uuidString)", isDirectory: true)
        let store = try SQLiteClipStore(rootDirectory: root)

        let minute: TimeInterval = 60
        let samples: [(ClipboardCapture, String?, TimeInterval)] = [
            (text("Meeting moved to Thursday 14:00. Same room, I'll bring the slides."), "com.apple.MobileSMS", 3 * 24 * 60 * minute),
            (files(["/Users/demo/Documents/Roadmap 2027.pdf"]), "com.apple.finder", 26 * 60 * minute),
            (text("brew install --cask ghostty"), "com.apple.Terminal", 5 * 60 * minute),
            (image(), "com.apple.Preview", 2 * 60 * minute),
            (text("let store = try SQLiteClipStore()\nlet items = try await store.fetchItems(limit: 250)"), "com.apple.dt.Xcode", 40 * minute),
            (text("Tracking number: 1Z 999 AA1 01 2345 6784"), "com.apple.mail", 12 * minute),
            (text("https://github.com/georgecristea/ClipVault"), "com.apple.Safari", 2 * minute),
        ]
        for (capture, source, age) in samples {
            try await store.save(capture, sourceBundleID: source, at: Date().addingTimeInterval(-age))
        }
        if let url = try await store.fetchItems(limit: 1).first {
            try await store.setPinned(true, for: url)
        }
        return store
    }

    /// Renders the popover offscreen once the history has loaded, writes a PNG, and quits.
    @MainActor
    static func writeSnapshot(of state: AppState, to path: String) {
        let view = NSHostingView(rootView: MainPopoverView(appState: state))
        let frame = NSRect(x: 0, y: 0, width: MUKTheme.popoverWidth, height: MUKTheme.popoverHeight)
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

    // MARK: - Sample clips

    private static func text(_ string: String) -> ClipboardCapture {
        let preview = string.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return ClipboardCapture(kind: .text, data: Data(string.utf8), preview: String(preview.prefix(240)), fileExtension: "txt")
    }

    private static func files(_ paths: [String]) -> ClipboardCapture {
        let data = (try? JSONEncoder().encode(paths)) ?? Data()
        let preview = paths.count == 1 ? URL(fileURLWithPath: paths[0]).lastPathComponent : "\(paths.count) files"
        return ClipboardCapture(kind: .files, data: data, preview: preview, fileExtension: "json")
    }

    private static func image() -> ClipboardCapture {
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
        let data = image.clipVaultPNGData ?? Data()
        return ClipboardCapture(kind: .image, data: data, preview: image.clipVaultDescription, fileExtension: "png")
    }
}
