import Foundation

enum ClipboardKind: String, Sendable {
    case text
    case image
    case files
    case link
    case color
}

struct ClipboardItem: Identifiable, Equatable, Sendable {
    let id: String
    let kind: ClipboardKind
    let createdAt: Date
    let updatedAt: Date
    let sha256: String
    let preview: String
    let payloadPath: String
    let byteCount: Int
    var sourceBundleID: String? = nil
    /// User-given name, shown on the card and searched.
    var title: String? = nil
    /// The pinboard the clip is on, if any. Clips on a pinboard never expire.
    var pinboardID: Int64? = nil
    /// The last time this content was copied (or pasted from ClipVault). History is newest first.
    var lastCopiedAt: Date = .distantPast

    var pinned: Bool { pinboardID != nil }
}

/// A clip as captured from the pasteboard, before it is stored.
struct ClipboardCapture: Sendable {
    let kind: ClipboardKind
    /// Every pasteboard item, each with all of its types, in the order the source offered them.
    let items: [PasteboardItemData]
    /// Short, single-line description for lists (at most 240 characters plus an ellipsis).
    let preview: String
    /// Text used for search: the full text, link, colour or file names (at most 20,000 characters).
    let searchText: String
    /// The bytes that identify the content, used to detect duplicates.
    let contentKey: Data
}

/// A named list of clips.
struct Pinboard: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    var position: Int
}
