import Foundation

/// Paths live inside the active app container. No hard-coded LiveContainer paths.
struct AppPaths {
    let root: URL
    let attachments: URL
    let database: URL

    init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(for: .applicationSupportDirectory,
                                          in: .userDomainMask, appropriateFor: nil, create: true)
        root = support.appendingPathComponent("ReFindOne", isDirectory: true)
        attachments = root.appendingPathComponent("Attachments", isDirectory: true)
        database = root.appendingPathComponent("library.sqlite")
        try fileManager.createDirectory(at: attachments, withIntermediateDirectories: true)
    }

    /// Enables isolated filesystem tests and future migrations between containers.
    init(root: URL, fileManager: FileManager = .default) throws {
        self.root = root
        attachments = root.appendingPathComponent("Attachments", isDirectory: true)
        database = root.appendingPathComponent("library.sqlite")
        try fileManager.createDirectory(at: attachments, withIntermediateDirectories: true)
    }

    func attachmentURL(_ name: String) -> URL? {
        guard Self.attachmentExtension(name) != nil else { return nil }
        return attachments.appendingPathComponent(name, isDirectory: false)
    }

    static func attachmentExtension(_ name: String) -> String? {
        let components = name.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2,
              UUID(uuidString: String(components[0])) != nil,
              ["jpg", "png", "heic", "pdf"].contains(String(components[1])) else { return nil }
        return String(components[1])
    }
}
