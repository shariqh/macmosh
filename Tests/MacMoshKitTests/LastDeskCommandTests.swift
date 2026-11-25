import Foundation
import Testing
@testable import MacMoshKit

/// `Workhorse.lastDeskCommand` (main window design, section 7.3): the command the window's New desk form
/// last sent, the next form's default. Optional, so a file saved before it existed still loads.
@Suite struct LastDeskCommandTests {
    @Test func aFileSavedBeforeItExistedLoadsWithNone() throws {
        let json = #"{"id":"attic","name":"Attic","user":"alex","mainAddress":"workhorse","hostKey":"ssh-ed25519 AAAA","projectsFolder":"~/Development"}"#
        let w = try JSONDecoder().decode(Workhorse.self, from: Data(json.utf8))
        #expect(w.lastDeskCommand == nil)
        #expect(w.projectsFolder == "~/Development")
    }

    @Test func itIsSavedAndReadBack() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        var w = Workhorse.sample(id: "attic", name: "Attic")
        w.lastDeskCommand = "claude --continue"
        try store.save([w])
        #expect(try store.load().first?.lastDeskCommand == "claude --continue")
    }

    @Test func noneIsNotWrittenAtAll() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        try store.save([.sample(id: "attic", name: "Attic")])
        let text = try String(contentsOf: store.paths.workhorsesFile, encoding: .utf8)
        #expect(!text.contains("lastDeskCommand"))
    }

    /// A background check writes only the fields a report fills, so it never undoes the form's save.
    @Test func aCheckThatIsSavedLeavesItAlone() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        var w = Workhorse.sample(id: "attic", name: "Attic")
        w.lastDeskCommand = "claude --continue"
        try store.save([w])
        var learned = Workhorse.sample(id: "attic", name: "Attic", osVersion: "26.1")
        learned.lastDeskCommand = nil
        try store.absorb(.sample(.ready(signIns: true), workhorse: learned, status: .sampleWithDesk))
        #expect(try store.load().first?.lastDeskCommand == "claude --continue")
        #expect(try store.load().first?.osVersion == "26.1")
    }
}
