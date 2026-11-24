import Foundation

public enum LaunchError: Error, Equatable {
    /// macOS refused MacMosh permission to control this terminal app (Automation).
    case automationDenied(TerminalApp)
    /// Anything else, in the words the tool gave.
    case failed(String)
    /// A select script stopped at one of its steps, with AppleScript's error number (menu design 8.4).
    case selectStopped(TerminalApp, step: SelectStep, error: Int)

    /// The plain reason for a stopped step, for the sentence the menu shows:
    /// `iTerm2 couldn't select the tab (error -1728).`
    public static func stoppedReason(_ app: TerminalApp, step: SelectStep, error: Int) -> String {
        "\(app.displayName) couldn't \(step.doing) (error \(error))."
    }
}

/// The steps of a select script (menu design 8.4). Each finds the tab by its terminal device again.
public enum SelectStep: String, Sendable, CaseIterable {
    /// Un-minimizes the tab's window.
    case a = "A"
    /// Brings that window to the front.
    case b = "B"
    /// Selects the tab (and iTerm2's session) and activates the app.
    case c = "C"

    /// What the step does, after "couldn't".
    var doing: String {
        switch self {
        case .a: return "un-minimize the tab's window"
        case .b: return "bring the tab's window to the front"
        case .c: return "select the tab"
        }
    }
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

/// Runs a fixed AppleScript with one argument: a tab's command line, or a terminal device. The argument's
/// text is never part of the script, so nothing in it can be read as AppleScript.
enum AppleScriptRunner {
    /// AppleScript's error number when macOS refuses to let this app control another ("Not authorized to send
    /// Apple events").
    static let notAuthorized = -1743

    /// Time for macOS to show its permission prompt and for the person to answer it.
    static let timeLimit: Duration = .seconds(120)

    static func run(_ script: String, command: TabCommand, app: TerminalApp, runner: CommandRunner) async throws {
        _ = try await run(script, argument: command.line, app: app, runner: runner)
    }

    /// Runs the script and returns what it printed. osascript(1), this Mac's manual: "Any arguments
    /// following the script will be passed as a list of strings to the direct parameter of the "run"
    /// handler", and "osascript normally prints its results in human-readable form: strings do not have
    /// quotes around them".
    static func run(_ script: String, argument: String, app: TerminalApp, runner: CommandRunner) async throws -> String {
        let result = await runner.run("osascript", ["-e", script, argument], environment: [:],
                                      stdin: nil, timeout: timeLimit)
        if result.timedOut {
            throw LaunchError.failed("\(app.displayName) did not answer in time.")
        }
        guard result.exitCode != 0 else { return result.stdout }
        let said = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if said.contains("\(notAuthorized)") || said.contains("Not authorized to send Apple events") {
            throw LaunchError.automationDenied(app)
        }
        throw LaunchError.failed(said.isEmpty ? "osascript ended with code \(result.exitCode)." : said)
    }
}
