import ArgumentParser
import Foundation
import MacMoshKit

struct PrepareCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prepare",
        abstract: "Run the setup checklist for a workhorse: what is ready on this Mac and on the workhorse, and how to fix the rest."
    )

    @Argument(help: "The workhorse's id or name.")
    var workhorse: String

    @Flag(help: "Do the automatic fixes, saying each one first. Never runs sudo or changes a power or security setting.")
    var fix = false

    @Flag(help: "Print JSON for programs instead of words for a person.")
    var json = false

    @Flag(help: "Wait for a key at the end, so a terminal tab stays open.")
    var pause = false

    @Flag(name: .customLong("restart-desk-server"),
          help: "Restart the desk server so sign-ins work. It lists the desks that close and asks first.")
    var restartDeskServer = false

    @Flag(name: .customLong("install-homebrew"),
          help: "Install Homebrew on the workhorse. It shows Homebrew's own command and asks first; you type the Mac's password into ssh.")
    var installHomebrew = false

    func validate() throws {
        if restartDeskServer && installHomebrew {
            throw ValidationError("Use --restart-desk-server or --install-homebrew, not both.")
        }
        if (restartDeskServer || installHomebrew) && (fix || json) {
            throw ValidationError("--restart-desk-server and --install-homebrew run on their own, without --fix or --json.")
        }
    }

    func run() async throws {
        let ui = TerminalInteraction()
        let paths = Paths.standard()
        let found = try findForRecovery(workhorse, paths: paths, ui: ui)
        let runner = ProcessRunner()
        let hints = SystemHints(runner: runner)
        let checklist = Checklist(runner: runner, paths: paths, store: WorkhorseStore(paths: paths),
                                  checker: StatusChecker(runner: runner, paths: paths, hints: hints),
                                  keys: KeyManager(paths: paths, runner: runner), hints: hints)

        if restartDeskServer {
            let done = await checklist.restartDeskServer(for: found, ui: ui)
            let code = ui.finish(done ? 0 : 1, reason: nil)
            if pause && done { ui.waitForKey("Press any key to close.") }
            if code != 0 { throw ExitCode(code) }
            return
        }
        if installHomebrew {
            let code = await checklist.installHomebrew(for: found, interactive: runner, ui: ui)
            if pause && code == 0 { ui.waitForKey("Press any key to close.") }
            if code != 0 { throw ExitCode(code) }
            return
        }

        let outcomes: [CheckOutcome]
        if fix {
            // With --json, what is being fixed goes to standard error so the JSON stays readable.
            let toStandardError = json
            outcomes = await checklist.applyAutomaticFixes(for: found, progress: { line in
                if toStandardError { printError(line) } else { print(line) }
            })
            if !json { print("") }
        } else {
            outcomes = await checklist.run(for: found)
        }
        if json {
            print(try ChecklistFormat.json(outcomes))
        } else {
            print(ChecklistFormat.text(outcomes), terminator: "")
        }
        if pause { ui.waitForKey("Press any key to close.") }
    }
}
