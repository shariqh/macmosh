import ArgumentParser
import Foundation
import MacMoshKit

struct RestartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Restart a workhorse. It lists the desks that will close and asks first."
    )

    @Argument(help: "The workhorse's id or name.")
    var workhorse: String

    @Flag(help: "A full restart: the disk is locked afterwards, so the unlock is tried too.")
    var full = false

    func run() async throws {
        let ui = TerminalInteraction()
        let paths = Paths.standard()
        let found = try findForRecovery(workhorse, paths: paths, ui: ui)
        let code = await makeRecovery(paths: paths).restart(found, full: full, ui: ui)
        if code != 0 { throw ExitCode(code) }
    }
}
