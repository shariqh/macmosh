import Foundation

/// What `macmosh connect` will run: the command line, the environment to add, whether a dropped
/// connection is tried again, and the sentence said before it starts.
public struct ConnectPlan: Sendable, Equatable {
    public var argv: [String]
    public var environment: [String: String]
    public var retryOnDrop: Bool
    public var intro: String

    public init(argv: [String], environment: [String: String], retryOnDrop: Bool, intro: String) {
        self.argv = argv
        self.environment = environment
        self.retryOnDrop = retryOnDrop
        self.intro = intro
    }
}

/// The three ways to open a desk (design 5.4). The mosh line and the retry loop are the ones run on
/// real Macs in sitting 1 (items 3 and 4); change them only with the same test.
///
/// No mode ever asks for a password: every ssh carries `SSHInvocation.noPasswordOptions`, so a refused
/// key ends the tab with the reason.
public enum ConnectPlanner {
    /// One week, as design 8.1 says, so a mosh-server whose client never returns cleans itself up.
    static let moshServerTimeout = "604800"
    /// Without these ssh can sit for minutes on a dead network, and the retry loop never gets its turn.
    static let keepAliveOptions = ["-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=2"]

    /// `path` is this Mac's `PATH`, for putting mosh's folder on it when it is missing: mosh is a script that
    /// starts `mosh-client` by name. It defaults to the running program's own.
    ///
    /// `tab`, for a tab opened with a window option, puts `--label <word>` and that option before the desk's
    /// name (menu design 8.3). Without it the lines are exactly as before. `connect` never asks for it in
    /// Tabs mode.
    public static func plan(workhorse w: Workhorse, desk: DeskName, mode: ConnectionMode, address: String,
                            paths: Paths, moshPath: String, localeEnvironment: [String: String],
                            path: String? = ProcessInfo.processInfo.environment["PATH"],
                            tab: TabRequest? = nil) -> ConnectPlan {
        switch mode {
        case .mosh:
            return mosh(w, desk: desk, address: address, paths: paths, moshPath: moshPath,
                        localeEnvironment: localeEnvironment, path: path, tab: tab)
        case .tabs:
            return ssh(w, desk: desk, address: address, paths: paths, control: true, tab: tab,
                       intro: "Opening \"\(desk.value)\" on \(w.name) as iTerm2 tabs. If the connection drops, the tabs close and this tab keeps trying.")
        case .ssh:
            return ssh(w, desk: desk, address: address, paths: paths, control: false, tab: tab,
                       intro: "Opening \"\(desk.value)\" on \(w.name) over plain ssh. If the connection drops, this tab ends; your work keeps running.")
        }
    }

    // MARK: - The three lines

    /// The line from sitting 1: mosh with the pinned-key ssh, the one-week timeout and the script's
    /// `attach`. The desk name is passed as `$1`, never pasted into the remote shell's text. With `tab`, the
    /// label, the option and the desk name are passed as `"$@"`, each its own argument.
    private static func mosh(_ w: Workhorse, desk: DeskName, address: String, paths: Paths, moshPath: String,
                             localeEnvironment: [String: String], path: String?, tab: TabRequest?) -> ConnectPlan {
        let remote: [String]
        if let tab {
            remote = ["/bin/sh", "-c", "exec \"$HOME/.macmosh/macmosh-host\" attach \"$@\"", "macmosh-host"]
                + tab.attachArguments + [desk.value]
        } else {
            remote = ["/bin/sh", "-c", "exec \"$HOME/.macmosh/macmosh-host\" attach \"$1\"", "macmosh-host", desk.value]
        }
        let argv = [
            moshPath,
            "--predict=\(w.prediction.rawValue)",
            "--ssh=\(SSHInvocation.sshStringForMosh(for: w, paths: paths))",
            "--server=MOSH_SERVER_NETWORK_TMOUT=\(moshServerTimeout) PATH=\"$PATH:/opt/homebrew/bin:/usr/local/bin\" mosh-server",
            "\(w.user)@\(address)",
            "--",
        ] + remote
        // The workhorse script's title is the window's or the desk's name alone (issue 162); mosh's client
        // puts "[mosh] " in front of it unless this is set (man mosh 1.4.0, MOSH_TITLE_NOPREFIX).
        var environment: [String: String] = ["MOSH_TITLE_NOPREFIX": "1"]
        if let withMosh = pathWithFolderOf(moshPath, in: path) { environment["PATH"] = withMosh }
        if let name = localeVariableToSet(localeEnvironment) { environment[name] = "en_US.UTF-8" }
        return ConnectPlan(argv: argv, environment: environment, retryOnDrop: false,
                           intro: "Opening \"\(desk.value)\" on \(w.name) over mosh. If the network drops, this tab picks up by itself.")
    }

    /// Tabs (`--cc`, iTerm2's control mode, with the retry loop) and plain ssh share one shape.
    private static func ssh(_ w: Workhorse, desk: DeskName, address: String, paths: Paths, control: Bool,
                            tab: TabRequest?, intro: String) -> ConnectPlan {
        let attach = (control ? ["attach", "--cc"] : ["attach"]) + (tab?.attachArguments ?? []) + [desk.value]
        let argv = SSHInvocation.argv(for: w, address: address, paths: paths, batch: false, tty: true,
                                      extraOptions: SSHInvocation.noPasswordOptions + keepAliveOptions,
                                      remote: SSHInvocation.hostCommand(attach))
        return ConnectPlan(argv: argv, environment: [:], retryOnDrop: control, intro: intro)
    }

    // MARK: - Pieces

    /// `PATH` with the folder of `tool` in front, or nil when that folder is already on it.
    static func pathWithFolderOf(_ tool: String, in path: String?) -> String? {
        let folder = (tool as NSString).deletingLastPathComponent
        guard !folder.isEmpty else { return nil }
        let current = (path ?? "").split(separator: ":").map(String.init)
        if current.contains(folder) { return nil }
        return current.isEmpty ? folder : folder + ":" + current.joined(separator: ":")
    }

    /// mosh needs a UTF-8 locale on both ends (design 8.1). The variable to set to a UTF-8 locale so
    /// that mosh has one here, or nil when it has one already.
    ///
    /// One variable decides how characters are read: `LC_ALL` if it is set and not empty, otherwise
    /// `LC_CTYPE`, otherwise `LANG` (POSIX.1-2024, Base Definitions 8.2). When that one isn't UTF-8 it
    /// is the one to set, because a variable below it would be ignored: `LANG` can't undo `LC_ALL=C`.
    /// With none of them set it is `LANG`. mosh also offers these variables to the workhorse as a
    /// fallback locale, so the one that changes the least is used and not `LC_ALL` every time.
    static func localeVariableToSet(_ environment: [String: String]) -> String? {
        let deciding = ["LC_ALL", "LC_CTYPE", "LANG"].first { !(environment[$0] ?? "").isEmpty }
        guard let deciding, let value = environment[deciding]?.lowercased() else { return "LANG" }
        return value.contains("utf-8") || value.contains("utf8") ? nil : deciding
    }
}
