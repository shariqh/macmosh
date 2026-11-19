import ArgumentParser
import Foundation
import MacMoshKit

struct SettingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "settings",
        abstract: "Change a setting that belongs to MacMosh itself, not to a workhorse.",
        subcommands: [Terminal.self]
    )

    struct Terminal: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "terminal",
            abstract: "Choose the terminal app MacMosh opens tabs in: iterm2, terminal, or auto to pick for you."
        )

        @Argument(help: "iterm2, terminal or auto.")
        var choice: String

        func run() async throws {
            let store = WorkhorseStore(paths: Paths.standard())
            do {
                var settings = try store.loadSettings()
                try WorkhorseSetting.applyTerminal(choice, to: &settings)
                try store.saveSettings(settings)
                print(WorkhorseSetting.describeTerminal(settings))
            } catch let error as SettingError {
                printError(error.description)
                throw ExitCode(1)
            } catch {
                throw failing(error)
            }
        }
    }
}
