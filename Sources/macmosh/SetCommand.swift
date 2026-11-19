import ArgumentParser
import Foundation
import MacMoshKit

struct SetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Change a workhorse's setting: name, mode, prediction, projects-folder or identity."
    )

    @Argument(help: "The workhorse's id or name.")
    var workhorse: String

    @Argument(help: "name, mode (mosh, tabs, ssh), prediction (adaptive, always, never, experimental), projects-folder (empty clears it) or identity (a key file, or default).")
    var key: String

    @Argument(help: "The new value.")
    var value: String

    func run() async throws {
        let store = WorkhorseStore(paths: Paths.standard())
        do {
            let found = try store.find(workhorse)
            var trial = found
            try WorkhorseSetting.apply(key: key, value: value, to: &trial)   // refuses before anything is saved
            var failure: Error?
            try store.update(id: found.id) { saved in
                do { try WorkhorseSetting.apply(key: key, value: value, to: &saved) } catch { failure = error }
            }
            if let failure { throw failure }
            print(WorkhorseSetting.describe(key: key, trial))
        } catch let error as SettingError {
            printError(error.description)
            throw ExitCode(1)
        } catch {
            throw failing(error)
        }
    }
}
