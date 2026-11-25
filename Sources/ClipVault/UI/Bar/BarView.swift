import AppKit
import MacUtilityKit
import SwiftUI

/// What the bar asks its controller to do.
struct BarActions {
    var paste: (_ items: [ClipboardItem], _ plainText: Bool) -> Void
    var copy: (_ items: [ClipboardItem]) -> Void
    var delete: (_ items: [ClipboardItem]) -> Void
    var pin: (_ items: [ClipboardItem], _ pinboardID: Int64?) -> Void
    var newPinboard: (_ items: [ClipboardItem]) -> Void
    var rename: (_ item: ClipboardItem) -> Void
    var renamePinboard: (_ pinboard: Pinboard) -> Void
    var deletePinboard: (_ pinboard: Pinboard) -> Void
    var selectTab: (_ tab: BarTab) -> Void
    var openSettings: () -> Void
}

struct BarView: View {
    @ObservedObject var model: BarModel
    @ObservedObject var settings: AppSettings
    let images: CardImageCache
    let actions: BarActions

    var body: some View {
        VStack(spacing: 10) {
            topRow
            strip
        }
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BarBackground())
    }

    private var topRow: some View {
        HStack(spacing: 14) {
            searchBox
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    tabButton(.history, title: "History", icon: "clock")
                    ForEach(model.pinboards) { board in
                        tabButton(.pinboard(board.id), title: board.name.isEmpty ? "Untitled" : board.name, icon: "pin")
                            .contextMenu {
                                Button("Rename Pinboard…") { actions.renamePinboard(board) }
                                Button("Delete Pinboard") { actions.deletePinboard(board) }
                            }
                    }
                    Button { actions.newPinboard([]) } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                        .help("New pinboard")
                }
            }
            Spacer(minLength: 0)
            if settings.isCapturePaused {
                MUKStatusChip(label: "Capture", value: "Paused", tone: .warning)
            }
            Button { actions.openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
        }
        .padding(.horizontal, 20)
        .frame(height: 30)
    }

    private var searchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            if model.query.isEmpty {
                Text("Type to search").foregroundStyle(.tertiary)
            } else {
                Text(model.query).lineLimit(1)
                Rectangle().fill(MUKTheme.accent).frame(width: 1.5, height: 15)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(width: 260, height: 28, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MUKTheme.rowRadius).fill(Color.primary.opacity(0.08)))
    }

    private func tabButton(_ tab: BarTab, title: String, icon: String) -> some View {
        Button { actions.selectTab(tab) } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: model.tab == tab ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(model.tab == tab ? MUKTheme.accent.opacity(0.22) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var strip: some View {
        if model.items.isEmpty {
            Text(emptyText)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                            card(item, index: index)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
                .onChange(of: model.cursor) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private var emptyText: String {
        if !model.query.isEmpty { return "No clips match \u{201C}\(model.query)\u{201D}" }
        if model.tab != .history { return "This pinboard is empty. Right-click a clip to pin it here." }
        if settings.isCapturePaused { return "Capture is paused" }
        return "Nothing copied yet. Copy text, an image or files and they'll show up here."
    }

    private func card(_ item: ClipboardItem, index: Int) -> some View {
        ClipCardView(item: item, images: images, isCursor: model.cursor == item.id,
                     isSelected: model.selection.contains(item.id), quickIndex: index < 9 ? index + 1 : nil)
            .id(item.id)
            .onTapGesture(count: 2) {
                let items = model.selection.contains(item.id) ? model.selectedItems : [item]
                actions.paste(items, NSEvent.modifierFlags.contains(.shift))
            }
            .simultaneousGesture(TapGesture().onEnded { model.click(item, modifiers: NSEvent.modifierFlags) })
            .contextMenu { contextMenu(for: item) }
    }

    @ViewBuilder private func contextMenu(for item: ClipboardItem) -> some View {
        let targets = model.selection.contains(item.id) ? model.selectedItems : [item]
        Button(targets.count > 1 ? "Paste \(targets.count) Items" : "Paste") { actions.paste(targets, false) }
        Button("Paste as Plain Text") { actions.paste(targets, true) }
        Button("Copy") { actions.copy(targets) }
        Divider()
        Menu("Pin to") {
            ForEach(model.pinboards) { board in
                Button(board.name.isEmpty ? "Untitled" : board.name) { actions.pin(targets, board.id) }
            }
            if !model.pinboards.isEmpty { Divider() }
            Button("New Pinboard…") { actions.newPinboard(targets) }
        }
        if targets.contains(where: \.pinned) {
            Button("Unpin") { actions.pin(targets, nil) }
        }
        if targets.count == 1 {
            Button("Rename…") { actions.rename(item) }
        }
        Divider()
        Button(targets.count > 1 ? "Delete \(targets.count) Items" : "Delete") { actions.delete(targets) }
    }
}

/// The translucent bar background with rounded top corners.
private struct BarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
