import ArgumentParser
import MacMoshKit

@main
struct Macmosh: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macmosh",
        abstract: "Drive a spare Mac that works as your workhorse.",
        version: MacMoshInfo.version,
        subcommands: [
            AddCommand.self,
            DeskCommand.self,
            DesksCommand.self,
            FoldersCommand.self,
            ListCommand.self,
            PairCommand.self,
            StatusCommand.self,
            SwiftBarCommand.self,
        ]
    )
}
