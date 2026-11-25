import AppKit
import MacUtilityKit
import SwiftUI

/// Fuller rendering of a clip than the row preview, shown in the floating side panel.
enum ClipPreview {
    case text(String)
    case image(NSImage)
    case files([String])
    case empty

    static func make(item: ClipboardItem, items: [PasteboardItemData]) -> ClipPreview {
        switch item.kind {
        case .text, .link, .color:
            return .text(String(PasteboardWriter.text(of: items).prefix(4000)))
        case .image:
            let data = items.lazy.flatMap { $0 }.first { ClipboardClassifier.imageTypes.contains($0.type) }?.data
            return data.flatMap(NSImage.init(data:)).map(ClipPreview.image) ?? .empty
        case .files:
            let paths = items.compactMap { $0.first { $0.type == ClipboardClassifier.fileURL }?.data }
                .compactMap { URL(dataRepresentation: $0, relativeTo: nil)?.path }
            return .files(paths)
        }
    }
}

struct ClipPreviewView: View {
    let preview: ClipPreview
    static let size = NSSize(width: 340, height: 380)

    var body: some View {
        content
            .frame(width: Self.size.width, height: Self.size.height)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MUKTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MUKTheme.cardRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08)))
    }

    @ViewBuilder private var content: some View {
        switch preview {
        case .text(let string):
            ScrollView {
                Text(string.isEmpty ? "(empty)" : string)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(12)
        case .files(let paths):
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(paths, id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable().frame(width: 20, height: 20)
                            Text((path as NSString).lastPathComponent)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
            }
        case .empty:
            Image(systemName: "eye.slash")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
        }
    }
}

/// Shows the full selected clip in the shared `MUKPreviewPanel`, above the bar.
@MainActor
final class ClipPreviewPresenter {
    private let panel = MUKPreviewPanel()
    private var loadTask: Task<Void, Never>?
    private var cache: [String: ClipPreview] = [:]
    var store: ClipStore?

    var isVisible: Bool { panel.isVisible }

    func show(item: ClipboardItem?, above window: NSWindow) {
        loadTask?.cancel()
        guard let item else { panel.hide(); return }
        if let cached = cache[item.id] {
            present(cached, window: window)
            return
        }
        loadTask = Task { [weak self] in
            guard let self, let store = self.store, let items = try? await store.payloadItems(for: item) else { return }
            if Task.isCancelled { return }
            let preview = ClipPreview.make(item: item, items: items)
            self.cache[item.id] = preview
            self.present(preview, window: window)
        }
    }

    func hide() {
        loadTask?.cancel()
        panel.hide()
    }

    func forget(_ id: String) { cache[id] = nil }

    private func present(_ preview: ClipPreview, window: NSWindow) {
        // MUKPreviewPanel places the panel left of the anchor, top-aligned; this anchor puts it
        // centred just above the bar.
        let size = ClipPreviewView.size
        let gap: CGFloat = 10
        let anchor = NSRect(x: window.frame.midX + size.width / 2 + gap, y: window.frame.maxY + gap,
                            width: 1, height: size.height)
        panel.show(size: size, relativeTo: anchor, edge: .minX, gap: gap, attachedTo: window) {
            ClipPreviewView(preview: preview)
        }
    }
}
