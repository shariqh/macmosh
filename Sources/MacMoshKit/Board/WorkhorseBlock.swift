import Foundation

/// What one workhorse shows, decided once for the menu (`MenuModel`) and the window's board
/// (`BoardModel`), so the two can't drift apart (main window design, section 7.2): its headline, its
/// hint, its buttons in order, its desks, and the summary and home-address light of a Ready workhorse.
/// Each face lays these out its own way; neither decides which there are.
///
/// The buttons come in this order, desks aside: the state's own (under the hint), New desk…, the
/// rarer ones (in the menu, the headline's submenu), and the checklist last. `buttons` lists them so.
public struct WorkhorseBlock: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Ready, with sign-ins working or off: desks, New desk… and the rarer buttons.
        case ready
        /// Any other state that came from a check.
        case other
        /// Just logged in to, with the desk server not started yet (issue #88).
        case waitingForDeskServer
        /// No answer yet.
        case stillChecking
    }

    public var kind: Kind
    public var headline: String
    public var hint: String?
    /// The button right under the hint, if the state has one (`ButtonRules.forState`).
    public var stateButtons: [ActionButton]
    /// Ready only: `ButtonRules.desks`.
    public var desks: [DeskLine]
    /// Ready only.
    public var newDesk: ActionButton?
    /// Ready only: Share screen, a laptop's lid-closed switch, Restart… (`ButtonRules.forHeadline`).
    public var rareButtons: [ActionButton]
    /// Ready only, when there is a report: `StatusFormat.summaryFacts`, which the menu draws one per line.
    public var summaryFacts: [String]
    /// The same facts as one line, `StatusFormat.summaryLine`, as the window's board shows them; nil with none.
    public var summary: String? { summaryFacts.isEmpty ? nil : summaryFacts.joined(separator: " · ") }
    /// Ready only, when a home address is known: whether this Mac can reach it (`homeLine` words it).
    public var homeReachable: Bool?
    /// Every workhorse has the checklist, last.
    public var checklist: ActionButton

    /// Every button but the desks', in the order both faces show them.
    public var buttons: [ActionButton] {
        stateButtons + (newDesk.map { [$0] } ?? []) + rareButtons + [checklist]
    }

    /// Under "Waiting for the desk server". Every clause is true when it is shown (issue #88).
    public static let waitingForDeskServerHint = "Someone has logged in and the desk server isn't running yet. MacMosh's login agent starts it after a login; if it still isn't running in a minute, this menu says so."

    /// "Home address reachable from here: yes"
    public static func homeLine(_ reachable: Bool) -> String {
        "Home address reachable from here: \(reachable ? "yes" : "no")"
    }

    /// A workhorse in `waitingForDeskServer` whose check found the desk server off shows the wait
    /// instead of the fix, and adds nothing to the icon.
    public static func isWaitingForDeskServer(_ r: CheckResult, _ waitingForDeskServer: Set<String>) -> Bool {
        waitingForDeskServer.contains(r.workhorse.id) && r.state == .notSetUp(.deskServerDown)
    }

    /// The block for one check's result. `now` and `timeZone` shape the time in a hint's "Last seen 14:02".
    public static func of(_ r: CheckResult, waitingForDeskServer: Set<String>, now: Date,
                          timeZone: TimeZone) -> WorkhorseBlock {
        let checklist = ButtonRules.checklist(r.workhorse.id)
        if isWaitingForDeskServer(r, waitingForDeskServer) {
            // No "Finish setting up…": the login agent is about to do it.
            return WorkhorseBlock(kind: .waitingForDeskServer,
                                  headline: "\(r.workhorse.name) · Waiting for the desk server",
                                  hint: waitingForDeskServerHint, stateButtons: [], desks: [], newDesk: nil,
                                  rareButtons: [], summaryFacts: [], homeReachable: nil, checklist: checklist)
        }
        var block = WorkhorseBlock(kind: .other, headline: StatusFormat.headline(r),
                                   hint: StatusFormat.hint(r, now: now, timeZone: timeZone),
                                   stateButtons: ButtonRules.forState(r), desks: [], newDesk: nil, rareButtons: [],
                                   summaryFacts: [], homeReachable: nil, checklist: checklist)
        guard case .ready = r.state else { return block }
        block.kind = .ready
        block.desks = ButtonRules.desks(r)
        block.newDesk = ButtonRules.newDesk(r.workhorse.id)
        block.rareButtons = ButtonRules.forHeadline(r)
        block.summaryFacts = r.status.map(StatusFormat.summaryFacts) ?? []
        block.homeReachable = r.homeReachable
        return block
    }

    /// A workhorse that hasn't answered yet: its name, "Still checking…", and the checklist.
    public static func stillChecking(_ w: Workhorse) -> WorkhorseBlock {
        WorkhorseBlock(kind: .stillChecking, headline: "\(w.name) · Still checking…", hint: nil, stateButtons: [],
                       desks: [], newDesk: nil, rareButtons: [], summaryFacts: [], homeReachable: nil,
                       checklist: ButtonRules.checklist(w.id))
    }
}
