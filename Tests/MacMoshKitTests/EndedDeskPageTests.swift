import Foundation
import Testing
@testable import MacMoshKit

private let attic = Workhorse.sample(id: "attic", name: "Attic", user: "alex", osVersion: "27.3", arch: "arm64")

/// `Fixtures/status/desks-board.txt` (script 0.8.0), after `edit` changed its text: website, api, garden
/// (permanent), recipes and blog open; notes permanent and closed; shop a leftover line.
private func boardReport(_ edit: (String) -> String = { $0 }) throws -> HostStatus {
    try HostStatus.parse(edit(fixture("status/desks-board.txt")))
}

private func ended(_ name: String, folder: String = "/Users/alex/Development/recipes", command: String? = "claude",
                   at: Date = utcDate(2027, 1, 15, 15, 10)) -> EndedDesk {
    EndedDesk(name: name, folder: folder, command: command, reopen: true, keep: false, endedAt: at)
}

/// Attic's page in `state`, from the fixture's report, with these ended desks.
private func page(_ list: [EndedDesk], state: WorkhorseState = .ready(signIns: true), status: HostStatus? = nil,
                  activity: WindowActivity = WindowActivity()) throws -> WorkhorsePage {
    let r = CheckResult.sample(state, workhorse: attic, status: try status ?? boardReport(), homeReachable: true,
                               checkedAt: utcDate(2027, 1, 15, 15, 30))
    let board = BoardModel.build(latest: ["attic": r], lastReady: ["attic": r], checking: [], order: [attic],
                                 waitingForDeskServer: [], ended: ["attic": list], now: formatNow, timeZone: formatZone)
    let w = try #require(board.workhorses.first)
    return WorkhorsePage(w, now: formatNow, timeZone: formatZone, activity: activity)
}

private func titles(_ row: EndedRow) -> [String] { row.buttons.map(\.title) }
private func enabled(_ row: EndedRow) -> [Bool] { row.buttons.map(\.isEnabled) }

/// The Ended group in the window (main window design, section 7.1 C): its words, its buttons and when they are off.
@Suite struct EndedDeskPageTests {
    // MARK: the row's words

    @Test func todayItSaysTheTime() throws {
        let row = try #require(try page([ended("recipes")]).ended.first)
        #expect(row.name == "recipes")
        #expect(row.when == "ended about 15:10")
        #expect(row.second == "~/Development/recipes · started with claude")
    }

    @Test func anotherDaySaysWhichInPlainWords() {
        let at = { (d: Int, y: Int) in EndedRow.when(utcDate(y, 1, d, 15, 10), now: formatNow, timeZone: formatZone) }
        #expect(at(14, 2027) == "ended yesterday about 15:10")
        #expect(at(3, 2027) == "ended on 3 Jan about 15:10")
        #expect(at(3, 2026) == "ended on 3 Jan 2026 about 15:10")
        // The time zone is the one passed in: at 16:00 UTC it is already the 16th in Tokyo.
        let tokyo = try! #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(EndedRow.when(utcDate(2027, 1, 15, 3, 0), now: formatNow, timeZone: tokyo) == "ended yesterday about 12:00")
    }

    @Test func noCommandIsTheFolderAlone() throws {
        let row = try #require(try page([ended("blog", folder: "/Users/alex/Development/blog", command: nil)]).ended.first)
        #expect(row.second == "~/Development/blog")
    }

    /// One line each. A long command is whole in the words (the view cuts the line on screen) and in what Start
    /// again sends (`WindowActionRunnerTests`).
    @Test func aLongCommandIsWholeInTheWords() throws {
        let long = "claude --continue --model a-very-long-model-name " + String(repeating: "--flag ", count: 30)
        let row = try #require(try page([ended("recipes", command: long)]).ended.first)
        #expect(row.second == "~/Development/recipes · started with " + long)
        #expect(!row.second.contains("\n") && !row.when.contains("\n"))
    }

    @Test func aFolderOutsideTheHomeFolderIsShownInFull() throws {
        let row = try #require(try page([ended("recipes", folder: "/opt/projects/recipes")]).ended.first)
        #expect(row.second == "/opt/projects/recipes · started with claude")
    }

    // MARK: the group

    @Test func theGroupShowsOnlyWhenThereIsAnEndedDesk() throws {
        let none = try page([])
        #expect(none.endedHeading == nil && none.ended.isEmpty)
        let some = try page([ended("recipes"), ended("shop", folder: "/Users/alex/Development/shop")])
        #expect(some.endedHeading == "Ended")
        #expect(some.ended.map(\.name) == ["recipes", "shop"])
    }

    @Test func eachHasThreeButtons() throws {
        let row = try #require(try page([ended("shop")]).ended.first)
        #expect(titles(row) == ["Start again", "Start again and keep it", "Forget"])
        #expect(row.buttons.map(\.action) == [
            .window(.startAgain(workhorse: "attic", desk: "shop", keepIt: false)),
            .window(.startAgain(workhorse: "attic", desk: "shop", keepIt: true)),
            .window(.forget(workhorse: "attic", desk: "shop")),
        ])
        #expect(enabled(row) == [true, true, true])
        #expect(row.note == nil)
    }

    /// "Start again and keep it" sends `--permanent`, which a script older than 0.5.0 doesn't know.
    @Test func keepItIsHiddenForAScriptOlderThan050() throws {
        let old = try boardReport { $0.replacingOccurrences(of: "macmosh-host\t1\t0.8.0", with: "macmosh-host\t1\t0.4.2") }
        #expect(old.scriptVersion == "0.4.2")
        let row = try #require(try page([ended("shop")], status: old).ended.first)
        #expect(titles(row) == ["Start again", "Forget"])
        let new = try boardReport { $0.replacingOccurrences(of: "macmosh-host\t1\t0.8.0", with: "macmosh-host\t1\t0.5.0") }
        #expect(titles(try #require(try page([ended("shop")], status: new).ended.first)).count == 3)
    }

    /// Taken by the script's rule: an open desk (website), or a permanent one (notes, closed). A leftover line (shop)
    /// is not, because the script replaces it. Both Start again buttons are off with the reason; Forget is not.
    @Test func bothAreOffWithTheReasonWhenTheNameIsTaken() throws {
        let p = try page([ended("notes"), ended("shop"), ended("website")])
        let notes = try #require(p.ended.first { $0.name == "notes" })
        #expect(enabled(notes) == [false, false, true])
        #expect(notes.note == "Attic already has a desk called notes.")
        let website = try #require(p.ended.first { $0.name == "website" })
        #expect(enabled(website) == [false, false, true])
        #expect(website.note == "Attic already has a desk called website.")
        let shop = try #require(p.ended.first { $0.name == "shop" })
        #expect(enabled(shop) == [true, true, true] && shop.note == nil)
    }

    @Test func aFailedTrysReasonShowsNextToIt() throws {
        var e = ended("shop")
        e.problem = "The folder must exist on Attic."
        let row = try #require(try page([e]).ended.first)
        #expect(row.note == "The folder must exist on Attic.")
        #expect(enabled(row) == [true, true, true])
    }

    /// One action per desk name: while one runs on shop, its three buttons are off and Start again reads
    /// "Starting…"; cookbook stays usable.
    @Test func offWhileAnActionForThatNameRuns() throws {
        let p = try page([ended("cookbook"), ended("shop")], activity: WindowActivity(busy: ["shop": .startAgain]))
        let shop = try #require(p.ended.first { $0.name == "shop" })
        #expect(enabled(shop) == [false, false, false])
        #expect(titles(shop) == ["Starting…", "Start again and keep it", "Forget"])
        let cookbook = try #require(p.ended.first { $0.name == "cookbook" })
        #expect(enabled(cookbook) == [true, true, true])
        // An action on an open desk of the same name counts too.
        let renaming = try page([ended("shop")], activity: WindowActivity(busy: ["shop": .rename]))
        #expect(enabled(try #require(renaming.ended.first)) == [false, false, false])
    }

    /// Under a workhorse that is not Ready nothing can be started (`DeskFlow` stops before any ssh), and the page
    /// shows the greyed list of its last Ready check with the state's hint: the Ended group is not shown. The
    /// ended desks stay in memory and come back with the next Ready check.
    @Test func notShownUnderAWorkhorseThatIsNotReady() throws {
        for state: WorkhorseState in [.locked, .waitingForLogin, .cantReach(.nothingAnswers), .notSetUp(.deskServerDown)] {
            let p = try page([ended("recipes")], state: state)
            #expect(p.endedHeading == nil && p.ended.isEmpty, "\(state)")
            #expect(p.stale != nil, "\(state)")
        }
    }

    // MARK: the board

    /// The board keeps every ended desk with its three buttons and the taken reason, whatever the state; the page
    /// decides what shows.
    @Test func theBoardSetsTheTakenReason() throws {
        let r = CheckResult.sample(.ready(signIns: true), workhorse: attic, status: try boardReport(), checkedAt: formatNow)
        let board = BoardModel.build(latest: ["attic": r], lastReady: [:], checking: [], order: [attic],
                                     waitingForDeskServer: [], ended: ["attic": [ended("garden"), ended("shop")]],
                                     now: formatNow, timeZone: formatZone)
        let w = try #require(board.workhorses.first)
        #expect(w.ended.map(\.taken) == ["Attic already has a desk called garden.", nil])
        #expect(w.ended.allSatisfy { $0.buttons.count == 3 })
    }
}
