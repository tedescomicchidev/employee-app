import XCTest

/// A11Y-001 (labels, traits), A11Y-002 (Dynamic Type clipping), A11Y-003 (contrast) and A11Y-005 (hit
/// regions) on the main CLASSIC screens, using the system accessibility audit. English is forced so the
/// tab labels are stable; the screens read the same string catalogs in every language (NFR-009).
final class AccessibilityAuditTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(auth: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-authStub", auth, "-signedIn", "YES", "-vacationStub", "populated",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + extra
        app.launch()
        return app
    }

    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .contrast, .hitRegion, .dynamicType]) { issue in
            // Report the screen with the failing element; do not ignore anything.
            XCTFail("\(screen): \(issue.compactDescription) \(issue.element?.debugDescription ?? "")")
            return false
        }
    }

    // A11Y-001/003/005
    func testEmployeeScreensPassTheAudit() throws {
        let app = launch(auth: "employee")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        for tab in ["Announcements", "Vacation", "More"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), tab)
            button.tap()
            try audit(app, tab)
        }
    }

    // A11Y-001/003: the manager's inbox
    func testApprovalsPassTheAudit() throws {
        let app = launch(auth: "manager")
        let tab = app.tabBars.buttons["Approvals"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        try audit(app, "Approvals")
    }

    // A11Y-002: the largest accessibility text size reflows without clipping critical content
    func testLargestTextSizeDoesNotClip() throws {
        let app = launch(
            auth: "employee",
            extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        for tab in ["Announcements", "Vacation"] {
            app.tabBars.buttons[tab].tap()
            try app.performAccessibilityAudit(for: [.dynamicType, .textClipped]) { issue in
                XCTFail("\(tab) at the largest size: \(issue.compactDescription)")
                return false
            }
        }
    }
}
