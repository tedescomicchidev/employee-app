import XCTest

/// FR-ANN-001 CLASSIC through the UI with the stubbed auth and announcement layers (DEBUG only).
final class PublishAnnouncementTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(auth: String = "publisher", api: String = "ok") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-authStub", auth, "-signedIn", "YES", "-announcementStub", api,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        return app
    }

    private func compose(_ app: XCUIApplication) {
        let entry = app.buttons["announcements.compose"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let title = app.textFields["compose.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Store hours")
        let body = app.textViews["compose.body"]
        body.tap()
        body.typeText("Open 8:00 on Friday")
    }

    // FR-ANN-001: compose, review shows the recipient count, publish, success
    func testComposeReviewPublish() {
        let app = launch()
        compose(app)
        app.buttons["compose.review"].tap()
        XCTAssertTrue(app.staticTexts["review.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["review.title"].label, "Store hours")
        XCTAssertTrue(app.staticTexts["11 recipients"].exists)
        app.buttons["review.publish"].tap()
        XCTAssertTrue(app.staticTexts["Published to 11 people"].waitForExistence(timeout: 5))
    }

    // FR-ANN-001.1: the API's validation error shows on the field, nothing is published
    func testEmptyTitleShowsValidationFromApi() {
        let app = launch()
        let entry = app.buttons["announcements.compose"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        app.buttons["compose.review"].tap()
        XCTAssertTrue(app.staticTexts["The title is missing or too long."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.publish"].exists)
    }

    // FR-ANN-001.4 / FR-AUTH-002: employees have no compose entry
    func testEmployeeHasNoComposeEntry() {
        let app = launch(auth: "employee")
        XCTAssertTrue(app.staticTexts["home.name"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["announcements.compose"].exists)
    }

    // NFR-007: a failed publish keeps the review and offers retry
    func testPublishFailureKeepsDraftAndOffersRetry() {
        let app = launch(api: "publishFails")
        compose(app)
        app.buttons["compose.review"].tap()
        XCTAssertTrue(app.buttons["review.publish"].waitForExistence(timeout: 5))
        app.buttons["review.publish"].tap()
        XCTAssertTrue(app.staticTexts["Your draft is kept. Try again in a moment."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["review.title"].label, "Store hours")
    }
}
