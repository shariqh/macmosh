import Foundation

/// The command lines MacMosh runs ssh with. Every call pins the workhorse's host key: one key
/// per workhorse, looked up under its alias whatever address is used, with strict checking on.
///
/// Each `-o` value is its own argument. The command line never goes through a shell on the
/// daily Mac, except in `sshStringForMosh`, which quotes every argument for the splitter mosh uses.
public enum SSHInvocation {
    /// The workhorse script. Left unquoted so the remote shell expands `~`.
    public static let remoteScript = "~/.macmosh/macmosh-host"

    /// The five options that pin the host key, in this order: the alias the key is filed under,
    /// MacMosh's own key file (and no other), strict checking, and no learning of new keys.
    ///
    /// The key file's path keeps double quotes inside its argument: ssh's own option parser
    /// takes them off, so a path with spaces (`Application Support`) stays one path.
    public static func hostKeyOptions(for w: Workhorse, paths: Paths) -> [String] {
        [
            "-o", "HostKeyAlias=\(w.hostKeyAlias)",
            "-o", "UserKnownHostsFile=\"\(paths.knownHostsFile.path)\"",
            "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UpdateHostKeys=no",
        ]
    }

    /// Sign-in by key only: ssh never asks for a password.
    public static let noPasswordOptions = ["-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no"]

    /// `hostKeyOptions`, then the key to sign in with. MacMosh's own key has no passphrase, so the
    /// agent is turned off for it; a key the user named keeps the agent, which may hold its passphrase.
    /// `batch` adds the options for a check nobody is watching: no prompts, a 5-second connect limit,
    /// and `LogLevel=INFO`, ssh's default. `SSHProbe.classify` reads ssh's messages, and a quieter
    /// `LogLevel` in the user's ssh settings would hide them (at `ERROR` the changed-key banner is
    /// gone; at `QUIET` nothing is printed). An option on the command line wins over the settings file.
    public static func options(for w: Workhorse, paths: Paths, batch: Bool) -> [String] {
        var o = hostKeyOptions(for: w, paths: paths)
        o += ["-o", "IdentitiesOnly=yes", "-i", KeyManager.identityURL(for: w, paths: paths).path]
        // An empty identityFile means MacMosh's own key too, as in KeyManager.identityURL.
        if w.identityFile?.isEmpty ?? true { o += ["-o", "IdentityAgent=none"] }
        if batch { o += ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "LogLevel=INFO"] }
        return o
    }

    /// The whole command line: `ssh`, the options, `extraOptions`, `-t` when a terminal is wanted,
    /// `--`, `user@address`, then `remote`. An empty `remote` gives an interactive login. The `--`
    /// ends ssh's options, so the destination can never be read as one (a user name starting with `-`).
    public static func argv(for w: Workhorse, address: String, paths: Paths, batch: Bool,
                            tty: Bool, extraOptions: [String] = [], remote: [String]) -> [String] {
        ["ssh"] + options(for: w, paths: paths, batch: batch) + extraOptions
            + (tty ? ["-t"] : []) + ["--", "\(w.user)@\(address)"] + remote
    }

    /// The remote command that runs the workhorse script with `arguments`, as one string for the
    /// remote shell. Each argument is quoted once; the script's path is not, so `~` expands there.
    public static func hostCommand(_ arguments: [String]) -> [String] {
        arguments.isEmpty ? [remoteScript] : [remoteScript + " " + ShellQuote.join(arguments)]
    }

    /// The value for mosh's `--ssh`: `ssh`, the interactive options and `noPasswordOptions`, each
    /// quoted with `ShellQuote.posix`. mosh splits it with Perl's `shellwords`, which gives back
    /// exactly these arguments. mosh adds the destination itself.
    ///
    /// Known limit: Perl's `shellwords` treats a backslash inside single quotes as an escape, so an
    /// argument ending in `\` (for example a key path ending in a backslash) does not split back.
    public static func sshStringForMosh(for w: Workhorse, paths: Paths) -> String {
        ShellQuote.join(["ssh"] + options(for: w, paths: paths, batch: false) + noPasswordOptions)
    }
}
