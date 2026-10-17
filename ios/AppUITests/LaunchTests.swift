import XCTest

final class LaunchTests: XCTestCase {
    func testAppLaunches() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["root.title"].waitForExistence(timeout: 10))
    }
}
