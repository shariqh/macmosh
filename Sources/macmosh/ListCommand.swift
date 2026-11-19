import ArgumentParser
import Foundation
import MacMoshKit

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the workhorses MacMosh knows, without checking them."
    )

    @Flag(help: "Print JSON for programs instead of words for a person.")
    var json = false

    func run() throws {
        let list: [Workhorse]
        do { list = try WorkhorseStore(paths: Paths.standard()).load() } catch { throw failing(error) }
        if json {
            print(try StatusFormat.listJSON(list))
        } else {
            print(StatusFormat.listText(list), terminator: "")
        }
    }
}
