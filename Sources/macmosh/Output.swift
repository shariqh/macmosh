import ArgumentParser
import Foundation
import MacMoshKit

/// Prints a line to standard error.
func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

/// Says what went wrong with the saved workhorses in plain words, then ends the command with exit code 1.
func failing(_ error: Error) -> ExitCode {
    printError(StatusFormat.storeMessage(error))
    return ExitCode(1)
}

/// Saves what a check learned. A failure to save is a warning: the check's answer is still shown.
func save(_ results: [CheckResult], in store: WorkhorseStore) {
    for result in results {
        do { try store.absorb(result) } catch {
            printError("macmosh: could not save what was learned about \(result.workhorse.name): \(StatusFormat.storeMessage(error))")
        }
    }
}

/// The checker the commands use: the real `ssh` and the real hints from this Mac.
func makeChecker(paths: Paths) -> StatusChecker {
    let runner = ProcessRunner()
    return StatusChecker(runner: runner, paths: paths, hints: SystemHints(runner: runner))
}
