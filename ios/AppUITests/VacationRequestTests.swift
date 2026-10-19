import XCTest

/// FR-VAC-001/002/006 CLASSIC through the UI with the stubbed auth and vacation layers (DEBUG only).
/// The stub mirrors the API on the fixtures of docs/product/test-cases.md (frozen clock 2026-10-19).
final class VacationRequestTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(api: String = "ok") -> XCUIApplication {
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

    /// The calendar renders months lazily; scroll until the day is on screen, then tap it.
    private func tapDay(_ app: XCUIApplication, _ label: String) {
        let day = app.buttons[label]
        var tries = 0
        while !(day.exists && day.isHittable), tries < 8 {
            app.scrollViews.firstMatch.swipeUp()
            tries += 1
        }
        XCTAssertTrue(day.waitForExistence(timeout: 5), label)
        day.tap()
    }

    /// Polls instead of using expectations, which Swift 6 flags as sending a non-Sendable test case.
    private func wait(timeout: TimeInterval = 5, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private func openRequest(_ app: XCUIApplication) {
        let request = app.buttons["vacation.request"]
        XCTAssertTrue(request.waitForExistence(timeout: 10))
        XCTAssertTrue(request.isEnabled)
        request.tap()
        XCTAssertTrue(app.buttons["request.continue"].waitForExistence(timeout: 5))
    }

    // FR-VAC-001.1: the overview shows the five numbers on load
    func testOverviewShowsTheFiveNumbers() {
        let app = launch(api: "populated")
        let remaining = element(app, "vacation.remaining")
        XCTAssertTrue(remaining.waitForExistence(timeout: 10))
        XCTAssertEqual(remaining.value as? String, "13 days")
        XCTAssertTrue(element(app, "vacation.entitlement").label.contains("25"))
        XCTAssertTrue(element(app, "vacation.carried").label.contains("3"))
        XCTAssertTrue(element(app, "vacation.approved").label.contains("11"))
        XCTAssertTrue(element(app, "vacation.pending").label.contains("4"))
        XCTAssertTrue(element(app, "vacation.next").label.contains("Marco Rossi"))
    }

    // FR-VAC-001: no requests shows the zeros and an empty state
    func testEmptyOverview() {
        let app = launch()
        XCTAssertTrue(element(app, "vacation.remaining").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "vacation.remaining").value as? String, "25 days")
        XCTAssertTrue(element(app, "vacation.empty").exists)
    }

    // NFR-007: offline without a cached overview is an error state and requesting is disabled
    func testOfflineDisablesRequest() {
        let app = launch(api: "offline")
        XCTAssertTrue(element(app, "vacation.error").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["vacation.request"].isEnabled)
    }

    // FR-VAC-006.3: the holidays of my canton, from the API
    func testHolidaysList() {
        let app = launch(api: "populated")
        let link = app.buttons["vacation.holidays"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(element(app, "holidays.row.2026-11-11").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "holidays.note").exists)
    }

    // FR-VAC-002 (test-cases "Classic request flow"): pick, review shows 3 days and balance after 22, submit
    func testRequestReviewSubmit() {
        let app = launch()
        openRequest(app)
        tapDay(app, "Monday, November 23")
        tapDay(app, "Wednesday, November 25")
        XCTAssertTrue(element(app, "request.workdays").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "request.workdays").label, "3 working days")
        app.buttons["request.continue"].tap()
        XCTAssertTrue(app.staticTexts["review.counted"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["review.counted"].label, "3 working days")
        XCTAssertTrue(element(app, "review.excluded.none").exists)
        XCTAssertTrue(element(app, "review.balanceAfter").label.contains("22"))
        XCTAssertTrue(element(app, "review.approver").label.contains("Marco Rossi"))
        app.buttons["review.submit"].tap()
        XCTAssertTrue(app.staticTexts["Request sent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pending with Marco Rossi"].exists)
        app.buttons["submitted.done"].tap()
        // FR-VAC-001.2: the overview reflects the write without a manual refresh
        let remaining = element(app, "vacation.remaining")
        XCTAssertTrue(remaining.waitForExistence(timeout: 5))
        XCTAssertTrue(wait { remaining.value as? String == "22 days" })
        XCTAssertTrue(element(app, "vacation.next").exists)
    }

    // FR-VAC-002.2 (R6): an overlap is shown inline and Continue stays off
    func testOverlapBlocksContinue() {
        let app = launch(api: "populated")
        openRequest(app)
        tapDay(app, "Wednesday, November 11")
        tapDay(app, "Friday, November 13")
        XCTAssertTrue(element(app, "request.violation.OVERLAP").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["request.continue"].isEnabled)
    }

    // FR-VAC-002.2 (R5): too few days leads to a review with the shortfall and no way to submit
    func testInsufficientBalanceReview() {
        let app = launch(api: "populated")
        openRequest(app)
        tapDay(app, "Monday, November 23")
        tapDay(app, "Friday, December 11")
        XCTAssertTrue(app.buttons["request.continue"].waitForExistence(timeout: 5))
        XCTAssertTrue(wait { app.buttons["request.continue"].isEnabled })
        app.buttons["request.continue"].tap()
        XCTAssertTrue(element(app, "review.violation.INSUFFICIENT_BALANCE").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["review.submit"].isEnabled)
        app.buttons["review.change"].tap()
        XCTAssertTrue(app.buttons["request.continue"].waitForExistence(timeout: 5))
    }

    // A11Y-005: the dates can be entered without the calendar
    func testTextEntryAlternativeExists() {
        let app = launch()
        openRequest(app)
        app.buttons["request.toggle_entry"].tap()
        XCTAssertTrue(element(app, "request.start").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "request.end").exists)
    }
}
