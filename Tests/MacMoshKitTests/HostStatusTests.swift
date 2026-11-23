import Foundation
import Testing
@testable import MacMoshKit

/// The report from "Shared interfaces", with tabs between the fields.
private func fullReport() throws -> String { try fixture("status/full.txt") }

/// A report with the given record lines between the header and `end`. Fields are joined with tabs.
private func report(_ records: [[String]], protocolNumber: String = "1", end: Bool = true) -> String {
    var lines = ["macmosh-host\t\(protocolNumber)\t0.1.0"]
    for record in records { lines.append(record.joined(separator: "\t")) }
    if end { lines.append("end") }
    return lines.joined(separator: "\n") + "\n"
}

/// The `MACMOSH_HOST_VERSION=` line of the script, read here and not by the code under test.
private func versionLine(in text: String) -> String {
    for line in text.split(separator: "\n") where line.hasPrefix("MACMOSH_HOST_VERSION=") {
        return String(line.dropFirst("MACMOSH_HOST_VERSION=".count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
    return ""
}

@Suite struct HostStatusTests {
    // MARK: the plan's named tests

    @Test func parsesTheFullExample() throws {
        let s = try HostStatus.parse(fullReport())
        #expect(s.protocolVersion == 1)
        #expect(s.scriptVersion == "0.1.0")
        #expect(s.osVersion == "27.3")
        #expect(s.arch == "arm64")
        #expect(s.consoleUser == "alex")
        #expect(s.serverUp)
        #expect(s.signIns == .yes)
        #expect(s.fileVault == .yes)
        #expect(s.authRestart == .yes)
        #expect(s.firewall == .no)
        #expect(s.screenSharing == .yes)
        #expect(s.agentInstalled)
        #expect(s.power.sleepOnPower == 0)
        #expect(s.power.wakeForNetwork == 1)
        #expect(s.power.autoRestart == nil)
        #expect(s.power.disableSleep == nil)
        let battery: HostStatus.Battery = .init(present: true, onAC: true, percent: 82)
        #expect(s.battery == battery)
        let home: HostStatus.Home = .init(address: "192.168.1.20", prefix: 24, localName: "workhorse.local")
        #expect(s.home == home)
        let deskNames: [String] = s.desks.map(\.name.value)
        #expect(deskNames == ["website"])
        #expect(s.desks[0].windows.count == 2)
        #expect(s.desks[0].windowCount == 2)
        #expect(s.desks[0].attached == 1)
        let windowNames: [String] = s.desks[0].windows.map(\.name)
        #expect(windowNames == ["zsh", "vim"])
        #expect(s.definitions.count == 1)
        #expect(s.definitions[0].command == "npm run dev")
        #expect(s.definitions[0].folder == "/Users/alex/Development/website")
        #expect(s.definitions[0].reopen)
        #expect(!s.definitions[0].keep)
        #expect(s.canUnlockOverSSH)
        #expect(s.isLaptop)
    }

    @Test func parsesTheTools() throws {
        let s = try HostStatus.parse(fullReport())
        let names: [String] = s.tools.map(\.name)
        #expect(names == ["brew", "mosh-server", "tmux"])
        let brew: HostStatus.Tool = .init(name: "brew", path: "/opt/homebrew/bin/brew", version: nil)
        #expect(s.tools[0] == brew)
        #expect(s.tools[2].version == "3.8")
    }

    @Test func skipsNoiseBeforeTheHeader() throws {
        let s = try HostStatus.parse("Welcome back!\nLast login: today\n" + fullReport())
        #expect(s.serverUp)
    }

    @Test func missingEndIsTruncated() throws {
        let cut = try fullReport().replacingOccurrences(of: "end\n", with: "")
        #expect(throws: HostStatusError.truncated) { try HostStatus.parse(cut) }
    }

    @Test func aReportCutOffInTheMiddleIsTruncated() throws {
        let full = try fullReport()
        let cut = String(full.prefix(full.count / 2))
        #expect(throws: HostStatusError.truncated) { try HostStatus.parse(cut) }
    }

    @Test func unsupportedProtocolIsReported() {
        #expect(throws: HostStatusError.unsupportedProtocol(2)) {
            try HostStatus.parse("macmosh-host\t2\t9.0.0\nend\n")
        }
    }

    @Test func anotherProtocolIsReportedEvenWithoutAnEndLine() {
        #expect(throws: HostStatusError.unsupportedProtocol(3)) {
            try HostStatus.parse("macmosh-host\t3\t9.0.0\nsomething new\n")
        }
    }

    @Test func theBuiltInScriptIsTheFileInTheRepo() throws {
        let onDisk = try String(contentsOf: repoRoot().appendingPathComponent("host/macmosh-host"), encoding: .utf8)
        #expect(HostScript.source == onDisk)
        #expect(HostScript.version == versionLine(in: HostScript.source))
        #expect(!HostScript.version.isEmpty)
    }

    // MARK: the plan's other named tests

    @Test func noHeaderIsReported() {
        #expect(throws: HostStatusError.noHeader) { try HostStatus.parse("") }
        #expect(throws: HostStatusError.noHeader) { try HostStatus.parse("Welcome back!\nLast login: today\n") }
        #expect(throws: HostStatusError.noHeader) { try HostStatus.parse("server\tup\nend\n") }
    }

    @Test func unknownRecordsAreIgnored() throws {
        let text = report([["os", "27.3", "arm64"], ["futurething", "1", "2"], ["server", "up"], ["tool"]])
        let s = try HostStatus.parse(text)
        #expect(s.serverUp)
        #expect(s.osVersion == "27.3")
    }

    @Test func emptyConsoleMeansNobody() throws {
        let s = try HostStatus.parse(report([["console", ""]]))
        #expect(s.consoleUser == nil)
        let none = try HostStatus.parse(report([["console"]]))
        #expect(none.consoleUser == nil)
    }

    @Test func aStartupCommandMayContainSpacesButIsTheLastField() throws {
        let s = try HostStatus.parse(report([
            ["def", "a", "0", "1", "/Users/alex/My Project", "npm run dev -- --port 3000"],
            ["def", "b", "0", "0", "/Users/alex/b", ""],
        ]))
        #expect(s.definitions.count == 2)
        #expect(s.definitions[0].command == "npm run dev -- --port 3000")
        #expect(s.definitions[0].folder == "/Users/alex/My Project")
        #expect(s.definitions[0].keep)
        #expect(s.definitions[1].command == "")
        #expect(!s.definitions[1].reopen)
    }

    @Test func aDefinitionCarriesWhetherItIsPermanent() throws {
        let s = try HostStatus.parse(report([
            ["def", "kept", "1", "0", "1", "/Users/alex/My Project", "npm run dev"],
            ["def", "brief", "0", "1", "0", "/Users/alex/b", ""],
            ["def", "odd", "0", "0", "2", "/Users/alex/c", ""],
        ]))
        let names: [String] = s.definitions.map(\.name.value)
        #expect(names == ["kept", "brief"])
        #expect(s.definitions[0] == HostStatus.Definition(name: DeskName("kept")!, reopen: true, keep: false,
                                                           folder: "/Users/alex/My Project", command: "npm run dev",
                                                           permanent: true))
        #expect(!s.definitions[1].permanent)
        #expect(!s.definitions[1].reopen)
        #expect(s.definitions[1].keep)
        #expect(s.definitions[1].folder == "/Users/alex/b")
        #expect(s.definitions[1].command == "")
    }

    @Test func aDefinitionFromAnOlderScriptIsNotPermanent() throws {
        // Before script 0.5.0 a definition had five fields: no permanent field before the folder.
        let s = try HostStatus.parse(report([
            ["def", "a", "1", "0", "/Users/alex/a", "npm run dev"],
            ["def", "b", "0", "0", "/Users/alex/b", ""],
            ["def", "c", "0", "1", "/Users/alex/c"],
        ]))
        #expect(s.definitions.count == 3)
        #expect(s.definitions.allSatisfy { !$0.permanent })
        #expect(s.definitions[0].reopen)
        #expect(s.definitions[0].folder == "/Users/alex/a")
        #expect(s.definitions[0].command == "npm run dev")
        #expect(s.definitions[2].folder == "/Users/alex/c")
        #expect(s.definitions[2].keep)
        #expect(try HostStatus.parse(fullReport()).definitions[0].permanent == false)
    }

    @Test func extraFieldsAfterTheCommandStayInTheCommand() throws {
        // The script never writes a tab into a command, but a reader must not cut one off if it appears.
        let s = try HostStatus.parse(report([["def", "a", "0", "0", "/tmp", "echo", "hi"]]))
        #expect(s.definitions[0].folder == "/tmp")
        #expect(s.definitions[0].command == "echo\thi")
    }

    @Test func macOS15CannotUnlockOverSSH() {
        #expect(!OSSupport.canUnlockOverSSH(osVersion: "15.6", arch: "arm64"))
        #expect(!OSSupport.canUnlockOverSSH(osVersion: "25.9", arch: "arm64"))
        #expect(OSSupport.canUnlockOverSSH(osVersion: "26.0", arch: "arm64"))
        #expect(OSSupport.canUnlockOverSSH(osVersion: "26", arch: "arm64"))
        #expect(OSSupport.canUnlockOverSSH(osVersion: "27.3", arch: "arm64"))
    }

    @Test func intelCannotUnlockOverSSH() {
        #expect(!OSSupport.canUnlockOverSSH(osVersion: "27.3", arch: "x86_64"))
    }

    @Test func anUnknownVersionCountsAsAble() {
        #expect(OSSupport.canUnlockOverSSH(osVersion: nil, arch: nil))
        #expect(OSSupport.canUnlockOverSSH(osVersion: nil, arch: "arm64"))
        #expect(OSSupport.canUnlockOverSSH(osVersion: "27.3", arch: nil))
        #expect(OSSupport.canUnlockOverSSH(osVersion: "", arch: "arm64"))
        #expect(OSSupport.canUnlockOverSSH(osVersion: "banana", arch: "arm64"))
        #expect(!OSSupport.canUnlockOverSSH(osVersion: "banana", arch: "x86_64"))
    }

    @Test func theReportsOwnVersionAndChipDecideCanUnlock() throws {
        let old = try HostStatus.parse(report([["os", "15.6", "arm64"]]))
        #expect(!old.canUnlockOverSSH)
        let intel = try HostStatus.parse(report([["os", "27.3", "x86_64"]]))
        #expect(!intel.canUnlockOverSSH)
        let silent = try HostStatus.parse(report([]))
        #expect(silent.canUnlockOverSSH)
    }

    @Test func aWindowLineBeforeItsDeskIsKept() throws {
        let s = try HostStatus.parse(report([
            ["window", "web", "1", "vim"],
            ["window", "web", "0", "zsh"],
            ["desk", "web", "2", "0"],
        ]))
        #expect(s.desks.count == 1)
        let names: [String] = s.desks[0].windows.map(\.name)
        #expect(names == ["zsh", "vim"])
        let indexes: [Int] = s.desks[0].windows.map(\.index)
        #expect(indexes == [0, 1])
    }

    @Test func aWindowWithoutADeskIsLeftOut() throws {
        let s = try HostStatus.parse(report([["window", "ghost", "0", "zsh"]]))
        #expect(s.desks.isEmpty)
    }

    @Test func aShortRecordDoesNotCrash() throws {
        let records: [[String]] = [
            ["os"], ["console"], ["server"], ["signins"], ["filevault"], ["authrestart"], ["power"],
            ["battery"], ["home"], ["firewall"], ["screensharing"], ["agent"],
            ["tool"], ["desk"], ["desk", "web"], ["window"], ["window", "web"], ["window", "web", "0"],
            ["def"], ["def", "web"], ["def", "web", "1", "0"],
        ]
        let s = try HostStatus.parse(report(records))
        #expect(!s.serverUp)
        #expect(s.signIns == .unknown)
        #expect(s.fileVault == .unknown)
        #expect(s.authRestart == .unknown)
        #expect(s.firewall == .unknown)
        #expect(s.screenSharing == .unknown)
        #expect(!s.agentInstalled)
        #expect(s.consoleUser == nil)
        let power: HostStatus.Power = .init(sleepOnPower: nil, wakeForNetwork: nil, autoRestart: nil, disableSleep: nil)
        #expect(s.power == power)
        #expect(!s.battery.present)
        #expect(s.battery.onAC == nil)
        #expect(s.battery.percent == nil)
        #expect(s.home == HostStatus.Home(address: nil, prefix: nil, localName: nil))
        #expect(s.tools.isEmpty)
        #expect(s.desks.isEmpty)
        #expect(s.definitions.isEmpty)
    }

    @Test func theLidFieldIsTheNumberOrNilForADash() throws {
        for (field, expected) in [("1", 1), ("0", 0), ("-", nil)] as [(String, Int?)] {
            let s = try HostStatus.parse(report([
                ["power", "sleep=0", "womp=1", "autorestart=-", "disablesleep=\(field)"],
            ]))
            #expect(s.power.disableSleep == expected, "disablesleep=\(field)")
            #expect(s.power.sleepOnPower == 0)
            #expect(s.power.wakeForNetwork == 1)
            #expect(s.power.autoRestart == nil)
        }
    }

    @Test func aNonNumericFieldIsNil() throws {
        let s = try HostStatus.parse(report([
            ["power", "sleep=soon", "womp=", "autorestart=1x", "disablesleep=1"],
            ["battery", "present", "ac", "lots"],
            ["home", "192.168.1.20", "wide", "workhorse.local"],
            ["desk", "web", "many", "0"],
            ["desk", "api", "1", "some"],
            ["desk", "ok", "1", "0"],
            ["def", "web", "yes", "0", "/Users/alex/web", ""],
            ["def", "ok", "0", "0", "/Users/alex/ok", ""],
        ]))
        #expect(s.power.sleepOnPower == nil)
        #expect(s.power.wakeForNetwork == nil)
        #expect(s.power.autoRestart == nil)
        #expect(s.power.disableSleep == 1)
        #expect(s.battery.present)
        #expect(s.battery.onAC == true)
        #expect(s.battery.percent == nil)
        #expect(s.home.address == "192.168.1.20")
        #expect(s.home.prefix == nil)
        #expect(s.home.localName == "workhorse.local")
        let deskNames: [String] = s.desks.map(\.name.value)
        #expect(deskNames == ["ok"])
        let definitionNames: [String] = s.definitions.map(\.name.value)
        #expect(definitionNames == ["ok"])
    }

    // MARK: more of the strict and lenient rules

    @Test func aDeskOrDefinitionWithAnInvalidNameIsLeftOut() throws {
        let s = try HostStatus.parse(report([
            ["desk", "has space", "1", "0"],
            ["desk", "good_1", "1", "0"],
            ["desk", String(repeating: "a", count: 65), "1", "0"],
            ["def", "bad/name", "0", "0", "/tmp", ""],
            ["def", "good_1", "0", "0", "/tmp", ""],
            ["def", "", "0", "0", "/tmp", ""],
        ]))
        let deskNames: [String] = s.desks.map(\.name.value)
        #expect(deskNames == ["good_1"])
        let definitionNames: [String] = s.definitions.map(\.name.value)
        #expect(definitionNames == ["good_1"])
    }

    @Test func windowsLineEndingsAreTolerated() throws {
        let text = try fullReport().replacingOccurrences(of: "\n", with: "\r\n")
        let s = try HostStatus.parse(text)
        #expect(s.serverUp)
        #expect(s.consoleUser == "alex")
        #expect(s.definitions[0].command == "npm run dev")
        #expect(s.desks[0].windows.count == 2)
        let cut = text.replacingOccurrences(of: "end\r\n", with: "")
        #expect(throws: HostStatusError.truncated) { try HostStatus.parse(cut) }
    }

    @Test func nothingAfterTheEndLineIsRead() throws {
        let s = try HostStatus.parse(report([["server", "up"]]) + "server\tdown\nmacmosh-host\t1\t9\n")
        #expect(s.serverUp)
        #expect(s.scriptVersion == "0.1.0")
    }

    @Test func threeStateAnswersMapToTheTriValues() throws {
        let s = try HostStatus.parse(report([
            ["signins", "off"], ["filevault", "unknown"], ["authrestart", "no"],
            ["firewall", "on"], ["screensharing", "off"],
        ]))
        #expect(s.signIns == .no)
        #expect(s.fileVault == .unknown)
        #expect(s.authRestart == .no)
        #expect(s.firewall == .yes)
        #expect(s.screenSharing == .no)
        let odd = try HostStatus.parse(report([["signins", "maybe"], ["filevault", "ON"], ["firewall", "yes"]]))
        #expect(odd.signIns == .unknown)
        #expect(odd.fileVault == .unknown)
        #expect(odd.firewall == .unknown)
    }

    @Test func aMissingAgentOrServerIsNotAssumed() throws {
        let s = try HostStatus.parse(report([["agent", "missing"], ["server", "down"], ["battery", "absent", "ac", "-"]]))
        #expect(!s.agentInstalled)
        #expect(!s.serverUp)
        #expect(!s.isLaptop)
        #expect(s.battery.percent == nil)
    }
}
