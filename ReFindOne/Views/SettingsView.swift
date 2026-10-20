import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var exportDocument: BackupFileDocument?
    @State private var showingExport = false
    @State private var showingRestore = false
    @State private var showingRestoreConfirmation = false
    @State private var pendingRestoreURL: URL?
    @AppStorage("lastBackupDate") private var lastBackupDate = 0.0

    var body: some View {
        Form {
            Section {
                Label("Хранится локально на iPhone", systemImage: "iphone.gen3")
                Label("Поиск и OCR без сервера", systemImage: "hand.raised")
                Label("Без аккаунта и подписки", systemImage: "checkmark.shield")
            } header: { Text("Приватность") }
              footer: { Text("Важно: гостевые приложения в одном LiveContainer не полностью изолированы друг от друга. Не сохраняй сюда пароли и секретные документы.") }

            Section {
                LabeledContent("Последняя сохранённая копия") {
                    if lastBackupDate > 0 { Text(Date(timeIntervalSince1970: lastBackupDate), style: .date) }
                    else { Text("Ещё не создана").foregroundStyle(.secondary) }
                }
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
                LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "ReFindReleaseVersion") as? String ?? "—")
                if let url = URL(string: "https://github.com/eljke/ReFindOne/releases") {
                    Link(destination: url) { Label("Версии и обновления", systemImage: "arrow.down.app") }
                }
            }
            Section {
                Text("В Safari или «Файлах» нажми «Поделиться» → LiveContainer → ReFind One. Ссылка откроется для сохранения, поддерживаемый файл импортируется во входящие.")
                Text("Нужен LiveContainer 3.8 или новее с установленным Share Extension. Если пункта нет, добавь LiveContainer через «Ещё» в меню «Поделиться» или переустанови его с сохранением расширений.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Текст и фото передаются не всеми приложениями. Для них доступны «Из буфера» и «Фото и скриншот» в библиотеке.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Сохранение из других приложений") }

            Section {
                Label("Сохрани ссылку, текст, фото или файл. Новое появится во «Входящих».", systemImage: "1.circle")
                Label("Ищи по началу слова: «помид» найдёт «помидоры». Поиск учитывает текст на фото и в PDF с текстовым слоем.", systemImage: "2.circle")
                Label("Свайп вправо — избранное. Свайп влево — архив или удаление. В «Всё» виден и архив.", systemImage: "3.circle")
                Label("Нажми на вложение в карточке, чтобы открыть фото или прочитать PDF.", systemImage: "4.circle")
                Text("Файлы — до 20 МБ. Сканированные страницы PDF пока не распознаются. Перед обновлением сохрани резервную копию.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Как пользоваться") }
        }
        .navigationTitle("Настройки")
        .fileExporter(isPresented: $showingExport,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: "ReFindOne-Backup") { result in
            switch result {
            case .success: lastBackupDate = Date.now.timeIntervalSince1970
            case .failure(let error): model.alertMessage = error.localizedDescription
            }
            exportDocument = nil
        }
        .fileImporter(isPresented: $showingRestore, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                Task {
                    if let temp = await model.stageBackup(from: url) {
                        pendingRestoreURL = temp
                        showingRestoreConfirmation = true
                    }
                }
            case .failure(let error): model.alertMessage = error.localizedDescription
            }
        }
        .confirmationDialog("Импортировать резервную копию?", isPresented: $showingRestoreConfirmation,
                            titleVisibility: .visible) {
            Button("Импортировать") {
                guard let url = pendingRestoreURL else { return }
                pendingRestoreURL = nil
                Task {
                    await model.restoreBackup(from: url)
                    try? FileManager.default.removeItem(at: url)
                }
            }
            Button("Отмена", role: .cancel) {
                if let url = pendingRestoreURL { try? FileManager.default.removeItem(at: url) }
                pendingRestoreURL = nil
            }
        } message: {
            Text("Добавятся только отсутствующие записи. При ошибке изменения отменяются. Текущие записи не заменяются.")
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
