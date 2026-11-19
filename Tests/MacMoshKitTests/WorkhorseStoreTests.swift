import Foundation
import Testing
@testable import MacMoshKit

/// Collects errors from concurrent work, so a failed write is reported with its cause.
private final class Failures: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ text: String) { lock.withLock { items.append(text) } }
    var all: [String] { lock.withLock { items } }
}

@Suite struct WorkhorseStoreTests {
    private func mode(_ url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.posixPermissions] as? Int ?? -1) & 0o777
    }

    @Test func savingWritesThePinnedKeyFile() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try store.upsert(.sample(id: "mbp", hostKey: "ssh-ed25519 AAAAC3Nza"))
        let pinned = try String(contentsOf: store.paths.knownHostsFile, encoding: .utf8)
        #expect(pinned == "macmosh-mbp ssh-ed25519 AAAAC3Nza\n")
    }

    @Test func roundTripKeepsEveryField() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let w = Workhorse.sample(
            id: "mbp", name: "MacBook Pro", user: "alex", mainAddress: "workhorse",
            homeAddress: "192.168.1.20", homePrefix: 24, localName: "workhorse.local",
            hostKey: "ssh-ed25519 AAAA", paired: true, mode: .tabs, prediction: .never,
            projectsFolder: "/Users/alex/Projects", identityFile: "/Users/alex/.ssh/other",
            osVersion: "26.1", arch: "arm64", lastSeen: when, lastKeyAccepted: when,
            powerChanges: ["sudo pmset -a sleep 0"])
        try store.save([w])
        #expect(try store.load() == [w])
    }

    @Test func filesArePrivate() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try store.upsert(.sample())
        try store.saveSettings(AppSettings(terminal: .iterm2))
        #expect(try mode(store.paths.supportDir) == 0o700)
        #expect(try mode(store.paths.workhorsesFile) == 0o600)
        #expect(try mode(store.paths.knownHostsFile) == 0o600)
        #expect(try mode(store.paths.settingsFile) == 0o600)
    }

    @Test func noTemporaryFilesAreLeftBehind() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try store.upsert(.sample())
        try store.update(id: "mbp") { $0.paired = true }
        let names = try FileManager.default.contentsOfDirectory(atPath: store.paths.supportDir.path).sorted()
        #expect(names == ["known_hosts", "lock", "workhorses.json"])
    }

    @Test func missingFileIsAnEmptyList() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        #expect(try store.load() == [])
        #expect(!FileManager.default.fileExists(atPath: store.paths.supportDir.path))
    }

    @Test func savedFileHasAVersion() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try store.upsert(.sample())
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: store.paths.workhorsesFile))
        let dict = try #require(object as? [String: Any])
        #expect(dict["version"] as? Int == 1)
        #expect((dict["workhorses"] as? [Any])?.count == 1)
    }

    @Test func newerFileVersionIsRefused() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try FileManager.default.createDirectory(at: store.paths.supportDir, withIntermediateDirectories: true)
        let text = #"{"version": 2, "workhorses": [{"somethingNew": true}]}"#
        try Data(text.utf8).write(to: store.paths.workhorsesFile)
        #expect(throws: StoreError.newerVersion(2)) { try store.load() }
        #expect(throws: StoreError.newerVersion(2)) { try store.upsert(.sample()) }
        #expect(throws: StoreError.newerVersion(2)) { try store.update(id: "mbp") { _ in } }
        #expect(throws: StoreError.newerVersion(2)) { try store.remove(id: "mbp") }
        #expect(try String(contentsOf: store.paths.workhorsesFile, encoding: .utf8) == text)
    }

    @Test func damagedFileIsNotOverwritten() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try FileManager.default.createDirectory(at: store.paths.supportDir, withIntermediateDirectories: true)
        let bytes = Data("{ not json".utf8)
        try bytes.write(to: store.paths.workhorsesFile)
        #expect(throws: StoreError.self) { try store.load() }
        do { _ = try store.load() } catch let StoreError.unreadable(why) { #expect(why.contains("workhorses.json")) }
        #expect(throws: StoreError.self) { try store.upsert(.sample()) }
        #expect(throws: StoreError.self) { try store.save([.sample()]) }
        #expect(try Data(contentsOf: store.paths.workhorsesFile) == bytes)
        #expect(!FileManager.default.fileExists(atPath: store.paths.knownHostsFile.path))
    }

    @Test func aRecordMissingARequiredFieldCountsAsDamage() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try FileManager.default.createDirectory(at: store.paths.supportDir, withIntermediateDirectories: true)
        try Data(#"{"version":1,"workhorses":[{"id":"mbp"}]}"#.utf8).write(to: store.paths.workhorsesFile)
        #expect(throws: StoreError.self) { try store.load() }
    }

    @Test func findByIdOrName() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try store.save([
            .sample(id: "mbp", name: "MacBook Pro"),
            .sample(id: "mini", name: "Studio"),
            .sample(id: "mini-2", name: "studio"),
        ])
        #expect(try store.find("mbp").id == "mbp")
        #expect(try store.find("macbook pro").id == "mbp")
        #expect(try store.find("MACBOOK PRO").id == "mbp")
        #expect(try store.find("mini").id == "mini")          // an exact id beats names
        #expect(throws: StoreError.ambiguous("Studio")) { try store.find("Studio") }
        #expect(throws: StoreError.notFound("nope")) { try store.find("nope") }
    }

    @Test func upsertReplacesTheRecordWithTheSameId() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try store.upsert(.sample(id: "mbp", name: "Old"))
        try store.upsert(.sample(id: "mini", name: "Mini"))
        try store.upsert(.sample(id: "mbp", name: "New"))
        #expect(try store.load().map(\.name) == ["New", "Mini"])
    }

    @Test func removeAlsoDropsThePinnedKey() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try store.upsert(.sample(id: "mbp", hostKey: "ssh-ed25519 AAAA"))
        try store.upsert(.sample(id: "mini", hostKey: "ssh-ed25519 BBBB"))
        try store.remove(id: "mbp")
        #expect(try store.load().map(\.id) == ["mini"])
        #expect(try String(contentsOf: store.paths.knownHostsFile, encoding: .utf8) == "macmosh-mini ssh-ed25519 BBBB\n")
        #expect(throws: StoreError.notFound("mbp")) { try store.remove(id: "mbp") }
    }

    @Test func aHostKeyWithANewlineIsNeverWrittenAsTwoLines() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try store.upsert(.sample(id: "mbp", hostKey: "ssh-ed25519 AAAA\nother-host ssh-ed25519 EVIL"))
        let pinned = try String(contentsOf: store.paths.knownHostsFile, encoding: .utf8)
        #expect(pinned == "")
    }

    @Test func settingsDefaultToAutomaticTerminal() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        #expect(try store.loadSettings() == AppSettings(terminal: nil))
        try store.saveSettings(AppSettings(terminal: .appleTerminal))
        #expect(try store.loadSettings().terminal == .appleTerminal)
        try store.saveSettings(AppSettings(terminal: nil))
        #expect(try store.loadSettings().terminal == nil)
    }

    @Test func damagedSettingsAreNotOverwritten() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try FileManager.default.createDirectory(at: store.paths.supportDir, withIntermediateDirectories: true)
        let bytes = Data("nonsense".utf8)
        try bytes.write(to: store.paths.settingsFile)
        #expect(throws: StoreError.self) { try store.loadSettings() }
        #expect(throws: StoreError.self) { try store.saveSettings(AppSettings(terminal: .iterm2)) }
        #expect(try Data(contentsOf: store.paths.settingsFile) == bytes)
    }

    @Test func updateKeepsAChangeMadeMeanwhile() throws {
        let paths = try temporaryPaths()
        let pairing = WorkhorseStore(paths: paths)
        let checking = WorkhorseStore(paths: paths)
        try pairing.upsert(.sample(id: "mbp", paired: false))

        // A status check loads its copy, then a pair finishes in another process.
        let copy = try checking.find("mbp")
        var paired = copy
        paired.paired = true
        try pairing.upsert(paired)

        // The check now saves only the fields a report fills.
        try checking.update(id: "mbp") { $0.homeAddress = "192.168.1.20" }

        let saved = try checking.find("mbp")
        #expect(saved.paired == true)
        #expect(saved.homeAddress == "192.168.1.20")
    }

    @Test func updateOfAnUnknownIdThrows() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try store.upsert(.sample(id: "mbp"))
        #expect(throws: StoreError.notFound("ghost")) { try store.update(id: "ghost") { $0.paired = true } }
    }

    @Test func updateCannotChangeTheId() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try store.upsert(.sample(id: "mbp"))
        try store.update(id: "mbp") { $0.id = "other" }
        #expect(try store.load().map(\.id) == ["mbp"])
    }

    @Test func simultaneousSavesDoNotLoseEachOther() throws {
        let paths = try temporaryPaths()
        let count = 24
        let failures = Failures()
        // Separate store values (and so separate lock file descriptors), as two processes would have.
        DispatchQueue.concurrentPerform(iterations: count) { i in
            let store = WorkhorseStore(paths: paths)
            do { try store.upsert(.sample(id: "h\(i)", name: "Host \(i)", hostKey: "ssh-ed25519 K\(i)")) }
            catch { failures.add("\(error)") }
        }
        #expect(failures.all.isEmpty, "\(failures.all)")
        let store = WorkhorseStore(paths: paths)
        #expect(try store.load().count == count)
        let pinned = try String(contentsOf: paths.knownHostsFile, encoding: .utf8)
        #expect(pinned.split(separator: "\n").count == count)
    }

    @Test func simultaneousUpdatesOfOneRecordAllLand() throws {
        let paths = try temporaryPaths()
        try WorkhorseStore(paths: paths).upsert(.sample(id: "mbp"))
        let count = 24
        let failures = Failures()
        DispatchQueue.concurrentPerform(iterations: count) { i in
            do { try WorkhorseStore(paths: paths).update(id: "mbp") { $0.powerChanges.append("change \(i)") } }
            catch { failures.add("\(error)") }
        }
        #expect(failures.all.isEmpty, "\(failures.all)")
        #expect(try WorkhorseStore(paths: paths).find("mbp").powerChanges.count == count)
    }

    @Test func worksWhenThePathHasASpace() throws {
        let store = WorkhorseStore(paths: try temporaryPaths(withSpaceInPath: true))
        try store.upsert(.sample())
        #expect(try store.load().count == 1)
    }
}
