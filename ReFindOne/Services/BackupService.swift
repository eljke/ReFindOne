import Foundation

/// Single-file, versioned JSON with embedded attachments. Exports are unencrypted.
/// This format favors portability and inspectability over small file size.
actor BackupService {
    static let maxBytes = 250 * 1024 * 1024
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
    private struct RestorableEntry {
        var capture: CaptureItem
        var attachment: (data: Data, extensionName: String)?
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
        let data = try encoder.encode(archive)
        guard data.count <= Self.maxBytes else { throw ReFindError.backupTooLarge }
        return data
    }

    /// Existing items are kept unchanged. Import adds only missing UUIDs.
    func restore(_ data: Data, repository: any CaptureRepository, attachments: AttachmentStore) async throws -> Int {
        guard data.count <= Self.maxBytes else { throw ReFindError.backupTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(Archive.self, from: data),
              archive.format == "refind-one", archive.version == 1,
              archive.entries.count <= 20_000 else { throw ReFindError.invalidBackup }
        var seen = Set<UUID>()
        var validated: [RestorableEntry] = []
        // Validate the complete archive before creating files or changing the database.
        for entry in archive.entries {
            guard seen.insert(entry.capture.id).inserted,
                  (entry.capture.attachmentFile == nil) == (entry.attachmentBase64 == nil) else {
                throw ReFindError.invalidBackup
            }
            if let name = entry.capture.attachmentFile, let base64 = entry.attachmentBase64 {
                guard let ext = AppPaths.attachmentExtension(name),
                      let decoded = Data(base64Encoded: base64),
                      !decoded.isEmpty, decoded.count <= AttachmentStore.maxBytes else {
                    throw ReFindError.invalidBackup
                }
                validated.append(RestorableEntry(capture: entry.capture, attachment: (decoded, ext)))
            } else {
                validated.append(RestorableEntry(capture: entry.capture, attachment: nil))
            }
        }
        let existing = Set(try await repository.allItems().map(\.id))
        var pending: [CaptureItem] = []
        var staged: [UUID: String] = [:]
        do {
            for entry in validated where !existing.contains(entry.capture.id) {
                var item = entry.capture
                item.attachmentFile = nil
                if let attachment = entry.attachment {
                    let saved = try await attachments.save(data: attachment.data, fileExtension: attachment.extensionName)
                    staged[item.id] = saved
                    item.attachmentFile = saved
                }
                pending.append(item)
            }
            let inserted = try await repository.insertMissing(pending)
            for (id, name) in staged where !inserted.contains(id) { try? await attachments.remove(name: name) }
            return inserted.count
        } catch {
            for name in staged.values { try? await attachments.remove(name: name) }
            throw error
        }
    }

    func restore(from url: URL, repository: any CaptureRepository, attachments: AttachmentStore) async throws -> Int {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 && size <= Self.maxBytes else { throw ReFindError.backupTooLarge }
        return try await restore(Data(contentsOf: url), repository: repository, attachments: attachments)
    }
}
