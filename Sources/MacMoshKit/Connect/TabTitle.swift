import Foundation

public enum TabTitle {
    /// The escape that names a terminal tab: ESC ] 1 ; <title> BEL (iTerm2 shows it on the tab).
    /// Control characters in the title are dropped, so it can't end the escape early or start another.
    public static func escape(_ title: String) -> String {
        let clean = String(String.UnicodeScalarView(title.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }))
        return "\u{1B}]1;\(clean)\u{07}"
    }
}
