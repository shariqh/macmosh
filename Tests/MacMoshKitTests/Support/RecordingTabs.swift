import Foundation
@testable import MacMoshKit

/// A stand-in `TabOpening`: records every tab it was asked to open or bring forward, and answers as told.
/// Nothing here starts a terminal.
final class RecordingTabs: TabOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [TabCommand] = []
    private var names: [String] = []
    private var happened: [String] = []
    private let notice: String?
    private let failure: Error?
    private let failFrom: Int
    private let selection: Result<TabSelection, any Error>

    /// `failure` is thrown by every open from the `failFrom`th on (counting from 0); the ones before it open.
    /// `selection` is what every request to bring a tab forward gives.
    init(notice: String? = nil, failure: Error? = nil, failFrom: Int = 0,
         selection: Result<TabSelection, any Error> = .success(.selected)) {
        self.notice = notice
        self.failure = failure
        self.failFrom = failFrom
        self.selection = selection
    }

    var opened: [TabCommand] { lock.withLock { commands } }
    var titles: [String] { lock.withLock { names } }
    /// What happened, in order: `open <line>` for each tab asked for, `select <device> <terminal>` for each
    /// tab to bring forward, and whatever `note` was told.
    var events: [String] { lock.withLock { happened } }

    /// Adds a line to `events`, so a test can see where something else happened between the opens.
    func note(_ event: String) {
        lock.withLock { happened.append(event) }
    }

    func open(_ command: TabCommand, title: String) async throws -> String? {
        let index = lock.withLock {
            commands.append(command)
            names.append(title)
            happened.append("open \(command.line)")
            return commands.count - 1
        }
        if let failure, index >= failFrom { throw failure }
        return notice
    }

    func select(tty: String, terminal: TabRecord.Terminal) async throws -> TabSelection {
        note("select \(tty) \(terminal.rawValue)")
        return try selection.get()
    }
}

/// Tab records in a new temporary folder, with a stand-in for the process calls: `running` maps each
/// process number that exists to its start time.
func scratchTabRecords(running: [Int32: Int64] = [:]) -> TabRecordStore {
    TabRecordStore(paths: try! temporaryPaths(), probe: FakeProcessProbe(running: running))
}
