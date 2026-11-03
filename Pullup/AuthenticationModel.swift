import Foundation
import Combine

@MainActor protocol AuthenticationServing {
    func submit(path: String, method: String, fields: [String: String]) async throws -> AuthResponse
    func account() async throws -> Account
}

@MainActor struct LiveAuthenticationService: AuthenticationServing {
    func submit(path: String, method: String, fields: [String: String]) async throws -> AuthResponse {
        try await API.shared.request(path, method: method, body: fields)
    }
    func account() async throws -> Account {
        guard API.shared.hasSession else { throw APIError(status: 401, message: "Your sign-in hasn’t completed. Please try again.") }
        let response: AccountResponse = try await API.shared.request("/api/auth/me")
        return response.user
    }
}

enum AuthMode { case signIn, signUp }
enum AuthStep: String { case welcome, email, name, password, approval, code, success }

@MainActor final class AuthenticationModel: ObservableObject {
    @Published private(set) var step: AuthStep = .welcome
    @Published private(set) var mode: AuthMode = .signIn
    @Published var email = ""
    @Published var confirmationEmail = ""
    @Published var name = ""
    @Published var password = ""
    @Published var code = ""
    @Published var acceptedTerms = false
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    @Published private(set) var account: Account?
    @Published private(set) var resendAvailableAt = Date.distantPast
    private(set) var hasAuthenticator = false
    private var challengeToken: String?
    private var sessionPending = false
    private let service: any AuthenticationServing

    init(service: any AuthenticationServing) { self.service = service }
    var isSignup: Bool { mode == .signUp }
    var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var validEmail: Bool {
        normalizedEmail.count <= 254 && normalizedEmail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
    var emailsMatch: Bool { normalizedEmail == confirmationEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var canContinue: Bool {
        if busy { return false }
        if sessionPending { return true }
        switch step {
        case .welcome, .success, .approval: return true
        case .email: return validEmail && (!isSignup || emailsMatch)
        case .name: return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 100
        case .password: return isSignup ? password.count >= 8 && acceptedTerms : !password.isEmpty
        case .code: return !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    var progress: Double {
        switch step {
        case .welcome: return 0
        case .email: return isSignup ? 0.25 : 0.35
        case .name: return 0.5
        case .password: return isSignup ? 0.75 : 0.7
        case .approval, .code: return 0.9
        case .success: return 1
        }
    }
    var primaryTitle: String {
        if sessionPending { return "Finish signing in" }
        switch step {
        case .welcome: return "Get started"
        case .email, .name: return "Continue"
        case .password: return isSignup ? "Create my account" : "Sign in"
        case .approval: return "I’ve approved this login"
        case .code: return "Verify & continue"
        case .success: return "Let’s find your night"
        }
    }
    func start(_ mode: AuthMode) {
        guard !busy else { return }
        self.mode = mode; password = ""; code = ""; acceptedTerms = false
        challengeToken = nil; sessionPending = false; hasAuthenticator = false
        error = nil; notice = nil; step = .email
    }
    func back() {
        guard !busy, !sessionPending else { return }
        error = nil; notice = nil
        switch step {
        case .email: step = .welcome
        case .name: step = .email
        case .password: password = ""; step = isSignup ? .name : .email
        case .approval: challengeToken = nil; password = ""; step = .email
        case .code:
            code = ""
            if challengeToken != nil { step = .approval } else { step = .password }
        default: break
        }
    }
    func editEmail() {
        guard !busy, !sessionPending else { return }
        challengeToken = nil; code = ""; password = ""; error = nil; notice = nil; step = .email
    }
    func useAuthenticator() { guard !busy, hasAuthenticator else { return }; code = ""; error = nil; notice = nil; step = .code }
    func clearError() { error = nil; notice = nil }
    func clearSecrets() { password = ""; code = ""; challengeToken = nil }

    func continueFlow() async {
        guard !busy else { return }
        error = nil; notice = nil
        if step == .email {
            guard validEmail else { error = "Enter a valid email address."; return }
            guard !isSignup || emailsMatch else { error = "Those email addresses don’t match. Check both before continuing."; return }
            step = isSignup ? .name : .password; return
        }
        if step == .name {
            guard canContinue else { error = "Enter the name you’d like on your account."; return }
            step = .password; return
        }
        guard canContinue else { return }
        busy = true
        defer { busy = false }
        do {
            if sessionPending { try await finish(); return }
            switch step {
            case .password:
                let result = try await service.submit(path: isSignup ? "/api/auth/signup" : "/api/auth/login", method: "POST", fields: ["email": normalizedEmail, "password": password, "fullName": name.trimmingCharacters(in: .whitespacesAndNewlines)])
                if result.requiresLocationApproval == true {
                    guard let token = result.challengeToken, !token.isEmpty else { throw APIError(status: 0, message: "Your login approval could not start. Please try again.") }
                    challengeToken = token; hasAuthenticator = result.has2FA == true
                    resendAvailableAt = Date().addingTimeInterval(30); step = .approval; return
                }
                if result.requires2FA == true { hasAuthenticator = true; step = .code; return }
                guard result.success == true else { throw APIError(status: 0, message: "Sign-in did not complete. Please try again.") }
                sessionPending = true; try await finish()
            case .approval:
                guard let token = challengeToken else { return }
                let result = try await service.submit(path: "/api/auth/login-challenge", method: "POST", fields: ["challengeToken": token])
                if result.status == "pending" { notice = "Still waiting for approval. Open the email on this device, approve the login, then come back here."; return }
                guard result.status == "approved" else { throw APIError(status: 0, message: "This login was declined or expired. Go back to start again.") }
                sessionPending = true; try await finish()
            case .code:
                let fields: [String: String]
                let path: String
                let method: String
                if let token = challengeToken {
                    fields = ["challengeToken": token, "code": code.trimmingCharacters(in: .whitespacesAndNewlines)]
                    path = "/api/auth/login-challenge"; method = "PUT"
                } else {
                    fields = ["email": normalizedEmail, "password": password, "code": code.trimmingCharacters(in: .whitespacesAndNewlines)]
                    path = "/api/auth/2fa/login-verify"; method = "POST"
                }
                let result = try await service.submit(path: path, method: method, fields: fields)
                guard result.success == true || result.status == "approved" else { throw APIError(status: 0, message: "That code could not be verified. Please try again.") }
                sessionPending = true; try await finish()
            default: break
            }
        } catch { self.error = error.localizedDescription }
    }
    private func finish() async throws {
        // If account loading fails after signup, retry only this read. Never
        // submit account creation again and strand the customer on "email in use".
        account = try await service.account()
        clearSecrets(); sessionPending = false; step = .success
    }
    func resendApproval(now: Date = Date()) async {
        guard !busy, let token = challengeToken, now >= resendAvailableAt else { return }
        busy = true; error = nil; notice = nil
        defer { busy = false }
        do {
            let result = try await service.submit(path: "/api/auth/login-challenge", method: "PUT", fields: ["challengeToken": token, "action": "resend-email"])
            guard result.status == "sent" else { throw APIError(status: 0, message: "We couldn’t resend that email. Please retry.") }
            resendAvailableAt = now.addingTimeInterval(30); notice = "A fresh approval email is on its way."
        } catch { self.error = error.localizedDescription }
    }
}
