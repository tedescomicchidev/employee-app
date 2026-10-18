import XCTest

/// FR-AUTH-001/002/005 through the UI with the stubbed auth layer (`-authStub`, DEBUG builds only).
/// English is forced so labels are stable.
final class AuthFlowTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ stub: String, signedIn: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-authStub", stub, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if signedIn { app.launchArguments += ["-signedIn", "YES"] }
        app.launch()
        return app
    }

    private func signIn(_ app: XCUIApplication) {
        let button = app.buttons["signin.button"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        button.tap()
    }

    private func tab(_ app: XCUIApplication, _ label: String) -> XCUIElement { app.tabBars.buttons[label] }

    // FR-AUTH-001
    func testSignInShowsNameAndRole() {
        let app = launch("manager")
        signIn(app)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        tab(app, "More").tap()
        XCTAssertTrue(app.staticTexts["Maria Keller"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Manager"].exists)
    }

    // FR-AUTH-002: manager sees Approvals, employee does not
    func testRoleDrivesTabs() {
        let manager = launch("manager", signedIn: true)
        XCTAssertTrue(manager.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(tab(manager, "Approvals").exists)
        manager.terminate()

        let employee = launch("employee", signedIn: true)
        XCTAssertTrue(employee.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(tab(employee, "Approvals").exists)
        XCTAssertTrue(tab(employee, "News").exists)
        XCTAssertTrue(tab(employee, "More").exists)
    }

    // FR-AUTH-001: signed out, no tabs (so no agent surface)
    func testSignedOutShowsOnlySignIn() {
        let app = launch("employee")
        XCTAssertTrue(app.staticTexts["signin.title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    // FR-AUTH-001: failed, cancelled, offline and not-allowed sign-ins show a banner and allow retry
    func testFailedAndCancelledSignIn() {
        for stub in ["failed", "cancelled", "offline", "notAllowed"] {
            let app = launch(stub)
            signIn(app)
            XCTAssertTrue(app.descendants(matching: .any)["signin.banner"].waitForExistence(timeout: 10), stub)
            XCTAssertTrue(app.buttons["signin.button"].exists, stub)
            XCTAssertFalse(app.tabBars.firstMatch.exists, stub)
            app.terminate()
        }
    }

    // FR-AUTH-005: sign-out returns to sign-in
    func testSignOut() {
        let app = launch("employee", signedIn: true)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        tab(app, "More").tap()
        app.buttons["more.signout"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["signin.title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
    }

    // FR-AUTH-005: expired session shows "Sign in again", signing in again returns to home
    func testExpiredSessionAsksToSignInAgain() {
        let app = launch("expiresAfterSignIn")
        signIn(app)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        app.buttons["home.refresh"].tap()
        XCTAssertTrue(app.staticTexts["Sign in again"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["reauth.button"].exists)
        app.buttons["reauth.button"].tap()
        XCTAssertTrue(app.buttons["reauth.button"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.firstMatch.exists)
    }

    // Debug menu: seeding a manager scenario adds the Approvals tab
    func testDebugMenuSeedsManager() {
        let app = launch("employee", signedIn: true)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(tab(app, "Approvals").exists)
        tab(app, "More").tap()
        app.buttons["debug.seed.manager"].tap()
        XCTAssertTrue(tab(app, "Approvals").waitForExistence(timeout: 10))
    }
}
