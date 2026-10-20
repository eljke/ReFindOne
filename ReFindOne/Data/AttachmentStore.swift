import Foundation

actor AttachmentStore {
    private let paths: AppPaths
    static let maxBytes = 20 * 1024 * 1024

    init(paths: AppPaths) { self.paths = paths }

    func save(data: Data, fileExtension: String) throws -> String {
        guard !data.isEmpty && data.count <= Self.maxBytes else { throw ReFindError.fileTooLarge }
        let ext = fileExtension.lowercased()
        guard ["jpg", "png", "heic", "pdf"].contains(ext) else { throw ReFindError.unsupportedFile }
        let name = UUID().uuidString.lowercased() + "." + ext
        guard let url = paths.attachmentURL(name) else { throw ReFindError.unsupportedFile }
        try data.write(to: url, options: .atomic)
        return name
    }

    func read(name: String) throws -> Data {
        guard let url = paths.attachmentURL(name),
              FileManager.default.fileExists(atPath: url.path) else { throw ReFindError.missingAttachment }
        return try Data(contentsOf: url)
    }

    func remove(name: String) throws {
        guard let url = paths.attachmentURL(name) else { throw ReFindError.missingAttachment }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
