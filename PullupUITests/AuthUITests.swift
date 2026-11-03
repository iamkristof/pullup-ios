import XCTest

@MainActor final class AuthUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 120 }
    private func launch(_ scenario: String = "success") {
        app = XCUIApplication()
        app.launchArguments = ["--auth-ui-testing", "--disable-decorative-animation"]
        app.launchEnvironment["AUTH_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(app.staticTexts["auth.welcome"].waitForExistence(timeout: 10))
    }
    private var primary: XCUIElement { app.buttons["auth.primary"] }
    private func fill(_ id: String, _ value: String, secure: Bool = false) {
        let field = secure ? app.secureTextFields[id] : app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(value)
    }
    private func openPassword(_ scenario: String = "success") {
        launch(scenario); app.buttons["auth.signin"].tap()
        fill("auth.email", "alex@example.com"); primary.tap()
        XCTAssertTrue(app.secureTextFields["auth.password"].waitForExistence(timeout: 5))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "PullupAuth-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testWelcomeAndSignup() async throws {
        launch(); capture("01-Welcome"); primary.tap()
        fill("auth.email", "alex@example.com")
        XCTAssertFalse(primary.isEnabled)
        fill("auth.confirmEmail", "alex@example.com")
        primary.tap(); fill("auth.name", "Alex Morgan"); primary.tap()
        fill("auth.password", "PreviewPassword8!", secure: true)
        let terms = app.switches["auth.terms"]
        if !terms.isHittable { app.swipeUp() }
        XCTAssertTrue(terms.waitForExistence(timeout: 5)); terms.tap()
        capture("02-CreateAccount")
        primary.tap()
        XCTAssertTrue(app.staticTexts["auth.success"].waitForExistence(timeout: 8))
        capture("03-Success")
    }
    func testSignInAndPasswordVisibility() async throws {
        openPassword(); fill("auth.password", "PreviewPassword8!", secure: true)
        app.buttons["Show password"].tap()
        XCTAssertTrue(app.textFields["auth.password"].waitForExistence(timeout: 3))
        app.buttons["Hide password"].tap()
        capture("04-SignIn")
        primary.tap(); XCTAssertTrue(app.staticTexts["auth.success"].waitForExistence(timeout: 8))
    }
    func testWrongCredentialsHaveRecoverableError() async throws {
        openPassword("error"); fill("auth.password", "WrongPassword8!", secure: true)
        primary.tap(); XCTAssertTrue(app.otherElements["auth.error"].waitForExistence(timeout: 5) || app.staticTexts["auth.error"].exists)
        XCTAssertTrue(primary.isEnabled)
        capture("05-SignInError")
    }
    func testLocationApprovalAndAuthenticator() async throws {
        openPassword("approval"); fill("auth.password", "PreviewPassword8!", secure: true); primary.tap()
        let authenticator = app.buttons["Use my authenticator instead"]
        XCTAssertTrue(authenticator.waitForExistence(timeout: 8)); capture("06-Approval")
        authenticator.tap(); fill("auth.code", "123456"); primary.tap()
        XCTAssertTrue(app.staticTexts["auth.success"].waitForExistence(timeout: 8))
    }
    func testTwoFactor() async throws {
        openPassword("twoFactor"); fill("auth.password", "PreviewPassword8!", secure: true); primary.tap()
        fill("auth.code", "123456"); capture("07-TwoFactor"); primary.tap()
        XCTAssertTrue(app.staticTexts["auth.success"].waitForExistence(timeout: 8))
    }
}
