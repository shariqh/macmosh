import Foundation

/// What the menu shows: its icon and its lines, top to bottom. Called `MenuLines`, not `Menu`, so a
/// view can use it beside SwiftUI's own `Menu`.
public struct MenuLines: Sendable, Equatable {
    public var symbol: String
    public var items: [MenuItem]

    public init(symbol: String, items: [MenuItem]) {
        self.symbol = symbol
        self.items = items
    }
}
