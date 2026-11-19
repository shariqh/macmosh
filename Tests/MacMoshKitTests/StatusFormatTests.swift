import Foundation
import Testing
@testable import MacMoshKit

/// 14:02 on the day before `formatNow`, and so on: the times the hints name.
private let seenToday = utcDate(2027, 1, 15, 14, 2)
private let seenYesterday = utcDate(2027, 1, 14, 14, 2)
private let seenThisYear = utcDate(2027, 1, 3, 9, 30)
private let seenLastYear = utcDate(2026, 12, 28, 9, 30)

private func seen(_ date: Date?, id: String = "mbp") -> Workhorse {
    .sample(id: id, name: "MacBook Pro", lastSeen: date)
}

private func headline(_ state: WorkhorseState, _ w: Workhorse = .sample(name: "MacBook Pro")) -> String {
    StatusFormat.headline(.sample(state, workhorse: w))
}

private func hint(_ state: WorkhorseState, _ w: Workhorse = .sample(name: "MacBook Pro")) -> String? {
    StatusFormat.hint(.sample(state, workhorse: w), now: formatNow, timeZone: formatZone)
}

private func report(replacing target: String? = nil, with new: String = "") throws -> HostStatus {
    var text = try fixture("status/full.txt")
    if let target { text = text.replacingOccurrences(of: target, with: new) }
    return try HostStatus.parse(text)
}

@Suite struct StatusFormatTests {
    // MARK: one test per row of the headline and hint table

    @Test func readyHasNoHint() {
        #expect(headline(.ready(signIns: true)) == "MacBook Pro · Ready")
        #expect(hint(.ready(signIns: true)) == nil)
    }

    @Test func readyWithSignInsOff() {
        #expect(headline(.ready(signIns: false)) == "MacBook Pro · Ready, sign-ins off")
        #expect(hint(.ready(signIns: false)) == "Tools that keep logins in the keychain look signed out here.")
    }

    @Test func waitingForLogin() {
        #expect(headline(.waitingForLogin) == "MacBook Pro · Waiting for login")
        #expect(hint(.waitingForLogin) == "It is on and unlocked, but nobody has logged in.")
    }

    @Test func lockedAfterARestart() {
        let able = Workhorse.sample(name: "MacBook Pro", osVersion: "27.3", arch: "arm64")
        #expect(headline(.locked, able) == "MacBook Pro · Locked after a restart")
        #expect(hint(.locked, able) == "The disk is locked until someone types the Mac's password.")
    }

    @Test func lockedOnAWorkhorseThatCannotUnlockOverSSHSaysToUnlockAtTheMac() {
        let old = Workhorse.sample(name: "MacBook Pro", osVersion: "15.6", arch: "arm64")
        #expect(hint(.locked, old) == "The disk is locked until someone types the Mac's password. Unlock it at the Mac.")
        let intel = Workhorse.sample(name: "MacBook Pro", osVersion: "27.3", arch: "x86_64")
        #expect(hint(.locked, intel)?.hasSuffix("Unlock it at the Mac.") == true)
    }

    @Test func cantVerifyIt() {
        #expect(headline(.cantVerify) == "MacBook Pro · Can't verify it")
        #expect(hint(.cantVerify) == "Something answers at its address with a different key. Stop. Don't type a password. Check or unlock at the Mac.")
    }

    @Test func cantReachBecauseTailscaleIsOff() {
        let w = seen(seenToday)
        #expect(headline(.cantReach(.tailscaleOff), w) == "MacBook Pro · Can't reach it")
        #expect(hint(.cantReach(.tailscaleOff), w) == "Last seen 14:02. Tailscale is off on this Mac.")
    }

    @Test func cantReachBecauseThereIsNoNetwork() {
        let w = seen(seenToday)
        #expect(headline(.cantReach(.noNetwork), w) == "MacBook Pro · Can't reach it")
        #expect(hint(.cantReach(.noNetwork), w) == "Last seen 14:02. This Mac has no network.")
    }

    @Test func cantReachBecauseAnotherVPNIsRunning() {
        let w = seen(seenToday)
        #expect(headline(.cantReach(.otherVPN), w) == "MacBook Pro · Can't reach it")
        #expect(hint(.cantReach(.otherVPN), w) == "Last seen 14:02. Another VPN is running on this Mac.")
    }

    @Test func cantReachBecauseAwayAndOffline() {
        let w = seen(seenToday)
        #expect(headline(.cantReach(.awayAndOffline), w) == "MacBook Pro · Can't reach it")
        #expect(hint(.cantReach(.awayAndOffline), w)
                == "Last seen 14:02. Tailscale says it is offline and you are away from home. It may have restarted: its home address is out of reach from here.")
    }

    @Test func cantReachBecauseNothingAnswers() {
        let w = seen(seenToday)
        #expect(headline(.cantReach(.nothingAnswers), w) == "MacBook Pro · Can't reach it")
        #expect(hint(.cantReach(.nothingAnswers), w)
                == "Last seen 14:02. Nothing answers at either address: it is off, asleep or disconnected. If it just restarted, its home address may have changed.")
    }

    @Test func notPaired() {
        let w = Workhorse.sample(id: "mbp", name: "MacBook Pro")
        #expect(headline(.notSetUp(.notPaired), w) == "MacBook Pro · Not paired")
        #expect(hint(.notSetUp(.notPaired), w) == "Run: macmosh pair mbp")
    }

    @Test func yourSSHKeyIsLocked() {
        let own = Workhorse.sample(name: "MacBook Pro")
        #expect(headline(.notSetUp(.identityUnusable), own) == "MacBook Pro · Your ssh key is locked")
        #expect(hint(.notSetUp(.identityUnusable), own) == "MacMosh can't use ~/.ssh/macmosh_ed25519.")
        let named = Workhorse.sample(name: "MacBook Pro", identityFile: "/keys/work_ed25519")
        #expect(hint(.notSetUp(.identityUnusable), named) == "MacMosh can't use /keys/work_ed25519.")
    }

    @Test func needsSettingUpWhenTheScriptIsMissing() {
        let w = Workhorse.sample(id: "mbp", name: "MacBook Pro")
        #expect(headline(.notSetUp(.hostScriptMissing), w) == "MacBook Pro · Needs setting up")
        #expect(hint(.notSetUp(.hostScriptMissing), w) == "Run: macmosh prepare mbp --fix")
    }

    @Test func needsSettingUpWhenTheScriptIsOutdated() {
        let w = Workhorse.sample(id: "mbp", name: "MacBook Pro")
        #expect(headline(.notSetUp(.hostScriptOutdated), w) == "MacBook Pro · Needs setting up")
        #expect(hint(.notSetUp(.hostScriptOutdated), w) == "Run: macmosh prepare mbp --fix")
    }

    @Test func couldntReadItsStatus() {
        let w = Workhorse.sample(id: "mbp", name: "MacBook Pro")
        #expect(headline(.notSetUp(.unreadableReport), w) == "MacBook Pro · Couldn't read its status")
        #expect(hint(.notSetUp(.unreadableReport), w)
                == "It answered, but its status report was incomplete. MacMosh will try again. If this stays, run: macmosh prepare mbp --fix")
    }

    @Test func deskServerIsOff() {
        let w = Workhorse.sample(id: "mbp", name: "MacBook Pro")
        #expect(headline(.notSetUp(.deskServerDown), w) == "MacBook Pro · Desk server is off")
        #expect(hint(.notSetUp(.deskServerDown), w) == "Run: macmosh prepare mbp --fix")
    }

    @Test func stateNamesAreFixed() {
        let names: [String] = [
            StatusFormat.stateName(.ready(signIns: true)), StatusFormat.stateName(.ready(signIns: false)),
            StatusFormat.stateName(.waitingForLogin), StatusFormat.stateName(.locked),
            StatusFormat.stateName(.cantVerify), StatusFormat.stateName(.cantReach(.nothingAnswers)),
            StatusFormat.stateName(.notSetUp(.notPaired)),
        ]
        let expected: [String] = ["ready", "ready-signins-off", "waiting-for-login", "locked",
                                  "cant-verify", "cant-reach", "not-set-up"]
        #expect(names == expected)
    }

    // MARK: the time in a hint

    @Test func lastSeenYesterdayNamesTheDay() {
        #expect(hint(.cantReach(.noNetwork), seen(seenYesterday)) == "Last seen yesterday 14:02. This Mac has no network.")
    }

    @Test func lastSeenLongerAgoIsTheDate() {
        #expect(hint(.cantReach(.noNetwork), seen(seenThisYear)) == "Last seen 3 Jan. This Mac has no network.")
        #expect(hint(.cantReach(.noNetwork), seen(seenLastYear)) == "Last seen 28 Dec 2026. This Mac has no network.")
    }

    @Test func aWorkhorseNeverSeenLeavesTheSentenceOut() {
        #expect(hint(.cantReach(.tailscaleOff), seen(nil)) == "Tailscale is off on this Mac.")
        #expect(hint(.cantReach(.nothingAnswers), seen(nil))?.hasPrefix("Nothing answers at either address") == true)
    }

    @Test func theTimeFollowsTheTimeZone() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let r = CheckResult.sample(.cantReach(.noNetwork), workhorse: seen(seenToday))
        // 14:02 UTC is 23:02 on the 15th in Tokyo, where it is already 01:00 on the 16th.
        #expect(StatusFormat.hint(r, now: formatNow, timeZone: tokyo) == "Last seen yesterday 23:02. This Mac has no network.")
    }

    // MARK: the summary line

    @Test func summaryLineFollowsTheReport() throws {
        let full = try report()
        #expect(StatusFormat.summaryLine(full) == "Sign-ins working · Awake on power · On power, 82%")
        let lidOff = try report(replacing: "disablesleep=-", with: "disablesleep=0")
        #expect(StatusFormat.summaryLine(lidOff) == "Sign-ins working · Awake on power · Lid-closed mode off · On power, 82%")
        let lidOn = try report(replacing: "disablesleep=-", with: "disablesleep=1")
        #expect(StatusFormat.summaryLine(lidOn).contains("Lid-closed mode on"))
    }

    @Test func summaryLineNamesSleepSignInsAndPowerSource() throws {
        var s = try report()
        s.signIns = .no
        s.power.sleepOnPower = 10
        s.battery = .init(present: true, onAC: false, percent: 40)
        #expect(StatusFormat.summaryLine(s) == "Sign-ins off · Sleeps on power · On battery, 40%")
        s.battery = .init(present: false, onAC: nil, percent: nil)
        #expect(StatusFormat.summaryLine(s) == "Sign-ins off · Sleeps on power · On power")
    }

    // MARK: the whole text

    @Test func readyShowsItsDesksAndTheSummary() throws {
        let status = try report()
        let r = CheckResult.sample(.ready(signIns: true), workhorse: .sample(name: "MacBook Pro"), status: status)
        let text = StatusFormat.text([r], now: formatNow, timeZone: formatZone)
        #expect(text == """
        MacBook Pro · Ready
          website  2 windows  1 tab attached
          Sign-ins working · Awake on power · On power, 82%

        """)
    }

    @Test func readyWithNoDesksSaysSo() throws {
        var status = try report()
        status.desks = []
        let r = CheckResult.sample(.ready(signIns: true), workhorse: .sample(name: "MacBook Pro"), status: status)
        let text = StatusFormat.text([r], now: formatNow, timeZone: formatZone)
        #expect(text.contains("  No desks yet.\n"))
    }

    @Test func deskLinesAreAlignedAndCountTabs() throws {
        var status = try report()
        let notes = HostStatus.Desk(name: DeskName("notes")!, windows: [], windowCount: 1, attached: 0)
        let long = HostStatus.Desk(name: DeskName("a-long-name")!, windows: [], windowCount: 3, attached: 2)
        status.desks = [notes, long]
        #expect(StatusFormat.deskLines(status) == ["notes        1 window  0 tabs attached",
                                                   "a-long-name  3 windows  2 tabs attached"])
    }

    @Test func otherStatesShowTheHintAndNoDesks() {
        let results = [
            CheckResult.sample(.locked, workhorse: .sample(name: "MacBook Pro", osVersion: "27.3", arch: "arm64")),
            CheckResult.sample(.cantVerify, workhorse: .sample(id: "mini", name: "Mac mini")),
        ]
        let text = StatusFormat.text(results, now: formatNow, timeZone: formatZone)
        #expect(text == """
        MacBook Pro · Locked after a restart
          The disk is locked until someone types the Mac's password.

        Mac mini · Can't verify it
          Something answers at its address with a different key. Stop. Don't type a password. Check or unlock at the Mac.

        """)
    }

    @Test func noWorkhorsesSaysHowToStart() {
        #expect(StatusFormat.text([], now: formatNow, timeZone: formatZone) == "No workhorses yet. Run: macmosh pair <user@address>\n")
        #expect(StatusFormat.listText([]) == "No workhorses yet. Run: macmosh pair <user@address>\n")
    }

    // MARK: JSON

    @Test func jsonHasAStableShape() throws {
        let status = try report()
        let ready = CheckResult.sample(.ready(signIns: true), workhorse: .sample(id: "mbp", name: "MacBook Pro"),
                                       status: status, homeReachable: true)
        let down = CheckResult.sample(.cantReach(.noNetwork), workhorse: seen(seenToday, id: "mini"))
        let text = try StatusFormat.json([ready, down], now: formatNow, timeZone: formatZone)

        let rows = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        #expect(rows.count == 2)
        let keys = ["checkedAt", "desks", "hint", "homeReachable", "id", "name", "reason", "state"]
        #expect(rows.allSatisfy { $0.keys.sorted() == keys })

        #expect(rows[0]["id"] as? String == "mbp" && rows[0]["name"] as? String == "MacBook Pro")
        #expect(rows[0]["state"] as? String == "ready")
        #expect(rows[0]["reason"] is NSNull && rows[0]["hint"] is NSNull)
        #expect(rows[0]["homeReachable"] as? Bool == true)
        #expect(rows[0]["checkedAt"] as? String == "2027-01-15T08:00:00Z")
        let desks = try #require(rows[0]["desks"] as? [[String: Any]])
        #expect(desks.count == 1 && desks[0].keys.sorted() == ["attached", "name", "windows"])
        #expect(desks[0]["name"] as? String == "website" && desks[0]["windows"] as? Int == 2 && desks[0]["attached"] as? Int == 1)

        #expect(rows[1]["state"] as? String == "cant-reach" && rows[1]["reason"] as? String == "noNetwork")
        #expect(rows[1]["hint"] as? String == "Last seen 14:02. This Mac has no network.")
        #expect(rows[1]["homeReachable"] is NSNull)
        #expect((rows[1]["desks"] as? [Any])?.isEmpty == true)
    }

    @Test func jsonKeysAreSortedAndTheTextIsTheSameEachTime() throws {
        let r = CheckResult.sample(.notSetUp(.notPaired), workhorse: .sample(id: "mbp", name: "MacBook Pro"))
        let a = try StatusFormat.json([r], now: formatNow, timeZone: formatZone)
        let b = try StatusFormat.json([r], now: formatNow, timeZone: formatZone)
        #expect(a == b)
        #expect(a.contains(#""reason":"notPaired""#))
        #expect(a.hasPrefix(#"[{"checkedAt":"#))          // sorted: checkedAt, desks, hint, ...
        #expect(try StatusFormat.json([], now: formatNow, timeZone: formatZone) == "[]")
    }

    // MARK: list

    @Test func listShowsTheSavedWorkhorsesWithoutChecking() {
        let a = Workhorse.sample(id: "mbp", name: "MacBook Pro", user: "alex", mainAddress: "workhorse")
        var b = Workhorse.sample(id: "mini", name: "Mac mini", user: "alex", mainAddress: "mini.example")
        b.paired = false
        #expect(StatusFormat.listText([a, b]) == """
        MacBook Pro (mbp) · alex@workhorse · paired
        Mac mini (mini) · alex@mini.example · not paired

        """)
    }

    @Test func listJSONHasAStableShape() throws {
        let w = Workhorse.sample(id: "mbp", name: "MacBook Pro", mainAddress: "workhorse", homeAddress: "192.168.1.20",
                                 localName: "workhorse.local", lastSeen: seenToday)
        let text = try StatusFormat.listJSON([w])
        let rows = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        let keys = ["homeAddress", "id", "lastSeen", "localName", "mainAddress", "mode", "name", "paired", "user"]
        #expect(rows[0].keys.sorted() == keys)
        #expect(rows[0]["lastSeen"] as? String == "2027-01-15T14:02:00Z")
        #expect(rows[0]["paired"] as? Bool == true)
    }

    // MARK: desks

    @Test func desksJSONIsOneObjectPerDesk() throws {
        let status = try report()
        let text = try StatusFormat.desksJSON(status)
        let rows = try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]])
        #expect(rows.count == 1 && rows[0].keys.sorted() == ["attached", "name", "windows"])
    }
}
