import Foundation

/// Abstraction over clipboard persistence so the SQLite backend is swappable and testable.
/// All access is async because the concrete store is an actor (off the main thread).
protocol ClipStore: Sendable {
    /// Most recent items first, pinned items ahead of the rest. When `query` is non-empty,
    /// results are filtered to previews containing it (case-insensitive).
    func fetchItems(limit: Int, query: String?) async throws -> [ClipboardItem]

    /// Persists a capture, deduping against the most recent item by content hash.
    /// Returns `false` (and stores nothing) when the content matches the latest item.
    @discardableResult
    func save(_ capture: ClipboardCapture, sourceBundleID: String?) async throws -> Bool

    func payloadData(for item: ClipboardItem) async throws -> Data

    func setPinned(_ pinned: Bool, for item: ClipboardItem) async throws

    func delete(_ item: ClipboardItem) async throws

    /// Deletes items older than `date`, leaving pinned items untouched.
    func deleteItems(olderThan date: Date) async throws
}

extension ClipStore {
    func fetchItems(limit: Int = 250) async throws -> [ClipboardItem] {
        try await fetchItems(limit: limit, query: nil)
    }
}
