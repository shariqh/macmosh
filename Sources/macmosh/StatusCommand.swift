import ArgumentParser
import Foundation
import MacMoshKit

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check a workhorse, or all of them, and say how each is."
    )

    @Argument(help: "The workhorse's id or name. Leave it out to check every workhorse.")
    var workhorse: String?

    @Flag(help: "Print JSON for programs instead of words for a person.")
    var json = false

    func run() async throws {
        let paths = Paths.standard()
        let store = WorkhorseStore(paths: paths)
        let list: [Workhorse]
        do {
            if let workhorse { list = [try store.find(workhorse)] } else { list = try store.load() }
        } catch {
            throw failing(error)
        }
        // A workhorse that can't be reached is a result, not an error: the exit code stays 0.
        let results = await makeChecker(paths: paths).checkAll(list)
        save(results, in: store)
        if json {
            print(try StatusFormat.json(results))
        } else {
            print(StatusFormat.text(results), terminator: "")
        }
    }
}
