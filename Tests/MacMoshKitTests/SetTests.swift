import Foundation
import Testing
@testable import MacMoshKit

@Suite struct SetTests {
    private func applied(_ key: String, _ value: String, to w: Workhorse = .sample()) throws -> Workhorse {
        var copy = w
        try WorkhorseSetting.apply(key: key, value: value, to: &copy)
        return copy
    }

    private func message(_ key: String, _ value: String) -> String? {
        var w = Workhorse.sample()
        do { try WorkhorseSetting.apply(key: key, value: value, to: &w) } catch { return "\(error)" }
        return nil
    }

    @Test func setRejectsUnknownKeysAndValues() {
        let unknown = message("colour", "red")
        #expect(unknown?.contains("name, mode, prediction, projects-folder, identity") == true)
        let mode = message("mode", "fast")
        #expect(mode?.contains("mosh, tabs, ssh") == true)
        let prediction = message("prediction", "sometimes")
        #expect(prediction?.contains("adaptive, always, never, experimental") == true)
        #expect(message("mode", "MOSH") != nil)
        #expect(message("mode", "") != nil)
        #expect(message("name", "") != nil)
        #expect(message("name", "   ") != nil)
        #expect(message("projects-folder", "a\tb") != nil)
        #expect(message("projects-folder", "a\nb") != nil)
        #expect(message("identity", "") != nil)
    }

    @Test func aRejectedChangeLeavesTheWorkhorseAsItWas() {
        var w = Workhorse.sample(mode: .tabs)
        let before = w
        #expect(throws: SettingError.self) { try WorkhorseSetting.apply(key: "mode", value: "fast", to: &w) }
        #expect(throws: SettingError.self) { try WorkhorseSetting.apply(key: "name", value: "", to: &w) }
        #expect(w == before)
    }

    @Test func setIdentityDefaultClearsIt() throws {
        let w = Workhorse.sample(identityFile: "~/.ssh/id_work")
        #expect(try applied("identity", "default", to: w).identityFile == nil)
        #expect(try applied("identity", "~/.ssh/id_other", to: w).identityFile == "~/.ssh/id_other")
    }

    @Test func nameModeAndPredictionAreSet() throws {
        #expect(try applied("name", "Workhorse").name == "Workhorse")
        #expect(try applied("name", "  Workhorse \n").name == "Workhorse")
        #expect(try applied("mode", "tabs").mode == .tabs)
        #expect(try applied("mode", "ssh").mode == .ssh)
        #expect(try applied("mode", "mosh").mode == .mosh)
        #expect(try applied("prediction", "never").prediction == .never)
        #expect(try applied("prediction", "experimental").prediction == .experimental)
    }

    @Test func theProjectsFolderIsStoredAsTyped() throws {
        #expect(try applied("projects-folder", "~/Development").projectsFolder == "~/Development")
        #expect(try applied("projects-folder", "/Users/alex/My Projects").projectsFolder == "/Users/alex/My Projects")
        let w = Workhorse.sample(projectsFolder: "~/Development")
        #expect(try applied("projects-folder", "", to: w).projectsFolder == nil)
    }

    @Test func aNameWithANewLineIsRefused() {
        #expect(message("name", "Work\nhorse") != nil)
        #expect(message("name", "Work\thorse") != nil)
    }

    @Test func theLineThatChangedIsOne() throws {
        #expect(WorkhorseSetting.describe(key: "mode", try applied("mode", "tabs")) == "mode: tabs")
        #expect(WorkhorseSetting.describe(key: "projects-folder", .sample()) == "projects-folder: not set")
        #expect(WorkhorseSetting.describe(key: "identity", .sample()) == "identity: default (MacMosh's own key)")
    }

    @Test func settingsSurviveASaveThroughTheStore() throws {
        let paths = try temporaryPaths()
        let store = WorkhorseStore(paths: paths)
        try store.upsert(.sample(id: "mbp", powerChanges: ["sudo pmset -a autorestart 1"]))
        try store.update(id: "mbp") { try? WorkhorseSetting.apply(key: "mode", value: "ssh", to: &$0) }
        let saved = try store.find("mbp")
        #expect(saved.mode == .ssh)
        #expect(saved.powerChanges == ["sudo pmset -a autorestart 1"])
    }

    // MARK: The terminal

    @Test func settingsTerminalChoosesAndClears() throws {
        var s = AppSettings()
        try WorkhorseSetting.applyTerminal("iterm2", to: &s)
        #expect(s.terminal == .iterm2)
        try WorkhorseSetting.applyTerminal("terminal", to: &s)
        #expect(s.terminal == .appleTerminal)
        try WorkhorseSetting.applyTerminal("auto", to: &s)
        #expect(s.terminal == nil)
        #expect(throws: SettingError.self) { try WorkhorseSetting.applyTerminal("kitty", to: &s) }
    }

    @Test func aBadTerminalListsTheChoices() {
        var s = AppSettings()
        do { try WorkhorseSetting.applyTerminal("kitty", to: &s) } catch {
            #expect("\(error)".contains("iterm2, terminal, auto"))
        }
    }

    @Test func theTerminalChoiceSurvivesASave() throws {
        let store = WorkhorseStore(paths: try temporaryPaths())
        var s = try store.loadSettings()
        try WorkhorseSetting.applyTerminal("terminal", to: &s)
        try store.saveSettings(s)
        #expect(try store.loadSettings().terminal == .appleTerminal)
        #expect(WorkhorseSetting.describeTerminal(try store.loadSettings()) == "terminal: terminal")
    }
}
