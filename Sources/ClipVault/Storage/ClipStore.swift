import Foundation

/// Abstraction over clipboard persistence so the SQLite backend is swappable and testable.
/// All access is async because the concrete store is an actor (off the main thread).
protocol ClipStore: Sendable {
    /// History newest first (by last copy), or one pinboard in pin order. A non-empty `query`
    /// keeps clips whose text or title contains every word, case-insensitively.
    func fetchItems(limit: Int, query: String?, pinboardID: Int64?) async throws -> [ClipboardItem]

    /// Stores a capture. If the same content is already stored, that clip moves to the front
    /// instead (its title and pinboard are kept). Returns the stored clip.
    @discardableResult
    func save(_ capture: ClipboardCapture, sourceBundleID: String?, at date: Date) async throws -> ClipboardItem

    /// The clip's pasteboard items, whatever version wrote them.
    func payloadItems(for item: ClipboardItem) async throws -> [PasteboardItemData]

    /// Moves clips to the front of history, as if just copied.
    func touch(_ ids: [String]) async throws
    func setTitle(_ title: String?, for id: String) async throws
    func delete(_ ids: [String]) async throws

    func pinboards() async throws -> [Pinboard]
    func createPinboard(name: String) async throws -> Pinboard
    func renamePinboard(id: Int64, name: String) async throws
    /// Deletes the pinboard; its clips stay in history.
    func deletePinboard(id: Int64) async throws
    /// Puts clips on a pinboard (at the end), or takes them off with `nil`.
    func pin(_ ids: [String], to pinboardID: Int64?) async throws

    /// Deletes clips not on a pinboard and last copied before `date`. Returns how many.
    @discardableResult
    func deleteItems(olderThan date: Date) async throws -> Int
    /// How many clips `deleteItems(olderThan:)` would delete.
    func countItems(olderThan date: Date) async throws -> Int
    /// Deletes every clip that is not on a pinboard. Returns how many.
    @discardableResult
    func eraseHistory() async throws -> Int
    func summary() async throws -> (count: Int, bytes: Int)
}
