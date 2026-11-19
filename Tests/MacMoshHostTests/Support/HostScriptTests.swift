import Testing

/// The parent of every suite that runs the real script.
///
/// These tests block a thread while they wait for the script and for tmux. Swift Testing runs suites
/// side by side on a small pool of threads (three on a CI runner), so three blocked suites at once
/// starve every other test in the run and make the time-limit tests in MacMoshKitTests fail.
/// `.serialized` on this parent keeps it to one blocked test at a time. A new suite that uses
/// `HostHarness` goes inside it: `extension HostScriptTests { @Suite struct MyTests { ... } }`.
@Suite(.serialized) enum HostScriptTests {}
