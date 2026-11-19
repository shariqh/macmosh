import ArgumentParser
import Foundation
import MacMoshKit

struct DesksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "desks",
        abstract: "List a workhorse's desks: name, windows and attached tabs."
    )

    @Argument(help: "The workhorse's id or name.")
    var workhorse: String

    @Flag(help: "Print JSON for programs instead of words for a person.")
    var json = false

    func run() async throws {
        let paths = Paths.standard()
        let store = WorkhorseStore(paths: paths)
        let found: Workhorse
        do { found = try store.find(workhorse) } catch { throw failing(error) }
        let result = await makeChecker(paths: paths).check(found)
        save([result], in: store)

        // Desks are listed only for a workhorse that is Ready. Otherwise say why, and exit 1.
        guard case .ready = result.state, let status = result.status else {
            printError(StatusFormat.text([result]).trimmingCharacters(in: .newlines))
            throw ExitCode(1)
        }
        if json {
            print(try StatusFormat.desksJSON(status))
        } else if status.desks.isEmpty {
            print("No desks yet.")
        } else {
            print(StatusFormat.deskLines(status).joined(separator: "\n"))
        }
    }
}
