import CryptoKit
import Foundation
import SQLite3

/// SQLite-backed clipboard store. An actor so all database and payload-file I/O runs off the
/// main thread; the `sqlite3` handle stays actor-isolated.
actor SQLiteClipStore: ClipStore {
    private let databaseURL: URL
    private let payloadDirectoryURL: URL
    private var database: OpaquePointer?

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
        try Self.migrate(database)
        Self.restrictPermissions(at: databaseURL)
    }

    deinit {
        sqlite3_close(database)
    }

    // MARK: - ClipStore

    func fetchItems(limit: Int = 250, query: String? = nil) throws -> [ClipboardItem] {
        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuery = !(trimmed?.isEmpty ?? true)

        var sql = """
        SELECT \(Self.columns)
        FROM clipboard_items
        """
        if hasQuery {
            sql += "\nWHERE preview LIKE ? ESCAPE '\\'"
        }
        sql += "\nORDER BY pinned DESC, created_at DESC\nLIMIT ?;"

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        var index: Int32 = 1
        if hasQuery, let trimmed {
            bind(statement, index, "%\(Self.escapeLike(trimmed))%")
            index += 1
        }
        sqlite3_bind_int(statement, index, Int32(limit))

        var items: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let item = item(from: statement) {
                items.append(item)
            }
        }
        return items
    }

    @discardableResult
    func save(_ capture: ClipboardCapture, sourceBundleID: String?) throws -> Bool {
        try save(capture, sourceBundleID: sourceBundleID, at: Date())
    }

    /// `date` is only overridden by demo mode, to give sample clips realistic ages.
    @discardableResult
    func save(_ capture: ClipboardCapture, sourceBundleID: String?, at date: Date) throws -> Bool {
        let hash = Self.hash(kind: capture.kind, data: capture.data)
        if try latestHash() == hash {
            return false
        }

        let id = UUID().uuidString
        let fileName = "\(id).\(capture.fileExtension)"
        let payloadURL = payloadDirectoryURL.appendingPathComponent(fileName)
        try capture.data.write(to: payloadURL, options: .atomic)
        Self.restrictPermissions(at: payloadURL)

        let now = date.timeIntervalSince1970
        let sql = """
        INSERT INTO clipboard_items
        (id, kind, created_at, updated_at, sha256, preview, payload_path, byte_count, pinned, source_bundle_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?);
        """

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        bind(statement, 1, id)
        bind(statement, 2, capture.kind.rawValue)
        sqlite3_bind_double(statement, 3, now)
        sqlite3_bind_double(statement, 4, now)
        bind(statement, 5, hash)
        bind(statement, 6, capture.preview)
        bind(statement, 7, fileName)
        sqlite3_bind_int64(statement, 8, Int64(capture.data.count))
        bindOptional(statement, 9, sourceBundleID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            try? FileManager.default.removeItem(at: payloadURL)
            throw error("Could not insert clipboard item")
        }

        return true
    }

    func payloadData(for item: ClipboardItem) throws -> Data {
        try Data(contentsOf: payloadURL(for: item))
    }

    func setPinned(_ pinned: Bool, for item: ClipboardItem) throws {
        let statement = try prepare("UPDATE clipboard_items SET pinned = ?, updated_at = ? WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, pinned ? 1 : 0)
        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        bind(statement, 3, item.id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw error("Could not update pin state")
        }
    }

    func delete(_ item: ClipboardItem) throws {
        try removePayloadIfPresent(for: item)

        let statement = try prepare("DELETE FROM clipboard_items WHERE id = ?;")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, item.id)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw error("Could not delete clipboard item")
        }

        try secureVacuum()
    }

    func deleteItems(olderThan date: Date) throws {
        let expiredItems = try fetchExpiredItems(olderThan: date)
        guard !expiredItems.isEmpty else { return }

        for item in expiredItems {
            try removePayloadIfPresent(for: item)
        }

        // Pinned items never expire.
        let statement = try prepare("DELETE FROM clipboard_items WHERE created_at < ? AND pinned = 0;")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw error("Could not delete expired clipboard items")
        }

        try secureVacuum()
    }

    // MARK: - Row mapping

    private static let columns =
        "id, kind, created_at, updated_at, sha256, preview, payload_path, byte_count, pinned, source_bundle_id"

    private func item(from statement: OpaquePointer?) -> ClipboardItem? {
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
            pinned: sqlite3_column_int(statement, 8) != 0,
            sourceBundleID: columnText(statement, 9)
        )
    }

    private func fetchExpiredItems(olderThan date: Date) throws -> [ClipboardItem] {
        let sql = """
        SELECT \(Self.columns)
        FROM clipboard_items
        WHERE created_at < ? AND pinned = 0
        ORDER BY created_at DESC;
        """

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)

        var items: [ClipboardItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let item = item(from: statement) {
                items.append(item)
            }
        }
        return items
    }

    private func latestHash() throws -> String? {
        let statement = try prepare("SELECT sha256 FROM clipboard_items ORDER BY created_at DESC LIMIT 1;")
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            return columnText(statement, 0)
        }
        return nil
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

    private static func applicationSupportURL(fileManager: FileManager) throws -> URL {
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

    private nonisolated static func migrate(_ database: OpaquePointer?) throws {
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

        // Additive columns for existing databases (idempotent).
        let columns = try tableColumns(database, "clipboard_items")
        if !columns.contains("pinned") {
            try exec(database, "ALTER TABLE clipboard_items ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;")
        }
        if !columns.contains("source_bundle_id") {
            try exec(database, "ALTER TABLE clipboard_items ADD COLUMN source_bundle_id TEXT;")
        }

        try exec(database, """
        CREATE INDEX IF NOT EXISTS idx_clipboard_items_created_at
        ON clipboard_items(created_at DESC);
        """)
        try exec(database, """
        CREATE INDEX IF NOT EXISTS idx_clipboard_items_pinned
        ON clipboard_items(pinned DESC, created_at DESC);
        """)
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
        try execute("PRAGMA secure_delete = ON;")
        try execute("VACUUM;")
    }

    // MARK: - SQLite helpers

    private nonisolated static func exec(_ database: OpaquePointer?, _ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(database, sql, nil, nil, &message) != SQLITE_OK {
            let details = message.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(message)
            throw ClipVaultError.storage(details)
        }
    }

    private func execute(_ sql: String) throws {
        try Self.exec(database, sql)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw error("Could not prepare statement")
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
    }

    private func bindOptional(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    private func error(_ fallback: String) -> ClipVaultError {
        if let database, let message = sqlite3_errmsg(database) {
            return .storage(String(cString: message))
        }
        return .storage(fallback)
    }

    private static func escapeLike(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func hash(kind: ClipboardKind, data: Data) -> String {
        var input = Data(kind.rawValue.utf8)
        input.append(0)
        input.append(data)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
