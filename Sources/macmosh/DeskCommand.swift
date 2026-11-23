import ArgumentParser
import Foundation
import MacMoshKit

/// Finds the workhorse, checks it and saves what the check learned. A check that can't start
/// (an unknown name, unreadable settings) is a failed result, with the words for it.
func checkedForDesk(_ name: String) async -> Result<CheckResult, DeskResult> {
    let paths = Paths.standard()
    let store = WorkhorseStore(paths: paths)
    let found: Workhorse
    do { found = try store.find(name) } catch { return .failure(.failure(StatusFormat.storeMessage(error))) }
    let result = await makeChecker(paths: paths).check(found)
    save([result], in: store)
    return .success(result)
}

func deskFlow() -> DeskFlow {
    DeskFlow(commands: HostCommands(runner: ProcessRunner(), paths: Paths.standard()))
}

extension DeskResult {
    /// Prints the reason on standard error, and ends the command with exit code 1 (or the result's).
    func finishPlainly() throws {
        if let reason { printError(reason) }
        if code != 0 { throw ExitCode(code) }
    }
}

struct DeskCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "desk",
        abstract: "Make, rename, remove or add a window to a desk on a workhorse.",
        subcommands: [
            New.self,
            Rename.self,
            Remove.self,
            Window.self,
        ]
    )

    struct New: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "new",
            abstract: "Make a desk. With no desk name or folder it asks for them, and for a command to start.",
            discussion: """
                A new desk opens again by itself after the workhorse restarts, unless you say --no-reopen. \
                When you close its last window (typing exit, for example), the desk is removed and its name \
                is free again, unless you say --permanent: a permanent desk stays in the menu, marked closed, \
                and opens again with one click.
                """
        )

        @Argument(help: "The workhorse's id or name.")
        var workhorse: String

        @Argument(help: "The desk's name: letters, digits, - and _ only. Leave it out to be asked.")
        var desk: String?

        @Option(help: "The folder on the workhorse, a full path or one starting with ~. Leave it out to pick from the projects folder.")
        var folder: String?

        @Flag(help: "Open the desk again after the workhorse restarts. This is what happens anyway, unless you say --no-reopen.")
        var reopen = false

        @Flag(name: .customLong("no-reopen"), help: "Don't open the desk again after the workhorse restarts.")
        var noReopen = false

        @Flag(help: "Keep the desk when its last window is closed, so it can be opened again from the menu. Without this, closing its last window removes the desk.")
        var permanent = false

        @Flag(help: "The startup command is kept running (not active yet).")
        var keep = false

        @Option(help: "A command to type into the desk when it starts. Given here, it isn't asked for.")
        var command: String?

        func run() async throws {
            let request: NewDeskRequest
            do {
                request = try NewDeskRequest.fromFlags(name: desk, folder: folder, reopen: reopen, noReopen: noReopen,
                                                       keep: keep, permanent: permanent, command: command)
            } catch let mistake as DeskUsageError {
                throw ValidationError(mistake.description)
            }
            let ui = TerminalInteraction()
            var outcome: DeskResult
            switch await checkedForDesk(workhorse) {
            case .failure(let failed): outcome = failed
            case .success(let check): outcome = await deskFlow().newDesk(check, request: request, ui: ui)
            }
            guard request.isInteractive else { return try outcome.finishPlainly() }
            // It runs in a terminal tab: on a failure say why and wait for a key, so the tab doesn't vanish.
            outcome.code = ui.finish(outcome.code, reason: outcome.reason)
            if outcome.code != 0 { throw ExitCode(outcome.code) }
            // The form ends by opening the desk it just made, in this same tab.
            if let made = outcome.desk {
                let code = await connectToDesk(workhorse, desk: made, mode: nil, ui: ui)
                if code != 0 { throw ExitCode(code) }
            }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "remove",
            abstract: "Remove a desk. What is running in it keeps running unless you say --kill."
        )

        @Argument(help: "The workhorse's id or name.")
        var workhorse: String

        @Argument(help: "The desk's name.")
        var desk: String

        @Flag(help: "Also close the desk's windows and whatever runs in them.")
        var kill = false

        @Flag(help: "Say what will close and ask first. On yes the desk's windows close too, as with --kill. This is what the menu's Remove runs.")
        var ask = false

        func run() async throws {
            let ui = TerminalInteraction()
            var outcome: DeskResult
            switch await checkedForDesk(workhorse) {
            case .failure(let failed): outcome = failed
            case .success(let check):
                outcome = ask ? await deskFlow().removeDeskAsking(check, name: desk, ui: ui)
                              : await deskFlow().removeDesk(check, name: desk, kill: kill, ui: ui)
            }
            guard ask else { return try outcome.finishPlainly() }
            // It runs in a tab from the menu: it stays open until a key is pressed.
            outcome.code = ui.finishTab(outcome.code, reason: outcome.reason)
            if outcome.code != 0 { throw ExitCode(outcome.code) }
        }
    }

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rename",
            abstract: "Rename a desk. With no new name it asks for one.",
            discussion: """
                The desk keeps its windows and whatever runs in them, its folder, its startup command, and \
                whether it comes back after a restart or is permanent. Tabs that are open on it keep working; \
                their titles may still say the old name.
                """
        )

        @Argument(help: "The workhorse's id or name.")
        var workhorse: String

        @Argument(help: "The desk's name now.")
        var desk: String

        @Argument(help: "The new name: letters, digits, - and _ only. Leave it out to be asked.")
        var newName: String?

        func run() async throws {
            let ui = TerminalInteraction()
            var outcome: DeskResult
            switch await checkedForDesk(workhorse) {
            case .failure(let failed): outcome = failed
            case .success(let check): outcome = await deskFlow().renameDesk(check, from: desk, to: newName, ui: ui)
            }
            guard newName == nil else { return try outcome.finishPlainly() }
            // The form that asks runs in a tab from the menu: it stays open until a key is pressed.
            outcome.code = ui.finishTab(outcome.code, reason: outcome.reason)
            if outcome.code != 0 { throw ExitCode(outcome.code) }
        }
    }

    struct Window: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "window",
            abstract: "Add a window to an open desk."
        )

        @Argument(help: "The workhorse's id or name.")
        var workhorse: String

        @Argument(help: "The desk's name.")
        var desk: String

        func run() async throws {
            switch await checkedForDesk(workhorse) {
            case .failure(let failed): try failed.finishPlainly()
            case .success(let check):
                try await deskFlow().newWindow(check, desk: desk, ui: TerminalInteraction()).finishPlainly()
            }
        }
    }
}
