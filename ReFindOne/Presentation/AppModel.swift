import Foundation
import Combine
import UIKit

/// Presentation state lives on MainActor; slow DB operations use the repository actor.
@MainActor
final class AppModel: ObservableObject {
    @Published var items: [CaptureItem] = []
    @Published var searchText = ""
    @Published var selectedKind: CaptureKind?
    @Published var favoritesOnly = false
    @Published var isBusy = false
    @Published var alertMessage: String?
    @Published var infoMessage: String?

    private let paths: AppPaths?
    private let repository: (any CaptureRepository)?
    private let attachments: AttachmentStore?
    private let ocr = OCRService()
    private let backup = BackupService()
    private let fileImportService = FileImportService()
    private var searchGeneration = 0

    /// Inject a repository in previews or UI tests; production uses SQLite.
    init(repository injected: (any CaptureRepository)? = nil, storagePaths: AppPaths? = nil) {
        var resolvedPaths: AppPaths?
        var resolvedRepository: (any CaptureRepository)?
        var resolvedAttachments: AttachmentStore?
        var startupError: String?
        do {
            let selectedPaths = try storagePaths ?? AppPaths()
            // Build every dependency before assigning immutable properties.
            let selectedRepository: any CaptureRepository
            if let injected { selectedRepository = injected }
            else { selectedRepository = try SQLiteRepository(url: selectedPaths.database) }
            resolvedPaths = selectedPaths
            resolvedRepository = selectedRepository
            resolvedAttachments = AttachmentStore(paths: selectedPaths)
        } catch {
            startupError = error.localizedDescription
        }
        paths = resolvedPaths
        repository = resolvedRepository
        attachments = resolvedAttachments
        if let startupError { alertMessage = startupError }
    }

    var filterSignature: String {
        "\(searchText)|\(selectedKind?.rawValue ?? "all")|\(favoritesOnly)"
    }

    func reload() async {
        guard let repository else { return }
        searchGeneration += 1
        let generation = searchGeneration
        do {
            let result = try await repository.list(query: searchText,
                                                   kind: selectedKind, favoritesOnly: favoritesOnly)
            if generation == searchGeneration { items = result }
        } catch { if generation == searchGeneration { alertMessage = error.localizedDescription } }
    }

    func addText(_ input: String, title: String? = nil) async -> Bool {
        guard let repository else { alertMessage = ReFindError.unavailable.localizedDescription; return false }
        isBusy = true
        defer { isBusy = false }
        do {
            let capture = try LinkNormalizer.capture(from: input, title: title)
            if let normalized = capture.normalizedURL,
               try await repository.existingLink(normalizedURL: normalized) != nil {
                infoMessage = "Эта ссылка уже сохранена"
                return true
            }
            try await repository.upsert(capture)
            infoMessage = "Сохранено в библиотеку"
            await reload()
            return true
        } catch { alertMessage = error.localizedDescription; return false }
    }

    func importImage(data: Data, fileExtension: String = "jpg", title: String = "Скриншот") async {
        guard let repository, let attachments else { alertMessage = ReFindError.unavailable.localizedDescription; return }
        isBusy = true
        defer { isBusy = false }
        do {
            guard UIImage(data: data) != nil else { throw ReFindError.unsupportedFile }
            let recognized = (try? await ocr.extract(from: data)) ?? ""
            let savedName = try await attachments.save(data: data, fileExtension: fileExtension)
            let capture = CaptureItem(kind: .image, title: title,
                                      extractedText: recognized, attachmentFile: savedName)
            do { try await repository.upsert(capture) }
            catch { try? await attachments.remove(name: savedName); throw error }
            infoMessage = recognized.isEmpty ? "Фото сохранено (текст не обнаружен)" : "Текст распознан и доступен в поиске"
            await reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func importFile(from fileURL: URL) async {
        isBusy = true
        defer { isBusy = false }
        do {
            switch try await fileImportService.load(from: fileURL) {
            case .image(let data, let ext, let title):
                await importImage(data: data, fileExtension: ext, title: title)
            case .text(let text, let title):
                _ = await addText(text, title: title)
            case .pdf(let data, let extractedText, let title):
                try await importPDF(data: data, extractedText: extractedText, title: title)
            }
        } catch { alertMessage = error.localizedDescription }
    }

    private func importPDF(data: Data, extractedText: String, title: String) async throws {
        guard let repository, let attachments else { throw ReFindError.unavailable }
        let filename = try await attachments.save(data: data, fileExtension: "pdf")
        let capture = CaptureItem(kind: .document, title: title,
                                  extractedText: extractedText, attachmentFile: filename)
        do { try await repository.upsert(capture) }
        catch { try? await attachments.remove(name: filename); throw error }
        infoMessage = extractedText.isEmpty ? "PDF сохранён (текст не обнаружен)" : "PDF сохранён и проиндексирован"
        await reload()
    }

    func toggleFavorite(_ item: CaptureItem) async {
        guard let repository else { return }
        do {
            var updated = item
            updated.isFavorite.toggle()
            updated.updatedAt = .now
            try await repository.upsert(updated)
            await reload()
        } catch { alertMessage = error.localizedDescription }
    }

    func saveChanges(_ item: CaptureItem, title: String, note: String, tagsText: String) async -> Bool {
        guard let repository else { return false }
        do {
            var updated = item
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else { throw ReFindError.emptyInput }
            updated.title = String(cleanTitle.prefix(200))
            updated.note = String(note.prefix(200_000))
            updated.tags = Array(Set(tagsText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }.map { String($0.prefix(30)) })).sorted().prefix(20).map { $0 }
            updated.updatedAt = .now
            try await repository.upsert(updated)
            infoMessage = "Изменения сохранены"
            await reload()
            return true
        } catch { alertMessage = error.localizedDescription; return false }
    }

    func delete(_ item: CaptureItem) async -> Bool {
        guard let repository else { return false }
        do {
            // Remove the DB row first, then best-effort remove its attachment.
            try await repository.delete(id: item.id)
            if let name = item.attachmentFile { try? await attachments?.remove(name: name) }
            await reload()
            infoMessage = "Удалено"
            return true
        } catch { alertMessage = error.localizedDescription; return false }
    }

    func attachmentURL(for item: CaptureItem) -> URL? {
        guard let name = item.attachmentFile else { return nil }
        return paths?.attachmentURL(name)
    }

    func makeBackup() async -> Data? {
        guard let repository, let attachments else { return nil }
        isBusy = true
        defer { isBusy = false }
        do { return try await backup.export(repository: repository, attachments: attachments) }
        catch { alertMessage = error.localizedDescription; return nil }
    }

    func restoreBackup(from url: URL) async {
        guard let repository, let attachments else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        isBusy = true
        defer { isBusy = false }
        do {
            let data = try Data(contentsOf: url)
            let count = try await backup.restore(data, repository: repository, attachments: attachments)
            infoMessage = "Восстановлено записей: \(count)"
            await reload()
        } catch { alertMessage = error.localizedDescription }
    }
}
