import Core
import Foundation
import Testing
@testable import Features

private func day(_ iso: String) -> CalendarDay { CalendarDay(iso: iso)! }

private func request(_ id: String, _ status: VacationStatus, _ start: String, _ end: String, reason: String? = nil)
    -> VacationRequestSummary
{
    VacationRequestSummary(
        id: id, status: status, start: day(start), end: day(end), countedDays: 1, approver: "Maria Keller",
        reason: reason)
}

@Suite("FR-VAC-007 My requests")
struct MyRequestsTests {
    @Test("FR-VAC-007.1: pending first, then decided per year, newest year first")
    func groupsByStatusAndYear() {
        let groups = MyRequestsGrouping.groups([
            request("a", .approved, "2025-08-04", "2025-08-08"),
            request("b", .rejected, "2026-03-02", "2026-03-04", reason: "Inventory week"),
            request("c", .pending, "2026-12-28", "2026-12-30"),
            request("d", .approved, "2026-11-02", "2026-11-06"),
            request("e", .cancelled, "2026-01-12", "2026-01-12"),
        ])
        #expect(groups.map(\.id) == ["pending", "decided-2026", "decided-2025"])
        #expect(groups[1].items.map(\.id) == ["e", "b", "d"])  // by start date
        #expect(groups[1].items[1].reason == "Inventory week")
    }

    @Test("FR-VAC-007: no requests means no groups")
    func emptyHasNoGroups() {
        #expect(MyRequestsGrouping.groups([]).isEmpty)
    }

    @Test("FR-VAC-007: no pending requests means no pending group")
    func noPendingGroup() {
        let groups = MyRequestsGrouping.groups([request("a", .approved, "2026-06-01", "2026-06-05")])
        #expect(groups.map(\.id) == ["decided-2026"])
    }
}
