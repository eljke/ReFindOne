import SwiftUI
import UIKit
import PDFKit

struct CaptureDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var item: CaptureItem
    @State private var title: String
    @State private var note: String
    @State private var tags: String
    @State private var showDeleteConfirmation = false

    init(item: CaptureItem) {
        _item = State(initialValue: item)
        _title = State(initialValue: item.title)
        _note = State(initialValue: item.note)
        _tags = State(initialValue: item.tags.joined(separator: ", "))
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
                    }
                    Spacer()
                    Button {
                        Task {
                            await model.toggleFavorite(item)
                            item.isFavorite.toggle()
                        }
                    } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(item.isFavorite ? .orange : .secondary)
                    }
                    .accessibilityLabel(item.isFavorite ? "Убрать из избранного" : "В избранное")
                }
                TextField("Название", text: $title)
                    .font(.headline)
            }

            if let path = model.attachmentURL(for: item) {
                Section("Вложение") {
                    if item.kind == .image, let picture = UIImage(contentsOfFile: path.path) {
                        Image(uiImage: picture)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Импортированное изображение")
                    } else if item.kind == .document {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.richtext").font(.title3)
                            Text("PDF-файл").font(.subheadline)
                            Spacer()
                        }
                    }
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
                    .frame(minHeight: 110)
                    .accessibilityLabel("Заметки к материалу")
            }
            Section {
                TextField("например: рецепты, посмотреть, идеи", text: $tags)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: { Text("Теги через запятую") }
              footer: { Text("Теги участвуют в поиске.") }
            Section {
                Button(role: .destructive) { showDeleteConfirmation = true } label: {
                    Label("Удалить запись", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Материал")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Сохранить") {
                    Task {
                        if await model.saveChanges(item, title: title, note: note, tagsText: tags) {
                            dismiss()
                        }
                    }
                }
                .fontWeight(.semibold)
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
    }
}
