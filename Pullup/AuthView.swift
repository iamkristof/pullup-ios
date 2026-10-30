import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var signup = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmEmail = ""
    @State private var accepted = false
    @State private var busy = false
    @State private var error: String?
    @State private var twoFactor = false
    @State private var challenge: String?
    @State private var has2FA = false
    @State private var code = ""
    @State private var web: WebDestination?
    private var normalizedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "sparkle").font(.system(size: 42)).foregroundStyle(Palette.acid).padding(.top, 16)
                    Text(challenge != nil || twoFactor ? "One more\nstep." : signup ? "Your next\nchapter." : "Back for\nmore.")
                        .font(.system(size: 52, weight: .black, design: .rounded))
                    Text(challenge != nil ? "Approve the login using the email we sent you, then continue below." : twoFactor ? "Enter your authenticator code or backup code." : "Your events, tickets and nights worth remembering.")
                        .foregroundStyle(.secondary)
                    if challenge == nil && !twoFactor {
                        Picker("Account action", selection: $signup) { Text("Sign in").tag(false); Text("Create account").tag(true) }.pickerStyle(.segmented)
                        VStack(spacing: 16) {
                            if signup { TextField("Full name", text: $name).textContentType(.name) }
                            TextField("Email address", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                            if signup { TextField("Confirm email address", text: $confirmEmail).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled() }
                            SecureField("Password", text: $password).textContentType(signup ? .newPassword : .password)
                        }.textFieldStyle(.roundedBorder)
                        if signup {
                            Text("Use at least 8 characters. Double-check your email so your tickets reach you.").font(.caption).foregroundStyle(.secondary)
                            Toggle("I agree to Pullup’s terms and privacy policy", isOn: $accepted).font(.subheadline)
                            HStack {
                                Button("Terms") { web = WebDestination(path: "/terms", title: "Terms") }
                                Button("Privacy") { web = WebDestination(path: "/privacy", title: "Privacy") }
                            }.font(.caption)
                        }
                    }
                    if twoFactor || (challenge != nil && has2FA) {
                        TextField("Authentication code", text: $code).textContentType(.oneTimeCode).textInputAutocapitalization(.characters).textFieldStyle(.roundedBorder)
                    }
                    if let error { ErrorBanner(text: error) }
                    Button { Task { await submit() } } label: {
                        if busy { ProgressView().tint(.black) }
                        else { Text(challenge != nil ? "I’ve approved this login" : twoFactor ? "Verify & sign in" : signup ? "Create account" : "Sign in") }
                    }.buttonStyle(PrimaryButton()).disabled(busy || (signup && !accepted && challenge == nil))
                    if challenge != nil && has2FA {
                        Button("Verify with authenticator") { Task { await verifyChallengeCode() } }.disabled(busy || code.isEmpty)
                    }
                    if challenge != nil {
                        Button("Resend approval email") { Task { await resend() } }.disabled(busy)
                    }
                    if !signup && challenge == nil && !twoFactor {
                        Button("Forgot password?") { web = WebDestination(path: "/auth/forgot-password", title: "Reset password") }
                    }
                    Button("Continue browsing") { dismiss() }.foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(28)
            }.background(Palette.background)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
                .sheet(item: $web) { WebSheet(destination: $0) }
                .onDisappear { password = ""; code = "" }
        }
    }
    private func finish() async throws {
        guard API.shared.hasSession else { throw APIError(status: 0, message: "Sign-in did not complete. Please try again.") }
        await state.restore()
        if state.account != nil { password = ""; dismiss() }
        else { throw APIError(status: 0, message: "Signed in, but account details could not load. Please retry.") }
    }
    private func submit() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            if let challenge {
                let reply: AuthResponse = try await API.shared.request("/api/auth/login-challenge", method: "POST", body: ["challengeToken": challenge])
                guard reply.status == "approved" else { throw APIError(status: 0, message: reply.status == "declined" ? "This login was declined. Close this screen and try again." : "Still waiting for approval. Check your email.") }
                try await finish(); return
            }
            if twoFactor {
                let _: AuthResponse = try await API.shared.request("/api/auth/2fa/login-verify", method: "POST", body: ["email": normalizedEmail, "password": password, "code": code])
                try await finish(); return
            }
            guard normalizedEmail.contains("@"), !password.isEmpty else { throw APIError(status: 0, message: "Enter your email and password.") }
            if signup {
                guard normalizedEmail == confirmEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), password.count >= 8, accepted else {
                    throw APIError(status: 0, message: "Check that both email addresses match, your password has 8 characters and you’ve accepted the terms.")
                }
            }
            let reply: AuthResponse = try await API.shared.request(signup ? "/api/auth/signup" : "/api/auth/login", method: "POST", body: ["email": normalizedEmail, "password": password, "fullName": name])
            if reply.requiresLocationApproval == true { challenge = reply.challengeToken; has2FA = reply.has2FA == true; return }
            if reply.requires2FA == true { twoFactor = true; return }
            guard reply.success == true else { throw APIError(status: 0, message: "Sign-in needs another step. Please try again.") }
            try await finish()
        } catch { self.error = error.localizedDescription }
    }
    private func verifyChallengeCode() async {
        guard let challenge else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let _: AuthResponse = try await API.shared.request("/api/auth/login-challenge", method: "PUT", body: ["challengeToken": challenge, "code": code])
            try await finish()
        } catch { self.error = error.localizedDescription }
    }
    private func resend() async {
        guard let challenge else { return }
        busy = true; error = nil; defer { busy = false }
        do { let _: AuthResponse = try await API.shared.request("/api/auth/login-challenge", method: "PUT", body: ["challengeToken": challenge, "action": "resend-email"]) }
        catch { self.error = error.localizedDescription }
    }
}
