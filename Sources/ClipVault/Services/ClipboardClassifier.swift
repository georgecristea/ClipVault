import AppKit

/// Pure snapshot → capture classification. Order: files, then text (link, colour or plain
/// text), then image.
enum ClipboardClassifier {
    static let plainText = "public.utf8-plain-text"
    static let fileURL = "public.file-url"
    static let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif"]
    static let maxSearchLength = 20_000

    /// True when the snapshot carries a marker meaning it must not be saved.
    static func shouldIgnore(_ snapshot: PasteboardSnapshot) -> Bool {
        !PasteboardMarkers.skip.isDisjoint(with: snapshot.types)
    }

    static func capture(from snapshot: PasteboardSnapshot) -> ClipboardCapture? {
        let items = snapshot.items
        guard !items.isEmpty else { return nil }
        func first(_ type: String, in item: PasteboardItemData) -> Data? { item.first { $0.type == type }?.data }

        let urls = items.compactMap { first(fileURL, in: $0) }.compactMap { URL(dataRepresentation: $0, relativeTo: nil) }
        if !urls.isEmpty {
            let names = urls.map(\.lastPathComponent)
            let preview = urls.count == 1 ? names[0] : "\(urls.count) files"
            return make(.files, items, preview: preview, search: names.joined(separator: "\n"),
                        key: Data(urls.map(\.path).joined(separator: "\n").utf8))
        }

        let strings = items.compactMap { first(plainText, in: $0) }.compactMap { String(data: $0, encoding: .utf8) }
        if let text = strings.first, !text.isEmpty {
            let joined = strings.joined(separator: "\n")
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            var kind = ClipboardKind.text
            if strings.count == 1, isColor(trimmed) { kind = .color } else if strings.count == 1, isLink(trimmed) { kind = .link }
            return make(kind, items, preview: joined.clipVaultPreview(maxLength: 240), search: joined, key: Data(joined.utf8))
        }

        for item in items {
            for type in imageTypes {
                if let data = first(type, in: item) {
                    let description = NSImage(data: data)?.clipVaultDescription ?? "Image"
                    return make(.image, items, preview: description, search: description, key: data)
                }
            }
        }
        return nil
    }

    private static func make(_ kind: ClipboardKind, _ items: [PasteboardItemData], preview: String, search: String, key: Data) -> ClipboardCapture {
        ClipboardCapture(kind: kind, items: items, preview: preview, searchText: String(search.prefix(maxSearchLength)), contentKey: key)
    }

    /// `#RRGGBB` or `RRGGBB`.
    static func isColor(_ text: String) -> Bool {
        text.range(of: "^#?[A-Fa-f0-9]{6}$", options: .regularExpression) != nil
    }

    /// A single web or mail link with nothing around it.
    static func isLink(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace), let url = URL(string: text), let scheme = url.scheme?.lowercased() else {
            return false
        }
        switch scheme {
        case "http", "https": return url.host?.isEmpty == false
        case "mailto": return true
        default: return false
        }
    }
}

extension String {
    func clipVaultPreview(maxLength: Int) -> String {
        let collapsed = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<endIndex]) + "..."
    }
}

extension NSImage {
    var clipVaultPNGData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    var clipVaultDescription: String {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        return "\(width) x \(height) image"
    }
}
