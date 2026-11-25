// Debug builds only, like `SampleMenu`, `SampleWindow` and `SampleForms`. A release build has none of this, and
// `scripts/build-app.sh` checks that the release app does not even contain the sample variable's name.
#if DEBUG
import Foundation
import os

/// The `window-ended` sample (main window design, section 8, step 5): the workhorse Attic, Ready, script 0.12.0,
/// whose desks are all open at first. The first click on the window's Check now ends the last shell of recipes,
/// garden, blog and shop, and closes website, which is permanent; at the same moment a permanent desk called shop,
/// closed, takes shop's name, so shop is ended with its name taken again. The check after it lists the four under
/// Ended. No ssh runs: `SampleSSH` stands in for it on these desks, writes the exact arguments to the log, and
/// answers desk-new as the workhorse script would. Every name in here is made up.
public enum SampleEnded {
    /// The desks the stand-in changes, made once per run.
    static let desks = makeDesks()
    private static let clicked = OSAllocatedUnfairLock(initialState: false)

    /// The sample's desks as they are at launch: the folder of recipes has a space and its command a quote and a
    /// dollar sign; garden doesn't come back after a restart and keeps its command running; shop's command is too
    /// long for its line, which the window cuts.
    static func makeDesks() -> SampleDesks {
        typealias D = SampleDesks.Desk
        let w = SampleDesks.windows
        return SampleDesks([
            D(name: "api", windows: w(1, ["server"]), folder: "/Users/alex/Development/api", command: "", permanent: false,
              isOpen: true),
            D(name: "blog", windows: w(2, ["zsh"]), folder: "/Users/alex/Development/blog", command: "", permanent: false,
              isOpen: true),
            D(name: "garden", windows: w(3, ["claude"]), folder: "/Users/alex/Development/garden", command: "claude",
              permanent: false, isOpen: true, reopen: false, keep: true),
            D(name: "recipes", windows: w(4, ["claude"]), folder: "/Users/alex/Development/my recipes",
              command: #"claude --continue "fix it" $HOME"#, permanent: false, isOpen: true),
            D(name: "shop", windows: w(5, ["npm"]), folder: "/Users/alex/Development/shop", command: longCommand,
              permanent: false, isOpen: true),
            D(name: "website", windows: w(6, ["claude", "zsh"]), folder: "/Users/alex/Development/website",
              command: "claude", permanent: true, isOpen: true),
        ], nextWindow: 7)
    }

    /// shop's startup command, longer than its line in the window.
    static let longCommand = "npm run dev -- --port 4000 --host 0.0.0.0 --open --watch --verbose --log-level debug --no-cache"

    /// A click on the window's Check now (`SampleRun.windowRan`): the first one ends the shells.
    static func checkNowClicked() {
        let first = clicked.withLock { done -> Bool in
            defer { done = true }
            return !done
        }
        if first { desks.endShells() }
    }

    static func result(_ w: Workhorse, desks: SampleDesks = desks) -> CheckResult {
        CheckResult(workhorse: w, state: .ready(signIns: true), status: try? HostStatus.parse(desks.report()),
                    probes: ProbeSet(), answeredAt: SampleForms.answeredAt, homeReachable: true, checkedAt: Date())
    }

    /// The real refresher with checks that find Attic Ready with `desks` as they are now.
    @MainActor static func refresher(desks: SampleDesks = desks,
                                     checkTakes: Duration = SampleForms.checkTakes) -> MenuRefresher {
        MenuRefresher(
            load: { [SampleForms.attic] },
            gather: { list in
                if checkTakes > .zero { try? await Task.sleep(for: checkTakes) }
                return list.map { .checked(result($0, desks: desks)) }
            },
            save: { _ in })
    }
}

extension SampleDesks {
    /// What the first Check now does in the `window-ended` sample.
    func endShells() {
        endShells(["recipes", "garden", "blog", "shop", "website"])
        holdAsPermanent("shop")
    }
}
#endif
