import Foundation
@testable import MacMoshKit

/// A stand-in `InteractiveRunner` for tests: records every `runAttached` call and returns exit
/// codes from the list given at creation (0 once the list runs out). Starts no program.
final class FakeInteractive: InteractiveRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var exitCodes: [Int32]
    private var recorded: [[String]] = []
    private let onRun: (@Sendable ([String]) -> Void)?

    /// `onRun`, when given, is called with argv at the moment of each call, before it returns.
    init(exitCodes: [Int32] = [], onRun: (@Sendable ([String]) -> Void)? = nil) {
        self.exitCodes = exitCodes
        self.onRun = onRun
    }

    /// The argv of every call so far, oldest first.
    var calls: [[String]] { lock.withLock { recorded } }

    func runAttached(_ argv: [String], environment: [String: String]) async -> Int32 {
        onRun?(argv)
        return lock.withLock {
            recorded.append(argv)
            return exitCodes.isEmpty ? 0 : exitCodes.removeFirst()
        }
    }
}
