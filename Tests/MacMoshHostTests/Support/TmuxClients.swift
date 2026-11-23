import Foundation
import Testing

/// Terminal clients for tests that need a real one: a tab over mosh or ssh is a tmux client with a
/// terminal of its own, and tmux treats it differently from a command run without one.
///
/// Each client runs under `script`, which gives it a pseudo terminal of the given size. Its input is a
/// `sleep`, so it stays attached until the test ends it; the test's own server goes away in `cleanUp`.
extension HostHarness {
    /// Starts `argv` in a terminal of `cols` x `rows` in the background. The environment is the
    /// harness's own (the throwaway socket, the temporary HOME).
    func startClient(_ label: String, cols: Int = 80, rows: Int = 24, _ argv: [String]) throws {
        let file = home.appendingPathComponent("client-\(label).sh")
        let quoted = argv.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        try "stty cols \(cols) rows \(rows)\nexec env TERM=xterm-256color \(quoted)\n"
            .write(to: file, atomically: true, encoding: .utf8)
        _ = shell("(sleep 120 | script -q /dev/null /bin/sh '\(file.path)' >/dev/null 2>&1 &)")
    }

    /// One line per attached client: `<session id>|<session name>|<client pid>|<tty>`.
    func clients() -> [String] {
        tmux(["list-clients", "-F", "#{session_id}|#{client_session}|#{client_pid}|#{client_tty}"]).stdout
            .split(separator: "\n").map(String.init).sorted()
    }

    /// The process id of the client attached to the session with this id, or nil.
    func clientPid(of sessionID: String) -> pid_t? {
        for line in clients() {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if f.count >= 3, f[0] == sessionID { return pid_t(f[2]) }
        }
        return nil
    }

    /// Ends a client the way a closed terminal does, with a hangup, after checking that the process
    /// is a tmux client of this harness's own socket.
    func hangUp(clientOf sessionID: String) throws {
        let pid = try #require(clientPid(of: sessionID), "no client on \(sessionID): \(clients())")
        #expect(pid > 1)
        let command = shell("ps -o command= -p \(pid)").stdout
        try #require(command.contains("tmux") && command.contains(socket),
                     "process \(pid) is not a client of this test's server: \(command)")
        #expect(kill(pid, SIGHUP) == 0)
    }

    /// The name of every session, sorted.
    func sessionNames() -> [String] {
        tmux(["list-sessions", "-F", "#{session_name}"]).stdout.split(separator: "\n").map(String.init).sorted()
    }

    /// One format, read for one session found by id through list-sessions (display-message answers
    /// even for a session that does not exist, so it can't tell).
    func sessionFormat(_ sessionID: String, _ format: String) -> String? {
        let text = tmux(["list-sessions", "-F", "#{session_id}\t" + format]).stdout
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.first.map(String.init) == sessionID { return parts.count > 1 ? String(parts[1]) : "" }
        }
        return nil
    }

    /// The id of the window a session shows.
    func currentWindow(_ sessionID: String) -> String? { sessionFormat(sessionID, "#{window_id}") }
}
