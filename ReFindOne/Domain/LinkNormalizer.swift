import Foundation

/// Conservative normalization: do not remove query parameters that may be content IDs.
/// No URL is fetched or opened when normalizing.
enum LinkNormalizer {
    private static let trackingKeys: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid",
        "igshid", "mc_cid", "mc_eid", "yclid", "twclid", "ref_src"
    ]

    static func parse(_ input: String) -> URL? {
        let candidate = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !candidate.contains(where: { $0.isWhitespace || $0.isNewline }),
              let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let hostname = components.host, !hostname.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        return components.url
    }

    static func normalize(_ url: URL) -> URL? {
        guard let checked = parse(url.absoluteString),
              var parts = URLComponents(url: checked, resolvingAgainstBaseURL: false) else { return nil }
        parts.fragment = nil
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        parts.queryItems = parts.queryItems?.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !trackingKeys.contains(name)
        }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        if (parts.scheme == "https" && parts.port == 443) ||
           (parts.scheme == "http" && parts.port == 80) { parts.port = nil }
        return parts.url
    }

    static func capture(from input: String, title customTitle: String? = nil) throws -> CaptureItem {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReFindError.emptyInput }
        let proposedTitle = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let url = parse(trimmed) {
            let defaultTitle = url.host?.replacingOccurrences(of: "www.", with: "") ?? "Ссылка"
            return CaptureItem(kind: .link, title: proposedTitle.isEmpty ? defaultTitle : proposedTitle,
                               originalURL: url.absoluteString,
                               normalizedURL: normalize(url)?.absoluteString ?? url.absoluteString)
        }
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? "Заметка"
        let title = proposedTitle.isEmpty ? String(firstLine.prefix(72)) : proposedTitle
        return CaptureItem(kind: .note, title: title, note: trimmed)
    }
}
