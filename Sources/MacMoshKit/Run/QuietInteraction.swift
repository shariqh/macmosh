import Foundation

/// An `Interaction` that never waits, for the MacMosh window's desk actions (main window design, section
/// 7.2): it keeps what is said, answers every question with nothing, and ignores "press a key". Run with it,
/// a desk command that would ask a question stops at once, as an empty answer stops it.
public final class QuietInteraction: Interaction, @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    public init() {}

    /// Every line said so far, oldest first.
    public var said: [String] { lock.withLock { lines } }

    public func say(_ line: String) {
        lock.withLock { lines.append(line) }
    }

    public func ask(_ prompt: String) -> String { "" }

    /// End of input, so a question where an empty line means something stops too.
    public func askOrEnd(_ prompt: String) -> String? { nil }

    public func waitForKey(_ prompt: String) {}
}
