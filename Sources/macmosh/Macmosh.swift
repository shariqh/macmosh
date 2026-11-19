import ArgumentParser
import MacMoshKit

@main
struct Macmosh: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macmosh",
        abstract: "Drive a spare Mac that works as your workhorse.",
        version: MacMoshInfo.version,
        subcommands: [
            DesksCommand.self,
            ListCommand.self,
            StatusCommand.self,
        ]
    )
}
