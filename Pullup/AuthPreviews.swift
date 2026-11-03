import SwiftUI

@MainActor enum AuthenticationFactory {
    static func make() -> AuthenticationModel {
#if DEBUG
        if isUITesting { return AuthenticationModel(service: AuthPreviewService(scenario: ProcessInfo.processInfo.environment["AUTH_SCENARIO"] ?? "success")) }
#endif
        return AuthenticationModel(service: LiveAuthenticationService())
    }
    static var quietUITests: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--disable-decorative-animation")
#else
        false
#endif
    }
    static var isUITesting: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--auth-ui-testing")
#else
        false
#endif
    }
}

#if DEBUG
/// Preview/test transport: only explicitly enabled DEBUG launches use fixtures.
/// Release builds have no fixture service or credential bypass.
@MainActor final class AuthPreviewService: AuthenticationServing {
    let scenario: String
    init(scenario: String = "success") { self.scenario = scenario }
    func submit(path: String, method: String, fields: [String: String]) async throws -> AuthResponse {
        try await Task.sleep(for: .milliseconds(250))
        if scenario == "error" { throw APIError(status: 401, message: "That email or password doesn’t look right. Please try again.") }
        if path == "/api/auth/login" && scenario == "approval" {
            return try response(#"{"requiresLocationApproval":true,"challengeToken":"preview-only","has2FA":true}"#)
        }
        if path == "/api/auth/login" && scenario == "twoFactor" { return try response(#"{"requires2FA":true}"#) }
        if path == "/api/auth/login-challenge", fields["action"] == "resend-email" { return try response(#"{"status":"sent"}"#) }
        if path == "/api/auth/login-challenge" { return try response(#"{"status":"approved"}"#) }
        return try response(#"{"success":true}"#)
    }
    func account() async throws -> Account {
        try JSONDecoder().decode(Account.self, from: Data(#"{"id":"preview-account","email":"alex@example.com","full_name":"Alex Morgan","email_verified":false,"buyerTier":"free"}"#.utf8))
    }
    private func response(_ json: String) throws -> AuthResponse { try JSONDecoder().decode(AuthResponse.self, from: Data(json.utf8)) }
}
#Preview("Welcome · glass") {
    AuthView(model: AuthenticationModel(service: AuthPreviewService())).environmentObject(AppState()).tint(Palette.acid)
}
#Preview("Sign in · password") {
    let model: AuthenticationModel = {
        let value = AuthenticationModel(service: AuthPreviewService())
        value.start(.signIn); value.email = "alex@example.com"
        return value
    }()
    AuthView(model: model).environmentObject(AppState()).tint(Palette.acid)
        .task { await model.continueFlow() }
}
#endif
