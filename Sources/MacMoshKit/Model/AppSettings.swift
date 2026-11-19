import Foundation

public enum TerminalApp: String, Codable, Sendable, CaseIterable { case iterm2, appleTerminal }

public struct AppSettings: Codable, Sendable, Equatable {
    public var terminal: TerminalApp?     // nil: pick automatically

    public init(terminal: TerminalApp? = nil) {
        self.terminal = terminal
    }
}
