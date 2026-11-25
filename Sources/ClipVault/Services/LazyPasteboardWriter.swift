import AppKit

/// Puts items on a pasteboard so their data is handed over on request, and reports the first time
/// another app reads any of it. Pasting several clips one after another uses this to move to the
/// next clip as soon as the target app has taken the current one, instead of guessing a delay.
///
/// ClipVault's marker type is written directly, so ClipVault's own monitor (which only looks at
/// type names when the marker is present) never counts as a read.
final class LazyPasteboardWriter: NSObject, NSPasteboardItemDataProvider {
    private var payloads: [(item: NSPasteboardItem, data: [String: Data])] = []
    private var onFirstRead: (() -> Void)?

    func write(_ items: [PasteboardItemData], to pasteboard: NSPasteboard, onFirstRead: @escaping () -> Void) {
        self.onFirstRead = onFirstRead
        payloads = items.map { item in
            let pbItem = NSPasteboardItem()
            pbItem.setDataProvider(self, forTypes: item.map { NSPasteboard.PasteboardType($0.type) })
            pbItem.setData(Data(), forType: NSPasteboard.PasteboardType(PasteboardMarkers.own))
            return (pbItem, Dictionary(item.map { ($0.type, $0.data) }, uniquingKeysWith: { first, _ in first }))
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(payloads.map(\.item))
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if let data = payloads.first(where: { $0.item === item })?.data[type.rawValue] {
            item.setData(data, forType: type)
        }
        if let callback = onFirstRead {
            onFirstRead = nil
            callback()
        }
    }
}
