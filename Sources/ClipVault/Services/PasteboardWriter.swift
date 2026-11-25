import AppKit

/// Puts clips back on a pasteboard.
enum PasteboardWriter {
    /// Decides what to write for one or more clips.
    ///
    /// - One clip: its items unchanged, or only its plain text when `plainText` (images and
    ///   files are always written unchanged).
    /// - Several text, link or colour clips: one item with their texts joined by newlines.
    /// - Several clips of other kinds: all their items, so apps that accept several items (images
    ///   in a chat prompt, files in Finder) get them all.
    static func plan(_ sources: [(kind: ClipboardKind, items: [PasteboardItemData])], plainText: Bool) -> [PasteboardItemData] {
        let textLike: Set<ClipboardKind> = [.text, .link, .color]
        if sources.count > 1, sources.allSatisfy({ textLike.contains($0.kind) }) {
            return [[PasteboardRepresentation(type: ClipboardClassifier.plainText,
                                              data: Data(sources.map { text(of: $0.items) }.joined(separator: "\n").utf8))]]
        }
        return sources.flatMap { source -> [PasteboardItemData] in
            guard plainText, textLike.contains(source.kind) else { return source.items }
            return [[PasteboardRepresentation(type: ClipboardClassifier.plainText, data: Data(text(of: source.items).utf8))]]
        }
    }

    /// The first plain-text representation, or "".
    static func text(of items: [PasteboardItemData]) -> String {
        for item in items {
            if let data = item.first(where: { $0.type == ClipboardClassifier.plainText })?.data,
               let string = String(data: data, encoding: .utf8) { return string }
        }
        return ""
    }

    /// Replaces the pasteboard contents, tagging every item with ClipVault's marker so the
    /// monitor never captures its own writes. Returns the new change count.
    @discardableResult
    static func write(_ items: [PasteboardItemData], to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { item in
            let pbItem = NSPasteboardItem()
            for rep in item { pbItem.setData(rep.data, forType: NSPasteboard.PasteboardType(rep.type)) }
            pbItem.setData(Data(), forType: NSPasteboard.PasteboardType(PasteboardMarkers.own))
            return pbItem
        })
        return pasteboard.changeCount
    }
}
