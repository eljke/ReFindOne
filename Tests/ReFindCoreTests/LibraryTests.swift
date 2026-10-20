import XCTest
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif
@testable import ReFindCore

final class LibraryTests: XCTestCase {
    func testPrefixSearchAndArchiveFilters() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = try AppPaths(root: dir)
        let repo = try SQLiteRepository(url: paths.database)
        let item = CaptureItem(kind: .note, title: "Рецепт пасты", note: "Помидоры и базилик")
        try await repo.upsert(item)
        let found = try await repo.list(query: "помид баз", archived: false)
        XCTAssertEqual(found.map(\.id), [item.id])
        _ = try await repo.setArchived(id: item.id, archived: true)
        let inbox = try await repo.list(archived: false)
        let archive = try await repo.list(query: "помид", archived: true)
        XCTAssertTrue(inbox.isEmpty)
        XCTAssertEqual(archive.map(\.id), [item.id])
        _ = try await repo.setArchived(id: item.id, archived: false)
        let restored = try await repo.list(archived: false)
        XCTAssertEqual(restored.map(\.id), [item.id])
        let punctuation = try await repo.list(query: "*** \" --")
        XCTAssertTrue(punctuation.isEmpty)
    }

    func testPagesHaveNoGapsOrDuplicates() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = try AppPaths(root: dir)
        let repo = try SQLiteRepository(url: paths.database)
        let date = Date(timeIntervalSince1970: 1_000)
        let items = (0..<270).map { CaptureItem(kind: .note, title: "Запись \($0)", createdAt: date) }
        for item in items { try await repo.upsert(item) }
        var ids: [UUID] = []
        for offset in stride(from: 0, to: 300, by: 60) {
            ids += try await repo.list(limit: 60, offset: offset).map(\.id)
        }
        XCTAssertEqual(ids.count, 270)
        XCTAssertEqual(Set(ids), Set(items.map(\.id)))
        let reverse = try await repo.list(sort: .oldest, limit: 270)
        XCTAssertEqual(reverse.map(\.id), Array(ids.reversed()))
    }

    func testEditingPreservesFavoriteAndArchive() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = try AppPaths(root: dir)
        let repo = try SQLiteRepository(url: paths.database)
        let item = CaptureItem(kind: .note, title: "До")
        try await repo.upsert(item)
        _ = try await repo.toggleFavorite(id: item.id)
        _ = try await repo.setArchived(id: item.id, archived: true)
        let edited = try await repo.updateDetails(id: item.id, title: "После", note: "Текст", tags: ["работа"])
        XCTAssertTrue(edited.isFavorite)
        XCTAssertTrue(edited.isArchived)
        XCTAssertEqual(edited.title, "После")
        try await repo.delete(id: item.id)
        do {
            _ = try await repo.updateDetails(id: item.id, title: "Не воскрешать", note: "", tags: [])
            XCTFail("Expected missing capture")
        } catch ReFindError.captureNotFound { /* expected */ }
    }

    func testMigrationPreservesVersionOneData() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = try AppPaths(root: dir)
        let id = UUID()
        try executeSQL(at: paths.database, sql: """
            CREATE TABLE captures (
                id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL, title TEXT NOT NULL,
                note TEXT NOT NULL, extracted_text TEXT NOT NULL, original_url TEXT,
                normalized_url TEXT, attachment_file TEXT, created_at REAL NOT NULL,
                updated_at REAL NOT NULL, is_favorite INTEGER NOT NULL DEFAULT 0,
                tags_json TEXT NOT NULL DEFAULT '[]'
            );
            INSERT INTO captures VALUES ('\(id.uuidString)', 'note', 'Старая заметка',
                'Непотерянный текст', '', NULL, NULL, NULL, 1000, 1000, 1, '[]');
            PRAGMA user_version=1;
            """)
        let repo = try SQLiteRepository(url: paths.database)
        let item = try await repo.item(id: id)
        XCTAssertEqual(item?.note, "Непотерянный текст")
        XCTAssertEqual(item?.isFavorite, true)
        XCTAssertEqual(item?.isArchived, false)
        let found = try await repo.list(query: "непотерян")
        XCTAssertEqual(found.map(\.id), [id])
        _ = try await repo.setArchived(id: id, archived: true)
        let reopened = try SQLiteRepository(url: paths.database)
        let archived = try await reopened.item(id: id)
        XCTAssertEqual(archived?.isArchived, true)
    }

    func testRestoreRollsBackAllRecordsAndAttachments() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try AppPaths(root: dir.appendingPathComponent("source"))
        let target = try AppPaths(root: dir.appendingPathComponent("target"))
        let sourceDB = try SQLiteRepository(url: source.database)
        let targetDB = try SQLiteRepository(url: target.database)
        let sourceFiles = AttachmentStore(paths: source)
        let targetFiles = AttachmentStore(paths: target)
        for title in ["Принять", "Отклонить"] {
            let name = try await sourceFiles.save(data: Data([1, 2, 3]), fileExtension: "png")
            try await sourceDB.upsert(CaptureItem(kind: .image, title: title, attachmentFile: name))
        }
        let data = try await BackupService().export(repository: sourceDB, attachments: sourceFiles)
        try executeSQL(at: target.database, sql: """
            CREATE TRIGGER reject_capture BEFORE INSERT ON captures
            WHEN NEW.title = 'Отклонить' BEGIN SELECT RAISE(ABORT, 'disk write failed'); END;
            """)
        do {
            _ = try await BackupService().restore(data, repository: targetDB, attachments: targetFiles)
            XCTFail("Expected restore failure")
        } catch ReFindError.database { /* expected */ }
        let records = try await targetDB.allItems()
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.attachments.path).isEmpty)
    }

    func testRestoreRejectsMissingAttachmentBeforeAddingRecords() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = try AppPaths(root: dir)
        let repo = try SQLiteRepository(url: paths.database)
        let files = AttachmentStore(paths: paths)
        let name = try await files.save(data: Data([1]), fileExtension: "png")
        try await repo.upsert(CaptureItem(kind: .image, title: "Фото", attachmentFile: name))
        let data = try await BackupService().export(repository: repo, attachments: files)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "attachmentBase64")
        json["entries"] = entries
        let invalid = try JSONSerialization.data(withJSONObject: json)
        do {
            _ = try await BackupService().restore(invalid, repository: repo, attachments: files)
            XCTFail("Expected invalid backup")
        } catch ReFindError.invalidBackup { /* expected */ }
        let records = try await repo.allItems()
        XCTAssertEqual(records.count, 1)
    }

    private func executeSQL(at url: URL, sql: String) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw ReFindError.database(String(cString: sqlite3_errmsg(handle)))
        }
    }
}
