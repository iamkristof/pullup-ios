import SwiftUI

struct DiscoverView: View {
    @State private var events: [Event] = []
    @State private var query = ""
    @State private var tonight = false
    @State private var nextPage: Int?
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
    private var filterKey: String { query + "|" + String(tonight) }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("FIND YOUR NEXT STORY").font(.caption.monospaced().weight(.semibold)).tracking(2).foregroundStyle(Palette.acid)
                    Text("Find tonight.\nPull up.").font(.system(size: 54, weight: .black, design: .rounded)).minimumScaleFactor(0.65)
                    Text("Real events. Your next favourite memory.").foregroundStyle(.secondary)
                    HStack {
                        filter("All upcoming", active: !tonight) { tonight = false }
                        filter("Tonight", active: tonight) { tonight = true }
                    }.padding(.top, 8)
                }
                if let error { ErrorBanner(text: error); Button("Try again") { Task { await load(reset: true) } } }
                if loading && events.isEmpty { ProgressView("Finding your next night…").frame(maxWidth: .infinity).padding(40) }
                if !loading && error == nil && events.isEmpty {
                    Notice(title: "Room for something new", message: "No public events match this search. Try another name or explore all upcoming events.", symbol: "sparkle.magnifyingglass")
                }
                ForEach(events) { event in
                    NavigationLink(value: event) { EventCard(event: event) }.buttonStyle(.plain)
                }
                if nextPage != nil {
                    Button { Task { await load(reset: false) } } label: {
                        if loading { ProgressView() } else { Text("Explore more") }
                    }.buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(loading)
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle("Discover").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search events or places")
            .navigationDestination(for: Event.self) { EventDetailView(event: $0) }
            .refreshable { await load(reset: true) }
            .task(id: filterKey) {
                do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation(); await load(reset: true) } catch {}
            }
    }
    private func filter(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.subheadline.bold()).padding(.horizontal, 20).padding(.vertical, 12)
            .foregroundStyle(active ? .black : .white).background(active ? Palette.acid : .white.opacity(0.07), in: Capsule()) }
            .accessibilityAddTraits(active ? .isSelected : [])
    }
    private func load(reset: Bool) async {
        guard reset || !loading else { return }
        let id = UUID(); requestID = id; loading = true; error = nil
        if reset { events = []; nextPage = nil }
        defer { if requestID == id { loading = false } }
        var parts = URLComponents()
        parts.path = "/api/events/browse"
        parts.queryItems = [URLQueryItem(name: "page", value: String(reset ? 0 : nextPage ?? 0)), URLQueryItem(name: "limit", value: "24"), URLQueryItem(name: "keyword", value: query), URLQueryItem(name: "dateRange", value: tonight ? "tonight" : "")]
        do {
            let result: EventPage = try await API.shared.request(parts.string!)
            try Task.checkCancellation()
            guard requestID == id else { return }
            let existing = Set(events.map(\.id))
            events += result.events.filter { !existing.contains($0.id) }; nextPage = result.nextPage
        } catch is CancellationError {} catch { if requestID == id { self.error = error.localizedDescription } }
    }
}
struct EventCard: View {
    let event: Event
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Artwork(url: event.bannerUrl).frame(height: 260).overlay(alignment: .bottomLeading) {
                Text(event.vibes?.first?.uppercased() ?? "LIVE EVENTS").font(.caption.bold()).tracking(1).padding(10)
                    .background(.ultraThinMaterial, in: Capsule()).padding(16)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(event.when).font(.caption.bold()).foregroundStyle(Palette.acid)
                Text(event.title).font(.title2.bold()).lineLimit(2)
                HStack { Label(event.place.isEmpty ? "See event details" : event.place, systemImage: "mappin").lineLimit(1); Spacer(); Image(systemName: "arrow.up.right") }.font(.subheadline).foregroundStyle(.secondary)
            }.padding(20)
        }.background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 28)).clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.08)))
    }
}
struct EventDetailView: View {
    let event: Event
    @State private var web: WebDestination?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Artwork(url: event.bannerUrl).frame(height: 360).clipShape(RoundedRectangle(cornerRadius: 30))
                Text(event.title).font(.system(.largeTitle, design: .rounded, weight: .black))
                Label(event.when, systemImage: "calendar").foregroundStyle(Palette.acid)
                Label(event.place.isEmpty ? "Location in event details" : event.place, systemImage: "mappin.and.ellipse")
                Text("See the latest lineup, ticket tiers and entry information. Checkout uses Pullup’s live availability and secure payment flow.").foregroundStyle(.secondary)
                if let vibes = event.vibes, !vibes.isEmpty { Text(vibes.joined(separator: " · ")).font(.caption.bold()).foregroundStyle(Palette.acid) }
            }.padding(24).padding(.bottom, 90)
        }.background(Palette.background).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("View event & get tickets") { web = WebDestination(path: "/party/\(API.segment(event.id))", title: "Event & checkout") }
                    .buttonStyle(PrimaryButton()).padding().background(.ultraThinMaterial)
            }
            .sheet(item: $web) { WebSheet(destination: $0) }
    }
}
