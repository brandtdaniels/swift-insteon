import Testing

@testable import RepoCheckSupport

@Suite("PythonText")
struct PythonTextTests {
  @Test("splits on newlines only, keeping the empty last element")
  func splitsLines() {
    #expect(PythonText.splitLines("a\nb\n") == ["a", "b", ""])
    #expect(PythonText.splitLines("") == [""])
  }

  @Test("a carriage return is not a line break")
  func carriageReturnStays() {
    #expect(PythonText.splitLines("a\r\nb").count == 2)
    #expect(PythonText.splitLines("a\r\nb")[0].unicodeScalars.count == 2)
  }

  @Test("strips the whitespace Python's isspace names, including NEL and the separators")
  func stripsPythonWhitespace() {
    let padded = "\u{85}\u{A0}\u{2028}\u{1C}x \u{3000}"
    #expect(PythonText.strip(padded) == "x")
    #expect(PythonText.lstrip("\t\u{0B}\u{0C}y ") == "y ")
    #expect(PythonText.rstrip(" y\u{2029}") == " y")
  }

  @Test("does not strip a zero width space, which isspace rejects")
  func keepsZeroWidthSpace() {
    #expect(PythonText.strip("\u{200B}x").unicodeScalars.count == 2)
  }

  @Test("strips only the given characters from both ends")
  func stripsCharacters() {
    #expect(PythonText.strip("'\"a'b\"'", characters: "'\"") == "a'b")
    #expect(PythonText.rstrip("lint::", characters: ":") == "lint")
    #expect(PythonText.strip("''", characters: "'\"") == "")
  }

  @Test("compares by code point, not by canonical equivalence")
  func comparesByScalar() {
    #expect(PythonText.areEqual("\u{E9}", "e\u{301}") == false)
    #expect(PythonText.hasPrefix("#\u{301}", "#"))
    #expect(PythonText.length("e\u{301}") == 2)
  }

  @Test("orders by code point")
  func ordersByScalar() {
    #expect(PythonText.isOrdered("Z", before: "a"))
    #expect(PythonText.isOrdered("a", before: "\u{E9}"))
    #expect(PythonText.isOrdered("a", before: "ab"))
    #expect(PythonText.isOrdered("ab", before: "a") == false)
  }
}
