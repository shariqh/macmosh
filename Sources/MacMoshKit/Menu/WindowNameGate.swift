import Foundation

/// Whether an open desk's windows can be named (issue 144): the menu's `Name a window…` line and the window's
/// Name buttons are there only when both hold:
/// 1. the workhorse's script is 0.11.0 or newer (`HostInstaller.isAtLeast`), which has `window-name`;
/// 2. the report gives the desk's windows' ids (`windowinfo` lines), since a window is named by its id.
/// The connection doesn't matter, so the line is there in both shapes of a desk's submenu. A closed desk has no
/// windows, so it never passes.
public enum WindowNameGate {
    public static let firstScriptVersion = DeskFlow.nameWindowNeeds

    /// `desk` is the desk's session in the report, nil for a closed permanent desk.
    public static func passes(_ r: CheckResult, desk: HostStatus.Desk?) -> Bool {
        guard let status = r.status, HostInstaller.isAtLeast(status.scriptVersion, firstScriptVersion) else { return false }
        return desk?.hasWindowInfo ?? false
    }
}
