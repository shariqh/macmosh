import Foundation

/// The short random word MacMosh gives each tab it opens with a window option, so it can find that tab
/// again (menu design 2 and 7). The workhorse script stores it on the tab's view and echoes it in the
/// report's `view` line.
public enum TabLabel {
    /// The workhorse script's rule (`attach --label`): 4 to 32 characters, each a digit or a letter from a to f.
    /// Checked on Unicode scalars, so a digit carrying a combining mark doesn't pass as a digit.
    public static func isValid(_ word: String) -> Bool {
        (4...32).contains(word.unicodeScalars.count)
            && word.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    /// A new label: 8 random bytes as 16 lowercase hex characters. `fill` fills the bytes; by default it is
    /// `arc4random_buf`, which arc4random(3) on this Mac describes as using "a cryptographic pseudo-random
    /// number generator" that "is re-seeded from the kernel random number subsystem on a regular basis".
    public static func make(fill: (inout [UInt8]) -> Void = { $0.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) } }) -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        fill(&bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
