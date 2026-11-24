import Foundation

/// Which window a tab opened by `macmosh connect` shows, from its `--window @<id>`, `--new-window` or
/// `--view` option (menu design 8.3).
public enum TabTarget: Sendable, Equatable {
    /// `--window @<id>`: this window of the desk.
    case window(String)
    /// `--new-window`: a new window the desk gets for this tab.
    case newWindow
    /// `--view`: the window the desk shows now, in a view of its own.
    case view

    /// The target the options name, nil when none is given. One at a time; a window id is `@` and digits.
    public static func from(window: String?, newWindow: Bool, view: Bool) throws(TabTargetError) -> TabTarget? {
        guard [window != nil, newWindow, view].filter({ $0 }).count <= 1 else { throw .moreThanOne }
        if let window {
            guard HostStatus.isWindowId(window) else { throw .badWindowId(window) }
            return .window(window)
        }
        if newWindow { return .newWindow }
        if view { return .view }
        return nil
    }

    /// The option for the workhorse script's `attach`; `--view` sends none.
    public var attachArguments: [String] {
        switch self {
        case .window(let id): ["--window", id]
        case .newWindow: ["--new-window"]
        case .view: []
        }
    }

    /// The option, as the tab record keeps it in `target`: `window`, `new-window` or `view`.
    public var recordWord: String {
        switch self {
        case .window: "window"
        case .newWindow: "new-window"
        case .view: "view"
        }
    }

    /// The window asked for, as the tab record keeps it: the id, or empty.
    public var askedWindow: String {
        if case .window(let id) = self { return id }
        return ""
    }
}

public enum TabTargetError: Error, Equatable, CustomStringConvertible {
    case moreThanOne
    case badWindowId(String)

    public var description: String {
        switch self {
        case .moreThanOne: "Use one of --window, --new-window and --view, not two."
        case .badWindowId(let id): "\"\(id)\" isn't a window id: use @ and its number, such as @3."
        }
    }
}

/// A tab's label and target, as the words given to `attach` before the desk's name.
public struct TabRequest: Sendable, Equatable {
    public var label: String
    public var target: TabTarget

    public init(label: String, target: TabTarget) {
        self.label = label
        self.target = target
    }

    /// `--label <word>` and the target's option.
    public var attachArguments: [String] { ["--label", label] + target.attachArguments }
}

/// What `connect` needs to note its tab: where the records go, a label maker, this process and its start
/// time, the tab's terminal device and the clock. Tests pass stand-ins.
public struct TabNoting: Sendable {
    public var store: TabRecordStore
    public var makeLabel: @Sendable () -> String
    /// The process that stays alive while the tab is connected. `connect` starts ssh or mosh as its child
    /// with `posix_spawn` and waits for it (`ProcessRunner.runAttached`); it never replaces itself with
    /// `exec`, so it is `macmosh connect` itself.
    public var pid: Int32
    /// Its start time in microseconds since 1970, nil when it can't be read (then no record is written).
    public var started: Int64?
    public var tty: String
    public var now: @Sendable () -> Date

    public init(store: TabRecordStore, makeLabel: @escaping @Sendable () -> String, pid: Int32, started: Int64?,
                tty: String, now: @escaping @Sendable () -> Date) {
        self.store = store
        self.makeLabel = makeLabel
        self.pid = pid
        self.started = started
        self.tty = tty
        self.now = now
    }

    /// The running program. The terminal device is `ttyname(STDIN_FILENO)`, which ttyname(3) on this Mac says
    /// "returns the null terminated name if the device is found and isatty() is true; otherwise a NULL pointer
    /// is returned": empty then.
    public static func thisProcess(paths: Paths) -> TabNoting {
        let probe = SystemProcessProbe()
        let tty = ttyname(STDIN_FILENO).map { String(cString: $0) } ?? ""
        return TabNoting(store: TabRecordStore(paths: paths, probe: probe), makeLabel: { TabLabel.make() },
                         pid: getpid(), started: probe.ownStartTime(), tty: tty, now: { Date() })
    }
}
