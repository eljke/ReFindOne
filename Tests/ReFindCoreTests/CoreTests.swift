import XCTest
@testable import ReFindCore

final class CoreTests: XCTestCase {
    func testURLNormalizationPreservesContentParameters() throws {
        let input = "https://Example.COM/watch?v=AB_2&utm_source=story&fbclid=123&t=74#comments"
        let output = LinkNormalizer.normalize(try XCTUnwrap(LinkNormalizer.parse(input)))
        XCTAssertEqual(output?.absoluteString, "https://example.com/watch?v=AB_2&t=74")
    }

    func testUnsafeURLNotTreatedAsLink() throws {
        XCTAssertNil(LinkNormalizer.parse("javascript:alert(1)"))
        XCTAssertNil(LinkNormalizer.parse("https://a.com@b.com/path"))
        XCTAssertNil(LinkNormalizer.parse("https://example.com with spaces"))
        XCTAssertEqual(try LinkNormalizer.capture(from: "Привет").kind, .note)
    }

    func testDatabaseRoundTripFTSAndDeletion() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try SQLiteRepository(url: folder.appendingPathComponent("items.sqlite"))
        var item = CaptureItem(kind: .image, title: "Рецепт", note: "вкусно",
                               extractedText: "Базилик и помидоры", tags: ["готовка"])
        try await repository.upsert(item)
        let results1 = try await repository.list(query: "помидоры", kind: nil, favoritesOnly: false)
        XCTAssertEqual(results1.count, 1)
        let results2 = try await repository.list(query: "базилик", kind: .note, favoritesOnly: false)
        XCTAssertEqual(results2.count, 0)
        let results3 = try await repository.list(query: "готовка", kind: nil, favoritesOnly: false)
        XCTAssertEqual(results3.count, 1)
        item.isFavorite = true
        item.note = "Новый комментарий"
        try await repository.upsert(item)
        let results4 = try await repository.list(query: "", kind: nil, favoritesOnly: true)
        XCTAssertEqual(results4.count, 1)
        let results5 = try await repository.list(query: "помидоры", kind: nil, favoritesOnly: false)
        XCTAssertEqual(results5.count, 1)
        let observed89 = try await repository.item(id: item.id)?.note
        XCTAssertEqual(observed89, "Новый комментарий")
        try await repository.delete(id: item.id)
        let results6 = try await repository.list(query: "помидоры", kind: nil, favoritesOnly: false)
        XCTAssertEqual(results6.count, 0)
    }

    func testSqlFTSInjectionIsTreatedAsText() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = try SQLiteRepository(url: folder.appendingPathComponent("db.sqlite"))
        try await repo.upsert(CaptureItem(kind: .note, title: "Nothing"))
        _ = try await repo.list(query: "\" OR kind:link --", kind: nil, favoritesOnly: false)
    }
}

extension CoreTests {
    func testBackupRestoresFullTextAndAttachment() async throws {
        let first = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let second = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let sourcePaths = try AppPaths(root: first)
        let targetPaths = try AppPaths(root: second)
        let sourceDB = try SQLiteRepository(url: sourcePaths.database)
        let targetDB = try SQLiteRepository(url: targetPaths.database)
        let sourceFiles = AttachmentStore(paths: sourcePaths)
        let targetFiles = AttachmentStore(paths: targetPaths)
        let bytes = Data([0x89, 0x50, 0x4e, 0x47, 0x41, 0x42, 0x43])
        let name = try await sourceFiles.save(data: bytes, fileExtension: "png")
        let original = CaptureItem(kind: .image, title: "Заметки о поездах",
                                   extractedText: "Станция Амстердам", attachmentFile: name)
        try await sourceDB.upsert(original)
        let archive = try await BackupService().export(repository: sourceDB, attachments: sourceFiles)
        let count = try await BackupService().restore(archive, repository: targetDB, attachments: targetFiles)
        XCTAssertEqual(count, 1)
        let restored = try await targetDB.item(id: original.id)
        XCTAssertEqual(restored?.extractedText, original.extractedText)
        let restoredName = try XCTUnwrap(restored?.attachmentFile)
        let restoredBytes = try await targetFiles.read(name: restoredName)
        XCTAssertEqual(restoredBytes, bytes)
        let secondCount = try await BackupService().restore(archive, repository: targetDB, attachments: targetFiles)
        XCTAssertEqual(secondCount, 0)
    }

    func testBackupRejectsInvalidInputAndAttachmentPaths() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = try AppPaths(root: dir)
        let repo = try SQLiteRepository(url: paths.database)
        let store = AttachmentStore(paths: paths)
        do {
            _ = try await BackupService().restore(Data("{}".utf8), repository: repo, attachments: store)
            XCTFail("Expected invalid backup")
        } catch ReFindError.invalidBackup { /* expected */ }
        XCTAssertNil(paths.attachmentURL("../../secret.png"))
        XCTAssertNil(paths.attachmentURL("test.png"))
    }
}

extension CoreTests {
    func testRepositorySurvivesReopenAndFindsDuplicateURL() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let dbPath = directory.appendingPathComponent("records.sqlite")
        let url = "https://example.com/page?id=11"
        let item = CaptureItem(kind: .link, title: "Документация",
                               originalURL: url, normalizedURL: url)
        let writer = try SQLiteRepository(url: dbPath)
        try await writer.upsert(item)
        let reader = try SQLiteRepository(url: dbPath)
        let found = try await reader.existingLink(normalizedURL: url)
        XCTAssertEqual(found?.id, item.id)
        let foundBySearch = try await reader.list(query: "Документация", kind: .link, favoritesOnly: false)
        XCTAssertEqual(foundBySearch.first?.title, "Документация")
    }
}
