import Foundation

/// Encodes a clip's pasteboard items into its payload file, and reads payloads written by any
/// ClipVault version.
enum PayloadCodec {
    /// Current format: a binary property list `[[["type": String, "data": Data]]]`.
    static let itemsFormat = "items-v1"
    /// ClipVault 0.1: text as UTF-8, images as PNG, files as a JSON array of paths.
    static let legacyFormat = "legacy"

    static func encode(_ items: [PasteboardItemData]) throws -> Data {
        let plist = items.map { item in item.map { ["type": $0.type, "data": $0.data] as [String: Any] } }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    static func decode(_ data: Data, format: String, kind: ClipboardKind) throws -> [PasteboardItemData] {
        if format == itemsFormat {
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[[String: Any]]] else {
                throw ClipVaultError.invalidPayload("Unreadable clip payload.")
            }
            return plist.map { item in
                item.compactMap { rep in
                    guard let type = rep["type"] as? String, let data = rep["data"] as? Data else { return nil }
                    return PasteboardRepresentation(type: type, data: data)
                }
            }
        }
        switch kind {
        case .image:
            return [[PasteboardRepresentation(type: "public.png", data: data)]]
        case .files:
            let paths = try JSONDecoder().decode([String].self, from: data)
            return paths.map { [PasteboardRepresentation(type: ClipboardClassifier.fileURL,
                                                         data: URL(fileURLWithPath: $0).dataRepresentation)] }
        case .text, .link, .color:
            return [[PasteboardRepresentation(type: ClipboardClassifier.plainText, data: data)]]
        }
    }
}
