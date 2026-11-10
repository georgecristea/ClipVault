import XCTest
@testable import ClipVault

final class SQLiteClipStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipVaultTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    private func makeStore() throws -> SQLiteClipStore {
        try SQLiteClipStore(rootDirectory: tempRoot)
    }

    private func textCapture(_ value: String) -> ClipboardCapture {
        ClipboardCapture(kind: .text, data: Data(value.utf8), preview: value, fileExtension: "txt")
    }

    func testSaveAndFetchRoundTrip() async throws {
        let store = try makeStore()
        try await store.save(textCapture("hello"), sourceBundleID: "com.example.app")

        let items = try await store.fetchItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.preview, "hello")
        XCTAssertEqual(items.first?.kind, .text)
        XCTAssertEqual(items.first?.sourceBundleID, "com.example.app")
        XCTAssertFalse(items.first?.pinned ?? true)

        let data = try await store.payloadData(for: try XCTUnwrap(items.first))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hello")
    }

    func testDedupReturnsFalseForIdenticalContent() async throws {
        let store = try makeStore()
        let first = try await store.save(textCapture("dupe"), sourceBundleID: nil)
        let second = try await store.save(textCapture("dupe"), sourceBundleID: nil)

        XCTAssertTrue(first)
        XCTAssertFalse(second)
        let items = try await store.fetchItems()
        XCTAssertEqual(items.count, 1)
    }

    func testPinnedSortsFirstAndSurvivesRetention() async throws {
        let store = try makeStore()
        try await store.save(textCapture("old"), sourceBundleID: nil)
        let saved = try await store.fetchItems()
        let oldItem = try XCTUnwrap(saved.first)
        try await store.save(textCapture("new"), sourceBundleID: nil)

        // Pin the older item; it should jump to the front.
        try await store.setPinned(true, for: oldItem)
        let ordered = try await store.fetchItems()
        XCTAssertEqual(ordered.first?.preview, "old")
        XCTAssertTrue(ordered.first?.pinned ?? false)

        // A retention sweep that covers everything must keep the pinned item.
        try await store.deleteItems(olderThan: Date().addingTimeInterval(60 * 60))
        let remaining = try await store.fetchItems()
        XCTAssertEqual(remaining.map(\.preview), ["old"])
    }

    func testSearchFiltersByPreview() async throws {
        let store = try makeStore()
        try await store.save(textCapture("apple pie"), sourceBundleID: nil)
        try await store.save(textCapture("banana bread"), sourceBundleID: nil)

        let results = try await store.fetchItems(limit: 250, query: "banana")
        XCTAssertEqual(results.map(\.preview), ["banana bread"])

        // LIKE wildcards in the query are treated literally.
        let wildcard = try await store.fetchItems(limit: 250, query: "%")
        XCTAssertTrue(wildcard.isEmpty)
    }

    func testDeleteRemovesItemAndPayload() async throws {
        let store = try makeStore()
        try await store.save(textCapture("trash"), sourceBundleID: nil)
        let saved = try await store.fetchItems()
        let item = try XCTUnwrap(saved.first)
        let payloadPath = tempRoot
            .appendingPathComponent("Payloads", isDirectory: true)
            .appendingPathComponent(item.payloadPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadPath.path))

        try await store.delete(item)
        let remaining = try await store.fetchItems()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadPath.path))
    }

    func testMigrationIsIdempotentAcrossReopens() async throws {
        // Open, write, close, reopen the same directory — the additive migration must not fail.
        do {
            let store = try makeStore()
            try await store.save(textCapture("persisted"), sourceBundleID: "com.example.app")
        }
        let reopened = try makeStore()
        let items = try await reopened.fetchItems()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.sourceBundleID, "com.example.app")
    }
}
