import Foundation
@testable import MacMoshKit

/// A stand-in `TabOpening`: records every tab it was asked to open, and answers as told.
/// Nothing here starts a terminal.
final class RecordingTabs: TabOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [TabCommand] = []
    private var names: [String] = []
    private let notice: String?
    private let failure: Error?

    init(notice: String? = nil, failure: Error? = nil) {
        self.notice = notice
        self.failure = failure
    }

    var opened: [TabCommand] { lock.withLock { commands } }
    var titles: [String] { lock.withLock { names } }

    func open(_ command: TabCommand, title: String) async throws -> String? {
        lock.withLock {
            commands.append(command)
            names.append(title)
        }
        if let failure { throw failure }
        return notice
    }
}
