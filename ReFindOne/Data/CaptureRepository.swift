import Foundation

/// Actor-friendly boundary. UI never issues SQL or touches a mutable database handle.
protocol CaptureRepository: Sendable {
    func allItems() async throws -> [CaptureItem]
    func list(query: String, kind: CaptureKind?, favoritesOnly: Bool,
              archived: Bool?, sort: CaptureSort, limit: Int, offset: Int) async throws -> [CaptureItem]
    func item(id: UUID) async throws -> CaptureItem?
    func existingLink(normalizedURL: String) async throws -> CaptureItem?
    func upsert(_ capture: CaptureItem) async throws
    func delete(id: UUID) async throws
    func toggleFavorite(id: UUID) async throws -> CaptureItem
    func setArchived(id: UUID, archived: Bool) async throws -> CaptureItem
    func updateDetails(id: UUID, title: String, note: String, tags: [String]) async throws -> CaptureItem
    func insertMissing(_ captures: [CaptureItem]) async throws -> Set<UUID>
}
