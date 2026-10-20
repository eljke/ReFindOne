import SwiftUI

struct AddCaptureView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content: String

    init(initialText: String = "") {
        _content = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название (необязательно)", text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextEditor(text: $content)
                        .frame(minHeight: 185)
                        .accessibilityLabel("Ссылка или текст заметки")
                } header: { Text("Что сохранить?") }
                  footer: {
                      Text("Ссылка начинается с https:// или http://. Обычный текст станет заметкой. Ничего не отправляется в облако.")
                  }
                if let url = LinkNormalizer.parse(content),
                   let normalized = LinkNormalizer.normalize(url),
                   normalized.absoluteString != url.absoluteString {
                    Section("Без рекламного трекинга") {
                        Text(normalized.absoluteString)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Сохранить")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        Task {
                            if await model.addText(content, title: title) { dismiss() }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
                }
            }
        }
    }
}
