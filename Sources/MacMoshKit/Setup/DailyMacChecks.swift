import Foundation

/// What the daily Mac's checks are worked out from. `Checklist` gathers it; tests write it out.
struct DailyMacFacts: Sendable, Equatable {
    var moshPath: String?
    var brewPath: String?
    /// The terminal desks open in: the setting's, or the one picked automatically.
    var terminal: TerminalApp
    var terminalFromSetting: Bool
    var identity: IdentityState
    /// The key is MacMosh's own (`~/.ssh/macmosh_ed25519`), not one the person named.
    var ownKey: Bool
    /// The key file as a person would write it.
    var identityPath: String
    /// nil: Tailscale isn't installed on this Mac.
    var tailscaleRunning: Bool?
}

/// The six checks on the daily Mac (design 7.5). A pure function of the facts.
enum DailyMacChecks {
    static let tailscaleLink = "https://tailscale.com/download"

    static func outcomes(_ f: DailyMacFacts) -> [CheckOutcome] {
        [mosh(f), terminal(f), identity(f), tabs(), homeNetwork(), tailscale(f)]
    }

    private static func outcome(_ id: CheckID, _ passed: Bool?, _ fix: FixKind, _ title: String, _ detail: String,
                                _ action: FixAction? = nil) -> CheckOutcome {
        CheckOutcome(id: id, side: .dailyMac, passed: passed, fix: fix, title: title, detail: detail, action: action)
    }

    private static func mosh(_ f: DailyMacFacts) -> CheckOutcome {
        let title = "mosh is installed"
        if let path = f.moshPath { return outcome(.moshInstalled, true, .auto, title, path) }
        if f.brewPath != nil {
            return outcome(.moshInstalled, false, .auto, title,
                           "mosh isn't installed on this Mac. MacMosh installs it with Homebrew.", .automatic)
        }
        return outcome(.moshInstalled, false, .auto, title,
                       "mosh isn't installed on this Mac, and neither is Homebrew, which installs it.",
                       .steps(["Install Homebrew: follow the steps at https://brew.sh",
                               "Run this checklist again with --fix: it then installs mosh."]))
    }

    private static func terminal(_ f: DailyMacFacts) -> CheckOutcome {
        let name = f.terminal == .iterm2 ? "iTerm2" : "Terminal"
        let why = f.terminalFromSetting ? "as your setting says" : (f.terminal == .iterm2 ? "it is installed" : "iTerm2 isn't installed")
        return outcome(.terminalChosen, nil, .info, "A terminal is chosen", "Desks open in \(name), because \(why).")
    }

    private static func identity(_ f: DailyMacFacts) -> CheckOutcome {
        let title = "MacMosh's own ssh key exists"
        switch f.identity {
        case .usable:
            return outcome(.identityExists, true, .auto, title, f.identityPath)
        case .missing where f.ownKey:
            return outcome(.identityExists, false, .auto, title,
                           "\(f.identityPath) isn't there yet. MacMosh creates it: an ed25519 key with no passphrase, readable only by you.",
                           .automatic)
        case .missing:
            // A key the person named is theirs: MacMosh never makes or replaces it.
            return outcome(.identityExists, false, .info, title,
                           "The key named in this workhorse's settings, \(f.identityPath), isn't there.",
                           .steps(["Put the key back at \(f.identityPath), or clear the setting so MacMosh uses its own key."]))
        case .badPermissions:
            // Never overwritten: a file at the key's path may be somebody's key.
            return outcome(.identityExists, false, .info, title,
                           "\(f.identityPath) can be read by others, or isn't a file, so ssh won't use it.",
                           .steps(["Make it readable only by you: chmod 600 \(f.identityPath)"]))
        }
    }

    private static func tabs() -> CheckOutcome {
        outcome(.opensTerminalTabs, nil, .info, "MacMosh may open terminal tabs",
                "macOS asks once per terminal app, the first time MacMosh opens a tab there. Choose Allow.")
    }

    private static func homeNetwork() -> CheckOutcome {
        outcome(.reachesHomeNetwork, nil, .info, "MacMosh may reach the home network",
                "macOS asks once, the first time MacMosh reaches the workhorse on your home network. Choose Allow.")
    }

    private static func tailscale(_ f: DailyMacFacts) -> CheckOutcome {
        let title = "Tailscale is connected"
        switch f.tailscaleRunning {
        case true?:
            return outcome(.tailscaleConnected, true, .info, title, "Tailscale is on.")
        case false?:
            return outcome(.tailscaleConnected, false, .info, title,
                           "Tailscale is installed but not connected. Optional: it lets you reach the workhorse away from home.")
        case nil:
            return outcome(.tailscaleConnected, nil, .info, title,
                           "Tailscale isn't installed. Optional: it lets you reach the workhorse away from home. \(tailscaleLink)")
        }
    }
}
