import Foundation

/// What a finished command left behind.
public struct CommandResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

/// Runs a program and collects its output. Tests swap in a stand-in.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], environment: [String: String],
             stdin: Data?, timeout: Duration) async -> CommandResult
}

/// Hands the terminal to a child program and waits for it to finish.
public protocol InteractiveRunner: Sendable {
    func runAttached(_ argv: [String], environment: [String: String]) async -> Int32
}
