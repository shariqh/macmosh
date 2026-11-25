import Foundation

/// The desks that ended, by workhorse (main window design, sections 7.1 C and 7.2): an ordinary desk whose last
/// shell exited, so the workhorse removed it. The window lists them under "Ended" with Start again and Forget.
///
/// It compares each workhorse's Ready check with its last Ready check before it. A desk is ended when its session
/// was open in that earlier check and its definition there was not permanent, and it is not open in the new one,
/// whether or not its definition is still listed (the script removes it about a minute after the exit). Only
/// Ready checks are compared: a check in any other state changes nothing and is not the one compared with. What it
/// keeps is what Start again needs, from the definition in the earlier check: the name, the folder exactly as the
/// report gave it, the startup command, the reopen and keep flags, and the time of the check that first missed it.
///
/// Not listed:
/// - a desk with no definition in the earlier check (made by hand with tmux): no folder is known, so it could not
///   be started again;
/// - a permanent desk that closed: it stays on the board as closed;
/// - a view, a tab's own session on one window of a desk (the desk's name, `+` and digits): the report lists it
///   only under its desk (`HostStatus.Desk.views`), never as a desk;
/// - a desk the window itself removed or renamed: the runner marks it before it sends the call (`expectGone`);
/// - a desk that disappears in the same check in which a new desk appears with the same folder and startup
///   command: that is a rename made elsewhere (the menu's tab, a terminal);
/// - while the refresher waits for the desk server after a login, nothing (that wait is never a Ready check);
/// - in the first Ready check after a check in another state (a restart, most often), a desk whose definition is
///   still there with reopen: it may be on its way back, so it gets one more Ready check, and is listed then,
///   from the time it was first missed, if it is still not open. A desk without reopen that a restart closed is
///   listed at once, which the design calls useful.
///
/// A desk that is open again in a later Ready check leaves the list at that check. The list is in memory only: it
/// starts empty when MacMosh starts and nothing is written to disk. It keeps at most `limit` desks per workhorse,
/// newest first, dropping the oldest. Pure: the refresher feeds it each check's results.
public struct EndedDeskTracker: Sendable, Equatable {
    /// At most this many ended desks per workhorse; the oldest goes first.
    public static let limit = 20

    /// By workhorse id, newest first.
    public private(set) var ended: [String: [EndedDesk]] = [:]

    /// One desk of the Ready check compared with: its definition in that check (nil: made by hand), and, for a
    /// desk given one more check after a restart, when it was first missed.
    private struct Seen: Sendable, Equatable {
        var definition: HostStatus.Definition?
        var missedAt: Date?
    }

    /// By workhorse id: the desks open in its last Ready check, and those given one more check.
    private var seen: [String: [String: Seen]] = [:]
    /// The workhorses with a check in another state since their last Ready one.
    private var gap: Set<String> = []
    /// By workhorse id: the desks the window is removing or renaming.
    private var expected: [String: Set<String>] = [:]

    public init() {}

    /// Takes one refresh's results. `waiting` are the workhorses the refresher shows as waiting for the desk server;
    /// `onList` the ids on the saved list, so a workhorse taken off it is forgotten. A workhorse still being
    /// checked (`.stillChecking`) changes nothing.
    public mutating func take(_ gathered: [Gathered], waiting: Set<String>, onList ids: Set<String>) {
        for case .checked(let r) in gathered {
            take(r, waitingForDeskServer: waiting.contains(r.workhorse.id))
        }
        ended = ended.filter { ids.contains($0.key) }
        seen = seen.filter { ids.contains($0.key) }
        gap.formIntersection(ids)
        expected = expected.filter { ids.contains($0.key) }
    }

    private mutating func take(_ r: CheckResult, waitingForDeskServer waiting: Bool) {
        let id = r.workhorse.id
        guard case .ready = r.state, !waiting, let status = r.status else {
            gap.insert(id)
            return
        }
        let open = Set(status.desks.map(\.name.value))
        var definitions: [String: HostStatus.Definition] = [:]
        for d in status.definitions where definitions[d.name.value] == nil { definitions[d.name.value] = d }

        // Open again, by itself or made again elsewhere: no longer ended.
        if var list = ended[id] {
            list.removeAll { open.contains($0.name) }
            ended[id] = list.isEmpty ? nil : list
        }

        var next: [String: Seen] = [:]
        if let before = seen[id] {
            let afterGap = gap.contains(id)
            let appeared = open.subtracting(before.keys)
            var gone: [EndedDesk] = []
            for (name, was) in before where !open.contains(name) {
                if expected[id]?.remove(name) != nil { continue }
                guard let def = was.definition, !def.permanent else { continue }
                let renamed = appeared.contains { new in
                    definitions[new].map { $0.folder == def.folder && $0.command == def.command } ?? false
                }
                if renamed { continue }
                if afterGap, was.missedAt == nil, definitions[name]?.reopen == true {
                    next[name] = Seen(definition: def, missedAt: r.checkedAt)
                    continue
                }
                gone.append(EndedDesk(name: name, folder: def.folder, command: def.command.isEmpty ? nil : def.command,
                                      reopen: def.reopen, keep: def.keep, endedAt: was.missedAt ?? r.checkedAt))
            }
            if !gone.isEmpty {
                let names = Set(gone.map(\.name))
                // Newest first; desks missed at the same check in name order.
                let newest = gone.sorted { $0.endedAt != $1.endedAt ? $0.endedAt > $1.endedAt : $0.name < $1.name }
                var list = ended[id] ?? []
                list.removeAll { names.contains($0.name) }
                list = Array((newest + list).prefix(Self.limit))
                ended[id] = list
            }
        }
        for name in open { next[name] = Seen(definition: definitions[name], missedAt: nil) }
        seen[id] = next
        gap.remove(id)
    }

    /// The window is about to remove or rename that desk: when a Ready check finds it gone, it is not listed.
    public mutating func expectGone(workhorse id: String, desk: String) {
        expected[id, default: []].insert(desk)
    }

    /// The removal or rename failed, or the check after it has landed: the mark is taken back.
    public mutating func stopExpecting(workhorse id: String, desk: String) {
        expected[id]?.remove(desk)
        if expected[id]?.isEmpty == true { expected[id] = nil }
    }

    /// Takes that ended desk off the list: Forget, or Start again worked.
    public mutating func forget(workhorse id: String, desk: String) {
        guard var list = ended[id] else { return }
        list.removeAll { $0.name == desk }
        ended[id] = list.isEmpty ? nil : list
    }

    /// Start again didn't work: the entry stays, with why, in one line.
    public mutating func failed(workhorse id: String, desk: String, reason: String) {
        guard let i = ended[id]?.firstIndex(where: { $0.name == desk }) else { return }
        ended[id]?[i].problem = reason
    }
}
