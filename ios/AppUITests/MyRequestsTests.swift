import XCTest

/// FR-VAC-007 CLASSIC: "My requests" through the UI with the stubbed layers (DEBUG only).
final class MyRequestsTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(api: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-authStub", "employee", "-signedIn", "YES", "-vacationStub", api,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func openMine(_ app: XCUIApplication) {
        let link = element(app, "vacation.mine")
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
    }

    // FR-VAC-007.1: statuses, counted days, decision date and rejection reason are listed
    func testListShowsStatusAndRejectionReason() {
        let app = launch(api: "history")
        openMine(app)
        let pending = element(app, "mine.row.r1")
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        XCTAssertTrue(pending.label.contains("Pending"))
        let rejected = element(app, "mine.row.h3")
        XCTAssertTrue(rejected.exists)
        XCTAssertTrue(rejected.label.contains("Rejected"))
        XCTAssertTrue(rejected.label.contains("Team-Engpass in KW 41"))
        XCTAssertTrue(element(app, "mine.row.h1").label.contains("Approved"))
    }

    // FR-VAC-007 (E): no requests shows the empty state
    func testEmptyState() {
        let app = launch(api: "ok")
        openMine(app)
        XCTAssertTrue(element(app, "mine.empty").waitForExistence(timeout: 5))
    }
}
