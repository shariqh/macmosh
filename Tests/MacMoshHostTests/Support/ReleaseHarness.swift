import Foundation
import Testing

/// Runs a copy of `scripts/release.sh` in a throwaway repository, with stand-in tools first on `PATH` (issue #36).
///
/// Safety rules, kept in one place:
/// - `PATH` is `<root>/stubs:/usr/bin:/bin:/usr/sbin:/sbin`, and every tool that could sign, reach Apple, read the
///   keychain or publish (`codesign`, `xcrun`, `spctl`, `gh`, `security`) is a stand-in there; `git`, `ditto` and
///   `lipo` are stand-ins too, so each call is written to `calls.log`;
/// - `HOME` and `TMPDIR` are inside the harness folder, so the Trash and the `mktemp` folder are too;
/// - `GIT_CONFIG_NOSYSTEM=1` and `GIT_CONFIG_GLOBAL=/dev/null`, and the repository's `origin` is a bare repository
///   in the harness folder, so nothing reaches a real remote;
/// - `MACMOSH_SIGN_IDENTITY` and `MACMOSH_NOTARY_PROFILE` are made-up values that override the person's own;
/// - `run` executes only `<root>/repo/scripts/release.sh`, never the real checkout's script.
final class ReleaseHarness {
    /// `<temporaryDirectory>/macmosh-release-test-<8 hex>`.
    let root: URL
    /// The throwaway checkout; release.sh runs here.
    var repo: URL { root.appendingPathComponent("repo") }
    /// `HOME`, so the Trash is `root/home/.Trash`.
    var home: URL { root.appendingPathComponent("home") }
    /// One line per stand-in call, `<tool> <arguments>`, from `root/calls.log`.
    var calls: [String] {
        let text = (try? String(contentsOf: root.appendingPathComponent("calls.log"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    private var baseEnvironment: [String: String]

    init() throws {
        let hex = (0..<4).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("macmosh-release-test-" + hex)
        var env = ProcessInfo.processInfo.environment
        for name in env.keys where name.hasPrefix("MACMOSH_") || name.hasPrefix("STANDIN_") || name.hasPrefix("GIT_") {
            env.removeValue(forKey: name)
        }
        env["PATH"] = root.appendingPathComponent("stubs").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOME"] = root.appendingPathComponent("home").path
        env["TMPDIR"] = root.appendingPathComponent("tmp").path
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        for name in ["GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL"] {
            env[name] = "alex"
        }
        env["MACMOSH_SIGN_IDENTITY"] = "Stand-in Signer (TEAM000000)"
        env["MACMOSH_NOTARY_PROFILE"] = "stand-in-profile"
        env["STANDIN_LOG"] = root.appendingPathComponent("calls.log").path
        baseEnvironment = env

        do { try setUp() } catch {
            cleanUp()   // a half-made harness leaves nothing behind
            throw error
        }
    }

    private func setUp() throws {
        let files = FileManager.default
        for folder in ["stubs", "home", "tmp", "repo/scripts", "repo/Sources/MacMoshKit", "repo/App"] {
            try files.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        for (tool, body) in Self.stubs {
            try Self.write(body, to: root.appendingPathComponent("stubs/\(tool)"), executable: true)
        }

        // The throwaway checkout: a copy of the real script, a stand-in build script, the version line and the
        // entitlements, committed as alex and pushed to a bare origin beside it.
        let real = HostHarness.repoRoot()
        try files.copyItem(at: real.appendingPathComponent("scripts/release.sh"),
                           to: repo.appendingPathComponent("scripts/release.sh"))
        try Self.write(Self.buildStandIn, to: repo.appendingPathComponent("scripts/build-app.sh"), executable: true)
        try Self.write("    public static let version = \"0.1.0\"\n",
                       to: repo.appendingPathComponent("Sources/MacMoshKit/MacMoshKit.swift"), executable: false)
        try files.copyItem(at: real.appendingPathComponent("App/MacMosh.entitlements"),
                           to: repo.appendingPathComponent("App/MacMosh.entitlements"))
        try Self.write("dist/\n", to: repo.appendingPathComponent(".gitignore"), executable: false)

        let origin = root.appendingPathComponent("origin.git")
        for (arguments, folder) in [(["init", "--bare", "-q", "-b", "main", origin.path], root),
                                    (["init", "-q", "-b", "main"], repo), (["add", "-A"], repo),
                                    (["commit", "-q", "-m", "the throwaway checkout"], repo),
                                    (["remote", "add", "origin", origin.path], repo),
                                    (["push", "-q", "origin", "main"], repo)] {
            let out = git(arguments, in: folder)
            guard out.exitCode == 0 else { throw ReleaseHarnessError.setUp("git \(arguments.joined(separator: " ")) failed") }
        }
    }

    /// Runs `root/repo/scripts/release.sh` in `root/repo`. `fault` sets `STANDIN_FAULT`; a nil value in
    /// `environment` unsets that variable.
    func run(_ arguments: [String], fault: String? = nil, environment: [String: String?] = [:])
        -> (exitCode: Int32, stdout: String, stderr: String) {
        let script = repo.appendingPathComponent("scripts/release.sh")
        let rootPath = root.standardizedFileURL.path + "/"
        guard FileManager.default.isExecutableFile(atPath: script.path),
              script.standardizedFileURL.path.hasPrefix(rootPath) else {
            Issue.record("the copy of release.sh is missing or outside the harness folder: \(script.path)")
            return (-1, "", "")
        }
        var env = baseEnvironment
        if let fault { env["STANDIN_FAULT"] = fault }
        for (name, value) in environment { env[name] = value }
        return execute(script.path, arguments, in: repo, environment: env)
    }

    /// The real git, not the stand-in, so the harness's own calls stay out of `calls`.
    func git(_ arguments: [String], in folder: URL? = nil) -> (exitCode: Int32, stdout: String) {
        let out = execute("/usr/bin/git", arguments, in: folder ?? repo, environment: baseEnvironment)
        return (out.exitCode, out.stdout)
    }

    func cleanUp() {
        guard root.lastPathComponent.hasPrefix("macmosh-release-test-") else { return }
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Process plumbing

    private func execute(_ executable: String, _ arguments: [String], in folder: URL, environment: [String: String])
        -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = folder

        // Output goes to files outside the checkout, so `git status` never sees them.
        let outURL = root.appendingPathComponent(".out-" + UUID().uuidString)
        let errURL = root.appendingPathComponent(".err-" + UUID().uuidString)
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }
        guard let outHandle = try? FileHandle(forWritingTo: outURL),
              let errHandle = try? FileHandle(forWritingTo: errURL) else {
            return (-1, "", "harness: cannot open output files")
        }
        process.standardOutput = outHandle
        process.standardError = errHandle
        process.standardInput = FileHandle.nullDevice

        do { try process.run() } catch {
            return (-1, "", "harness: \(error)")
        }
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                Issue.record("\(URL(fileURLWithPath: executable).lastPathComponent) ran past 60 seconds")
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        process.waitUntilExit()
        try? outHandle.close()
        try? errHandle.close()
        let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }

    private static func write(_ text: String, to url: URL, executable: Bool) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    // MARK: - The stand-ins

    /// Every stand-in first writes `<name> <arguments>` to `$STANDIN_LOG`. A "copy" path is one that does not start
    /// with `dist/`: the folder release.sh unpacks the download zip into.
    private static let stubs: [(String, String)] = [
        ("codesign", #"""
            #!/bin/bash
            echo "codesign $*" >> "$STANDIN_LOG"
            fault=${STANDIN_FAULT:-}
            for word in "$@"; do
                case "$word" in --sign|--sign=*|-s) exit 97 ;; esac
            done
            for path in "$@"; do :; done
            case "${1:-}" in
                --verify)
                    if [ "$fault" = verify-fails ]; then
                        echo "$path: a sealed resource is missing or invalid" >&2
                        exit 1
                    fi
                    echo "$path: valid on disk" >&2
                    exit 0
                    ;;
                --display) ;;
                *) exit 97 ;;
            esac
            case " $* " in
                *" --entitlements - --xml "*)
                    case "$path" in
                        */Contents/Helpers/macmosh) ;;
                        *)
                            if [ "$fault" = extra-entitlement ]; then
                                printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
                                    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
                                    '<plist version="1.0"><dict>' \
                                    '<key>com.apple.security.automation.apple-events</key><true/>' \
                                    '<key>com.apple.security.get-task-allow</key><true/>' \
                                    '</dict></plist>'
                                exit 0
                            fi
                            ;;
                    esac
                    cat App/MacMosh.entitlements
                    exit 0
                    ;;
                *" --verbose=2 "*)
                    flags="0x10000(runtime)"
                    [ "$fault" = no-runtime ] && flags="0x0(none)"
                    stamp="Timestamp=Nov 26, 2026 at 09:00:00"
                    [ "$fault" = no-timestamp ] && stamp="Signed Time=Nov 26, 2026 at 09:00:00"
                    case "$path" in
                        */Contents/Helpers/macmosh)
                            [ "$fault" = helper-no-timestamp ] && stamp="Signed Time=Nov 26, 2026 at 09:00:00" ;;
                    esac
                    {
                        echo "Executable=$path"
                        echo "Authority=$MACMOSH_SIGN_IDENTITY"
                        echo "CodeDirectory v=20500 size=100 flags=$flags hashes=1+7 location=embedded"
                        echo "$stamp"
                    } >&2
                    exit 0
                    ;;
            esac
            exit 97
            """#),
        ("lipo", #"""
            #!/bin/bash
            echo "lipo $*" >> "$STANDIN_LOG"
            [ "${1:-}" = -archs ] || exit 97
            case "${2:-}" in
                */Contents/MacOS/MacMosh)
                    if [ "${STANDIN_FAULT:-}" = intel ]; then
                        echo "x86_64 arm64"
                        exit 0
                    fi
                    ;;
            esac
            echo arm64
            """#),
        ("ditto", #"""
            #!/bin/bash
            echo "ditto $*" >> "$STANDIN_LOG"
            exec /usr/bin/ditto "$@"
            """#),
        ("xcrun", #"""
            #!/bin/bash
            echo "xcrun $*" >> "$STANDIN_LOG"
            fault=${STANDIN_FAULT:-}
            id=2efe2717-0000-4000-8000-000000000036
            for last in "$@"; do :; done
            case "${1:-} ${2:-}" in
                "notarytool submit")
                    if [ "$fault" = notary-upload-fails ]; then
                        echo "Error: stand-in upload failure" >&2
                        exit 1
                    fi
                    echo "Conducting pre-submission checks for for-notary.zip and initiating connection to the Apple notary service..."
                    echo "Submission ID received"
                    echo "  id: $id"
                    echo "Successfully uploaded file."
                    echo "  id: $id"
                    echo "  path: $3"
                    echo "Waiting for processing to complete."
                    [ "$fault" = notary-unfinished ] && exit 1
                    status=Accepted
                    [ "$fault" = notary-invalid ] && status=Invalid
                    echo "Processing complete"
                    echo "  createdDate: 2026-11-26T09:00:00.000Z"
                    echo "  id: $id"
                    echo "  name: for-notary.zip"
                    echo "  status: $status"
                    exit 0
                    ;;
                "notarytool log")
                    if [ "$fault" = notary-invalid ]; then
                        echo '{"status":"Invalid","issues":[{"severity":"error","path":"MacMosh.app/Contents/MacOS/MacMosh","message":"The signature does not include a secure timestamp."}]}' > "$last"
                    else
                        echo '{"status":"Accepted","issues":[{"severity":"warning","path":"MacMosh.app/Contents/Helpers/macmosh","message":"stand-in warning"}]}' > "$last"
                    fi
                    exit 0
                    ;;
                "stapler staple")
                    [ "$fault" = staple-fails ] && exit 65
                    touch "$last/Contents/stand-in-ticket"
                    exit 0
                    ;;
                "stapler validate")
                    [ -f "$last/Contents/stand-in-ticket" ] || exit 65
                    exit 0
                    ;;
            esac
            exit 97
            """#),
        ("spctl", #"""
            #!/bin/bash
            echo "spctl $*" >> "$STANDIN_LOG"
            [ "${1:-}" = --assess ] || exit 97
            for path in "$@"; do :; done
            reject=0
            [ "${STANDIN_FAULT:-}" = gatekeeper-rejects ] && reject=1
            if [ "${STANDIN_FAULT:-}" = copy-gatekeeper-rejects ]; then
                case "$path" in dist/*) ;; *) reject=1 ;; esac
            fi
            if [ "$reject" -eq 1 ]; then
                echo "$path: rejected" >&2
                echo "source=Unnotarized Developer ID" >&2
                exit 3
            fi
            echo "$path: accepted" >&2
            echo "source=Notarized Developer ID" >&2
            exit 0
            """#),
        ("git", #"""
            #!/bin/bash
            echo "git $*" >> "$STANDIN_LOG"
            if [ "${STANDIN_FAULT:-}" = ls-remote-fails ] && [ "${1:-}" = ls-remote ]; then
                exit 128
            fi
            exec /usr/bin/git "$@"
            """#),
        ("gh", #"""
            #!/bin/bash
            echo "gh $*" >> "$STANDIN_LOG"
            exit 97
            """#),
        ("security", #"""
            #!/bin/bash
            echo "security $*" >> "$STANDIN_LOG"
            exit 97
            """#),
    ]

    /// The stand-in for scripts/build-app.sh: it needs `--into F` and makes a two-program app in it.
    private static let buildStandIn = #"""
        #!/bin/bash
        echo "build-app.sh $*" >> "$STANDIN_LOG"
        into=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --into)
                    into=${2:-}
                    shift
                    ;;
            esac
            shift
        done
        if [ -z "$into" ]; then
            echo "stand-in build-app.sh: needs --into" >&2
            exit 2
        fi
        app="$into/MacMosh.app"
        mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers"
        echo "stand-in app" > "$app/Contents/MacOS/MacMosh"
        echo "stand-in command" > "$app/Contents/Helpers/macmosh"
        version=0.1.0
        case "${STANDIN_FAULT:-}" in
            home-path) echo "/Users/sample/x" >> "$app/Contents/Helpers/macmosh" ;;
            sample-menu) echo "MACMOSH_SAMPLE_MENU" >> "$app/Contents/MacOS/MacMosh" ;;
            wrong-version) version=0.0.9 ;;
        esac
        printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
            '<plist version="1.0"><dict>' \
            "<key>CFBundleShortVersionString</key><string>$version</string>" \
            '</dict></plist>' > "$app/Contents/Info.plist"
        echo "build-app.sh: built $app (stand-in)"
        """#
}

enum ReleaseHarnessError: Error {
    case setUp(String)
}
