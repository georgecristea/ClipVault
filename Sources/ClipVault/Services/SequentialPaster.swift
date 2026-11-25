import AppKit

/// Pastes clips one ⌘V at a time. Each clip is offered lazily on the pasteboard and the next one
/// follows as soon as the target app has read the current one (or after `stepTimeout`, for apps
/// that never read). Apps that accept one image per paste, like a chat prompt in a terminal,
/// then receive every clip, in order. Nothing here touches focus.
@MainActor
final class SequentialPaster {
    private let pasteboard: NSPasteboard
    private let stepTimeout: TimeInterval
    private let pressPaste: () -> Void
    private var writer: LazyPasteboardWriter?
    /// Time for the target to finish reading the other formats of a clip it started reading.
    static let settle: TimeInterval = 0.08

    init(pasteboard: NSPasteboard = .general, stepTimeout: TimeInterval = 1.5, pressPaste: @escaping () -> Void) {
        self.pasteboard = pasteboard
        self.stepTimeout = stepTimeout
        self.pressPaste = pressPaste
    }

    func paste(_ batches: [[PasteboardItemData]], completion: @escaping () -> Void = {}) {
        guard batches.count > 1 else {
            if let only = batches.first { PasteboardWriter.write(only, to: pasteboard) }
            pressPaste()
            completion()
            return
        }
        step(batches, index: 0, completion: completion)
    }

    private func step(_ batches: [[PasteboardItemData]], index: Int, completion: @escaping () -> Void) {
        guard index < batches.count else {
            // Leave the last clip as real data: lazily offered data vanishes if ClipVault quits.
            if let last = batches.last { PasteboardWriter.write(last, to: pasteboard) }
            writer = nil
            completion()
            return
        }
        let writer = LazyPasteboardWriter()
        self.writer = writer
        let once = Once()
        let next: @MainActor @Sendable () -> Void = { [weak self] in
            guard once.fire() else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle) {
                self?.step(batches, index: index + 1, completion: completion)
            }
        }
        writer.write(batches[index], to: pasteboard, onFirstRead: {
            // Data requests normally arrive on the main thread; hop there if one ever doesn't.
            if Thread.isMainThread { MainActor.assumeIsolated { next() } } else { DispatchQueue.main.async { next() } }
        })
        pressPaste()
        DispatchQueue.main.asyncAfter(deadline: .now() + stepTimeout) { next() }
    }

    /// Main-thread only; Sendable so the read and timeout callbacks can share it.
    private final class Once: @unchecked Sendable {
        private var fired = false
        func fire() -> Bool {
            defer { fired = true }
            return !fired
        }
    }
}
