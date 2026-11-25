import Foundation

/// The window's sheet that names one window of a desk (issue 144): "Name a window of website", the label "Name for
/// window 2 (vim)", one field filled with the window's name now, the rule (or why the typed name can't be used)
/// under it, and three buttons: "Use its program's name", Cancel, and Name, which is off until the name keeps
/// `WindowName`'s rule and differs from the one it has. The window is the one with this id; its number is only for
/// reading. `WindowActionRunner.nameWindow` sends it.
public struct WindowNameForm: Sendable, Equatable, Identifiable {
    public enum Words {
        public static let useProgramsName = "Use its program's name"
        public static let cancel = "Cancel"
        public static let name = "Name"
        public static let naming = "Naming…"
    }

    public var id: String { workhorseID + "/" + desk + "/" + windowID }
    public let workhorseID: String
    public let workhorseName: String
    public let desk: String
    /// tmux's window id, which the call names.
    public let windowID: String
    /// The number tmux gives the window, only for reading.
    public let number: Int
    /// The window's name in the check's report; "" for none.
    public let current: String
    /// What is in the field. It starts as the current name.
    public var name: String

    /// nil when the check has no such desk or window, or its windows can't be named (`WindowNameGate`).
    public init?(check: CheckResult, desk: String, window: String) {
        guard let session = check.status?.desks.first(where: { $0.name.value == desk }),
              WindowNameGate.passes(check, desk: session),
              let shown = session.windows.first(where: { $0.id == window }) else { return nil }
        workhorseID = check.workhorse.id
        workhorseName = check.workhorse.name
        self.desk = desk
        windowID = window
        number = shown.index
        current = shown.name
        name = shown.name
    }

    public var title: String { "Name a window of \(desk)" }
    /// "Name for window 2 (vim)", or "Name for window 2" for a window with no name.
    public var label: String { current.isEmpty ? "Name for window \(number)" : "Name for window \(number) (\(current))" }

    /// Why the typed name can't be used; nil while it is still the current one, which only keeps Name off.
    public var problem: String? { name == current ? nil : WindowName.problem(name) }
    /// The line under the field: the rule, or why the typed name can't be used.
    public var help: String { problem ?? WindowName.rule }
    public var helpIsProblem: Bool { problem != nil }

    public var canName: Bool { name != current && WindowName(name) != nil }

    /// What Name sends; nil while it is off.
    public var naming: WindowNaming? { canName ? WindowName(name).map(WindowNaming.named) : nil }
}
