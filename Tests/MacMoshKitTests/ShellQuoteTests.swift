import Testing
@testable import MacMoshKit

@Suite struct ShellQuoteTests {
    @Test func plainTextIsLeftBare() {
        #expect(ShellQuote.posix("plain") == "plain")
        #expect(ShellQuote.posix("a/b-c.d:e,f=g+h%i@j") == "a/b-c.d:e,f=g+h%i@j")
    }

    @Test func emptyTextBecomesTwoQuotes() {
        #expect(ShellQuote.posix("") == "''")
    }

    @Test func singleQuoteIsClosedEscapedAndReopened() {
        #expect(ShellQuote.posix("it's") == #"'it'\''s'"#)
    }

    @Test func spacesAndShellCharactersAreQuoted() {
        #expect(ShellQuote.posix("a b") == "'a b'")
        #expect(ShellQuote.posix("$HOME") == "'$HOME'")
        #expect(ShellQuote.posix("é") == "'é'")
        #expect(ShellQuote.posix("~") == "'~'")
    }

    @Test func joinQuotesEachArgument() {
        #expect(ShellQuote.join(["a b", "c"]) == "'a b' c")
        #expect(ShellQuote.join([]) == "")
    }
}
