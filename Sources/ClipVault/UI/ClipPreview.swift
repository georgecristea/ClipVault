import AppKit
import MacUtilityKit
import SwiftUI

/// Fuller rendering of a clip than the row preview, shown in the floating side panel.
enum ClipPreview {
    case text(String)
    case image(NSImage)
    case files([String])
    case empty

    static func make(item: ClipboardItem, data: Data) -> ClipPreview {
        switch item.kind {
        case .text:
            let full = String(decoding: data, as: UTF8.self)
            return .text(String(full.prefix(4000)))
        case .image:
            return NSImage(data: data).map(ClipPreview.image) ?? .empty
        case .files:
            let paths = (try? JSONDecoder().decode([String].self, from: data)) ?? []
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

/// Resolves the hosting NSWindow of a SwiftUI view (so the preview can position itself
/// relative to the popover window).
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(view.window) }
    }
}

/// Drives the shared `MUKPreviewPanel` for the currently selected clip. Loads payloads
/// asynchronously, caches them by id, and shows the panel to the left of the popover window.
@MainActor
final class ClipPreviewPresenter: ObservableObject {
    private let panel = MUKPreviewPanel()
    private var loadTask: Task<Void, Never>?
    private var cache: [String: ClipPreview] = [:]
    weak var appState: AppState?

    func update(item: ClipboardItem?, window: NSWindow?) {
        loadTask?.cancel()
        guard let item, let window else { panel.hide(); return }

        if let cached = cache[item.id] {
            present(cached, window: window)
            return
        }

        loadTask = Task { [weak self] in
            guard let self, let data = await self.appState?.payloadData(for: item) else { return }
            if Task.isCancelled { return }
            let preview = ClipPreview.make(item: item, data: data)
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
        panel.show(size: ClipPreviewView.size, relativeTo: window.frame, edge: .minX) {
            ClipPreviewView(preview: preview)
        }
    }
}
