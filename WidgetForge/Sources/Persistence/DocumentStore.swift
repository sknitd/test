import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

/// A tiny document database: named collections of JSON documents keyed by id.
protocol DocumentStore: AnyObject {
    func put(_ collection: String, id: String, data: Data) throws
    func get(_ collection: String, id: String) throws -> Data?
    func all(_ collection: String) throws -> [(id: String, data: Data)]
    func delete(_ collection: String, id: String) throws
    func deleteAll(_ collection: String) throws
}

extension DocumentStore {
    func save<T: Encodable>(_ value: T, in collection: String, id: String) throws {
        try put(collection, id: id, data: JSONEncoder().encode(value))
    }

    func load<T: Decodable>(_ type: T.Type, from collection: String, id: String) throws -> T? {
        try get(collection, id: id).map { try JSONDecoder().decode(T.self, from: $0) }
    }

    /// Loads every document that still decodes; undecodable rows are reported instead of aborting the load,
    /// so one corrupt widget can never take the whole desktop down with it.
    func loadAll<T: Decodable>(_ type: T.Type, from collection: String, onError: ((String, Error) -> Void)? = nil) throws -> [T] {
        try all(collection).compactMap { row in
            do { return try JSONDecoder().decode(T.self, from: row.data) }
            catch { onError?(row.id, error); return nil }
        }
    }
}

enum Collections {
    static let widgets = "widgets"
    static let trash = "trash"
    static let layouts = "layouts"
    static let profiles = "profiles"
    static let automations = "automations"
    static let dataCache = "dataCache"
    static let library = "library"
    static let settings = "settings"
    static let bookmarks = "bookmarks"
    static let sources = "sources"
}

final class InMemoryDocumentStore: DocumentStore {
    private var storage: [String: [String: Data]] = [:]
    private let lock = NSLock()

    init() {}

    func put(_ collection: String, id: String, data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        storage[collection, default: [:]][id] = data
    }

    func get(_ collection: String, id: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[collection]?[id]
    }

    func all(_ collection: String) throws -> [(id: String, data: Data)] {
        lock.lock(); defer { lock.unlock() }
        return (storage[collection] ?? [:]).sorted { $0.key < $1.key }.map { (id: $0.key, data: $0.value) }
    }

    func delete(_ collection: String, id: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[collection]?[id] = nil
    }

    func deleteAll(_ collection: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[collection] = nil
    }
}

#if canImport(SQLite3)
struct SQLiteError: Error, LocalizedError {
    var message: String
    var errorDescription: String? { "SQLite: \(message)" }
}

/// SQLite-backed store (WAL mode) used by the app. One table, `documents(collection, id, body, updated)`.
final class SQLiteDocumentStore: DocumentStore {
    private var db: OpaquePointer?
    private let lock = NSLock()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    let url: URL

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database"
            sqlite3_close(db)
            throw SQLiteError(message: message)
        }
        sqlite3_busy_timeout(db, 2000)
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try exec("""
            CREATE TABLE IF NOT EXISTS documents (
                collection TEXT NOT NULL,
                id TEXT NOT NULL,
                body BLOB NOT NULL,
                updated REAL NOT NULL,
                PRIMARY KEY (collection, id)
            );
            """)
    }

    deinit { sqlite3_close(db) }

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(error)
            throw SQLiteError(message: message)
        }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        return try body(statement)
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ text: String) {
        sqlite3_bind_text(statement, index, text, -1, SQLiteDocumentStore.transient)
    }

    private func step(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw SQLiteError(message: String(cString: sqlite3_errmsg(db))) }
    }

    func put(_ collection: String, id: String, data: Data) throws {
        try withStatement("INSERT INTO documents (collection, id, body, updated) VALUES (?, ?, ?, ?) ON CONFLICT(collection, id) DO UPDATE SET body = excluded.body, updated = excluded.updated;") { s in
            bind(s, 1, collection)
            bind(s, 2, id)
            _ = data.withUnsafeBytes { sqlite3_bind_blob(s, 3, $0.baseAddress, Int32(data.count), SQLiteDocumentStore.transient) }
            sqlite3_bind_double(s, 4, Date().timeIntervalSince1970)
            try step(s)
        }
    }

    private func blob(_ statement: OpaquePointer, _ column: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    func get(_ collection: String, id: String) throws -> Data? {
        try withStatement("SELECT body FROM documents WHERE collection = ? AND id = ?;") { s in
            bind(s, 1, collection)
            bind(s, 2, id)
            return sqlite3_step(s) == SQLITE_ROW ? blob(s, 0) : nil
        }
    }

    func all(_ collection: String) throws -> [(id: String, data: Data)] {
        try withStatement("SELECT id, body FROM documents WHERE collection = ? ORDER BY id;") { s in
            bind(s, 1, collection)
            var rows: [(id: String, data: Data)] = []
            while sqlite3_step(s) == SQLITE_ROW {
                let id = sqlite3_column_text(s, 0).map { String(cString: $0) } ?? ""
                rows.append((id: id, data: blob(s, 1)))
            }
            return rows
        }
    }

    func delete(_ collection: String, id: String) throws {
        try withStatement("DELETE FROM documents WHERE collection = ? AND id = ?;") { s in
            bind(s, 1, collection)
            bind(s, 2, id)
            try step(s)
        }
    }

    func deleteAll(_ collection: String) throws {
        try withStatement("DELETE FROM documents WHERE collection = ?;") { s in
            bind(s, 1, collection)
            try step(s)
        }
    }
}
#endif
