import Foundation
import Testing
@testable import MacMoshKit

/// The window's sentences for the desk actions (main window design, section 7.3): the terminal's, with no
/// `macmosh` command in them, and the Remove sentence both faces share.
@Suite struct DeskFormatWindowTests {
    private let attic = Workhorse.sample(id: "attic", name: "Attic")

    @Test func noWindowSentenceNamesTheMacmoshCommand() {
        let errors: [HostCommandError] = [
            .badInput, .alreadyExists, .noSuchDesk, .noProjectsFolder, .nobodyLoggedIn, .serverDidNotStart,
            .failed(exitCode: 255, message: "Your ssh key is locked: MacMosh can't use its key file. Run: macmosh status attic"),
            .failed(exitCode: 255, message: "The workhorse turned MacMosh's key down. Check it with: macmosh status"),
            .failed(exitCode: 255, message: "MacMosh has no saved host key for this workhorse. Pair it again with: macmosh pair"),
        ]
        for error in errors {
            let window = DeskFormat.message(error, workhorse: attic, for: .window)
            #expect(!window.contains("macmosh "), "\(error): \(window)")
            #expect(!window.isEmpty)
        }
    }

    @Test func theWindowSaysPickAnotherNameWhereTheTerminalGivesACommand() {
        #expect(DeskFormat.message(.alreadyExists, workhorse: attic, for: .window)
                == "Attic already has a desk with that name. Pick another name.")
        #expect(DeskFormat.message(.alreadyExists, workhorse: attic, for: .terminal)
                == "Attic already has a desk with that name. Pick another name, or remove it with: macmosh desk remove attic <name>")
        // The terminal's words are as they were.
        #expect(DeskFormat.message(.alreadyExists, workhorse: attic) == DeskFormat.message(.alreadyExists, workhorse: attic, for: .terminal))
    }

    @Test func theOtherWindowSentences() {
        #expect(DeskFormat.message(.noSuchDesk, workhorse: attic, for: .window) == "Attic has no desk with that name now.")
        #expect(DeskFormat.message(.noProjectsFolder, workhorse: attic, for: .window) == "No projects folder is set for Attic.")
        #expect(DeskFormat.message(.serverDidNotStart, workhorse: attic, for: .window)
                == "The desk server on Attic didn't start. Run the checklist on its page to fix it.")
        #expect(DeskFormat.message(.nobodyLoggedIn, workhorse: attic, for: .window)
                == DeskFormat.message(.nobodyLoggedIn, workhorse: attic, for: .terminal))
        #expect(DeskFormat.message(.badInput, workhorse: attic, for: .window)
                == DeskFormat.message(.badInput, workhorse: attic, for: .terminal))
    }

    /// A message from ssh keeps its first sentence and loses the one that names a command.
    @Test func aCommandAtTheEndOfAnSshMessageIsLeftOut() {
        #expect(DeskFormat.message(.failed(exitCode: 255, message: "The workhorse turned MacMosh's key down. Check it with: macmosh status"),
                                   workhorse: attic, for: .window) == "The workhorse turned MacMosh's key down.")
        #expect(DeskFormat.message(.failed(exitCode: 255, message: "Your ssh key is locked: MacMosh can't use its key file. Run: macmosh status attic"),
                                   workhorse: attic, for: .window) == "Your ssh key is locked: MacMosh can't use its key file.")
        #expect(DeskFormat.message(.failed(exitCode: 1, message: "It broke."), workhorse: attic, for: .window) == "It broke.")
    }

    // MARK: the Remove sentence

    @Test func theRemoveSentenceNamesTheWindowsThatClose() {
        let website = HostStatus.Desk(name: DeskName("website")!,
                                      windows: [.init(index: 0, name: "claude"), .init(index: 1, name: "zsh"), .init(index: 2, name: "vim")],
                                      windowCount: 3, attached: 1)
        #expect(DeskFormat.removeSentence(DeskName("website")!, open: website)
                == "This removes the desk website and closes its 3 windows (claude, zsh, vim), with whatever is running in them.")
        let solo = HostStatus.Desk(name: DeskName("solo")!, windows: [.init(index: 0, name: "")], windowCount: 1, attached: 0)
        #expect(DeskFormat.removeSentence(DeskName("solo")!, open: solo)
                == "This removes the desk solo and closes its 1 window, with whatever is running in them.")
        #expect(DeskFormat.removeSentence(DeskName("notes")!, open: nil) == "This removes the desk notes. It has no open windows.")
    }

    // MARK: result lines

    @Test func theResultLinesSayWhatHappenedAndWhere() {
        let garden = DeskName("garden-planner")!
        #expect(DeskFormat.windowDone(.newDesk, desk: garden, to: nil, on: attic) == "Created the desk garden-planner on Attic.")
        #expect(DeskFormat.windowDone(.rename, desk: DeskName("api")!, to: DeskName("api-v2")!, on: attic)
                == "Renamed api to api-v2 on Attic.")
        #expect(DeskFormat.windowDone(.remove, desk: DeskName("website")!, to: nil, on: attic) == "Removed the desk website from Attic.")
        #expect(DeskFormat.windowFailed(.newDesk, desk: "garden", reason: "It broke.") == "The desk garden wasn't made. It broke.")
        #expect(DeskFormat.windowFailed(.rename, desk: "api", reason: "It broke.") == "api wasn't renamed. It broke.")
        #expect(DeskFormat.windowFailed(.remove, desk: "website", reason: "It broke.") == "website wasn't removed. It broke.")
        // No answer in time: it may have happened, so the line claims neither.
        #expect(DeskFormat.windowUnsure(.newDesk, desk: "garden", on: attic)
                == "MacMosh didn't hear back from Attic about garden within 15 seconds. The next check shows whether it was made.")
        #expect(DeskFormat.windowUnsure(.rename, desk: "api", on: attic)
                == "MacMosh didn't hear back from Attic about api within 15 seconds. The next check shows whether it was renamed.")
        #expect(DeskFormat.windowUnsure(.remove, desk: "website", on: attic)
                == "MacMosh didn't hear back from Attic about website within 15 seconds. The next check shows whether it was removed.")
    }
}
