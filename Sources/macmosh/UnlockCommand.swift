import ArgumentParser
import Foundation
import MacMoshKit

/// The `Recovery` the restart-recovery commands use: the real checker, ssh and terminal.
func makeRecovery(paths: Paths) -> Recovery {
    Recovery(checker: makeChecker(paths: paths), paths: paths, interactive: ProcessRunner(),
             sleep: { try? await Task.sleep(for: $0) })
}

/// Finds a saved workhorse. On a failure it says why, waits for a key (these commands run in a
/// terminal tab) and ends the command with exit code 1.
func findForRecovery(_ name: String, paths: Paths, ui: Interaction) throws -> Workhorse {
    do {
        return try WorkhorseStore(paths: paths).find(name)
    } catch {
        throw ExitCode(ui.finish(1, reason: StatusFormat.storeMessage(error)))
    }
}

struct UnlockCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unlock",
        abstract: "Unlock a workhorse's disk after a restart. You type the Mac's password into ssh."
    )

    @Argument(help: "The workhorse's id or name.")
    var workhorse: String

    func run() async throws {
        let ui = TerminalInteraction()
        let paths = Paths.standard()
        let found = try findForRecovery(workhorse, paths: paths, ui: ui)
        let code = await makeRecovery(paths: paths).unlock(found, ui: ui)
        if code != 0 { throw ExitCode(code) }
    }
}
