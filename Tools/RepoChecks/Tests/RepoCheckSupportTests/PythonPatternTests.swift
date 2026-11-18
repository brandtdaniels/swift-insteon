import Testing

@testable import RepoCheckSupport

@Suite("PythonPattern")
struct PythonPatternTests {
  @Test("search finds a match anywhere and match only at the start")
  func searchAndMatch() {
    let pattern = PythonPattern("b+")

    #expect(pattern.search("abb")?.group("x") == nil)
    #expect(pattern.search("abb") != nil)
    #expect(pattern.match("abb") == nil)
    #expect(pattern.match("bba") != nil)
  }

  @Test("returns named groups, and nil for one that took no part")
  func namedGroups() {
    let match = PythonPattern("^(?<head>a)(?<tail>b)?$").match("a")

    #expect(match?.group("head") == "a")
    #expect(match?.group("tail") == nil)
  }

  @Test("the space class holds Python's whitespace and not the zero width space")
  func spaceClass() {
    let pattern = PythonPattern("^\(PythonPattern.space)$")

    for value in [0x09, 0x0B, 0x1C, 0x20, 0x85, 0xA0, 0x2028, 0x3000] {
      #expect(pattern.match(String(Unicode.Scalar(UInt32(value))!)) != nil)
    }
    #expect(pattern.match("\u{200B}") == nil)
  }

  @Test("a dot matches a carriage return and a line separator, as Python's does")
  func dotMatchesAllButNewline() {
    let pattern = PythonPattern("^#.*$")

    #expect(pattern.match("# a\r b\u{2028}c\u{85}") != nil)
    #expect(pattern.match("# a\nb") == nil)
  }

  @Test("the word class holds letters, numbers and the underscore, and not marks")
  func wordClass() {
    let pattern = PythonPattern("^[\(PythonPattern.wordMembers)]+$")

    #expect(pattern.match("caf\u{E9}_9\u{2167}") != nil)
    #expect(pattern.match("e\u{301}") == nil)
  }
}
