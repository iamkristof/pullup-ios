import XCTest
@testable import Pullup

@MainActor final class AuthenticationTests: XCTestCase {
    final class Service: AuthenticationServing {
        var calls: [(String, String, [String: String])] = []
        var result = #"{"success":true}"#
        var accountFailures = 0
        var shouldThrow = false
        func submit(path: String, method: String, fields: [String: String]) async throws -> AuthResponse {
            calls.append((path, method, fields))
            if shouldThrow { throw APIError(status: 401, message: "Wrong credentials") }
            return try JSONDecoder().decode(AuthResponse.self, from: Data(result.utf8))
        }
        func account() async throws -> Account {
            if accountFailures > 0 { accountFailures -= 1; throw APIError(status: 503, message: "Please retry") }
            return try JSONDecoder().decode(Account.self, from: Data(#"{"id":"test","email":"alex@example.com","full_name":"Alex","email_verified":true}"#.utf8))
        }
    }
    func signIn(_ model: AuthenticationModel) async {
        model.start(.signIn); model.email = "  Alex@Example.com  "
        await model.continueFlow(); model.password = "a password"
    }
    func signUp(_ model: AuthenticationModel) async {
        model.start(.signUp); model.email = "alex@example.com"; model.confirmationEmail = "alex@example.com"
        await model.continueFlow(); model.name = " Alex "; await model.continueFlow()
        model.password = "a password"; model.acceptedTerms = true
    }
    func testEmailMismatchStopsSignupWithoutNetwork() async {
        let service = Service(), model = AuthenticationModel(service: service)
        model.start(.signUp); model.email = "alex@example.com"; model.confirmationEmail = "typo@example.com"
        await model.continueFlow()
        XCTAssertEqual(model.step, .email); XCTAssertNotNil(model.error); XCTAssertEqual(service.calls.count, 0)
    }
    func testMalformedEmailCannotAdvance() async {
        let model = AuthenticationModel(service: Service()); model.start(.signIn)
        for value in ["alex", "a@", "a @example.com", "a@example"] { model.email = value; XCTAssertFalse(model.canContinue) }
    }
    func testSignupNeedsTermsAndPasswordLength() async {
        let service = Service(), model = AuthenticationModel(service: service)
        await signUp(model); model.acceptedTerms = false
        await model.continueFlow(); XCTAssertEqual(service.calls.count, 0)
        model.acceptedTerms = true; model.password = "short"; XCTAssertFalse(model.canContinue)
    }
    func testSignupUsesExistingEndpointAndClearsSecrets() async {
        let service = Service(), model = AuthenticationModel(service: service)
        await signUp(model); await model.continueFlow()
        XCTAssertEqual(service.calls[0].0, "/api/auth/signup")
        XCTAssertEqual(service.calls[0].2["fullName"], "Alex")
        XCTAssertEqual(model.step, .success); XCTAssertTrue(model.password.isEmpty); XCTAssertNotNil(model.account)
    }
    func testLoginNormalizesEmailAndUsesPasswordEndpoint() async {
        let service = Service(), model = AuthenticationModel(service: service)
        await signIn(model); await model.continueFlow()
        XCTAssertEqual(service.calls[0].2["email"], "alex@example.com")
        XCTAssertEqual(service.calls[0].0, "/api/auth/login"); XCTAssertEqual(model.step, .success)
    }
    func testWrongPasswordKeepsEditableFormAndError() async {
        let service = Service(); service.shouldThrow = true
        let model = AuthenticationModel(service: service); await signIn(model); await model.continueFlow()
        XCTAssertEqual(model.step, .password); XCTAssertNotNil(model.error); XCTAssertFalse(model.busy)
        service.shouldThrow = false; await model.continueFlow(); XCTAssertEqual(model.step, .success)
    }
    func testSignupAccountReadRetryDoesNotCreateAccountTwice() async {
        let service = Service(); service.accountFailures = 1
        let model = AuthenticationModel(service: service); await signUp(model); await model.continueFlow()
        XCTAssertEqual(model.primaryTitle, "Finish signing in"); XCTAssertNotNil(model.error)
        await model.continueFlow(); XCTAssertEqual(model.step, .success); XCTAssertEqual(service.calls.count, 1)
    }
    func testTwoFactorKeepsCredentialsUntilVerified() async {
        let service = Service(); service.result = #"{"requires2FA":true}"#
        let model = AuthenticationModel(service: service); await signIn(model); await model.continueFlow()
        XCTAssertEqual(model.step, .code); XCTAssertFalse(model.password.isEmpty)
        model.code = "BACKUP-CODE"; service.result = #"{"success":true}"#; await model.continueFlow()
        XCTAssertEqual(service.calls.last?.0, "/api/auth/2fa/login-verify")
        XCTAssertEqual(service.calls.last?.2["code"], "BACKUP-CODE"); XCTAssertTrue(model.password.isEmpty)
    }
    func testLocationApprovalRequiresServerApproval() async {
        let service = Service(); service.result = #"{"requiresLocationApproval":true,"challengeToken":"private","has2FA":true}"#
        let model = AuthenticationModel(service: service); await signIn(model); await model.continueFlow()
        XCTAssertEqual(model.step, .approval)
        service.result = #"{"status":"pending"}"#; await model.continueFlow()
        XCTAssertEqual(model.step, .approval); XCTAssertNotNil(model.notice); XCTAssertNil(model.account)
        service.result = #"{"status":"approved"}"#; await model.continueFlow()
        XCTAssertEqual(model.step, .success)
    }
    func testLocationAuthenticatorUsesChallengeNotDirectLogin() async {
        let service = Service(); service.result = #"{"requiresLocationApproval":true,"challengeToken":"private","has2FA":true}"#
        let model = AuthenticationModel(service: service); await signIn(model); await model.continueFlow()
        model.useAuthenticator(); model.code = "123456"; service.result = #"{"status":"approved"}"#
        await model.continueFlow()
        XCTAssertEqual(service.calls.last?.0, "/api/auth/login-challenge"); XCTAssertEqual(service.calls.last?.1, "PUT")
        XCTAssertEqual(service.calls.last?.2["challengeToken"], "private"); XCTAssertEqual(model.step, .success)
    }
    func testEditingEmailClearsPasswordAndBackPreservesEmail() async {
        let model = AuthenticationModel(service: Service()); await signIn(model)
        model.editEmail(); XCTAssertEqual(model.step, .email); XCTAssertTrue(model.password.isEmpty)
        XCTAssertEqual(model.normalizedEmail, "alex@example.com"); model.back(); XCTAssertEqual(model.step, .welcome)
    }
    func testResendCooldownPreventsRepeatedRequests() async {
        let service = Service(); service.result = #"{"requiresLocationApproval":true,"challengeToken":"private"}"#
        let model = AuthenticationModel(service: service); await signIn(model); await model.continueFlow()
        await model.resendApproval(); XCTAssertEqual(service.calls.count, 1)
        service.result = #"{"status":"sent"}"#; await model.resendApproval(now: Date().addingTimeInterval(31))
        XCTAssertEqual(service.calls.count, 2); XCTAssertNotNil(model.notice)
    }
}
