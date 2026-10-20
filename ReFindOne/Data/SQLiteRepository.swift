import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite)
import CSQLite
#endif

/// All database access is serialized by the actor. No ORM or remote dependency.
actor SQLiteRepository: CaptureRepository {
    private let db: SQLiteDatabase

    init(url: URL) throws {
        db = try SQLiteDatabase(url: url)
    }

    func list(query: String = "", kind: CaptureKind? = nil, favoritesOnly: Bool = false) throws -> [CaptureItem] {
        var sql = "SELECT c.* FROM captures c"
        var filters: [String] = []
        var args: [SQLValue] = []
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            if db.ftsEnabled {
                sql += " JOIN captures_fts f ON f.id = c.id"
                filters.append("captures_fts MATCH ?")
                args.append(.text(Self.ftsQuery(text)))
            } else {
                filters.append("(c.title LIKE ? OR c.note LIKE ? OR c.extracted_text LIKE ? OR c.tags_json LIKE ?)")
                let pattern = "%" + text.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_") + "%"
                args += Array(repeating: .text(pattern), count: 4)
                filters[filters.count - 1] = "(c.title LIKE ? ESCAPE '\\' OR c.note LIKE ? ESCAPE '\\' OR c.extracted_text LIKE ? ESCAPE '\\' OR c.tags_json LIKE ? ESCAPE '\\')"
            }
        }
        if let kind { filters.append("c.kind = ?"); args.append(.text(kind.rawValue)) }
        if favoritesOnly { filters.append("c.is_favorite = 1") }
        if !filters.isEmpty { sql += " WHERE " + filters.joined(separator: " AND ") }
        sql += " ORDER BY c.created_at DESC LIMIT 250"
        return try db.selectCaptures(sql: sql, args: args)
    }

    func allItems() throws -> [CaptureItem] {
        try db.selectCaptures(sql: "SELECT * FROM captures ORDER BY created_at ASC", args: [])
    }

    func item(id: UUID) throws -> CaptureItem? {
        try db.selectCaptures(sql: "SELECT * FROM captures WHERE id = ? LIMIT 1", args: [.text(id.uuidString)]).first
    }

    func existingLink(normalizedURL: String) throws -> CaptureItem? {
        try db.selectCaptures(sql: "SELECT * FROM captures WHERE normalized_url = ? LIMIT 1",
                              args: [.text(normalizedURL)]).first
    }

    func upsert(_ capture: CaptureItem) throws {
        try db.execute("BEGIN IMMEDIATE")
        do {
            try db.execute("""
                INSERT INTO captures (id, kind, title, note, extracted_text, original_url,
                  normalized_url, attachment_file, created_at, updated_at, is_favorite, tags_json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET kind=excluded.kind, title=excluded.title,
                  note=excluded.note, extracted_text=excluded.extracted_text,
                  original_url=excluded.original_url, normalized_url=excluded.normalized_url,
                  attachment_file=excluded.attachment_file, updated_at=excluded.updated_at,
                  is_favorite=excluded.is_favorite, tags_json=excluded.tags_json
                """, args: [
                    .text(capture.id.uuidString), .text(capture.kind.rawValue),
                    .text(capture.title), .text(capture.note), .text(capture.extractedText),
                    .nullable(capture.originalURL), .nullable(capture.normalizedURL),
                    .nullable(capture.attachmentFile), .double(capture.createdAt.timeIntervalSince1970),
                    .double(capture.updatedAt.timeIntervalSince1970), .int(capture.isFavorite ? 1 : 0),
                    .text(String(data: try JSONEncoder().encode(capture.tags), encoding: .utf8) ?? "[]")
                ])
            if db.ftsEnabled {
                try db.execute("DELETE FROM captures_fts WHERE id = ?", args: [.text(capture.id.uuidString)])
                try db.execute("INSERT INTO captures_fts (id, title, note, extracted_text, tags) VALUES (?, ?, ?, ?, ?)", args: [
                    .text(capture.id.uuidString), .text(capture.title), .text(capture.note),
                    .text(capture.extractedText), .text(capture.tags.joined(separator: " "))
                ])
            }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
    }

    func delete(id: UUID) throws {
        try db.execute("BEGIN IMMEDIATE")
        do {
            try db.execute("DELETE FROM captures WHERE id = ?", args: [.text(id.uuidString)])
            if db.ftsEnabled { try db.execute("DELETE FROM captures_fts WHERE id = ?", args: [.text(id.uuidString)]) }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
    }

    private static func ftsQuery(_ text: String) -> String {
        // Quote every token: avoids SQLite MATCH syntax injection and supports Cyrillic.
        // Prefix matching is intentionally disabled for stable, predictable results.
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .prefix(8)
            .map { "\"" + String($0.prefix(80)).replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            .joined(separator: " AND ")
    }
}

private enum SQLValue {
    case text(String), nullable(String?), double(Double), int(Int32)
}

private final class SQLiteDatabase {
    private var handle: OpaquePointer?
    private(set) var ftsEnabled = false
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        let result = sqlite3_open_v2(url.path, &handle,
                                    SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            handle = nil
            throw ReFindError.database(message)
        }
        sqlite3_busy_timeout(handle, 4000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA foreign_keys=ON")
        let version = Int(sqlite3_user_version())
        guard version <= 1 else { throw ReFindError.database("Неподдерживаемая версия базы: \(version)") }
        try execute("""
            CREATE TABLE IF NOT EXISTS captures (
                id TEXT PRIMARY KEY NOT NULL,
                kind TEXT NOT NULL,
                title TEXT NOT NULL,
                note TEXT NOT NULL,
                extracted_text TEXT NOT NULL,
                original_url TEXT,
                normalized_url TEXT,
                attachment_file TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0,
                tags_json TEXT NOT NULL DEFAULT '[]'
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS idx_captures_date ON captures(created_at DESC)")
        try execute("CREATE INDEX IF NOT EXISTS idx_captures_url ON captures(normalized_url)")
        // iOS ships FTS5; on an unusual SQLite build fall back to escaped LIKE.
        do {
            try execute("CREATE VIRTUAL TABLE IF NOT EXISTS captures_fts USING fts5(id UNINDEXED, title, note, extracted_text, tags, tokenize='unicode61')")
            ftsEnabled = true
            if version == 0 {
                try execute("""
                    INSERT INTO captures_fts(id, title, note, extracted_text, tags)
                    SELECT id, title, note, extracted_text, tags_json FROM captures
                    """)
            }
        } catch {
            ftsEnabled = false
        }
        try execute("PRAGMA user_version=1")
    }

    deinit { if let handle { sqlite3_close(handle) } }

    private func sqlite3_user_version() -> Int32 {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return -1 }
        return sqlite3_column_int(statement, 0)
    }

    func execute(_ sql: String, args: [SQLValue] = []) throws {
        let stmt = try prepare(sql, args: args)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw error() }
    }

    func selectCaptures(sql: String, args: [SQLValue]) throws -> [CaptureItem] {
        let stmt = try prepare(sql, args: args)
        defer { sqlite3_finalize(stmt) }
        var results: [CaptureItem] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { return results }
            guard step == SQLITE_ROW else { throw error() }
            func column(_ index: Int32) -> String? {
                guard let bytes = sqlite3_column_text(stmt, index) else { return nil }
                return String(cString: bytes)
            }
            guard let idString = column(0), let uuid = UUID(uuidString: idString),
                  let rawKind = column(1), let kind = CaptureKind(rawValue: rawKind) else {
                throw ReFindError.database("Повреждённая запись")
            }
            let tags = (column(11)?.data(using: .utf8)).flatMap {
                try? JSONDecoder().decode([String].self, from: $0)
            } ?? []
            results.append(CaptureItem(
                id: uuid, kind: kind, title: column(2) ?? "", note: column(3) ?? "",
                extractedText: column(4) ?? "", originalURL: column(5), normalizedURL: column(6),
                attachmentFile: column(7),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9)),
                isFavorite: sqlite3_column_int(stmt, 10) == 1, tags: tags))
        }
    }

    private func prepare(_ sql: String, args: [SQLValue]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { throw error() }
        do {
            for (i, value) in args.enumerated() {
                let index = Int32(i + 1)
                let result: Int32
                switch value {
                case .text(let text):
                    result = text.withCString { sqlite3_bind_text(stmt, index, $0, -1, Self.transient) }
                case .nullable(let maybe):
                    if let text = maybe {
                        result = text.withCString { sqlite3_bind_text(stmt, index, $0, -1, Self.transient) }
                    } else { result = sqlite3_bind_null(stmt, index) }
                case .double(let number): result = sqlite3_bind_double(stmt, index, number)
                case .int(let number): result = sqlite3_bind_int(stmt, index, number)
                }
                guard result == SQLITE_OK else { throw error() }
            }
            return stmt
        } catch {
            sqlite3_finalize(stmt)
            throw error
        }
    }

    private func error() -> ReFindError {
        ReFindError.database(String(cString: sqlite3_errmsg(handle)))
    }
}
