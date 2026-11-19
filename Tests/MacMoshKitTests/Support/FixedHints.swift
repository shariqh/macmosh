import Foundation
@testable import MacMoshKit

/// A stand-in `HintsProvider` for tests: gives the same hints for every workhorse and runs nothing.
struct FixedHints: HintsProvider {
    let value: Hints

    init(_ value: Hints) {
        self.value = value
    }

    func hints(for workhorse: Workhorse) async -> Hints { value }
}
