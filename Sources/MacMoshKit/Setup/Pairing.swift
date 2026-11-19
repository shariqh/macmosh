import Foundation

public enum PairingError: Error, Equatable {
    /// Not `user@address`, or a part of it that ssh could read as an option.
    case badTarget(String)
    /// The address is saved with a different pinned key. Nothing was changed.
    case keyDiffers
    /// The person didn't type yes to the fingerprint. Nothing was copied.
    case declined
    /// `ssh-copy-id` exited with this code.
    case copyFailed(Int32)
    /// After copying, signing in with the key still didn't work.
    case keyNotAccepted
    /// The key ssh would sign in with can't be used: "your ssh key is locked".
    case identityUnusable(path: String)
}

/// Pairing a workhorse (design 5.3): `add` pins its host key, and `pair` shows the fingerprint to
/// compare at the workhorse, then installs MacMosh's own key there with `ssh-copy-id`.
///
/// The workhorse's password is typed by the person into ssh, which `ssh-copy-id` runs in the
/// terminal MacMosh hands over. Nothing here takes, returns, logs or stores it, and nothing reads
/// the terminal while `ssh-copy-id` runs.
public struct Pairing: Sendable {
    /// The key-works check is a batch ssh; it gets this long.
    static let probeTimeLimit: Duration = .seconds(15)
    /// The remote command of the key-works check. Its answer becomes the name of a workhorse that
    /// was named after its address.
    static let computerNameCommand = "scutil --get ComputerName"

    private let store: WorkhorseStore
    private let paths: Paths
    private let runner: CommandRunner
    private let interactive: InteractiveRunner
    private let keys: KeyManager
    private let now: @Sendable () -> Date

    public init(store: WorkhorseStore, paths: Paths, runner: CommandRunner, interactive: InteractiveRunner,
                keys: KeyManager, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.paths = paths
        self.runner = runner
        self.interactive = interactive
        self.keys = keys
        self.now = now
    }

    // MARK: add

    /// Saves the workhorse at `target` (`user@address`) with the key `ssh-keyscan` reads there,
    /// unpaired. Its id comes from `name`, or else from the address (see `nameFromAddress`).
    ///
    /// For an address already saved (as a main address, home address or local name) it changes
    /// nothing: it returns the saved record when the key is the pinned one and throws `.keyDiffers`
    /// when it isn't. It never replaces a pinned key.
    public func add(target: String, name: String?) async throws -> Workhorse {
        let (user, address) = try Self.parse(target)
        let hostKey = try await HostKeys.scan(address: address, runner: runner)
        let list = try store.load()
        let known = list.filter { Self.isSaved(address, in: $0) }
        if known.contains(where: { HostKeys.normalized($0.hostKey) != HostKeys.normalized(hostKey) }) {
            throw PairingError.keyDiffers
        }
        if let saved = known.first { return saved }

        let chosen = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let display = chosen.isEmpty ? Self.nameFromAddress(address) : chosen
        let id = Workhorse.makeID(from: display, existing: list.map(\.id))
        let w = Workhorse(id: id, name: display, user: user, mainAddress: address, hostKey: hostKey, paired: false)
        try store.upsert(w)
        return w
    }

    // MARK: pair

    /// Pairs a saved workhorse (id or name) or a `user@address`, which it adds first. In order:
    /// makes MacMosh's own key if there is none (only when the workhorse uses that key), checks the
    /// key can be used, shows the pinned key's fingerprint and how to compare it, asks for a yes
    /// unless `confirmedFingerprint` is that fingerprint, says who asks for the password, hands the
    /// terminal to `ssh-copy-id`, checks the key now signs in, and only then marks it paired.
    public func pair(_ idOrTarget: String, confirmedFingerprint: String?, ui: Interaction) async throws -> Workhorse {
        let w = idOrTarget.contains("@") ? try await add(target: idOrTarget, name: nil) : try store.find(idOrTarget)

        // Key first: MacMosh makes only its own key, and never signs in with one it can't use.
        if w.identityFile?.isEmpty ?? true {
            let key = paths.defaultIdentity.path
            let existed = KeyManager.somethingIsAt(key)
            try await keys.ensureIdentity()
            if !existed && KeyManager.somethingIsAt(key) { ui.say("Created MacMosh's own ssh key at \(key).") }
        }
        let identity = KeyManager.identityURL(for: w, paths: paths).path
        guard keys.identityState(for: w) == .usable, (try? keys.publicKeyBlob(for: w)) != nil else {
            throw PairingError.identityUnusable(path: identity)
        }

        let fingerprint = try HostKeys.fingerprint(of: w.hostKey)
        ui.say("This installs MacMosh's own ssh key on \(w.user)@\(w.mainAddress), so MacMosh can check on that Mac without a password.")
        ui.say("Its key fingerprint is: \(fingerprint)")
        ui.say("At the workhorse, run this and compare: \(HostKeys.compareCommand)")
        if confirmedFingerprint != fingerprint {
            let answer = ui.ask("Type yes if they match: ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard answer.lowercased() == "yes" else { throw PairingError.declined }
        }

        ui.say("Next, ssh asks for the workhorse's password. You are typing into ssh; MacMosh can't see it.")
        let code = await interactive.runAttached(copyIDArgv(for: w), environment: [:])
        guard code == 0 else { throw PairingError.copyFailed(code) }

        let argv = SSHInvocation.argv(for: w, address: w.mainAddress, paths: paths, batch: true, tty: false,
                                      remote: [Self.computerNameCommand])
        let result = await runner.run(argv[0], Array(argv.dropFirst()), environment: [:], stdin: nil,
                                      timeout: Self.probeTimeLimit)
        guard case .ok(let stdout) = SSHProbe.classify(result) else {
            ui.say("Tried: ssh to \(w.user)@\(w.mainAddress) with the key, running \(Self.computerNameCommand). \(Self.describe(result))")
            throw PairingError.keyNotAccepted
        }

        let computerName = Self.computerName(from: stdout)
        let accepted = now()
        try store.update(id: w.id) { saved in
            saved.paired = true
            saved.lastKeyAccepted = accepted
            if let computerName, saved.name == Self.nameFromAddress(saved.mainAddress) { saved.name = computerName }
        }
        let paired = try store.find(w.id)
        ui.say("Paired. Next: macmosh prepare \(paired.id) --fix")
        return paired
    }

    /// `ssh-copy-id -i <identity>.pub`, the options that pin the host key, `--`, then `user@address`.
    /// It has no other `-i` (`ssh-copy-id` refuses a second one), so it doesn't use
    /// `SSHInvocation.options`. The system's `ssh-copy-id` reads its options with `getopts`, which
    /// stops at `--`, so the destination is never read as an option.
    public func copyIDArgv(for w: Workhorse) -> [String] {
        ["ssh-copy-id", "-i", KeyManager.identityURL(for: w, paths: paths).path + ".pub"]
            + SSHInvocation.hostKeyOptions(for: w, paths: paths)
            + ["--", "\(w.user)@\(w.mainAddress)"]
    }

    // MARK: Choosing a workhorse

    /// For `macmosh pair` with no argument: lists the Macs among the Tailscale devices, numbered,
    /// and lets the person pick one or type an address, then asks for the user name, offering
    /// `currentUser`. Returns `user@address`, or nil when nothing was chosen. An answer that is
    /// already `user@address` is returned as it is.
    public static func chooseTarget(ui: Interaction, tailscale: TailscaleStatus?, currentUser: String) -> String? {
        let macs = (tailscale?.peers ?? []).filter { $0.os.lowercased() == "macos" }
        if !macs.isEmpty {
            ui.say("Macs on your Tailscale network:")
            for (i, mac) in macs.enumerated() {
                let address = address(of: mac)
                let label = mac.hostName.isEmpty ? address : "\(mac.hostName) (\(address))"
                ui.say("  \(i + 1). \(label)\(mac.online ? "" : ", offline")")
            }
        }
        let answer = ui.ask(macs.isEmpty ? "Workhorse address: " : "Pick a number, or type an address: ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return nil }
        let address: String
        if let n = Int(answer) {
            guard n >= 1, n <= macs.count else { return nil }
            address = Self.address(of: macs[n - 1])
        } else if answer.contains("@") {
            return answer
        } else {
            address = answer
        }
        let user = ui.ask("User name on the workhorse [\(currentUser)]: ").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(user.isEmpty ? currentUser : user)@\(address)"
    }

    /// A Tailscale device's MagicDNS name without the trailing dot, else its first IPv4 address.
    static func address(of peer: TailscalePeer) -> String {
        var dns = peer.dnsName
        while dns.hasSuffix(".") { dns.removeLast() }
        if !dns.isEmpty { return dns }
        return peer.addresses.first { IPv4.parse($0) != nil } ?? peer.addresses.first ?? peer.hostName
    }

    // MARK: Errors

    /// What went wrong and the one thing to do next (design 5.3). `target` is what the person asked
    /// to pair, for the command to run again.
    public static func explain(_ error: Error, target: String) -> String {
        switch error {
        case PairingError.badTarget(let t):
            return "\"\(t)\" isn't a user name and an address. Check it and give both, like this: alex@workhorse"
        case PairingError.keyDiffers:
            return "MacMosh already has a different key pinned for that address, so something else may be answering there. "
                + "Stop. Don't type a password. Check at the workhorse with: \(HostKeys.compareCommand)"
        case PairingError.declined:
            return "Nothing was installed. Check that you are pairing the right Mac, then run: macmosh pair \(target)"
        case PairingError.copyFailed(let code):
            return "ssh-copy-id stopped with code \(code), so MacMosh's key may not be installed. "
                + "Check the user name and that Remote Login is on at the workhorse, then run: macmosh pair \(target)"
        case PairingError.keyNotAccepted:
            return "The key was copied, but signing in with it didn't work. "
                + "Check that Remote Login is on at the workhorse, then run: macmosh pair \(target)"
        case PairingError.identityUnusable(let path):
            return "Your ssh key is locked. MacMosh can't use \(path). "
                + "Check that it and its .pub file are there, that only you can read it, and that it has no passphrase."
        case IdentityError.createFailed(let said):
            return "MacMosh couldn't create its ssh key. ssh-keygen said: \(said). Check that your ssh folder is yours and writable."
        case IdentityError.noPublicKey(let path):
            return "Your ssh key is locked. MacMosh can't read \(path). Check that the .pub file next to the key is there."
        case HostKeyError.noKey(let address):
            return "Tried ssh-keyscan at \(address), and no ed25519 key came back. "
                + "Check the address, and that Remote Login is on at the workhorse (System Settings > General > Sharing)."
        case HostKeyError.malformed:
            return "Tried ssh-keyscan, and the answer wasn't an ed25519 key MacMosh can read. Check that the address is the workhorse."
        case StoreError.notFound(let name):
            return "No workhorse called \"\(name)\". Run: macmosh list"
        default:
            return "Pairing stopped: \(error). Run: macmosh pair \(target)"
        }
    }

    // MARK: Helpers

    /// `user@address`, refusing a target with no user or address, more than one `@`, a space or
    /// control character, or a part beginning with `-`, which ssh tools could read as an option.
    static func parse(_ target: String) throws -> (user: String, address: String) {
        let bad = PairingError.badTarget(target)
        let unsafe = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        guard !target.unicodeScalars.contains(where: { unsafe.contains($0) }) else { throw bad }
        let parts = target.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              !parts[0].hasPrefix("-"), !parts[1].hasPrefix("-") else { throw bad }
        return (String(parts[0]), String(parts[1]))
    }

    /// The name a workhorse gets when none is given: the address's first label (`workhorse` from
    /// `workhorse.local`), or the whole address when it is an IP address.
    static func nameFromAddress(_ address: String) -> String {
        if IPv4.parse(address) != nil || address.contains(":") { return address }
        let first = String(address.prefix { $0 != "." })
        return first.isEmpty ? address : first
    }

    /// Whether `address` is one of the workhorse's saved addresses, ignoring case and a trailing dot.
    private static func isSaved(_ address: String, in w: Workhorse) -> Bool {
        let wanted = comparable(address)
        return [w.mainAddress, w.homeAddress, w.localName].contains { $0.map(comparable) == wanted }
    }

    private static func comparable(_ address: String) -> String {
        var s = address.lowercased()
        while s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// The last line the workhorse printed, without control characters and at most 64 characters:
    /// a shell start-up file may print before the command does. Nil when nothing is left.
    static func computerName(from stdout: String) -> String? {
        let lines = stdout.split(whereSeparator: \.isNewline)
            .map { line in String(String.UnicodeScalarView(line.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let last = lines.last else { return nil }
        return String(last.prefix(64))
    }

    /// One sentence about what ssh answered.
    private static func describe(_ result: CommandResult) -> String {
        switch SSHProbe.classify(result) {
        case .authDenied: return "The workhorse turned the key down."
        case .hostKeyChanged: return "The workhorse answered with a different host key."
        case .hostKeyUnknown: return "No host key is pinned for it."
        case .timedOut: return "Nothing answered in time."
        case .refused: return "The connection was refused."
        case .unresolved: return "The address couldn't be found."
        case .identityUnusable(let detail), .unreachable(let detail): return "ssh said: \(detail)"
        case .remoteFailed(let code, _): return "The command on the workhorse exited with code \(code)."
        case .ok: return "It worked."
        }
    }
}
