import Foundation

/// Why a desk command on the workhorse didn't work. The first five and the two after them are
/// the workhorse script's exit codes 6, 7, 4, (no projects folder, which is checked here) and 3 and 5.
public enum HostCommandError: Error, Equatable {
    /// Exit code 6: a bad desk name, folder or startup command.
    case badInput
    /// Exit code 7: a desk with that name is already there.
    case alreadyExists
    /// Exit code 4: no such desk.
    case noSuchDesk
    /// The workhorse has no projects folder saved, so there is nothing to list.
    case noProjectsFolder
    /// Exit code 3: nobody is logged in at the workhorse's screen, so the desk server can't start.
    case nobodyLoggedIn
    /// Exit code 5: the desk server didn't start.
    case serverDidNotStart
    /// Anything else, in plain words. `exitCode` is the script's, or 255 when ssh itself didn't get through.
    case failed(exitCode: Int32, message: String)
}

/// The desk commands, run on a workhorse through the workhorse script. Every call is one batch ssh
/// to `address`, which is where a status check just got its answer. Nothing here is checked for
/// readiness: `DeskFlow` does that first.
public struct HostCommands: Sendable {
    /// One call gets this long. ssh's own connect limit is 5 seconds (`SSHInvocation`); the script
    /// may wait up to 5 more for the desk server.
    static let timeLimit: Duration = .seconds(15)

    private let runner: CommandRunner
    private let paths: Paths

    public init(runner: CommandRunner, paths: Paths) {
        self.runner = runner
        self.paths = paths
    }

    /// The script's arguments for a new desk. The flags appear only when asked for, in this order:
    /// `--reopen`, `--keep`, `--command <text>`. An empty command is no command. `SSHInvocation.hostCommand`
    /// quotes each one once for the remote shell, so the folder and the command arrive exactly as given.
    public static func newDeskArguments(name: DeskName, folder: String, reopen: Bool, keep: Bool,
                                        command: String?) -> [String] {
        var args = ["desk-new", name.value, folder]
        if reopen { args.append("--reopen") }
        if keep { args.append("--keep") }
        if let command, !command.isEmpty { args += ["--command", command] }
        return args
    }

    public func newDesk(on w: Workhorse, address: String, name: DeskName, folder: String,
                        reopen: Bool, keep: Bool, command: String?) async throws {
        _ = try await run(w, address, Self.newDeskArguments(name: name, folder: folder, reopen: reopen,
                                                            keep: keep, command: command))
    }

    /// Removes the desk's definition. Its open session is closed only with `kill`.
    public func removeDesk(on w: Workhorse, address: String, name: DeskName, kill: Bool) async throws {
        _ = try await run(w, address, ["desk-remove", name.value] + (kill ? ["--kill"] : []))
    }

    public func newWindow(on w: Workhorse, address: String, desk: DeskName) async throws {
        _ = try await run(w, address, ["window-new", desk.value])
    }

    /// The names of the folders inside the workhorse's projects folder, sorted by the workhorse.
    /// The folder is sent as saved, so a leading `~` is expanded on the workhorse.
    public func folders(on w: Workhorse, address: String) async throws -> [String] {
        guard let projects = w.projectsFolder, !projects.isEmpty else { throw HostCommandError.noProjectsFolder }
        let out = try await run(w, address, ["folders", projects])
        return out.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
    }

    // MARK: - One call

    /// Key first: with the key unusable no ssh runs at all (ssh would only warn, then quietly try the
    /// user's own keys). Returns the script's standard output.
    private func run(_ w: Workhorse, _ address: String, _ arguments: [String]) async throws -> String {
        guard KeyManager(paths: paths, runner: runner).identityState(for: w) == .usable else {
            throw HostCommandError.failed(exitCode: 255, message: "Your ssh key is locked: MacMosh can't use its key file. Run: macmosh status \(w.id)")
        }
        let argv = SSHInvocation.argv(for: w, address: address, paths: paths, batch: true, tty: false,
                                      remote: SSHInvocation.hostCommand(arguments))
        let result = await runner.run(argv[0], Array(argv.dropFirst()), environment: [:], stdin: nil,
                                      timeout: Self.timeLimit)
        let outcome = SSHProbe.classify(result)
        if case .ok(let stdout) = outcome { return stdout }
        throw Self.error(for: outcome)
    }

    private static func error(for outcome: ProbeOutcome) -> HostCommandError {
        func failed(_ message: String) -> HostCommandError { .failed(exitCode: 255, message: message) }
        switch outcome {
        case .ok:
            return failed("ssh answered, but not in a way MacMosh understands.")
        case .remoteFailed(let code, let stderr):
            switch code {
            case 3: return .nobodyLoggedIn
            case 4: return .noSuchDesk
            case 5: return .serverDidNotStart
            case 6: return .badInput
            case 7: return .alreadyExists
            default: return .failed(exitCode: code, message: scriptMessage(code, stderr))
            }
        case .authDenied:
            return failed("The workhorse turned MacMosh's key down. Check it with: macmosh status")
        case .hostKeyChanged:
            return failed("The workhorse's host key is different from the one MacMosh saved. Stop, and check at the Mac.")
        case .hostKeyUnknown:
            return failed("MacMosh has no saved host key for this workhorse. Pair it again with: macmosh pair")
        case .timedOut:
            return failed("The workhorse didn't answer within \(Int(timeLimit.components.seconds)) seconds.")
        case .refused:
            return failed("The workhorse refused the connection. Is Remote Login on?")
        case .unresolved:
            return failed("MacMosh couldn't find the workhorse's address.")
        case .unreachable(let detail):
            return failed(detail.isEmpty ? "ssh couldn't connect to the workhorse." : "ssh couldn't connect: \(detail)")
        case .identityUnusable(let detail):
            return failed("MacMosh can't use its ssh key: \(detail)")
        }
    }

    /// The script's own last line of complaint, without its `macmosh-host: ` prefix.
    private static func scriptMessage(_ code: Int32, _ stderr: String) -> String {
        let last = stderr.split(whereSeparator: \.isNewline).last.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let prefix = "macmosh-host: "
        let text = last.hasPrefix(prefix) ? String(last.dropFirst(prefix.count)) : last
        if text.isEmpty { return "The script on the workhorse stopped with exit code \(code)." }
        return text.prefix(1).uppercased() + text.dropFirst() + (text.hasSuffix(".") ? "" : ".")
    }
}
