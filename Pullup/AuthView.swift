import SwiftUI

@MainActor struct AuthView: View {
    @StateObject private var model: AuthenticationModel
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPassword = false
    @State private var web: WebDestination?
    @FocusState private var focus: Field?
    private enum Field: Hashable { case email, confirmation, name, password, revealedPassword, code }

    init(model: AuthenticationModel? = nil) {
        _model = StateObject(wrappedValue: model ?? AuthenticationFactory.make())
    }
    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            if model.step == .welcome { welcome }
                            else if model.step == .success { success }
                            else { stepContent }
                        }.frame(maxWidth: 480, alignment: .leading).padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 28)
                            .frame(maxWidth: .infinity)
                            .id(model.step)
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: 18)), removal: .opacity))
                    }.scrollDismissesKeyboard(.interactively)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .animation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86), value: model.step)
            .sensoryFeedback(.selection, trigger: model.step)
            .sensoryFeedback(.error, trigger: model.error)
            .sensoryFeedback(.success, trigger: model.step == .success)
            .sheet(item: $web) { WebSheet(destination: $0) }
            .interactiveDismissDisabled(model.busy)
            .task(id: model.step) {
                focus = nil; showPassword = false
                guard model.step != .welcome && model.step != .success else { return }
                do { try await Task.sleep(for: .milliseconds(400)); try Task.checkCancellation() } catch { return }
                switch model.step {
                case .email: focus = .email
                case .name: focus = .name
                case .password: focus = .password
                case .code: focus = .code
                default: break
                }
            }
            .onChange(of: model.account?.id) { _, _ in
                if let account = model.account { app.account = account; app.error = nil }
            }
            .onDisappear { model.clearSecrets() }
        }.preferredColorScheme(.dark)
    }
    private var header: some View {
        VStack(spacing: 20) {
            HStack {
                if model.step != .welcome && model.step != .success {
                    AuthRoundButton(symbol: "arrow.left", label: "Back") { focus = nil; model.back() }.disabled(model.busy)
                } else { Color.clear.frame(width: 46, height: 46) }
                Spacer()
                Text("pullup↗").font(.title3.weight(.black)).accessibilityLabel("Pullup")
                Spacer()
                AuthRoundButton(symbol: "xmark", label: "Close sign in") { model.clearSecrets(); dismiss() }.disabled(model.busy)
            }
            if model.step != .welcome && model.step != .success {
                ProgressView(value: model.progress).tint(Palette.acid).accessibilityLabel("Account setup progress")
            }
        }.frame(maxWidth: 520).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8).frame(maxWidth: .infinity)
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 20) {
            AuthTicketArtwork()
            HStack(spacing: 7) {
                Circle().fill(Palette.acid).frame(width: 6, height: 6)
                Text("GOOD NIGHTS START HERE").font(.system(.caption2, design: .monospaced).weight(.medium)).tracking(1.8)
            }.foregroundStyle(Palette.acid)
            Text("Your next night.\nStarts here.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-1.2).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("auth.welcome")
            Text("Discover something worth going out for. Keep your tickets close. Make it a night to remember.")
                .font(.body).foregroundStyle(.white.opacity(0.58)).lineSpacing(4)
            HStack(spacing: 8) {
                Image(systemName: "ticket").foregroundStyle(Palette.acid)
                Text("Your events. One place.").foregroundStyle(.white.opacity(0.7))
            }.font(.caption).padding(.horizontal, 14).padding(.vertical, 10).authGlass(radius: 18)
        }
    }
    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 13) {
                Text(stepEyebrow).font(.system(.caption2, design: .monospaced).weight(.medium)).tracking(2).foregroundStyle(Palette.acid)
                Text(stepTitle).font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-1).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("auth.heading")
                Text(stepDescription).font(.body).foregroundStyle(.white.opacity(0.58)).lineSpacing(3)
            }
            Group {
                switch model.step {
                case .email: emailFields
                case .name: nameField
                case .password: passwordFields
                case .approval: approvalCard
                case .code: codeField
                default: EmptyView()
                }
            }.disabled(model.busy)
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle.fill").font(.subheadline).foregroundStyle(Color(red: 1, green: 0.55, blue: 0.62))
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("auth.error")
            }
            if let notice = model.notice {
                Label(notice, systemImage: "envelope.badge").font(.subheadline).foregroundStyle(Palette.acid).padding(16).authGlass(radius: 18)
                    .accessibilityIdentifier("auth.notice")
            }
        }
    }
    private var emailFields: some View {
        VStack(alignment: .leading, spacing: 22) {
            AuthField("Email address", symbol: "envelope") {
                TextField("you@example.com", text: $model.email)
                    .keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .email).submitLabel(model.isSignup ? .next : .continue)
                    .onSubmit { if model.isSignup { focus = .confirmation } else { submit() } }
                    .accessibilityLabel("Email address").accessibilityIdentifier("auth.email")
            }
            if model.isSignup {
                AuthField("Confirm email", symbol: "checkmark.shield") {
                    TextField("Enter it once more", text: $model.confirmationEmail).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().focused($focus, equals: .confirmation)
                        .submitLabel(.continue).onSubmit(submit).accessibilityLabel("Confirm email").accessibilityIdentifier("auth.confirmEmail")
                }
                Label("We’ll send your tickets here. A quick double-check makes all the difference.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var nameField: some View {
        AuthField("Your name", symbol: "person") {
            TextField("First and last name", text: $model.name).textContentType(.name).textInputAutocapitalization(.words)
                .focused($focus, equals: .name).submitLabel(.continue).onSubmit(submit)
                .accessibilityLabel("Your name").accessibilityIdentifier("auth.name")
        }
    }
    private var passwordFields: some View {
        VStack(alignment: .leading, spacing: 22) {
            emailReview
            AuthField(model.isSignup ? "Create a password" : "Password", symbol: "lock") {
                Group {
                    if showPassword {
                        TextField("Your password", text: $model.password).focused($focus, equals: .revealedPassword)
                    } else { SecureField("Your password", text: $model.password).focused($focus, equals: .password) }
                }.textContentType(model.isSignup ? .newPassword : .password).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.go).onSubmit(submit).accessibilityLabel("Password").accessibilityIdentifier("auth.password")
                Button {
                    showPassword.toggle(); focus = showPassword ? .revealedPassword : .password
                } label: { Image(systemName: showPassword ? "eye.slash" : "eye").frame(minWidth: 32, minHeight: 44) }
                    .foregroundStyle(.white.opacity(0.6)).accessibilityLabel(showPassword ? "Hide password" : "Show password")
            }
            if model.isSignup {
                Label("At least 8 characters", systemImage: model.password.count >= 8 ? "checkmark.circle.fill" : "circle")
                    .font(.caption).foregroundStyle(model.password.count >= 8 ? Palette.acid : .white.opacity(0.45))
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("I agree to the terms and privacy policy", isOn: $model.acceptedTerms).font(.subheadline).tint(Palette.acid)
                        .accessibilityIdentifier("auth.terms")
                    HStack(spacing: 18) {
                        Button("Terms") { focus = nil; web = WebDestination(path: "/terms", title: "Terms") }
                        Button("Privacy policy") { focus = nil; web = WebDestination(path: "/privacy", title: "Privacy") }
                    }.font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.6))
                }.padding(18).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
            } else {
                Button("Forgot your password?") { focus = nil; web = WebDestination(path: "/auth/forgot-password", title: "Reset password") }
                    .font(.subheadline.weight(.medium)).foregroundStyle(Palette.acid)
            }
        }
    }
    private var emailReview: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.badge.shield.half.filled").foregroundStyle(Palette.acid)
            Text(model.normalizedEmail).font(.subheadline).lineLimit(2).textSelection(.enabled)
            Spacer(minLength: 0)
            Button { focus = nil; model.editEmail() } label: { Image(systemName: "pencil").frame(width: 36, height: 40) }
                .foregroundStyle(.white.opacity(0.65)).accessibilityLabel("Change email")
        }.padding(.horizontal, 16).padding(.vertical, 10).authGlass(radius: 22)
    }
    private var approvalCard: some View {
        VStack(spacing: 22) {
            Image(systemName: "envelope.open.badge.clock").font(.system(size: 46, weight: .light)).foregroundStyle(Palette.acid).padding(.top, 10)
            Text(model.normalizedEmail).font(.headline).multilineTextAlignment(.center).textSelection(.enabled)
            Text("Approve this login from the email, then return here. We’ll keep your place.").font(.subheadline).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            if model.hasAuthenticator { Button("Use my authenticator instead") { model.useAuthenticator() }.font(.subheadline.weight(.semibold)).foregroundStyle(Palette.acid) }
        }.frame(maxWidth: .infinity).padding(26).authGlass(radius: 28)
    }
    private var codeField: some View {
        VStack(alignment: .leading, spacing: 20) {
            AuthField("Authentication or backup code", symbol: "key.horizontal") {
                TextField("Enter your code", text: $model.code).font(.title3.monospaced()).textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled().focused($focus, equals: .code)
                    .submitLabel(.go).onSubmit(submit).accessibilityLabel("Authentication code").accessibilityIdentifier("auth.code")
            }
            Label("Use the code from your authenticator. A saved backup code works too.", systemImage: "checkmark.shield")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
        }
    }
    private var success: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 36)
            Image(systemName: "checkmark").font(.system(size: 48, weight: .medium)).foregroundStyle(Palette.acid)
                .frame(width: 112, height: 112).authGlass(radius: 40).padding(.bottom, 16)
            Text("YOU’RE ALL SET").font(.system(.caption2, design: .monospaced).weight(.medium)).tracking(2).foregroundStyle(Palette.acid)
            Text("You’re in\(firstName.map { ", " + $0 } ?? "").")
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-1).accessibilityIdentifier("auth.success")
            Text("Your next favourite memory is out there.").foregroundStyle(.white.opacity(0.6)).lineSpacing(4)
            if model.isSignup {
                Label("Check your inbox to verify your email. That helps keep all your tickets connected to you.", systemImage: "envelope.badge")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65)).padding(20).authGlass(radius: 24)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var footer: some View {
        VStack(spacing: 17) {
            if model.step == .welcome {
                AuthActionButton(title: "Get started") { model.start(.signUp) }
                Button("I already have an account") { model.start(.signIn) }.font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(minHeight: 32).accessibilityIdentifier("auth.signin")
                Button("Just looking? Explore as a guest") { dismiss() }.font(.caption).foregroundStyle(.white.opacity(0.5)).frame(minHeight: 28)
            } else {
                AuthActionButton(title: model.primaryTitle, busy: model.busy, enabled: model.canContinue) {
                    if model.step == .success { dismiss() } else { submit() }
                }
                if model.step == .approval {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = max(0, Int(ceil(model.resendAvailableAt.timeIntervalSince(context.date))))
                        Button(seconds > 0 ? "Resend email in \(seconds)s" : "Resend approval email") { Task { await model.resendApproval() } }
                            .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.6)).disabled(seconds > 0 || model.busy).frame(minHeight: 30)
                    }
                } else if model.step == .password {
                    Label("Secure sign-in. Your password stays private.", systemImage: "lock.shield").font(.caption2).foregroundStyle(.white.opacity(0.55))
                }
            }
        }.frame(maxWidth: 480).padding(.horizontal, 26).padding(.top, 18).padding(.bottom, 16)
            .frame(maxWidth: .infinity).background(LinearGradient(colors: [Palette.background.opacity(0), Palette.background.opacity(0.97)], startPoint: .top, endPoint: .bottom))
    }
    private var firstName: String? { model.account?.full_name?.split(separator: " ").first.map(String.init) }
    private var stepEyebrow: String {
        switch model.step {
        case .email: return model.isSignup ? "LET’S MAKE IT YOURS" : "WELCOME BACK"
        case .name: return "A LITTLE INTRODUCTION"
        case .password: return model.isSignup ? "ONE LAST THING" : "PICK UP WHERE YOU LEFT OFF"
        case .approval, .code: return "KEEPING YOUR ACCOUNT YOURS"
        default: return "PULLUP"
        }
    }
    private var stepTitle: String {
        switch model.step {
        case .email: return "What’s your email?"
        case .name: return "What should we\ncall you?"
        case .password: return model.isSignup ? "Make it\nyours." : "Good to have\nyou back."
        case .approval: return "Check your\ninbox."
        case .code: return "Just you.\nOne more step."
        default: return "Welcome."
        }
    }
    private var stepDescription: String {
        switch model.step {
        case .email: return model.isSignup ? "Your tickets and good nights, all connected." : "Use the email linked to your Pullup account."
        case .name: return "A name for your account. You can change it later."
        case .password: return model.isSignup ? "Choose a password to keep your account safe." : "Enter your password and we’ll get you back to it."
        case .approval: return "There’s a login approval waiting for you."
        case .code: return "Confirm this login with your authenticator."
        default: return ""
        }
    }
    private func submit() {
        if model.canContinue { focus = nil }
        Task { await model.continueFlow() }
    }
}
