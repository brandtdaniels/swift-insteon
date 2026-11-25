import Foundation
import Testing

@testable import RepoCheckSupport

@Suite("TextFile")
struct TextFileTests {
  @Test("turns CRLF and a lone CR into LF")
  func normalizesNewlines() {
    #expect(TextFile.normalizingNewlines("a\r\nb\rc\nd\r\r\ne") == "a\nb\nc\nd\n\ne")
  }

  @Test("leaves text without a CR as it is")
  func leavesLF() {
    #expect(TextFile.normalizingNewlines("a\n\nb") == "a\n\nb")
  }

  @Test("reads a file with its newlines normalized and its byte order mark kept")
  func readsFile() throws {
    let directory = try ScratchDirectory()
    try directory.write(Data([0xEF, 0xBB, 0xBF] + Array("a\r\nb".utf8)), to: "x.txt")

    let text = try TextFile.read(directory.url(for: "x.txt"))

    #expect(text.unicodeScalars.map(\.value) == [0xFEFF, 0x61, 0x0A, 0x62])
  }

  @Test("refuses bytes that aren't UTF-8")
  func refusesInvalidUTF8() throws {
    let directory = try ScratchDirectory()
    try directory.write(Data([0x61, 0xFF]), to: "x.txt")

    #expect(throws: TextFileError.self) {
      try TextFile.read(directory.url(for: "x.txt"))
    }
  }

  @Test("refuses a path that isn't a readable file")
  func refusesMissingFile() throws {
    let directory = try ScratchDirectory()

    #expect(throws: TextFileError.self) {
      try TextFile.read(directory.url(for: "missing.txt"))
    }
  }
}
