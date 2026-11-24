#if DEBUG
import Foundation
import Testing
@testable import MacMoshKit

/// The samples CI opens the window on (main window design, section 8, step 3). Debug builds only.
@MainActor @Suite struct SampleWindowTests {
    /// Ready at the first check, Locked from the second on: the window then has a greyed list.
    @Test func readyThenLockedIsReadyFirstThenLocked() {
        let s = SampleWindow.readyThenLocked
        #expect(s.workhorses.map(\.id) == ["workhorse"])
        let first = s.gathered(check: 0), later = s.gathered(check: 1), much = s.gathered(check: 9)
        guard case .checked(let a)? = first.first, case .checked(let b)? = later.first,
              case .checked(let c)? = much.first else {
            Issue.record("every check answers"); return
        }
        #expect(a.state == .ready(signIns: true) && a.status?.desks.count == 5)
        #expect(b.state == .locked && c.state == .locked)
    }

    @Test func itsRefresherKeepsTheReadyCheckForTheGreyedList() async {
        let r = SampleWindow.readyThenLocked.refresher()
        await r.refresh()
        await r.refresh()
        #expect(r.latest["workhorse"]?.state == .locked)
        #expect(r.lastReady["workhorse"]?.state == .ready(signIns: true))
        let board = BoardModel.build(latest: r.latest, lastReady: r.lastReady, checking: r.checking,
                                     order: SampleWindow.readyThenLocked.workhorses, waitingForDeskServer: [],
                                     now: Date(), timeZone: .current)
        #expect(board.workhorses.first?.lastReadyDesks?.count == 6)
    }

    /// Every sample name the app accepts, the menu's and the window's, and nothing else.
    @Test func everySampleNameStartsARun() {
        for name in SampleMenu.allCases.map(\.rawValue) + SampleWindow.allCases.map(\.rawValue) {
            let run = SampleRun.named(name)
            #expect(run?.startedLine == "sample menu: \(name)")
        }
        #expect(SampleRun.named("six-desks")?.workhorses.map(\.id) == ["workhorse"])
        #expect(SampleRun.named("two-workhorses")?.workhorses.map(\.id) == ["workhorse", "spare"])
        #expect(SampleRun.named("no-workhorses")?.workhorses.isEmpty == true)
        #expect(SampleRun.named("ready-then-locked")?.workhorses.map(\.id) == ["workhorse"])
        #expect(SampleRun.named("nope") == nil)
    }

    /// The line CI reads to see which button of the window ran: the action's kind and its words.
    @Test func theRanLineNamesTheActionsWords() {
        #expect(SampleRun.ranLine(.tab(["connect", "workhorse", "api"])) == "sample window ran: tab connect workhorse api")
        #expect(SampleRun.ranLine(.tabs([["connect", "workhorse", "api"], ["connect", "workhorse", "blog"]]))
                == "sample window ran: tabs connect workhorse api connect workhorse blog")
        #expect(SampleRun.ranLine(.run(["screen", "workhorse"])) == "sample window ran: run screen workhorse")
        #expect(SampleRun.ranLine(.refresh) == "sample window ran: refresh")
    }
}
#endif
