import Foundation

/// The domain model has no dependencies on UIKit, SwiftUI, or the persistence layer.
enum CaptureKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case link, image, document, note
    var id: String { rawValue }

    var title: String {
        switch self {
        case .link: "Ссылки"
        case .image: "Скриншоты"
        case .document: "Документы"
        case .note: "Заметки"
        }
    }

    var symbol: String {
        switch self {
        case .link: "link"
        case .image: "photo"
        case .document: "doc.text"
        case .note: "note.text"
        }
    }
}

struct CaptureItem: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var kind: CaptureKind
    var title: String
    var note: String
    var extractedText: String
    var originalURL: String?
    var normalizedURL: String?
    /// Private, generated filename; never an untrusted imported path.
    var attachmentFile: String?
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var tags: [String]

    init(id: UUID = UUID(), kind: CaptureKind, title: String,
         note: String = "", extractedText: String = "",
         originalURL: String? = nil, normalizedURL: String? = nil,
         attachmentFile: String? = nil, createdAt: Date = .now,
         updatedAt: Date = .now, isFavorite: Bool = false,
         tags: [String] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.note = note
        self.extractedText = extractedText
        self.originalURL = originalURL
        self.normalizedURL = normalizedURL
        self.attachmentFile = attachmentFile
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.tags = tags
    }
}

enum ReFindError: LocalizedError, Sendable {
    case emptyInput
    case fileTooLarge
    case unsupportedFile
    case invalidBackup
    case missingAttachment
    case database(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .emptyInput: "Добавь ссылку или текст."
        case .fileTooLarge: "Файл слишком большой (предел — 20 МБ)."
        case .unsupportedFile: "Пока поддерживаются JPEG, PNG, HEIC, PDF и TXT."
        case .invalidBackup: "Не удалось прочитать резервную копию ReFind One."
        case .missingAttachment: "Файл вложения не найден."
        case .database(let message): "Ошибка базы данных: \(message)"
        case .unavailable: "Хранилище недоступно."
        }
    }
}
