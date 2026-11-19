import ArgumentParser
import Foundation
import MacMoshKit

struct ScreenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screen",
        abstract: "Open Screen Sharing at the address where the workhorse answers."
    )

    @Argument(help: "The workhorse's id or name.")
    var workhorse: String

    func run() async throws {
        let ui = TerminalInteraction()
        let paths = Paths.standard()
        let found = try findForRecovery(workhorse, paths: paths, ui: ui)
        let code = await makeRecovery(paths: paths).screen(found, runner: ProcessRunner(), ui: ui)
        if code != 0 { throw ExitCode(code) }
    }
}
