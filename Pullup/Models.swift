import Foundation

struct Event: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let date: String?
    let time: String?
    let city: String?
    let venue: String?
    let bannerUrl: String?
    let vibes: [String]?
    var when: String { DisplayDate.format(date, time: time) }
    var place: String { [venue, city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
}
struct EventPage: Decodable { let events: [Event]; let nextPage: Int? }
struct Account: Decodable {
    let id: String
    let email: String
    let full_name: String?
    let email_verified: Bool?
    let buyerTier: String?
}
struct AccountResponse: Decodable { let user: Account }
struct AuthResponse: Decodable {
    let success: Bool?
    let requires2FA: Bool?
    let requiresLocationApproval: Bool?
    let challengeToken: String?
    let has2FA: Bool?
    let status: String?
}
struct TicketPage: Decodable { let tickets: [Ticket]; let nextPage: Int? }
struct Ticket: Decodable, Identifiable {
    let id: String
    let name: String
    let qr_code: String?
    let ticket_tier: String?
    let payment_status: String?
    let status: String?
    let checked_in: Bool?
    let party: TicketEvent?
}
struct TicketEvent: Decodable {
    let id: String
    let title: String
    let date: String?
    let time: String?
    let location: String?
    let banner_url: String?
}
struct TicketDetails: Decodable {
    let guest: Ticket
    let checkinEnded: Bool?
    let appleWallet: WalletAvailability?
    let entryTime: EntryTime?
    let seatAssignments: [Seat]?
    var canShowQR: Bool {
        !["cancelled", "canceled", "rejected", "refunded", "refund_pending", "transferred", "resold"].contains(guest.status ?? "") &&
        !["cancelled", "canceled", "refunded", "refund_pending", "failed", "pending_bank_transfer"].contains(guest.payment_status ?? "") &&
        guest.checked_in != true && checkinEnded != true && guest.qr_code != nil
    }
    var statusLabel: String {
        if guest.payment_status == "pending_bank_transfer" { return "Awaiting bank approval" }
        if guest.checked_in == true { return "Checked in" }
        if checkinEnded == true { return "Entry closed" }
        if !canShowQR { return "Ticket unavailable" }
        if guest.payment_status == "instalment" { return "Payments remaining" }
        if guest.payment_status == "pending_door" { return "Pay at the door" }
        return "Your ticket"
    }
}
struct WalletAvailability: Decodable { let available: Bool }
struct EntryTime: Decodable { let label: String?; let time: String?; let date: String? }
struct Seat: Decodable { let section_name: String?; let row_label: String?; let seat_label: String? }
struct QRResponse: Decodable { let token: String; let expiresAt: Double }
struct APIMessage: Decodable { let error: String? }

enum DisplayDate {
    static func format(_ value: String?, time: String? = nil) -> String {
        guard let value else { return "Date to be announced" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_GB")
        parser.timeZone = TimeZone(identifier: "Europe/London")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(value.prefix(10))) else { return value }
        parser.dateFormat = "EEE, d MMM"
        return parser.string(from: date) + (time.map { " · " + String($0.prefix(5)) } ?? "")
    }
}
