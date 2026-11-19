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
            PowerCommand.self,
            RemoveCommand.self,
            RestartCommand.self,
            ScreenCommand.self,
            SetCommand.self,
            SettingsCommand.self,
            StatusCommand.self,
            SwiftBarCommand.self,
            UnlockCommand.self,
        ]
    )
}
