import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingAdd = false
    @State private var showingFiles = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var draftFromClipboard = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                quickActions
                filters
                if model.items.isEmpty { emptyState }
                else {
                    HStack {
                        Text("Сохранённое").font(.headline)
                        Spacer()
                        Text("\(model.items.count)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(model.items) { item in
                        NavigationLink {
                            CaptureDetailView(item: item)
                        } label: {
                            CaptureRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("ReFind One")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draftFromClipboard = ""
                    showingAdd = true
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                .accessibilityLabel("Добавить запись")
            }
        }
        .searchable(text: $model.searchText, prompt: "Найти ссылку, текст, скриншот...")
        .task(id: model.filterSignature) {
            try? await Task.sleep(for: .milliseconds(180))
            if !Task.isCancelled { await model.reload() }
        }
        .refreshable { await model.reload() }
        .sheet(isPresented: $showingAdd) {
            AddCaptureView(initialText: draftFromClipboard)
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image, .pdf, .plainText]) { result in
            if case let .success(url) = result { Task { await model.importFile(from: url) } }
            else if case let .failure(error) = result { model.alertMessage = error.localizedDescription }
        }
        .onChange(of: photoSelection) { _, selection in
            guard let selection else { return }
            Task {
                do {
                    guard let bytes = try await selection.loadTransferable(type: Data.self) else {
                        throw ReFindError.unsupportedFile
                    }
                    let ext = ImageDataFormat.fileExtension(for: bytes)
                    await model.importImage(data: bytes, fileExtension: ext)
                } catch { model.alertMessage = error.localizedDescription }
                photoSelection = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Всё важное — под рукой.")
                .font(.system(.title2, design: .rounded, weight: .bold))
            Text("Сохраняй полезное из разных приложений. Находи за секунды — даже офлайн.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 7)
    }

    private var quickActions: some View {
        HStack(spacing: 9) {
            actionTile("Ссылка / текст", symbol: "square.and.pencil") {
                draftFromClipboard = ""
                showingAdd = true
            }
            actionTile("Вставить", symbol: "doc.on.clipboard") {
                draftFromClipboard = UIPasteboard.general.string ?? ""
                showingAdd = true
            }
            PhotosPicker(selection: $photoSelection, matching: .images) {
                actionContent("Скриншот", symbol: "text.viewfinder")
            }
            .buttonStyle(.plain)
            actionTile("Файл", symbol: "folder") { showingFiles = true }
        }
    }

    private func actionTile(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionContent(label, symbol: symbol) }
            .buttonStyle(.plain)
    }

    private func actionContent(_ label: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .frame(height: 26)
                .foregroundStyle(.tint)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 17)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterPill("Все", active: model.selectedKind == nil && !model.favoritesOnly) {
                    model.selectedKind = nil
                    model.favoritesOnly = false
                }
                filterPill("Избранное", icon: "star.fill", active: model.favoritesOnly) {
                    model.selectedKind = nil
                    model.favoritesOnly = true
                }
                ForEach(CaptureKind.allCases) { kind in
                    filterPill(kind.title, icon: kind.symbol,
                               active: model.selectedKind == kind && !model.favoritesOnly) {
                        model.selectedKind = kind
                        model.favoritesOnly = false
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterPill(_ label: String, icon: String? = nil, active: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(label)
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(active ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: model.searchText.isEmpty ? "tray.full" : "magnifyingglass")
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text(model.searchText.isEmpty && model.favoritesOnly ? "Здесь пока нет избранного" :
                 (model.searchText.isEmpty && model.selectedKind == nil ? "Твоя коллекция начинается здесь" : "Ничего не найдено"))
                .font(.headline)
            Text(model.searchText.isEmpty && model.selectedKind == nil && !model.favoritesOnly
                 ? "Добавь первую ссылку, заметку или скриншот. Их текст станет доступен в поиске."
                 : "Попробуй другие слова или выбери фильтр «Все».")
                .multilineTextAlignment(.center)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if model.searchText.isEmpty {
                Button("Добавить запись") { draftFromClipboard = ""; showingAdd = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct CaptureRow: View {
    let item: CaptureItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.kind.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 46, height: 46)
                .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 4)
                    if item.isFavorite { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption) }
                }
                let snippet = item.note.isEmpty ? item.extractedText : item.note
                if !snippet.isEmpty {
                    Text(snippet.replacingOccurrences(of: "\n", with: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let url = item.originalURL {
                    Text(url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack {
                    Text(item.kind.title)
                    Text("·")
                    Text(item.createdAt, style: .date)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                .padding(.top, 14)
        }
        .padding(13)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private enum ImageDataFormat {
    static func fileExtension(for data: Data) -> String {
        let bytes = [UInt8](data.prefix(16))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if bytes.starts(with: [0xFF, 0xD8]) { return "jpg" }
        if bytes.count >= 12 && String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
            return "heic"
        }
        return "jpg"
    }
}
