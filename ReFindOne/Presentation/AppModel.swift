import Foundation
import Combine
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var items: [CaptureItem] = []
    @Published var searchText = ""
    @Published var selectedKind: CaptureKind?
    @Published var collection: CaptureCollection = .inbox
    @Published var sort: CaptureSort = .newest
    @Published private(set) var isBusy = false
    @Published private(set) var busyMessage = ""
    @Published private(set) var isLoading = false
    @Published private(set) var canLoadMore = false
    @Published var alertMessage: String?
    @Published var infoMessage: String?

    private let paths: AppPaths?
    private let repository: (any CaptureRepository)?
    private let attachments: AttachmentStore?
    private let ocr = OCRService()
    private let backup = BackupService()
    private let fileImportService = FileImportService()
    private let pageSize = 60
    private var searchGeneration = 0

    init(repository injected: (any CaptureRepository)? = nil, storagePaths: AppPaths? = nil) {
        do {
            let selectedPaths = try storagePaths ?? AppPaths()
            let selectedRepository: any CaptureRepository
            if let injected { selectedRepository = injected }
            else { selectedRepository = try SQLiteRepository(url: selectedPaths.database) }
            paths = selectedPaths
            repository = selectedRepository
            attachments = AttachmentStore(paths: selectedPaths)
        } catch {
            paths = nil
            repository = nil
            attachments = nil
            alertMessage = error.localizedDescription
        }
    }

    var filterSignature: String {
        "\(searchText)|\(selectedKind?.rawValue ?? "all")|\(collection.rawValue)|\(sort.rawValue)"
    }

    private var archivedFilter: Bool? {
        switch collection {
        case .inbox: false
        case .archive: true
        case .favorites, .all: nil
        }
    }

    func reload(reset: Bool = true) async {
        guard let repository else { return }
        searchGeneration += 1
        let generation = searchGeneration
        let count = reset ? pageSize : max(pageSize, items.count)
        isLoading = true
        defer { if generation == searchGeneration { isLoading = false } }
        do {
            let result = try await repository.list(query: searchText, kind: selectedKind,
                favoritesOnly: collection == .favorites, archived: archivedFilter,
                sort: sort, limit: count + 1, offset: 0)
            guard generation == searchGeneration else { return }
            items = Array(result.prefix(count))
            canLoadMore = result.count > count
        } catch {
            if generation == searchGeneration {
                items = []
                canLoadMore = false
                alertMessage = error.localizedDescription
            }
        }
    }

    func loadMore() async {
        guard let repository, !isLoading, !isBusy, canLoadMore else { return }
        let generation = searchGeneration
        isLoading = true
        defer { if generation == searchGeneration { isLoading = false } }
        do {
            let result = try await repository.list(query: searchText, kind: selectedKind,
                favoritesOnly: collection == .favorites, archived: archivedFilter,
                sort: sort, limit: pageSize + 1, offset: items.count)
            guard generation == searchGeneration else { return }
            items += result.prefix(pageSize)
            canLoadMore = result.count > pageSize
        } catch { alertMessage = error.localizedDescription }
    }

    private func beginWork(_ message: String) -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        busyMessage = message
        return true
    }

    private func endWork() {
        isBusy = false
        busyMessage = ""
    }

    private func showInbox() async {
        collection = .inbox
        selectedKind = nil
        searchText = ""
        sort = .newest
        await reload()
    }

    func addText(_ input: String, title: String? = nil) async -> Bool {
        guard beginWork("Сохраняю…") else { return false }
        defer { endWork() }
        do { try await saveText(input, title: title); return true }
        catch { alertMessage = error.localizedDescription; return false }
    }

    private func saveText(_ input: String, title: String? = nil) async throws {
        guard let repository else { throw ReFindError.unavailable }
        let capture = try LinkNormalizer.capture(from: input, title: title)
        if let normalized = capture.normalizedURL,
           let existing = try await repository.existingLink(normalizedURL: normalized) {
            collection = .all
            selectedKind = .link
            searchText = existing.title
            infoMessage = "Уже сохранено: \(existing.title)"
            await reload()
            return
        }
        try await repository.upsert(capture)
        infoMessage = "Сохранено во входящие"
        await showInbox()
    }

    func importImage(data: Data, fileExtension: String = "jpg", title: String = "Скриншот") async {
        guard beginWork("Распознаю текст на изображении…") else { return }
        defer { endWork() }
        do { try await saveImage(data: data, fileExtension: fileExtension, title: title) }
        catch { alertMessage = error.localizedDescription }
    }

    private func saveImage(data: Data, fileExtension: String, title: String) async throws {
        guard let repository, let attachments else { throw ReFindError.unavailable }
        guard !data.isEmpty, data.count <= AttachmentStore.maxBytes else { throw ReFindError.fileTooLarge }
        guard UIImage(data: data) != nil else { throw ReFindError.unsupportedFile }
        busyMessage = "Распознаю текст на изображении…"
        let recognized = (try? await ocr.extract(from: data)) ?? ""
        let name = try await attachments.save(data: data, fileExtension: fileExtension)
        let capture = CaptureItem(kind: .image, title: title, extractedText: recognized, attachmentFile: name)
        do { try await repository.upsert(capture) }
        catch { try? await attachments.remove(name: name); throw error }
        infoMessage = recognized.isEmpty ? "Изображение сохранено. Текст не найден" : "Сохранено. Текст доступен в поиске"
        await showInbox()
    }

    func importFile(from url: URL) async {
        guard beginWork("Импортирую файл…") else { return }
        defer { endWork() }
        do {
            switch try await fileImportService.load(from: url) {
            case .image(let data, let ext, let title):
                try await saveImage(data: data, fileExtension: ext, title: title)
            case .text(let text, let title):
                try await saveText(text, title: title)
            case .pdf(let data, let extractedText, let title):
                guard let repository, let attachments else { throw ReFindError.unavailable }
                let name = try await attachments.save(data: data, fileExtension: "pdf")
                let capture = CaptureItem(kind: .document, title: title, extractedText: extractedText, attachmentFile: name)
                do { try await repository.upsert(capture) }
                catch { try? await attachments.remove(name: name); throw error }
                infoMessage = extractedText.isEmpty ? "PDF сохранён. Текстового слоя нет" : "PDF сохранён и доступен в поиске"
                await showInbox()
            }
        } catch { alertMessage = error.localizedDescription }
    }

    func toggleFavorite(_ item: CaptureItem) async -> CaptureItem? {
        guard let repository, beginWork("Сохраняю…") else { return nil }
        defer { endWork() }
        do {
            let updated = try await repository.toggleFavorite(id: item.id)
            await reload(reset: false)
            return updated
        } catch { alertMessage = error.localizedDescription; return nil }
    }

    func setArchived(_ item: CaptureItem, archived: Bool) async -> CaptureItem? {
        guard let repository, beginWork("Сохраняю…") else { return nil }
        defer { endWork() }
        do {
            let updated = try await repository.setArchived(id: item.id, archived: archived)
            infoMessage = archived ? "Перемещено в архив" : "Возвращено во входящие"
            await reload(reset: false)
            return updated
        } catch { alertMessage = error.localizedDescription; return nil }
    }

    func saveChanges(_ item: CaptureItem, title: String, note: String, tagsText: String) async -> Bool {
        guard let repository, beginWork("Сохраняю изменения…") else { return false }
        defer { endWork() }
        do {
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty else { throw ReFindError.emptyInput }
            let tags = Array(Set(tagsText.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }.map { String($0.prefix(30)) })).sorted().prefix(20).map { $0 }
            _ = try await repository.updateDetails(id: item.id, title: String(cleanTitle.prefix(200)),
                note: String(note.prefix(200_000)), tags: tags)
            infoMessage = "Изменения сохранены"
            await reload(reset: false)
            return true
        } catch { alertMessage = error.localizedDescription; return false }
    }

    func delete(_ item: CaptureItem) async -> Bool {
        guard let repository, beginWork("Удаляю…") else { return false }
        defer { endWork() }
        do {
            try await repository.delete(id: item.id)
            if let name = item.attachmentFile { try? await attachments?.remove(name: name) }
            await reload(reset: false)
            infoMessage = "Запись удалена"
            return true
        } catch { alertMessage = error.localizedDescription; return false }
    }

    func attachmentURL(for item: CaptureItem) -> URL? {
        guard let name = item.attachmentFile else { return nil }
        return paths?.attachmentURL(name)
    }

    func makeBackup() async -> Data? {
        guard let repository, let attachments, beginWork("Готовлю резервную копию…") else { return nil }
        defer { endWork() }
        do { return try await backup.export(repository: repository, attachments: attachments) }
        catch { alertMessage = error.localizedDescription; return nil }
    }

    func stageBackup(from url: URL) async -> URL? {
        guard beginWork("Проверяю файл копии…") else { return nil }
        defer { endWork() }
        do { return try await fileImportService.stageBackup(from: url) }
        catch { alertMessage = error.localizedDescription; return nil }
    }

    func restoreBackup(from url: URL) async {
        guard let repository, let attachments, beginWork("Восстанавливаю коллекцию…") else { return }
        defer { endWork() }
        do {
            let count = try await backup.restore(from: url, repository: repository, attachments: attachments)
            infoMessage = "Добавлено записей: \(count)"
            await reload()
        } catch { alertMessage = error.localizedDescription }
    }
}
