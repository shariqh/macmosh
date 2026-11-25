// Debug builds only, like `SampleMenu`, `SampleWindow` and `SampleForms`. A release build has none of this, and
// `scripts/build-app.sh` checks that the release app does not even contain the sample variable's name.
#if DEBUG
import Foundation

/// The `window-settings` sample (issue 157): two workhorses, Attic (Mosh, Adaptive, a projects folder, a last desk
/// command) and Spare (Tabs, Never, nothing else), both Ready, for CI's pictures of the Settings page.
///
/// The page's stand-in store is a saved list and settings file of its own, in a temporary folder named after the
/// app's process (`macmosh-sample-settings-<pid>`), never the person's: the Settings page saves into it, the board
/// and the checks read it, and CI reads the file to see what a click changed. No ssh runs and the checks write
/// nothing back. Every name in here is made up.
public enum SampleSettings {
    static let attic = Workhorse(id: "attic", name: "Attic", user: "alex", mainAddress: "attic",
                                 hostKey: "ssh-ed25519 SAMPLE-KEY-NOT-REAL", paired: true,
                                 projectsFolder: "~/Development", osVersion: "26.1", arch: "arm64",
                                 lastDeskCommand: "claude --continue")
    static let spare = Workhorse(id: "spare", name: "Spare", user: "alex", mainAddress: "spare",
                                 hostKey: "ssh-ed25519 SAMPLE-KEY-NOT-REAL", paired: true, mode: .tabs, prediction: .never,
                                 osVersion: "15.6", arch: "arm64")

    /// The sample's own folder, under the temporary folder: its saved list, and a stand-in key file (made-up text,
    /// not a key) so that the window's desk actions find a usable key. Never the real support folder or `~/.ssh`.
    public static let paths: Paths = folder("macmosh-sample-settings-\(ProcessInfo.processInfo.processIdentifier)",
                                            list: [attic, spare])

    /// The Settings page's stand-in for another sample (`SampleRun.settingsPaths`): a folder of its own, named after
    /// the sample and the app's process, holding the sample's workhorses, or with `list` nil a saved list that can't
    /// be read, as the `unreadable-list` sample's. So the page agrees with the sidebar, and never reads the person's.
    static func paths(forSample name: String, list: [Workhorse]?) -> Paths {
        folder("macmosh-sample-settings-\(ProcessInfo.processInfo.processIdentifier)-\(name)", list: list)
    }

    private static func folder(_ name: String, list: [Workhorse]?) -> Paths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        let paths = Paths(supportDir: root.appendingPathComponent("support", isDirectory: true),
                          sshDir: root.appendingPathComponent("ssh", isDirectory: true))
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: paths.sshDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let key = paths.defaultIdentity
            try Data("stand-in for a sample, not a key\n".utf8).write(to: key)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: key.path)
            if let list {
                try WorkhorseStore(paths: paths).save(list)
            } else {
                try fm.createDirectory(at: paths.supportDir, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                try Data("not JSON".utf8).write(to: paths.workhorsesFile)
            }
        } catch {
            MenuLog.write("sample: the settings sample's folder was not made")
        }
        return paths
    }

    /// The real refresher, reading the sample's saved list (so a saved name shows in the menu at its next check),
    /// with checks that find each workhorse Ready. They write nothing back to the list.
    @MainActor static func refresher() -> MenuRefresher {
        let store = WorkhorseStore(paths: paths)
        return MenuRefresher(
            load: { try store.load() },
            gather: { list in list.map { .checked(SampleForms.result($0)) } },
            save: { _ in })
    }
}
#endif
