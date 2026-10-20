import XCTest
@testable import ReFindCore

final class SharedCaptureTests: XCTestCase {
    func testWebLinkAndFileRouting() throws {
        let web = try XCTUnwrap(URL(string: "https://example.com/article?id=7&utm_source=share"))
        XCTAssertEqual(try SharedCapture.parse(web), .text(web.absoluteString))
        let file = URL(fileURLWithPath: "/tmp/Рецепт.pdf")
        XCTAssertEqual(try SharedCapture.parse(file), .file(file))
    }

    func testTextDeepLinkPreservesUnicodeAndQueryCharacters() throws {
        let text = "Идея: купить сыр & томаты + базилик\nНа выходные"
        var parts = URLComponents()
        parts.scheme = "refindone"
        parts.host = "capture"
        parts.queryItems = [URLQueryItem(name: "text", value: text)]
        XCTAssertEqual(try SharedCapture.parse(XCTUnwrap(parts.url)), .text(text))
    }

    func testRejectsUnsafeAndAmbiguousInputs() throws {
        for input in ["javascript:alert(1)", "https://user:password@example.com", "refindone://other?text=hello",
                      "refindone://capture?text=", "refindone://capture?text=one&text=two",
                      "refindone://capture/path?text=hello"] {
            XCTAssertThrowsError(try SharedCapture.parse(XCTUnwrap(URL(string: input))), input)
        }
    }

    func testVersionOneBackupWithoutArchiveFieldStillDecodes() throws {
        let item = CaptureItem(kind: .note, title: "Старая запись")
        let data = try JSONEncoder().encode(item)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "archivedAt")
        let restored = try JSONDecoder().decode(CaptureItem.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.id, item.id)
        XCTAssertFalse(restored.isArchived)
    }
}
