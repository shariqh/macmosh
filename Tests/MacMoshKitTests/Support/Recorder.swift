import Foundation

/// Collects values from `@Sendable` async closures, such as the `sleep` a test hands to `ConnectRunner`.
actor Recorder<Value: Sendable> {
    private(set) var values: [Value] = []

    func add(_ value: Value) {
        values.append(value)
    }
}
