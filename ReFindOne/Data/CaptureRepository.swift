import Foundation

/// Actor-friendly boundary. UI never issues SQL or touches a mutable database handle.
protocol CaptureRepository: Sendable {
    func allItems() async throws -> [CaptureItem]
    func list(query: String, kind: CaptureKind?, favoritesOnly: Bool) async throws -> [CaptureItem]
    func item(id: UUID) async throws -> CaptureItem?
    func existingLink(normalizedURL: String) async throws -> CaptureItem?
    func upsert(_ capture: CaptureItem) async throws
    func delete(id: UUID) async throws
}
