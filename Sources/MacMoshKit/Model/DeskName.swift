import Foundation

/// A desk's name: 1 to 64 characters, each a letter, digit, `-` or `_` (design 7.3).
/// A value of this type has been checked, including when it was decoded from JSON.
public struct DeskName: Hashable, Codable, Sendable {
    public static let maxLength = 64

    public let value: String

    public init?(_ raw: String) {
        guard !raw.isEmpty, raw.utf8.count <= Self.maxLength,
              raw.utf8.allSatisfy(Self.isAllowed) else { return nil }
        self.value = raw
    }

    private static func isAllowed(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"),
             UInt8(ascii: "A")...UInt8(ascii: "Z"),
             UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "-"), UInt8(ascii: "_"):
            return true
        default:
            return false
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let name = DeskName(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "not a valid desk name"))
        }
        self = name
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
