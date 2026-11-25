import Foundation
import Testing
@testable import MacMoshKit

/// The app's copy of the workhorse script's rule for a window's name (issue 144), and the app's one extra rule:
/// no name that starts with `-`, so a name is never sent where the script reads `--auto` looking like an option.
@Suite struct WindowNameRuleTests {
    /// The names `WindowNameTests` (MacMoshHostTests) sets on a real tmux: the script takes every one.
    static let scriptAccepts = [
        "build logs", "v1.2", "a-b_c", ".", "-n", "--x", "A b  C", "notes 2.0 - draft_1",
        String(repeating: "x", count: 32), "abcdefghijklmnop qrstuvwxyz.-_09",
    ]

    /// The names `WindowNameTests` sees the script refuse, with exit code 2 and nothing changed.
    static let scriptRefuses = [
        "", String(repeating: "x", count: 33), " lead", "trail ", " ", "a\tb", "a\nb", "a\n", "a#b", "#{pane_pid}",
        "it's", "say \"hi\"", "a;b", "a;", "a/b", "caf\u{e9}", "na\u{ef}ve", "\u{3b1}", "a$b", "a`b`", "a\\b",
        "a:b", "a,b", "a*b", "a\u{a0}b",
    ]

    @Test func theScriptsRuleTakesAndRefusesWhatTheScriptDoes() {
        for name in Self.scriptAccepts { #expect(WindowName.keepsScriptRule(name), "\(name.debugDescription)") }
        for name in Self.scriptRefuses { #expect(!WindowName.keepsScriptRule(name), "\(name.debugDescription)") }
    }

    /// The script's rule is still the one these lists were written for: the same characters, the same ends and
    /// the same length, word for word in the script the app installs. A change there fails here until someone
    /// changes the app's copy too.
    @Test func theScriptStillHasTheRuleTheseListsWereWrittenFor() {
        let script = HostScript.source
        #expect(script.contains(#"'' | ' '* | *' ' | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\ ._-]*) return 1 ;;"#))
        #expect(script.contains(#"[ "${#1}" -le 32 ]"#))
        #expect(script.contains("MM_WINDOW_NAME_RULE=\"a window name is 1 to 32 characters, each a letter, a digit, a space, -, _ or a full stop, and it can't start or end with a space\""))
        #expect(WindowName.maxLength == 32)
    }

    @Test func theAppTakesWhatTheScriptTakesButANameStartingWithADash() {
        for name in Self.scriptAccepts {
            let taken = WindowName(name)
            if name.hasPrefix("-") {
                #expect(taken == nil, "\(name)")
            } else {
                #expect(taken?.value == name, "\(name)")
            }
        }
        for name in Self.scriptRefuses { #expect(WindowName(name) == nil, "\(name.debugDescription)") }
        for name in ["--auto", "-", "-front end", "--", "- a"] { #expect(WindowName(name) == nil, "\(name)") }
        // A dash anywhere else is fine.
        #expect(WindowName("front-end")?.value == "front-end")
        #expect(WindowName("a -")?.value == "a -")
    }

    /// Nothing is trimmed or changed: the name is the text as typed.
    @Test func theNameIsTheTextAsTyped() {
        #expect(WindowName("front end")?.value == "front end")
        #expect(WindowName("A b  C")?.value == "A b  C")
        #expect(WindowName("v1.2")?.value == "v1.2")
    }

    @Test func oneSentenceStatesTheRule() {
        #expect(WindowName.rule
                == "A window name is 1 to 32 letters, digits, spaces, -, _ and full stops. It can't start with a space or -, or end with a space.")
    }

    /// Why a name can't be used, one plain sentence each; nil for a name that can.
    @Test func eachRefusalSaysWhy() {
        #expect(WindowName.problem("front end") == nil)
        #expect(WindowName.problem("") == "Type a name.")
        #expect(WindowName.problem(String(repeating: "x", count: 33)) == "A window name is 32 characters at most.")
        #expect(WindowName.problem(" lead") == "A window name can't start or end with a space.")
        #expect(WindowName.problem("trail ") == "A window name can't start or end with a space.")
        #expect(WindowName.problem(" ") == "A window name can't start or end with a space.")
        #expect(WindowName.problem("--auto") == "A window name can't start with -.")
        #expect(WindowName.problem("-n") == "A window name can't start with -.")
        for name in ["a#b", "it's", "caf\u{e9}", "a\tb", "a/b", "a\u{a0}b"] {
            #expect(WindowName.problem(name) == "A window name uses letters, digits, spaces, -, _ and full stops only.",
                    "\(name.debugDescription)")
        }
        // Every refused name has a sentence, and every accepted one none.
        for name in Self.scriptRefuses + ["--auto", "-n"] { #expect(WindowName.problem(name) != nil, "\(name.debugDescription)") }
        for name in Self.scriptAccepts where !name.hasPrefix("-") { #expect(WindowName.problem(name) == nil, "\(name)") }
    }
}
