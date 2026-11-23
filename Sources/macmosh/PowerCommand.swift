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

    @Argument(help: "awake (stay awake on power), autorestart (start again after a power cut, desktop Macs) or lid (keep a laptop running with its lid closed).")
    var setting: PowerSetting

    @Argument(help: "For lid only: on or off. The other settings take nothing here.")
    var value: String?

    func run() async throws {
        let request: PowerRequest
        do {
            request = try PowerRequest.parse(setting: setting, word: value)
        } catch let usage as PowerUsageError {
            throw ValidationError(usage.description)
        }
        let ui = TerminalInteraction()
        let paths = Paths.standard()
        let found = try findForRecovery(workhorse, paths: paths, ui: ui)
        let runner = ProcessRunner()
        let flow = PowerFlow(checker: makeChecker(paths: paths), store: WorkhorseStore(paths: paths), paths: paths,
                             interactive: runner, keys: KeyManager(paths: paths, runner: runner))
        let code = await flow.power(found, setting: request.setting, turnOn: request.turnOn, ui: ui)
        if code != 0 { throw ExitCode(code) }
    }
}
