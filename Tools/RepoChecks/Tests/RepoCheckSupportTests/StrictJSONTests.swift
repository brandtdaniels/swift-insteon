import Testing

@testable import RepoCheckSupport

@Suite("StrictJSON")
struct StrictJSONTests {
  private func accepts(_ text: String) -> Bool {
    (try? StrictJSON.validate(Array(text.utf8), named: "x.json")) != nil
  }

  @Test("accepts valid JSON, with the whitespace JSON allows around it")
  func acceptsValid() {
    #expect(accepts(#"{"a": [1, 2.5e-3, -0, true, false, null, "sé\n"], "b": {}}"#))
    #expect(accepts(" \t\r\n[]\n"))
    #expect(accepts("1"))
    #expect(accepts(#""text""#))
  }

  @Test("refuses a byte order mark, as Python's json.loads does")
  func refusesByteOrderMark() {
    #expect(!accepts("\u{FEFF}{}"))
  }

  @Test("refuses a trailing comma in an array and in an object")
  func refusesTrailingComma() {
    #expect(!accepts("[1,2,]"))
    #expect(!accepts(#"{"a": 1,}"#))
    #expect(!accepts(#"{"a": [1,2,],"b":1}"#))
  }

  @Test("refuses truncated and empty text")
  func refusesTruncatedAndEmpty() {
    #expect(!accepts(""))
    #expect(!accepts("   "))
    #expect(!accepts(#"{"a": [1, 2"#))
    #expect(!accepts(#"{"a": "unterminated"#))
    #expect(!accepts(#"{"a""#))
  }

  @Test("refuses comments, single quotes, bare keys, extra data and leading zeros")
  func refusesOtherForms() {
    #expect(!accepts("// c\n{}"))
    #expect(!accepts("{} // c"))
    #expect(!accepts("{'a': 1}"))
    #expect(!accepts("{a: 1}"))
    #expect(!accepts("{} {}"))
    #expect(!accepts("01"))
    #expect(!accepts("1."))
    #expect(!accepts(".5"))
    #expect(!accepts("+1"))
    #expect(!accepts("\u{A0}{}"))
  }

  @Test("refuses a raw control character or a bad escape in a string")
  func refusesBadStrings() {
    #expect(!accepts("\"a\nb\""))
    #expect(!accepts("\"a\tb\""))
    #expect(!accepts(#""\x41""#))
    #expect(!accepts(#""\u12G4""#))
  }

  @Test("accepts NaN and the infinities, which Python reads")
  func acceptsPythonConstants() {
    #expect(accepts("[NaN, Infinity, -Infinity]"))
    #expect(!accepts("[nan]"))
  }

  @Test("refuses bytes that aren't UTF-8")
  func refusesInvalidUTF8() {
    #expect((try? StrictJSON.validate([0x22, 0xFF, 0x22], named: "x.json")) == nil)
  }

  @Test("names the file in a one-line message")
  func names() {
    do {
      try StrictJSON.validate(Array("[1,]".utf8), named: "catalog.json")
      Issue.record("expected a failure")
    } catch let failure as CheckFailure {
      #expect(failure.message.hasPrefix("catalog.json: isn't valid JSON"))
      #expect(!failure.message.contains("\n"))
    } catch {
      Issue.record("\(error)")
    }
  }
}
