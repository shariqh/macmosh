import Foundation
import Testing
@testable import MacMoshKit

/// The Settings page's words and rules (main window design, section 7.1 F, issue 157): pure, from the saved list,
/// the app's settings and the last change on each section.
@Suite struct SettingsPageTests {
    private let attic = Workhorse.sample(id: "attic", name: "Attic", projectsFolder: "~/Development")
    private let spare = Workhorse.sample(id: "spare", name: "Spare", mode: .tabs, prediction: .never,
                                         identityFile: "~/.ssh/id_work")

    private func page(_ list: [Workhorse], listProblem: String? = nil, settings: AppSettings? = AppSettings(),
                      settingsProblem: String? = nil, pick: TerminalApp = .iterm2,
                      lines: [String: SettingLine] = [:]) -> SettingsPage {
        SettingsPage(list: list, listProblem: listProblem, settings: settings, settingsProblem: settingsProblem,
                     pickForMe: pick, lines: lines)
    }

    // MARK: The page

    @Test func onePagePerSavedWorkhorseInSavedOrderAfterThisMac() {
        let p = page([spare, attic])
        #expect(p.heading == "Settings")
        #expect(p.thisMac.heading == "This Mac")
        #expect(p.thisMac.label == "Terminal")
        #expect(p.workhorses.map(\.id) == ["spare", "attic"])
        #expect(p.workhorses.map(\.heading) == ["Spare", "Attic"])
        #expect(p.none == nil)
        #expect(p.notices.isEmpty)
    }

    @Test func theTerminalChoicesAreApplyTerminalsWords() {
        let p = page([attic])
        #expect(p.thisMac.choices == [SettingChoice(title: "Pick for me", value: "auto"),
                                      SettingChoice(title: "iTerm2", value: "iterm2"),
                                      SettingChoice(title: "Terminal", value: "terminal")])
        #expect(page([], settings: AppSettings()).thisMac.chosen == "auto")
        #expect(page([], settings: AppSettings(terminal: .iterm2)).thisMac.chosen == "iterm2")
        #expect(page([], settings: AppSettings(terminal: .appleTerminal)).thisMac.chosen == "terminal")
        // Every value is one `macmosh settings terminal` takes.
        #expect(p.thisMac.choices.map(\.value).sorted() == WorkhorseSetting.terminalChoices.sorted())
    }

    /// TabOpener's rule: the setting, else iTerm2 when /Applications/iTerm.app is there, else Terminal.
    @Test func theGreyLineSaysWhatPickForMePicksOnThisMac() {
        #expect(page([], pick: .iterm2).thisMac.pickLine
                == "Pick for me opens tabs in iTerm2 when it is in the Applications folder, and in Terminal when it isn't. On this Mac that is iTerm2.")
        #expect(page([], pick: .appleTerminal).thisMac.pickLine
                == "Pick for me opens tabs in iTerm2 when it is in the Applications folder, and in Terminal when it isn't. On this Mac that is Terminal.")
    }

    @Test func eachWorkhorseShowsItsStoredValues() {
        let p = page([attic, spare])
        let a = p.workhorses[0], s = p.workhorses[1]
        #expect(a.name == "Attic" && a.connection == "mosh" && a.prediction == "adaptive")
        #expect(a.projectsFolder == "~/Development")
        #expect(s.connection == "tabs" && s.prediction == "never" && s.projectsFolder == "")
        #expect(s.keyFile == "~/.ssh/id_work")
        #expect(a.labels == ["Name", "Connection", "Typing prediction", "Projects folder", "Advanced", "ssh key file"])
        #expect(a.connectionChoices == [SettingChoice(title: "Mosh", value: "mosh"), SettingChoice(title: "Tabs", value: "tabs"),
                                        SettingChoice(title: "Plain ssh", value: "ssh")])
        #expect(a.predictionChoices.map(\.title) == ["Adaptive", "Always", "Never", "Experimental"])
        #expect(a.predictionChoices.map(\.value) == Prediction.allCases.map(\.rawValue))
        #expect(a.connectionChoices.map(\.value) == ConnectionMode.allCases.map(\.rawValue))
    }

    /// One line under the Connection group, for the chosen one, from the v1 design's section 5.4 table.
    @Test func oneLineUnderConnectionForEachChoice() {
        func line(_ mode: ConnectionMode) -> String {
            page([Workhorse.sample(id: "attic", name: "Attic", mode: mode)]).workhorses[0].connectionLine
        }
        #expect(line(.mosh) == "One terminal tab per desk. When the Wi-Fi drops or the lid closes, the tab picks up by itself when the network returns. Needs mosh on both Macs.")
        #expect(line(.tabs) == "Every window of a desk as a real iTerm2 tab. When the Wi-Fi drops or the lid closes, the tabs close; your work keeps running, and reconnecting brings the tabs back. Needs iTerm2.")
        #expect(line(.ssh) == "One terminal tab per desk. When the Wi-Fi drops or the lid closes, the tab ends; your work keeps running. Needs nothing extra.")
    }

    /// What prediction is, what the chosen value does (mosh 1.4.0's manual and --help), and that only Mosh uses it.
    @Test func oneLineUnderTypingPrediction() {
        func line(_ p: Prediction) -> String {
            page([Workhorse.sample(id: "attic", name: "Attic", prediction: p)]).workhorses[0].predictionLine
        }
        let first = "Mosh can show what you type before the workhorse answers."
        let last = "Only Mosh uses this."
        #expect(line(.adaptive) == "\(first) Adaptive shows it on slow links and through network glitches. \(last)")
        #expect(line(.always) == "\(first) Always shows it on fast links too, once mosh is confident. \(last)")
        // Read at a glance, it must not say the opposite: with Never you wait for the workhorse every time.
        #expect(line(.never) == "\(first) With Never, you see what you type only after the workhorse answers. \(last)")
        #expect(line(.experimental) == "\(first) Experimental shows it even when it may be wrong. \(last)")
    }

    @Test func anEmptyProjectsFolderSaysWhatNewDeskDoesThen() {
        let p = page([attic, spare])
        #expect(p.workhorses[0].under(.projectsFolder) == nil)
        #expect(p.workhorses[1].under(.projectsFolder)
                == SettingLine(field: .projectsFolder, words: "Not set. New desk has no folders to list until it is.",
                               isProblem: false))
    }

    /// Advanced's field is empty for MacMosh's own key, which is what `macmosh set <id> identity default` stores.
    @Test func advancedShowsAnEmptyFieldForMacMoshsOwnKey() {
        let a = page([attic]).workhorses[0]
        #expect(a.keyFile == "")
        #expect(a.keyFileHelp == "Leave it empty for MacMosh's own key, ~/.ssh/macmosh_ed25519.")
    }

    @Test func theTwoButtonsOpenTodaysTabs() {
        let a = page([attic]).workhorses[0]
        #expect(a.checklist == BoardButton(title: "Run the checklist…", action: .menu(.tab(["prepare", "attic", "--pause"]))))
        #expect(a.remove == BoardButton(title: "Remove MacMosh from this workhorse…", action: .menu(.tab(["remove", "attic"]))))
        // The checklist is the menu's own button.
        #expect(a.checklist.action == BoardAction(ButtonRules.checklist("attic").action))
        // Each goes through the menu's path, as a tab, and every argument passes `TabCommand`'s check.
        for b in [a.checklist, a.remove] {
            guard case .menu(.tab(let args))? = Optional(b.action) else { Issue.record("not a tab"); continue }
            #expect(WindowRun.menuAction(for: b.action) == .tab(args))
            #expect(WindowRun.form(for: b.action) == nil)
        }
    }

    @Test func withNoWorkhorsesThePageSaysSoUnderThisMac() {
        let p = page([])
        #expect(p.workhorses.isEmpty)
        #expect(p.none == "No workhorses yet. Add a Mac… in the sidebar adds one.")
    }

    // MARK: look step 4 (design 6.9 and 7, issue 160 items 1 to 4)

    @Test func theHeadingSaysChangesSaveThemselvesAndRemoveSaysWhatItOpens() {
        let p = page([attic])
        #expect(p.howSaved == "Each change is saved as you make it.")
        #expect(p.workhorses[0].removeHelp == "Opens a terminal tab that lists what goes and asks first.")
        #expect(ButtonKind.of(p.workhorses[0].remove.action) == .destructive
                && ButtonKind.of(p.workhorses[0].checklist.action) == .secondary)
        #expect(SettingsWords.keyFileNotAPath == "Type a full path, starting with / or with ~."
                && SettingsWords.keyFileNotAPath == NewDeskForm.Words.typeAFullPath)
    }

    /// Review Focus 5: the line follows the terminal tabs open in: the setting, else Pick for me's, also when the
    /// settings file can't be read.
    @Test func theTabsLineFollowsWhereThisMacOpensTabs() {
        let line = "This Mac opens tabs in Terminal, so Mosh is used instead."
        let cases: [(AppSettings?, TerminalApp, String?)] = [
            (AppSettings(terminal: .appleTerminal), .iterm2, line), (AppSettings(terminal: .iterm2), .appleTerminal, nil),
            (AppSettings(), .appleTerminal, line), (AppSettings(), .iterm2, nil), (nil, .appleTerminal, line), (nil, .iterm2, nil)]
        for (settings, pick, want) in cases {
            let p = page([attic, spare], settings: settings, settingsProblem: settings == nil ? "unreadable" : nil, pick: pick)
            #expect(p.workhorses[1].connectionNote == want, "\(String(describing: settings)) \(pick)")
            #expect(p.workhorses[0].connectionNote == nil)   // Attic is on Mosh
        }
    }

    @Test func onlyASavedLineHasTheTick() {
        for field in SettingField.allCases {
            for w in [attic, spare] {
                #expect(SettingLine(field: field, words: SettingsWords.saved(field, w), isProblem: false).showsTick, "\(field)")
            }
        }
        #expect(page([spare]).workhorses[0].under(.projectsFolder)?.showsTick == false)
        #expect(!SettingLine(field: .name, words: "Saved. but refused", isProblem: true).showsTick)
    }

    @Test func anUnreadableListGivesTheStoresSentenceAndKeepsTheTerminal() {
        let p = page([], listProblem: "Can't read MacMosh's saved settings: workhorses.json: not JSON",
                     settings: AppSettings(terminal: .iterm2))
        #expect(p.workhorses.isEmpty)
        #expect(p.none == "Can't read MacMosh's saved settings: workhorses.json: not JSON")
        #expect(p.thisMac.chosen == "iterm2")
    }

    @Test func anUnreadableSettingsFileShowsNoChoiceAndItsSentence() {
        let p = page([attic], settings: nil, settingsProblem: "Can't read MacMosh's saved settings: settings.json: not JSON")
        #expect(p.thisMac.chosen == nil)
        #expect(p.thisMac.line == SettingLine(field: .terminal, words: "Can't read MacMosh's saved settings: settings.json: not JSON",
                                              isProblem: true))
    }

    /// Only the last change of each section has its line, under that setting.
    @Test func theLastChangeOfEachSectionHasItsLine() {
        let saved = SettingLine(field: .projectsFolder, words: "Saved. Used by the next New desk.", isProblem: false)
        let refused = SettingLine(field: .name, words: "The name can't be empty.", isProblem: true)
        let terminal = SettingLine(field: .terminal, words: "Saved. Used by the next tab MacMosh opens.", isProblem: false)
        let p = page([attic, spare], lines: ["attic": saved, "spare": refused, SettingsPage.thisMacID: terminal])
        #expect(p.thisMac.line == terminal)
        #expect(p.workhorses[0].under(.projectsFolder) == saved)
        #expect(p.workhorses[0].under(.name) == nil)
        #expect(p.workhorses[1].under(.name) == refused)
        // Spare's projects folder is empty, and its last change was the name: the folder keeps its own line.
        #expect(p.workhorses[1].under(.projectsFolder)?.words == "Not set. New desk has no folders to list until it is.")
    }

    /// A workhorse taken off the list after the page was shown: its section has gone, and its sentence is a line
    /// at the top of the page.
    @Test func aLineForAWorkhorseNoLongerListedIsAtTheTop() {
        let gone = SettingLine(field: .name, words: "Den is no longer on MacMosh's list, so nothing was saved.", isProblem: true)
        let p = page([attic], lines: ["den": gone])
        #expect(p.workhorses.map(\.id) == ["attic"])
        #expect(p.notices == ["Den is no longer on MacMosh's list, so nothing was saved."])
    }

    // MARK: What a change saves

    private func plan(_ field: SettingField, _ typed: String, _ w: Workhorse? = nil,
                      exists: @escaping (String) -> Bool = { _ in true }) -> SettingPlan {
        SettingsRules.plan(field, typed: typed, stored: w ?? attic, keyFileExists: exists, home: "/Users/alex")
    }

    @Test func eachChangeIsMacmoshSetsKeyAndValue() {
        #expect(plan(.name, "Loft") == .set(key: "name", value: "Loft"))
        #expect(plan(.connection, "tabs") == .set(key: "mode", value: "tabs"))
        #expect(plan(.prediction, "experimental") == .set(key: "prediction", value: "experimental"))
        #expect(plan(.projectsFolder, "~/Projects") == .set(key: "projects-folder", value: "~/Projects"))
        #expect(plan(.projectsFolder, "") == .set(key: "projects-folder", value: ""))
        #expect(plan(.keyFile, "~/.ssh/id_work") == .set(key: "identity", value: "~/.ssh/id_work"))
        #expect(plan(.keyFile, "", spare) == .set(key: "identity", value: "default"))
    }

    @Test func aFieldLeftAsStoredSavesNothing() {
        #expect(plan(.name, "Attic") == .unchanged)
        #expect(plan(.name, "  Attic ") == .unchanged)
        #expect(plan(.connection, "mosh") == .unchanged)
        #expect(plan(.prediction, "adaptive") == .unchanged)
        #expect(plan(.projectsFolder, "~/Development") == .unchanged)
        #expect(plan(.projectsFolder, " ~/Development ") == .unchanged)
        #expect(plan(.projectsFolder, "", spare) == .unchanged)
        #expect(plan(.keyFile, "") == .unchanged)
        #expect(plan(.keyFile, "~/.ssh/id_work", spare, exists: { _ in false }) == .unchanged)
        #expect(SettingsRules.planTerminal("auto", stored: AppSettings()) == .unchanged)
        #expect(SettingsRules.planTerminal("iterm2", stored: AppSettings(terminal: .iterm2)) == .unchanged)
    }

    /// Every refusal sentence is WorkhorseSetting's own.
    @Test func aRefusedValueGivesMacmoshSetsSentence() {
        #expect(plan(.name, "") == .refused("The name can't be empty."))
        #expect(plan(.name, "   ") == .refused("The name can't be empty."))
        #expect(plan(.name, "At\ttic") == .refused("The name can't contain a tab or a new line."))
        #expect(plan(.projectsFolder, "~/a\tb") == .refused("The projects folder can't contain a tab or a new line."))
        #expect(plan(.projectsFolder, "~/a\nb") == .refused("The projects folder can't contain a tab or a new line."))
        #expect(plan(.connection, "fast") == .refused("\"fast\" isn't a mode. Allowed: mosh, tabs, ssh."))
        #expect(plan(.prediction, "sometimes")
                == .refused("\"sometimes\" isn't a prediction. Allowed: adaptive, always, never, experimental."))
        #expect(SettingsRules.planTerminal("warp", stored: AppSettings())
                == .refused("\"warp\" isn't a terminal. Allowed: iterm2, terminal, auto."))
    }

    @Test func theTerminalInAllThreeValues() {
        #expect(SettingsRules.planTerminal("iterm2", stored: AppSettings()) == .set(key: "terminal", value: "iterm2"))
        #expect(SettingsRules.planTerminal("terminal", stored: AppSettings(terminal: .iterm2)) == .set(key: "terminal", value: "terminal"))
        #expect(SettingsRules.planTerminal("auto", stored: AppSettings(terminal: .appleTerminal)) == .set(key: "terminal", value: "auto"))
    }

    // MARK: The window's own check on an ssh key file

    @Test func aKeyFileWithNoFileThereIsRefused() {
        let seen = Box<[String]>([])
        let p = plan(.keyFile, "~/.ssh/id_typo", exists: { seen.value.append($0); return false })
        #expect(p == .refused("There is no file at ~/.ssh/id_typo on this Mac, so it was not saved."))
        // The ~ is expanded for the check only.
        #expect(seen.value == ["/Users/alex/.ssh/id_typo"])
    }

    @Test func aKeyFileThatIsThereIsStoredAsTyped() {
        let seen = Box<[String]>([])
        #expect(plan(.keyFile, "~/.ssh/id_work", exists: { seen.value.append($0); return true })
                == .set(key: "identity", value: "~/.ssh/id_work"))
        #expect(plan(.keyFile, " /Users/alex/keys/work ", exists: { seen.value.append($0); return true })
                == .set(key: "identity", value: "/Users/alex/keys/work"))
        #expect(seen.value == ["/Users/alex/.ssh/id_work", "/Users/alex/keys/work"])
    }

    @Test func aRelativeKeyFileIsRefusedWithoutLooking() {
        let seen = Box<[String]>([])
        #expect(plan(.keyFile, ".ssh/id_work", exists: { seen.value.append($0); return true })
                == .refused("Type a full path, starting with / or with ~."))
        #expect(seen.value.isEmpty)
    }

    /// "default" is `macmosh set`'s word for MacMosh's own key; typed in the field it means the same, needs no file.
    @Test func theWordDefaultIsMacMoshsOwnKey() {
        #expect(plan(.keyFile, "default", spare, exists: { _ in false }) == .set(key: "identity", value: "default"))
        #expect(plan(.keyFile, "default", exists: { _ in false }) == .unchanged)
    }

    @Test func aLoneTildeIsTheHomeFolder() {
        #expect(SettingsRules.expandedForCheck("~", home: "/Users/alex") == "/Users/alex")
        #expect(SettingsRules.expandedForCheck("~/k", home: "/Users/alex") == "/Users/alex/k")
        #expect(SettingsRules.expandedForCheck("/k", home: "/Users/alex") == "/k")
    }

    /// `~user/…` is expanded the way ssh's key path is (`KeyManager.identityURL`), so a file that is there is not
    /// refused with an untrue sentence; a user who doesn't exist stays as typed and is refused.
    @Test func aTildeWithAUserNameIsThatUsersHomeFolder() throws {
        let me = NSUserName()
        let home = try #require(NSHomeDirectoryForUser(me))
        #expect(SettingsRules.expandedForCheck("~\(me)/k", home: "/elsewhere") == home + "/k")
        #expect(plan(.keyFile, "~\(me)/k", exists: { $0 == home + "/k" }) == .set(key: "identity", value: "~\(me)/k"))
        // Not expanded, so the check looks at a path that is not a full one, where no file is.
        #expect(SettingsRules.expandedForCheck("~nosuchuser-w6/k", home: "/elsewhere") == "~nosuchuser-w6/k")
        #expect(plan(.keyFile, "~nosuchuser-w6/k", exists: { $0.hasPrefix("/") })
                == .refused("There is no file at ~nosuchuser-w6/k on this Mac, so it was not saved."))
    }

    /// A key file refused when the page was left is still explained when it opens again, so Advanced opens for it.
    @Test func aRefusedKeyFileOpensAdvanced() {
        let refused = SettingLine(field: .keyFile, words: SettingsWords.noKeyFile("~/.ssh/id_typo"), isProblem: true)
        let saved = SettingLine(field: .keyFile, words: SettingsWords.saved(.keyFile, attic), isProblem: false)
        let name = SettingLine(field: .name, words: "The name can't be empty.", isProblem: true)
        #expect(page([attic], lines: ["attic": refused]).workhorses[0].opensAdvanced)
        #expect(!page([attic], lines: ["attic": saved]).workhorses[0].opensAdvanced)
        #expect(!page([attic], lines: ["attic": name]).workhorses[0].opensAdvanced)
        #expect(!page([attic]).workhorses[0].opensAdvanced)
    }

    // MARK: The grey line after a save

    @Test func eachSavedLineSaysWhatUsesItNext() {
        #expect(SettingsWords.saved(.terminal, nil) == "Saved. Used by the next tab MacMosh opens.")
        #expect(SettingsWords.saved(.name, attic) == "Saved. The menu shows it at its next check.")
        #expect(SettingsWords.saved(.connection, attic) == "Saved. Used by the next tab you open on a desk.")
        #expect(SettingsWords.saved(.prediction, attic) == "Saved. Used by the next Mosh tab you open.")
        #expect(SettingsWords.saved(.projectsFolder, attic) == "Saved. Used by the next New desk.")
        #expect(SettingsWords.saved(.projectsFolder, spare) == "Saved. New desk has no folders to list until it is set.")
        #expect(SettingsWords.saved(.keyFile, spare) == "Saved. Used for Spare from the next check on.")
        #expect(SettingsWords.saved(.keyFile, attic) == "Saved. MacMosh's own key is used from the next check on.")
    }

    @Test func theSidebarAndTheBoardTakeASavedNameAtOnce() throws {
        // The check ran before the save; the saved list has the new name.
        let checked = CheckResult(workhorse: attic, state: .ready(signIns: true), status: nil, probes: ProbeSet(),
                                  answeredAt: nil, homeReachable: nil, checkedAt: formatNow)
        var renamed = attic
        renamed.name = "Loft"
        let board = BoardModel.build(latest: ["attic": checked], lastReady: [:], checking: [], order: [renamed],
                                     waitingForDeskServer: [], now: formatNow, timeZone: formatZone)
        #expect(board.workhorses.first?.name == "Loft")
        #expect(board.workhorses.first?.headline == "Loft · Ready")
        #expect(SidebarItem.list(board).first?.title == "Loft")
        // Only the name is the saved list's: the rest is still the check's.
        var other = renamed
        other.mode = .ssh
        other.homeAddress = "192.168.1.99"
        let same = BoardModel.build(latest: ["attic": checked], lastReady: [:], checking: [], order: [other],
                                    waitingForDeskServer: [], now: formatNow, timeZone: formatZone)
        #expect(same == board)
    }

    @Test func linesForSeveralWorkhorsesNoLongerListedAreInIdOrder() {
        let p = page([attic], lines: [
            "den": SettingLine(field: .name, words: SettingsWords.gone("Den"), isProblem: true),
            "cellar": SettingLine(field: .connection, words: SettingsWords.gone("Cellar"), isProblem: true),
        ])
        #expect(p.notices == ["Cellar is no longer on MacMosh's list, so nothing was saved.",
                              "Den is no longer on MacMosh's list, so nothing was saved."])
    }
}
