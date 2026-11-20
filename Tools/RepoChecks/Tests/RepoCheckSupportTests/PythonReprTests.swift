import Testing

@testable import RepoCheckSupport

@Suite("PythonRepr")
struct PythonReprTests {
  @Test("uses single quotes")
  func singleQuotes() {
    #expect(PythonRepr.of("INSTEON") == "'INSTEON'")
  }

  @Test("uses double quotes for an apostrophe and no double quote")
  func doubleQuotesForApostrophe() {
    #expect(PythonRepr.of("Developer's guide") == "\"Developer's guide\"")
  }

  @Test("escapes the single quote when both quotes appear")
  func escapesWhenBothAppear() {
    #expect(PythonRepr.of("it's \"x\"") == #"'it\'s "x"'"#)
  }

  @Test("escapes the backslash, tab, newline and return")
  func escapesBackslashAndWhitespace() {
    #expect(PythonRepr.of("a\\b\t\n\r") == #"'a\\b\t\n\r'"#)
  }

  @Test("escapes controls and non-printable characters by width")
  func escapesNonPrintable() {
    #expect(PythonRepr.of("\u{00}\u{7F}\u{85}") == "'\\x00\\x7f\\x85'")
    #expect(PythonRepr.of("\u{200B}\u{2028}") == "'\\u200b\\u2028'")
    #expect(PythonRepr.of("\u{E0001}") == "'\\U000e0001'")
  }

  @Test("keeps printable non-ASCII text and the space")
  func keepsPrintable() {
    #expect(PythonRepr.of("caf\u{E9} \u{1F600}") == "'caf\u{E9} \u{1F600}'")
  }

  @Test("escapes a no-break space, which is a separator")
  func escapesNoBreakSpace() {
    #expect(PythonRepr.of("\u{A0}") == #"'\xa0'"#)
  }
}
