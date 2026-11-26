import Foundation
import Testing
@testable import MacMoshKit

/// Attic, whose user is alex, with its projects folder saved as typed.
private func attic(projects: String? = "~/Development", last: String? = nil) -> Workhorse {
    var w = Workhorse.sample(id: "attic", name: "Attic", user: "alex", projectsFolder: projects)
    w.lastDeskCommand = last
    return w
}

/// A Ready check of Attic from `Fixtures/status/desks-board.txt`: open desks website, api, garden, recipes and
/// blog (blog made by hand); notes permanent and closed; shop a leftover definition with no session.
private func boardCheck(version: String = "0.8.0", _ w: Workhorse = attic()) throws -> CheckResult {
    var status = try HostStatus.parse(fixture("status/desks-board.txt"))
    status.scriptVersion = version
    return .sample(.ready(signIns: true), workhorse: w, status: status, answeredAt: "workhorse")
}

private func form(version: String = "0.8.0", saved: Workhorse = attic()) throws -> NewDeskForm {
    NewDeskForm(check: try boardCheck(version: version, saved), saved: saved)
}

/// The window's New desk form (main window design, section 7.5): every field's rule, its default, and the
/// request it sends.
@Suite struct NewDeskFormTests {
    // MARK: the words

    @Test func theTitleAndLabelsAreTheDesigns() throws {
        let f = try form()
        #expect(f.title == "New desk on Attic")
        #expect(f.folderHeading == "Folder in ~/Development")
        #expect(NewDeskForm.Words.orAPath == "Or a path, full or starting with ~:")
        #expect(NewDeskForm.Words.nameHelp == "Letters, digits, - and _ only.")
        #expect(NewDeskForm.Words.commandHelp == "Leave it empty for a plain shell.")
        #expect(NewDeskForm.Words.comesBack == "Comes back")
        #expect(NewDeskForm.Words.removeTheDesk == "Remove the desk")
        #expect(NewDeskForm.Words.keepItClosed == "Keep it, closed")
        #expect(NewDeskForm.Words.openInATabNow == "Open it in a tab now")
        #expect(NewDeskForm.Words.makeDesk == "Make desk" && NewDeskForm.Words.making == "Making…")
    }

    // MARK: the defaults

    @Test func theDefaultsAreHisRulings() throws {
        let f = try form()
        #expect(f.chosen == nil && f.typedPath.isEmpty && f.name.isEmpty)
        #expect(f.comesBack && !f.keepClosed && f.openInTab)
        #expect(f.command == "")
        #expect(f.folders == .reading)
        #expect(!f.canMake)
    }

    @Test func theCommandStartsAsTheLastOneSent() throws {
        #expect(try form(saved: attic(last: "claude --continue")).command == "claude --continue")
    }

    // MARK: the folder list

    @Test func foldersThatHaveADeskAreMarkedButCanBeChosen() throws {
        var f = try form()
        f.folders = .listed(["api", "blog", "garden-planner", "shop", "website"])
        #expect(f.rows.map(\.name) == ["api", "blog", "garden-planner", "shop", "website"])
        // api and website are open desks with those folders. blog was made by hand, so its folder is not known;
        // shop's definition is a leftover with no session, which the board does not show.
        #expect(f.rows.filter(\.hasDesk).map(\.name) == ["api", "website"])
        #expect(f.rows.first?.note == "(has a desk)")
        #expect(f.rows[2].note == nil)
        f.choose("api")
        #expect(f.chosen == "api" && f.folderPath == "~/Development/api")
    }

    @Test func theFilterKeepsTheFoldersThatHoldItInAnyCase() throws {
        var f = try form()
        f.folders = .listed(["api", "Garden-Planner", "garden-tools", "website"])
        f.filter = "GARDEN"
        #expect(f.rows.map(\.name) == ["Garden-Planner", "garden-tools"])
        f.filter = "  "
        #expect(f.rows.count == 4)
    }

    @Test func aProjectsFolderWithAFullPathMarksItsDesksToo() throws {
        let w = attic(projects: "/Users/alex/Development/")
        var f = NewDeskForm(check: try boardCheck(w), saved: w)
        f.folders = .listed(["api", "garden-planner"])
        #expect(f.rows.filter(\.hasDesk).map(\.name) == ["api"])
        f.choose("garden-planner")
        #expect(f.folderPath == "/Users/alex/Development/garden-planner")
    }

    @Test func withNoProjectsFolderTheFormAsksForOne() throws {
        let f = try form(saved: attic(projects: nil))
        #expect(f.folders == .noProjectsFolder)
        #expect(f.projectsFolderLine == "Projects folder on Attic:")
        #expect(f.projectsFolderDraft == "~/Development")
        #expect(NewDeskForm.Words.save == "Save")
        #expect(try form(saved: attic(projects: "")).folders == .noProjectsFolder)
    }

    @Test func aSavedProjectsFolderFillsTheList() throws {
        var f = try form(saved: attic(projects: nil))
        f.projectsFolderSaved("~/Code")
        #expect(f.projectsFolder == "~/Code" && f.folders == .reading)
        #expect(f.folderHeading == "Folder in ~/Code")
    }

    // MARK: the path and the name

    @Test func aChosenFolderNamesTheDesk() throws {
        var f = try form()
        f.choose("garden-planner")
        #expect(f.name == "garden-planner")
        f.choose("recipes")
        #expect(f.name == "recipes")
    }

    @Test func theNameIsMadeToFit() {
        #expect(NewDeskForm.name(fromFolder: "~/Development/garden planner") == "garden-planner")
        #expect(NewDeskForm.name(fromFolder: "/Users/alex/Café.app/") == "Caf--app")
        #expect(NewDeskForm.name(fromFolder: "~/x/" + String(repeating: "a", count: 80)) == String(repeating: "a", count: 64))
        #expect(NewDeskForm.name(fromFolder: "~") == "")
        #expect(NewDeskForm.name(fromFolder: "my_site-2") == "my_site-2")
    }

    @Test func aTypedPathWinsOverTheList() throws {
        var f = try form()
        f.choose("garden-planner")
        f.setTypedPath("  ~/notes/journal ")
        #expect(f.folderPath == "~/notes/journal")
        #expect(f.name == "journal")
        f.setTypedPath("")
        #expect(f.folderPath == "~/Development/garden-planner" && f.name == "garden-planner")
    }

    @Test func aNameHeTypedIsKeptWhenTheFolderChanges() throws {
        var f = try form()
        f.choose("garden-planner")
        f.setName("plants")
        f.choose("recipes")
        #expect(f.name == "plants")
        // Cleared, it follows the folder again.
        f.setName("")
        f.choose("website-two")
        #expect(f.name == "website-two")
    }

    @Test func aTypedPathMustBeFullOrStartWithATilde() throws {
        var f = try form()
        f.setTypedPath("Development/x")
        #expect(f.problems.contains("Type a full path, starting with / or with ~."))
        f.setTypedPath("/opt/x")
        #expect(f.folderProblem == nil)
    }

    /// Under the path field: nothing while it is empty (Make desk just waits for a folder, section 7.5), then
    /// why a typed path can't be used.
    @Test func theLineUnderThePathSaysWhyATypedPathIsRefused() throws {
        var f = try form()
        #expect(f.pathLine == nil)
        f.choose("garden-planner")
        #expect(f.pathLine == nil)
        f.setTypedPath("Development/garden")
        #expect(f.pathLine == "Type a full path, starting with / or with ~.")
        #expect(!f.canMake)
        f.setTypedPath("~/x\ty")
        #expect(f.pathLine == "A path can't contain a tab or a new line.")
        f.setTypedPath("~/x")
        #expect(f.pathLine == nil)
        f.setTypedPath("/x")
        #expect(f.pathLine == nil)
        f.setTypedPath("")
        #expect(f.pathLine == nil)
    }

    /// Save is off while the projects folder field is empty, and the saved value is the trimmed one.
    @Test func anEmptyProjectsFolderCantBeSaved() throws {
        var f = try form(saved: attic(projects: nil))
        #expect(f.canSaveProjectsFolder)
        f.projectsFolderDraft = "  "
        #expect(!f.canSaveProjectsFolder)
        f.projectsFolderDraft = " ~/Code "
        #expect(f.projectsFolderToSave == "~/Code")
        f.projectsFolderSaved(" ~/Code ")
        #expect(f.projectsFolder == "~/Code")
        #expect(f.folders == .reading)
    }

    // MARK: the name rules

    @Test func theNameIsCheckedAsTyped() throws {
        var f = try form()
        f.choose("garden-planner")
        f.setName("garden planner")
        #expect(f.nameProblem == DeskFormat.nameRule)
        f.setName(String(repeating: "a", count: 65))
        #expect(f.nameProblem == DeskFormat.nameRule)
        f.setName("")
        #expect(f.nameProblem == "Give the desk a name.")
        f.setName("garden-planner")
        #expect(f.nameProblem == nil && f.canMake)
    }

    /// The script's rule: a name is taken by an open desk or a permanent one; a leftover definition is not.
    @Test func aNameIsTakenByTheScriptsRule() throws {
        var f = try form()
        f.choose("x")
        for taken in ["website", "api", "garden", "recipes", "blog", "notes"] {
            f.setName(taken)
            #expect(f.nameProblem == "Attic already has a desk called \(taken).", "\(taken)")
            #expect(!f.canMake)
        }
        f.setName("shop")
        #expect(f.nameProblem == nil, "a leftover definition does not count")
        f.setName("Website")
        #expect(f.nameProblem == nil, "names differ by case, as tmux's do")
    }

    /// Under the name: its help line until something is typed, then what is wrong with it, if anything.
    @Test func theLineUnderTheNameIsItsHelpUntilSomethingIsWrong() throws {
        var f = try form()
        #expect(f.nameLine == "Letters, digits, - and _ only." && !f.nameLineIsProblem)
        #expect(f.nameProblem == "Give the desk a name.")
        f.setName("api")
        #expect(f.nameLine == "Attic already has a desk called api." && f.nameLineIsProblem)
        f.setName("garden-planner")
        #expect(f.nameLine == "Letters, digits, - and _ only." && !f.nameLineIsProblem)
        #expect(f.commandLine == "Leave it empty for a plain shell." && !f.commandLineIsProblem)
        f.command = "a\tb"
        #expect(f.commandLine == "A command to start can't contain a tab or a new line." && f.commandLineIsProblem)
    }

    // MARK: the command

    @Test func aTabOrANewLineInTheCommandIsRefused() throws {
        var f = try form()
        f.choose("garden-planner")
        for bad in ["claude\t--continue", "claude\n", "a\rb"] {
            f.command = bad
            #expect(f.commandProblem == "A command to start can't contain a tab or a new line.")
            #expect(!f.canMake)
        }
    }

    @Test func theCommandIsSentExactlyAsTyped() throws {
        var f = try form()
        f.choose("garden-planner")
        f.command = #"claude --continue "fix it" $HOME; echo 'done'"#
        #expect(f.request?.command == #"claude --continue "fix it" $HOME; echo 'done'"#)
        #expect(f.commandToSave == #"claude --continue "fix it" $HOME; echo 'done'"#)
    }

    @Test func anEmptyCommandIsAPlainShell() throws {
        var f = try form(saved: attic(last: "claude"))
        f.choose("garden-planner")
        f.command = ""
        #expect(f.request?.command == nil && f.commandToSave == nil)
        f.command = "   "
        #expect(f.request?.command == nil && f.commandToSave == nil)
    }

    // MARK: the request

    @Test func theRequestCarriesEveryField() throws {
        var f = try form()
        f.choose("garden-planner")
        f.command = "claude"
        #expect(f.request == NewDeskRequest(name: "garden-planner", folder: "~/Development/garden-planner",
                                            reopen: true, keep: false, permanent: false, command: "claude"))
        f.comesBack = false
        f.keepClosed = true
        #expect(f.request == NewDeskRequest(name: "garden-planner", folder: "~/Development/garden-planner",
                                            reopen: false, keep: false, permanent: true, command: "claude"))
        #expect(f.request?.isInteractive == false)
    }

    @Test func makeDeskIsOffWithEachReason() throws {
        var f = try form()
        #expect(f.problems == ["Pick a folder, or type a path.", "Give the desk a name."])
        f.choose("garden-planner")
        f.command = "a\tb"
        #expect(f.problems == ["A command to start can't contain a tab or a new line."])
        #expect(f.request == nil)
    }

    // MARK: an older script

    @Test func keepItClosedIsHiddenForAScriptOlderThan050() throws {
        #expect(try form(version: "0.4.9").canKeepClosed == false)
        #expect(try form(version: "0.5.0").canKeepClosed == true)
        var old = try form(version: "0.4.0")
        old.choose("garden-planner")
        old.keepClosed = true
        #expect(old.request?.permanent == false)
    }
}

/// The Rename form and the Remove confirmation (main window design, section 7.2).
@Suite struct RenameAndRemoveTests {
    @Test func theRenameFormStartsWithTheOldName() throws {
        let f = RenameForm(check: try boardCheck(), desk: "api")
        #expect(f.title == "Rename api" && f.label == "New name for api" && f.name == "api")
        #expect(RenameForm.Words.rename == "Rename" && RenameForm.Words.renaming == "Renaming…")
        #expect(!f.canRename && f.problem == nil)
    }

    @Test func theNewNameIsCheckedAsTheFormChecksIt() throws {
        var f = RenameForm(check: try boardCheck(), desk: "api")
        f.name = "api v2"
        #expect(f.problem == DeskFormat.nameRule)
        f.name = "website"
        #expect(f.problem == "Attic already has a desk called website.")
        f.name = "notes"
        #expect(f.problem == "Attic already has a desk called notes.")
        f.name = "shop"
        #expect(f.problem == nil && f.canRename && f.newName == DeskName("shop"))
        f.name = ""
        #expect(f.problem == "Give the desk a name." && !f.canRename)
    }

    @Test func theRemoveConfirmationSaysWhatTheTerminalSays() throws {
        let check = try boardCheck()
        let c = try #require(RemoveConfirmation(check: check, desk: "website"))
        #expect(c.title == "Remove website?")
        #expect(c.message == "This removes the desk website and closes its 3 windows (claude, zsh, vim), with whatever is running in them.")
        #expect(c.button == "Remove website" && RemoveConfirmation.cancel == "Cancel")
        let notes = try #require(RemoveConfirmation(check: check, desk: "notes"))
        #expect(notes.message == "This removes the desk notes. It has no open windows.")
        #expect(RemoveConfirmation(check: check, desk: "shop") == nil, "the board does not show a leftover")
    }

    @Test func theConfirmationStillMatchesOnlyTheSameDesk() throws {
        let check = try boardCheck()
        let c = try #require(RemoveConfirmation(check: check, desk: "website"))
        #expect(c.stillMatches(check))
        // A window's new name is no change to the desk.
        var renamedWindow = check
        renamedWindow.status?.desks[0].windows[0].name = "node"
        #expect(c.stillMatches(renamedWindow))
        // Gone (closed or renamed).
        var gone = check
        gone.status?.desks.removeFirst()
        #expect(!c.stillMatches(gone))
        // Another desk now has its name: other windows.
        var other = check
        other.status?.desks[0].windows = [.init(index: 0, name: "zsh", id: "@40")]
        other.status?.desks[0].windowCount = 1
        #expect(!c.stillMatches(other))
        // A closed permanent desk that has been opened again.
        let notes = try #require(RemoveConfirmation(check: check, desk: "notes"))
        var reopened = check
        reopened.status?.desks.append(.init(name: DeskName("notes")!, windows: [.init(index: 0, name: "zsh")], windowCount: 1, attached: 0))
        #expect(!notes.stillMatches(reopened))
    }
    // MARK: look step 4 (design 6.8 and 7)

    /// Look design 6.8: one line beside Make desk only when it is off for want of a folder.
    @Test func makeDeskSaysWhyOnlyWhenNoFolderIsChosen() throws {
        var f = try form()
        #expect(NewDeskForm.Words.chooseAFolderFirst == "Choose a folder first.")
        #expect(!f.canMake && f.makeReason == "Choose a folder first.")
        f.choose("garden-planner")
        #expect(f.canMake && f.makeReason == nil)
        f.setName("api")                                   // taken: the refusal under the name is the reason
        #expect(!f.canMake && f.makeReason == nil && f.nameLineIsProblem)
        f.setName("garden-planner"); f.setTypedPath("Development/x")   // a bad typed path: its line says why
        #expect(!f.canMake && f.makeReason == nil && f.pathLine == "Type a full path, starting with / or with ~.")
        let none = try form(saved: attic(projects: nil))   // no projects folder yet
        #expect(none.folders == .noProjectsFolder && none.makeReason == "Choose a folder first.")
    }

    /// Review Focus 4: off for two reasons at once, each says so in its own place.
    @Test func bothReasonsShowEachInTheirPlace() throws {
        var f = try form()
        f.command = "npm\trun"
        #expect(f.makeReason == "Choose a folder first." && f.commandLineIsProblem)
        #expect(f.problems == ["Pick a folder, or type a path.", "Give the desk a name.",
                               "A command to start can't contain a tab or a new line."])   // no folder, so no name yet
    }

    @Test func aFolderThatGivesNoNameShowsNothingBesideMakeDesk() throws {
        var f = try form()
        f.setTypedPath("~")
        #expect(f.name == "" && !f.canMake && f.makeReason == nil && f.nameLine == NewDeskForm.Words.nameHelp)
    }

    @Test func eachSheetHasOnePrimaryButton() {
        #expect(FormButton.allCases.filter { $0.kind == .primary } == [.makeDesk, .rename, .name])
        for b in FormButton.allCases { #expect(Look.pairs.contains(b.kind.words), "\(b)") }
    }
}
