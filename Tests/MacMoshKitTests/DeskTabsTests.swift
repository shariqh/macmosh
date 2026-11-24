import Foundation
import Testing
@testable import MacMoshKit

/// Which tabs show which windows (menu design 8.2): the report's `windowinfo` and `view` lines joined with the
/// live tab records. Pure; "now" is fixed.
@Suite struct DeskTabsTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func window(_ index: Int, _ id: String, tabs: Int, deskShows: Bool = false) -> HostStatus.Window {
        HostStatus.Window(index: index, name: "w\(index)", id: id, deskShows: deskShows, tabs: tabs)
    }

    private func desk(_ windows: [HostStatus.Window], views: [HostStatus.View] = [],
                      name: String = "website") -> HostStatus.Desk {
        HostStatus.Desk(name: DeskName(name)!, windows: windows, windowCount: windows.count, attached: 0, views: views)
    }

    private func view(_ windowId: String, _ label: String?, tabs: Int = 1) -> HostStatus.View {
        HostStatus.View(name: "website+\(label ?? "none")", windowId: windowId, tabs: tabs, label: label)
    }

    private func record(_ label: String, workhorse: String = "mbp", desk: String = "website", asked: String = "",
                        secondsAgo: Double = 600) -> TabRecord {
        sampleTabRecord(label: label, workhorse: workhorse, desk: desk, askedWindow: asked,
                        openedAt: Self.now.addingTimeInterval(-secondsAgo))
    }

    private func build(_ d: HostStatus.Desk, _ records: [TabRecord], now: Date = DeskTabsTests.now) -> [DeskTabs.WindowTabs] {
        DeskTabs.build(desk: d, workhorse: "mbp", records: records, now: now)
    }

    @Test func aTabOnAViewLineIsFoundForItsWindow() {
        let d = desk([window(0, "@0", tabs: 1, deskShows: true), window(1, "@1", tabs: 1)],
                     views: [view("@1", "aaaaaaaaaaaaaaaa")])
        let tabs = build(d, [record("aaaaaaaaaaaaaaaa")])
        #expect(tabs == [
            DeskTabs.WindowTabs(windowId: "@0", index: 0, labels: [], newest: nil, others: 1),
            DeskTabs.WindowTabs(windowId: "@1", index: 1, labels: ["aaaaaaaaaaaaaaaa"], newest: "aaaaaaaaaaaaaaaa", others: 0),
        ])
    }

    @Test func noTabsMeansNothingFoundAndNoOthers() {
        let tabs = build(desk([window(0, "@0", tabs: 0)]), [])
        #expect(tabs == [DeskTabs.WindowTabs(windowId: "@0", index: 0, labels: [], newest: nil, others: 0)])
    }

    @Test func twoTabsOnOneWindowGiveTheMostRecentlyOpened() {
        let d = desk([window(0, "@3", tabs: 3)],
                     views: [view("@3", "aaaaaaaaaaaaaaaa"), view("@3", "bbbbbbbbbbbbbbbb"), view("@3", nil)])
        let tabs = build(d, [record("bbbbbbbbbbbbbbbb", secondsAgo: 100), record("aaaaaaaaaaaaaaaa", secondsAgo: 900)])
        #expect(tabs.first?.labels == ["aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb"])
        #expect(tabs.first?.newest == "bbbbbbbbbbbbbbbb")
        #expect(tabs.first?.others == 1)
    }

    /// A tab opened a moment ago that the report doesn't list yet counts for the window it asked for.
    @Test func aFreshRecordNotInTheReportCountsForItsAskedWindow() {
        let d = desk([window(0, "@0", tabs: 1), window(1, "@1", tabs: 0)])
        let tabs = build(d, [record("aaaaaaaaaaaaaaaa", asked: "@1", secondsAgo: 30)])
        #expect(tabs[1].labels == ["aaaaaaaaaaaaaaaa"] && tabs[1].newest == "aaaaaaaaaaaaaaaa")
        #expect(tabs[1].others == 0)
        #expect(tabs[0].labels.isEmpty && tabs[0].others == 1)
    }

    @Test(arguments: [120.0, 121.0, 3600.0])
    func afterTwoMinutesAFreshRecordNoLongerCounts(_ secondsAgo: Double) {
        let d = desk([window(1, "@1", tabs: 0)])
        #expect(build(d, [record("aaaaaaaaaaaaaaaa", asked: "@1", secondsAgo: secondsAgo)]).first?.labels == [])
    }

    @Test func justUnderTwoMinutesItStillCounts() {
        let d = desk([window(1, "@1", tabs: 0)])
        #expect(build(d, [record("aaaaaaaaaaaaaaaa", asked: "@1", secondsAgo: 119.9)]).first?.labels == ["aaaaaaaaaaaaaaaa"])
    }

    /// A fresh tab that asked for a new window or a view asked for no window, so it counts nowhere yet.
    @Test func aFreshRecordThatAskedForNoWindowCountsNowhere() {
        let d = desk([window(0, "@0", tabs: 1)])
        let tabs = build(d, [record("aaaaaaaaaaaaaaaa", asked: "", secondsAgo: 5)])
        #expect(tabs.first?.labels == [] && tabs.first?.others == 1)
    }

    /// The view line wins over the window asked for: the label follows the person when they switch windows.
    @Test func aLabelThatFollowsAWindowSwitchMovesToTheNewWindow() {
        let d = desk([window(0, "@3", tabs: 0), window(1, "@5", tabs: 1)], views: [view("@5", "aaaaaaaaaaaaaaaa")])
        for secondsAgo in [5.0, 600.0] {
            let tabs = build(d, [record("aaaaaaaaaaaaaaaa", asked: "@3", secondsAgo: secondsAgo)])
            #expect(tabs[0].labels == [] && tabs[1].labels == ["aaaaaaaaaaaaaaaa"])
        }
    }

    /// The desk's name in the record is for logs only: after a rename the record still joins by label.
    @Test func afterARenameTheRecordStillJoinsByLabel() {
        let d = desk([window(0, "@0", tabs: 1)], views: [view("@0", "aaaaaaaaaaaaaaaa")], name: "notes")
        let tabs = build(d, [record("aaaaaaaaaaaaaaaa", desk: "website")])
        #expect(tabs.first?.labels == ["aaaaaaaaaaaaaaaa"])
    }

    @Test func anotherWorkhorsesRecordsAreIgnored() {
        let d = desk([window(0, "@0", tabs: 2)], views: [view("@0", "aaaaaaaaaaaaaaaa")])
        let tabs = build(d, [record("aaaaaaaaaaaaaaaa", workhorse: "daily-mac"),
                             record("bbbbbbbbbbbbbbbb", workhorse: "daily-mac", asked: "@0", secondsAgo: 5)])
        #expect(tabs.first?.labels == [] && tabs.first?.others == 2)
    }

    /// A tab the report has not counted yet makes the findable tabs more than the count: never below 0.
    @Test func otherTabsAreNeverBelowZero() {
        let d = desk([window(0, "@0", tabs: 1)], views: [view("@0", "aaaaaaaaaaaaaaaa")])
        let tabs = build(d, [record("aaaaaaaaaaaaaaaa"), record("bbbbbbbbbbbbbbbb", asked: "@0", secondsAgo: 5)])
        #expect(tabs.first?.labels.count == 2 && tabs.first?.others == 0)
    }

    /// A label on a view line that no record has (a tab another Mac opened, or one whose record died) is
    /// one of the other tabs.
    @Test func aLabelWithoutALiveRecordIsAnOtherTab() {
        let d = desk([window(0, "@0", tabs: 2)], views: [view("@0", "aaaaaaaaaaaaaaaa"), view("@0", "cccccccccccccccc")])
        let tabs = build(d, [record("aaaaaaaaaaaaaaaa")])
        #expect(tabs.first?.labels == ["aaaaaaaaaaaaaaaa"] && tabs.first?.others == 1)
    }

    /// A report from a script before 0.7.0 has no window ids, so nothing can be joined.
    @Test func windowsWithoutWindowInfoGiveNothing() {
        let d = desk([HostStatus.Window(index: 0, name: "zsh")])
        #expect(build(d, [record("aaaaaaaaaaaaaaaa", asked: "@0", secondsAgo: 5)]).isEmpty)
    }
}
