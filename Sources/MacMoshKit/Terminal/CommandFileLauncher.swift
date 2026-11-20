import Foundation

/// Opens a small `.command` file with the terminal app. It needs no Automation permission, so it
/// is the way out when macOS refuses the AppleScript (sitting 1, item 2).
public struct CommandFileLauncher: TerminalLauncher {
    private let runner: CommandRunner
    private let app: TerminalApp
    private let folder: URL

    /// Files this old are deleted the next time a file is made.
    static let keepFor: TimeInterval = 24 * 60 * 60
    static let openTimeLimit: Duration = .seconds(30)

    public init(runner: CommandRunner, app: TerminalApp, folder: URL) {
        self.runner = runner
        self.app = app
        self.folder = folder
    }

    public func openTab(_ command: TabCommand, title: String) async throws {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        } catch {
            throw LaunchError.failed("Could not make a folder for the tab's file: \(error.localizedDescription)")
        }
        clearOldFiles()

        let name = "MacMosh-" + Self.randomHex(count: 8) + ".command"
        let file = folder.appendingPathComponent(name)
        let contents = "#!/bin/sh\nexec \(command.line)\n"
        guard fm.createFile(atPath: file.path, contents: Data(contents.utf8),
                            attributes: [.posixPermissions: 0o700]) else {
            throw LaunchError.failed("Could not write the tab's file.")
        }
        // createFile applies the umask to the mode it is given, so say it again.
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)

        let result = await runner.run("open", ["-a", app.openName, file.path], environment: [:],
                                      stdin: nil, timeout: Self.openTimeLimit)
        if result.timedOut { throw LaunchError.failed("\(app.displayName) did not answer in time.") }
        if result.exitCode != 0 {
            let said = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LaunchError.failed(said.isEmpty ? "open ended with code \(result.exitCode)." : said)
        }
    }

    /// Deletes this launcher's own files (named `MacMosh-<8 hex characters>.command`) that are
    /// more than a day old. Nothing else in the folder is touched.
    private func clearOldFiles() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]) else { return }
        let cutoff = Date().addingTimeInterval(-Self.keepFor)
        for url in urls where Self.isOurs(url.lastPathComponent) {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true, let modified = values?.contentModificationDate,
                  modified < cutoff else { continue }
            try? fm.removeItem(at: url)
        }
    }

    static func isOurs(_ name: String) -> Bool {
        guard name.hasPrefix("MacMosh-"), name.hasSuffix(".command") else { return false }
        let middle = name.dropFirst("MacMosh-".count).dropLast(".command".count)
        return middle.count == 8 && middle.allSatisfy { $0.isASCII && ($0.isNumber || ("a"..."f").contains($0)) }
    }

    private static func randomHex(count: Int) -> String {
        String((0..<count).map { _ in "0123456789abcdef".randomElement()! })
    }
}
