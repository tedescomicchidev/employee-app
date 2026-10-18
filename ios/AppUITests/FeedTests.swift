import XCTest

/// FR-ANN-003 feed and detail, FR-ANN-005 inert rendering, through the stubbed API (DEBUG only).
final class FeedTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(api: String = "ok", scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if let scenario {
            arguments += ["-scenario", scenario]
        } else {
            arguments += ["-authStub", "employee", "-signedIn", "YES", "-announcementStub", api]
        }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    // FR-ANN-003.1/.2: unread count, open marks read, the count drops
    func testOpeningAnAnnouncementMarksItRead() {
        let app = launch()
        XCTAssertTrue(element(app, "feed.row.a4").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2 new"].exists)
        element(app, "feed.row.a4").tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1 new"].waitForExistence(timeout: 5))
    }

    // FR-ANN-005.2: markup is shown as typed, links are listed and only open on a tap
    func testDetailShowsTextUnchangedAndListsLinksWithoutOpeningThem() {
        let app = launch(scenario: "detail-ok")
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "detail.link.0").exists)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.staticTexts["detail.body"].label.contains("https://intranet.example/oeffnungszeiten"))
    }

    // FR-ANN-003.3: empty and error states
    func testEmptyFeed() {
        let app = launch(api: "feedEmpty")
        XCTAssertTrue(element(app, "feed.empty").waitForExistence(timeout: 10))
    }

    func testFeedErrorOffersRetry() {
        let app = launch(api: "feedError")
        XCTAssertTrue(element(app, "feed.error").waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Try again"].exists)
    }

    // FR-ANN-003.3 / NFR-007: offline shows the cached list with an "as of" banner
    func testOfflineFeedShowsCachedItemsWithBanner() {
        let app = launch(scenario: "feed-offline")
        XCTAssertTrue(element(app, "feed.offline").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "feed.row.a4").exists)
    }
}
