import Foundation

enum SharedCapture: Equatable, Sendable {
    case text(String)
    case file(URL)

    static func parse(_ url: URL) throws -> SharedCapture {
        if url.isFileURL { return .file(url) }
        if LinkNormalizer.parse(url.absoluteString) != nil { return .text(url.absoluteString) }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "refindone", parts.host == "capture",
              parts.path.isEmpty || parts.path == "/",
              let query = parts.queryItems, query.count == 1,
              query[0].name == "text", let text = query[0].value,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 200_000 else { throw ReFindError.unsupportedShare }
        return .text(text)
    }
}

struct CaptureDraft: Identifiable {
    let id = UUID()
    var text: String
}
