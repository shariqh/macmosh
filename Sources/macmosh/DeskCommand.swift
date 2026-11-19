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
        abstract: "Make, remove or add a window to a desk on a workhorse.",
        subcommands: [
            New.self,
            Remove.self,
            Window.self,
        ]
    )

    struct New: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "new",
            abstract: "Make a desk. With no desk name or folder it asks for them."
        )

        @Argument(help: "The workhorse's id or name.")
        var workhorse: String

        @Argument(help: "The desk's name: letters, digits, - and _ only. Leave it out to be asked.")
        var desk: String?

        @Option(help: "The folder on the workhorse, a full path or one starting with ~. Leave it out to pick from the projects folder.")
        var folder: String?

        @Flag(help: "Open the desk again after the workhorse restarts.")
        var reopen = false

        @Flag(help: "The startup command is kept running (not active yet).")
        var keep = false

        @Option(help: "A command to type into the desk when it starts.")
        var command: String?

        func run() async throws {
            let request = NewDeskRequest(name: desk, folder: folder, reopen: reopen, keep: keep, command: command)
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

        func run() async throws {
            switch await checkedForDesk(workhorse) {
            case .failure(let failed): try failed.finishPlainly()
            case .success(let check):
                try await deskFlow().removeDesk(check, name: desk, kill: kill, ui: TerminalInteraction()).finishPlainly()
            }
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
