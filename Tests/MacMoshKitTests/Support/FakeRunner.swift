import Foundation
@testable import MacMoshKit

/// A stand-in `CommandRunner` for tests: records every call and answers from a closure.
final class FakeRunner: CommandRunner, @unchecked Sendable {
    struct Call: Equatable {
        var argv: [String]
        var environment: [String: String]
        var stdin: Data?
        var timeout: Duration
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let answer: @Sendable ([String]) -> CommandResult

    /// The calls made so far, oldest first.
    var calls: [Call] { lock.withLock { recorded } }

    /// `answer` gets argv, which is `[executable] + arguments`.
    init(_ answer: @escaping @Sendable ([String]) -> CommandResult) {
        self.answer = answer
    }

    static func ok(_ stdout: String = "") -> CommandResult {
        CommandResult(exitCode: 0, stdout: stdout, stderr: "", timedOut: false)
    }

    static func failed(_ exitCode: Int32, stderr: String = "") -> CommandResult {
        CommandResult(exitCode: exitCode, stdout: "", stderr: stderr, timedOut: false)
    }

    func run(_ executable: String, _ arguments: [String], environment: [String: String],
             stdin: Data?, timeout: Duration) async -> CommandResult {
        let argv = [executable] + arguments
        lock.withLock {
            recorded.append(Call(argv: argv, environment: environment, stdin: stdin, timeout: timeout))
        }
        return answer(argv)
    }
}
