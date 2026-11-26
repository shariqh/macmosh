import Foundation

/// What a desk row's state cell says (look design 6.5).
public enum DeskStateKind: Sendable, Equatable {
    /// "In 1 tab", "In 2 tabs".
    case inTabs
    /// "No tab".
    case noTab
    /// "Closed".
    case closed
    /// "Updating…", "Renaming…", "Naming…" while an action runs on it.
    case busy

    /// In green when it is in a tab, in secondary words otherwise.
    public var textRole: TextRole {
        switch self {
        case .inTabs: return .good
        case .noTab, .closed, .busy: return .secondary
        }
    }
}

/// A desk row's state cell (look design 6.5): its word, which CI reads under `desk.<name>.status`, and its kind.
public struct DeskStateCell: Sendable, Equatable {
    public var word: String
    public var kind: DeskStateKind

    public init(word: String, kind: DeskStateKind) {
        self.word = word
        self.kind = kind
    }
}

/// A desk row's second line (look design 6.5): the folder and the unusual facts ("Kept when it exits", "Doesn't come
/// back after a restart"), or, for a desk with no saved definition, the tag "Made by hand". It never loses its facts:
/// too long for one line, the folder is cut in the middle with "…", and the whole line is the help tag.
public struct SecondLine: Sendable, Equatable {
    /// The folder shown the short way; nil for a desk made by hand, or one with no folder.
    public var folder: String?
    /// The facts that apply, in order.
    public var facts: [String]
    /// "Made by hand" for a desk with no saved definition; nil otherwise.
    public var tag: String?

    public init(folder: String?, facts: [String], tag: String?) {
        self.folder = folder
        self.facts = facts
        self.tag = tag
    }

    /// The folder and the facts joined with " · ", or the tag; "" for a desk just made, before its check.
    public var whole: String {
        if let tag { return tag }
        return ([folder].compactMap { $0 } + facts).joined(separator: " · ")
    }

    /// The help tag: the whole line, or for the tag the sentence today's row shows.
    public var help: String { tag == nil ? whole : WindowWords.notMadeWithMacMosh }

    /// The line in at most `maxCharacters` characters where it can be: the whole line when it fits; otherwise the facts
    /// stay whole and the folder is cut in the middle with "…" to the room left, at least 5 characters, keeping
    /// (room - 1) / 2 from its start and the rest from its end. The tag is never cut.
    public func fitted(_ maxCharacters: Int) -> String {
        let all = whole
        guard tag == nil, all.count > maxCharacters, let folder else { return all }
        let factsPart = facts.isEmpty ? "" : " · " + facts.joined(separator: " · ")
        let room = max(maxCharacters - factsPart.count, 5)
        guard folder.count > room else { return all }
        let head = (room - 1) / 2
        let tail = room - 1 - head
        return String(folder.prefix(head)) + "…" + String(folder.suffix(tail)) + factsPart
    }

    /// The lines the row tries, longest first: the whole line, then `fitted(n)` for n from one character shorter down
    /// to 0, each different one once, so each rung is one character shorter than the last and the folder is never cut
    /// more than the room needs. The view draws the first that fits on one line (`ViewThatFits`). The tag alone for a tag.
    public var ladder: [String] {
        let all = whole
        guard tag == nil, !all.isEmpty else { return [all] }
        return stride(from: all.count - 1, through: 0, by: -1).map(fitted).reduce(into: [all]) {
            if $0.last != $1 { $0.append($1) }
        }
    }
}
