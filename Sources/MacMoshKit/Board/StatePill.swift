import Foundation

/// The colour of a state pill's dot and word (look design 6.3): green for Ready, amber for a state that needs the
/// person, red for one MacMosh can't get past, ink-3 while it is still checking.
public enum PillTone: Sendable, Equatable {
    case ready, needsYou, cannot, checking

    public var textRole: TextRole {
        switch self {
        case .ready: return .good
        case .needsYou: return .needsYou
        case .cannot: return .cannot
        case .checking: return .tertiary
        }
    }
}

/// The pill beside a workhorse's name in the window's header (look design 6.3): the state's word and its tone. The
/// word is the state's own title, or the block's for the wait and "Still checking…", which are built outside the
/// state's title; never a piece cut from the headline.
public struct StatePill: Sendable, Equatable {
    public var word: String
    public var tone: PillTone

    public init(word: String, tone: PillTone) {
        self.word = word
        self.tone = tone
    }

    /// The pill of a state a check found, worded as the headline words it (`StatusFormat.title`).
    public static func of(_ state: WorkhorseState) -> StatePill {
        let tone: PillTone
        switch state {
        case .ready(let signIns): tone = signIns ? .ready : .needsYou
        case .waitingForLogin, .locked, .notSetUp: tone = .needsYou
        case .cantVerify, .cantReach: tone = .cannot
        }
        return StatePill(word: StatusFormat.title(state), tone: tone)
    }

    /// The pill of a workhorse's block: the wait for the desk server and "Still checking…" by the block's kind, any
    /// other by its state. A block of kind `.ready` or `.other` always has a state; without one it is still checking.
    public static func of(_ block: WorkhorseBlock, state: WorkhorseState?) -> StatePill {
        switch block.kind {
        case .waitingForDeskServer: return StatePill(word: WorkhorseBlock.waitingForDeskServerTitle, tone: .needsYou)
        case .stillChecking: return StatePill(word: WorkhorseBlock.stillCheckingTitle, tone: .checking)
        case .ready, .other:
            return state.map(of) ?? StatePill(word: WorkhorseBlock.stillCheckingTitle, tone: .checking)
        }
    }
}
