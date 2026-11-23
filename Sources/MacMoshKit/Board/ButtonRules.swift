import Foundation

/// One button the menu shows as a line, and the window (later) as a button: what it says and what
/// clicking it does. `key` is a short fixed word, different for each button of one workhorse or of
/// one desk; the menu builds its lines' ids from it.
public struct ActionButton: Sendable, Equatable {
    public var key: String
    public var title: String
    public var action: MenuAction

    public init(key: String, title: String, action: MenuAction) {
        self.key = key
        self.title = title
        self.action = action
    }
}

/// Which buttons go with which state. The menu reads these rules, and the window will read the
/// same ones, so the two can't drift apart (main window design, section 7.2). Every argument is a
/// workhorse id or a desk name, both plain words.
public enum ButtonRules {
    /// The button right under a workhorse's hint, if its state has one: Fix… when sign-ins are off,
    /// Log in…, Unlock disk… (only on a Mac that can be unlocked over ssh), Pair… or Finish setting up….
    public static func forState(_ r: CheckResult) -> [ActionButton] {
        let id = r.workhorse.id
        switch r.state {
        case .ready(let signIns):
            return signIns ? [] : [ActionButton(key: "fix", title: "Fix…",
                                                action: .tab(["prepare", id, "--restart-desk-server", "--pause"]))]
        case .waitingForLogin:
            return [ActionButton(key: "login", title: "Log in…  (opens Screen Sharing)", action: .run(["screen", id]))]
        case .locked:
            guard r.workhorse.canUnlockOverSSH else { return [] }
            return [ActionButton(key: "unlock", title: "Unlock disk…  (you type the Mac's password)",
                                 action: .tab(["unlock", id]))]
        case .cantVerify, .cantReach:
            return []
        case .notSetUp(let problem):
            if problem == .notPaired {
                return [ActionButton(key: "pair", title: "Pair…", action: .tab(["pair", id]))]
            }
            return [ActionButton(key: "finish", title: "Finish setting up…", action: .tab(["prepare", id, "--fix", "--pause"]))]
        }
    }

    /// A Ready workhorse's buttons after its desks: New desk…, Share screen, Restart…, and on a laptop
    /// the lid-closed switch, which offers the opposite of how the setting is now.
    public static func forReady(_ r: CheckResult) -> [ActionButton] {
        let id = r.workhorse.id
        var buttons = [
            ActionButton(key: "newDesk", title: "New desk…", action: .tab(["desk", "new", id])),
            ActionButton(key: "share", title: "Share screen", action: .run(["screen", id])),
            ActionButton(key: "restart", title: "Restart…", action: .tab(["restart", id])),
        ]
        if let status = r.status, status.isLaptop {
            if status.power.disableSleep == 1 {
                buttons.append(ActionButton(key: "lid", title: "Turn off lid-closed mode…", action: .tab(["power", id, "lid", "off"])))
            } else {
                buttons.append(ActionButton(key: "lid", title: "Turn on lid-closed mode…", action: .tab(["power", id, "lid", "on"])))
            }
        }
        return buttons
    }

    /// What clicking a desk does: open a tab attached to it. A closed permanent desk is made again.
    public static func connect(workhorse id: String, desk name: String) -> MenuAction {
        .tab(["connect", id, name])
    }

    /// The buttons under one desk. An open desk can have a window added; a closed one can't. Rename and
    /// Remove open a tab that asks first.
    public static func forDesk(workhorse id: String, desk name: String, isOpen: Bool) -> [ActionButton] {
        var buttons: [ActionButton] = []
        if isOpen {
            buttons.append(ActionButton(key: "window", title: "New window in \(name)", action: .run(["desk", "window", id, name])))
        }
        buttons.append(ActionButton(key: "rename", title: "Rename \(name)…", action: .tab(["desk", "rename", id, name])))
        buttons.append(ActionButton(key: "remove", title: "Remove \(name)…", action: .tab(["desk", "remove", id, name, "--ask"])))
        return buttons
    }

    /// Every workhorse's last button, in every state.
    public static func checklist(_ id: String) -> ActionButton {
        ActionButton(key: "checklist", title: "Run the checklist…", action: .tab(["prepare", id, "--pause"]))
    }

    public static let addAMac = ActionButton(key: "add", title: "Add a Mac…", action: .tab(["pair"]))
    public static let checkNow = ActionButton(key: "check", title: "Check now", action: .refresh)
}
