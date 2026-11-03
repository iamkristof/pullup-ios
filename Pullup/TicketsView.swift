import SwiftUI
import CoreImage.CIFilterBuiltins
import PassKit

struct TicketsView: View {
    @EnvironmentObject private var state: AppState
    @State private var tickets: [Ticket] = []
    @State private var loading = false
    @State private var error: String?
    @State private var nextPage: Int?
    @State private var auth = false
    @State private var web: WebDestination?
    @State private var generation = UUID()
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                Text("Good nights.\nAll here.").font(.system(.largeTitle, design: .rounded, weight: .black))
                if state.account == nil {
                    Notice(title: "Your way in", message: "Sign in to see your tickets, or find a guest booking using your verified email.", symbol: "ticket")
                    Button("Sign in") { auth = true }.buttonStyle(PrimaryButton())
                } else {
                    if loading && tickets.isEmpty { ProgressView("Loading your tickets…").frame(maxWidth: .infinity).padding(40) }
                    if let error { ErrorBanner(text: error); Button("Retry") { Task { await load(reset: true) } } }
                    if !loading && error == nil && tickets.isEmpty {
                        Notice(title: "Your next night awaits", message: "Your tickets will appear here. Booked with another email? Find your guest booking below.", symbol: "ticket")
                    }
                    ForEach(tickets) { ticket in
                        NavigationLink { TicketDetailView(ticket: ticket) } label: {
                            HStack(alignment: .top, spacing: 16) {
                                Artwork(url: ticket.party?.banner_url).frame(width: 78, height: 100).clipShape(RoundedRectangle(cornerRadius: 18))
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(DisplayDate.format(ticket.party?.date, time: ticket.party?.time)).font(.caption.bold()).foregroundStyle(Palette.acid)
                                    Text(ticket.party?.title ?? "Event ticket").font(.title3.bold()).foregroundStyle(.white)
                                    Text(ticket.ticket_tier ?? "General admission").font(.subheadline).foregroundStyle(.secondary)
                                    Text(ticket.name).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.frame(maxWidth: .infinity, alignment: .leading).surface()
                        }.buttonStyle(.plain)
                    }
                    if nextPage != nil { Button("Load more tickets") { Task { await load(reset: false) } }.disabled(loading) }
                }
                Button("Find tickets bought as a guest") { web = WebDestination(path: "/my-tickets", title: "Find your tickets") }.font(.subheadline).padding(.vertical)
            }.padding(24)
        }.background(Palette.background).navigationTitle("Tickets").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $auth) { AuthView() }
            .sheet(item: $web) { WebSheet(destination: $0) }
            .task(id: state.account?.id) { await load(reset: true) }
            .refreshable { await load(reset: true) }
    }
    private func load(reset: Bool) async {
        guard reset || !loading else { return }
        let id = UUID(); generation = id
        if reset { tickets = []; nextPage = nil }
        guard let accountID = state.account?.id else { loading = false; return }
        loading = true; error = nil
        defer { if generation == id { loading = false } }
        do {
            let response: TicketPage = try await API.shared.request("/api/mobile/tickets?page=\(reset ? 0 : nextPage ?? 0)")
            guard generation == id, state.account?.id == accountID, !Task.isCancelled else { return }
            let seen = Set(tickets.map(\.id))
            tickets += response.tickets.filter { !seen.contains($0.id) }; nextPage = response.nextPage
        } catch {
            if generation == id, !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
struct PassPresentation: Identifiable { let id = UUID(); let pass: PKPass }
struct TicketDetailView: View {
    let ticket: Ticket
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var details: TicketDetails?
    @State private var qr: QRResponse?
    @State private var qrImage: UIImage?
    @State private var error: String?
    @State private var pass: PassPresentation?
    @State private var addingPass = false
    @State private var web: WebDestination?
    private var reference: String { ticket.qr_code ?? ticket.id }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(details?.guest.party?.title ?? ticket.party?.title ?? "Your ticket").font(.system(.largeTitle, design: .rounded, weight: .black))
                Text(DisplayDate.format(ticket.party?.date, time: ticket.party?.time)).foregroundStyle(Palette.acid)
                VStack(spacing: 22) {
                    HStack { Image(systemName: "ticket.fill"); Text(details?.statusLabel ?? "Checking ticket…"); Spacer() }.font(.caption.bold()).foregroundStyle(Palette.acid)
                    if let details {
                        Text(details.guest.ticket_tier ?? "General admission").font(.title.bold()).multilineTextAlignment(.center)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            if details.canShowQR, let qr, qr.expiresAt / 1000 > context.date.timeIntervalSince1970, let qrImage, phase == .active {
                                VStack(spacing: 12) {
                                    Image(uiImage: qrImage).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 260)
                                        .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 24))
                                        .accessibilityLabel("Live ticket QR code. Show this to door staff.")
                                    Label("Live QR · refreshes automatically", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
                                }
                            } else if details.canShowQR {
                                VStack(spacing: 12) { ProgressView(); Text("Refreshing your secure QR").font(.caption) }.frame(height: 250)
                            } else {
                                Notice(title: details.statusLabel, message: "Open the full ticket for payment information or contact your host.", symbol: "ticket")
                            }
                        }
                        Divider()
                        HStack { VStack(alignment: .leading, spacing: 6) { Text("GUEST").font(.caption2).foregroundStyle(.secondary); Text(details.guest.name).font(.headline) }; Spacer(); Image(systemName: "sparkle").foregroundStyle(Palette.acid) }
                        if let entry = details.entryTime?.label { info("ENTRY FROM", value: entry) }
                        if let location = details.guest.party?.location, !location.isEmpty { info("LOCATION", value: location) }
                        ForEach(Array((details.seatAssignments ?? []).enumerated()), id: \.offset) { _, seat in
                            info("YOUR PLACE", value: [seat.section_name, seat.row_label, seat.seat_label].compactMap { $0 }.joined(separator: " · "))
                        }
                        if ["instalment", "pending_door", "pending", "unpaid"].contains(details.guest.payment_status ?? "") {
                            Text("Any outstanding payment and entry requirements still apply. A visible QR does not confirm payment.").font(.caption).foregroundStyle(.secondary)
                        }
                    } else { ProgressView().padding(60) }
                }.surface()
                if let error { ErrorBanner(text: error); Button("Refresh ticket") { Task { await refresh() } } }
                if details?.appleWallet?.available == true && PKAddPassesViewController.canAddPasses() {
                    Button { Task { await addPass() } } label: {
                        Label(addingPass ? "Preparing pass…" : "Add to Apple Wallet", systemImage: "wallet.pass")
                    }.buttonStyle(PrimaryButton()).disabled(addingPass)
                }
                Button("Full ticket, bar pass & extras") { web = WebDestination(path: "/ticket/\(API.segment(reference))", title: "Your ticket") }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }.padding(24)
        }.background(Palette.background).navigationBarTitleDisplayMode(.inline)
            .sheet(item: $pass) { WalletSheet(pass: $0.pass) }
            .sheet(item: $web) { WebSheet(destination: $0) }
            .task(id: phase) {
                guard phase == .active else { qr = nil; qrImage = nil; return }
                while !Task.isCancelled {
                    await refresh()
                    do { try await Task.sleep(for: .seconds(20)) } catch { break }
                }
            }
    }
    private func info(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(label).font(.caption2).foregroundStyle(.secondary); Text(value).font(.subheadline.weight(.medium)) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func refresh() async {
        do {
            let fresh: TicketDetails = try await API.shared.request("/api/ticket/\(API.segment(reference))")
            try Task.checkCancellation()
            details = fresh
            guard fresh.canShowQR, let code = fresh.guest.qr_code else { qr = nil; qrImage = nil; error = nil; return }
            let token: QRResponse = try await API.shared.request("/api/qr/generate", method: "POST", body: ["qrCode": code])
            try Task.checkCancellation()
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(token.token.utf8); filter.correctionLevel = "M"
            if let output = filter.outputImage, let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) {
                qrImage = UIImage(cgImage: image); qr = token
            }
            error = nil
        } catch is CancellationError {} catch { qr = nil; qrImage = nil; self.error = "Your ticket could not refresh. Check your connection and retry." }
    }
    private func addPass() async {
        addingPass = true; error = nil; defer { addingPass = false }
        do {
            let data = try await API.shared.data("/api/ticket/\(API.segment(reference))/apple-wallet/click", method: "POST", form: ["pass": "entry"])
            pass = PassPresentation(pass: try PKPass(data: data))
        } catch { self.error = error.localizedDescription }
    }
}
struct WalletSheet: UIViewControllerRepresentable {
    let pass: PKPass
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> UIViewController {
        guard let controller = PKAddPassesViewController(pass: pass) else { return UIViewController() }
        controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let close: () -> Void
        init(close: @escaping () -> Void) { self.close = close }
        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) { close() }
    }
}

