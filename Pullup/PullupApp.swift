import SwiftUI

@MainActor final class AppState: ObservableObject {
    @Published var account: Account?
    @Published var restoring = true
    @Published var error: String?
    func restore() async {
        defer { restoring = false }
        guard API.shared.hasSession else { account = nil; return }
        do { let result: AccountResponse = try await API.shared.request("/api/auth/me"); account = result.user; error = nil }
        catch let failure as APIError where failure.status == 401 { API.shared.clear(); account = nil }
        catch { self.error = "Your account could not be loaded. Pull to refresh or try again." }
    }
    func signOut() async {
        do { _ = try await API.shared.data("/api/auth/logout", method: "POST") }
        catch { self.error = "Signed out on this device. If you are offline, revoke this session in web settings later." }
        API.shared.clear(); account = nil
    }
}
@main struct PullupApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(state).preferredColorScheme(.dark).tint(Palette.acid)
                .task { await state.restore() }
                .onChange(of: phase) { _, value in if value == .active { Task { await state.restore() } } }
                .overlay { if phase != .active { Palette.background.ignoresSafeArea().overlay(Text("PULLUP").font(.largeTitle.weight(.black))) } }
        }
    }
}
struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { DiscoverView() }.tabItem { Label("Discover", systemImage: "sparkles") }
            NavigationStack { TicketsView() }.tabItem { Label("Tickets", systemImage: "ticket") }
            NavigationStack { AccountView() }.tabItem { Label("You", systemImage: "person.crop.circle") }
        }.toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}
struct AccountView: View {
    @EnvironmentObject private var state: AppState
    @State private var auth = false
    @State private var web: WebDestination?
    @State private var signingOut = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your world.\nOne account.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                if let account = state.account {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 48)).foregroundStyle(Palette.acid)
                        Text(account.full_name ?? "Pullup member").font(.title2.bold())
                        Text(account.email).font(.subheadline).foregroundStyle(.secondary)
                        Text((account.buyerTier ?? "free").capitalized + " member").font(.caption.bold()).foregroundStyle(Palette.acid)
                    }.frame(maxWidth: .infinity, alignment: .leading).surface()
                    Button("Account settings") { web = WebDestination(path: "/dashboard/settings", title: "Settings") }.buttonStyle(.bordered)
                    Button("Sign out", role: .destructive) { signingOut = true; Task { await state.signOut(); signingOut = false } }.disabled(signingOut)
                } else {
                    Notice(title: "Make it your night", message: "Sign in to keep your tickets together. You can always explore without an account.", symbol: "person.crop.circle.badge.plus")
                    Button("Sign in or create account") { auth = true }.buttonStyle(PrimaryButton())
                }
                if let error = state.error { ErrorBanner(text: error); Button("Retry account") { Task { await state.restore() } } }
                VStack(spacing: 0) {
                    row("Find tickets bought as a guest", symbol: "envelope", path: "/my-tickets")
                    row("Help & support", symbol: "questionmark.circle", path: "/support")
                    row("Privacy", symbol: "hand.raised", path: "/privacy")
                    row("Terms", symbol: "doc.text", path: "/terms")
                }.surface()
                Text("PULLUP  /  MADE FOR THE NIGHT").font(.caption2.monospaced()).foregroundStyle(.secondary)
            }.padding(24)
        }.background(Palette.background).navigationTitle("You")
            .sheet(isPresented: $auth) { AuthView() }
            .sheet(item: $web) { WebSheet(destination: $0) }
    }
    private func row(_ title: String, symbol: String, path: String) -> some View {
        Button { web = WebDestination(path: path, title: title) } label: {
            HStack { Label(title, systemImage: symbol); Spacer(); Image(systemName: "arrow.up.right").font(.caption) }
                .foregroundStyle(.white).padding(.vertical, 16)
        }
    }
}
