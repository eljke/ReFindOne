import SwiftUI
import UIKit
import QuickLook

struct CaptureDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var item: CaptureItem
    @State private var title: String
    @State private var note: String
    @State private var tags: String
    @State private var showDeleteConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var previewURL: URL?

    init(item: CaptureItem) {
        _item = State(initialValue: item)
        _title = State(initialValue: item.title)
        _note = State(initialValue: item.note)
        _tags = State(initialValue: item.tags.joined(separator: ", "))
    }

    private var hasChanges: Bool {
        title != item.title || note != item.note || tags != item.tags.joined(separator: ", ")
    }

    /// System data detector. Never accesses the network automatically.
    private var detectedLinks: [URL] {
        let source = String(item.extractedText.prefix(12_000))
        guard !source.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var seen = Set<String>()
        return detector.matches(in: source, range: range)
            .compactMap(\.url)
            .filter { LinkNormalizer.parse($0.absoluteString) != nil && seen.insert($0.absoluteString).inserted }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: item.kind.symbol)
                        .font(.title2)
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.tint)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.kind.title).font(.caption).foregroundStyle(.secondary)
                        Text(item.createdAt, style: .date).font(.footnote).foregroundStyle(.secondary)
                        if item.isArchived { Label("В архиве", systemImage: "archivebox").font(.caption) }
                    }
                    Spacer()
                    Button {
                        Task {
                            if let updated = await model.toggleFavorite(item) { item = updated }
                        }
                    } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(item.isFavorite ? .orange : .secondary)
                    }
                    .accessibilityLabel(item.isFavorite ? "Убрать из избранного" : "В избранное")
                    .accessibilityIdentifier("favoriteCapture")
                    .disabled(model.isBusy)
                }
                TextField("Название", text: $title)
                    .font(.headline)
                    .accessibilityIdentifier("captureTitle")
            }

            if let path = model.attachmentURL(for: item) {
                Section("Вложение") {
                    Button { previewURL = path } label: {
                        if item.kind == .image {
                            VStack(spacing: 8) {
                                AttachmentThumbnail(url: path).frame(maxWidth: .infinity, maxHeight: 260)
                                Label("Открыть изображение", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.subheadline)
                            }
                        } else {
                            Label("Читать PDF", systemImage: "doc.richtext")
                                .frame(minHeight: 44)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("previewAttachment")
                    ShareLink(item: path) { Label("Поделиться файлом", systemImage: "square.and.arrow.up") }
                }
            }

            if let original = item.originalURL, let url = LinkNormalizer.parse(original) {
                Section("Источник") {
                    Text(original)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .lineLimit(4)
                    Button {
                        openURL(url)
                    } label: { Label("Открыть оригинал", systemImage: "arrow.up.right.square") }
                    if let cleaned = item.normalizedURL {
                        Button {
                            UIPasteboard.general.string = cleaned
                            model.infoMessage = "Ссылка скопирована"
                        } label: { Label("Скопировать ссылку без трекеров", systemImage: "link") }
                        if let cleanURL = LinkNormalizer.parse(cleaned) {
                            ShareLink(item: cleanURL) { Label("Поделиться ссылкой", systemImage: "square.and.arrow.up") }
                        }
                    }
                }
            }

            if !item.extractedText.isEmpty {
                Section("Распознанный текст") {
                    Text(item.extractedText)
                        .font(.subheadline)
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = item.extractedText
                        model.infoMessage = "Текст скопирован"
                    } label: { Label("Копировать весь текст", systemImage: "doc.on.doc") }
                }
            }

            if !detectedLinks.isEmpty {
                Section("Ссылки, найденные в тексте") {
                    ForEach(detectedLinks, id: \.absoluteString) { url in
                        Button {
                            openURL(url)
                        } label: {
                            Label {
                                Text(url.absoluteString).lineLimit(2)
                            } icon: { Image(systemName: "link") }
                        }
                    }
                }
            }

            Section("Твои заметки") {
                TextEditor(text: $note)
                    .frame(minHeight: 150)
                    .accessibilityLabel("Заметки к материалу")
                    .accessibilityIdentifier("captureNote")
                if item.kind == .note, !note.isEmpty {
                    ShareLink(item: note) { Label("Поделиться текстом", systemImage: "square.and.arrow.up") }
                }
            }
            Section {
                TextField("например: рецепты, посмотреть, идеи", text: $tags)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: { Text("Теги через запятую") }
              footer: { Text("Теги участвуют в поиске.") }
            Section {
                Button {
                    Task {
                        if let updated = await model.setArchived(item, archived: !item.isArchived) { item = updated }
                    }
                } label: {
                    Label(item.isArchived ? "Вернуть во входящие" : "Переместить в архив",
                          systemImage: item.isArchived ? "tray.and.arrow.down" : "archivebox")
                }
                .accessibilityIdentifier("archiveCapture")
                .disabled(model.isBusy)
                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                    Label("Удалить запись", systemImage: "trash")
                }
                .disabled(model.isBusy)
            }
        }
        .navigationTitle("Материал")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(hasChanges)
        .scrollDismissesKeyboard(.interactively)
        .quickLookPreview($previewURL)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { showDiscardConfirmation = true }.disabled(model.isBusy)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Сохранить") {
                    Task {
                        if await model.saveChanges(item, title: title, note: note, tagsText: tags) {
                            dismiss()
                        }
                    }
                }
                .fontWeight(.semibold)
                .disabled(!hasChanges || model.isBusy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("saveCapture")
            }
        }
        .confirmationDialog("Удалить этот материал?", isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                Task { if await model.delete(item) { dismiss() } }
            }
        } message: {
            Text("Восстановить его можно будет только из резервной копии.")
        }
        .confirmationDialog("Сохранить изменения?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("Сохранить") {
                Task {
                    if await model.saveChanges(item, title: title, note: note, tagsText: tags) { dismiss() }
                }
            }
            Button("Выйти без сохранения", role: .destructive) { dismiss() }
        }
    }
}
