import Foundation
import Testing
@testable import MacMoshKit

/// One desk in a made-up report: open or not, its views, and its `def` line when it has one.
private struct D {
    var name: String
    var open = true
    var views: [String] = []
    var reopen = true
    var keep = false
    var permanent = false
    var folder: String? = nil
    var command = ""
}

/// A workhorse script 0.11.0 report with these desks, read through `HostStatus.parse` as the app reads one.
private func report(_ desks: [D]) throws -> HostStatus {
    var lines = ["macmosh-host\t1\t0.11.0", "os\t26.1\tarm64", "console\talex", "server\tup", "signins\tok",
                 "agent\tinstalled"]
    var window = 1
    for d in desks where d.open {
        lines.append("desk\t\(d.name)\t1\t\(d.views.count)")
        lines.append("window\t\(d.name)\t0\tzsh")
        lines.append("windowinfo\t\(d.name)\t0\t@\(window)\t1\t\(d.views.count)")
        for v in d.views { lines.append("view\t\(d.name)\t\(v)\t@\(window)\t1\t") }
        window += 1
    }
    for d in desks {
        guard let folder = d.folder else { continue }
        lines.append("def\t\(d.name)\t\(d.reopen ? 1 : 0)\t\(d.keep ? 1 : 0)\t\(d.permanent ? 1 : 0)\t\(folder)\t\(d.command)")
    }
    return try HostStatus.parse((lines + ["end"]).joined(separator: "\n") + "\n")
}

private let attic = Workhorse.sample(id: "attic", name: "Attic", user: "alex")
private let spare = Workhorse.sample(id: "spare", name: "Spare", user: "alex")

/// A Ready check of `w` at that minute of 15 January 2027 (UTC), with these desks.
private func ready(_ desks: [D], _ w: Workhorse = attic, at minute: Int) throws -> CheckResult {
    .sample(.ready(signIns: true), workhorse: w, status: try report(desks), checkedAt: utcDate(2027, 1, 15, 15, minute))
}

/// A check of `w` in another state, with no report.
private func other(_ state: WorkhorseState, _ w: Workhorse = attic, at minute: Int) -> CheckResult {
    .sample(state, workhorse: w, status: nil, checkedAt: utcDate(2027, 1, 15, 15, minute))
}

private extension EndedDeskTracker {
    mutating func feed(_ r: CheckResult, waiting: Bool = false) {
        take([.checked(r)], waiting: waiting ? [r.workhorse.id] : [], onList: ["attic", "spare"])
    }
    func names(_ id: String = "attic") -> [String] { (ended[id] ?? []).map(\.name) }
}

private let recipesFolder = "/Users/alex/Development/my recipes"
private let recipesCommand = #"claude --continue "fix it" $HOME"#
private func recipes(open: Bool = true, def: Bool = true) -> D {
    D(name: "recipes", open: open, reopen: false, keep: true, folder: def ? recipesFolder : nil, command: recipesCommand)
}
private func api(open: Bool = true) -> D { D(name: "api", open: open, folder: "/Users/alex/Development/api") }

/// The ended desks (main window design, sections 7.1 C and 7.2): which desks count as ended, what is kept of
/// each for Start again, and what never shows.
@Suite struct EndedDeskTrackerTests {
    @Test func macMoshStartsWithNothingListed() throws {
        var t = EndedDeskTracker()
        #expect(t.ended.isEmpty)
        // The first Ready check is only what later ones are compared with: a closed desk in it that isn't
        // permanent (a leftover line) ended before MacMosh knew it, so it isn't listed.
        t.feed(try ready([api(), recipes(open: false)], at: 0))
        #expect(t.ended.isEmpty)
    }

    @Test func aDeskThatEndedIsListedWithWhatStartAgainNeeds() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), recipes()], at: 0))
        // Its session is gone and the script has not removed its definition yet: ended at this check.
        t.feed(try ready([api(), recipes(open: false)], at: 10))
        let e = try #require(t.ended["attic"]?.first)
        #expect(t.names() == ["recipes"])
        #expect(e.folder == recipesFolder)   // as the report gave it, not the ~/ form
        #expect(e.command == recipesCommand && !e.reopen && e.keep)
        #expect(e.endedAt == utcDate(2027, 1, 15, 15, 10))
        // A minute later the script removes its definition: it stays listed, as it was first missed.
        t.feed(try ready([api()], at: 11))
        #expect(t.ended["attic"] == [e])
    }

    @Test func aDeskWhoseDefinitionIsAlreadyGoneIsListedToo() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), recipes()], at: 0))
        t.feed(try ready([api()], at: 2))
        #expect(t.ended["attic"]?.first?.folder == recipesFolder)
        #expect(t.ended["attic"]?.first?.endedAt == utcDate(2027, 1, 15, 15, 2))
    }

    @Test func anEmptyCommandIsNone() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api()], at: 0))
        t.feed(try ready([api(open: false)], at: 1))
        t.feed(try ready([api(open: false)], at: 2))   // with reopen: one more check
        #expect(t.ended["attic"]?.first?.command == nil)
        #expect(t.ended["attic"]?.first?.reopen == true)
    }

    @Test func aPermanentDeskThatClosedIsNotListed() throws {
        var t = EndedDeskTracker()
        let notes = D(name: "notes", permanent: true, folder: "/Users/alex/notes")
        t.feed(try ready([notes], at: 0))
        var closed = notes
        closed.open = false
        t.feed(try ready([closed], at: 1))
        #expect(t.ended.isEmpty)
    }

    /// A desk made by hand with tmux has no definition, so no folder is known and it could not be started again.
    @Test func aDeskWithNoDefinitionIsNotListed() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), D(name: "scratch")], at: 0))
        t.feed(try ready([api()], at: 1))
        #expect(t.ended.isEmpty)
    }

    /// A view (a tab on one window of a desk) is a session of its own named after the desk, a plus sign and
    /// digits. The report lists it only under its desk, so one that closes is never a desk that ended.
    @Test func aViewThatClosedIsNotADeskThatEnded() throws {
        var t = EndedDeskTracker()
        var website = D(name: "website", views: ["website+4101", "website+4102"], folder: "/Users/alex/Development/website")
        let before = try report([website])
        #expect(before.desks.map(\.name.value) == ["website"])
        #expect(before.desks.first?.views.map(\.name) == ["website+4101", "website+4102"])
        t.feed(try ready([website], at: 0))
        website.views = []
        t.feed(try ready([website], at: 1))
        #expect(t.ended.isEmpty)
        // A line naming a view as a desk (no script writes one) is no desk at all: `+` is not in a desk's name.
        let odd = try HostStatus.parse("macmosh-host\t1\t0.11.0\ndesk\twebsite+4101\t1\t1\nend\n")
        #expect(odd.desks.isEmpty)
    }

    /// The desk's own session killed by hand while views of it stay: the script lists a view only under its
    /// desk's session and leaves every tagged session out of the desks (`mm_desk_records`), so the report has
    /// nothing of that desk, and it is listed as ended like any other.
    @Test func aDeskWhoseOwnSessionIsGoneWhileItsViewsStayIsListed() throws {
        var t = EndedDeskTracker()
        let website = D(name: "website", views: ["website+4101"], folder: "/Users/alex/Development/website")
        t.feed(try ready([api(), website], at: 0))
        // What the report gives then: no desk line and no view line for website, its definition still there.
        var gone = website
        gone.open = false
        let after = try report([api(), gone])
        #expect(after.desks.map(\.name.value) == ["api"])
        t.feed(try ready([api(), gone], at: 1))
        t.feed(try ready([api(), gone], at: 2))   // with reopen: one more check
        #expect(t.names() == ["website"])
    }

    @Test func aDeskThatComesBackLeavesTheList() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), recipes()], at: 0))
        t.feed(try ready([api(), recipes(open: false)], at: 1))
        #expect(t.names() == ["recipes"])
        // Made again elsewhere, or come back by itself: gone from the list at the check that shows it open.
        t.feed(try ready([api(), recipes()], at: 2))
        #expect(t.ended["attic"]?.isEmpty ?? true)
        // And if it ends again, it is listed again, from that time.
        t.feed(try ready([api(), recipes(open: false)], at: 3))
        #expect(t.ended["attic"]?.map(\.endedAt) == [utcDate(2027, 1, 15, 15, 3)])
    }

    /// Only Ready checks are compared. One in another state changes nothing and is not the one compared with.
    @Test func aCheckThatIsNotReadyChangesNothing() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), recipes()], at: 0))
        t.feed(other(.locked, at: 1))
        t.feed(other(.cantReach(.nothingAnswers), at: 2))
        // Not Ready, but with a report that lists no desk: still not compared.
        var down = try report([])
        down.serverUp = false
        t.feed(.sample(.notSetUp(.deskServerDown), workhorse: attic, status: down, checkedAt: utcDate(2027, 1, 15, 15, 3)))
        #expect(t.ended.isEmpty)
        // The next Ready check is compared with the last Ready one, before them.
        t.feed(try ready([api(), recipes(open: false)], at: 4))
        #expect(t.names() == ["recipes"])
    }

    /// After a restart every desk is gone for a while. While the refresher waits for the desk server nothing
    /// counts; then a desk without reopen that the restart closed is listed, and one with reopen is not.
    @Test func aRestartWhileTheRefresherWaitsForTheDeskServer() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), recipes()], at: 0))   // api comes back after a restart, recipes doesn't
        t.feed(other(.cantReach(.nothingAnswers), at: 1))
        t.feed(other(.waitingForLogin, at: 2))
        var down = try report([api(open: false), recipes(open: false)])
        down.serverUp = false
        let waiting = CheckResult.sample(.notSetUp(.deskServerDown), workhorse: attic, status: down,
                                         checkedAt: utcDate(2027, 1, 15, 15, 3))
        t.feed(waiting, waiting: true)
        // Even a Ready check while it waits counts nothing (the refresher never sends one, as waiting means
        // the desk server is down, but the rule doesn't rest on that).
        t.feed(try ready([], at: 4), waiting: true)
        #expect(t.ended.isEmpty)
        // The restart kept both definitions; api is back.
        t.feed(try ready([api(), recipes(open: false)], at: 5))
        #expect(t.names() == ["recipes"])
        #expect(t.ended["attic"]?.first?.endedAt == utcDate(2027, 1, 15, 15, 5))
    }

    /// The first Ready check after a restart may come while the desks with reopen are still being opened.
    /// Those are given one more Ready check, so the Ended group doesn't flash a desk on its way back.
    @Test func aDeskOnItsWayBackAfterARestartIsNotListed() throws {
        var t = EndedDeskTracker()
        let blog = D(name: "blog", folder: "/Users/alex/Development/blog")
        t.feed(try ready([api(), blog, recipes()], at: 0))
        t.feed(other(.locked, at: 1))
        // The desk server is up, api and blog not open yet, their lines kept; recipes has no reopen.
        t.feed(try ready([api(open: false), blog.closed, recipes(open: false)], at: 2))
        #expect(t.names() == ["recipes"])
        // api is back; blog never came back, so it is listed now, from when it was first missed.
        t.feed(try ready([api(), blog.closed, recipes(open: false)], at: 3))
        #expect(t.names().sorted() == ["blog", "recipes"])
        #expect(t.ended["attic"]?.first { $0.name == "blog" }?.endedAt == utcDate(2027, 1, 15, 15, 2))
        t.feed(try ready([api(), blog.closed, recipes(open: false)], at: 4))
        #expect(t.names().sorted() == ["blog", "recipes"])
    }

    @Test func aDeskRemovedFromTheWindowIsNotListed() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), recipes()], at: 0))
        // The runner says so before it sends the call, so a check landing during the call can't list it.
        t.expectGone(workhorse: "attic", desk: "recipes")
        t.feed(try ready([api(), recipes()], at: 1))   // a check from before the call reached the workhorse
        t.feed(try ready([api()], at: 2))
        #expect(t.ended.isEmpty)
        // The mark is used up: a desk of that name made again and ended later is listed.
        t.feed(try ready([api(), recipes()], at: 3))
        t.feed(try ready([api()], at: 4))
        #expect(t.names() == ["recipes"])
    }

    @Test func aMarkTakenBackLetsTheDeskBeListed() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), recipes()], at: 0))
        t.expectGone(workhorse: "attic", desk: "recipes")
        t.stopExpecting(workhorse: "attic", desk: "recipes")   // the remove failed: nothing was removed
        t.feed(try ready([api(), recipes()], at: 1))   // the mark goes at this Ready check
        t.feed(try ready([api()], at: 2))
        #expect(t.names() == ["recipes"])
    }

    @Test func aDeskRenamedFromTheWindowIsNotListed() throws {
        var t = EndedDeskTracker()
        let blog = D(name: "blog", folder: "/Users/alex/Development/blog")
        t.feed(try ready([api(), blog], at: 0))
        t.expectGone(workhorse: "attic", desk: "blog")
        // Renamed to a name with another folder in the same check: only the window's mark keeps it out.
        let renamed = D(name: "notes-v2", folder: "/Users/alex/notes")
        t.feed(try ready([api(), renamed], at: 1))
        #expect(t.ended.isEmpty)
    }

    /// A rename made in the menu's tab or a terminal: a new desk with the same folder and startup command
    /// appears in the same check in which the old one disappears.
    @Test func aRenameMadeElsewhereIsNotListed() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), recipes()], at: 0))
        var renamed = recipes()
        renamed.name = "recipes-v2"
        t.feed(try ready([api(), renamed], at: 1))
        #expect(t.ended.isEmpty)
        // A new desk in the same folder with another command is not a rename: the old one ended.
        var other = recipes()
        other.name = "cookbook"
        other.command = "zsh"
        t.feed(try ready([api(), other], at: 2))
        #expect(t.names() == ["recipes-v2"])
    }

    @Test func twoWorkhorsesWithADeskOfTheSameName() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), recipes()], attic, at: 0))
        t.feed(try ready([api(), recipes()], spare, at: 0))
        t.feed(try ready([api(), recipes(open: false)], attic, at: 1))
        t.feed(try ready([api(), recipes()], spare, at: 1))
        #expect(t.names("attic") == ["recipes"] && t.names("spare").isEmpty)
        t.feed(try ready([api(), recipes(open: false)], spare, at: 2))
        t.forget(workhorse: "attic", desk: "recipes")
        #expect(t.names("attic").isEmpty && t.names("spare") == ["recipes"])
    }

    /// Kept in memory, at most 20 per workhorse: the oldest goes first. Newest first.
    @Test func atMostTwentyPerWorkhorse() throws {
        var t = EndedDeskTracker()
        let all = (1...25).map { D(name: "d\($0)", folder: "/Users/alex/d\($0)") }
        t.feed(try ready(all, at: 0))
        for n in 1...25 {
            t.feed(try ready(all.dropFirst(n).map { $0 }, at: n))
        }
        #expect(EndedDeskTracker.limit == 20)
        #expect(t.names() == (6...25).reversed().map { "d\($0)" })
    }

    @Test func desksThatEndTogetherAreInNameOrder() throws {
        var t = EndedDeskTracker()
        let blog = D(name: "blog", folder: "/Users/alex/Development/blog")
        t.feed(try ready([api(), blog, recipes()], at: 0))
        t.feed(try ready([api(), recipes()], at: 1))
        t.feed(try ready([], at: 2))
        #expect(t.names() == ["api", "recipes", "blog"])
    }

    @Test func forgetAndAFailedTryChangeOnlyThatEntry() throws {
        var t = EndedDeskTracker()
        let blog = D(name: "blog", folder: "/Users/alex/Development/blog")
        t.feed(try ready([api(), blog], at: 0))
        t.feed(try ready([], at: 1))
        t.failed(workhorse: "attic", desk: "blog", reason: "Attic already has a desk called blog.")
        #expect(t.ended["attic"]?.first { $0.name == "blog" }?.problem == "Attic already has a desk called blog.")
        #expect(t.ended["attic"]?.first { $0.name == "api" }?.problem == nil)
        t.forget(workhorse: "attic", desk: "blog")
        #expect(t.names() == ["api"])
    }

    /// A long gap between two Ready checks (the Mac asleep overnight, the workhorse locked): the desk ended
    /// somewhere in it, so the entry keeps when it was last seen open as well as when it was first missed.
    @Test func aLongGapKeepsWhenTheDeskWasLastSeenOpen() throws {
        var t = EndedDeskTracker()
        t.feed(.sample(.ready(signIns: true), workhorse: attic, status: try report([api(), recipes()]),
                       checkedAt: utcDate(2027, 1, 14, 23, 2)))
        t.feed(.sample(.locked, workhorse: attic, status: nil, checkedAt: utcDate(2027, 1, 14, 23, 30)))
        t.feed(.sample(.ready(signIns: true), workhorse: attic, status: try report([api()]),
                       checkedAt: utcDate(2027, 1, 15, 7, 13)))
        let e = try #require(t.ended["attic"]?.first)
        #expect(e.lastSeenAt == utcDate(2027, 1, 14, 23, 2))
        #expect(e.endedAt == utcDate(2027, 1, 15, 7, 13))
    }

    /// A restart between two Ready checks with no other check between them: the first Ready check after it can
    /// land while the agent is still opening the desks with reopen one by one. A missing desk whose definition is
    /// still there with reopen gets one more Ready check, gap or not.
    @Test func aDeskWithReopenGetsOneMoreCheckEvenWithoutAGap() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), recipes()], at: 0))
        t.feed(try ready([api(open: false), recipes()], at: 1))
        #expect(t.ended.isEmpty)
        // Still not open at the next one: listed, from the check that first missed it.
        t.feed(try ready([api(open: false), recipes()], at: 2))
        #expect(t.names() == ["api"])
        #expect(t.ended["attic"]?.first?.endedAt == utcDate(2027, 1, 15, 15, 1))
        #expect(t.ended["attic"]?.first?.lastSeenAt == utcDate(2027, 1, 15, 15, 0))
        // Back by the next one: never listed.
        var u = EndedDeskTracker()
        u.feed(try ready([api(), recipes()], at: 0))
        u.feed(try ready([api(open: false), recipes()], at: 1))
        u.feed(try ready([api(), recipes()], at: 2))
        u.feed(try ready([api(), recipes()], at: 3))
        #expect(u.ended.isEmpty)
    }

    /// The window removed recipes, and the check after the call was Locked: that check compared nothing, so
    /// taking the mark back then must not let the next Ready check list the desk.
    @Test func aMarkLastsUntilAReadyCheckAfterTheCall() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), recipes()], at: 0))
        t.expectGone(workhorse: "attic", desk: "recipes")
        t.feed(other(.locked, at: 1))
        t.stopExpecting(workhorse: "attic", desk: "recipes")
        t.feed(try ready([api()], at: 2))
        #expect(t.ended.isEmpty)
        // Taken back for good after that Ready check: a desk of that name made again and ended is listed.
        t.feed(try ready([api(), recipes()], at: 3))
        t.feed(try ready([api()], at: 4))
        #expect(t.names() == ["recipes"])
    }

    /// The same when the check after the call never finished in time (`.stillChecking`).
    @Test func aMarkLastsPastACheckThatNeverFinished() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api(), recipes()], at: 0))
        t.expectGone(workhorse: "attic", desk: "recipes")
        t.take([.stillChecking(attic)], waiting: [], onList: ["attic", "spare"])
        t.stopExpecting(workhorse: "attic", desk: "recipes")
        t.feed(try ready([api()], at: 2))
        #expect(t.ended.isEmpty)
    }

    @Test func aWorkhorseOffTheListIsForgotten() throws {
        var t = EndedDeskTracker()
        t.feed(try ready([api()], spare, at: 0))
        t.feed(try ready([], spare, at: 1))
        #expect(t.names("spare") == ["api"])
        t.take([], waiting: [], onList: ["attic"])
        #expect(t.ended["spare"] == nil)
    }
}

private extension D {
    var closed: D {
        var d = self
        d.open = false
        return d
    }
}

/// What the stand-in checks find, changed by a test between checks.
private final class Found: @unchecked Sendable {
    private let lock = NSLock()
    private var desks: [D]
    private var state: WorkhorseState = .ready(signIns: true)
    init(_ desks: [D]) { self.desks = desks }
    func set(_ next: [D], state s: WorkhorseState = .ready(signIns: true)) { lock.withLock { desks = next; state = s } }
    func gather(_ list: [Workhorse]) -> [Gathered] {
        lock.withLock {
            list.map { w in
                .checked(.sample(state, workhorse: w, status: try? report(desks), checkedAt: Date()))
            }
        }
    }
}

/// The tracker belongs to the app: the refresher feeds it from every check, whether the window is open or not,
/// and publishes what it lists; the window's board shows it.
@MainActor @Suite struct EndedDeskRefresherTests {
    @Test func theRefresherListsADeskThatEndedAndTheBoardShowsIt() async throws {
        let found = Found([api(), recipes()])
        let r = MenuRefresher(load: { [attic] }, gather: { found.gather($0) }, save: { _ in }, log: { _ in }, pause: { _ in })
        let screen = BoardOnScreen(refresher: r, load: { [attic] }, log: { _ in })
        await r.refresh()
        #expect(r.ended.isEmpty)
        found.set([api()])
        await r.refresh()
        #expect(r.ended["attic"]?.map(\.name) == ["recipes"])
        #expect(r.ended["attic"]?.first?.folder == recipesFolder)
        await screen.reloadList()
        #expect(screen.board.workhorses.first?.ended.map(\.name) == ["recipes"])
        #expect(screen.board.workhorses.first?.ended.first?.shownFolder == "~/Development/my recipes")
        // The menu is built as before: it never lists an ended desk.
        #expect(!r.menu.items.contains { $0.title.contains("recipes") })

        r.endedFailed(id: "attic", desk: "recipes", reason: "The folder must exist on Attic.")
        #expect(r.ended["attic"]?.first?.problem == "The folder must exist on Attic.")
        #expect(screen.board.workhorses.first?.ended.first?.problem == "The folder must exist on Attic.")
        r.forgetEnded(id: "attic", desk: "recipes")
        #expect(r.ended.isEmpty)
        #expect(screen.board.workhorses.first?.ended.isEmpty == true)
    }

    @Test func aDeskTheWindowRemovesIsNotListed() async throws {
        let found = Found([api(), recipes()])
        let r = MenuRefresher(load: { [attic] }, gather: { found.gather($0) }, save: { _ in }, log: { _ in }, pause: { _ in })
        await r.refresh()
        r.expectGone(id: "attic", desk: "recipes")
        found.set([api()])
        await r.refresh()
        #expect(r.ended.isEmpty)
        r.stopExpecting(id: "attic", desk: "recipes")
    }

    @Test func aWaitForTheDeskServerCountsNothing() async throws {
        let found = Found([api(), recipes()])
        let r = MenuRefresher(load: { [attic] }, gather: { found.gather($0) }, save: { _ in }, log: { _ in }, pause: { _ in })
        await r.refresh()
        found.set([], state: .waitingForLogin)
        await r.refresh()
        // Logged in: the desk server isn't up yet, and the refresher waits for it (issue #88).
        found.set([], state: .notSetUp(.deskServerDown))
        await r.refresh()
        #expect(r.waitingForDeskServer == ["attic"])
        #expect(r.ended.isEmpty)
        // Up: api came back (reopen), recipes (no reopen) didn't.
        found.set([api(), recipes(open: false)])
        await r.refresh()
        #expect(r.ended["attic"]?.map(\.name) == ["recipes"])
    }
}
