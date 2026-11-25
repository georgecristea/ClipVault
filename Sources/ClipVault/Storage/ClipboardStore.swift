import CryptoKit
import Foundation
import SQLite3

/// SQLite-backed clipboard store. An actor so all database and payload-file I/O runs off the
/// main thread; the `sqlite3` handle stays actor-isolated.
actor SQLiteClipStore: ClipStore {
    private let databaseURL: URL
    private let payloadDirectoryURL: URL
    private var database: OpaquePointer?

    static let schemaVersion: Int32 = 2

    /// - Parameter rootDirectory: overrides the storage location (used by tests). Defaults to
    ///   `~/Library/Application Support/ClipVault`.
    init(fileManager: FileManager = .default, rootDirectory: URL? = nil) throws {
        let appSupportURL = try rootDirectory ?? Self.applicationSupportURL(fileManager: fileManager)
        databaseURL = appSupportURL.appendingPathComponent("ClipVault.sqlite3")
        payloadDirectoryURL = appSupportURL.appendingPathComponent("Payloads", isDirectory: true)

        try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: payloadDirectoryURL, withIntermediateDirectories: true)
        // Clipboard history can contain secrets — keep it out of Time Machine / iCloud backups.
        Self.excludeFromBackup(appSupportURL)
        database = try Self.openDatabase(at: databaseURL.path)
        try Self.migrate(database, payloadDirectory: payloadDirectoryURL)
        Self.restrictPermissions(at: databaseURL)
    }

    deinit {
        sqlite3_close(database)
    }

    /// Whether a database already exists at the default location (an earlier installation).
    nonisolated static func databaseExists(fileManager: FileManager = .default) -> Bool {
        guard let url = try? applicationSupportURL(fileManager: fileManager) else { return false }
        return fileManager.fileExists(atPath: url.appendingPathComponent("ClipVault.sqlite3").path)
    }

    // MARK: - Reading

    func fetchItems(limit: Int = 250, query: String? = nil, pinboardID: Int64? = nil) throws -> [ClipboardItem] {
        var conditions: [String] = []
        var params: [Param] = []
        if let pinboardID {
            conditions.append("pinboard_id = ?")
            params.append(.int(pinboardID))
        }
        for word in Self.fold(query ?? "").split(whereSeparator: \.isWhitespace) {
            conditions.append("search_key LIKE ? ESCAPE '\\'")
            params.append(.text("%\(Self.escapeLike(String(word)))%"))
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        let order = pinboardID == nil ? "last_copied_at DESC, created_at DESC" : "pin_order ASC, last_copied_at DESC"
        params.append(.int(Int64(limit)))
        return try items("SELECT \(Self.columns) FROM clipboard_items \(whereClause) ORDER BY \(order) LIMIT ?;", params)
    }

    func payloadItems(for item: ClipboardItem) throws -> [PasteboardItemData] {
        let format = try rows("SELECT payload_format FROM clipboard_items WHERE id = ?;", [.text(item.id)]) {
            Self.columnText($0, 0)
        }.first ?? nil
        let data = try Data(contentsOf: payloadURL(for: item))
        return try PayloadCodec.decode(data, format: format ?? PayloadCodec.legacyFormat, kind: item.kind)
    }

    func summary() throws -> (count: Int, bytes: Int) {
        try rows("SELECT COUNT(*), IFNULL(SUM(byte_count), 0) FROM clipboard_items;", []) {
            (count: Int(sqlite3_column_int64($0, 0)), bytes: Int(sqlite3_column_int64($0, 1)))
        }.first ?? (count: 0, bytes: 0)
    }

    // MARK: - Writing

    @discardableResult
    func save(_ capture: ClipboardCapture, sourceBundleID: String?, at date: Date = Date()) throws -> ClipboardItem {
        let hash = Self.hash(kind: capture.kind, key: capture.contentKey)
        let now = date.timeIntervalSince1970
        if let existing = try items("SELECT \(Self.columns) FROM clipboard_items WHERE sha256 = ? LIMIT 1;", [.text(hash)]).first {
            try run("UPDATE clipboard_items SET last_copied_at = ?, source_bundle_id = IFNULL(?, source_bundle_id) WHERE id = ?;",
                    [.double(now), sourceBundleID.map(Param.text) ?? .null, .text(existing.id)])
            return try item(id: existing.id)
        }

        let id = UUID().uuidString
        let fileName = "\(id).clip"
        let payloadURL = payloadDirectoryURL.appendingPathComponent(fileName)
        try PayloadCodec.encode(capture.items).write(to: payloadURL, options: .atomic)
        Self.restrictPermissions(at: payloadURL)
        let byteCount = capture.items.reduce(0) { $0 + $1.reduce(0) { $0 + $1.data.count } }

        do {
            try run("""
                INSERT INTO clipboard_items
                (id, kind, created_at, updated_at, sha256, preview, payload_path, byte_count, pinned, source_bundle_id,
                 payload_format, search_text, search_key, last_copied_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?);
                """, [.text(id), .text(capture.kind.rawValue), .double(now), .double(now), .text(hash), .text(capture.preview),
                      .text(fileName), .int(Int64(byteCount)), sourceBundleID.map(Param.text) ?? .null,
                      .text(PayloadCodec.itemsFormat), .text(capture.searchText),
                      .text(Self.searchKey(text: capture.searchText, title: nil)), .double(now)])
        } catch {
            try? FileManager.default.removeItem(at: payloadURL)
            throw error
        }
        return try item(id: id)
    }

    func touch(_ ids: [String]) throws {
        let now = Date().timeIntervalSince1970
        for id in ids {
            try run("UPDATE clipboard_items SET last_copied_at = ? WHERE id = ?;", [.double(now), .text(id)])
        }
    }

    func setTitle(_ title: String?, for id: String) throws {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let searchText = try rows("SELECT IFNULL(search_text, preview) FROM clipboard_items WHERE id = ?;", [.text(id)]) {
            Self.columnText($0, 0) ?? ""
        }.first ?? ""
        try run("UPDATE clipboard_items SET title = ?, search_key = ?, updated_at = ? WHERE id = ?;",
                [trimmed.isEmpty ? .null : .text(trimmed), .text(Self.searchKey(text: searchText, title: trimmed)),
                 .double(Date().timeIntervalSince1970), .text(id)])
    }

    func delete(_ ids: [String]) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            guard let item = try items("SELECT \(Self.columns) FROM clipboard_items WHERE id = ?;", [.text(id)]).first else { continue }
            try removePayloadIfPresent(for: item)
            try run("DELETE FROM clipboard_items WHERE id = ?;", [.text(id)])
        }
        try secureVacuum()
    }

    // MARK: - Pinboards

    func pinboards() throws -> [Pinboard] {
        try rows("SELECT id, name, position FROM pinboards ORDER BY position, id;", []) {
            Pinboard(id: sqlite3_column_int64($0, 0), name: Self.columnText($0, 1) ?? "", position: Int(sqlite3_column_int64($0, 2)))
        }
    }

    func createPinboard(name: String) throws -> Pinboard {
        let position = try rows("SELECT IFNULL(MAX(position), -1) + 1 FROM pinboards;", []) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
        try run("INSERT INTO pinboards (name, position) VALUES (?, ?);", [.text(name), .int(Int64(position))])
        return Pinboard(id: sqlite3_last_insert_rowid(database), name: name, position: position)
    }

    func renamePinboard(id: Int64, name: String) throws {
        try run("UPDATE pinboards SET name = ? WHERE id = ?;", [.text(name), .int(id)])
    }

    func deletePinboard(id: Int64) throws {
        try run("UPDATE clipboard_items SET pinboard_id = NULL, pin_order = 0 WHERE pinboard_id = ?;", [.int(id)])
        try run("DELETE FROM pinboards WHERE id = ?;", [.int(id)])
    }

    func pin(_ ids: [String], to pinboardID: Int64?) throws {
        for id in ids {
            guard let pinboardID else {
                try run("UPDATE clipboard_items SET pinboard_id = NULL, pin_order = 0 WHERE id = ?;", [.text(id)])
                continue
            }
            let order = try rows("SELECT IFNULL(MAX(pin_order), -1) + 1 FROM clipboard_items WHERE pinboard_id = ?;",
                                 [.int(pinboardID)]) { sqlite3_column_int64($0, 0) }.first ?? 0
            try run("UPDATE clipboard_items SET pinboard_id = ?, pin_order = ? WHERE id = ?;", [.int(pinboardID), .int(order), .text(id)])
        }
    }

    // MARK: - Retention

    @discardableResult
    func deleteItems(olderThan date: Date) throws -> Int {
        let cutoff = Param.double(date.timeIntervalSince1970)
        let expired = try items("SELECT \(Self.columns) FROM clipboard_items WHERE pinboard_id IS NULL AND last_copied_at < ?;", [cutoff])
        guard !expired.isEmpty else { return 0 }
        for item in expired { try removePayloadIfPresent(for: item) }
        try run("DELETE FROM clipboard_items WHERE pinboard_id IS NULL AND last_copied_at < ?;", [cutoff])
        try secureVacuum()
        return expired.count
    }

    func countItems(olderThan date: Date) throws -> Int {
        try rows("SELECT COUNT(*) FROM clipboard_items WHERE pinboard_id IS NULL AND last_copied_at < ?;",
                 [.double(date.timeIntervalSince1970)]) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }

    @discardableResult
    func eraseHistory() throws -> Int {
        let unpinned = try items("SELECT \(Self.columns) FROM clipboard_items WHERE pinboard_id IS NULL;", [])
        guard !unpinned.isEmpty else { return 0 }
        for item in unpinned { try removePayloadIfPresent(for: item) }
        try run("DELETE FROM clipboard_items WHERE pinboard_id IS NULL;", [])
        try secureVacuum()
        return unpinned.count
    }

    // MARK: - Row mapping

    private static let columns = """
        id, kind, created_at, updated_at, sha256, preview, payload_path, byte_count, source_bundle_id,
        title, pinboard_id, last_copied_at
        """

    private func item(id: String) throws -> ClipboardItem {
        guard let item = try items("SELECT \(Self.columns) FROM clipboard_items WHERE id = ?;", [.text(id)]).first else {
            throw ClipVaultError.storage("Clip not found")
        }
        return item
    }

    private static func makeItem(_ statement: OpaquePointer?) -> ClipboardItem? {
        guard
            let id = columnText(statement, 0),
            let kindValue = columnText(statement, 1),
            let kind = ClipboardKind(rawValue: kindValue),
            let sha256 = columnText(statement, 4),
            let preview = columnText(statement, 5),
            let payloadPath = columnText(statement, 6)
        else {
            return nil
        }
        return ClipboardItem(
            id: id,
            kind: kind,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
            sha256: sha256,
            preview: preview,
            payloadPath: payloadPath,
            byteCount: Int(sqlite3_column_int64(statement, 7)),
            sourceBundleID: columnText(statement, 8),
            title: columnText(statement, 9),
            pinboardID: sqlite3_column_type(statement, 10) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 10),
            lastCopiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)))
    }

    // MARK: - Payload files

    private func removePayloadIfPresent(for item: ClipboardItem) throws {
        let url = payloadURL(for: item)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func payloadURL(for item: ClipboardItem) -> URL {
        payloadDirectoryURL.appendingPathComponent(item.payloadPath)
    }

    private nonisolated static func applicationSupportURL(fileManager: FileManager) throws -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ClipVaultError.storage("Could not locate Application Support.")
        }
        return baseURL.appendingPathComponent("ClipVault", isDirectory: true)
    }

    private nonisolated static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Owner-only read/write (0600) so other local users can't read clipboard secrets.
    private nonisolated static func restrictPermissions(at url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - Schema (nonisolated so it can run from the actor's synchronous init)

    private nonisolated static func openDatabase(at path: String) throws -> OpaquePointer {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &database, flags, nil) == SQLITE_OK, let database else {
            throw ClipVaultError.storage("Could not open database")
        }
        return database
    }

    private nonisolated static func migrate(_ database: OpaquePointer?, payloadDirectory: URL) throws {
        try exec(database, "PRAGMA journal_mode = DELETE;")
        try exec(database, "PRAGMA secure_delete = ON;")
        try exec(database, "PRAGMA foreign_keys = ON;")

        try exec(database, """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            sha256 TEXT NOT NULL,
            preview TEXT NOT NULL,
            payload_path TEXT NOT NULL,
            byte_count INTEGER NOT NULL
        );
        """)
        try exec(database, """
        CREATE TABLE IF NOT EXISTS pinboards (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            position INTEGER NOT NULL DEFAULT 0
        );
        """)

        // Additive columns for existing databases (idempotent).
        let columns = try tableColumns(database, "clipboard_items")
        let added: [(String, String)] = [
            ("pinned", "INTEGER NOT NULL DEFAULT 0"),
            ("source_bundle_id", "TEXT"),
            ("payload_format", "TEXT NOT NULL DEFAULT '\(PayloadCodec.legacyFormat)'"),
            ("search_text", "TEXT"),
            ("title", "TEXT"),
            ("pinboard_id", "INTEGER"),
            ("pin_order", "INTEGER NOT NULL DEFAULT 0"),
            ("last_copied_at", "REAL"),
            ("search_key", "TEXT")
        ]
        for (name, definition) in added where !columns.contains(name) {
            try exec(database, "ALTER TABLE clipboard_items ADD COLUMN \(name) \(definition);")
        }

        // Version 1: fill the new columns for old rows, and move pinned clips to a "Pinned" pinboard.
        if userVersion(database) < 1 {
            try exec(database, "BEGIN;")
            do {
                try exec(database, "UPDATE clipboard_items SET last_copied_at = created_at WHERE last_copied_at IS NULL;")
                try exec(database, "UPDATE clipboard_items SET search_text = preview WHERE search_text IS NULL;")
                if try count(database, "SELECT COUNT(*) FROM clipboard_items WHERE pinned = 1 AND pinboard_id IS NULL;") > 0 {
                    try exec(database, "INSERT INTO pinboards (name, position) VALUES ('Pinned', 0);")
                    let board = sqlite3_last_insert_rowid(database)
                    try exec(database, """
                    UPDATE clipboard_items SET pinboard_id = \(board), pin_order = CAST(created_at AS INTEGER), pinned = 0
                    WHERE pinned = 1 AND pinboard_id IS NULL;
                    """)
                }
                try exec(database, "PRAGMA user_version = 1;")
                try exec(database, "COMMIT;")
            } catch {
                try? exec(database, "ROLLBACK;")
                throw error
            }
        }

        // Version 2: give 0.1 clips the current content hash (so re-copying them moves them to the
        // front), search the full text of 0.1 text clips, and fill the case-folded search key.
        if userVersion(database) < 2 {
            try exec(database, "BEGIN;")
            do {
                try migrateToV2(database, payloadDirectory: payloadDirectory)
                try exec(database, "PRAGMA user_version = 2;")
                try exec(database, "COMMIT;")
            } catch {
                try? exec(database, "ROLLBACK;")
                throw error
            }
        }

        try exec(database, "CREATE INDEX IF NOT EXISTS idx_clipboard_items_created_at ON clipboard_items(created_at DESC);")
        try exec(database, "CREATE INDEX IF NOT EXISTS idx_clipboard_items_last_copied ON clipboard_items(last_copied_at DESC);")
        try exec(database, "CREATE INDEX IF NOT EXISTS idx_clipboard_items_sha256 ON clipboard_items(sha256);")
        try exec(database, "CREATE INDEX IF NOT EXISTS idx_clipboard_items_pinboard ON clipboard_items(pinboard_id, pin_order);")
    }

    private nonisolated static func migrateToV2(_ database: OpaquePointer?, payloadDirectory: URL) throws {
        var select: OpaquePointer?
        let sql = "SELECT id, kind, payload_path, payload_format, IFNULL(search_text, preview), title, sha256 FROM clipboard_items;"
        guard sqlite3_prepare_v2(database, sql, -1, &select, nil) == SQLITE_OK else { throw ClipVaultError.storage("v2: select") }
        var updates: [(id: String, hash: String, searchText: String, key: String)] = []
        while sqlite3_step(select) == SQLITE_ROW {
            guard let id = columnText(select, 0), let kindValue = columnText(select, 1),
                  let kind = ClipboardKind(rawValue: kindValue), let path = columnText(select, 2) else { continue }
            var searchText = columnText(select, 4) ?? ""
            var hash = columnText(select, 6) ?? ""
            if columnText(select, 3) == PayloadCodec.legacyFormat,
               let data = try? Data(contentsOf: payloadDirectory.appendingPathComponent(path)) {
                switch kind {
                case .text, .link, .color:
                    if let text = String(data: data, encoding: .utf8) {
                        searchText = String(text.prefix(ClipboardClassifier.maxSearchLength))
                        hash = Self.hash(kind: kind, key: data)
                    }
                case .image:
                    hash = Self.hash(kind: kind, key: data)
                case .files:
                    if let paths = try? JSONDecoder().decode([String].self, from: data) {
                        hash = Self.hash(kind: kind, key: Data(paths.joined(separator: "\n").utf8))
                        searchText = paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: "\n")
                    }
                }
            }
            updates.append((id, hash, searchText, searchKey(text: searchText, title: columnText(select, 5))))
        }
        sqlite3_finalize(select)

        var update: OpaquePointer?
        guard sqlite3_prepare_v2(database, "UPDATE clipboard_items SET sha256 = ?, search_text = ?, search_key = ? WHERE id = ?;",
                                 -1, &update, nil) == SQLITE_OK else { throw ClipVaultError.storage("v2: update") }
        defer { sqlite3_finalize(update) }
        for row in updates {
            sqlite3_reset(update)
            sqlite3_bind_text(update, 1, row.hash, -1, sqliteTransient)
            sqlite3_bind_text(update, 2, row.searchText, -1, sqliteTransient)
            sqlite3_bind_text(update, 3, row.key, -1, sqliteTransient)
            sqlite3_bind_text(update, 4, row.id, -1, sqliteTransient)
            guard sqlite3_step(update) == SQLITE_DONE else { throw ClipVaultError.storage("v2: update row") }
        }
    }

    private nonisolated static func userVersion(_ database: OpaquePointer?) -> Int32 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? sqlite3_column_int(statement, 0) : 0
    }

    private nonisolated static func count(_ database: OpaquePointer?, _ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ClipVaultError.storage("Could not prepare \(sql)")
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }

    private nonisolated static func tableColumns(_ database: OpaquePointer?, _ table: String) throws -> Set<String> {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table));", -1, &statement, nil) == SQLITE_OK else {
            throw ClipVaultError.storage("Could not inspect table \(table)")
        }
        defer { sqlite3_finalize(statement) }

        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let pointer = sqlite3_column_text(statement, 1) {
                columns.insert(String(cString: pointer))
            }
        }
        return columns
    }

    private func secureVacuum() throws {
        try Self.exec(database, "PRAGMA secure_delete = ON;")
        try Self.exec(database, "VACUUM;")
    }

    // MARK: - SQLite helpers

    private enum Param {
        case text(String), int(Int64), double(Double), null
    }

    private nonisolated static func exec(_ database: OpaquePointer?, _ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &message) != SQLITE_OK {
            let details = message.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(message)
            throw ClipVaultError.storage(details)
        }
    }

    private func prepare(_ sql: String, _ params: [Param]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw error("Could not prepare statement")
        }
        for (offset, param) in params.enumerated() {
            let index = Int32(offset + 1)
            switch param {
            case .text(let value): sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
            case .int(let value): sqlite3_bind_int64(statement, index, value)
            case .double(let value): sqlite3_bind_double(statement, index, value)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        return statement
    }

    private func run(_ sql: String, _ params: [Param]) throws {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw error("Could not run statement") }
    }

    private func rows<T>(_ sql: String, _ params: [Param], map: (OpaquePointer?) -> T) throws -> [T] {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        var result: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW { result.append(map(statement)) }
        return result
    }

    private func items(_ sql: String, _ params: [Param]) throws -> [ClipboardItem] {
        try rows(sql, params, map: Self.makeItem).compactMap { $0 }
    }

    private nonisolated static func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func error(_ fallback: String) -> ClipVaultError {
        if let database, let message = sqlite3_errmsg(database) {
            return .storage(String(cString: message))
        }
        return .storage(fallback)
    }

    /// Lower-cased for any script (SQLite's LIKE only folds ASCII), so "Å" finds "å".
    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive], locale: nil)
    }

    /// What search matches against: the clip's text and its title, case-folded.
    nonisolated static func searchKey(text: String, title: String?) -> String {
        fold(text) + "\n" + fold(title ?? "")
    }

    private static func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    /// Text, links and colours share one category, so the same text is one clip whatever kind
    /// it was classified as (and it matches text clips stored by ClipVault 0.1).
    private nonisolated static func hash(kind: ClipboardKind, key: Data) -> String {
        let category: String
        switch kind {
        case .text, .link, .color: category = ClipboardKind.text.rawValue
        case .image, .files: category = kind.rawValue
        }
        var input = Data(category.utf8)
        input.append(0)
        input.append(key)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
