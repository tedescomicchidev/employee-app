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

    // FR-AUTH-005: a revoked token on Review opens "Sign in again" and sends nothing. The sheet replaces
    // the compose sheet, so after signing in the draft comes back when compose is opened again.
    func testRevokedTokenDuringComposeKeepsTheDraft() {
        let app = launch(api: "sessionRevoked")
        compose(app)
        app.buttons["compose.review"].tap()
        XCTAssertTrue(app.buttons["reauth.button"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["review.publish"].exists)
        app.buttons["reauth.button"].tap()
        XCTAssertTrue(app.buttons["reauth.button"].waitForNonExistence(timeout: 10))
        let entry = app.buttons["announcements.compose"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let title = app.textFields["compose.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Store hours")
        XCTAssertTrue((app.textViews["compose.body"].value as? String)?.contains("Open 8:00 on Friday") == true)
        app.buttons["compose.review"].tap()
        XCTAssertTrue(app.staticTexts["review.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Published to 11 people"].exists)
    }

    // FR-ANN-001.4 / FR-AUTH-002: employees have no compose entry
    func testEmployeeHasNoComposeEntry() {
        let app = launch(auth: "employee")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
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

    private func openAudience(_ app: XCUIApplication) {
        compose(app)
        let row = app.buttons["compose.audience"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.switches["audience.all"].waitForExistence(timeout: 5))
    }

    // FR-ANN-002.1/.2: chips narrow the audience, the live count and the review show the same number
    func testAudienceChipsShowLiveCountAndReviewMatches() {
        let app = launch()
        openAudience(app)
        app.buttons["audience.region.IT"].tap()
        XCTAssertTrue(app.staticTexts["3 recipients"].waitForExistence(timeout: 5))
        app.buttons["audience.role.Manager"].tap()
        XCTAssertTrue(app.staticTexts["4 recipients"].waitForExistence(timeout: 5))
        app.buttons["audience.next"].tap()
        XCTAssertTrue(app.staticTexts["review.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["4 recipients"].exists)
        XCTAssertTrue(app.staticTexts["review.audience"].label.contains("IT"))
    }

    // FR-ANN-002.1: "All" is exclusive; FR-ANN-002.4: an empty selection cannot go to review
    func testAllIsExclusiveAndEmptyAudienceBlocksReview() {
        let app = launch()
        openAudience(app)
        app.buttons["audience.region.FR"].tap()
        XCTAssertTrue(app.staticTexts["2 recipients"].waitForExistence(timeout: 5))
        app.buttons["audience.region.FR"].tap()
        XCTAssertTrue(app.staticTexts["No matching recipients"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["audience.next"].isEnabled)
        app.switches["audience.all"].tap()
        XCTAssertTrue(app.staticTexts["11 recipients"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["audience.next"].isEnabled)
    }
}
