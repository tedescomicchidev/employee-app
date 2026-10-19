import XCTest

/// A11Y-001 (labels, traits), A11Y-005 (hit regions), A11Y-003 (contrast) and A11Y-002 (Dynamic Type,
/// clipping) on the main CLASSIC screens, using the system accessibility audit. English is forced so the
/// tab labels are stable; the screens read the same string catalogs in every language (NFR-009).
///
/// Element descriptions and hit regions are gated strictly. Contrast, Dynamic Type and clipping have open
/// findings that need a design decision (colour tokens are human-owned); they are listed in
/// `docs/design/a11y-findings.md` and matched below, so any finding NOT on that list fails the test.
final class AccessibilityAuditTests: XCTestCase {
    override func setUp() {
        // List every finding of a screen in one run, with the element.
        continueAfterFailure = true
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

    /// Open findings, see docs/design/a11y-findings.md (F1..F5).
    private static func isKnown(_ screen: String, _ issue: XCUIAccessibilityAuditIssue) -> Bool {
        let label = issue.element?.label ?? ""
        let isLanguageChip = ["DE", "FR", "IT", "EN"].contains(label)
        switch (screen, issue.auditType) {
        case ("News", .contrast): return isLanguageChip  // F1
        case ("News", .dynamicType): return isLanguageChip || label.contains(" · ")  // F2
        case ("News", .textClipped): return label.hasPrefix("Liebe Kolleginnen") || issue.element == nil  // F3
        case ("Vacation", .contrast): return label == "My requests"  // F4
        case ("More", .contrast): return label == "AM" || issue.element?.identifier == "debug.expire"  // F5
        default: return false
        }
    }

    private func audit(_ app: XCUIApplication, _ screen: String, types: XCUIAccessibilityAuditType) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            if Self.isKnown(screen, issue) { return true }
            XCTFail("\(screen): \(issue.compactDescription) \(issue.element?.debugDescription ?? "")")
            return false
        }
    }

    // A11Y-001, A11Y-002, A11Y-003, A11Y-005
    func testEmployeeScreensPassTheAudit() throws {
        let app = launch(auth: "employee")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        for tab in ["News", "Vacation", "Week", "More"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5), tab)
            button.tap()
            try audit(app, tab, types: [.sufficientElementDescription, .contrast, .hitRegion, .dynamicType])
        }
    }

    // A11Y-001, A11Y-003: the manager's inbox
    func testApprovalsPassTheAudit() throws {
        let app = launch(auth: "manager")
        let tab = app.tabBars.buttons["Approvals"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        try audit(app, "Approvals", types: [.sufficientElementDescription, .contrast, .hitRegion, .dynamicType])
    }

    // A11Y-002: the largest accessibility text size reflows without clipping critical content
    func testLargestTextSizeDoesNotClip() throws {
        let app = launch(
            auth: "employee",
            extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
        for tab in ["News", "Vacation"] {
            app.tabBars.buttons[tab].tap()
            try audit(app, tab, types: [.dynamicType, .textClipped])
        }
    }
}
