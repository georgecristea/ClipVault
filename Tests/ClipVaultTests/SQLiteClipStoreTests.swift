import SQLite3
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

    private func text(_ value: String) -> ClipboardCapture {
        ClipboardClassifier.capture(from: Snap.of([Snap.text(value)]))!
    }

    @discardableResult
    private func save(_ store: SQLiteClipStore, _ value: String, at date: Date = Date(), source: String? = nil) async throws -> ClipboardItem {
        try await store.save(text(value), sourceBundleID: source, at: date)
    }

    func testSaveAndFetchRoundTrip() async throws {
        let store = try makeStore()
        let rich = ClipboardClassifier.capture(from: Snap.of([Snap.item(("public.rtf", Data("{\\rtf1 hi}".utf8)),
                                                                         ("public.utf8-plain-text", Data("hi".utf8)))]))!
        let saved = try await store.save(rich, sourceBundleID: "com.example.app", at: Date())

        let items = try await store.fetchItems(limit: 50, query: nil, pinboardID: nil)
        XCTAssertEqual(items.map(\.id), [saved.id])
        XCTAssertEqual(items.first?.preview, "hi")
        XCTAssertEqual(items.first?.sourceBundleID, "com.example.app")
        XCTAssertFalse(items.first?.pinned ?? true)
        let payload = try await store.payloadItems(for: saved)
        XCTAssertEqual(payload, rich.items)
    }

    func testDuplicateMovesToFrontKeepingTitleAndPinboard() async throws {
        let store = try makeStore()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let first = try await save(store, "one", at: t0)
        try await store.setTitle("My title", for: first.id)
        let board = try await store.createPinboard(name: "Board")
        try await store.pin([first.id], to: board.id)
        try await save(store, "two", at: t0.addingTimeInterval(10))

        let again = try await save(store, "one", at: t0.addingTimeInterval(20))
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(again.title, "My title")
        XCTAssertEqual(again.pinboardID, board.id)
        let items = try await store.fetchItems(limit: 50, query: nil, pinboardID: nil)
        XCTAssertEqual(items.map(\.preview), ["one", "two"])
    }

    func testSearchAllWordsAcrossTextAndTitle() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000)
        try await save(store, "alpha beta", at: base)
        let gamma = try await save(store, "gamma", at: base.addingTimeInterval(1))
        try await save(store, "Beta 100%", at: base.addingTimeInterval(2))
        try await store.setTitle("delta note", for: gamma.id)
        // A long text is searchable beyond the 240-character preview.
        try await save(store, String(repeating: "filler ", count: 60) + "needle", at: base.addingTimeInterval(3))

        func search(_ q: String) async throws -> [String] {
            try await store.fetchItems(limit: 50, query: q, pinboardID: nil).map(\.preview)
        }
        let beta = try await search("beta")
        XCTAssertEqual(beta, ["Beta 100%", "alpha beta"])
        let percent = try await search("100%")
        XCTAssertEqual(percent, ["Beta 100%"])
        let both = try await search("beta alpha")
        XCTAssertEqual(both, ["alpha beta"])
        let byTitle = try await search("delta")
        XCTAssertEqual(byTitle, ["gamma"])
        let needle = try await search("needle")
        XCTAssertEqual(needle.count, 1)
    }

    func testPinboardOrderAndDeleteKeepsClips() async throws {
        let store = try makeStore()
        let board = try await store.createPinboard(name: "Links")
        let one = try await save(store, "one", at: Date(timeIntervalSince1970: 1))
        let two = try await save(store, "two", at: Date(timeIntervalSince1970: 2))
        try await store.pin([one.id], to: board.id)
        try await store.pin([two.id], to: board.id)
        let onBoard = try await store.fetchItems(limit: 50, query: nil, pinboardID: board.id).map(\.preview)
        XCTAssertEqual(onBoard, ["one", "two"])
        try await store.renamePinboard(id: board.id, name: "Renamed")
        let names = try await store.pinboards().map(\.name)
        XCTAssertEqual(names, ["Renamed"])

        try await store.deletePinboard(id: board.id)
        let boards = try await store.pinboards()
        XCTAssertEqual(boards, [])
        let all = try await store.fetchItems(limit: 50, query: nil, pinboardID: nil)
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.allSatisfy { $0.pinboardID == nil })
    }

    func testRetentionSparesPinboards() async throws {
        let store = try makeStore()
        let board = try await store.createPinboard(name: "Keep")
        let old = Date(timeIntervalSinceNow: -40 * 86_400)
        let pinned = try await save(store, "old pinned", at: old)
        try await store.pin([pinned.id], to: board.id)
        try await save(store, "old", at: old)
        try await save(store, "new")
        let cutoff = Date(timeIntervalSinceNow: -30 * 86_400)
        let counted = try await store.countItems(olderThan: cutoff)
        XCTAssertEqual(counted, 1)
        let deleted = try await store.deleteItems(olderThan: cutoff)
        XCTAssertEqual(deleted, 1)
        let left = Set(try await store.fetchItems(limit: 50, query: nil, pinboardID: nil).map(\.preview))
        XCTAssertEqual(left, ["old pinned", "new"])
    }

    func testEraseHistoryKeepsPinned() async throws {
        let store = try makeStore()
        let board = try await store.createPinboard(name: "Keep")
        let kept = try await save(store, "kept")
        try await store.pin([kept.id], to: board.id)
        try await save(store, "gone")
        let erased = try await store.eraseHistory()
        XCTAssertEqual(erased, 1)
        let left = try await store.fetchItems(limit: 50, query: nil, pinboardID: nil).map(\.preview)
        XCTAssertEqual(left, ["kept"])
        let summary = try await store.summary()
        XCTAssertEqual(summary.count, 1)
    }

    func testDeleteRemovesItemAndPayload() async throws {
        let store = try makeStore()
        let item = try await save(store, "gone")
        let payloadURL = tempRoot.appendingPathComponent("Payloads").appendingPathComponent(item.payloadPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: payloadURL.path))
        try await store.delete([item.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: payloadURL.path))
        let left = try await store.fetchItems(limit: 50, query: nil, pinboardID: nil)
        XCTAssertEqual(left, [])
    }

    func testTouchMovesToFront() async throws {
        let store = try makeStore()
        let a = try await save(store, "a", at: Date(timeIntervalSince1970: 1))
        try await save(store, "b", at: Date(timeIntervalSince1970: 2))
        try await store.touch([a.id])
        let order = try await store.fetchItems(limit: 50, query: nil, pinboardID: nil).map(\.preview)
        XCTAssertEqual(order, ["a", "b"])
    }

    /// A database written by ClipVault 0.1.x: legacy payload files, a pinned flag, no pinboards.
    func testMigratesLegacyDatabase() async throws {
        let payloads = tempRoot.appendingPathComponent("Payloads", isDirectory: true)
        try FileManager.default.createDirectory(at: payloads, withIntermediateDirectories: true)
        try Data("legacy text".utf8).write(to: payloads.appendingPathComponent("t.txt"))
        let png = Snap.pngData()
        try png.write(to: payloads.appendingPathComponent("i.png"))
        try JSONEncoder().encode(["/tmp/a.txt", "/tmp/b.pdf"]).write(to: payloads.appendingPathComponent("f.json"))

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(tempRoot.appendingPathComponent("ClipVault.sqlite3").path, &db), SQLITE_OK)
        let sql = """
        CREATE TABLE clipboard_items (id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL, created_at REAL NOT NULL,
            updated_at REAL NOT NULL, sha256 TEXT NOT NULL, preview TEXT NOT NULL, payload_path TEXT NOT NULL,
            byte_count INTEGER NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, source_bundle_id TEXT);
        INSERT INTO clipboard_items VALUES ('T', 'text', 100, 100, 'h1', 'legacy text', 't.txt', 11, 1, 'com.a');
        INSERT INTO clipboard_items VALUES ('I', 'image', 200, 200, 'h2', '4 x 3 image', 'i.png', 10, 0, NULL);
        INSERT INTO clipboard_items VALUES ('F', 'files', 300, 300, 'h3', '2 files', 'f.json', 20, 0, NULL);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)

        let store = try makeStore()
        let items = try await store.fetchItems(limit: 50, query: nil, pinboardID: nil)
        XCTAssertEqual(items.map(\.id), ["F", "I", "T"])
        let boards = try await store.pinboards()
        XCTAssertEqual(boards.map(\.name), ["Pinned"])
        let pinned = try await store.fetchItems(limit: 50, query: nil, pinboardID: boards[0].id)
        XCTAssertEqual(pinned.map(\.id), ["T"])

        let textPayload = try await store.payloadItems(for: items[2])
        XCTAssertEqual(textPayload, [[PasteboardRepresentation(type: "public.utf8-plain-text", data: Data("legacy text".utf8))]])
        let imagePayload = try await store.payloadItems(for: items[1])
        XCTAssertEqual(imagePayload, [[PasteboardRepresentation(type: "public.png", data: png)]])
        let filePayload = try await store.payloadItems(for: items[0])
        XCTAssertEqual(filePayload.map { $0.map(\.type) }, [["public.file-url"], ["public.file-url"]])
        XCTAssertEqual(URL(dataRepresentation: filePayload[1][0].data, relativeTo: nil)?.path, "/tmp/b.pdf")

        let search = try await store.fetchItems(limit: 50, query: "legacy", pinboardID: nil)
        XCTAssertEqual(search.map(\.id), ["T"])

        // Reopening must not migrate twice (one "Pinned" pinboard only).
        let reopened = try makeStore()
        let boardsAgain = try await reopened.pinboards()
        XCTAssertEqual(boardsAgain.count, 1)
    }
}
