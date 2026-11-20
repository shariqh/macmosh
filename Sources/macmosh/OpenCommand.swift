import ArgumentParser
import Foundation
import MacMoshKit

struct OpenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open a terminal tab that runs macmosh with the arguments you give, such as: macmosh open connect mbp website."
    )

    @Argument(parsing: .captureForPassthrough, help: "What the tab runs after macmosh, for example: connect mbp website.")
    var arguments: [String] = []

    func run() async throws {
        guard !arguments.isEmpty else {
            printError("macmosh open: say what the tab should run, for example: macmosh open connect mbp website")
            throw ExitCode(2)
        }
        let command: TabCommand
        do {
            command = try TabCommand(macmoshPath: ownPath(), arguments: arguments)
        } catch TabCommandError.unsafeArgument(let text) {
            printError("macmosh open: \"\(text)\" can't be used in a tab. Use only letters, digits and these characters: @ % + = : , . / _ -")
            throw ExitCode(2)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("macmosh-tabs", isDirectory: true)
        let opener = TabOpener(runner: ProcessRunner(), settings: (try? WorkhorseStore(paths: Paths.standard()).loadSettings()) ?? AppSettings(),
                               temporaryFolder: folder,
                               fileExists: { FileManager.default.fileExists(atPath: $0) })
        do {
            if let said = try await opener.open(command, title: arguments.last ?? "macmosh") { print(said) }
        } catch LaunchError.failed(let reason) {
            printError("macmosh open: the tab didn't open. \(reason)")
            throw ExitCode(1)
        } catch LaunchError.automationDenied(let app) {
            printError("macmosh open: macOS hasn't let MacMosh control \(app.displayName). To allow it: System Settings > Privacy & Security > Automation.")
            throw ExitCode(1)
        }
    }

    /// The absolute path this command was started from.
    private func ownPath() -> String {
        if let path = Bundle.main.executablePath { return URL(fileURLWithPath: path).standardizedFileURL.path }
        let first = CommandLine.arguments[0]
        if first.hasPrefix("/") { return first }
        return ToolFinder.find(first) ?? first
    }
}
