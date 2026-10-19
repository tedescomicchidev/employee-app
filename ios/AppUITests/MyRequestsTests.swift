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

final class ManagerDecisionTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(api: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-authStub", "manager", "-signedIn", "YES", "-vacationStub", api, "-startOnApprovals", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func waitFor(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    // FR-VAC-004 (UI): manager decides in two taps from the inbox
    func testApproveFromInboxInTwoTaps() {
        let app = launch(api: "manager")
        let row = element(app, "inbox.row.m1")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let approve = app.buttons["detail.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        approve.tap()  // tap 1
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Approve"].tap()  // tap 2 confirms
        XCTAssertTrue(element(app, "detail.decided").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["detail.approve"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(waitFor { !self.element(app, "inbox.row.m1").exists }, "the inbox no longer lists it")
        XCTAssertTrue(element(app, "inbox.row.m2").exists)
    }

    // FR-VAC-004.1: reject with a reason through the sheet
    func testRejectWithReason() {
        let app = launch(api: "manager")
        element(app, "inbox.row.m1").tap()
        let reject = app.buttons["detail.reject"]
        XCTAssertTrue(reject.waitForExistence(timeout: 10))
        reject.tap()
        let reason = element(app, "reject.reason")
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        reason.tap()
        reason.typeText("Inventory week")
        XCTAssertTrue(element(app, "reject.count").label.contains("14 / 500"))
        app.buttons["reject.confirm"].tap()
        XCTAssertTrue(element(app, "detail.decided").waitForExistence(timeout: 5))
    }

    // FR-VAC-004.3: decided meanwhile shows the final state, actions disabled
    func testAlreadyDecidedShowsFinalStateWithoutActions() {
        let app = launch(api: "managerDecided")
        element(app, "inbox.row.m1").tap()
        let approve = app.buttons["detail.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 10))
        approve.tap()
        app.alerts.firstMatch.buttons["Approve"].tap()
        XCTAssertTrue(element(app, "detail.invalid_state").waitForExistence(timeout: 5))
        XCTAssertFalse(approve.isEnabled)
    }

    // FR-VAC-004.2: a rule broken since submission is shown and the request stays pending
    func testBlockedApprovalStaysPending() {
        let app = launch(api: "managerBlocked")
        element(app, "inbox.row.m1").tap()
        let approve = app.buttons["detail.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 10))
        approve.tap()
        app.alerts.firstMatch.buttons["Approve"].tap()
        XCTAssertTrue(element(app, "detail.blocked.BLACKOUT").waitForExistence(timeout: 5))
        XCTAssertTrue(approve.isEnabled)
    }

    // FR-VAC-005.1: the Team segment shows present of total per day, absences named, pending marked
    func testTeamCoverageShowsDaysAndAbsences() {
        let app = launch(api: "team")
        let segment = app.segmentedControls["approvals.segment"]
        XCTAssertTrue(segment.waitForExistence(timeout: 10))
        segment.buttons["Team"].tap()
        let day = element(app, "team.day.2026-11-09")
        XCTAssertTrue(day.waitForExistence(timeout: 10))
        XCTAssertTrue(day.label.contains("5") && day.label.contains("6"))
        XCTAssertTrue(element(app, "team.range").exists)
    }

    // FR-VAC-005.2 (403): a non-manager that reaches the team view gets the forbidden state
    func testTeamCoverageForbidden() {
        let app = launch(api: "managerForbidden")
        app.segmentedControls["approvals.segment"].buttons["Team"].tap()
        XCTAssertTrue(element(app, "team.forbidden").waitForExistence(timeout: 10))
    }

    // FR-VAC-005.3: the approval detail shows the team on the request's days and the other absences
    func testDecisionDetailShowsTeamPresence() {
        let app = launch(api: "team")
        element(app, "inbox.row.m1").tap()
        let presence = element(app, "detail.presence")
        XCTAssertTrue(presence.waitForExistence(timeout: 10))
        let also = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Tim Berger'")).firstMatch
        XCTAssertTrue(also.waitForExistence(timeout: 5))
        XCTAssertFalse(also.label.contains("Lena"), "the request itself is not listed as another absence")
    }

    // FR-VAC-004 (E): nothing waiting
    func testEmptyInbox() {
        let app = launch(api: "managerEmpty")
        XCTAssertTrue(element(app, "inbox.empty").waitForExistence(timeout: 10))
    }
}
