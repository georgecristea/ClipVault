import Foundation

enum ClipboardKind: String, Sendable {
    case text
    case image
    case files
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
    var pinned: Bool = false
    var sourceBundleID: String? = nil
}

struct ClipboardCapture: Sendable {
    let kind: ClipboardKind
    let data: Data
    let preview: String
    let fileExtension: String
}
