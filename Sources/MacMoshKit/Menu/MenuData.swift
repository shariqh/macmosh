import Foundation

public enum MenuData {
    private enum Event: Sendable {
        case answered(Int, CheckResult)
        case timeUp
    }

    /// Checks every workhorse at the same time and returns within `budget`. A workhorse that
    /// hasn't answered by then comes back as `.stillChecking`; the results keep the order of
    /// `list`. The unfinished checks are cancelled, which stops their ssh.
    public static func gather(_ list: [Workhorse], checker: StatusChecker, budget: Duration) async -> [Gathered] {
        if list.isEmpty { return [] }
        let answers: [CheckResult?] = await withTaskGroup(of: Event.self) { group in
            for (i, w) in list.enumerated() {
                group.addTask { .answered(i, await checker.check(w)) }
            }
            group.addTask {
                try? await Task.sleep(for: budget)
                return .timeUp
            }
            var slots = [CheckResult?](repeating: nil, count: list.count)
            var remaining = list.count
            while let event = await group.next() {
                switch event {
                case .answered(let i, let result):
                    slots[i] = result
                    remaining -= 1
                    // All answered: stop the timer, which then ends the loop.
                    if remaining == 0 { group.cancelAll() }
                case .timeUp:
                    // Out of time, or everything answered and the timer was stopped.
                    group.cancelAll()
                    return slots
                }
            }
            return slots
        }
        return zip(list, answers).map { w, answer in
            answer.map(Gathered.checked) ?? .stillChecking(w)
        }
    }
}
