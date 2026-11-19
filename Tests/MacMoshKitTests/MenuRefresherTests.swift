import Foundation
import Testing
@testable import MacMoshKit

/// Collects what `save` was given. The closure is `@Sendable`, so the list sits behind a lock.
private final class Saved: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []

    func add(_ id: String) { lock.lock(); ids.append(id); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return ids }
}

@MainActor @Suite struct MenuRefresherTests {
    @Test func refreshBuildsTheMenuFromWhatWasGathered() async {
        let r = MenuRefresher(load: { [.sample(id: "mbp", name: "MacBook Pro")] },
                              gather: { list in list.map { .checked(.sampleReady(id: $0.id, name: $0.name)) } },
                              save: { _ in })
        await r.refresh()
        #expect(r.menu.symbol == "checkmark.circle")
        #expect(r.menu.items.first?.title == "MacBook Pro · Ready")
    }

    @Test func theMenuStartsAsStillLoading() {
        let r = MenuRefresher(load: { [] }, gather: { _ in [] }, save: { _ in })
        #expect(r.menu.symbol == "ellipsis.circle")
        #expect(r.menu.items.map(\.title) == ["Checking…"])
    }

    @Test func aDamagedListShowsAPlainMessageNotACrash() async {
        let r = MenuRefresher(load: { throw StoreError.unreadable("workhorses.json: not JSON") },
                              gather: { _ in Issue.record("gather must not run"); return [] },
                              save: { _ in Issue.record("save must not run") })
        await r.refresh()
        #expect(r.menu.symbol == "exclamationmark.triangle")
        #expect(r.menu.items.count == 1)
        #expect(r.menu.items.first?.title == "Can't read MacMosh's saved settings: workhorses.json: not JSON")
    }

    @Test func refreshSavesOnlyCheckedResults() async {
        let saved = Saved()
        let r = MenuRefresher(
            load: { [.sample(id: "a", name: "A"), .sample(id: "b", name: "B")] },
            gather: { list in
                let first: Gathered = .checked(.sampleReady(id: list[0].id, name: list[0].name))
                let second: Gathered = .stillChecking(list[1])
                return [first, second]
            },
            save: { saved.add($0.workhorse.id) })
        await r.refresh()
        #expect(saved.all == ["a"])
        #expect(r.menu.items.contains { $0.title == "B · Still checking…" })
    }

    @Test func aRefreshWhileOneIsRunningDoesNothing() async {
        let r = MenuRefresher(load: { [.sample()] },
                              gather: { list in
                                  try? await Task.sleep(for: .milliseconds(200))
                                  return list.map { .checked(.sampleReady(id: $0.id, name: $0.name)) }
                              },
                              save: { _ in })
        async let first: Void = r.refresh()
        await Task.yield()
        await r.refresh()   // returns at once: the first is still gathering
        #expect(r.menu.symbol == "ellipsis.circle")
        await first
        #expect(r.menu.symbol == "checkmark.circle")
    }
}
