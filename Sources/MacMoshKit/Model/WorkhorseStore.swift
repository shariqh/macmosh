import Foundation

public enum StoreError: Error, Equatable {
    case notFound(String)
    case ambiguous(String)
    case newerVersion(Int)
    case unreadable(String)
}

/// The saved list of workhorses and the app's settings, in `Paths.supportDir`.
///
/// `workhorses.json` is `{"version": 1, "workhorses": [...]}`. Files are written to a temporary
/// file and renamed, at mode 0600, in a folder at mode 0700. A file that is damaged or from a
/// newer version is reported and never overwritten. Every change takes an exclusive `flock` on
/// `supportDir/lock` around read, change and write, so two `macmosh` processes can't lose each
/// other's changes.
public struct WorkhorseStore: Sendable {
    public static let fileVersion = 1

    public let paths: Paths

    public init(paths: Paths) {
        self.paths = paths
    }

    // MARK: Workhorses

    public func load() throws -> [Workhorse] {
        try readList()
    }

    public func save(_ list: [Workhorse]) throws {
        try locked {
            _ = try readList()   // refuse to overwrite a damaged or newer file
            try writeList(list)
        }
    }

    /// An exact id, or else a name without regard to case. Two names that match throw `.ambiguous`.
    public func find(_ idOrName: String) throws -> Workhorse {
        let list = try readList()
        if let exact = list.first(where: { $0.id == idOrName }) { return exact }
        let matches = list.filter { $0.name.caseInsensitiveCompare(idOrName) == .orderedSame }
        switch matches.count {
        case 0: throw StoreError.notFound(idOrName)
        case 1: return matches[0]
        default: throw StoreError.ambiguous(idOrName)
        }
    }

    /// Replaces the record with the same id, or adds it at the end.
    public func upsert(_ workhorse: Workhorse) throws {
        try locked {
            var list = try readList()
            if let i = list.firstIndex(where: { $0.id == workhorse.id }) {
                list[i] = workhorse
            } else {
                list.append(workhorse)
            }
            try writeList(list)
        }
    }

    /// Reads the saved record, applies `change`, and saves, all under the lock. Use this rather
    /// than `upsert` for a change to some fields, so a change another process made in between survives.
    /// The id can't be changed.
    public func update(id: String, _ change: (inout Workhorse) -> Void) throws {
        try locked {
            var list = try readList()
            guard let i = list.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound(id) }
            change(&list[i])
            list[i].id = id
            try writeList(list)
        }
    }

    /// Removes the record and its pinned key.
    public func remove(id: String) throws {
        try locked {
            var list = try readList()
            guard let i = list.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound(id) }
            list.remove(at: i)
            try writeList(list)
        }
    }

    // MARK: Settings

    public func loadSettings() throws -> AppSettings {
        guard let data = try readFile(paths.settingsFile) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            throw StoreError.unreadable("\(paths.settingsFile.lastPathComponent): \(Self.describe(error))")
        }
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try locked {
            _ = try loadSettings()   // refuse to overwrite a damaged file
            let encoder = Self.makeEncoder()
            try writeFile(paths.settingsFile, try encoder.encode(settings))
        }
    }

    // MARK: Reading and writing

    private struct Header: Decodable { var version: Int }
    private struct Envelope: Codable { var version: Int; var workhorses: [Workhorse] }

    private func readList() throws -> [Workhorse] {
        let name = paths.workhorsesFile.lastPathComponent
        guard let data = try readFile(paths.workhorsesFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header: Header
        do { header = try decoder.decode(Header.self, from: data) } catch {
            throw StoreError.unreadable("\(name): \(Self.describe(error))")
        }
        if header.version > Self.fileVersion { throw StoreError.newerVersion(header.version) }
        if header.version < 1 { throw StoreError.unreadable("\(name): version \(header.version) is not known") }
        do { return try decoder.decode(Envelope.self, from: data).workhorses } catch {
            throw StoreError.unreadable("\(name): \(Self.describe(error))")
        }
    }

    private func writeList(_ list: [Workhorse]) throws {
        let data = try Self.makeEncoder().encode(Envelope(version: Self.fileVersion, workhorses: list))
        try writeFile(paths.workhorsesFile, data)
        // One pinned key per workhorse, under its alias. A key with a line break in it would
        // write a second, forged entry, so such a key is left out (ssh then refuses the host).
        let lines = list.compactMap { w -> String? in
            guard !w.hostKey.isEmpty, !w.hostKey.contains(where: \.isNewline) else { return nil }
            return "\(w.hostKeyAlias) \(w.hostKey)\n"
        }
        try writeFile(paths.knownHostsFile, Data(lines.joined().utf8))
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? DecodingError {
            switch e {
            case .dataCorrupted(let c): return c.debugDescription
            case .keyNotFound(let k, _): return "missing \"\(k.stringValue)\""
            case .typeMismatch(_, let c), .valueNotFound(_, let c): return c.debugDescription
            @unknown default: return "not readable"
            }
        }
        return error.localizedDescription
    }

    /// The file's bytes, or nil when there is no such file.
    private func readFile(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        } catch {
            throw StoreError.unreadable("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Writes a temporary file beside `url` at mode 0600 and renames it into place.
    private func writeFile(_ url: URL, _ data: Data) throws {
        let fm = FileManager.default
        try ensureSupportDir()
        let temporary = paths.supportDir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw StoreError.unreadable("could not write \(url.lastPathComponent)")
        }
        if rename(temporary.path, url.path) != 0 {
            let code = errno
            try? fm.removeItem(at: temporary)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }

    private func ensureSupportDir() throws {
        // Created at 0700 from the start; the second call fixes a folder that already existed.
        try FileManager.default.createDirectory(at: paths.supportDir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: paths.supportDir.path)
    }

    // MARK: Lock

    private func locked<T>(_ body: () throws -> T) throws -> T {
        try ensureSupportDir()
        let fd = open(paths.supportDir.appendingPathComponent("lock").path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }   // closing also releases the lock
        while flock(fd, LOCK_EX) != 0 {
            if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        return try body()
    }
}
