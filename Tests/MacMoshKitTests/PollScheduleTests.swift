import Foundation
import Testing
@testable import MacMoshKit

@Suite struct PollScheduleTests {
    @Test(arguments: [(0, 30), (1, 30), (2, 60), (3, 120), (4, 300), (9, 300)])
    func theWaitGrowsWhileAWorkhorseCantBeReached(misses: Int, seconds: Int) {
        #expect(PollSchedule.delay(missesInARow: misses) == .seconds(seconds))
    }

    @Test func aMissIsAnyWorkhorseThatCantBeReached() {
        let ready: Gathered = .checked(.sampleReady(id: "a", name: "A"))
        let away: Gathered = .checked(.sample(.cantReach(.tailscaleOff), workhorse: .sample(id: "b", name: "B")))
        let waiting: Gathered = .stillChecking(.sample(id: "c", name: "C"))
        #expect(PollSchedule.isMiss([ready, away]))
        #expect(!PollSchedule.isMiss([ready]))
        #expect(!PollSchedule.isMiss([]))
        // A check that has not answered yet is not a miss: only a finished "can't reach it" counts.
        #expect(!PollSchedule.isMiss([ready, waiting]))
        #expect(!PollSchedule.isMiss([.checked(.sample(.locked)), .checked(.sample(.cantVerify))]))
        #expect(!PollSchedule.isMiss([waiting, waiting]))
        #expect(PollSchedule.isMiss([.checked(.sample(.locked)), .checked(.sample(.cantReach(.noNetwork)))]))
    }
}
