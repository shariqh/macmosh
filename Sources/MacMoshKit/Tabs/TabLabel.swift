import Foundation

/// The short random word MacMosh gives each tab it opens with a window option, so it can find that tab
/// again (menu design 2 and 7). The workhorse script stores it on the tab's view and echoes it in the
/// report's `view` line.
public enum TabLabel {
    /// The workhorse script's rule (`attach --label`): 4 to 32 characters, each a digit or a letter from a to f.
    public static func isValid(_ word: String) -> Bool {
        (4...32).contains(word.count) && word.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
}
