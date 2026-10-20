import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingAdd = false
    @State private var showingFiles = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var draft = ""
    @State private var pendingDelete: CaptureItem?

    var body: some View {
        List {
            Section {
                captureActions
                    .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 12, trailing: 18))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                collections
                    .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                if model.items.isEmpty {
                    if model.isLoading {
                        ProgressView("Загружаю коллекцию…")
                            .frame(maxWidth: .infinity).padding(36)
                    } else { emptyState }
                }
                ForEach(model.items) { item in
                    NavigationLink {
                        CaptureDetailView(item: item)
                    } label: {
                        CaptureRow(item: item, query: model.searchText, attachmentURL: model.attachmentURL(for: item))
                    }
                    .accessibilityIdentifier("capture.\(item.title)")
                    .listRowInsets(EdgeInsets(top: 13, leading: 16, bottom: 13, trailing: 14))
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { _ = await model.toggleFavorite(item) }
                        } label: {
                            Label(item.isFavorite ? "Убрать звезду" : "В избранное",
                                  systemImage: item.isFavorite ? "star.slash" : "star")
                        }.tint(.orange)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingDelete = item } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                        Button {
                            Task { _ = await model.setArchived(item, archived: !item.isArchived) }
                        } label: {
                            Label(item.isArchived ? "Во входящие" : "В архив",
                                  systemImage: item.isArchived ? "tray" : "archivebox")
                        }.tint(.indigo)
                    }
                    .contextMenu {
                        Button {
                            Task { _ = await model.toggleFavorite(item) }
                        } label: {
                            Label(item.isFavorite ? "Убрать из избранного" : "В избранное", systemImage: "star")
                        }
                        Button {
                            Task { _ = await model.setArchived(item, archived: !item.isArchived) }
                        } label: {
                            Label(item.isArchived ? "Вернуть во входящие" : "В архив", systemImage: "archivebox")
                        }
                        if let url = item.normalizedURL.flatMap(LinkNormalizer.parse) {
                            ShareLink(item: url) { Label("Поделиться ссылкой", systemImage: "square.and.arrow.up") }
                        }
                        Button(role: .destructive) { pendingDelete = item } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                    .disabled(model.isBusy)
                }
                if model.canLoadMore {
                    Button {
                        Task { await model.loadMore() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.isLoading { ProgressView() }
                            else { Text("Показать ещё") }
                            Spacer()
                        }.padding(.vertical, 8)
                    }
                    .disabled(model.isLoading || model.isBusy)
                    .accessibilityIdentifier("loadMore")
                }
            } header: {
                HStack {
                    Text(model.collection.title)
                    Spacer()
                    Picker("Тип материала", selection: $model.selectedKind) {
                        Text("Все типы").tag(CaptureKind?.none)
                        ForEach(CaptureKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(Optional(kind))
                        }
                    }
                    .textCase(nil)
                    .accessibilityIdentifier("kindFilter")
                }
            } footer: {
                if !model.items.isEmpty {
                    Text(model.canLoadMore ? "Показано \(model.items.count). Остальные — по кнопке «Показать ещё»." :
                         "Записей: \(model.items.count)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 0)
        .navigationTitle("ReFind One")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Label("На устройстве", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Порядок записей", selection: $model.sort) {
                        ForEach(CaptureSort.allCases) { Text($0.title).tag($0) }
                    }
                    if !model.searchText.isEmpty || model.selectedKind != nil {
                        Button("Сбросить поиск и тип", systemImage: "line.3.horizontal.decrease.circle") {
                            model.searchText = ""
                            model.selectedKind = nil
                        }
                    }
                } label: { Image(systemName: "arrow.up.arrow.down") }
                    .accessibilityLabel("Порядок записей")
                Button {
                    draft = ""
                    showingAdd = true
                } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Добавить запись")
                    .accessibilityIdentifier("addCapture")
                    .disabled(model.isBusy)
            }
        }
        .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Слово, тег или текст со скриншота")
        .task(id: model.filterSignature) {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await model.reload()
        }
        .refreshable { await model.reload() }
        .sheet(isPresented: $showingAdd) { AddCaptureView(initialText: draft) }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image, .pdf, .plainText]) { result in
            switch result {
            case .success(let url): Task { await model.importFile(from: url) }
            case .failure(let error): model.alertMessage = error.localizedDescription
            }
        }
        .onChange(of: photoSelection) { _, selection in
            guard let selection else { return }
            Task {
                do {
                    guard let bytes = try await selection.loadTransferable(type: Data.self) else {
                        throw ReFindError.unsupportedFile
                    }
                    await model.importImage(data: bytes, fileExtension: ImageDataFormat.fileExtension(for: bytes))
                } catch { model.alertMessage = error.localizedDescription }
                photoSelection = nil
            }
        }
        .confirmationDialog("Удалить запись?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { item in
            Button("Удалить", role: .destructive) { Task { _ = await model.delete(item) } }
        } message: { _ in Text("Запись и вложение будут удалены. Архив позволяет просто убрать материал из входящих.") }
    }

    private var captureActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Сохрани сейчас. Найди, когда нужно.")
                .font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                captureButton("Ссылка или текст", subtitle: "Идея, заметка, адрес", symbol: "square.and.pencil") {
                    draft = ""
                    showingAdd = true
                }
                captureButton("Из буфера", subtitle: "Вставить и сохранить", symbol: "doc.on.clipboard") {
                    draft = UIPasteboard.general.string ?? ""
                    showingAdd = true
                }
                PhotosPicker(selection: $photoSelection, matching: .images) {
                    captureLabel("Фото и скриншот", subtitle: "Распознаем текст", symbol: "text.viewfinder")
                }.buttonStyle(.plain)
                captureButton("Документ", subtitle: "PDF, TXT, изображение", symbol: "doc.badge.plus") {
                    showingFiles = true
                }
            }
            .disabled(model.isBusy)
        }
    }

    private func captureButton(_ title: String, subtitle: String, symbol: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) { captureLabel(title, subtitle: subtitle, symbol: symbol) }
            .buttonStyle(.plain)
    }

    private func captureLabel(_ title: String, subtitle: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(.tint)
                .frame(minHeight: 25)
            Text(title).font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private var collections: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CaptureCollection.allCases) { collection in
                    let selected = model.collection == collection
                    Button { model.collection = collection } label: {
                        Label(collection.title, systemImage: collection.symbol)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(selected ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("collection.\(collection.rawValue)")
                }
            }.padding(.vertical, 4).padding(.trailing, 18)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(model.searchText.isEmpty ? emptyTitle : "Ничего не найдено",
                  systemImage: model.searchText.isEmpty ? model.collection.symbol : "magnifyingglass")
        } description: {
            Text(model.searchText.isEmpty ? emptyDescription :
                 "Попробуй начало слова, другой тип материала или коллекцию «Всё».")
        } actions: {
            if !model.searchText.isEmpty || model.selectedKind != nil {
                Button("Сбросить фильтры") {
                    model.searchText = ""
                    model.selectedKind = nil
                }.buttonStyle(.bordered)
            }
        }
        .listRowBackground(Color.clear)
    }

    private var emptyTitle: String {
        switch model.collection {
        case .inbox: "Пусть важное останется здесь"
        case .favorites: "Самое нужное — под звездой"
        case .archive: "Архив пока пуст"
        case .all: "Твоя коллекция начинается здесь"
        }
    }

    private var emptyDescription: String {
        switch model.collection {
        case .inbox, .all: "Добавь ссылку, заметку или скриншот кнопками выше. Всё сохранится на устройстве."
        case .favorites: "Отмечай материалы звездой в карточке или свайпом вправо."
        case .archive: "Перемещай сюда просмотренное свайпом влево. Записи останутся доступны в поиске по архиву и в «Всё»."
        }
    }
}

private struct CaptureRow: View {
    let item: CaptureItem
    let query: String
    let attachmentURL: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Group {
                if item.kind == .image, let attachmentURL {
                    AttachmentThumbnail(url: attachmentURL)
                } else {
                    Image(systemName: item.kind.symbol).font(.title2).foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 56, height: 68)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    HighlightedText(value: item.title, query: query)
                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 4)
                    if item.isFavorite {
                        Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption)
                            .accessibilityLabel("В избранном")
                    }
                }
                let snippet = item.snippet(matching: query)
                if !snippet.isEmpty {
                    HighlightedText(value: snippet, query: query)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                if !item.tags.isEmpty {
                    Text(item.tags.prefix(3).map { "#\($0)" }.joined(separator: "  "))
                        .font(.caption2).foregroundStyle(.tint).lineLimit(1)
                }
                HStack(spacing: 5) {
                    Text(item.createdAt, style: .date)
                    if item.isArchived { Label("В архиве", systemImage: "archivebox") }
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct HighlightedText: View {
    let value: String
    let query: String

    var body: some View {
        var text = AttributedString(value)
        for word in query.split(whereSeparator: \.isWhitespace).prefix(8) {
            if let range = text.range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive]) {
                text[range].foregroundColor = .accentColor
                text[range].inlinePresentationIntent = .stronglyEmphasized
            }
        }
        return Text(text)
    }
}

private enum ImageDataFormat {
    static func fileExtension(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(16))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0xFF, 0xD8]) { return "jpg" }
        if bytes.count >= 12 && String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" { return "heic" }
        return "jpg"
    }
}
