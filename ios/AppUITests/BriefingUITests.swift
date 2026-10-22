import XCTest

/// FR-BRF-001/002/004/005 through the UI with the stubbed auth, briefing and agent layers (DEBUG only).
/// The app's own strings are forced to English so labels are stable; stub agent text stays German.
final class BriefingUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-authStub", "employee", "-signedIn", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            + arguments
        app.launch()
        return app
    }

    private func classic(_ scenario: String) -> XCUIApplication {
        launch(["-briefingStub", scenario])
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    // FR-BRF-001.1/2: off by default; the opt-in screen names what is read before anything is
    func testOptInNamesWhatIsAccessedAndShowsNothingBefore() {
        let app = classic("optIn")
        XCTAssertTrue(element(app, "briefing.optin.access").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Your calendar for the coming week"].exists)
        XCTAssertTrue(app.buttons["briefing.optin.turnon"].exists && app.buttons["briefing.optin.notnow"].exists)
        XCTAssertFalse(element(app, "briefing.week").exists)  // no calendar content before the opt-in
    }

    // FR-BRF-001, FR-BRF-003.1: Turn on, the one-time reminder question, then the week
    func testTurnOnAsksForTheReminderThenShowsTheWeek() {
        let app = launch(["-briefingStub", "optIn", "-notifications", "notDetermined"])
        let turnOn = app.buttons["briefing.optin.turnon"]
        XCTAssertTrue(turnOn.waitForExistence(timeout: 10))
        turnOn.tap()
        XCTAssertTrue(element(app, "briefing.reminder").waitForExistence(timeout: 10))
        app.buttons["briefing.reminder.allow"].tap()
        XCTAssertTrue(element(app, "briefing.week").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Team standup"].exists)
    }

    // FR-BRF-002: every event, the overlap flagged, grouped by day
    func testWeekListsTheEventsAndFlagsTheOverlap() {
        let app = classic("ok")
        XCTAssertTrue(element(app, "briefing.week").waitForExistence(timeout: 10))
        for title in ["Team standup", "Budget review", "Store visit Zurich", "One-to-one with manager"] {
            XCTAssertTrue(app.staticTexts[title].exists, title)
        }
        XCTAssertTrue(app.staticTexts["6 events"].exists && app.staticTexts["1 overlap"].exists)
    }

    // FR-BRF-005.2: an empty calendar is a briefing
    func testEmptyWeekIsNotAnError() {
        let app = classic("empty")
        XCTAssertTrue(element(app, "briefing.empty").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No events this week"].exists)
    }

    // FR-BRF-005.3: a partial week is labelled and the missing days are named
    func testPartialWeekNamesTheMissingDays() {
        let app = classic("partial")
        XCTAssertTrue(element(app, "briefing.partial").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Partial briefing"].exists)
    }

    // FR-BRF-005.1: each failure has its own message and shows no calendar
    func testFailuresShowTheirOwnMessageAndNoContent() {
        let cases = [
            ("workIQUnavailable", "briefing.problem.WORKIQ_UNAVAILABLE", "Work IQ is temporarily unavailable"),
            ("noLicence", "briefing.problem.NO_LICENCE", "Your account does not have access"),
            ("consentRequired", "briefing.problem.CONSENT_REQUIRED", "Work IQ is not approved yet"),
            ("offline", "briefing.problem.OFFLINE", "The briefing needs a connection"),
        ]
        for (scenario, id, title) in cases {
            let app = classic(scenario)
            XCTAssertTrue(element(app, id).waitForExistence(timeout: 10), scenario)
            XCTAssertTrue(app.staticTexts[title].exists, scenario)
            XCTAssertFalse(app.staticTexts["Team standup"].exists, scenario)
            app.terminate()
        }
    }

    // 40-60 s wait: while Work IQ works there is a progress state with a way out
    func testSlowReadShowsProgressAndCanBeStopped() {
        let app = classic("loading")
        XCTAssertTrue(element(app, "briefing.reading").waitForExistence(timeout: 10))
        app.buttons["briefing.stop"].tap()
        XCTAssertTrue(element(app, "briefing.problem.STOPPED").waitForExistence(timeout: 5))
    }

    // FR-BRF-002: the day detail lists the day's events and its free time
    func testDayDetailOpensFromTheWeek() {
        let app = classic("ok")
        let monday = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'briefing.day.'")).firstMatch
        XCTAssertTrue(monday.waitForExistence(timeout: 10))
        monday.tap()
        XCTAssertTrue(element(app, "briefing.dayDetail").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Team standup"].exists)
    }

    // FR-BRF-001.3/4: Settings shows the state; turning off asks first
    func testSettingsToggleAsksBeforeTurningOff() {
        let app = classic("ok")
        app.tabBars.buttons.element(boundBy: 3).tap()
        let toggle = element(app, "briefing.settings.toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.switches.firstMatch.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Turn off the weekly briefing?"].exists)
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    // FR-BRF-001 AGENT, FR-AUTH-006: the offer is a card; nothing is turned on before the tap
    func testAgentOffersOptInOnACard() {
        let app = launch(["-agentStub", "brfOffer"])
        let composer = element(app, "agent.composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("Brief me on my week")
        app.buttons["agent.send"].tap()
        XCTAssertTrue(app.buttons["confirmcard.confirm"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Turn on weekly briefing"].exists)
    }

    // FR-BRF-004 AGENT: asking about a colleague is declined
    func testAgentDeclinesAnotherPersonsCalendar() {
        let app = launch(["-agentStub", "brfDeclined"])
        let composer = element(app, "agent.composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("What does Anna have on Thursday?")
        app.buttons["agent.send"].tap()
        XCTAssertTrue(element(app, "agent.refusal").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["confirmcard.confirm"].exists)
    }
}
