import ArgumentParser
import Foundation
import MacMoshKit

struct FoldersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "folders",
        abstract: "List the folders inside a workhorse's projects folder."
    )

    @Argument(help: "The workhorse's id or name.")
    var workhorse: String

    @Flag(help: "Print JSON for programs instead of one name per line.")
    var json = false

    func run() async throws {
        let outcome: DeskResult
        switch await checkedForDesk(workhorse) {
        case .failure(let failed): outcome = failed
        case .success(let check): outcome = await deskFlow().folders(check)
        }
        guard outcome.code == 0 else { return try outcome.finishPlainly() }
        if json {
            print(try DeskFormat.foldersJSON(outcome.output))
        } else {
            outcome.output.forEach { print($0) }
        }
    }
}
