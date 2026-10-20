import SwiftUI
import UIKit

struct AttachmentThumbnail: View {
    let url: URL
    @State private var image: UIImage?
    @State private var loading = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 70)
            } else {
                Label("Изображение недоступно", systemImage: "photo.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            loading = true
            let result = await ImagePreviewService.shared.thumbnail(for: url)
            guard !Task.isCancelled else { return }
            image = result
            loading = false
        }
    }
}
