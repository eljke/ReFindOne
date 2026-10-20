import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var exportDocument: BackupFileDocument?
    @State private var showingExport = false
    @State private var showingRestore = false
    @State private var showingRestoreConfirmation = false
    @State private var pendingRestoreURL: URL?

    var body: some View {
        Form {
            Section {
                Label("Хранится локально на iPhone", systemImage: "iphone.gen3")
                Label("Поиск и OCR без сервера", systemImage: "hand.raised")
                Label("Без аккаунта и подписки", systemImage: "checkmark.shield")
            } header: { Text("Приватность") }
              footer: { Text("Важно: гостевые приложения в одном LiveContainer не полностью изолированы друг от друга. Не сохраняй сюда пароли и секретные документы.") }

            Section {
                Button {
                    Task {
                        if let data = await model.makeBackup() {
                            exportDocument = BackupFileDocument(data: data)
                            showingExport = true
                        }
                    }
                } label: { Label("Экспортировать всю коллекцию", systemImage: "square.and.arrow.up") }
                    .disabled(model.isBusy)
                Button { showingRestore = true } label: {
                    Label("Восстановить из копии", systemImage: "square.and.arrow.down")
                }
                    .disabled(model.isBusy)
            } header: { Text("Резервные копии") }
              footer: {
                  Text("Экспорт включает все записи и вложения в один JSON-файл. Резервная копия НЕ зашифрована. Храни её в безопасном месте. При восстановлении существующие записи не заменяются.")
              }

            Section("О приложении") {
                LabeledContent("Версия", value: "0.2.0 MVP")
                LabeledContent("Платформа", value: "iOS 17+")
                LabeledContent("Хранилище", value: "SQLite + FTS5")
                LabeledContent("Разработано для", value: "LiveContainer / обычный iOS")
            }
            Section {
                Text("Поиск работает по названиям, заметкам, тегам и тексту из импортированных изображений или PDF. Ссылки из других приложений вставляются вручную — расширение «Поделиться» для гостевой IPA не регистрируется.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: { Text("Как пользоваться") }
        }
        .navigationTitle("Настройки")
        .fileExporter(isPresented: $showingExport,
                      document: $exportDocument,
                      contentType: .json,
                      defaultFilename: "ReFindOne-Backup") { result in
            if case let .failure(error) = result { model.alertMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $showingRestore, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                // Import picker URLs are temporary: copy before presenting confirmation.
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                do {
                    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                    guard size > 0 && size <= 250 * 1024 * 1024 else { throw ReFindError.fileTooLarge }
                    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("refind-import-\(UUID().uuidString).json")
                    try FileManager.default.copyItem(at: url, to: temp)
                    pendingRestoreURL = temp
                    showingRestoreConfirmation = true
                } catch { model.alertMessage = error.localizedDescription }
            case .failure(let error): model.alertMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Импортировать резервную копию?", isPresented: $showingRestoreConfirmation,
                            titleVisibility: .visible) {
            Button("Импортировать") {
                guard let url = pendingRestoreURL else { return }
                Task {
                    await model.restoreBackup(from: url)
                    try? FileManager.default.removeItem(at: url)
                    pendingRestoreURL = nil
                }
            }
            Button("Отмена", role: .cancel) {
                if let url = pendingRestoreURL { try? FileManager.default.removeItem(at: url) }
                pendingRestoreURL = nil
            }
        } message: {
            Text("Добавятся только записи, которых ещё нет в библиотеке. Текущие данные останутся без изменений.")
        }
    }
}

struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ReFindError.invalidBackup }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
