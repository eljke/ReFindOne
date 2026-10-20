import XCTest

final class LibraryUITests: XCTestCase {
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
