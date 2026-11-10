import MacUtilityKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings
    @State private var searchText = ""
    @State private var selectedID: String?
    @State private var window: NSWindow?

    init(appState: AppState) {
        self.appState = appState
        self._settings = ObservedObject(wrappedValue: appState.settings)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusStrip
            searchField

            if appState.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KeyboardMonitor(handler: handleKeyDown))
        .background(WindowAccessor { window = $0 })
        .onDisappear { appState.preview.hide() }
        .onChange(of: appState.items) { _, items in
            if selectedID == nil || !items.contains(where: { $0.id == selectedID }) {
                selectedID = items.first?.id
            }
            updatePreview()
        }
        .onChange(of: selectedID) { _, _ in updatePreview() }
        .onChange(of: window) { _, _ in updatePreview() }
    }

    private func updatePreview() {
        // Only show the preview while the popover is actually open and on screen.
        guard appState.isPopoverOpen, let window, window.isVisible else {
            appState.preview.hide()
            return
        }
        appState.preview.update(item: selectedItem, window: window)
    }

    // MARK: - Status strip (nudges only)

    @ViewBuilder private var statusStrip: some View {
        if settings.capturePaused {
            HStack(spacing: 8) {
                Button { appState.setCapturePaused(false) } label: {
                    MUKStatusChip(label: "Capture", value: "Paused", tone: .warning)
                }
                .buttonStyle(.plain)
                .help("Resume capture")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clips", text: $searchText)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { _, query in
                    appState.reload(query: query)
                }
            if !searchText.isEmpty {
                Button { clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: MUKTheme.rowRadius))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(appState.items.enumerated()), id: \.element.id) { index, item in
                        HistoryRowView(
                            item: item,
                            thumbnail: appState.thumbnail(for: item),
                            isSelected: selectedID == item.id,
                            shortcutIndex: index < 9 ? index + 1 : nil,
                            restore: {
                                selectedID = item.id
                                appState.select(item)
                            },
                            togglePin: { appState.setPinned(!item.pinned, for: item) },
                            delete: { appState.delete(item) })
                            .id(item.id)
                            .onHover { hovering in if hovering { selectedID = item.id } }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
            .onChange(of: selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !searchText.isEmpty {
            MUKEmptyState(
                title: "No matches",
                detail: "No clips match \u{201C}\(searchText)\u{201D}.",
                systemImage: "magnifyingglass")
        } else if settings.capturePaused {
            MUKEmptyState(
                title: "Capture paused",
                detail: "New copies aren't being saved. Resume from the header to start capturing again.",
                systemImage: "pause.circle")
        } else {
            MUKEmptyState(
                title: "Nothing copied yet",
                detail: "Copy text, an image, or files and they'll show up here.",
                systemImage: "doc.on.clipboard")
        }
    }

    // MARK: - Keyboard (AppKit key-down monitor; works regardless of SwiftUI focus)

    /// Returns true to consume the event.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)
        // Whether the user is currently editing the search text field.
        let editingSearch = event.window?.firstResponder is NSText

        switch event.keyCode {
        case 125: // down arrow
            moveSelection(by: 1); return true
        case 126: // up arrow
            moveSelection(by: -1); return true
        case 36, 76: // return / enter
            if let item = selectedItem { appState.select(item) }
            return true
        case 53: // escape
            if !searchText.isEmpty { clearSearch() } else { appState.requestClosePopover?() }
            return true
        default:
            break
        }

        if cmd {
            let chars = event.charactersIgnoringModifiers ?? ""
            if let digit = Int(chars), (1...9).contains(digit) { quickPaste(index: digit - 1); return true }
            if chars == "p", let item = selectedItem { appState.setPinned(!item.pinned, for: item); return true }
            if chars == "," { withAnimation(.easeInOut(duration: 0.18)) { appState.popoverScreen = .settings }; return true }
            if event.keyCode == 51, let item = selectedItem { appState.delete(item); return true } // ⌘⌫
            return false
        }

        // When the search field is focused, let it handle typing/backspace natively.
        if editingSearch { return false }

        // Otherwise, type-to-search.
        if event.keyCode == 51 { // backspace
            if !searchText.isEmpty { searchText.removeLast() }
            return true
        }
        if let chars = event.characters, !chars.isEmpty,
           !chars.contains(where: { $0.isNewline || $0 == "\t" || $0.unicodeScalars.contains { $0.value < 32 } }) {
            searchText.append(chars)
            return true
        }
        return false
    }

    private var selectedItem: ClipboardItem? {
        appState.items.first { $0.id == selectedID }
    }

    private func moveSelection(by delta: Int) {
        let items = appState.items
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(current + delta, 0), items.count - 1)
        selectedID = items[next].id
    }

    private func quickPaste(index: Int) {
        guard appState.items.indices.contains(index) else { return }
        appState.select(appState.items[index])
    }

    private func clearSearch() {
        searchText = ""
        appState.reload()
    }
}
