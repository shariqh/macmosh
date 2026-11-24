import Foundation
import Testing
@testable import MacMoshKit

/// Which tab records are cleared after a good report (menu design 8.2, issue #120). Pure: the records, the
/// reports, the liveness and the time are all given.
@Suite struct TabRecordSweepTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func record(_ label: String, workhorse: String = "workhorse", openedAt: Date = t0) -> TabRecord {
        sampleTabRecord(label: label, workhorse: workhorse, openedAt: openedAt)
    }

    private let a = "aaaaaaaaaaaaaaaa", b = "bbbbbbbbbbbbbbbb", c = "cccccccccccccccc"

    @Test func aRecordWhoseProcessEndedIsClearedAtTheNextGoodReport() {
        var sweep = TabRecordSweep()
        let cleared = sweep.clear([record(a), record(b)], reports: ["workhorse": [a, b]],
                                  isLive: { $0.label != a }, now: Self.t0)
        #expect(cleared == [a])
    }

    @Test func aLiveRecordOnAViewLineIsKept() {
        var sweep = TabRecordSweep()
        let old = record(a, openedAt: Self.t0.addingTimeInterval(-3600))
        #expect(sweep.clear([old], reports: ["workhorse": [a]], isLive: { _ in true }, now: Self.t0).isEmpty)
    }

    /// Not on any view line yet: kept for two minutes from its opening, then cleared.
    @Test func aRecordNeverSeenIsClearedMoreThanTwoMinutesAfterItOpened() {
        var sweep = TabRecordSweep()
        let fresh = [record(a)]
        #expect(sweep.clear(fresh, reports: ["workhorse": []], isLive: { _ in true }, now: Self.t0.addingTimeInterval(119)).isEmpty)
        #expect(sweep.clear(fresh, reports: ["workhorse": []], isLive: { _ in true }, now: Self.t0.addingTimeInterval(120)).isEmpty)
        #expect(sweep.clear(fresh, reports: ["workhorse": []], isLive: { _ in true }, now: Self.t0.addingTimeInterval(121)) == [a])
        #expect(TabRecordSweep.unseenFor == 120)
    }

    /// Seen, then missing: two minutes from the last good report that showed it, however long ago it opened.
    @Test func aRecordLastSeenIsClearedMoreThanTwoMinutesAfterThat() {
        var sweep = TabRecordSweep()
        let old = [record(a, openedAt: Self.t0.addingTimeInterval(-3600))]
        #expect(sweep.clear(old, reports: ["workhorse": [a]], isLive: { _ in true }, now: Self.t0).isEmpty)
        #expect(sweep.clear(old, reports: ["workhorse": []], isLive: { _ in true }, now: Self.t0.addingTimeInterval(60)).isEmpty)
        #expect(sweep.clear(old, reports: ["workhorse": [a]], isLive: { _ in true }, now: Self.t0.addingTimeInterval(90)).isEmpty)
        #expect(sweep.clear(old, reports: ["workhorse": []], isLive: { _ in true }, now: Self.t0.addingTimeInterval(200)).isEmpty)
        #expect(sweep.clear(old, reports: ["workhorse": []], isLive: { _ in true }, now: Self.t0.addingTimeInterval(211)) == [a])
    }

    /// "Last seen" is kept in memory only: a new sweep, as after the app restarts, knows only the opening time.
    @Test func lastSeenIsNotKeptAcrossSweeps() {
        var first = TabRecordSweep()
        let old = [record(a, openedAt: Self.t0.addingTimeInterval(-3600))]
        _ = first.clear(old, reports: ["workhorse": [a]], isLive: { _ in true }, now: Self.t0)
        var second = TabRecordSweep()
        #expect(second.clear(old, reports: ["workhorse": []], isLive: { _ in true }, now: Self.t0.addingTimeInterval(1)) == [a])
    }

    /// A workhorse with no good report this time clears nothing, not even a dead record.
    @Test func aWorkhorseWithNoGoodReportClearsNothing() {
        var sweep = TabRecordSweep()
        let records = [record(a), record(b, openedAt: Self.t0.addingTimeInterval(-3600))]
        #expect(sweep.clear(records, reports: [:], isLive: { _ in false }, now: Self.t0).isEmpty)
        #expect(sweep.clear(records, reports: ["another": []], isLive: { _ in false }, now: Self.t0).isEmpty)
    }

    @Test func anotherWorkhorsesRecordsAreUntouched() {
        var sweep = TabRecordSweep()
        let records = [record(a, workhorse: "workhorse", openedAt: Self.t0.addingTimeInterval(-3600)),
                       record(b, workhorse: "attic", openedAt: Self.t0.addingTimeInterval(-3600)),
                       record(c, workhorse: "attic")]
        let cleared = sweep.clear(records, reports: ["workhorse": [b, c]], isLive: { $0.label != c }, now: Self.t0)
        #expect(cleared == [a])
    }

    /// A label seen on another workhorse's report doesn't count for this one's record.
    @Test func aLabelCountsOnlyOnItsOwnWorkhorsesReport() {
        var sweep = TabRecordSweep()
        let old = [record(a, openedAt: Self.t0.addingTimeInterval(-3600))]
        #expect(sweep.clear(old, reports: ["workhorse": [], "attic": [a]], isLive: { _ in true }, now: Self.t0) == [a])
    }

    /// The clock moved back after the record was written: as with a fresh record (`DeskTabs`), the distance counts either way.
    @Test func aRecordOpenedMoreThanTwoMinutesInTheFutureIsCleared() {
        var sweep = TabRecordSweep()
        let ahead = [record(a, openedAt: Self.t0.addingTimeInterval(600))]
        #expect(sweep.clear(ahead, reports: ["workhorse": []], isLive: { _ in true }, now: Self.t0) == [a])
        let near = [record(b, openedAt: Self.t0.addingTimeInterval(60))]
        #expect(sweep.clear(near, reports: ["workhorse": []], isLive: { _ in true }, now: Self.t0).isEmpty)
    }

    // MARK: good reports

    @Test func aGoodReportIsACheckThatCameBackWithAStatus() {
        var status = HostStatus.sampleReady
        status.desks = [
            HostStatus.Desk(name: DeskName("website")!, windows: [], windowCount: 2, attached: 2, views: [
                HostStatus.View(name: "website+1", windowId: "@1", tabs: 1, label: a),
                HostStatus.View(name: "website+2", windowId: "@2", tabs: 1, label: nil),
            ]),
            HostStatus.Desk(name: DeskName("notes")!, windows: [], windowCount: 1, attached: 1, views: [
                HostStatus.View(name: "notes+3", windowId: "@3", tabs: 1, label: b),
            ]),
        ]
        let gathered: [Gathered] = [
            .checked(.sample(.ready(signIns: true), workhorse: .sample(id: "workhorse"), status: status)),
            .checked(.sample(.ready(signIns: true), workhorse: .sample(id: "garden"), status: .sampleReady)),
            .checked(.sample(.cantReach(.tailscaleOff), workhorse: .sample(id: "attic"))),
            .stillChecking(.sample(id: "api")),
        ]
        #expect(TabRecordSweep.reports(gathered) == ["workhorse": [a, b], "garden": []])
    }
}
