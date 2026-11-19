import Foundation

/// Runs real programs. `run` collects output under a time limit; `runAttached` hands over the terminal.
public struct ProcessRunner: CommandRunner, InteractiveRunner {
    public init() {}

    // MARK: run

    /// Seconds between SIGTERM and SIGKILL when a command has to be stopped.
    private static let killDelay: Double = 2
    /// How long to wait for the output pipes to close after the child has exited. A grandchild that
    /// kept a pipe open must not hold the caller up.
    private static let drainGrace: Double = 2

    public func run(_ executable: String, _ arguments: [String], environment: [String: String],
                    stdin: Data?, timeout: Duration) async -> CommandResult {
        let env = Spawn.mergedEnvironment(environment)
        guard let path = Spawn.resolve(executable, environment: env) else {
            return CommandResult(exitCode: 127, stdout: "",
                                 stderr: "macmosh: \(executable): command not found\n", timedOut: false)
        }
        guard let outPipe = Spawn.makePipe(), let errPipe = Spawn.makePipe() else {
            return CommandResult(exitCode: 127, stdout: "",
                                 stderr: "macmosh: \(executable): could not create pipes\n", timedOut: false)
        }
        var inPipe: (read: Int32, write: Int32)?
        if stdin != nil { inPipe = Spawn.makePipe() }

        let stdinSpec: Spawn.Stdio = inPipe.map { .fd($0.read) } ?? .devNull
        let spawned = Spawn.spawn(path: path, argv: [executable] + arguments, environment: env,
                                  stdio: [stdinSpec, .fd(outPipe.write), .fd(errPipe.write)], ownProcessGroup: true)
        // The child has its own copies now; the parent keeps only its ends.
        close(outPipe.write)
        close(errPipe.write)
        if let inPipe { close(inPipe.read) }

        guard case .success(let pid) = spawned else {
            close(outPipe.read)
            close(errPipe.read)
            if let inPipe { close(inPipe.write) }
            var code: Int32 = 0
            if case .failure(let e) = spawned { code = e.code }
            return CommandResult(exitCode: 127, stdout: "",
                                 stderr: "macmosh: \(executable): \(String(cString: strerror(code)))\n", timedOut: false)
        }

        let child = Child(pid: pid)
        let group = DispatchGroup()
        let out = Collector(), err = Collector()
        out.start(fd: outPipe.read, group: group)
        err.start(fd: errPipe.read, group: group)
        if let inPipe, let stdin { Spawn.feed(stdin, to: inPipe.write) }

        let timer = Task {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { child.stop(afterGrace: Self.killDelay, timedOut: true) }
        }
        let status = await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Int32, Never>) in
                DispatchQueue.global().async { c.resume(returning: child.waitAndReap()) }
            }
        } onCancel: {
            child.stop(afterGrace: Self.killDelay, timedOut: false)
        }
        timer.cancel()

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                _ = group.wait(timeout: .now() + Self.drainGrace)
                c.resume()
            }
        }
        let stopped = child.wasStopped
        return CommandResult(exitCode: stopped.stopped ? -1 : Spawn.exitCode(fromWaitStatus: status),
                             stdout: String(decoding: out.data, as: UTF8.self),
                             stderr: String(decoding: err.data, as: UTF8.self),
                             timedOut: stopped.timedOut)
    }

    // MARK: runAttached

    public func runAttached(_ argv: [String], environment: [String: String]) async -> Int32 {
        let env = Spawn.mergedEnvironment(environment)
        guard let first = argv.first, let path = Spawn.resolve(first, environment: env) else {
            FileHandle.standardError.write(Data("macmosh: \(argv.first ?? ""): command not found\n".utf8))
            return 127
        }
        // Ignore Ctrl-C in the parent before the child exists, so the key can never arrive
        // while the parent still has the default action (quit). The child gets the default
        // action back, so Ctrl-C still reaches ssh or mosh.
        SigintGuard.shared.enter()
        defer { SigintGuard.shared.leave() }

        switch Spawn.spawn(path: path, argv: argv, environment: env,
                           stdio: [.inherit, .inherit, .inherit], ownProcessGroup: false) {
        case .failure(let failure):
            FileHandle.standardError.write(Data("macmosh: \(first): \(String(cString: strerror(failure.code)))\n".utf8))
            return 127
        case .success(let pid):
            let child = Child(pid: pid)
            let status = await withCheckedContinuation { (c: CheckedContinuation<Int32, Never>) in
                DispatchQueue.global().async { c.resume(returning: child.waitAndReap()) }
            }
            return Spawn.exitCode(fromWaitStatus: status)
        }
    }
}

// MARK: - Helpers

/// One running child. All signalling goes through the lock, and stops once the child is
/// reaped, so a recycled process number is never signalled.
private final class Child: @unchecked Sendable {
    private let pid: pid_t
    private let lock = NSLock()
    private var reaped = false
    private var stopped = false
    private var timedOut = false

    init(pid: pid_t) { self.pid = pid }

    var wasStopped: (stopped: Bool, timedOut: Bool) { lock.withLock { (stopped, timedOut) } }

    /// Blocks until the child has exited, then collects its status.
    func waitAndReap() -> Int32 {
        // Wait without collecting, so the number stays ours until we hold the lock.
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == -1 && errno == EINTR {}
        return lock.withLock {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            reaped = true
            return status
        }
    }

    /// SIGTERM to the child's whole process group now, SIGKILL after `afterGrace` seconds if it is still there.
    func stop(afterGrace: Double, timedOut isTimeout: Bool) {
        let sent: Bool = lock.withLock {
            guard !reaped else { return false }
            stopped = true
            if isTimeout { timedOut = true }
            kill(-pid, SIGTERM)
            return true
        }
        guard sent else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + afterGrace) { [self] in
            lock.withLock { if !reaped { kill(-pid, SIGKILL) } }
        }
    }
}

/// Reads one pipe to the end on its own thread.
private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    var data: Data { lock.withLock { buffer } }

    func start(fd: Int32, group: DispatchGroup) {
        group.enter()
        DispatchQueue.global().async { [self] in
            var chunk = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = read(fd, &chunk, chunk.count)
                if n > 0 {
                    lock.withLock { buffer.append(contentsOf: chunk[0..<n]) }
                } else if n < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
            close(fd)
            group.leave()
        }
    }
}

/// Keeps Ctrl-C ignored while any attached child runs, however many overlap, then puts back
/// whatever handling was there before.
private final class SigintGuard: @unchecked Sendable {
    static let shared = SigintGuard()
    private let lock = NSLock()
    private var depth = 0
    private var previous: sig_t?

    func enter() {
        lock.withLock {
            if depth == 0 { previous = signal(SIGINT, SIG_IGN) }
            depth += 1
        }
    }

    func leave() {
        lock.withLock {
            depth -= 1
            if depth == 0 { signal(SIGINT, previous) }
        }
    }
}

private enum Spawn {
    enum Stdio { case inherit, devNull, fd(Int32) }
    /// The error number `posix_spawn` gave back.
    struct Failure: Error { var code: Int32 }

    static func mergedEnvironment(_ extra: [String: String]) -> [String: String] {
        ProcessInfo.processInfo.environment.merging(extra) { _, new in new }
    }

    /// A name with a `/` is used as it stands; a bare name is looked up on `PATH`, then in Homebrew's folders.
    static func resolve(_ name: String, environment: [String: String]) -> String? {
        if name.contains("/") { return name.isEmpty ? nil : name }
        return ToolFinder.find(name, path: environment["PATH"])
    }

    static func exitCode(fromWaitStatus status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    /// A pipe whose ends close themselves in any child.
    static func makePipe() -> (read: Int32, write: Int32)? {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return nil }
        for fd in fds { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        return (fds[0], fds[1])
    }

    /// Writes `data` to `fd` on its own thread, then closes it. A child that quits early is not an error.
    static func feed(_ data: Data, to fd: Int32) {
        _ = fcntl(fd, F_SETNOSIGPIPE, 1)
        DispatchQueue.global().async {
            data.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                    if n > 0 { offset += n } else if n < 0 && errno == EINTR { continue } else { break }
                }
            }
            close(fd)
        }
    }

    /// Starts a program with only the descriptors named in `stdio` (0, 1, 2) open.
    /// Ctrl-C and broken-pipe handling are set back to the defaults, and no signals are blocked.
    static func spawn(path: String, argv: [String], environment: [String: String],
                      stdio: [Stdio], ownProcessGroup: Bool) -> Result<pid_t, Spawn.Failure> {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for (target, spec) in stdio.enumerated() {
            let t = Int32(target)
            switch spec {
            case .inherit: posix_spawn_file_actions_addinherit_np(&actions, t)
            case .devNull: posix_spawn_file_actions_addopen(&actions, t, "/dev/null", O_RDONLY, 0)
            case .fd(let source): posix_spawn_file_actions_adddup2(&actions, source, t)
            }
        }

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGINT)
        sigaddset(&defaults, SIGPIPE)
        posix_spawnattr_setsigdefault(&attr, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attr, &mask)
        var flags = POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        if ownProcessGroup {
            posix_spawnattr_setpgroup(&attr, 0)
            flags |= POSIX_SPAWN_SETPGROUP
        }
        posix_spawnattr_setflags(&attr, Int16(flags))

        var cArgv: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        var cEnv: [UnsafeMutablePointer<CChar>?] = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            cArgv.forEach { free($0) }
            cEnv.forEach { free($0) }
        }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, path, &actions, &attr, &cArgv, &cEnv)
        return rc == 0 ? .success(pid) : .failure(Failure(code: rc))
    }
}
