import AppKit
import Combine

enum BarTab: Hashable {
    case history
    case pinboard(Int64)
}

/// What the bar shows: the clips of one tab, filtered by the search text, with a cursor and a
/// multi-selection. Loading is done by `BarController`; this type only holds state.
@MainActor
final class BarModel: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var pinboards: [Pinboard] = []
    @Published var tab: BarTab = .history
    @Published var query = ""
    /// The focused card.
    @Published var cursor: String?
    /// Cards chosen for pasting; contains the cursor whenever something is shown.
    @Published var selection: Set<String> = []
    /// True from the moment a reload starts until its results are applied. While true the shown
    /// cards may be stale (from the last time the bar was open, or the previous search), so
    /// keyboard actions must not act on them.
    @Published private(set) var isLoading = false

    func beginLoading() { isLoading = true }

    /// Replaces the shown clips. The cursor stays on the same clip when it is still shown,
    /// unless `resetCursor`.
    func apply(items: [ClipboardItem], pinboards: [Pinboard], resetCursor: Bool = true) {
        isLoading = false
        self.items = items
        self.pinboards = pinboards
        let ids = Set(items.map(\.id))
        if resetCursor || cursor.map({ !ids.contains($0) }) ?? true {
            cursor = items.first?.id
            selection = cursor.map { [$0] } ?? []
        } else {
            selection = selection.intersection(ids)
            if let cursor, selection.isEmpty { selection = [cursor] }
        }
    }

    var cursorIndex: Int? { cursor.flatMap { id in items.firstIndex { $0.id == id } } }

    /// Selected clips in on-screen order.
    var selectedItems: [ClipboardItem] { items.filter { selection.contains($0.id) } }

    var cursorItem: ClipboardItem? { cursorIndex.map { items[$0] } }

    /// The selection, or nothing while a reload is pending.
    var actionableItems: [ClipboardItem] { isLoading ? [] : selectedItems }

    /// The clip for ⌘`number` (1-based), or nil while a reload is pending.
    func quickItem(at number: Int) -> ClipboardItem? {
        guard !isLoading, number >= 1, number <= items.count else { return nil }
        return items[number - 1]
    }

    func move(by delta: Int, extend: Bool = false) {
        guard !items.isEmpty else { return }
        let index = max(0, min(items.count - 1, (cursorIndex ?? 0) + delta))
        let id = items[index].id
        cursor = id
        if extend { selection.insert(id) } else { selection = [id] }
    }

    /// A plain click selects one card, ⌘ toggles one, ⇧ selects the range from the cursor.
    func click(_ item: ClipboardItem, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(item.id), selection.count > 1 {
                selection.remove(item.id)
                // Keep the cursor on a card that is still selected.
                if cursor == item.id { cursor = items.last { selection.contains($0.id) }?.id }
            } else {
                selection.insert(item.id)
                cursor = item.id
            }
        } else if modifiers.contains(.shift), let from = cursorIndex, let to = items.firstIndex(where: { $0.id == item.id }) {
            for i in min(from, to)...max(from, to) { selection.insert(items[i].id) }
            cursor = item.id
        } else {
            cursor = item.id
            selection = [item.id]
        }
    }

    /// History first, then the pinboards.
    var tabs: [BarTab] { [.history] + pinboards.map { .pinboard($0.id) } }

    func switchTab(by delta: Int) {
        let all = tabs
        let index = all.firstIndex(of: tab) ?? 0
        tab = all[(index + delta + all.count) % all.count]
    }

    var pinboardID: Int64? {
        if case .pinboard(let id) = tab { return id }
        return nil
    }
}
