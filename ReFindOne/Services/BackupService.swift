import Foundation

/// Single-file, versioned JSON with embedded attachments. Exports are unencrypted.
/// This format favors portability and inspectability over small file size.
struct BackupService {
    private struct Archive: Codable {
        var format: String
        var version: Int
        var exportedAt: Date
        var entries: [Entry]
    }
    private struct Entry: Codable {
        var capture: CaptureItem
        var attachmentBase64: String?
    }

    func export(repository: any CaptureRepository, attachments: AttachmentStore) async throws -> Data {
        let captures = try await repository.allItems()
        var entries: [Entry] = []
        for capture in captures {
            let encoded: String?
            if let name = capture.attachmentFile {
                encoded = try await attachments.read(name: name).base64EncodedString()
            } else { encoded = nil }
            entries.append(Entry(capture: capture, attachmentBase64: encoded))
        }
        let archive = Archive(format: "refind-one", version: 1, exportedAt: .now, entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    /// Existing items are kept unchanged. Import adds only missing UUIDs.
    func restore(_ data: Data, repository: any CaptureRepository, attachments: AttachmentStore) async throws -> Int {
        guard data.count <= 250 * 1024 * 1024 else { throw ReFindError.fileTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(Archive.self, from: data),
              archive.format == "refind-one", archive.version == 1,
              archive.entries.count <= 20_000 else { throw ReFindError.invalidBackup }
        var inserted = 0
        for entry in archive.entries {
            if try await repository.item(id: entry.capture.id) != nil { continue }
            var item = entry.capture
            item.attachmentFile = nil // Never trust filenames/paths from an imported archive.
            if let base64 = entry.attachmentBase64 {
                guard let decoded = Data(base64Encoded: base64),
                      !decoded.isEmpty, decoded.count <= AttachmentStore.maxBytes,
                      let extensionFromArchive = entry.capture.attachmentFile?.split(separator: ".").last,
                      ["jpg", "png", "heic", "pdf"].contains(String(extensionFromArchive)) else {
                    throw ReFindError.invalidBackup
                }
                item.attachmentFile = try await attachments.save(data: decoded, fileExtension: String(extensionFromArchive))
            }
            do {
                try await repository.upsert(item)
                inserted += 1
            } catch {
                if let name = item.attachmentFile { try? await attachments.remove(name: name) }
                throw error
            }
        }
        return inserted
    }
}
