// Debug builds only, like `SampleMenu` and `SampleWindow`. A release build has none of this, and
// `scripts/build-app.sh` checks that the release app does not even contain the sample variable's name.
#if DEBUG
import Foundation
import os

/// The `window-forms` sample (main window design, section 8, step 4): the workhorse Attic, Ready, with no
/// projects folder saved, whose desks change as the window's New desk, Rename and Remove act on them, and whose
/// windows' names change as the window names them (issue 144). No
/// ssh runs: `SampleSSH` stands in for it, writes the exact arguments to the log, and answers as the workhorse
/// script would. Every name in here is made up.
public enum SampleForms {
    static let attic = Workhorse(id: "attic", name: "Attic", user: "alex", mainAddress: "attic",
                                 hostKey: "ssh-ed25519 SAMPLE-KEY-NOT-REAL", paired: true, osVersion: "26.1", arch: "arm64")
    /// Where the check says the workhorse answered, so the log shows the actions go there.
    static let answeredAt = "192.168.1.20"
    /// The folders in the projects folder, as the script lists them.
    static let folders = ["api", "blog", "garden-planner", "recipes", "website"]
    /// How long a sample check and a sample New desk take, so a picture can catch "Updating…" and "Making…". A
    /// check is shorter than the second between two of them (`SampleMenu.lookEvery`): longer, and the next one
    /// would be asked for while it runs, every time, so the refresh that runs them would never end.
    static let checkTakes: Duration = .milliseconds(800)
    static let makingTakes: Duration = .seconds(2)

    /// The sample's own folder, under the temporary folder: its saved list, and a stand-in key file (made-up
    /// text, not a key) so that `HostCommands` finds a usable key. Never the real support folder or `~/.ssh`.
    public static let paths: Paths = {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macmosh-sample-forms-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        let paths = Paths(supportDir: root.appendingPathComponent("support", isDirectory: true),
                          sshDir: root.appendingPathComponent("ssh", isDirectory: true))
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: paths.sshDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let key = paths.defaultIdentity
            try Data("stand-in for the window-forms sample, not a key\n".utf8).write(to: key)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
            try WorkhorseStore(paths: paths).save([attic])
        } catch {
            MenuLog.write("sample: the forms sample's folder was not made")
        }
        return paths
    }()

    static let desks = SampleDesks()

    /// The real refresher, reading the sample's saved list (so a saved projects folder shows), with checks that
    /// find Attic Ready with the desks as they are now.
    @MainActor static func refresher() -> MenuRefresher {
        let store = WorkhorseStore(paths: paths)
        return MenuRefresher(
            load: { try store.load() },
            gather: { list in
                try? await Task.sleep(for: checkTakes)
                return list.map { .checked(result($0)) }
            },
            save: { _ in })
    }

    static func result(_ w: Workhorse) -> CheckResult {
        CheckResult(workhorse: w, state: .ready(signIns: true), status: try? HostStatus.parse(desks.report()),
                    probes: ProbeSet(), answeredAt: answeredAt, homeReachable: true, checkedAt: Date())
    }
}

/// The sample's desks, which the stand-in ssh changes as the script would.
final class SampleDesks: @unchecked Sendable {
    /// One tmux window: its id, its name, and the program running in it, which `--auto` names it after.
    struct Window {
        var id: String
        var name: String
        var program: String
    }

    struct Desk {
        var name: String
        var windows: [Window]
        var folder: String
        var command: String
        var permanent: Bool
        var isOpen: Bool
        var reopen = true
        var keep = false
    }

    static func windows(_ first: Int, _ programs: [String]) -> [Window] {
        programs.enumerated().map { Window(id: "@\(first + $0.offset)", name: $0.element, program: $0.element) }
    }

    private let lock = NSLock()
    private var nextWindow: Int
    private var all: [Desk]

    /// The `window-forms` desks, or `desks` with new windows numbered from `nextWindow`.
    init(_ desks: [Desk]? = nil, nextWindow: Int = 7) {
        all = desks ?? Self.forms
        self.nextWindow = nextWindow
    }

    private static let forms: [Desk] = [
        Desk(name: "api", windows: windows(1, ["server", "tests"]), folder: "/Users/alex/Development/api", command: "",
             permanent: false, isOpen: true),
        Desk(name: "blog", windows: windows(3, ["zsh"]), folder: "/Users/alex/Development/blog", command: "", permanent: false,
             isOpen: true),
        Desk(name: "website", windows: windows(4, ["claude", "zsh", "vim"]), folder: "/Users/alex/Development/website",
             command: "claude --continue", permanent: false, isOpen: true),
        Desk(name: "notes", windows: [], folder: "/Users/alex/notes", command: "", permanent: true, isOpen: false),
    ]

    /// A workhorse script 0.11.0 report of the desks as they are now, with each window's id (`windowinfo`: the
    /// desk, the window's number, its id, 1 for the one the desk shows, and its tabs). The `def` fields are the
    /// name, reopen, keep, permanent, the folder and the command.
    func report() -> String {
        lock.withLock {
            var lines = ["macmosh-host\t1\t0.11.0", "os\t26.1\tarm64", "console\talex", "server\tup", "signins\tok",
                         "agent\tinstalled", "power\tsleep=0\twomp=1", "battery\tpresent\tac\t82"]
            for d in all where d.isOpen {
                lines.append("desk\t\(d.name)\t\(d.windows.count)\t0")
                lines += d.windows.enumerated().map { "window\t\(d.name)\t\($0.offset)\t\($0.element.name)" }
                lines += d.windows.enumerated().map {
                    "windowinfo\t\(d.name)\t\($0.offset)\t\($0.element.id)\t\($0.offset == 0 ? 1 : 0)\t0"
                }
            }
            lines += all.map {
                "def\t\($0.name)\t\($0.reopen ? 1 : 0)\t\($0.keep ? 1 : 0)\t\($0.permanent ? 1 : 0)\t\($0.folder)\t\($0.command)"
            }
            return (lines + ["end"]).joined(separator: "\n") + "\n"
        }
    }

    /// The last shell of each of these desks exits: each closes. Its definition stays, as the script's does for the
    /// minute before it removes one that is not permanent.
    func endShells(_ names: Set<String>) {
        lock.withLock {
            for i in all.indices where names.contains(all[i].name) {
                all[i].isOpen = false
                all[i].windows = []
            }
        }
    }

    /// A permanent desk with that name, closed, made elsewhere: it takes the name by the script's rule.
    func holdAsPermanent(_ name: String) {
        lock.withLock {
            for i in all.indices where all[i].name == name {
                all[i].permanent = true
                all[i].isOpen = false
                all[i].windows = []
            }
        }
    }

    /// The script's rule: an open desk, or a permanent one.
    private func taken(_ name: String) -> Bool {
        all.contains { $0.name == name && ($0.isOpen || $0.permanent) }
    }

    /// What the script's `desk-new`, `desk-rename`, `desk-remove` and `window-name` do, by exit code (0, 2, 4 or 7).
    func run(_ args: [String]) -> (Int32, String) {
        lock.withLock {
            guard let command = args.first else { return (2, "") }
            switch command {
            case "desk-new" where args.count >= 3:
                let name = args[1]
                if taken(name) { return (7, "macmosh-host: the desk \(name) already exists\n") }
                all.removeAll { $0.name == name }
                let started = args.firstIndex(of: "--command").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? ""
                let first = started.split(separator: " ").first.map(String.init) ?? "zsh"
                let home = "/Users/alex"
                let folder = args[2].hasPrefix("~/") ? home + args[2].dropFirst(1) : args[2]
                all.append(Desk(name: name, windows: [Window(id: "@\(nextWindow)", name: first, program: first)], folder: folder,
                                command: started, permanent: args.contains("--permanent"), isOpen: true,
                                reopen: !args.contains("--no-reopen"), keep: args.contains("--keep")))
                nextWindow += 1
                return (0, "")
            case "desk-rename" where args.count == 3:
                guard let i = all.firstIndex(where: { $0.name == args[1] }) else { return (4, "macmosh-host: no such desk: \(args[1])\n") }
                if taken(args[2]) { return (7, "macmosh-host: the desk \(args[2]) already exists\n") }
                all[i].name = args[2]
                return (0, "")
            case "window-name" where args.count == 4:
                let wanted = args[3]
                if wanted != "--auto", !WindowName.keepsScriptRule(wanted) {
                    return (2, "macmosh-host: a window name is 1 to 32 characters, each a letter, a digit, a space, -, _ or a full stop, and it can't start or end with a space\n")
                }
                guard let d = all.firstIndex(where: { $0.name == args[1] && $0.isOpen }) else {
                    return (4, "macmosh-host: no such desk: \(args[1])\n")
                }
                guard let w = all[d].windows.firstIndex(where: { $0.id == args[2] }) else { return (4, "That window has closed.\n") }
                all[d].windows[w].name = wanted == "--auto" ? all[d].windows[w].program : wanted
                return (0, "")
            case "desk-remove" where args.count >= 2:
                guard all.contains(where: { $0.name == args[1] }) else { return (4, "macmosh-host: no such desk: \(args[1])\n") }
                all.removeAll { $0.name == args[1] }
                return (0, "")
            default:
                return (0, "")
            }
        }
    }
}

/// Stands in for ssh in the `window-forms` sample. Writes one line per call with the exact arguments that
/// matter (`sample ssh: to=alex@192.168.1.20 batch=yes stdin=closed limit=15s run=<the remote command>`), then
/// answers as the workhorse script would. Runs nothing.
struct SampleSSH: CommandRunner {
    /// The desks it changes: the `window-forms` sample's, or another sample's (`SampleEnded`).
    var desks: SampleDesks = SampleForms.desks

    func run(_ executable: String, _ arguments: [String], environment: [String: String],
             stdin: Data?, timeout: Duration) async -> CommandResult {
        let argv = [executable] + arguments
        let dash = argv.firstIndex(of: "--")
        let to = dash.flatMap { $0 + 1 < argv.count ? argv[$0 + 1] : nil } ?? "?"
        let remote = argv.last ?? ""
        MenuLog.write(Self.line(argv: argv, to: to, stdin: stdin, timeout: timeout, remote: remote))
        let args = Self.split(remote).dropFirst()   // the script's path first
        if args.first == "folders" {
            return CommandResult(exitCode: 0, stdout: SampleForms.folders.joined(separator: "\n") + "\n", stderr: "", timedOut: false)
        }
        if args.first == "desk-new" { try? await Task.sleep(for: SampleForms.makingTakes) }
        let (code, stderr) = desks.run(Array(args))
        return CommandResult(exitCode: code, stdout: "", stderr: stderr, timedOut: false)
    }

    static func line(argv: [String], to: String, stdin: Data?, timeout: Duration, remote: String) -> String {
        let batch = argv.contains("BatchMode=yes") ? "yes" : "no"
        return "sample ssh: to=\(to) batch=\(batch) stdin=\(stdin == nil ? "closed" : "open") "
            + "limit=\(timeout.components.seconds)s run=\(remote)"
    }

    /// Splits a command line the way a POSIX shell reads `ShellQuote.join`'s output: words apart at spaces,
    /// single quotes kept together, and `\` taking the next character as it is.
    static func split(_ line: String) -> [String] {
        var words: [String] = []
        var word = ""
        var inWord = false
        var quoted = false
        var escaped = false
        for c in line {
            if escaped {
                word.append(c)
                escaped = false
            } else if quoted {
                if c == "'" { quoted = false } else { word.append(c) }
            } else if c == "'" {
                quoted = true
                inWord = true
            } else if c == "\\" {
                escaped = true
                inWord = true
            } else if c == " " {
                if inWord { words.append(word) }
                word = ""
                inWord = false
            } else {
                word.append(c)
                inWord = true
            }
        }
        if inWord { words.append(word) }
        return words
    }
}
#endif
