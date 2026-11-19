import ArgumentParser
import Foundation
import MacMoshKit

struct RemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Take MacMosh off a workhorse and off this Mac's list. It lists what goes and asks first."
    )

    @Argument(help: "The workhorse's id or name.")
    var workhorse: String

    @Flag(name: .customLong("forget-only"), help: "Only remove it from this Mac's list. Nothing on the workhorse changes and no ssh call is made.")
    var forgetOnly = false

    @Flag(help: "Don't ask. For a program that started this command.")
    var yes = false

    func run() async throws {
        let ui = TerminalInteraction()
        let paths = Paths.standard()
        let found = try findForRecovery(workhorse, paths: paths, ui: ui)
        let runner = ProcessRunner()
        let removal = Removal(store: WorkhorseStore(paths: paths), paths: paths, runner: runner,
                              keys: KeyManager(paths: paths, runner: runner), checker: makeChecker(paths: paths))
        do {
            try await removal.remove(found, forgetOnly: forgetOnly, skipQuestion: yes, ui: ui)
        } catch is RemovalError {
            throw ExitCode(1)   // the reason has been said already
        }
    }
}
