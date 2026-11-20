import Foundation

public enum LaunchError: Error, Equatable {
    /// macOS refused MacMosh permission to control this terminal app (Automation).
    case automationDenied(TerminalApp)
    /// Anything else, in the words the tool gave.
    case failed(String)
}

/// One way of opening a tab (or a window) that runs a command.
public protocol TerminalLauncher: Sendable {
    func openTab(_ command: TabCommand, title: String) async throws
}

extension TerminalApp {
    /// How the app is named to people.
    public var displayName: String {
        switch self {
        case .iterm2: return "iTerm2"
        case .appleTerminal: return "Terminal"
        }
    }

    /// The name `open -a` takes.
    var openName: String {
        switch self {
        case .iterm2: return "iTerm"
        case .appleTerminal: return "Terminal"
        }
    }
}

/// Runs a fixed AppleScript with the command line as its one argument. The command's text is
/// never part of the script, so nothing in it can be read as AppleScript.
enum AppleScriptRunner {
    /// Time for macOS to show its permission prompt and for the person to answer it.
    static let timeLimit: Duration = .seconds(120)

    static func run(_ script: String, command: TabCommand, app: TerminalApp, runner: CommandRunner) async throws {
        let result = await runner.run("osascript", ["-e", script, command.line], environment: [:],
                                      stdin: nil, timeout: timeLimit)
        if result.timedOut {
            throw LaunchError.failed("\(app.displayName) did not answer in time.")
        }
        guard result.exitCode != 0 else { return }
        let said = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if said.contains("-1743") || said.contains("Not authorized to send Apple events") {
            throw LaunchError.automationDenied(app)
        }
        throw LaunchError.failed(said.isEmpty ? "osascript ended with code \(result.exitCode)." : said)
    }
}
