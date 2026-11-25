import Foundation
import Testing
@testable import MacMoshKit

/// Hands CI the exact select scripts the app sends (issue #129). When `MACMOSH_SELECT_SCRIPTS_OUT` names a
/// folder, this writes `ITermLauncher.selectScript` and `AppleTerminalLauncher.selectScript` into it, byte
/// for byte, and the "Terminal scripts" job runs those files against the real apps
/// (scripts/ci/try-select.sh). It also writes `tab-title-website.txt`, the bytes the app prints to name a tab
/// for the desk "website" before it connects (`TabTitle.escape`, said as one line, as `ConnectRunner` says it),
/// which scripts/ci/try-title.sh prints in a real tab before it attaches (issue 162). Without the variable it is
/// skipped and writes nothing.
@Suite struct SelectScriptFiles {
    static let folder = ProcessInfo.processInfo.environment["MACMOSH_SELECT_SCRIPTS_OUT"]

    @Test(.enabled(if: SelectScriptFiles.folder != nil))
    func writeTheSelectScriptsForCI() throws {
        let folder = URL(fileURLWithPath: try #require(Self.folder), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(ITermLauncher.selectScript.utf8).write(to: folder.appendingPathComponent("iterm2-select.applescript"))
        try Data(AppleTerminalLauncher.selectScript.utf8).write(to: folder.appendingPathComponent("terminal-select.applescript"))
        try Data((TabTitle.escape("website") + "\n").utf8).write(to: folder.appendingPathComponent("tab-title-website.txt"))
    }
}
