import Foundation
import Testing

/// A refusal: exit 1, one `release.sh: refused: ` sentence on stderr, and nothing built, signed or sent.
private func expectRefusal(_ h: ReleaseHarness, _ arguments: [String], _ sentence: String,
                           environment: [String: String?] = [:],
                           sourceLocation: SourceLocation = #_sourceLocation) {
    let out = h.run(arguments, environment: environment)
    #expect(out.exitCode == 1, "\(arguments)", sourceLocation: sourceLocation)
    #expect(out.stderr == "release.sh: refused: " + sentence + "\n", sourceLocation: sourceLocation)
    #expect(h.calls.allSatisfy { $0.hasPrefix("git ") }, "\(h.calls)", sourceLocation: sourceLocation)
}

/// The build and the checks before sending, in order; `dist/X/` is `dist/rehearsal/` or `dist/release/`.
private let checks = ["build-app.sh --into dist/X/0.1.0",
    "codesign --verify --deep --strict --verbose=2 dist/X/0.1.0/MacMosh.app",
    "codesign --display --entitlements - --xml dist/X/0.1.0/MacMosh.app",
    "codesign --display --verbose=2 dist/X/0.1.0/MacMosh.app",
    "codesign --display --entitlements - --xml dist/X/0.1.0/MacMosh.app/Contents/Helpers/macmosh",
    "codesign --display --verbose=2 dist/X/0.1.0/MacMosh.app/Contents/Helpers/macmosh",
    "lipo -archs dist/X/0.1.0/MacMosh.app/Contents/MacOS/MacMosh",
    "lipo -archs dist/X/0.1.0/MacMosh.app/Contents/Helpers/macmosh",
    "ditto -c -k --keepParent dist/X/0.1.0/MacMosh.app dist/X/0.1.0/for-notary.zip"]

/// Every stand-in call but git's.
private func steps(_ h: ReleaseHarness) -> [String] { h.calls.filter { !$0.hasPrefix("git ") } }

extension HostScriptTests {
    /// scripts/release.sh, run as a copy in a throwaway repository with stand-ins for every outside tool (issue #36).
    @Suite struct ReleaseScriptTests {
        @Test func refusesAWrongShape() throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            for arguments in [[], ["0.1.0", "0.1.0"], ["--rehearse", "0.1.0"], ["--rehearsal"], ["0.1.0", "--rehearsal"]] {
                let out = h.run(arguments)
                #expect(out.exitCode == 2 && out.stderr == "usage: scripts/release.sh [--rehearsal] <version>\n", "\(arguments)") } }

        @Test func refusesAVersionThatIsNotTheApps() throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            expectRefusal(h, ["0.2.0"], "0.2.0 is not the app's version; Sources/MacMoshKit/MacMoshKit.swift says 0.1.0.") }

        @Test func refusesWhenTheVersionCannotBeRead() throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            try "// no version here\n".write(to: h.repo.appendingPathComponent("Sources/MacMoshKit/MacMoshKit.swift"),
                                             atomically: true, encoding: .utf8)
            expectRefusal(h, ["0.1.0"], "could not read the app's version from Sources/MacMoshKit/MacMoshKit.swift.") }

        @Test func refusesWithoutASigningIdentity() throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            for value in [nil, ""] as [String?] {
                expectRefusal(h, ["0.1.0"], "MACMOSH_SIGN_IDENTITY is empty, and a release is never signed ad hoc.",
                              environment: ["MACMOSH_SIGN_IDENTITY": value])
                expectRefusal(h, ["--rehearsal", "0.1.0"], "MACMOSH_SIGN_IDENTITY is empty, and a release is never signed ad hoc.",
                              environment: ["MACMOSH_SIGN_IDENTITY": value]) } }

        @Test func refusesWithoutANotaryProfile() throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            for value in [nil, ""] as [String?] {
                expectRefusal(h, ["0.1.0"],
                              "MACMOSH_NOTARY_PROFILE is empty; set it to the profile name you saved with notarytool store-credentials.",
                              environment: ["MACMOSH_NOTARY_PROFILE": value]) } }

        @Test func refusesUncommittedChanges() throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            try "x\n".write(to: h.repo.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
            expectRefusal(h, ["0.1.0"], "the checkout has changes that are not committed.")
            expectRefusal(h, ["--rehearsal", "0.1.0"], "the checkout has changes that are not committed.") }

        /// Rows 6 to 10: a release refuses them, and a rehearsal goes on.
        @Test(arguments: [
            ([["checkout", "-q", "-b", "try"]], "the checkout is on try, not main."),
            ([["checkout", "-q", "--detach"]], "the checkout is on a detached HEAD, not main."),
            ([["commit", "-q", "--allow-empty", "-m", "not pushed"]], "main here is not the same commit as origin/main."),
            ([["tag", "v0.1.0"]], "the tag v0.1.0 already exists here."),
            ([["tag", "v0.1.0"], ["push", "-q", "origin", "v0.1.0"], ["tag", "-d", "v0.1.0"]], "the tag v0.1.0 already exists on origin.")])
        func refusesWhatOnlyAReleaseNeeds(git commands: [[String]], sentence: String) throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            for command in commands { #expect(h.git(command).exitCode == 0, "\(command)") }
            expectRefusal(h, ["0.1.0"], sentence)
            #expect(h.run(["--rehearsal", "0.1.0"]).exitCode == 0) }

        /// Rows 10 (an answer other than 0 or 2) and 7, with git's own messages kept off the terminal.
        @Test func refusesWhenOriginCannotBeAsked() throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            let out = h.run(["0.1.0"], fault: "ls-remote-fails")
            #expect(out.exitCode == 1 && out.stderr == "release.sh: refused: could not ask origin whether the tag v0.1.0 exists.\n")
            #expect(h.git(["remote", "set-url", "origin", h.root.appendingPathComponent("missing.git").path]).exitCode == 0)
            expectRefusal(h, ["0.1.0"], "could not fetch origin to compare main with it.")
            #expect(h.run(["--rehearsal", "0.1.0"]).exitCode == 0) }

        @Test func refusesAReleaseFolderThatIsThere() throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            try FileManager.default.createDirectory(at: h.repo.appendingPathComponent("dist/release/0.1.0"),
                                                    withIntermediateDirectories: true)
            expectRefusal(h, ["0.1.0"], "dist/release/0.1.0 already exists; move it to the Trash to build this version again.") }

        @Test func theHarnessStandsInForEveryToolThatReachesOut() throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            for tool in ["codesign", "xcrun", "spctl", "gh", "security", "lipo", "ditto", "git"] {   // a forgotten one would be real
                #expect(FileManager.default.isExecutableFile(atPath: h.root.appendingPathComponent("stubs/\(tool)").path), "\(tool)") } }

        @Test func theScriptKeepsItsOwnRules() throws {
            let url = HostHarness.repoRoot().appendingPathComponent("scripts/release.sh")
            let script = try String(contentsOf: url, encoding: .utf8)
            #expect(FileManager.default.isExecutableFile(atPath: url.path) && script.hasPrefix("#!/bin/bash\n"))
            for banned in ["/usr/bin/", "STANDIN", "defaults write", "--sign", "store-credentials \"", "notarytool history"] {
                #expect(!script.contains(banned), "\(banned)") }
            #expect(script.range(of: #"(^|[\s;|&(])rm\s"#, options: .regularExpression) == nil)
            for line in script.split(separator: "\n") {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("#") || code.hasPrefix("echo ") || code.hasPrefix("printf ") { continue }
                #expect(!code.hasPrefix("git tag") && !code.hasPrefix("git push") && !code.hasPrefix("gh "), "\(line)") }
            let check = try String(contentsOf: HostHarness.repoRoot().appendingPathComponent("scripts/check.sh"), encoding: .utf8)
            #expect(check.contains("\nshellcheck scripts/release.sh\n")) }

        @Test func aRehearsalSendsNothing() throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            _ = h.git(["checkout", "-q", "-b", "try"]); _ = h.git(["tag", "v0.1.0"])
            let out = h.run(["--rehearsal", "0.1.0"], environment: ["MACMOSH_NOTARY_PROFILE": nil])
            #expect(out.exitCode == 0, "\(out.stderr)")
            #expect(out.stdout.hasSuffix("release.sh: rehearsal finished. Nothing was sent to Apple's notary service, and nothing in dist/rehearsal/0.1.0 is a release.\n"))
            #expect(steps(h) == checks.map { $0.replacingOccurrences(of: "dist/X/", with: "dist/rehearsal/") })
            let folder = h.repo.appendingPathComponent("dist/rehearsal/0.1.0")
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            for name in ["MacMosh.app", "for-notary.zip", "REHEARSAL.txt", "signature-app.txt", "signature-command.txt"] {
                #expect(names.contains(name), "\(name)") }
            #expect(!names.contains { $0.hasPrefix("MacMosh-") || $0.hasSuffix(".sha256") })
            #expect(!FileManager.default.fileExists(atPath: h.repo.appendingPathComponent("dist/release").path)) }

        @Test func aRehearsalPutsTheLastOneInTheTrash() throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            #expect(h.run(["--rehearsal", "0.1.0"]).exitCode == 0)
            #expect(h.run(["--rehearsal", "0.1.0"]).exitCode == 0)
            let trash = try FileManager.default.contentsOfDirectory(atPath: h.home.appendingPathComponent(".Trash").path)
            #expect(trash.filter { $0.hasPrefix("rehearsal-0.1.0-") }.count == 1) }

        @Test(arguments: [
            ("verify-fails", "the signature of dist/release/0.1.0/MacMosh.app did not verify (codesign --verify --deep --strict)."),
            ("extra-entitlement", "the entitlements on MacMosh.app are not exactly those of App/MacMosh.entitlements."),
            ("no-runtime", "MacMosh.app does not have the hardened runtime switched on."),
            ("no-timestamp", "MacMosh.app has no secure timestamp."),
            ("helper-no-timestamp", "Contents/Helpers/macmosh has no secure timestamp."),
            ("intel", "Contents/MacOS/MacMosh is built for x86_64 arm64; the first release is for Apple silicon (arm64) only."),
            ("home-path", "Contents/Helpers/macmosh contains a folder path from the Mac that built it (the text /Users/)."),
            ("sample-menu", "Contents/MacOS/MacMosh contains MACMOSH_SAMPLE_MENU, so it is not a release build."),
            ("wrong-version", "MacMosh.app says version 0.0.9, not 0.1.0.")])
        func aFailedCheckStopsBeforeAnythingIsSent(fault: String, sentence: String) throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            let out = h.run(["0.1.0"], fault: fault)
            #expect(out.exitCode == 1)
            #expect(out.stderr.split(separator: "\n").last.map(String.init) == "release.sh: stopped: " + sentence)
            #expect(!steps(h).contains { $0.hasPrefix("xcrun ") || $0.hasPrefix("spctl ") || $0.hasPrefix("ditto ") }) }

        /// What names the certificate's owner stays in dist/, which git ignores.
        @Test func theSigningNameStaysInDist() throws {
            let h = try ReleaseHarness(); defer { h.cleanUp() }
            let out = h.run(["0.1.0"])
            #expect(out.exitCode == 0, "\(out.stderr)")
            #expect(!(out.stdout + out.stderr).contains("Stand-in Signer"))
            let signature = try String(contentsOf: h.repo.appendingPathComponent("dist/release/0.1.0/signature-app.txt"), encoding: .utf8)
            #expect(signature.contains("Authority=Stand-in Signer (TEAM000000)")) }
    }
}
