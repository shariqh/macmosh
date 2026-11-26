import Foundation

/// The sheets' buttons and the look's style each takes (look design 6.4 and 6.8): Make desk, Rename and Name are the
/// one primary button of their sheet; Cancel, Save and Name it after the program running in it are secondary.
public enum FormButton: Sendable, CaseIterable {
    case makeDesk, rename, name, cancel, save, nameAfterProgram

    public var kind: ButtonKind {
        switch self {
        case .makeDesk, .rename, .name: return .primary
        case .cancel, .save, .nameAfterProgram: return .secondary
        }
    }
}
