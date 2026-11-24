import Foundation
import Testing
@testable import MacMoshKit

/// The workhorse Attic, whose user is alex.
private let attic = Workhorse.sample(id: "attic", name: "Attic", user: "alex", osVersion: "27.3", arch: "arm64")

/// The recorded report `Fixtures/status/desks-board.txt` (script 0.8.0), read through `HostStatus.parse`,
/// after `edit` has changed its text.
private func boardReport(_ edit: (String) -> String = { $0 }) throws -> HostStatus {
    try HostStatus.parse(edit(fixture("status/desks-board.txt")))
}

private let checkedAt = utcDate(2027, 1, 15, 14, 2)
private let readyAt = utcDate(2027, 1, 15, 8, 57)

/// Attic in `state`, from the fixture's report unless `status` is given.
private func result(_ state: WorkhorseState, workhorse: Workhorse = attic, status: HostStatus?,
                    homeReachable: Bool? = true, at: Date = checkedAt) -> CheckResult {
    .sample(state, workhorse: workhorse, status: status, homeReachable: homeReachable, checkedAt: at)
}

private func board(_ latest: [CheckResult], lastReady: [CheckResult] = [], checking: Set<String> = [],
                   order: [Workhorse]? = nil, waiting: Set<String> = [], ended: [String: [EndedDesk]] = [:],
                   results: [String: String] = [:]) -> Board {
    BoardModel.build(latest: Dictionary(latest.map { ($0.workhorse.id, $0) }, uniquingKeysWith: { a, _ in a }),
                     lastReady: Dictionary(lastReady.map { ($0.workhorse.id, $0) }, uniquingKeysWith: { a, _ in a }),
                     checking: checking, order: order ?? latest.map(\.workhorse),
                     waitingForDeskServer: waiting, ended: ended, results: results,
                     now: formatNow, timeZone: formatZone)
}

private func titles(_ buttons: [BoardButton]) -> [String] { buttons.map(\.title) }

@Suite struct BoardModelTests {
    // MARK: Ready, from the recorded report

    @Test func theFixtureGivesSixDesksInNameOrderAndNotTheLeftover() throws {
        let status = try boardReport()
        #expect(status.scriptVersion == "0.8.0")
        let w = try #require(board([result(.ready(signIns: true), status: status)]).workhorses.first)
        #expect(w.desks.map(\.name) == ["api", "blog", "garden", "notes", "recipes", "website"])
        #expect(w.desks.map(\.isOpen) == [true, true, true, false, true, true])
        #expect(w.lastReadyDesks == nil && w.lastReadyAt == nil)
    }

    @Test func aReadyWorkhorseCarriesTheMenusWordsAndItsButtons() throws {
        let status = try boardReport()
        let r = result(.ready(signIns: true), status: status)
        let b = board([r])
        let w = try #require(b.workhorses.first)
        #expect(w.id == "attic" && w.name == "Attic")
        #expect(w.state == .ready(signIns: true))
        #expect(w.symbol == "checkmark.circle" && b.symbol == "checkmark.circle")
        #expect(w.headline == "Attic · Ready")
        #expect(w.hint == nil)
        #expect(w.summary == StatusFormat.summaryLine(status))
        #expect(w.summary == "Sign-ins working · Awake on power · Lid-closed mode on · On power, 100%")
        #expect(w.homeReachable == true)
        #expect(w.checkedAt == checkedAt && !w.isChecking && !w.isWaitingForDeskServer)
        #expect(titles(w.buttons) == ["Open the 2 not in a tab", "New desk…", "Share screen",
                                      "Turn off lid-closed mode…", "Restart…", "Run the checklist…"])
        #expect(w.buttons.map(\.action) == [
            .window(.openAllWithoutTab(workhorse: "attic", desks: ["garden", "recipes"])),
            .window(.newDesk(workhorse: "attic")),
            .menu(.run(["screen", "attic"])),
            .menu(.tab(["power", "attic", "lid", "off"])),
            .menu(.tab(["restart", "attic"])),
            .menu(.tab(["prepare", "attic", "--pause"])),
        ])
        #expect(w.buttons.allSatisfy { $0.note == nil })
        #expect(w.result == nil && w.ended.isEmpty)
    }

    /// Script 0.7.0 and newer give each window its id and tabs; a desk without those lines still has its names.
    @Test func anOpenDeskMadeWithMacMoshHasItsWindowsFolderCommandAndFlags() throws {
        let w = try #require(board([result(.ready(signIns: true), status: try boardReport())]).workhorses.first)
        let website = try #require(w.desks.first { $0.name == "website" })
        #expect(website.windows == [
            BoardWindow(index: 0, name: "claude", id: "@1", tabs: 1),
            BoardWindow(index: 1, name: "zsh", id: "@2", tabs: 1),
            BoardWindow(index: 2, name: "vim", id: "@3", tabs: 0),
        ])
        #expect(website.windowNames == ["claude", "zsh", "vim"])
        #expect(website.windowCount == 3 && website.tabsOpen == 2)
        #expect(website.folder == "~/Development/website")
        #expect(website.command == "claude --continue")
        #expect(website.reopen == true && website.keep == true && website.permanent == false)
        #expect(website.madeByMacMosh)
        #expect(website.open == BoardButton(title: "Open website", action: .menu(.tab(["connect", "attic", "website"]))))
        #expect(website.buttons == [
            BoardButton(title: "New window", action: .menu(.run(["desk", "window", "attic", "website"]))),
            BoardButton(title: "Rename website…", action: .window(.rename(workhorse: "attic", desk: "website"))),
            BoardButton(title: "Remove website…", action: .window(.remove(workhorse: "attic", desk: "website"))),
        ])

        let api = try #require(w.desks.first { $0.name == "api" })
        #expect(api.windows.map(\.id) == ["@5", "@6"] && api.windows.map(\.tabs) == [1, 0])
        #expect(api.command == nil)   // saved with no startup command: a plain shell

        let garden = try #require(w.desks.first { $0.name == "garden" })
        #expect(garden.windows == [BoardWindow(index: 0, name: "claude", id: nil, tabs: nil)])
        #expect(garden.permanent == true && garden.tabsOpen == 0 && garden.command == "claude")

        let recipes = try #require(w.desks.first { $0.name == "recipes" })
        #expect(recipes.reopen == false)                      // doesn't come back after a restart
        #expect(recipes.folder == "/opt/projects/recipes")    // outside the home folder: in full
    }

    /// A desk made by hand with tmux: on the board, not made by MacMosh, no folder and no flags, and
    /// the same buttons the menu gives it.
    @Test func aDeskWithNoDefinitionIsNotMadeByMacMoshAndHasNoFolderOrFlags() throws {
        let w = try #require(board([result(.ready(signIns: true), status: try boardReport())]).workhorses.first)
        let blog = try #require(w.desks.first { $0.name == "blog" })
        #expect(blog.isOpen && !blog.madeByMacMosh)
        #expect(blog.folder == nil && blog.command == nil)
        #expect(blog.reopen == nil && blog.keep == nil && blog.permanent == nil)
        #expect(blog.windowNames == ["claude", "zsh"] && blog.tabsOpen == 1)
        #expect(titles(blog.buttons) == ["New window", "Rename blog…", "Remove blog…"])
        #expect(blog.open?.action == .menu(.tab(["connect", "attic", "blog"])))
    }

    /// A permanent desk whose session is gone shows as closed, with Open (which makes it again); a
    /// definition with no session that is not permanent (shop) is a leftover and is not on the board.
    @Test func aClosedPermanentDeskIsThereAndALeftoverIsNot() throws {
        let w = try #require(board([result(.ready(signIns: true), status: try boardReport())]).workhorses.first)
        let notes = try #require(w.desks.first { $0.name == "notes" })
        #expect(!notes.isOpen && notes.windows.isEmpty && notes.windowCount == 0 && notes.tabsOpen == 0)
        #expect(notes.folder == "~/notes" && notes.permanent == true && notes.madeByMacMosh)
        #expect(notes.open?.action == .menu(.tab(["connect", "attic", "notes"])))
        #expect(titles(notes.buttons) == ["Rename notes…", "Remove notes…"])
        #expect(!w.desks.contains { $0.name == "shop" })
    }

    /// With every running desk in a tab, "Open the N not in a tab" is left out.
    @Test func openTheOnesNotInATabIsLeftOutWhenEveryDeskHasATab() throws {
        let status = try boardReport { text in
            text.replacingOccurrences(of: "desk\tgarden\t1\t0", with: "desk\tgarden\t1\t1")
                .replacingOccurrences(of: "desk\trecipes\t1\t0", with: "desk\trecipes\t1\t1")
        }
        let w = try #require(board([result(.ready(signIns: true), status: status)]).workhorses.first)
        #expect(titles(w.buttons).first == "New desk…")
        let one = try boardReport { $0.replacingOccurrences(of: "desk\tgarden\t1\t0", with: "desk\tgarden\t1\t1") }
        let w1 = try #require(board([result(.ready(signIns: true), status: one)]).workhorses.first)
        #expect(w1.buttons.first == BoardButton(title: "Open the 1 not in a tab",
                                                action: .window(.openAllWithoutTab(workhorse: "attic", desks: ["recipes"]))))
    }

    @Test func readyWithSignInsOffHasTheHintAndFixFirst() throws {
        let status = try boardReport { $0.replacingOccurrences(of: "signins\tok", with: "signins\toff") }
        let r = result(.ready(signIns: false), status: status)
        let b = board([r])
        let w = try #require(b.workhorses.first)
        #expect(w.headline == "Attic · Ready, sign-ins off")
        #expect(w.hint == "Tools that keep logins in the keychain look signed out here.")
        #expect(w.symbol == "exclamationmark.circle" && b.symbol == "exclamationmark.circle")
        #expect(w.summary?.hasPrefix("Sign-ins off") == true)
        #expect(titles(w.buttons) == ["Fix…", "Open the 2 not in a tab", "New desk…", "Share screen",
                                      "Turn off lid-closed mode…", "Restart…", "Run the checklist…"])
        #expect(w.desks.count == 6)
    }

    // MARK: Every state that is not Ready

    /// Locked: the hint, Unlock disk…, the checklist, no desks of its own, and the greyed list of the
    /// desks at the last Ready check, with its time. The greyed desks have no buttons.
    @Test func lockedHasUnlockAndTheGreyedListWithItsTime() throws {
        let ready = result(.ready(signIns: true), status: try boardReport(), at: readyAt)
        let b = board([result(.locked, status: nil, homeReachable: nil)], lastReady: [ready])
        let w = try #require(b.workhorses.first)
        #expect(w.headline == "Attic · Locked after a restart")
        #expect(w.hint == "The disk is locked until someone types the Mac's password.")
        #expect(w.symbol == "lock.circle" && b.symbol == "lock.circle")
        #expect(titles(w.buttons) == ["Unlock disk…  (you type the Mac's password)", "Run the checklist…"])
        #expect(w.buttons.first?.action == .menu(.tab(["unlock", "attic"])))
        #expect(w.desks.isEmpty && w.summary == nil && w.homeReachable == nil)
        let greyed = try #require(w.lastReadyDesks)
        #expect(w.lastReadyAt == readyAt)
        #expect(greyed.map(\.name) == ["api", "blog", "garden", "notes", "recipes", "website"])
        #expect(greyed.first { $0.name == "recipes" }?.reopen == false)
        #expect(greyed.first { $0.name == "website" }?.folder == "~/Development/website")
        #expect(greyed.allSatisfy { $0.buttons.isEmpty && $0.open == nil })
    }

    @Test func lockedOnAMacThatCantBeUnlockedOverSSHHasNoUnlockButton() throws {
        let old = Workhorse.sample(id: "attic", name: "Attic", user: "alex", osVersion: "15.6", arch: "arm64")
        let w = try #require(board([result(.locked, workhorse: old, status: nil)]).workhorses.first)
        #expect(w.hint == "The disk is locked until someone types the Mac's password. Unlock it at the Mac.")
        #expect(titles(w.buttons) == ["Run the checklist…"])
        #expect(w.lastReadyDesks == nil && w.lastReadyAt == nil)   // no Ready check since MacMosh started
    }

    @Test func waitingForLoginHasLogInAndTheGreyedList() throws {
        let ready = result(.ready(signIns: true), status: try boardReport(), at: readyAt)
        let report = try boardReport { $0.replacingOccurrences(of: "console\talex", with: "console\t")
            .replacingOccurrences(of: "server\tup", with: "server\tdown") }
        let w = try #require(board([result(.waitingForLogin, status: report)], lastReady: [ready]).workhorses.first)
        #expect(w.headline == "Attic · Waiting for login")
        #expect(w.hint == "It is on and unlocked, but nobody has logged in.")
        #expect(w.symbol == "person.crop.circle.badge.questionmark")
        #expect(titles(w.buttons) == ["Log in…  (opens Screen Sharing)", "Run the checklist…"])
        #expect(w.desks.isEmpty && w.summary == nil)
        #expect(w.lastReadyDesks?.count == 6 && w.lastReadyAt == readyAt)
    }

    /// "Now" and the time zone are passed in, and shape the hint's "Last seen".
    @Test func cantReachHasTheHintWithTheTimeItWasLastSeen() throws {
        let seen = Workhorse.sample(id: "attic", name: "Attic", user: "alex", lastSeen: utcDate(2027, 1, 15, 14, 2))
        let w = try #require(board([result(.cantReach(.tailscaleOff), workhorse: seen, status: nil, homeReachable: nil)])
            .workhorses.first)
        #expect(w.headline == "Attic · Can't reach it")
        #expect(w.hint == "Last seen 14:02. Tailscale is off on this Mac.")
        #expect(w.symbol == "wifi.slash")
        #expect(titles(w.buttons) == ["Run the checklist…"])
    }

    @Test func cantVerifyHasOnlyTheChecklist() throws {
        let w = try #require(board([result(.cantVerify, status: nil, homeReachable: nil)]).workhorses.first)
        #expect(w.headline == "Attic · Can't verify it")
        #expect(w.hint?.hasPrefix("Something answers at its address with a different key.") == true)
        #expect(w.symbol == "exclamationmark.triangle")
        #expect(titles(w.buttons) == ["Run the checklist…"])
    }

    @Test func needsSettingUpAndNotPairedHaveTheirButtons() throws {
        let w = try #require(board([result(.notSetUp(.hostScriptMissing), status: nil)]).workhorses.first)
        #expect(w.headline == "Attic · Needs setting up")
        #expect(w.hint == "Run: macmosh prepare attic --fix")
        #expect(w.symbol == "wrench.and.screwdriver")
        #expect(titles(w.buttons) == ["Finish setting up…", "Run the checklist…"])
        let p = try #require(board([result(.notSetUp(.notPaired), status: nil)]).workhorses.first)
        #expect(titles(p.buttons) == ["Pair…", "Run the checklist…"])
        #expect(p.buttons.first?.action == .menu(.tab(["pair", "attic"])))
    }

    /// Just logged in to, with the desk server not started yet: the wait, not the fix, and it adds
    /// nothing to the symbol. Without the wait the same result is "Desk server is off".
    @Test func waitingForTheDeskServerShowsTheWaitAndAddsNothingToTheSymbol() throws {
        let report = try boardReport { $0.replacingOccurrences(of: "server\tup", with: "server\tdown") }
        let down = result(.notSetUp(.deskServerDown), status: report)
        let b = board([down], waiting: ["attic"])
        let w = try #require(b.workhorses.first)
        #expect(w.isWaitingForDeskServer)
        #expect(w.headline == "Attic · Waiting for the desk server")
        #expect(w.hint == MenuModel.waitingForDeskServerHint)
        #expect(titles(w.buttons) == ["Run the checklist…"])
        #expect(w.symbol == "ellipsis.circle" && b.symbol == "ellipsis.circle")
        #expect(w.state == .notSetUp(.deskServerDown))

        let off = try #require(board([down]).workhorses.first)
        #expect(!off.isWaitingForDeskServer)
        #expect(off.headline == "Attic · Desk server is off")
        #expect(titles(off.buttons) == ["Finish setting up…", "Run the checklist…"])
        #expect(off.symbol == "wrench.and.screwdriver")
    }

    // MARK: Checking

    @Test func aWorkhorseThatHasNeverAnsweredIsStillChecking() throws {
        let b = board([], checking: ["attic"], order: [attic])
        let w = try #require(b.workhorses.first)
        #expect(w.state == nil && w.checkedAt == nil && w.isChecking)
        #expect(w.headline == "Attic · Still checking…")
        #expect(w.hint == nil && w.summary == nil && w.desks.isEmpty && w.lastReadyDesks == nil)
        #expect(titles(w.buttons) == ["Run the checklist…"])
        #expect(w.symbol == "ellipsis.circle" && b.symbol == "ellipsis.circle")
    }

    /// A check that is running keeps the last result on the board, marked as checking. It never goes blank.
    @Test func aCheckThatIsRunningKeepsTheLastResult() throws {
        let r = result(.ready(signIns: true), status: try boardReport())
        let still = board([r], lastReady: [r], checking: ["attic"])
        let done = board([r], lastReady: [r])
        let w = try #require(still.workhorses.first)
        #expect(w.isChecking)
        #expect(!(try #require(done.workhorses.first)).isChecking)
        #expect(w.headline == "Attic · Ready" && w.desks.count == 6 && w.checkedAt == checkedAt)
        var unmarked = w
        unmarked.isChecking = false
        #expect(unmarked == done.workhorses.first)
        #expect(still.symbol == "checkmark.circle")
    }

    // MARK: The list of workhorses

    @Test func theWorkhorsesFollowTheSavedOrderAndOnlyThose() throws {
        let den = Workhorse.sample(id: "den", name: "Den", user: "alex")
        let gone = Workhorse.sample(id: "gone", name: "Gone", user: "alex")
        let latest = [result(.ready(signIns: true), status: try boardReport()),
                      result(.locked, workhorse: den, status: nil),
                      result(.cantVerify, workhorse: gone, status: nil)]
        let b = board(latest, order: [den, attic])
        #expect(b.workhorses.map(\.id) == ["den", "attic"])
        // The most urgent of the states on the board, as the menu picks it; Gone (Can't verify) is not on it.
        #expect(b.symbol == "lock.circle")
        // A saved list edited by hand can name an id twice: it is on the board once.
        #expect(board(latest, order: [attic, den, attic]).workhorses.map(\.id) == ["attic", "den"])
    }

    @Test func noWorkhorsesGivesAnEmptyBoard() {
        let b = board([])
        #expect(b.workhorses.isEmpty)
        #expect(b.symbol == "plus.circle")
    }

    // MARK: What is passed in

    @Test func theResultLineAndTheEndedDesksArePassedThrough() throws {
        let shop = EndedDesk(name: "shop", folder: "/Users/alex/Development/shop", command: "claude", reopen: true,
                             keep: false, endedAt: utcDate(2027, 1, 15, 15, 10))
        let b = board([result(.ready(signIns: true), status: try boardReport())],
                      ended: ["attic": [shop], "den": [shop]],
                      results: ["attic": "Created the desk garden on Attic.", "den": "x"])
        let w = try #require(b.workhorses.first)
        #expect(w.result == "Created the desk garden on Attic.")
        let ended = try #require(w.ended.first)
        #expect(w.ended.count == 1)
        #expect(ended.name == "shop" && ended.folder == "/Users/alex/Development/shop")
        #expect(ended.shownFolder == "~/Development/shop")
        #expect(ended.command == "claude" && ended.reopen && !ended.keep && ended.endedAt == utcDate(2027, 1, 15, 15, 10))
        #expect(ended.buttons == [
            BoardButton(title: "Start again", action: .window(.startAgain(workhorse: "attic", desk: "shop", keepIt: false))),
            BoardButton(title: "Start again and keep it",
                        action: .window(.startAgain(workhorse: "attic", desk: "shop", keepIt: true))),
            BoardButton(title: "Forget", action: .window(.forget(workhorse: "attic", desk: "shop"))),
        ])
    }

    // MARK: The short folder

    @Test func aFolderInsideTheUsersHomeIsShownWithATilde() {
        #expect(BoardModel.shortFolder("/Users/alex/Development/api", user: "alex") == "~/Development/api")
        #expect(BoardModel.shortFolder("/Users/alex/notes", user: "alex") == "~/notes")
        #expect(BoardModel.shortFolder("/Users/alex", user: "alex") == "~")
    }

    @Test func aFolderOutsideTheUsersHomeIsShownInFull() {
        #expect(BoardModel.shortFolder("/opt/projects/recipes", user: "alex") == "/opt/projects/recipes")
        #expect(BoardModel.shortFolder("/Volumes/Attic/alex/notes", user: "alex") == "/Volumes/Attic/alex/notes")
        #expect(BoardModel.shortFolder("/Users/alexander/api", user: "alex") == "/Users/alexander/api")
        #expect(BoardModel.shortFolder("/Users/alex/api", user: "") == "/Users/alex/api")
    }

    @Test func aFolderInAnotherUsersHomeIsShownInFull() {
        #expect(BoardModel.shortFolder("/Users/sam/Development/api", user: "alex") == "/Users/sam/Development/api")
        #expect(BoardModel.shortFolder("/Users/Shared/api", user: "alex") == "/Users/Shared/api")
    }

    /// The board's user is the workhorse's: another user on the same Mac sees their own home shortened.
    @Test func theShortFolderUsesTheWorkhorsesUser() throws {
        let sam = Workhorse.sample(id: "attic", name: "Attic", user: "sam")
        let w = try #require(board([result(.ready(signIns: true), workhorse: sam, status: try boardReport())])
            .workhorses.first)
        #expect(w.desks.first { $0.name == "website" }?.folder == "/Users/alex/Development/website")
    }
}
