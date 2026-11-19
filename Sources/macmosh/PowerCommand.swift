import ArgumentParser
import Foundation
import MacMoshKit

extension PowerSetting: ExpressibleByArgument {}

struct PowerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "power",
        abstract: "Change a power setting on a workhorse. It shows the exact command first; you type the Mac's password into ssh."
    )

    @Argument(help: "The workhorse's id or name.")
    var workhorse: String

    @Argument(help: "awake (stay awake on power) or autorestart (start again after a power cut, desktop Macs).")
    var setting: PowerSetting

    func run() async throws {
        let ui = TerminalInteraction()
        let paths = Paths.standard()
        let found = try findForRecovery(workhorse, paths: paths, ui: ui)
        let runner = ProcessRunner()
        let flow = PowerFlow(checker: makeChecker(paths: paths), store: WorkhorseStore(paths: paths), paths: paths,
                             interactive: runner, keys: KeyManager(paths: paths, runner: runner))
        let code = await flow.power(found, setting: setting, ui: ui)
        if code != 0 { throw ExitCode(code) }
    }
}
