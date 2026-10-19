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

final class CancelRequestTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func openPendingDetail(api: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-authStub", "employee", "-signedIn", "YES", "-vacationStub", api,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        let link = app.descendants(matching: .any)["vacation.mine"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let row = app.descendants(matching: .any)["mine.row.r1"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        return app
    }

    // FR-VAC-003.1/.3: Cancel request -> confirmation dialog -> cancelled, button gone
    func testCancelPendingRequestAfterConfirmation() {
        let app = openPendingDetail(api: "history")
        let cancel = app.buttons["detail.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Keep"].tap()
        XCTAssertTrue(cancel.exists, "keeping leaves the request pending")
        cancel.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["Cancel request"].tap()
        let status = app.descendants(matching: .any)["detail.status"].firstMatch
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !status.label.contains("Cancelled") {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(status.label.contains("Cancelled"))
        XCTAssertFalse(app.buttons["detail.cancel"].exists)
    }

    // FR-VAC-003 (ERR): a failed cancel keeps the request pending and says so
    func testFailedCancelShowsMessage() {
        let app = openPendingDetail(api: "cancelFails")
        app.buttons["detail.cancel"].tap()
        app.alerts.firstMatch.buttons["Cancel request"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["detail.cancel_failed"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail.cancel"].exists)
    }
}
