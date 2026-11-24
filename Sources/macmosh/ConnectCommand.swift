import ArgumentParser
import Foundation
import MacMoshKit

/// Checks the workhorse, then opens the desk in this terminal tab. It runs in a terminal tab, so a
/// failure says why and waits for a key (the tab doesn't vanish). Returns the exit code.
func connectToDesk(_ workhorseName: String, desk: DeskName, mode: ConnectionMode?, tab: TabTarget? = nil,
                   ui: Interaction) async -> Int32 {
    let paths = Paths.standard()
    let store = WorkhorseStore(paths: paths)
    let found: Workhorse
    do {
        found = try store.find(workhorseName)
    } catch {
        return ui.finish(1, reason: StatusFormat.storeMessage(error))
    }
    let checker = makeChecker(paths: paths)
    let result = await checker.check(found)
    save([result], in: store)
    let runner = ConnectRunner(interactive: ProcessRunner(), sleep: { try? await Task.sleep(for: $0) },
                               stateNow: { await checker.check(found).state })
    return await runner.connect(result, desk: desk, requestedMode: mode, paths: paths,
                                environment: ProcessInfo.processInfo.environment,
                                findMosh: { ToolFinder.find("mosh") }, ui: ui, tab: tab)
}

struct ConnectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect",
        abstract: "Open a desk on a workhorse in this terminal tab: over mosh, as iTerm2 tabs or over plain ssh."
    )

    @Argument(help: "The workhorse's id or name.")
    var workhorse: String

    @Argument(help: "The desk's name.")
    var desk: String

    @Option(help: "How to connect: mosh, tabs or ssh. Leave it out to use the workhorse's setting.")
    var mode: String?

    @Option(help: ArgumentHelp("Show this window of the desk in this tab, by its id.", valueName: "@id"))
    var window: String?

    @Flag(help: "Give the desk a new window and show it in this tab.")
    var newWindow = false

    @Flag(help: "Show the window the desk shows now, in this tab's own view of the desk.")
    var view = false

    func validate() throws {
        do {
            _ = try TabTarget.from(window: window, newWindow: newWindow, view: view)
        } catch {
            throw ValidationError(error.description)
        }
    }

    func run() async throws {
        let ui = TerminalInteraction()
        var chosen: ConnectionMode?
        if let mode {
            guard let known = ConnectionMode(rawValue: mode) else {
                throw ExitCode(ui.finish(1, reason: "\"\(mode)\" isn't a way to connect. Use one of: \(ConnectionMode.allCases.map(\.rawValue).joined(separator: ", "))."))
            }
            chosen = known
        }
        guard let name = DeskName(desk) else {
            throw ExitCode(ui.finish(1, reason: DeskFormat.nameRule))
        }
        // validate() has refused a bad combination already.
        let tab = try? TabTarget.from(window: window, newWindow: newWindow, view: view)
        let code = await connectToDesk(workhorse, desk: name, mode: chosen, tab: tab, ui: ui)
        if code != 0 { throw ExitCode(code) }
    }
}
