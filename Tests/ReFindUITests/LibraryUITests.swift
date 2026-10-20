import XCTest

final class LibraryUITests: XCTestCase {
    @MainActor
    func testIncomingLinkRequiresConfirmationAndAvoidsDuplicates() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        var parts = URLComponents()
        parts.scheme = "refindone"
        parts.host = "capture"
        let sharedURL = "https://example.com/shared?id=7&utm_source=share"
        parts.queryItems = [URLQueryItem(name: "text", value: sharedURL)]
        let route = try XCTUnwrap(parts.url)
        app.open(route)
        let editor = app.textViews["newCaptureContent"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, sharedURL)
        app.buttons["Отмена"].tap()
        XCTAssertFalse(app.buttons["capture.Shared from Safari"].exists)

        app.terminate()
        app.open(route)
        let title = app.textFields["newCaptureTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText("Shared from Safari")
        saveScreenshot("Incoming link")
        app.buttons["createCapture"].tap()
        XCTAssertTrue(app.buttons["capture.Shared from Safari"].waitForExistence(timeout: 10))
        app.open(route)
        XCTAssertTrue(app.buttons["createCapture"].waitForExistence(timeout: 10))
        app.buttons["createCapture"].tap()
        XCTAssertTrue(app.buttons["capture.Shared from Safari"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "capture.Shared from Safari").count, 1)
    }

    @MainActor
    func testSaveEditArchiveSearchAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()

        createCapture(in: app, title: "Weekend pasta", content: "Tomatoes, basil and olive oil. A recipe worth keeping.")
        app.buttons["capture.Weekend pasta"].tap()
        let favorite = app.buttons["favoriteCapture"]
        favorite.tap()
        XCTAssertTrue(app.buttons["Убрать из избранного"].waitForExistence(timeout: 10))
        let note = app.textViews["captureNote"]
        note.tap()
        note.typeText(" Remember to buy cheese.")
        app.buttons["saveCapture"].tap()

        app.buttons["collection.favorites"].tap()
        XCTAssertTrue(app.buttons["capture.Weekend pasta"].waitForExistence(timeout: 10))
        app.buttons["capture.Weekend pasta"].tap()
        app.swipeUp()
        app.buttons["archiveCapture"].tap()
        XCTAssertTrue(app.buttons["Вернуть во входящие"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.buttons["collection.inbox"].tap()
        let missing = NSPredicate(format: "exists == false")
        expectation(for: missing, evaluatedWith: app.buttons["capture.Weekend pasta"])
        waitForExpectations(timeout: 10)
        app.buttons["collection.archive"].tap()
        XCTAssertTrue(app.buttons["capture.Weekend pasta"].waitForExistence(timeout: 10))
        saveScreenshot("Archive")
        app.buttons["capture.Weekend pasta"].tap()
        app.swipeUp()
        app.buttons["archiveCapture"].tap()
        XCTAssertTrue(app.buttons["Переместить в архив"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["collection.inbox"].tap()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Tomat")
        XCTAssertTrue(app.buttons["capture.Weekend pasta"].waitForExistence(timeout: 10))
        saveScreenshot("Search")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["capture.Weekend pasta"].waitForExistence(timeout: 10))
        createCapture(in: app, title: "Read on a quiet evening", content: "https://developer.apple.com/documentation/swiftui?utm_source=test")
        createCapture(in: app, title: "A small idea for tomorrow", content: "Keep useful things together. Leave the rest behind.")
        saveScreenshot("Inbox")
    }

    @MainActor
    private func createCapture(in app: XCUIApplication, title: String, content: String) {
        XCTAssertTrue(app.buttons["addCapture"].waitForExistence(timeout: 10))
        app.buttons["addCapture"].tap()
        let titleField = app.textFields["newCaptureTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText(title)
        let editor = app.textViews["newCaptureContent"]
        editor.tap()
        editor.typeText(content)
        app.buttons["createCapture"].tap()
        XCTAssertTrue(app.buttons["capture.\(title)"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func saveScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
