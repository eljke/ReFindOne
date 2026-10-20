import Foundation
import PDFKit

/// Reads user-picked files off the main actor. All permissions are held during reading.
actor FileImportService {
    enum Imported: Sendable {
        case image(Data, extensionName: String, title: String)
        case text(String, title: String)
        case pdf(Data, extractedText: String, title: String)
    }

    func load(from url: URL) throws -> Imported {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }

        let extensionName = url.pathExtension.lowercased()
        guard ["jpg", "jpeg", "png", "heic", "heif", "pdf", "txt"].contains(extensionName) else {
            throw ReFindError.unsupportedFile
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 && size <= AttachmentStore.maxBytes else { throw ReFindError.fileTooLarge }
        let data = try Data(contentsOf: url)
        let title = url.deletingPathExtension().lastPathComponent

        switch extensionName {
        case "jpg", "jpeg", "png", "heic", "heif":
            let ext = extensionName == "jpeg" ? "jpg" : (extensionName == "heif" ? "heic" : extensionName)
            return .image(data, extensionName: ext, title: title)
        case "txt":
            guard let text = String(data: data, encoding: .utf8) else { throw ReFindError.unsupportedFile }
            return .text(String(text.prefix(200_000)), title: title)
        case "pdf":
            guard let doc = PDFDocument(data: data) else { throw ReFindError.unsupportedFile }
            let content = String((doc.string ?? "").prefix(500_000))
            return .pdf(data, extractedText: content, title: title)
        default: throw ReFindError.unsupportedFile
        }
    }
}
