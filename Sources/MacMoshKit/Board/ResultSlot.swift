import Foundation

/// Whether a window action worked (look design 6.3), set where the runner already knows: a desk made, renamed,
/// removed, named or started again is `done`; a refusal or an error is `failed`; a call that passed the time limit,
/// which may still have done its work on the workhorse, is `unknown` until the next check shows which.
public enum ResultKind: Sendable, Equatable {
    case done, failed, unknown

    /// A failure in red words, a done result in ink (look-b-details.png draws it so), an unknown one in secondary
    /// words (the view gives each its own mark: a tick, a warning, or a neutral one).
    public var textRole: TextRole {
        switch self {
        case .failed: return .cannot
        case .done: return .primary
        case .unknown: return .secondary
        }
    }
}

/// What the header's result slot holds (look design 6.3): the slot is always two lines high and never moves the list.
/// The last action's sentence, with its kind, when there is one; under it, in one line, the menu's notice when it
/// says something else. Without a result, the notice alone, in both lines.
public struct ResultSlot: Sendable, Equatable {
    /// The whole sentence: the slot's value and its help tag, however many lines show.
    public var sentence: String
    /// nil for the notice alone, and for a result whose kind is not known.
    public var kind: ResultKind?
    /// The sentence is the workhorse's result line, which carries `page.result`; false for the notice alone.
    public var isResult: Bool
    /// The menu's notice under the result, when it is a different sentence; nil otherwise.
    public var notice: String?
    /// The lines the sentence may take: both, or one when a notice sits under it.
    public var sentenceLines: Int

    public init(sentence: String, kind: ResultKind?, isResult: Bool, notice: String?, sentenceLines: Int) {
        self.sentence = sentence
        self.kind = kind
        self.isResult = isResult
        self.notice = notice
        self.sentenceLines = sentenceLines
    }
}

extension WorkhorsePage {
    /// The slot for the menu's notice now; nil when there is neither a result nor a notice. The notice is left out
    /// when it is the result line, as `notice(_:)` decides.
    public func resultSlot(notice: String?) -> ResultSlot? {
        let other = self.notice(notice)
        let lines = LookSize.resultLines
        if let result {
            return ResultSlot(sentence: result, kind: resultKind, isResult: true, notice: other,
                              sentenceLines: other == nil ? lines : lines - 1)
        }
        return other.map { ResultSlot(sentence: $0, kind: nil, isResult: false, notice: nil, sentenceLines: lines) }
    }
}
