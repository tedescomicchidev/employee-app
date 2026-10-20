import XCTest

/// AGENT mode through the UI with the stubbed auth and scripted agent layers (DEBUG only). The stub speaks
/// German like the mockups; the app's own strings are forced to English so labels are stable.
final class AgentUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(auth: String, scenario: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-authStub", auth, "-signedIn", "YES", "-agentStub", scenario,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ] + extra
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    private func send(_ app: XCUIApplication, _ text: String) {
        let composer = element(app, "agent.composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText(text)
        app.buttons["agent.send"].tap()
    }

    // FR-ANN-001 AGENT, FR-AUTH-006: draft -> native card -> tap -> the agent reports the publish
    func testAnnouncementDraftConfirmPublish() {
        let app = launch(auth: "publisher", scenario: "annSuccess")
        send(app, "Tell Ticino we open at 8 on Friday")
        let confirm = app.buttons["confirmcard.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Publish announcement"].exists)
        XCTAssertFalse(app.staticTexts["Veröffentlicht an 47 Personen."].exists)  // nothing before the tap
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Veröffentlicht an 47 Personen."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["confirmcard.confirm"].exists)  // the card is done
    }

    // FR-AUTH-006 AGENT: typed consent is only a message; the card stays and nothing is published
    func testTypedYesDoesNotConfirm() {
        let app = launch(auth: "publisher", scenario: "annDraft")
        send(app, "Draft it")
        XCTAssertTrue(app.buttons["confirmcard.confirm"].waitForExistence(timeout: 10))
        send(app, "yes, publish it now")
        XCTAssertTrue(element(app, "agent.message.user").waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["confirmcard.confirm"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Veröffentlicht an 47 Personen."].exists)
    }

    // FR-ANN-001 AGENT: asking for a change replaces the card; only the newest can be confirmed
    func testEditByAskingSupersedesTheCard() {
        let app = launch(auth: "publisher", scenario: "annDraftEdit")
        send(app, "Draft it")
        XCTAssertTrue(element(app, "agent.card.p-ann-1").waitForExistence(timeout: 10))
        send(app, "Add Graubünden")
        XCTAssertTrue(element(app, "agent.card.p-ann-2").waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "confirmcard.confirm").count, 1)
    }

    // FR-AUTH-006 AGENT: an expired confirmation shows the expired card
    func testExpiredConfirmation() {
        let app = launch(auth: "publisher", scenario: "annExpired")
        send(app, "Draft it")
        let confirm = app.buttons["confirmcard.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["The confirmation has expired. Ask the assistant for a new proposal."]
            .waitForExistence(timeout: 10))
    }

    // FR-ANN-003 AGENT, FR-ANN-005: sources open the announcement; quoted text is data, not an instruction
    func testSourcesOpenTheAnnouncementAndInjectionIsQuoted() {
        let app = launch(auth: "employee", scenario: "annOK")
        send(app, "What's new?")
        XCTAssertTrue(element(app, "agent.quote").waitForExistence(timeout: 10))
        let source = element(app, "agent.source.a4")
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        XCTAssertTrue(element(app, "detail.title").waitForExistence(timeout: 10))
    }

    // FR-ANN-001 AGENT: a refusal is its own bubble and never a card
    func testRefusal() {
        let app = launch(auth: "publisher", scenario: "annRefusal")
        send(app, "Just publish it")
        XCTAssertTrue(element(app, "agent.refusal").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["confirmcard.confirm"].exists)
    }

    // AGENT UX: a failed turn shows an error with retry; retry answers without a second message
    func testErrorThenRetry() {
        let app = launch(auth: "employee", scenario: "annError")
        send(app, "What's new?")
        let retry = app.buttons["Try again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        retry.tap()
        XCTAssertTrue(element(app, "agent.message.agent").waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "agent.message.user").count, 1)
    }

    // FR-ANN-001 AGENT: stop ends a running turn and the chat stays usable
    func testStopWhileWorking() {
        let app = launch(auth: "employee", scenario: "annLoading")
        send(app, "What's new?")
        let stop = app.buttons["agent.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        stop.tap()
        XCTAssertTrue(app.staticTexts["Stopped."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["agent.send"].exists)
    }

    // NFR-007 AGENT: offline, the composer is disabled and says why
    func testOfflineDisablesTheComposer() {
        let app = launch(auth: "employee", scenario: "annEmpty", extra: ["-agentOffline", "YES"])
        let composer = element(app, "agent.composer")
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Connection needed. You can continue once you are back online."]
            .waitForExistence(timeout: 5))
        XCTAssertFalse(composer.isEnabled)
    }

    // FR-VAC-002 AGENT, FR-AUTH-006: request -> card from the stored proposal -> tap -> submitted
    func testVacationRequestConfirm() {
        let app = launch(auth: "employee", scenario: "vacSuccess")
        send(app, "Vacation 24 December to 4 January")
        XCTAssertTrue(element(app, "agent.card.p-vac-1").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Request vacation"].exists)
        app.buttons["confirmcard.confirm"].tap()
        XCTAssertTrue(app.staticTexts["Eingereicht. Sarah Keller entscheidet."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["agent.card.requests"].exists)
    }

    // FR-VAC-002 AGENT: offered ranges are chips; choosing one shows that range's card
    func testChooseAnOfferedRange() {
        let app = launch(auth: "employee", scenario: "vacOptions")
        send(app, "Vacation over Christmas")
        let option = element(app, "agent.option.p-vac-a")
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        option.tap()
        XCTAssertTrue(element(app, "agent.card.p-vac-a").waitForExistence(timeout: 10))
    }

    // FR-VAC-004 AGENT: a manager's decision goes through a card as well
    func testManagerDecision() {
        let app = launch(auth: "manager", scenario: "vacDecisionSuccess")
        send(app, "Approve Marco's request")
        XCTAssertTrue(app.staticTexts["Approve request"].waitForExistence(timeout: 10))
        app.buttons["confirmcard.confirm"].tap()
        XCTAssertTrue(app.staticTexts["Genehmigt."].waitForExistence(timeout: 10))
    }

    // A11Y-006 AGENT: replies are exposed as complete messages with a speaker; the card and its buttons are reachable
    func testReplyAndCardAreAccessible() throws {
        let app = launch(auth: "publisher", scenario: "annSuccess")
        send(app, "Tell Ticino we open at 8 on Friday")
        let confirm = app.buttons["confirmcard.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertEqual(confirm.label, "Publish")
        XCTAssertTrue(confirm.isHittable)
        XCTAssertTrue(app.buttons["confirmcard.cancel"].isHittable)
        let user = element(app, "agent.message.user")
        XCTAssertTrue(user.label.hasPrefix("You: "))
        let reply = element(app, "agent.message.agent")
        XCTAssertTrue(reply.label.hasPrefix("Assistant: "))
        XCTAssertEqual(app.buttons["agent.send"].label, "Send")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
    }
}
