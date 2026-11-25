import Foundation
@testable import MacMoshKit

/// A stand-in `Interaction` for tests: records what was said and asked, answers `ask` from a
/// list (an empty string once the list runs out), and counts `waitForKey` calls. Reads no terminal.
final class ScriptedInteraction: Interaction, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String]
    private var saidLines: [String] = []
    private var askedPrompts: [String] = []
    private var waitCount = 0

    init(answers: [String] = []) {
        self.answers = answers
    }

    /// Every line passed to `say`, oldest first.
    var said: [String] { lock.withLock { saidLines } }
    /// Every prompt passed to `ask`, oldest first.
    var asked: [String] { lock.withLock { askedPrompts } }
    /// How many times `waitForKey` was called.
    var waits: Int { lock.withLock { waitCount } }

    func say(_ line: String) {
        lock.withLock { saidLines.append(line) }
    }

    func ask(_ prompt: String) -> String {
        lock.withLock {
            askedPrompts.append(prompt)
            return answers.isEmpty ? "" : answers.removeFirst()
        }
    }

    /// Like `ask`, but nil once the list has run out, as a terminal's end of input.
    func askOrEnd(_ prompt: String) -> String? {
        lock.withLock {
            askedPrompts.append(prompt)
            return answers.isEmpty ? nil : answers.removeFirst()
        }
    }

    func waitForKey(_ prompt: String) {
        lock.withLock { waitCount += 1 }
    }
}
