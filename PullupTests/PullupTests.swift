import XCTest
@testable import Pullup

final class PullupTests: XCTestCase {
    private func ticket(_ payment: String, status: String = "approved", checkedIn: Bool = false, ended: Bool = false) throws -> TicketDetails {
        let object: [String: Any] = ["guest": ["id": "1", "name": "Guest", "qr_code": "private-reference", "payment_status": payment, "status": status, "checked_in": checkedIn], "checkinEnded": ended]
        return try JSONDecoder().decode(TicketDetails.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testPendingBankTransferIsLocked() throws { XCTAssertFalse(try ticket("pending_bank_transfer").canShowQR) }
    func testHostIssuedTicketShowsQR() throws { XCTAssertTrue(try ticket("not_required").canShowQR) }
    func testCancelledAndRefundedAreLocked() throws {
        for state in ["cancelled", "refunded", "rejected", "transferred", "resold"] { XCTAssertFalse(try ticket("paid", status: state).canShowQR) }
        XCTAssertFalse(try ticket("refunded").canShowQR)
    }
    func testUsedAndClosedAreLocked() throws {
        XCTAssertFalse(try ticket("paid", checkedIn: true).canShowQR)
        XCTAssertFalse(try ticket("paid", ended: true).canShowQR)
    }
    func testInstalmentNoticeDoesNotClaimPaid() throws {
        XCTAssertEqual(try ticket("instalment").statusLabel, "Payments remaining")
    }
    func testBrowseDecodesNullableFields() throws {
        let json = #"{"events":[{"id":"1","title":"Tonight","date":null,"time":null,"city":null,"venue":null,"bannerUrl":null,"vibes":[]}],"nextPage":null}"#
        let page = try JSONDecoder().decode(EventPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.events.count, 1)
        XCTAssertEqual(page.events[0].when, "Date to be announced")
    }
    func testTicketPaginationContract() throws {
        let json = #"{"tickets":[{"id":"1","name":"Guest","payment_status":"paid","party":{"id":"2","title":"Night","date":"2026-11-05","time":"20:00","banner_url":null}}],"nextPage":1}"#
        let page = try JSONDecoder().decode(TicketPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.nextPage, 1)
        XCTAssertEqual(page.tickets[0].party?.title, "Night")
    }
    func testUKCalendarDateFormatting() { XCTAssertEqual(DisplayDate.format("2026-11-05", time: "20:00:00"), "Thu, 5 Nov · 20:00") }
}
