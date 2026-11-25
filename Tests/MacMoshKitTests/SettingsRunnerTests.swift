import Foundation
import Testing
@testable import MacMoshKit

/// The Settings page's saves (issue 157): one field of one workhorse, or the terminal, through `WorkhorseSetting`
/// and the store's lock, in a temporary folder only.
@MainActor @Suite struct SettingsRunnerTests {
    private let attic = Workhorse.sample(id: "attic", name: "Attic", homeAddress: "192.168.1.20",
                                         projectsFolder: "~/Development")
    private let spare = Workhorse.sample(id: "spare", name: "Spare", mode: .tabs)

    private struct Rig {
        let paths: Paths
        let store: WorkhorseStore
        let runner: SettingsRunner
        let log: Box<[String]>
        let reloaded: Box<Int>
    }

    private func rig(_ list: [Workhorse]? = nil, keyFiles: Set<String> = []) async throws -> Rig {
        let paths = try temporaryPaths()
        let store = WorkhorseStore(paths: paths)
        try store.save(list ?? [attic, spare])
        let log = Box<[String]>([]), reloaded = Box(0)
        let runner = SettingsRunner(store: store, home: "/Users/alex", keyFileExists: { keyFiles.contains($0) },
                                    pickForMe: { .iterm2 }, log: { line in log.value.append(line) },
                                    saved: { reloaded.value += 1 })
        await runner.reload()
        return Rig(paths: paths, store: store, runner: runner, log: log, reloaded: reloaded)
    }

    /// The saved list's fields as JSON objects, to show exactly which changed.
    private func fields(_ store: WorkhorseStore) throws -> [String: [String: String]] {
        let data = try Data(contentsOf: store.paths.workhorsesFile)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let list = object?["workhorses"] as? [[String: Any]] ?? []
        var out: [String: [String: String]] = [:]
        for w in list {
            out[w["id"] as? String ?? "?"] = w.mapValues { "\($0)" }
        }
        return out
    }

    private func changed(_ before: [String: [String: String]], _ after: [String: [String: String]]) -> [String] {
        var keys: [String] = []
        for (id, fields) in after {
            let old = before[id] ?? [:]
            for key in Set(fields.keys).union(old.keys).sorted() where fields[key] != old[key] {
                keys.append("\(id).\(key)")
            }
        }
        return keys.sorted()
    }

    @Test func theRunnerReadsTheSavedListAndTheSettings() async throws {
        let r = try await rig()
        try r.store.saveSettings(AppSettings(terminal: .appleTerminal))
        await r.runner.reload()
        let page = r.runner.page
        #expect(page.workhorses.map(\.id) == ["attic", "spare"])
        #expect(page.thisMac.chosen == "terminal")
        #expect(page.thisMac.pickLine.hasSuffix("On this Mac that is iTerm2."))
    }

    // MARK: Each setting's save

    private func save(_ r: Rig, _ field: SettingField, _ id: String, _ typed: String) async throws
        -> (outcome: SettingOutcome, changed: [String]) {
        let before = try fields(r.store)
        let outcome = await r.runner.save(field, of: id, typed: typed)
        return (outcome, changed(before, try fields(r.store)))
    }

    @Test func aNameIsSavedAndOnlyThatFieldChanges() async throws {
        let r = try await rig()
        let (outcome, changed) = try await save(r, .name, "attic", "Loft")
        #expect(outcome == .saved(SettingLine(field: .name, words: "Saved. The menu shows it at its next check.", isProblem: false)))
        #expect(changed == ["attic.name"])
        #expect(try r.store.find("attic").name == "Loft")
        #expect(r.runner.page.workhorses[0].heading == "Loft")
        #expect(r.runner.page.workhorses[0].under(.name)?.words == "Saved. The menu shows it at its next check.")
        #expect(r.log.value == ["window action: setting ok"])
        // The window's board is asked to read the list again, so the sidebar shows the name at once.
        #expect(r.reloaded.value == 1)
    }

    @Test func connectionAndPredictionAreSavedWhenClicked() async throws {
        let r = try await rig()
        for mode in ["tabs", "ssh", "mosh"] {
            let (outcome, changed) = try await save(r, .connection, "attic", mode)
            #expect(outcome == .saved(SettingLine(field: .connection, words: "Saved. Used by the next tab you open on a desk.",
                                                  isProblem: false)))
            #expect(changed == ["attic.mode"])
            #expect(try r.store.find("attic").mode.rawValue == mode)
        }
        for p in ["always", "never", "experimental", "adaptive"] {
            let (outcome, changed) = try await save(r, .prediction, "attic", p)
            #expect(outcome == .saved(SettingLine(field: .prediction, words: "Saved. Used by the next Mosh tab you open.",
                                                  isProblem: false)))
            #expect(changed == ["attic.prediction"])
            #expect(try r.store.find("attic").prediction.rawValue == p)
        }
        #expect(r.log.value == Array(repeating: "window action: setting ok", count: 7))
    }

    @Test func theProjectsFolderIsSavedThenEmptied() async throws {
        let r = try await rig()
        var (outcome, changed) = try await save(r, .projectsFolder, "spare", " ~/Projects ")
        #expect(outcome == .saved(SettingLine(field: .projectsFolder, words: "Saved. Used by the next New desk.", isProblem: false)))
        #expect(changed == ["spare.projectsFolder"])
        #expect(try r.store.find("spare").projectsFolder == "~/Projects")
        (outcome, changed) = try await save(r, .projectsFolder, "spare", "")
        #expect(outcome == .saved(SettingLine(field: .projectsFolder,
                                              words: "Saved. New desk has no folders to list until it is set.", isProblem: false)))
        #expect(changed == ["spare.projectsFolder"])
        #expect(try r.store.find("spare").projectsFolder == nil)
    }

    @Test func aKeyFileIsSavedAsTypedAndEmptiedToMacMoshsOwn() async throws {
        let r = try await rig(keyFiles: ["/Users/alex/.ssh/id_work"])
        var (outcome, changed) = try await save(r, .keyFile, "attic", "~/.ssh/id_work")
        #expect(outcome == .saved(SettingLine(field: .keyFile, words: "Saved. Used for Attic from the next check on.", isProblem: false)))
        #expect(changed == ["attic.identityFile"])
        #expect(try r.store.find("attic").identityFile == "~/.ssh/id_work")
        (outcome, changed) = try await save(r, .keyFile, "attic", "")
        #expect(outcome == .saved(SettingLine(field: .keyFile, words: "Saved. MacMosh's own key is used from the next check on.",
                                              isProblem: false)))
        #expect(changed == ["attic.identityFile"])
        #expect(try r.store.find("attic").identityFile == nil)
    }

    @Test func theTerminalIsSavedInEachOfItsValues() async throws {
        let r = try await rig()
        for (value, stored) in [("iterm2", TerminalApp.iterm2), ("terminal", .appleTerminal)] {
            let outcome = await r.runner.chooseTerminal(value)
            #expect(outcome == .saved(SettingLine(field: .terminal, words: "Saved. Used by the next tab MacMosh opens.", isProblem: false)))
            #expect(try r.store.loadSettings().terminal == stored)
            #expect(r.runner.page.thisMac.chosen == value)
        }
        _ = await r.runner.chooseTerminal("auto")
        #expect(try r.store.loadSettings().terminal == nil)
        #expect(r.runner.page.thisMac.line?.words == "Saved. Used by the next tab MacMosh opens.")
        // The saved list is not touched by the terminal.
        #expect(try r.store.load() == [attic, spare])
        #expect(r.log.value == Array(repeating: "window action: setting ok", count: 3))
    }

    /// The page opened again forgets the last changes' lines; the next save sets only its own section's.
    @Test func openingThePageAgainClearsTheLinesAndTheNextSaveSetsOnlyItsOwn() async throws {
        let r = try await rig()
        _ = await r.runner.save(.name, of: "attic", typed: "Loft")
        _ = await r.runner.chooseTerminal("iterm2")
        #expect(r.runner.lines.count == 2)
        await r.runner.reload(clearingLines: true)
        #expect(r.runner.lines.isEmpty)
        _ = await r.runner.save(.connection, of: "spare", typed: "mosh")
        #expect(Array(r.runner.lines.keys) == ["spare"])
        #expect(r.runner.page.workhorses.map { $0.line?.field } == [nil, .connection])
        #expect(r.runner.page.thisMac.line == nil)
    }

    // MARK: Refusals

    @Test func anEmptyNameSavesNothingAndSaysWhy() async throws {
        let r = try await rig()
        let bytes = try Data(contentsOf: r.paths.workhorsesFile)
        let (outcome, changed) = try await save(r, .name, "attic", "  ")
        #expect(outcome == .refused(SettingLine(field: .name, words: "The name can't be empty.", isProblem: true)))
        #expect(changed.isEmpty)
        #expect(try Data(contentsOf: r.paths.workhorsesFile) == bytes)
        #expect(r.runner.page.workhorses[0].under(.name)?.words == "The name can't be empty.")
        #expect(r.runner.page.workhorses[0].name == "Attic")
        #expect(r.log.value == ["window action: setting failed"])
    }

    @Test func aKeyFileWithNoFileSavesNothing() async throws {
        let r = try await rig()
        let bytes = try Data(contentsOf: r.paths.workhorsesFile)
        let (outcome, _) = try await save(r, .keyFile, "attic", "~/.ssh/id_typo")
        #expect(outcome == .refused(SettingLine(field: .keyFile, words: "There is no file at ~/.ssh/id_typo on this Mac, so it was not saved.",
                                                isProblem: true)))
        #expect(try Data(contentsOf: r.paths.workhorsesFile) == bytes)
        let relative = await r.runner.save(.keyFile, of: "attic", typed: "keys/work")
        #expect(relative == .refused(SettingLine(field: .keyFile, words: "A key file's path is full, starting with /, or starts with ~.",
                                                 isProblem: true)))
        #expect(try Data(contentsOf: r.paths.workhorsesFile) == bytes)
    }

    /// The page was shown with Den on it, then Den was taken off the list (by `macmosh remove`, say): nothing is
    /// written, and the page says so in one line.
    @Test func aWorkhorseRemovedBeforeTheClickIsNotWritten() async throws {
        let den = Workhorse.sample(id: "den", name: "Den")
        let r = try await rig([attic, den])
        #expect(r.runner.page.workhorses.map(\.id) == ["attic", "den"])
        try r.store.remove(id: "den")
        let bytes = try Data(contentsOf: r.paths.workhorsesFile)
        let outcome = await r.runner.save(.connection, of: "den", typed: "ssh")
        #expect(outcome == .refused(SettingLine(field: .connection, words: "Den is no longer on MacMosh's list, so nothing was saved.",
                                                isProblem: true)))
        #expect(try Data(contentsOf: r.paths.workhorsesFile) == bytes)
        #expect(try r.store.load().map(\.id) == ["attic"])
        #expect(r.runner.page.workhorses.map(\.id) == ["attic"])
        #expect(r.runner.page.notices == ["Den is no longer on MacMosh's list, so nothing was saved."])
        #expect(r.log.value == ["window action: setting failed"])
    }

    @Test func aFieldLeftUnchangedSavesNothingAndLogsNothing() async throws {
        let r = try await rig()
        let bytes = try Data(contentsOf: r.paths.workhorsesFile)
        #expect(await r.runner.save(.name, of: "attic", typed: "Attic") == .unchanged)
        #expect(await r.runner.save(.projectsFolder, of: "attic", typed: "~/Development") == .unchanged)
        #expect(await r.runner.save(.keyFile, of: "attic", typed: "") == .unchanged)
        #expect(await r.runner.save(.connection, of: "spare", typed: "tabs") == .unchanged)
        #expect(await r.runner.chooseTerminal("auto") == .unchanged)
        #expect(try Data(contentsOf: r.paths.workhorsesFile) == bytes)
        #expect(!FileManager.default.fileExists(atPath: r.paths.settingsFile.path))
        #expect(r.log.value.isEmpty)
        #expect(r.runner.page.workhorses.allSatisfy { $0.line == nil })
    }

    @Test func anUnreadableListSavesNothingAndGivesTheStoresSentence() async throws {
        let r = try await rig()
        try Data("not JSON".utf8).write(to: r.paths.workhorsesFile)
        let outcome = await r.runner.save(.name, of: "attic", typed: "Loft")
        guard case .refused(let line) = outcome else { Issue.record("not refused: \(outcome)"); return }
        #expect(line.words.hasPrefix("Can't read MacMosh's saved settings: workhorses.json:"))
        #expect(try Data(contentsOf: r.paths.workhorsesFile) == Data("not JSON".utf8))
        #expect(r.runner.page.none?.hasPrefix("Can't read MacMosh's saved settings") == true)
    }

    // MARK: Beside a background check

    /// A check's `absorb` writes the report's fields; a save writes one setting. Both go through `update` under the
    /// store's lock, so in either order, and at the same moment, the file ends with both, and `lastDeskCommand`
    /// stays.
    @Test func aSaveAndACheckForTheSameWorkhorseKeepBothWritesInEitherOrder() async throws {
        var start = attic
        start.lastDeskCommand = "claude --continue"
        let r = try await rig([start, spare])
        let seen = Date(timeIntervalSince1970: 1_800_000_000)
        func report(_ address: String) -> CheckResult {
            var w = attic
            w.homeAddress = address
            w.lastSeen = seen
            return CheckResult(workhorse: w, state: .ready(signIns: true), status: HostStatus.sampleWithDesk,
                               probes: ProbeSet(), answeredAt: address, homeReachable: true, checkedAt: seen)
        }
        // The check first, then the save.
        try r.store.absorb(report("192.168.1.21"))
        _ = await r.runner.save(.name, of: "attic", typed: "Loft")
        var w = try r.store.find("attic")
        #expect(w.name == "Loft" && w.homeAddress == "192.168.1.21" && w.lastSeen == seen)
        #expect(w.lastDeskCommand == "claude --continue")
        // The save first, then the check, whose workhorse still has the old name and folder.
        _ = await r.runner.save(.projectsFolder, of: "attic", typed: "~/Projects")
        try r.store.absorb(report("192.168.1.22"))
        w = try r.store.find("attic")
        #expect(w.name == "Loft" && w.projectsFolder == "~/Projects" && w.homeAddress == "192.168.1.22")
        #expect(w.lastDeskCommand == "claude --continue")
        // At the same moment, many times over: every save and every check lands.
        let store = r.store
        for round in 0..<20 {
            let address = "192.168.1.\(30 + round)"
            let result = report(address)
            let check = Task.detached { try store.absorb(result) }
            let value = round.isMultiple(of: 2) ? "never" : "always"
            _ = await r.runner.save(.prediction, of: "attic", typed: value)
            try await check.value
            w = try r.store.find("attic")
            #expect(w.prediction.rawValue == value && w.homeAddress == address)
            #expect(w.name == "Loft" && w.projectsFolder == "~/Projects" && w.lastDeskCommand == "claude --continue")
        }
        // Spare was never touched.
        #expect(try r.store.find("spare") == spare)
    }

    /// The runner's own write, under the lock, re-reads the record, so a field another process changed since the
    /// page was shown is kept.
    @Test func aChangeMadeElsewhereSinceThePageWasShownIsKept() async throws {
        let r = try await rig()
        try r.store.update(id: "attic") { $0.mode = .ssh }   // `macmosh set attic mode ssh`, say
        _ = await r.runner.save(.name, of: "attic", typed: "Loft")
        let w = try r.store.find("attic")
        #expect(w.name == "Loft" && w.mode == .ssh)
    }
}
