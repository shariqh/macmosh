import Foundation

/// A note of one terminal tab that `macmosh connect` opened with a window option (menu design 8.1): which
/// label it carries, which process holds it open, and which terminal device it is. The menu joins it to the
/// report's `view` lines by label to find which tab shows which window.
public struct TabRecord: Codable, Sendable, Equatable {
    /// Which terminal app the tab is in, from `TERM_PROGRAM`.
    public enum Terminal: String, Codable, Sendable {
        case iterm2, terminal, unknown

        /// `iterm2` when `TERM_PROGRAM` is `iTerm.app`, `terminal` when it is `Apple_Terminal`, else `unknown`.
        public init(environment: [String: String]) {
            switch environment["TERM_PROGRAM"] {
            case "iTerm.app": self = .iterm2
            case "Apple_Terminal": self = .terminal
            default: self = .unknown
            }
        }

        /// A value this version doesn't know reads as `unknown`, so the record is still read.
        public init(from decoder: Decoder) throws {
            self = Terminal(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public var label: String
    /// The workhorse's id.
    public var workhorse: String
    /// The desk's name when the tab opened. For logs only: a rename changes it, so it is never used to join.
    public var desk: String
    /// The window asked for (`@n`), or empty for `--new-window` and `--view`.
    public var askedWindow: String
    /// Which option the tab was opened with: `window`, `new-window` or `view` (`TabTarget.recordWord`). nil in
    /// a record an older version wrote, which has no such key. The menu reads it to tell a fresh `--view` tab
    /// from a `--new-window` one, whose `askedWindow` are both empty (menu design 8.2).
    public var target: String?
    /// The process that stays alive for as long as the tab is connected, and its start time in
    /// microseconds since 1970. Both must still match for the record to be trusted.
    public var pid: Int32
    public var started: Int64
    /// The tab's terminal device, or empty when standard input isn't a terminal.
    public var tty: String
    public var terminal: Terminal
    public var openedAt: Date

    public init(label: String, workhorse: String, desk: String, askedWindow: String, target: String? = nil,
                pid: Int32, started: Int64, tty: String, terminal: Terminal, openedAt: Date) {
        self.label = label
        self.workhorse = workhorse
        self.desk = desk
        self.askedWindow = askedWindow
        self.target = target
        self.pid = pid
        self.started = started
        self.tty = tty
        self.terminal = terminal
        self.openedAt = openedAt
    }

    /// True for `/dev/ttys` followed by one or more digits 0 to 9, the shape of a terminal tab's device. Only
    /// such a device is handed to a terminal to find its tab; anything else counts as a tab that has gone.
    /// Compared one Unicode scalar at a time, so no look-alike or combining mark passes.
    public static func isTerminalDevice(_ tty: String) -> Bool {
        let prefix = Array("/dev/ttys".unicodeScalars)
        let scalars = Array(tty.unicodeScalars)
        guard scalars.count > prefix.count, Array(scalars.prefix(prefix.count)) == prefix else { return false }
        return scalars.dropFirst(prefix.count).allSatisfy { ("0"..."9").contains($0) }
    }
}

extension JSONEncoder {
    /// How a tab record is written: dates as ISO 8601, keys sorted so a file reads the same each time.
    static var tabRecord: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var tabRecord: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum TabRecordError: Error, Equatable {
    /// The label breaks `TabLabel`'s rule, so it can't name a file.
    case badLabel(String)
    /// A system call failed while writing; the number is `errno`.
    case writeFailed(String, Int32)
}

/// The tab records on this Mac: one file per tab in `<support folder>/tabs/`, named `<label>.json`. The folder
/// is the person's only (0700) and so is each file (0600). A file is written whole under another name and
/// then renamed into place, so a reader never sees half a record.
public struct TabRecordStore: Sendable {
    public let folder: URL
    private let probe: any ProcessProbe

    public init(paths: Paths, probe: any ProcessProbe = SystemProcessProbe()) {
        self.folder = paths.tabsDir
        self.probe = probe
    }

    /// The records that can be trusted, oldest opened first (menu design 8.2): those whose process still
    /// exists and started when the record says. Every other record is removed. The terminal device alone is
    /// never trusted, because nothing says a later tab can't get the same one.
    public func liveRecords() -> [TabRecord] {
        records().filter { record in
            if isLive(record) { return true }
            remove(label: record.label)
            return false
        }
    }

    func isLive(_ record: TabRecord) -> Bool {
        // 0 and below name a process group to kill(2), never one process.
        record.pid > 0 && probe.exists(record.pid) && probe.startTime(of: record.pid) == record.started
    }

    /// Writes (or replaces) the record's file.
    ///
    /// The file is made with `open(O_CREAT | O_EXCL)` and mode 0600 under a temporary name in the same
    /// folder, then moved with `rename(2)`, which "guarantees that an instance of new will always exist,
    /// even if the system should crash in the middle of the operation" (rename(2), this Mac's manual).
    public func write(_ record: TabRecord) throws {
        guard TabLabel.isValid(record.label) else { throw TabRecordError.badLabel(record.label) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        guard chmod(folder.path, 0o700) == 0 else { throw TabRecordError.writeFailed("chmod", errno) }

        let data = try JSONEncoder.tabRecord.encode(record)
        let final = file(for: record.label)
        // A process killed between open and rename leaves this file behind. It is never read (records() reads
        // only `.json`) and stays small; nothing removes it yet.
        let temporary = folder.appendingPathComponent(".\(record.label).\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw TabRecordError.writeFailed("open", errno) }
        var failure: TabRecordError?
        // The mode given to open is narrowed by the umask; set it exactly.
        if fchmod(fd, 0o600) != 0 { failure = .writeFailed("fchmod", errno) }
        if failure == nil {
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < raw.count {
                    let n = Darwin.write(fd, base + offset, raw.count - offset)
                    if n > 0 {
                        offset += n
                    } else if n < 0 && errno == EINTR {
                        continue
                    } else {
                        failure = .writeFailed("write", n == 0 ? EIO : errno)
                        break
                    }
                }
            }
        }
        close(fd)
        if failure == nil, rename(temporary.path, final.path) != 0 { failure = .writeFailed("rename", errno) }
        if let failure {
            unlink(temporary.path)
            throw failure
        }
    }

    /// Removes the record with this label. Nothing happens when there is none, or the word isn't a label.
    public func remove(label: String) {
        guard TabLabel.isValid(label) else { return }
        unlink(file(for: label).path)
    }

    /// Every record in the folder, oldest opened first. A file that isn't a record (not JSON, not this shape,
    /// or a label that isn't its file's name) is ignored and left alone; a missing folder has none.
    func records() -> [TabRecord] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let found = names.filter { $0.hasSuffix(".json") }.compactMap { record(label: String($0.dropLast(".json".count))) }
        return found.sorted { ($0.openedAt, $0.label) < ($1.openedAt, $1.label) }
    }

    /// The record with this label, whether or not its process still runs. nil when the word isn't a label,
    /// or there is no such file, or the file isn't a record carrying that label.
    public func record(label: String) -> TabRecord? {
        guard TabLabel.isValid(label),
              let data = try? Data(contentsOf: file(for: label)),
              let record = try? JSONDecoder.tabRecord.decode(TabRecord.self, from: data),
              record.label == label else { return nil }
        return record
    }

    private func file(for label: String) -> URL { folder.appendingPathComponent("\(label).json") }
}
