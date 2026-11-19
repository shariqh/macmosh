import ArgumentParser
import Foundation
import MacMoshKit

struct PairCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pair",
        abstract: "Install MacMosh's own ssh key on a workhorse. You type its password into ssh once."
    )

    @Argument(help: "A saved workhorse, or user@address. Leave it out to pick from your Tailscale devices.")
    var workhorse: String?

    @Option(help: "The fingerprint you have already compared at the workhorse; skips the question.")
    var confirmed: String?

    func run() async throws {
        let ui = TerminalInteraction()
        let paths = Paths.standard()
        let runner = ProcessRunner()
        let pairing = Pairing(store: WorkhorseStore(paths: paths), paths: paths, runner: runner, interactive: runner,
                              keys: KeyManager(paths: paths, runner: runner))
        var chosen = workhorse
        if chosen == nil {
            let tailscale = await SystemHints(runner: runner).tailscaleStatus()
            chosen = Pairing.chooseTarget(ui: ui, tailscale: tailscale, currentUser: NSUserName())
        }
        var code: Int32 = 0
        var reason: String?
        if let target = chosen {
            do {
                _ = try await pairing.pair(target, confirmedFingerprint: confirmed, ui: ui)
            } catch {
                code = 1
                reason = Pairing.explain(error, target: target)
            }
        } else {
            code = 1
            reason = "No workhorse was chosen. Run: macmosh pair alex@workhorse, with the workhorse's user name and address."
        }
        let result = ui.finish(code, reason: reason)
        if result != 0 { throw ExitCode(result) }
    }
}
