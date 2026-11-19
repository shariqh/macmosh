import Foundation

/// How a command talks to the person in front of a terminal tab. Tests use a stand-in.
///
/// It only ever reads plain answers MacMosh asks for (a yes, a number, a user name). Passwords
/// are typed into ssh or `sudo`, which own the terminal at that moment, never into `ask`.
public protocol Interaction: Sendable {
    /// Prints one line.
    func say(_ line: String)
    /// Prints `prompt` with no line break and returns one line from the terminal, without its
    /// line break. An empty string when there is nothing to read.
    func ask(_ prompt: String) -> String
    /// Prints `prompt` and waits for any key.
    func waitForKey(_ prompt: String)
}

extension Interaction {
    /// The last line of every command that runs in a terminal tab. On a non-zero code it says the reason
    /// and waits for a key, so the tab doesn't vanish (design 7.2). Returns the code.
    public func finish(_ code: Int32, reason: String?) -> Int32 {
        guard code != 0 else { return code }
        if let reason, !reason.isEmpty { say(reason) }
        waitForKey("Press any key to close.")
        return code
    }
}

/// The real terminal: standard output for what is said, standard input for answers.
public struct TerminalInteraction: Interaction {
    public init() {}

    public func say(_ line: String) {
        write(line + "\n")
    }

    public func ask(_ prompt: String) -> String {
        write(prompt)
        return readLine(strippingNewline: true) ?? ""
    }

    /// Reads one key with the terminal's line editing and echo off, then puts the terminal back.
    /// When standard input isn't a terminal (a program started the command), it doesn't wait.
    public func waitForKey(_ prompt: String) {
        guard isatty(STDIN_FILENO) == 1 else { return }
        write(prompt)
        var saved = termios()
        guard tcgetattr(STDIN_FILENO, &saved) == 0 else {
            _ = readLine()
            return
        }
        var raw = saved
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO)
        withUnsafeMutableBytes(of: &raw.c_cc) { cc in
            cc[Int(VMIN)] = 1
            cc[Int(VTIME)] = 0
        }
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        var byte: UInt8 = 0
        while read(STDIN_FILENO, &byte, 1) == -1 && errno == EINTR {}
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &saved)
        write("\n")
    }

    /// Unbuffered, so a prompt shows before the program waits for an answer.
    private func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
}
