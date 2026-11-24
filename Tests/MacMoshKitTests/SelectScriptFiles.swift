import Foundation
import Testing
@testable import MacMoshKit

/// Hands CI the exact select scripts the app sends (issue #129). When `MACMOSH_SELECT_SCRIPTS_OUT` names a
/// folder, this writes `ITermLauncher.selectScript` and `AppleTerminalLauncher.selectScript` into it, byte
/// for byte, and the "Terminal scripts" job runs those files against the real apps
/// (scripts/ci/try-select.sh). Without the variable it is skipped and writes nothing.
@Suite struct SelectScriptFiles {
    static let folder = ProcessInfo.processInfo.environment["MACMOSH_SELECT_SCRIPTS_OUT"]

    @Test(.enabled(if: SelectScriptFiles.folder != nil))
    func writeTheSelectScriptsForCI() throws {
        let folder = URL(fileURLWithPath: try #require(Self.folder), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(ITermLauncher.selectScript.utf8).write(to: folder.appendingPathComponent("iterm2-select.applescript"))
        try Data(AppleTerminalLauncher.selectScript.utf8).write(to: folder.appendingPathComponent("terminal-select.applescript"))
    }
}
