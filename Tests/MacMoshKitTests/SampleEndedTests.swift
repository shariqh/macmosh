#if DEBUG
import Foundation
import Testing
@testable import MacMoshKit

/// The `window-ended` sample CI opens the window on (step 5). Debug builds only.
@MainActor @Suite struct SampleEndedTests {
    @Test func itIsASampleTheAppAccepts() throws {
        let run = try #require(SampleRun.named("window-ended"))
        #expect(run.startedLine == "sample menu: window-ended")
        #expect(run.workhorses.map(\.id) == ["attic"])
        #expect(try run.load().map(\.id) == ["attic"])
        #expect(SampleWindow.allCases.contains(.ended))
    }

    /// Every desk open at first; a click on Check now ends recipes, garden, blog and shop, closes website (permanent),
    /// and a permanent desk called shop, closed, takes shop's name. Only the first click does it.
    @Test func checkNowEndsTheDesksOnce() throws {
        let desks = SampleEnded.makeDesks()
        var status = try HostStatus.parse(desks.report())
        #expect(status.scriptVersion == "0.12.0")
        #expect(status.desks.map(\.name.value) == ["api", "blog", "garden", "recipes", "shop", "website"])
        let recipes = try #require(status.definitions.first { $0.name.value == "recipes" })
        #expect(recipes.folder == "/Users/alex/Development/my recipes" && recipes.command == #"claude --continue "fix it" $HOME"#)
        let garden = try #require(status.definitions.first { $0.name.value == "garden" })
        #expect(!garden.reopen && garden.keep && garden.command == "claude")
        #expect(status.definitions.first { $0.name.value == "shop" }?.command == SampleEnded.longCommand)
        desks.endShells()
        status = try HostStatus.parse(desks.report())
        #expect(status.desks.map(\.name.value) == ["api"])
        #expect(status.definitions.first { $0.name.value == "shop" }?.permanent == true)
        #expect(status.definitions.first { $0.name.value == "website" }?.permanent == true)
    }

    /// The stand-in answers desk-new as the script would: the ended desk is made again with its flags, and a name
    /// held by a permanent desk is refused with exit 7.
    @Test func theStandInMakesAnEndedDeskAgain() throws {
        let desks = SampleEnded.makeDesks()
        desks.endShells()
        #expect(desks.run(["desk-new", "shop", "/Users/alex/Development/shop", "--reopen"]).0 == 7)
        #expect(desks.run(["desk-new", "garden", "/Users/alex/Development/garden", "--no-reopen", "--keep", "--permanent",
                           "--command", "claude"]).0 == 0)
        let status = try HostStatus.parse(desks.report())
        #expect(status.desks.map(\.name.value) == ["api", "garden"])
        let garden = try #require(status.definitions.first { $0.name.value == "garden" })
        #expect(!garden.reopen && garden.keep && garden.permanent && garden.command == "claude")
    }

    /// Through the sample's own refresher: the first checks list nothing; after the stand-in's shells end, the next
    /// check lists garden (no reopen), and the one after it the four ended desks, and the board marks shop as taken.
    @Test func itsRefresherListsTheEndedDesks() async throws {
        let desks = SampleEnded.makeDesks()
        let r = SampleEnded.refresher(desks: desks, checkTakes: .zero)
        await r.refresh()
        #expect(r.ended.isEmpty)
        desks.endShells()
        await r.refresh()
        #expect(r.ended["attic"]?.map(\.name) == ["garden"])
        await r.refresh()
        #expect(r.ended["attic"]?.map(\.name) == ["blog", "garden", "recipes", "shop"])
        let board = BoardModel.build(latest: r.latest, lastReady: r.lastReady, checking: [], order: [SampleForms.attic],
                                     waitingForDeskServer: [], ended: r.ended, now: Date(), timeZone: .current)
        let page = try #require(board.workhorses.first.map { WorkhorsePage($0, now: Date(), timeZone: .current) })
        #expect(page.endedHeading == "Ended")
        #expect(page.ended.first { $0.name == "shop" }?.note == "Attic already has a desk called shop.")
        #expect(page.desks.first { $0.name == "website" }?.windows == "(closed)")
    }
}
#endif
