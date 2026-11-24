import Foundation

/// What a window button runs, until the window's own forms exist (main window design, section 8, step 3).
///
/// A button that carries one of the menu's actions runs it as it is, through `MenuRefresher.perform`
/// like the menu's line. New desk, Rename and Remove have no form yet (step 4), so each runs the menu
/// action that does the same thing today: the terminal tab that asks its questions. "Open the N not in a
/// tab" opens the tabs the board listed, one after another (`MenuAction.tabs`).
/// Start again and Forget run nothing: there are no ended desks until step 5.
public enum WindowRun {
    public static func menuAction(for action: BoardAction) -> MenuAction? {
        switch action {
        case .menu(let action):
            return action
        case .window(.newDesk(let id)):
            return ButtonRules.newDesk(id).action
        case .window(.rename(let id, let desk)):
            return ButtonRules.forDesk(workhorse: id, desk: desk, isOpen: false).first { $0.key == "rename" }?.action
        case .window(.remove(let id, let desk)):
            return ButtonRules.forDesk(workhorse: id, desk: desk, isOpen: false).first { $0.key == "remove" }?.action
        case .window(.openAllWithoutTab(_, let tabs)):
            return .tabs(tabs)
        case .window(.startAgain), .window(.forget):
            return nil
        }
    }
}
