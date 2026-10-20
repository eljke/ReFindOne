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
    var archivedAt: Date?

    var isArchived: Bool { archivedAt != nil }

    func snippet(matching query: String) -> String {
        let sources = [note, extractedText, normalizedURL ?? originalURL ?? "", tags.joined(separator: ", ")]
        let words = query.split(whereSeparator: \.isWhitespace).prefix(8).map(String.init)
        for source in sources where !source.isEmpty {
            for word in words {
                if let match = source.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                    let start = source.index(match.lowerBound, offsetBy: -35, limitedBy: source.startIndex) ?? source.startIndex
                    let end = source.index(start, offsetBy: 160, limitedBy: source.endIndex) ?? source.endIndex
                    return (start == source.startIndex ? "" : "…") +
                        source[start..<end].replacingOccurrences(of: "\n", with: " ") +
                        (end == source.endIndex ? "" : "…")
                }
            }
        }
        return String((sources.first { !$0.isEmpty } ?? "").prefix(160)).replacingOccurrences(of: "\n", with: " ")
    }

    init(id: UUID = UUID(), kind: CaptureKind, title: String,
         note: String = "", extractedText: String = "",
         originalURL: String? = nil, normalizedURL: String? = nil,
         attachmentFile: String? = nil, createdAt: Date = .now,
         updatedAt: Date = .now, isFavorite: Bool = false,
         tags: [String] = [], archivedAt: Date? = nil) {
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
        self.archivedAt = archivedAt
    }
}

enum CaptureCollection: String, CaseIterable, Identifiable {
    case inbox, favorites, archive, all
    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "Входящие"
        case .favorites: "Избранное"
        case .archive: "Архив"
        case .all: "Всё"
        }
    }

    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .favorites: "star"
        case .archive: "archivebox"
        case .all: "square.stack"
        }
    }
}

enum CaptureSort: String, CaseIterable, Identifiable, Sendable {
    case newest, oldest
    var id: String { rawValue }
    var title: String { self == .newest ? "Сначала новые" : "Сначала старые" }
}

enum ReFindError: LocalizedError, Sendable {
    case emptyInput
    case fileTooLarge
    case unsupportedFile
    case invalidBackup
    case missingAttachment
    case database(String)
    case unavailable
    case captureNotFound
    case backupTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyInput: "Добавь ссылку или текст."
        case .fileTooLarge: "Файл слишком большой (предел — 20 МБ)."
        case .unsupportedFile: "Пока поддерживаются JPEG, PNG, HEIC, PDF и TXT."
        case .invalidBackup: "Не удалось прочитать резервную копию ReFind One."
        case .missingAttachment: "Файл вложения не найден."
        case .database(let message): "Ошибка базы данных: \(message)"
        case .unavailable: "Хранилище недоступно."
        case .captureNotFound: "Запись уже удалена. Вернись в библиотеку."
        case .backupTooLarge: "Размер резервной копии превышает 250 МБ."
        }
    }
}
