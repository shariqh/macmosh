import Foundation
import MacMoshKit
import Testing

extension HostScriptTests {
    @Suite struct RemoteStringTests {
        /// Review Focus item 1: a folder and a startup command full of characters the shell treats
        /// as special reach the workhorse exactly as typed. The remote string is run with
        /// `/bin/sh -c`, as sshd runs it, against the real script.
        @Test func remoteStringSurvivesTheRemoteShell() throws {
            let h = try HostHarness(); defer { h.cleanUp() }
            try h.installScriptInHome()
            let odd = h.home.appendingPathComponent("My \"Proj\" $HOME it's é")
            try FileManager.default.createDirectory(at: odd, withIntermediateDirectories: true)
            _ = h.run(["start"])
            let args = HostCommands.newDeskArguments(name: DeskName("odd")!, folder: odd.path, reopen: false, keep: false,
                                                     command: "echo \"$((6*7))\" > out.txt")
            let remote = SSHInvocation.hostCommand(args)[0]
            #expect(h.shell(remote).exitCode == 0)            // /bin/sh -c <remote>, as sshd's shell would run it
            let path = h.tmux(["display-message", "-p", "-t", "=odd:", "#{session_path}"]).stdout
                .trimmingCharacters(in: .newlines)
            #expect(path == odd.path)
            try waitFor(seconds: 5) { FileManager.default.fileExists(atPath: odd.appendingPathComponent("out.txt").path) }
            #expect(try String(contentsOf: odd.appendingPathComponent("out.txt"), encoding: .utf8) == "42\n")
        }
    }
}
