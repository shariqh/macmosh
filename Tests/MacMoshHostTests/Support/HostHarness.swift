import Foundation

/// Runs `host/macmosh-host` against a throwaway tmux socket and a temporary HOME.
///
/// Safety rules, kept in one place:
/// - the socket name always starts with `macmosh-test-`, and `init` fails otherwise;
/// - `TMUX`, `TMUX_PANE`, `XDG_CONFIG_HOME` and `MACMOSH_HOME` are removed from the environment;
/// - `launchctl` and `stat` are stand-ins from the start, so nothing reaches the real ones.
final class HostHarness {
    struct Output {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    let home: URL
    let socket: String

    /// The folder holding the stand-in tools; it comes first on `PATH`.
    var stubFolder: URL { home.appendingPathComponent("stubs") }

    private var baseEnvironment: [String: String]

    init() throws {
        let hex = (0..<4).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        socket = "macmosh-test-" + hex
        guard socket.hasPrefix("macmosh-test-") else { throw HarnessError.badSocketName(socket) }

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("macmosh-host-test-" + hex)
        home = base
        try FileManager.default.createDirectory(at: base.appendingPathComponent("stubs"),
                                                withIntermediateDirectories: true)

        var env = ProcessInfo.processInfo.environment
        for name in ["TMUX", "TMUX_PANE", "XDG_CONFIG_HOME", "MACMOSH_HOME", "TMUX_TMPDIR"] {
            env.removeValue(forKey: name)
        }
        env["HOME"] = base.path
        env["MACMOSH_SOCKET"] = socket
        let inherited = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = base.appendingPathComponent("stubs").path + ":" + inherited
        baseEnvironment = env

        try stub("launchctl", script: """
            echo "$*" >> "$HOME/launchctl.log"
            exit 1
            """)
        try stub("stat", script: """
            if [ "$1" = "-f" ] && [ "$2" = "%Su" ] && [ "$3" = "/dev/console" ]; then
                echo tester
                exit 0
            fi
            exec /usr/bin/stat "$@"
            """)
    }

    /// Sets one variable for every later call. Set it before `start`: the desk server hands its
    /// environment to the shells inside the desks.
    func setEnvironment(_ name: String, _ value: String) {
        baseEnvironment[name] = value
    }

    var scriptURL: URL { Self.repoRoot().appendingPathComponent("host/macmosh-host") }

    /// The `MACMOSH_HOST_VERSION=` line of the script.
    var scriptVersion: String {
        let text = (try? String(contentsOf: scriptURL, encoding: .utf8)) ?? ""
        for line in text.split(separator: "\n") where line.hasPrefix("MACMOSH_HOST_VERSION=") {
            return String(line.dropFirst("MACMOSH_HOST_VERSION=".count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return ""
    }

    /// An executable stand-in placed first on `PATH`. `script` is the body; a `#!/bin/bash` line is added.
    func stub(_ tool: String, script: String) throws {
        let url = stubFolder.appendingPathComponent(tool)
        let body = script.hasPrefix("#!") ? script : "#!/bin/bash\n" + script
        try (body.hasSuffix("\n") ? body : body + "\n").write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func run(_ arguments: [String], stdin: String? = nil) -> (exitCode: Int32, stdout: String, stderr: String) {
        let out = execute(scriptURL.path, arguments, stdin: stdin)
        return (out.exitCode, out.stdout, out.stderr)
    }

    /// Runs tmux, always with `-L <socket>`.
    func tmux(_ arguments: [String]) -> (exitCode: Int32, stdout: String) {
        let out = execute("/usr/bin/env", ["tmux", "-L", socket] + arguments, stdin: nil)
        return (out.exitCode, out.stdout)
    }

    /// Copies the script to `<home>/.macmosh/macmosh-host`.
    func installScriptInHome() throws {
        let folder = home.appendingPathComponent(".macmosh")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent("macmosh-host")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: scriptURL, to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
    }

    /// `/bin/sh -c`, with the same environment as `run`.
    func shell(_ commandLine: String) -> (exitCode: Int32, stdout: String, stderr: String) {
        let out = execute("/bin/sh", ["-c", commandLine], stdin: nil)
        return (out.exitCode, out.stdout, out.stderr)
    }

    /// Stops the throwaway tmux server and removes the temporary folder.
    func cleanUp() {
        guard socket.hasPrefix("macmosh-test-") else { return }
        _ = tmux(["kill-server"])
        // tmux leaves its socket file behind after kill-server; this one is ours, so remove it.
        let uid = getuid()
        let socketFile = "/private/tmp/tmux-\(uid)/\(socket)"
        let plain = "/tmp/tmux-\(uid)/\(socket)"
        for path in [socketFile, plain] where FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: - Process plumbing

    private func execute(_ executable: String, _ arguments: [String], stdin: String?) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = baseEnvironment
        process.currentDirectoryURL = home

        // Output goes to files, not pipes: a tmux server that outlives the script would keep a pipe open.
        let outURL = home.appendingPathComponent(".out-" + UUID().uuidString)
        let errURL = home.appendingPathComponent(".err-" + UUID().uuidString)
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }
        guard let outHandle = try? FileHandle(forWritingTo: outURL),
              let errHandle = try? FileHandle(forWritingTo: errURL) else {
            return Output(exitCode: -1, stdout: "", stderr: "harness: cannot open output files")
        }
        process.standardOutput = outHandle
        process.standardError = errHandle

        let inPipe = Pipe()
        process.standardInput = inPipe

        do { try process.run() } catch {
            return Output(exitCode: -1, stdout: "", stderr: "harness: \(error)")
        }
        if let stdin, let data = stdin.data(using: .utf8) {
            try? inPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try? inPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(60)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        try? outHandle.close()
        try? errHandle.close()

        let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        return Output(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    static func repoRoot() -> URL {
        let file = #filePath
        // <root>/Tests/MacMoshHostTests/Support/HostHarness.swift
        return URL(fileURLWithPath: file)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }
}

enum HarnessError: Error {
    case badSocketName(String)
    case timedOut
}

/// Checks `condition` every tenth of a second; throws when `seconds` run out.
func waitFor(seconds: Double, _ condition: () -> Bool) throws {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return }
        Thread.sleep(forTimeInterval: 0.1)
    }
    if condition() { return }
    throw HarnessError.timedOut
}
