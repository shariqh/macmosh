import Foundation

/// A form the window opens in place of the menu's terminal tab (main window design, section 7.2).
public enum WindowForm: Sendable, Equatable {
    case newDesk(workhorse: String)
    case rename(workhorse: String, desk: String)
    case remove(workhorse: String, desk: String)
    /// The sheet that names one window of a desk, by the window's id (issue 144).
    case nameWindow(workhorse: String, desk: String, window: String)
}

/// What a window button runs (main window design, section 8, steps 3 and 4).
///
/// A button that carries one of the menu's actions runs it as it is, through `MenuRefresher.perform` like the
/// menu's line. New desk, Rename and Remove open the window's own forms (`form(for:)`), which
/// `WindowActionRunner` runs; the menu keeps its terminal tabs for them. "Open the N not in a tab" opens the
/// tabs the board listed, one after another (`MenuAction.tabs`). Start again and Forget on an ended desk (step 5)
/// are neither: the window hands them to `WindowActionRunner.startAgain` and `forget`.
public enum WindowRun {
    /// The menu action a button runs; nil for a form, and for Start again and Forget.
    public static func menuAction(for action: BoardAction) -> MenuAction? {
        switch action {
        case .menu(let action):
            return action
        case .window(.openAllWithoutTab(_, let tabs)):
            return .tabs(tabs)
        case .window(.newDesk), .window(.rename), .window(.remove), .window(.startAgain), .window(.forget),
             .window(.nameWindow):
            return nil
        }
    }

    /// The form a button opens, if it opens one.
    public static func form(for action: BoardAction) -> WindowForm? {
        switch action {
        case .window(.newDesk(let id)): return .newDesk(workhorse: id)
        case .window(.rename(let id, let desk)): return .rename(workhorse: id, desk: desk)
        case .window(.remove(let id, let desk)): return .remove(workhorse: id, desk: desk)
        case .window(.nameWindow(let id, let desk, let window)): return .nameWindow(workhorse: id, desk: desk, window: window)
        default: return nil
        }
    }
}
