import Foundation
import Testing
@testable import MacMoshKit

private let sudoSentence = "ssh asks for the Mac's password, for sudo. You are typing into ssh; MacMosh can't see it."
private let awakeCommand = "sudo pmset -c sleep 0 womp 1"
private let autorestartCommand = "sudo pmset -a autorestart 1"
private let lidOnCommand = "sudo pmset -a disablesleep 1"
private let lidOffCommand = "sudo pmset -a disablesleep 0"

@Suite struct PowerTests {
    // MARK: The plan

    @Test func awakeIsTheDesignsCommand() throws {
        let plan = try PowerPlanner.plan(.awake, status: .sampleReady)
        #expect(plan.command == "sudo pmset -c sleep 0 womp 1")
        #expect(plan.explanation == "Keeps the Mac awake while it is on power, and lets it wake for network access.")
    }

    @Test func autorestartIsForDesktops() {
        #expect(throws: PowerError.self) { try PowerPlanner.plan(.autorestart, status: .sampleLaptop) }
        #expect((try? PowerPlanner.plan(.autorestart, status: .sampleDesktop).command) == "sudo pmset -a autorestart 1")
        #expect((try? PowerPlanner.plan(.autorestart, status: .sampleDesktop).explanation)
            == "Starts the Mac again by itself after a power cut.")
    }

    @Test func aLaptopIsToldWhyNotWithTheDesignsWords() {
        do {
            _ = try PowerPlanner.plan(.autorestart, status: .sampleLaptop)
            Issue.record("a laptop was given an autorestart plan")
        } catch let error as PowerError {
            #expect(error == .notApplicable("This setting is for desktop Macs. A laptop carries on from its battery."))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func powerCommandsAreFixedText() throws {
        // A report carrying text that would be dangerous in a `sudo` command line, if any of it got in.
        var odd = HostStatus.sampleDesktop
        odd.consoleUser = "alex; sudo rm -rf /"
        odd.home = HostStatus.Home(address: "192.168.1.20", prefix: 24, localName: "wor'k$(reboot)horse.local")
        odd.osVersion = "27.3; reboot"
        odd.tools = [HostStatus.Tool(name: "tmux", path: "/opt/$(reboot)/tmux", version: "`reboot`")]
        let desk = try #require(DeskName("odd_desk-1"))
        odd.desks = [HostStatus.Desk(name: desk, windows: [], windowCount: 1, attached: 0)]
        odd.definitions = [HostStatus.Definition(name: desk, reopen: true, keep: false,
                                                 folder: "/Users/alex/it's $HOME", command: "; reboot")]
        for status in [odd, HostStatus.sampleDesktop, HostStatus.sampleReady] {
            #expect(try PowerPlanner.plan(.awake, status: status).command == awakeCommand)
        }
        #expect(try PowerPlanner.plan(.autorestart, status: odd).command == autorestartCommand)
        #expect(try PowerPlanner.plan(.autorestart, status: .sampleDesktop).command == autorestartCommand)
    }

    @Test func theValuesLineSaysWhatIsNotListed() {
        let line = PowerPlanner.valuesLine(.sampleLaptop)
        #expect(line == "Sleep on power: 0 · Wake for network access: 1 · Restart after a power cut: not listed · Lid-closed mode: off")
    }

    @Test func theValuesLineGivesTheLidForLaptopsOnly() {
        var laptop = HostStatus.sampleLaptop
        laptop.power.disableSleep = 1
        #expect(PowerPlanner.valuesLine(laptop).hasSuffix(" · Lid-closed mode: on"))
        laptop.power.disableSleep = 0
        #expect(PowerPlanner.valuesLine(laptop).hasSuffix(" · Lid-closed mode: off"))
        #expect(PowerPlanner.valuesLine(.sampleDesktop)
            == "Sleep on power: 10 · Wake for network access: 0 · Restart after a power cut: 0")
    }

    // MARK: The lid-closed switch

    @Test func lidOnAndOffAreTheFixedCommands() throws {
        #expect(try PowerPlanner.plan(.lid, turnOn: true, status: .sampleLaptop).command == lidOnCommand)
        #expect(try PowerPlanner.plan(.lid, turnOn: false, status: .sampleLaptop).command == lidOffCommand)
    }

    @Test func lidIsForLaptopsOnly() {
        for turnOn in [true, false] {
            do {
                _ = try PowerPlanner.plan(.lid, turnOn: turnOn, status: .sampleDesktop)
                Issue.record("a Mac with no battery was given a lid plan")
            } catch let error as PowerError {
                #expect(error == .notApplicable("This setting is for laptops. This Mac has no battery, so it has no lid to close."))
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
    }

    @Test func turningTheLidModeOnWarnsAboutPowerHeatAndRestarts() throws {
        let words = try PowerPlanner.plan(.lid, turnOn: true, status: .sampleLaptop).explanation
        #expect(words.contains("plugged in"))
        #expect(words.contains("battery"))
        #expect(words.contains("in a bag"))
        #expect(words.contains("empty"))
        #expect(words.contains("hotter"))
        #expect(words.contains("after a restart"))
        #expect(words.contains("turn it off"))
    }

    @Test func turningTheLidModeOffSaysTheMacSleepsAgain() throws {
        let words = try PowerPlanner.plan(.lid, turnOn: false, status: .sampleLaptop).explanation
        #expect(words == "The Mac sleeps again when its lid closes.")
    }

    @Test func lidCommandsAreFixedText() throws {
        var odd = HostStatus.sampleLaptop
        odd.consoleUser = "alex; sudo rm -rf /"
        odd.home = HostStatus.Home(address: "192.168.1.20", prefix: 24, localName: "wor'k$(reboot)horse.local")
        odd.osVersion = "27.3; reboot"
        odd.power.disableSleep = 1
        #expect(try PowerPlanner.plan(.lid, turnOn: true, status: odd).command == lidOnCommand)
        #expect(try PowerPlanner.plan(.lid, turnOn: false, status: odd).command == lidOffCommand)
    }

    // MARK: Reading `power <workhorse> lid on|off`

    @Test func lidNeedsOnOrOff() {
        for word in [nil, "", "maybe", "ON", "1"] as [String?] {
            #expect(throws: PowerUsageError.self) { try PowerRequest.parse(setting: .lid, word: word) }
        }
        #expect(PowerUsageError.lidNeedsOnOrOff.description == "Say whether to turn lid-closed mode on or off: macmosh power <workhorse> lid on, or macmosh power <workhorse> lid off.")
    }

    @Test func onAndOffBelongToLidOnly() {
        for setting in [PowerSetting.awake, .autorestart] {
            #expect(throws: PowerUsageError.self) { try PowerRequest.parse(setting: setting, word: "on") }
            #expect(throws: PowerUsageError.self) { try PowerRequest.parse(setting: setting, word: "off") }
        }
        #expect(PowerUsageError.onOffOnlyForLid(.awake).description
            == "awake takes no on or off. Only lid does: macmosh power <workhorse> lid on.")
    }

    @Test func requestsParse() throws {
        #expect(try PowerRequest.parse(setting: .lid, word: "on") == PowerRequest(setting: .lid, turnOn: true))
        #expect(try PowerRequest.parse(setting: .lid, word: "off") == PowerRequest(setting: .lid, turnOn: false))
        #expect(try PowerRequest.parse(setting: .awake, word: nil) == PowerRequest(setting: .awake, turnOn: true))
        #expect(try PowerRequest.parse(setting: .autorestart, word: nil) == PowerRequest(setting: .autorestart, turnOn: true))
    }

    // MARK: Asking

    @Test func powerShowsTheCommandBeforeAsking() async throws {
        let f = try PowerFixture(answers: ["yes"])
        let code = await f.flow.power(f.workhorse, setting: .awake, ui: f.ui)
        #expect(code == 0)
        let who = f.ui.indexOfSaid("This runs on MacBook Pro:")
        let command = f.ui.indexOfSaid(awakeCommand)
        let explanation = f.ui.indexOfSaid("Keeps the Mac awake while it is on power, and lets it wake for network access.")
        let sudo = f.ui.indexOfSaid(sudoSentence)
        let question = f.ui.indexOfFirstQuestion
        let run = f.ui.indexOfFirstRun
        #expect(who != nil && command != nil && explanation != nil && sudo != nil && question != nil && run != nil)
        guard let who, let command, let explanation, let sudo, let question, let run else { return }
        let order: [Int] = [who, command, explanation, sudo, question, run]
        #expect(order == order.sorted())
        #expect(Set(order).count == order.count)
        #expect(f.ui.asked == ["Type yes to run it: "])
    }

    @Test func powerHandsTheTerminalToSSHWithTheCommandOnly() async throws {
        let f = try PowerFixture(answers: ["yes"])
        _ = await f.flow.power(f.workhorse, setting: .awake, ui: f.ui)
        #expect(f.interactive.calls.count == 1)
        let argv = try #require(f.interactive.calls.first)
        #expect(argv.first == "ssh")
        #expect(argv.contains("-t"))
        #expect(!argv.contains("BatchMode=yes"))
        #expect(sshTarget(argv) == "alex@workhorse")
        #expect(sshRemote(argv) == [awakeCommand])
        #expect(argv.contains("StrictHostKeyChecking=yes"))
    }

    @Test func nothingRunsWithoutYes() async throws {
        for answer in ["", "y", "no", "Yes", "yes please", "YES"] {
            let f = try PowerFixture(answers: [answer])
            let code = await f.flow.power(f.workhorse, setting: .awake, ui: f.ui)
            #expect(code == 1)
            #expect(f.interactive.calls.isEmpty)
            #expect(try f.savedPowerChanges().isEmpty)
            #expect(f.ui.waits == 1)   // ui.finish kept the tab open with the reason
        }
    }

    @Test func yesWithSpacesAroundItIsStillYes() async throws {
        let f = try PowerFixture(answers: ["  yes \n"])
        #expect(await f.flow.power(f.workhorse, setting: .awake, ui: f.ui) == 0)
        #expect(f.interactive.calls.count == 1)
    }

    // MARK: Recording

    @Test func aChangeThatRanIsRecorded() async throws {
        let f = try PowerFixture(answers: ["yes"])
        #expect(await f.flow.power(f.workhorse, setting: .awake, ui: f.ui) == 0)
        #expect(try f.savedPowerChanges() == [awakeCommand])
    }

    @Test func theSameCommandIsRecordedOnce() async throws {
        let f = try PowerFixture(answers: ["yes", "yes"])
        _ = await f.flow.power(f.workhorse, setting: .awake, ui: f.ui)
        _ = await f.flow.power(f.workhorse, setting: .awake, ui: f.ui)
        #expect(f.interactive.calls.count == 2)
        #expect(try f.savedPowerChanges() == [awakeCommand])
    }

    @Test func aSecondSettingIsRecordedBesideTheFirst() async throws {
        let f = try PowerFixture(script: [PowerFixture.desktop()], answers: ["yes", "yes"])
        _ = await f.flow.power(f.workhorse, setting: .awake, ui: f.ui)
        _ = await f.flow.power(f.workhorse, setting: .autorestart, ui: f.ui)
        #expect(try f.savedPowerChanges() == [awakeCommand, autorestartCommand])
    }

    @Test func aFailedChangeIsNotRecorded() async throws {
        let f = try PowerFixture(answers: ["yes"], sshExitCodes: [1])
        let code = await f.flow.power(f.workhorse, setting: .awake, ui: f.ui)
        #expect(code == 1)
        #expect(try f.savedPowerChanges().isEmpty)
        #expect(f.checker.checks == 1)   // no fresh check of values that didn't change
        #expect(f.ui.waits == 1)
    }

    @Test func aChangeThatRanButCouldNotBeSavedIsSaidSo() async throws {
        let f = try PowerFixture(answers: ["yes"])
        try f.store.remove(id: f.workhorse.id)   // the record is gone, so the note can't be saved
        let code = await f.flow.power(f.workhorse, setting: .awake, ui: f.ui)
        #expect(code == 0)   // the change did run
        #expect(f.interactive.calls.count == 1)
        #expect(f.ui.said.contains { $0.hasPrefix("The change ran, but MacMosh couldn't save a note of it") })
    }

    @Test func afterAChangeTheNewValuesAreShown() async throws {
        var after = HostStatus.sampleLaptop
        after.power.sleepOnPower = 0
        after.power.wakeForNetwork = 1
        let f = try PowerFixture(script: [.usual(.ready(signIns: true)),
                                          ScriptedCheck(.ready(signIns: true), status: after, answeredAt: "workhorse")],
                                 answers: ["yes"])
        #expect(await f.flow.power(f.workhorse, setting: .awake, ui: f.ui) == 0)
        #expect(f.checker.checks == 2)
        #expect(f.ui.said.last == "Sleep on power: 0 · Wake for network access: 1 · Restart after a power cut: not listed · Lid-closed mode: off")
    }

    // MARK: The lid-closed switch through the flow

    @Test func lidOnShowsItsWordsAndRunsTheCommand() async throws {
        let f = try PowerFixture(script: [PowerFixture.laptop(), PowerFixture.laptop()], answers: ["yes"])
        let code = await f.flow.power(f.workhorse, setting: .lid, turnOn: true, ui: f.ui)
        #expect(code == 0)
        #expect(f.ui.indexOfSaid(lidOnCommand) != nil)
        #expect(f.ui.said.contains { $0.contains("plugged in") })
        #expect(sshRemote(try #require(f.interactive.calls.first)) == [lidOnCommand])
        #expect(try f.savedPowerChanges() == [lidOnCommand])
    }

    @Test func lidOffRunsTheOffCommandAndTakesTheOnNoteBack() async throws {
        let f = try PowerFixture(script: Array(repeating: PowerFixture.laptop(), count: 4), answers: ["yes", "yes"])
        _ = await f.flow.power(f.workhorse, setting: .lid, turnOn: true, ui: f.ui)
        #expect(try f.savedPowerChanges() == [lidOnCommand])
        let code = await f.flow.power(f.workhorse, setting: .lid, turnOn: false, ui: f.ui)
        #expect(code == 0)
        #expect(sshRemote(try #require(f.interactive.calls.last)) == [lidOffCommand])
        #expect(f.ui.said.contains("The Mac sleeps again when its lid closes."))
        // Nothing is left to put back, so "Remove" has nothing to list.
        #expect(try f.savedPowerChanges().isEmpty)
    }

    @Test func lidOnADesktopRunsNothing() async throws {
        let f = try PowerFixture(script: [PowerFixture.desktop()], answers: ["yes"])
        let code = await f.flow.power(f.workhorse, setting: .lid, turnOn: true, ui: f.ui)
        #expect(code == 1)
        #expect(f.interactive.calls.isEmpty)
        #expect(f.ui.asked.isEmpty)
    }

    // MARK: Refusals

    @Test func autorestartOnALaptopRunsNothing() async throws {
        let f = try PowerFixture(script: [ScriptedCheck(.ready(signIns: true), status: .sampleLaptop, answeredAt: "workhorse")],
                                 answers: ["yes"])
        let code = await f.flow.power(f.workhorse, setting: .autorestart, ui: f.ui)
        #expect(code == 1)
        #expect(f.interactive.calls.isEmpty)
        #expect(f.ui.asked.isEmpty)
        #expect(f.ui.said.contains("This setting is for desktop Macs. A laptop carries on from its battery."))
    }

    @Test func powerWorksOnAWorkhorseWaitingForLogin() async throws {
        let f = try PowerFixture(script: [.usual(.waitingForLogin)], answers: ["yes"])
        #expect(await f.flow.power(f.workhorse, setting: .awake, ui: f.ui) == 0)
        #expect(sshTarget(f.interactive.calls[0]) == "alex@192.168.1.20")
    }

    @Test func powerStopsInAnyOtherState() async throws {
        let states: [WorkhorseState] = [.locked, .cantVerify, .cantReach(.nothingAnswers),
                                        .notSetUp(.notPaired), .notSetUp(.hostScriptMissing)]
        for state in states {
            let f = try PowerFixture(script: [.usual(state)], answers: ["yes"])
            let code = await f.flow.power(f.workhorse, setting: .awake, ui: f.ui)
            #expect(code == 1)
            #expect(f.interactive.calls.isEmpty)
            #expect(f.ui.asked.isEmpty)
            #expect(f.ui.said.first?.hasPrefix("MacBook Pro · ") == true)
            #expect(f.ui.waits == 1)
        }
    }

    @Test func powerStopsWhenTheKeyIsLockedAndMakesNoSSHCall() async throws {
        let f = try PowerFixture(answers: ["yes"])
        chmod(f.paths.defaultIdentity.path, 0o644)
        let code = await f.flow.power(f.workhorse, setting: .awake, ui: f.ui)
        #expect(code == 1)
        #expect(f.interactive.calls.isEmpty)
        #expect(f.checker.checks == 0)   // the checker would use the key too
        #expect(f.ui.said.contains("MacBook Pro · Your ssh key is locked"))
    }

    @Test func powerNeverAsksForAPassword() async throws {
        let f = try PowerFixture(answers: ["yes"])
        _ = await f.flow.power(f.workhorse, setting: .awake, ui: f.ui)
        // The only question is the yes/no one; the password is ssh's to ask.
        #expect(f.ui.asked == ["Type yes to run it: "])
    }
}
