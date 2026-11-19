import Foundation

/// Why a workhorse that answers isn't ready to use yet.
public enum SetupProblem: String, Sendable, Codable {
    /// MacMosh's key was refused and has never worked, or was refused at a Tailscale address.
    case notPaired
    /// The ssh key on this Mac is missing or can't be used: "Your ssh key is locked". Never "Locked".
    case identityUnusable
    /// The workhorse has no `macmosh-host` script, or can't run it.
    case hostScriptMissing
    /// The script speaks another version of the status report.
    case hostScriptOutdated
    /// The report was cut off, had no header, or the script failed.
    case unreadableReport
    /// Somebody is logged in, but the desk server isn't running.
    case deskServerDown
}

/// The likely reason nothing answers, shown under "Can't reach it".
public enum UnreachableReason: String, Sendable, Codable {
    case tailscaleOff, noNetwork, otherVPN, awayAndOffline, nothingAnswers
}

/// What MacMosh shows for a workhorse (design 5.2). `notSetUp` is the plan's addition for a
/// workhorse that answers but isn't finished.
public enum WorkhorseState: Sendable, Equatable {
    case ready(signIns: Bool)             // false is "Ready, sign-ins off"
    case waitingForLogin
    case locked
    case cantVerify
    case cantReach(UnreachableReason)
    case notSetUp(SetupProblem)
}
