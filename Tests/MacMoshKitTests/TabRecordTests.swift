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

/// A stand-in for the two system calls: which process numbers exist, and each one's start time.
struct FakeProcessProbe: ProcessProbe {
    var running: [Int32: Int64]
    func exists(_ pid: Int32) -> Bool { running[pid] != nil }
    func startTime(of pid: Int32) -> Int64? { running[pid] }
}

/// When a record is trusted (menu design 8.2): only while its process exists and started when it says.
@Suite struct TabRecordLivenessTests {
    private func store(_ running: [Int32: Int64]) throws -> TabRecordStore {
        TabRecordStore(paths: try temporaryPaths(), probe: FakeProcessProbe(running: running))
    }

    private func fileExists(_ store: TabRecordStore, _ label: String) -> Bool {
        FileManager.default.fileExists(atPath: store.folder.appendingPathComponent("\(label).json").path)
    }

    @Test func aRecordWhoseProcessRunsIsLive() throws {
        let s = try store([4242: 1_800_000_000_123_456])
        try s.write(sampleTabRecord(pid: 4242, started: 1_800_000_000_123_456))
        #expect(s.liveRecords().map(\.label) == ["0123456789abcdef"])
        #expect(fileExists(s, "0123456789abcdef"))
    }

    @Test func aRecordWhoseProcessIsGoneIsDroppedAndRemoved() throws {
        let s = try store([:])
        try s.write(sampleTabRecord(pid: 4242))
        #expect(s.liveRecords().isEmpty)
        #expect(!fileExists(s, "0123456789abcdef"))
    }

    /// The same number given to a later process: the start time differs, so the record is not trusted.
    @Test func aRecordWhoseProcessNumberWasReusedIsDroppedAndRemoved() throws {
        let s = try store([4242: 1_800_000_999_000_000])
        try s.write(sampleTabRecord(pid: 4242, started: 1_800_000_000_123_456))
        #expect(s.liveRecords().isEmpty)
        #expect(!fileExists(s, "0123456789abcdef"))
    }

    @Test func aRecordWhoseStartTimeCantBeReadIsNotTrusted() throws {
        struct NoStartTime: ProcessProbe {
            func exists(_ pid: Int32) -> Bool { true }
            func startTime(of pid: Int32) -> Int64? { nil }
        }
        let s = TabRecordStore(paths: try temporaryPaths(), probe: NoStartTime())
        try s.write(sampleTabRecord())
        #expect(s.liveRecords().isEmpty)
    }

    /// 0 and below name a process group to kill(2), never one process.
    @Test(arguments: [Int32(0), -1, -4242])
    func aProcessNumberBelowOneIsNeverLive(_ pid: Int32) throws {
        let s = try store([pid: 1_800_000_000_123_456])
        try s.write(sampleTabRecord(pid: pid, started: 1_800_000_000_123_456))
        #expect(s.liveRecords().isEmpty)
    }

    @Test func liveAndDeadRecordsAreSorted() throws {
        let s = try store([1: 10, 2: 20])
        try s.write(sampleTabRecord(label: "aaaaaaaaaaaaaaaa", pid: 1, started: 10))
        try s.write(sampleTabRecord(label: "bbbbbbbbbbbbbbbb", pid: 2, started: 99))
        try s.write(sampleTabRecord(label: "cccccccccccccccc", pid: 3, started: 30))
        #expect(s.liveRecords().map(\.label) == ["aaaaaaaaaaaaaaaa"])
        #expect(s.records().map(\.label) == ["aaaaaaaaaaaaaaaa"])
    }

    @Test func aFileThatIsNotARecordIsNotRemoved() throws {
        let s = try store([:])
        try s.write(sampleTabRecord())
        try Data("not json".utf8).write(to: s.folder.appendingPathComponent("cccccccccccccccc.json"))
        #expect(s.liveRecords().isEmpty)
        #expect(fileExists(s, "cccccccccccccccc"))
    }

    // MARK: The real calls

    @Test func theRealProbeSeesThisProcessAndItsStartTime() throws {
        let probe = SystemProcessProbe()
        let me = getpid()
        #expect(probe.exists(me))
        let started = try #require(probe.startTime(of: me))
        #expect(probe.startTime(of: me) == started)
        let now = Int64(Date().timeIntervalSince1970 * 1_000_000)
        #expect(started <= now && started > now - 86_400 * 1_000_000)
    }

    @Test func theRealProbeDoesNotSeeAProcessThatEnded() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()
        let probe = SystemProcessProbe()
        #expect(!probe.exists(child.processIdentifier))
        #expect(probe.startTime(of: child.processIdentifier) == nil)
    }
}
