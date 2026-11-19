import Foundation
import Testing
@testable import MacMoshKit

@Suite struct ModelTests {
    @Test(arguments: ["website", "a_b-1", String(repeating: "a", count: 64)])
    func acceptsDeskName(_ s: String) { #expect(DeskName(s)?.value == s) }

    @Test(arguments: ["", "a b", "a/b", "é", "a;b", "a\nb", String(repeating: "a", count: 65)])
    func rejectsDeskName(_ s: String) { #expect(DeskName(s) == nil) }

    @Test func deskNameIsCheckedWhenDecoded() throws {
        let good = try JSONDecoder().decode([DeskName].self, from: Data(#"["web"]"#.utf8))
        #expect(good.first?.value == "web")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([DeskName].self, from: Data(#"["a b"]"#.utf8))
        }
    }

    @Test func idsAreSlugsAndUnique() {
        #expect(Workhorse.makeID(from: "MacBook Pro", existing: []) == "macbook-pro")
        #expect(Workhorse.makeID(from: "MacBook Pro", existing: ["macbook-pro"]) == "macbook-pro-2")
        #expect(Workhorse.makeID(from: "MacBook Pro", existing: ["macbook-pro", "macbook-pro-2"]) == "macbook-pro-3")
        #expect(Workhorse.makeID(from: "!!!", existing: []) == "mac")
        #expect(Workhorse.makeID(from: "  Café  Mac--Mini ", existing: []) == "cafe-mac-mini")
    }

    @Test func hostKeyAliasIsPrefixedWithTheId() {
        #expect(Workhorse.sample(id: "mbp").hostKeyAlias == "macmosh-mbp")
    }

    @Test func decodesAFileThatLacksOptionalFieldsAndDefaults() throws {
        let json = #"{"id":"mbp","name":"MacBook Pro","user":"alex","mainAddress":"workhorse","hostKey":"ssh-ed25519 AAAA"}"#
        let w = try JSONDecoder().decode(Workhorse.self, from: Data(json.utf8))
        #expect(w.id == "mbp")
        #expect(w.mode == .mosh)
        #expect(w.prediction == .adaptive)
        #expect(w.paired == false)
        #expect(w.powerChanges == [])
        #expect(w.homeAddress == nil && w.homePrefix == nil && w.localName == nil)
        #expect(w.projectsFolder == nil && w.identityFile == nil)
        #expect(w.osVersion == nil && w.arch == nil && w.lastSeen == nil && w.lastKeyAccepted == nil)
    }

    @Test func ignoresFieldsAddedByALaterVersion() throws {
        let json = #"{"id":"mbp","name":"M","user":"alex","mainAddress":"workhorse","hostKey":"k","futureField":[1,2]}"#
        #expect(try JSONDecoder().decode(Workhorse.self, from: Data(json.utf8)).id == "mbp")
    }

    @Test func missingRequiredFieldIsAnError() {
        let json = #"{"id":"mbp","name":"M","user":"alex","hostKey":"k"}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Workhorse.self, from: Data(json.utf8))
        }
    }

    @Test func settingsDecodeWithoutATerminal() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(s.terminal == nil)
    }

    @Test func pathsAreBuiltFromTheTwoFolders() {
        let p = Paths(supportDir: URL(fileURLWithPath: "/x/Support"), sshDir: URL(fileURLWithPath: "/x/ssh"))
        #expect(p.workhorsesFile.path == "/x/Support/workhorses.json")
        #expect(p.settingsFile.path == "/x/Support/settings.json")
        #expect(p.knownHostsFile.path == "/x/Support/known_hosts")
        #expect(p.defaultIdentity.path == "/x/ssh/macmosh_ed25519")
    }
}
