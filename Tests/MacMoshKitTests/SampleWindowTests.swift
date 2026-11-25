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

    /// A desk with a long folder that is kept when it exits and doesn't come back after a restart, and a
    /// desk made by hand: CI's picture shows their second lines whole.
    @Test func longFolderHasADeskWithEveryUnusualFact() async {
        let s = SampleWindow.longFolder
        let r = s.refresher()
        await r.refresh()
        let board = BoardModel.build(latest: r.latest, lastReady: r.lastReady, checking: r.checking,
                                     order: s.workhorses, waitingForDeskServer: [], now: Date(), timeZone: .current)
        let rows = board.workhorses.first.map { WorkhorsePage($0, now: Date(), timeZone: .current).desks } ?? []
        #expect(rows.map(\.name) == ["notes", "website-redesign"])
        #expect(rows.first?.second == WindowWords.notMadeWithMacMosh)
        #expect(rows.last?.second
                == "~/Development/clients/acme/website-redesign · Kept when it exits · Doesn't come back after a restart")
    }

    /// The saved list can't be read: the menu shows the store's sentence, and the window's selection
    /// is that sentence rather than Add a Mac.
    @Test func unreadableListCantBeRead() async {
        let r = SampleWindow.unreadableList.refresher()
        await r.refresh()
        #expect(r.latest.isEmpty)
        #expect(throws: StoreError.unreadable("workhorses.json: not JSON")) { try SampleWindow.unreadableList.load() }
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
        #expect(SampleRun.named("long-folder")?.workhorses.map(\.id) == ["workhorse"])
        #expect(SampleRun.named("unreadable-list")?.workhorses.isEmpty == true)
        #expect((try? SampleRun.named("six-desks")?.load())?.map(\.id) == ["workhorse"])
        #expect(throws: StoreError.unreadable("workhorses.json: not JSON")) { try SampleRun.named("unreadable-list")?.load() }
        #expect(SampleRun.named("window-forms")?.workhorses.map(\.id) == ["attic"])
        #expect(SampleRun.named("window-settings")?.workhorses.map(\.id) == ["attic", "spare"])
        #expect(SampleRun.named("nope") == nil)
    }

    // MARK: the settings sample (issue 157)

    /// The Settings page's sample writes a saved list of its own, in a temporary folder named after the app's
    /// process, never the person's: the Settings page and the board both read it, and CI reads the file.
    @Test func theSettingsSampleHasAStoreOfItsOwnInATemporaryFolder() throws {
        let paths = SampleSettings.paths
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
        #expect(paths.supportDir.standardizedFileURL.path.hasPrefix(temporary))
        #expect(paths.supportDir.path.contains("macmosh-sample-settings-\(ProcessInfo.processInfo.processIdentifier)"))
        #expect(paths.supportDir.path != Paths.forHome(FileManager.default.homeDirectoryForCurrentUser, environment: [:]).supportDir.path)
        let run = try #require(SampleRun.named("window-settings"))
        #expect(run.settingsPaths.supportDir == paths.supportDir)
        #expect(try run.load().map(\.id) == ["attic", "spare"])
        let saved = try WorkhorseStore(paths: paths).load()
        #expect(saved.map(\.name) == ["Attic", "Spare"])
        #expect(saved.last?.mode == .tabs)
    }

    /// Any other sample's Settings page reads a stand-in with that sample's workhorses, never the real folder: none
    /// for no-workhorses, and a list that can't be read for unreadable-list, as the sidebar shows them.
    @Test func everyOtherSampleHasAStandInForTheSettingsPage() throws {
        let real = Paths.forHome(FileManager.default.homeDirectoryForCurrentUser, environment: [:]).supportDir.path
        for name in SampleMenu.allCases.map(\.rawValue) + SampleWindow.allCases.map(\.rawValue) {
            let run = try #require(SampleRun.named(name))
            #expect(run.settingsPaths.supportDir.path != real)
            let store = WorkhorseStore(paths: run.settingsPaths)
            if name == "unreadable-list" {
                #expect(throws: StoreError.self) { try store.load() }
            } else {
                #expect(try store.load().map(\.id) == run.workhorses.map(\.id), "\(name)")
            }
        }
    }

    // MARK: the forms sample (step 4)

    /// The stand-in reads the remote command back as the workhorse's shell would.
    @Test func theStandInSplitsWhatShellQuoteJoins() {
        let args = ["desk-new", "garden_planner", "~/Development/garden planner", "--command",
                    #"claude --continue "fix it" $HOME; echo 'done'"#, ""]
        #expect(SampleSSH.split(ShellQuote.join(args)) == args)
    }

    /// It answers as the script would: a taken name is refused with exit 7, and a desk made, renamed or removed
    /// shows in the next report.
    @Test func theStandInAnswersAsTheScriptWould() throws {
        let desks = SampleDesks()
        #expect(desks.run(["desk-new", "api", "~/Development/api", "--reopen"]).0 == 7)
        #expect(desks.run(["desk-new", "notes", "~/notes", "--reopen"]).0 == 7)
        #expect(desks.run(["desk-new", "garden-planner", "~/Development/garden-planner", "--reopen", "--command", "claude --continue"]).0 == 0)
        var status = try HostStatus.parse(desks.report())
        #expect(status.desks.map(\.name.value) == ["api", "blog", "website", "garden-planner"])
        #expect(status.definitions.first { $0.name.value == "garden-planner" }?.folder == "/Users/alex/Development/garden-planner")
        #expect(status.definitions.first { $0.name.value == "garden-planner" }?.command == "claude --continue")
        #expect(desks.run(["desk-rename", "api", "blog"]).0 == 7)
        #expect(desks.run(["desk-rename", "api", "api-v2"]).0 == 0)
        #expect(desks.run(["desk-remove", "website", "--kill"]).0 == 0)
        #expect(desks.run(["desk-remove", "website", "--kill"]).0 == 4)
        status = try HostStatus.parse(desks.report())
        #expect(status.desks.map(\.name.value) == ["api-v2", "blog", "garden-planner"])
    }

    /// window-name as the script 0.11.0 answers it (issue 144): the desk's window by its id takes the name; --auto
    /// gives back its program's name; a window that isn't the desk's is exit 4 with "That window has closed."; no
    /// such desk is exit 4; a name that breaks the rule is exit 2. The report gives every window's id.
    @Test func theStandInNamesWindowsAsTheScriptWould() throws {
        let desks = SampleDesks()
        var status = try HostStatus.parse(desks.report())
        #expect(status.scriptVersion == "0.11.0")
        let website = try #require(status.desks.first { $0.name.value == "website" })
        #expect(website.windows.map(\.name) == ["claude", "zsh", "vim"])
        let ids = website.windows.compactMap(\.id)
        #expect(ids.count == 3 && Set(ids).count == 3)
        #expect(status.desks.allSatisfy { $0.hasWindowInfo })
        #expect(desks.run(["window-name", "website", ids[2], "front end"]).0 == 0)
        status = try HostStatus.parse(desks.report())
        #expect(status.desks.first { $0.name.value == "website" }?.windows.map(\.name) == ["claude", "zsh", "front end"])
        #expect(desks.run(["window-name", "website", ids[2], "--auto"]).0 == 0)
        status = try HostStatus.parse(desks.report())
        #expect(status.desks.first { $0.name.value == "website" }?.windows.map(\.name) == ["claude", "zsh", "vim"])
        let closed = desks.run(["window-name", "website", "@99", "x"])
        #expect(closed.0 == 4 && closed.1 == "That window has closed.\n")
        let other = try #require(status.desks.first { $0.name.value == "blog" }?.windows.first?.id)
        #expect(desks.run(["window-name", "website", other, "x"]).0 == 4)
        #expect(desks.run(["window-name", "nowhere", ids[0], "x"]).0 == 4)
        #expect(desks.run(["window-name", "website", ids[0], "a#b"]).0 == 2)
        // A desk made later gets a window with an id of its own.
        #expect(desks.run(["desk-new", "garden-planner", "~/Development/garden-planner", "--reopen"]).0 == 0)
        status = try HostStatus.parse(desks.report())
        let made = try #require(status.desks.first { $0.name.value == "garden-planner" }?.windows.first?.id)
        #expect(!ids.contains(made) && made != other)
    }

    @Test func theStandInsLineHasTheExactRemoteCommand() {
        let line = SampleSSH.line(argv: ["ssh", "-o", "BatchMode=yes", "--", "alex@192.168.1.20", "~/.macmosh/macmosh-host desk-remove website --kill"],
                                  to: "alex@192.168.1.20", stdin: nil, timeout: .seconds(15),
                                  remote: "~/.macmosh/macmosh-host desk-remove website --kill")
        #expect(line == "sample ssh: to=alex@192.168.1.20 batch=yes stdin=closed limit=15s run=~/.macmosh/macmosh-host desk-remove website --kill")
    }

    /// Attic has no projects folder saved, so the form starts with the line that saves one.
    @Test func theFormsSampleStartsWithNoProjectsFolder() {
        let check = SampleForms.result(SampleForms.attic)
        #expect(check.workhorse.projectsFolder == nil && check.answeredAt == "192.168.1.20")
        let form = NewDeskForm(check: check, saved: SampleForms.attic)
        #expect(form.folders == .noProjectsFolder && form.canKeepClosed)
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
