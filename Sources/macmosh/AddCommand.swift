import ArgumentParser
import Foundation
import MacMoshKit

struct AddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Save a workhorse and pin its ssh host key. Run macmosh pair next."
    )

    @Argument(help: "The workhorse, as user@address (for example alex@workhorse).")
    var target: String

    @Option(help: "The name shown for it. Without one, the address's first part is used.")
    var name: String?

    @Flag(help: "Print the saved workhorse as JSON.")
    var json = false

    /// What `--json` prints.
    private struct Added: Encodable {
        var id, name, user, mainAddress, hostKey, fingerprint: String
        var paired: Bool
    }

    func run() async throws {
        let ui = TerminalInteraction()
        let paths = Paths.standard()
        let runner = ProcessRunner()
        let pairing = Pairing(store: WorkhorseStore(paths: paths), paths: paths, runner: runner, interactive: runner,
                              keys: KeyManager(paths: paths, runner: runner))
        var code: Int32 = 0
        var reason: String?
        do {
            let w = try await pairing.add(target: target, name: name)
            let fingerprint = try HostKeys.fingerprint(of: w.hostKey)
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let added = Added(id: w.id, name: w.name, user: w.user, mainAddress: w.mainAddress,
                                  hostKey: w.hostKey, fingerprint: fingerprint, paired: w.paired)
                ui.say(String(decoding: try encoder.encode(added), as: UTF8.self))
            } else {
                ui.say("Saved \(w.name) as \(w.id), with its host key pinned.")
                ui.say("Its key fingerprint is: \(fingerprint)")
                ui.say("At the workhorse, run this and compare: \(HostKeys.compareCommand)")
                ui.say(w.paired ? "It is already paired." : "Next: macmosh pair \(w.id)")
            }
        } catch {
            code = 1
            reason = Pairing.explain(error, target: target)
        }
        let result = ui.finish(code, reason: reason)
        if result != 0 { throw ExitCode(result) }
    }
}
