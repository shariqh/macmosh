import Foundation
import Testing
@testable import MacMoshKit

/// A record as `connect` would write it, every field named so a test changes only the ones it cares about.
func sampleTabRecord(label: String = "0123456789abcdef", workhorse: String = "mbp", desk: String = "website",
                     askedWindow: String = "@3", pid: Int32 = 4242, started: Int64 = 1_800_000_000_123_456,
                     tty: String = "/dev/ttys004", terminal: TabRecord.Terminal = .iterm2,
                     openedAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> TabRecord {
    TabRecord(label: label, workhorse: workhorse, desk: desk, askedWindow: askedWindow, pid: pid, started: started,
              tty: tty, terminal: terminal, openedAt: openedAt)
}

private func mode(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

/// The tab record (menu design 8.1): one small JSON file per tab under `<support folder>/tabs/`.
/// Every test uses a temporary support folder.
@Suite struct TabRecordTests {
    @Test func theFolderIsTabsInTheSupportFolder() throws {
        let paths = try temporaryPaths()
        #expect(paths.tabsDir == paths.supportDir.appendingPathComponent("tabs", isDirectory: true))
        #expect(TabRecordStore(paths: paths).folder == paths.tabsDir)
    }

    @Test func aWrittenRecordIsReadBack() throws {
        let store = TabRecordStore(paths: try temporaryPaths())
        let record = sampleTabRecord()
        try store.write(record)
        #expect(store.records() == [record])
    }

    @Test func theFileIsNamedByItsLabelAndHoldsTheDesignsFields() throws {
        let store = TabRecordStore(paths: try temporaryPaths())
        try store.write(sampleTabRecord(label: "00ff00ff00ff00ff"))
        let file = store.folder.appendingPathComponent("00ff00ff00ff00ff.json")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(Set(object.keys) == ["label", "workhorse", "desk", "askedWindow", "pid", "started", "tty",
                                     "terminal", "openedAt"])
        #expect(object["label"] as? String == "00ff00ff00ff00ff")
        #expect(object["workhorse"] as? String == "mbp")
        #expect(object["askedWindow"] as? String == "@3")
        #expect(object["terminal"] as? String == "iterm2")
        #expect((object["pid"] as? NSNumber)?.intValue == 4242)
    }

    @Test func onlyThePersonCanReadTheFolderAndTheFile() throws {
        let paths = try temporaryPaths()
        let store = TabRecordStore(paths: paths)
        try store.write(sampleTabRecord())
        #expect(try mode(store.folder) == 0o700)
        #expect(try mode(store.folder.appendingPathComponent("0123456789abcdef.json")) == 0o600)
    }

    @Test func aFolderThatOthersCouldReadIsMadePrivate() throws {
        let paths = try temporaryPaths()
        try FileManager.default.createDirectory(at: paths.tabsDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        try TabRecordStore(paths: paths).write(sampleTabRecord())
        #expect(try mode(paths.tabsDir) == 0o700)
    }

    /// Written in one move: nothing but the record is left in the folder, and writing again replaces it whole.
    @Test func aRecordIsWrittenInOneMove() throws {
        let store = TabRecordStore(paths: try temporaryPaths())
        try store.write(sampleTabRecord(desk: "website"))
        try store.write(sampleTabRecord(desk: "notes"))
        let names = try FileManager.default.contentsOfDirectory(atPath: store.folder.path)
        #expect(names == ["0123456789abcdef.json"])
        #expect(store.records().map(\.desk) == ["notes"])
    }

    @Test func aLabelThatBreaksTheRuleIsNotWritten() throws {
        let paths = try temporaryPaths()
        let store = TabRecordStore(paths: paths)
        for bad in ["../escape", "ABCDEF12", "abc", ""] {
            #expect(throws: (any Error).self) { try store.write(sampleTabRecord(label: bad)) }
        }
        #expect(store.records().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: paths.supportDir.appendingPathComponent("escape.json").path))
    }

    @Test func removingARecordDeletesItsFile() throws {
        let store = TabRecordStore(paths: try temporaryPaths())
        try store.write(sampleTabRecord(label: "aaaaaaaaaaaaaaaa"))
        try store.write(sampleTabRecord(label: "bbbbbbbbbbbbbbbb"))
        store.remove(label: "aaaaaaaaaaaaaaaa")
        #expect(store.records().map(\.label) == ["bbbbbbbbbbbbbbbb"])
        store.remove(label: "aaaaaaaaaaaaaaaa")   // already gone: nothing happens
        store.remove(label: "../bbbbbbbbbbbbbbbb")   // not a label: nothing happens
        #expect(store.records().map(\.label) == ["bbbbbbbbbbbbbbbb"])
    }

    @Test func aMissingFolderHasNoRecords() throws {
        #expect(TabRecordStore(paths: try temporaryPaths()).records().isEmpty)
    }

    /// A file that is not a record is ignored and left where it is.
    @Test func aFileThatIsNotARecordIsIgnored() throws {
        let store = TabRecordStore(paths: try temporaryPaths())
        try store.write(sampleTabRecord())
        let fm = FileManager.default
        try Data("not json".utf8).write(to: store.folder.appendingPathComponent("cccccccccccccccc.json"))
        try Data("{}".utf8).write(to: store.folder.appendingPathComponent("dddddddddddddddd.json"))
        try Data("notes".utf8).write(to: store.folder.appendingPathComponent("notes.txt"))
        try fm.createDirectory(at: store.folder.appendingPathComponent("eeeeeeeeeeeeeeee.json"),
                               withIntermediateDirectories: false)
        // A record whose label is not its file's name.
        let other = try JSONEncoder.tabRecord.encode(sampleTabRecord(label: "ffffffffffffffff"))
        try other.write(to: store.folder.appendingPathComponent("1111111111111111.json"))

        #expect(store.records().map(\.label) == ["0123456789abcdef"])
        #expect(try fm.contentsOfDirectory(atPath: store.folder.path).count == 6)
    }

    @Test(arguments: [("iTerm.app", TabRecord.Terminal.iterm2), ("Apple_Terminal", .terminal),
                      ("vscode", .unknown), ("", .unknown)])
    func theTerminalComesFromTermProgram(_ value: String, _ expected: TabRecord.Terminal) {
        #expect(TabRecord.Terminal(environment: ["TERM_PROGRAM": value]) == expected)
        #expect(TabRecord.Terminal(environment: [:]) == .unknown)
    }
}
